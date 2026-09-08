import Foundation

struct PullRequest: Equatable {
    let number: Int
    let title: String
    let state: String          // OPEN, MERGED, CLOSED
    let reviewDecision: String // APPROVED, CHANGES_REQUESTED, REVIEW_REQUIRED or empty
    let isDraft: Bool
    let url: String

    var summary: String {
        var s = "PR #\(number) " + (isDraft ? "draft" : state.lowercased())
        switch reviewDecision {
        case "APPROVED": s += " · approved"
        case "CHANGES_REQUESTED": s += " · changes requested"
        case "REVIEW_REQUIRED": s += " · awaiting review"
        default: break
        }
        return s
    }
}

struct ReleasePR: Equatable {
    let number: Int
    let title: String
    let base: String     // staging or production
    let head: String
    let state: String
    let url: String
    let labels: [String]
    var isProduction: Bool { base == "production" || base == "main" || base == "master" }
    var untested: Bool { labels.contains { $0.lowercased().contains("untested") } }
}

struct CrewPR: Equatable {
    let number: Int
    let title: String
    let author: String
    let branch: String
    let state: String
    let createdAt: Date
    let mergedAt: Date?
    let url: String
    let commits: [(Date, String)]
    let reviews: [(Date, String, String)]

    static func == (a: CrewPR, b: CrewPR) -> Bool {
        a.number == b.number && a.state == b.state && a.commits.count == b.commits.count && a.reviews.count == b.reviews.count
    }
}

/// Resolves pull requests for task branches with the gh CLI, off the main thread.
final class GitHubResolver {
    private var crew: [String: ([CrewPR], Date)] = [:]
    private var me: String?

    func crewPRs(repoRoot: String) -> [CrewPR]? {
        lock.lock(); defer { lock.unlock() }
        return crew[repoRoot]?.0
    }

