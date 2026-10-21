import Foundation

final class GitSource: Intake {
    let name = "git"
    private weak var github: GitHubResolver?
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "rumkapsel.git", qos: .utility, attributes: .concurrent)
    private var watchers: [String: GitWatch] = [:]
    private var commits: [String: (Int, Date)] = [:]
    private var pushed: [String: Bool] = [:]
    private var dirty: [String: Int] = [:]
    private var checkedOut: [String: String] = [:]
    private var counts: [String: GitHubResolver.Cargo] = [:]
    private var fetchedAt: [String: Date] = [:]
    private var reading = Set<String>()
    private var rerun = Set<String>()

    init(github: GitHubResolver) { self.github = github }

    func checks() -> [Watch.Check] { [] }
    func reports() -> [Report] { [] }

    func watch(_ roots: [String]) {
        lock.lock()
        for gone in watchers.keys where !roots.contains(gone) { watchers[gone] = nil }
        let fresh = roots.filter { watchers[$0] == nil }
        lock.unlock()
        for root in fresh {
            let w = GitWatch(root: root) { [weak self] change in self?.heard(change, repoRoot: root) }
            lock.lock(); watchers[root] = w; lock.unlock()
        }
    }

    func commitsAhead(worktree: String) -> Int? {
        lock.lock(); defer { lock.unlock() }
        return commits[worktree]?.0
    }

    func dirtyFiles(worktree: String) -> Int {
        lock.lock(); defer { lock.unlock() }
        return dirty[worktree] ?? 0
    }

    func currentBranch(worktree: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return checkedOut[worktree]
    }

    func branchPushed(worktree: String) -> Bool? {
        lock.lock(); defer { lock.unlock() }
        return pushed[worktree]
    }

    func counted(repoRoot: String) -> GitHubResolver.Cargo? {
        lock.lock(); defer { lock.unlock() }
        return counts[repoRoot]
    }

    func isBusy(repoRoot: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return reading.contains { $0.hasPrefix(repoRoot) }
    }

    func fetched(_ path: String) { lock.lock(); fetchedAt[path] = Date(); lock.unlock() }

    func invalidate() {
        lock.lock(); commits = commits.mapValues { ($0.0, .distantPast) }; lock.unlock()
    }

    private func heard(_ change: GitChange, repoRoot: String) {
        guard let github else { return }
        let now = Date()
        lock.lock()
        let echo = now.timeIntervalSince(fetchedAt[repoRoot] ?? .distantPast) < 2
        let links = commits.keys.compactMap { w in GitWatch.link(ofWorktree: w).flatMap { $0.root == repoRoot ? (w, $0.name) : nil } }
        let hit = links.filter { change.local || change.remote || ($0.1.map(change.worktrees.contains) ?? false) }.map(\.0)
        for w in hit { if let c = commits[w] { commits[w] = (c.0, .distantPast) }; if reading.contains(w) { rerun.insert(w) } }
        let expect = change.remote && !echo ? links.compactMap { checkedOut[$0.0] } : []
        lock.unlock()
        if change.remote, !echo { github.watch.ring(repoRoot: repoRoot) }
        for b in expect { github.pulls.expect(branch: b, repoRoot: repoRoot) }
        github.trace("git \(repoRoot): \(change.local ? "commit or checkout " : "")\(change.worktrees.isEmpty ? "" : "worktree \(change.worktrees.sorted()) ")\(change.remote ? "remote refs " : "")\(change.tags ? "tags " : "")\(echo ? "(our fetch) " : "")→ \(hit.count) checkout(s)")
        for w in hit { refreshCommits(worktree: w) }
        if change.tags, !echo, github.pipeline(repoRoot: repoRoot).shipsOnTag { github.pulls.follow(FollowUps.Due(releasing: true), repoRoot: repoRoot) }
    }

    func refreshCommits(worktree: String) {
        guard let github, !github.frozen else { return }
        lock.lock()
        if let (_, at) = commits[worktree], Date().timeIntervalSince(at) < 60 { lock.unlock(); return }
        if reading.contains(worktree) { lock.unlock(); return }
        reading.insert(worktree)
        lock.unlock()
        queue.async { [self] in
            let trunk = GitWatch.link(ofWorktree: worktree).map { github.detectedPipeline(repoRoot: $0.root).trunk } ?? ""
            let candidates = (trunk.isEmpty ? ["origin/HEAD"] : ["origin/" + trunk, "origin/HEAD"]) + Pipeline.trunkNames.map { "origin/" + $0 }
            let base = candidates.first { github.run(["git", "rev-parse", "--verify", "--quiet", $0], cwd: worktree) != nil } ?? "origin/HEAD"
            var isPushed = false
            var onBranch: String?
            if let out = github.run(["git", "branch", "--show-current"], cwd: worktree),
               let branch = String(data: out, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !branch.isEmpty {
                isPushed = github.run(["git", "rev-parse", "--verify", "--quiet", "origin/" + branch], cwd: worktree) != nil
                onBranch = branch
            }
            var changed = 0
            if let out = github.run(["git", "status", "--porcelain"], cwd: worktree), let text = String(data: out, encoding: .utf8) {
                changed = text.split(separator: "\n").count
            }
            var n = 0
            if let out = github.run(["git", "rev-list", "--count", "\(base)..HEAD"], cwd: worktree),
               let text = String(data: out, encoding: .utf8), let v = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)) {
                n = v
            }
            lock.lock()
            let changedResult = commits[worktree]?.0 != n || pushed[worktree] != isPushed || dirty[worktree] != changed
            commits[worktree] = (n, Date())
            pushed[worktree] = isPushed
            dirty[worktree] = changed
            checkedOut[worktree] = onBranch
            lock.unlock()
            if landed(worktree) {
                lock.lock(); commits[worktree] = (n, .distantPast); lock.unlock()
                refreshCommits(worktree: worktree)
            }
            if changedResult { DispatchQueue.main.async { github.onUpdate?() } }
        }
    }

    func count(repoRoot: String, pipe: Pipeline, releases found: [ReleasePR], began: Date) -> Bool {
        guard let github else { return false }
        let trunk = pipe.trunk, stagingBranch = pipe.staging, productionBranch = pipe.production
        let bases = pipe.remote ? [stagingBranch, productionBranch].filter { !$0.isEmpty } : []
        let iso = ISO8601DateFormatter()
        let lastStaging = found.filter { $0.base == stagingBranch && $0.state == "MERGED" }.compactMap(\.mergedAt).max()
        let lastProduction = found.filter { $0.base == productionBranch && $0.state == "MERGED" }.compactMap(\.mergedAt).max()
        var newCargo = GitHubResolver.Cargo(storage: 0, deck: 0, storageNumbers: [], deckNumbers: [])
        let hasPipeline = (!bases.isEmpty && (lastStaging != nil || lastProduction != nil)) || pipe.shipsOnTag
        let floor = Date().addingTimeInterval(-30 * 24 * 3600)
        func prNumbers(_ range: String) -> [Int]? {
            guard let out = github.run(["git", "log", "--format=%s", "--no-merges", "--max-count=300", range], cwd: repoRoot),
                  let text = String(data: out, encoding: .utf8) else { return nil }
            var found: [Int] = []
            for line in text.split(separator: "\n") {
                if let m = line.firstMatch(of: #/\(#(\d+)\)\s*$/#), let n = Int(m.1) { found.append(n) }
            }
            if let out = github.run(["git", "log", "--format=%s", "--merges", "--max-count=300", range], cwd: repoRoot), let t = String(data: out, encoding: .utf8) {
                for line in t.split(separator: "\n") {
                    if let m = line.firstMatch(of: #/Merge pull request #(\d+)/#), let n = Int(m.1) { found.append(n) }
                }
            }
            return Array(Set(found)).sorted(by: >)
        }
        var exact = false
        if hasPipeline, !stagingBranch.isEmpty, !productionBranch.isEmpty {
            _ = github.run(["git", "fetch", "-q", "origin", trunk, stagingBranch, productionBranch], cwd: repoRoot)
            if let deck = prNumbers("origin/\(productionBranch)..origin/\(stagingBranch)"),
               let storage = prNumbers("origin/\(stagingBranch)..origin/\(trunk)") {
                let releaseNumbers = Set(found.map(\.number))
                newCargo.deckNumbers = deck.filter { !releaseNumbers.contains($0) }
                newCargo.storageNumbers = storage.filter { !releaseNumbers.contains($0) }
                newCargo.deck = newCargo.deckNumbers.count
                newCargo.storage = newCargo.storageNumbers.count
                exact = true
            }
        }
        if hasPipeline, !exact, pipe.shipsOnTag, let tag = found.first(where: \.tag)?.head {
            _ = github.run(["git", "fetch", "-q", "origin", trunk], cwd: repoRoot)
            if let storage = prNumbers("\(tag)..origin/\(trunk)") {
                newCargo.storageNumbers = storage
                newCargo.storage = storage.count
                exact = true
            }
        }
        if hasPipeline, !exact, stagingBranch.isEmpty, !productionBranch.isEmpty {
            _ = github.run(["git", "fetch", "-q", "origin", trunk, productionBranch], cwd: repoRoot)
            if let storage = prNumbers("origin/\(productionBranch)..origin/\(trunk)") {
                let releaseNumbers = Set(found.map(\.number))
                newCargo.storageNumbers = storage.filter { !releaseNumbers.contains($0) }
                newCargo.storage = newCargo.storageNumbers.count
                exact = true
            }
        }
        var merged: [Int: String] = [:]
        if hasPipeline, !exact, let out = github.run(["gh", "pr", "list", "--base", trunk, "--state", "merged", "--limit", "80", "--json", "number,mergedAt,author"], cwd: repoRoot),
           let arr = try? JSONSerialization.jsonObject(with: out) as? [[String: Any]] {
            for o in arr {
                guard let m = (o["mergedAt"] as? String).flatMap(iso.date(from:)), let n = o["number"] as? Int else { continue }
                if let login = (o["author"] as? [String: Any])?["login"] as? String { merged[n] = login }
                if m < floor { continue }
                if let lp = lastProduction, m <= lp { continue }
                if stagingBranch.isEmpty || lastStaging == nil || m > lastStaging! { newCargo.storage += 1; newCargo.storageNumbers.append(n) }
                else { newCargo.deck += 1; newCargo.deckNumbers.append(n) }
            }
        }
        github.note(authors: merged, repoRoot: repoRoot)
        lock.lock()
        let changed = counts[repoRoot] != newCargo
        newCargo.exact = exact
        newCargo.at = began
        counts[repoRoot] = newCargo
        lock.unlock()
        return changed
    }

    private func landed(_ worktree: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        reading.remove(worktree)
        return rerun.remove(worktree) != nil
    }

    func reset() {
        lock.lock(); counts = [:]; commits = [:]; pushed = [:]; dirty = [:]; lock.unlock()
    }

    func inject(cargo c: GitHubResolver.Cargo, for repoRoot: String) { lock.lock(); counts[repoRoot] = c; lock.unlock() }

    func inject(commits n: Int, pushed isPushed: Bool, dirty files: Int, worktree: String) {
        lock.lock(); commits[worktree] = (n, Date()); pushed[worktree] = isPushed; dirty[worktree] = files; lock.unlock()
    }
}