    /// Teammates' pull requests touched in the last day, with their commits and reviews. Every 10 minutes.
    func refreshCrew(repoRoot: String, within: TimeInterval) {
        lock.lock()
        if let (_, at) = crew[repoRoot], Date().timeIntervalSince(at) < 600 { lock.unlock(); return }
        if inFlight.contains("w:" + repoRoot) { lock.unlock(); return }
        inFlight.insert("w:" + repoRoot)
        lock.unlock()
        queue.async { [self] in
            if me == nil, let out = run(["gh", "api", "user", "--jq", ".login"], cwd: repoRoot),
               let login = String(data: out, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !login.isEmpty {
                lock.lock(); me = login; lock.unlock()
            }
            let iso = ISO8601DateFormatter()
            let since = Date().addingTimeInterval(-within)
            var found: [CrewPR] = []
            if let out = run(["gh", "pr", "list", "--state", "all", "--limit", "40",
                              "--json", "number,title,author,headRefName,state,createdAt,mergedAt,updatedAt,url"], cwd: repoRoot),
               let arr = try? JSONSerialization.jsonObject(with: out) as? [[String: Any]] {
                for o in arr {
                    let authorObj = o["author"] as? [String: Any]
                    let author = authorObj?["login"] as? String ?? "?"
                    let isBot = (authorObj?["is_bot"] as? Bool ?? false) || author.lowercased().contains("dependabot") || author.contains("[bot]")
                    let head = o["headRefName"] as? String ?? ""
                    guard author != me, !isBot, !["develop", "staging", "main", "master"].contains(head),
                          let updated = (o["updatedAt"] as? String).flatMap(iso.date(from:)), updated > since,
                          let number = o["number"] as? Int else { continue }
                    var commits: [(Date, String)] = [], reviews: [(Date, String, String)] = []
                    if let v = run(["gh", "pr", "view", "\(number)", "--json", "commits,reviews"], cwd: repoRoot),
                       let d = try? JSONSerialization.jsonObject(with: v) as? [String: Any] {
                        for c in d["commits"] as? [[String: Any]] ?? [] {
                            guard let t = (c["authoredDate"] as? String).flatMap(iso.date(from:)) else { continue }
                            let who = (c["authors"] as? [[String: Any]])?.first?["login"] as? String ?? author
                            commits.append((t, who.isEmpty ? author : who))
                        }
                        for r in d["reviews"] as? [[String: Any]] ?? [] {
                            guard let t = (r["submittedAt"] as? String).flatMap(iso.date(from:)) else { continue }
                            reviews.append((t, (r["author"] as? [String: Any])?["login"] as? String ?? "?", r["state"] as? String ?? ""))
                        }
                    }
                    found.append(CrewPR(number: number, title: o["title"] as? String ?? "", author: author, branch: head,
                                        state: o["state"] as? String ?? "", createdAt: (o["createdAt"] as? String).flatMap(iso.date(from:)) ?? updated,
                                        mergedAt: (o["mergedAt"] as? String).flatMap(iso.date(from:)), url: o["url"] as? String ?? "",
                                        commits: commits, reviews: reviews))
                    if found.count >= 10 { break }
                }
            }
            lock.lock()
            let changed = crew[repoRoot]?.0 != found
            crew[repoRoot] = (found, Date())
            inFlight.remove("w:" + repoRoot)
            lock.unlock()
            if changed { DispatchQueue.main.async { self.onUpdate?() } }
        }
    }

    private var releases: [String: ([ReleasePR], Date)] = [:]
    private var pendingLaunches: [(repoRoot: String, pr: ReleasePR)] = []
    private var stateChanges: [(branch: String, pr: PullRequest)] = []

    /// Open release pull requests for a repository, or nil if not fetched yet.
    func openReleases(repoRoot: String) -> [ReleasePR]? {
        lock.lock(); defer { lock.unlock() }
        return releases[repoRoot]?.0.filter { $0.state == "OPEN" }
    }

    /// Release pull requests that merged since the last poll, each returned once.
    func takeLaunches() -> [(repoRoot: String, pr: ReleasePR)] {
        lock.lock(); defer { lock.unlock() }
        let out = pendingLaunches; pendingLaunches = []; return out
    }

    /// Task pull requests whose state changed since the last poll, each returned once.
    func takeStateChanges() -> [(branch: String, pr: PullRequest)] {
        lock.lock(); defer { lock.unlock() }
        let out = stateChanges; stateChanges = []; return out
    }

    /// Forgets cache ages for one repository so its next refresh hits GitHub again.
    func invalidate(repoRoot: String) {
        lock.lock(); defer { lock.unlock() }
        let old = Date.distantPast
        for k in pulls.keys where k.hasPrefix(repoRoot + "@") { pulls[k] = (pulls[k]!.0, old) }
        if let r = releases[repoRoot] { releases[repoRoot] = (r.0, old) }
    }

    /// Forgets all cache ages so the next refresh calls hit GitHub again.
    func invalidate() {
        lock.lock(); defer { lock.unlock() }
        let old = Date.distantPast
        pulls = pulls.mapValues { ($0.0, old) }
        commits = commits.mapValues { ($0.0, old) }
        releases = releases.mapValues { ($0.0, old) }
    }

    func refreshReleases(repoRoot: String) {
        lock.lock()
        if let (_, at) = releases[repoRoot], Date().timeIntervalSince(at) < 300 { lock.unlock(); return }
        if inFlight.contains("r:" + repoRoot) { lock.unlock(); return }
        inFlight.insert("r:" + repoRoot)
        lock.unlock()
        queue.async { [self] in
            var found: [ReleasePR] = []
            for base in ["staging", "production"] {
                guard let out = run(["gh", "pr", "list", "--base", base, "--state", "all", "--limit", "5",
                                     "--json", "number,title,baseRefName,headRefName,state,url,labels"], cwd: repoRoot),
                      let arr = try? JSONSerialization.jsonObject(with: out) as? [[String: Any]] else { continue }
                for o in arr {
                    let head = o["headRefName"] as? String ?? ""
                    guard ["develop", "staging", "main", "master"].contains(head) else { continue }
                    let labels = (o["labels"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
                    found.append(ReleasePR(number: o["number"] as? Int ?? 0, title: o["title"] as? String ?? "", base: base,
                                           head: head, state: o["state"] as? String ?? "", url: o["url"] as? String ?? "", labels: labels))
                }
            }
            lock.lock()
            let previous = releases[repoRoot]?.0 ?? []
            for pr in found where pr.state == "MERGED" && previous.contains(where: { $0.number == pr.number && $0.state == "OPEN" }) {
                pendingLaunches.append((repoRoot, pr))
            }
            let changed = previous != found
            releases[repoRoot] = (found, Date())
            inFlight.remove("r:" + repoRoot)
            lock.unlock()
            if changed { DispatchQueue.main.async { self.onUpdate?() } }
        }
    }

    private let queue = DispatchQueue(label: "rymdkapsel.github", qos: .utility, attributes: .concurrent)
    private var pulls: [String: (PullRequest?, Date)] = [:]
    private var commits: [String: (Int, Date)] = [:]
    private var owners: [String: String] = [:]
    private var inFlight = Set<String>()
    private let lock = NSLock()
    var onUpdate: (() -> Void)?

    func pull(branch: String, repoRoot: String) -> PullRequest? {
        lock.lock(); defer { lock.unlock() }
        return pulls[repoRoot + "@" + branch]?.0
    }

    /// Commits on the worktree's branch that are not on the default branch, or nil if unknown yet.
    func commitsAhead(worktree: String) -> Int? {
        lock.lock(); defer { lock.unlock() }
        return commits[worktree]?.0
    }

    func refreshCommits(worktree: String) {
        lock.lock()
        if let (_, at) = commits[worktree], Date().timeIntervalSince(at) < 60 { lock.unlock(); return }
        if inFlight.contains("c:" + worktree) { lock.unlock(); return }
        inFlight.insert("c:" + worktree)
        lock.unlock()
        queue.async { [self] in
            var base = "origin/main"
            if let out = run(["git", "symbolic-ref", "--short", "refs/remotes/origin/HEAD"], cwd: worktree),
               let name = String(data: out, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
                base = name
            } else if run(["git", "rev-parse", "--verify", "origin/main"], cwd: worktree) == nil,
                      run(["git", "rev-parse", "--verify", "origin/master"], cwd: worktree) != nil {
                base = "origin/master"
            }
            var n = 0
            if let out = run(["git", "rev-list", "--count", "\(base)..HEAD"], cwd: worktree),
               let text = String(data: out, encoding: .utf8), let v = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)) {
                n = v
            }
            lock.lock()
            let changed = commits[worktree]?.0 != n
            commits[worktree] = (n, Date())
            inFlight.remove("c:" + worktree)
            lock.unlock()
            if changed { DispatchQueue.main.async { self.onUpdate?() } }
        }
    }

    func nameWithOwner(repoRoot: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return owners[repoRoot]
    }

    /// Refreshes stale entries; each branch at most once every two minutes.
    func refresh(branch: String, repoRoot: String) {
        let key = repoRoot + "@" + branch
        lock.lock()
        if let (_, at) = pulls[key], Date().timeIntervalSince(at) < 300 { lock.unlock(); return }
        if inFlight.contains(key) { lock.unlock(); return }
        inFlight.insert(key)
        lock.unlock()

        queue.async { [self] in
            if nameWithOwner(repoRoot: repoRoot) == nil,
               let out = run(["gh", "repo", "view", "--json", "nameWithOwner"], cwd: repoRoot),
               let obj = try? JSONSerialization.jsonObject(with: out) as? [String: Any],
               let n = obj["nameWithOwner"] as? String {
                lock.lock(); owners[repoRoot] = n; lock.unlock()
            }
            var pr: PullRequest?
            func parse(_ o: [String: Any]) -> PullRequest {
                PullRequest(number: o["number"] as? Int ?? 0, title: o["title"] as? String ?? "",
                            state: o["state"] as? String ?? "", reviewDecision: o["reviewDecision"] as? String ?? "",
                            isDraft: o["isDraft"] as? Bool ?? false, url: o["url"] as? String ?? "")
            }
            let fields = "number,title,state,reviewDecision,isDraft,url"
            if let out = run(["gh", "pr", "view", branch, "--json", fields], cwd: repoRoot),
               let o = try? JSONSerialization.jsonObject(with: out) as? [String: Any] {
                pr = parse(o)
            } else if let out = run(["gh", "pr", "list", "--head", branch, "--state", "all", "--limit", "1", "--json", fields], cwd: repoRoot),
                      let arr = try? JSONSerialization.jsonObject(with: out) as? [[String: Any]], let o = arr.first {
                pr = parse(o)
            }
            lock.lock()
            let changed = pulls[key]?.0 != pr
            if changed, let pr, pulls[key] != nil { stateChanges.append((branch, pr)) }
            pulls[key] = (pr, Date())
            inFlight.remove(key)
            lock.unlock()
            if changed { DispatchQueue.main.async { self.onUpdate?() } }
        }
    }

    private func run(_ args: [String], cwd: String) -> Data? {
        guard FileManager.default.fileExists(atPath: cwd) else { return nil }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = args
        p.currentDirectoryURL = URL(fileURLWithPath: cwd)
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (env["PATH"] ?? "")
        p.environment = env
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return p.terminationStatus == 0 ? data : nil
    }
}
