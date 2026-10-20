import Foundation

struct DeployRun: Equatable {
    let id: Int
    let workflow: String
    let branch: String
    let status: String
    let conclusion: String
    let startedAt: Date?
    let updatedAt: Date?
    let title: String

    var running: Bool { status != "completed" }
    var outcome: DeployOutcome? {
        guard !running else { return nil }
        switch conclusion {
        case "success": return .live
        case "cancelled", "skipped": return .cancelled
        default: return .failed
        }
    }
    var took: TimeInterval? {
        guard !running, let s = startedAt, let u = updatedAt, u > s else { return nil }
        return u.timeIntervalSince(s)
    }
    var release: String {
        title.range(of: "#[0-9]+", options: .regularExpression).map { String(title[$0]) } ?? ""
    }

    init?(json o: [String: Any]) {
        guard let id = o["databaseId"] as? Int else { return nil }
        let iso = ISO8601DateFormatter()
        self.init(id: id, workflow: o["workflowName"] as? String ?? "", branch: o["headBranch"] as? String ?? "",
                  status: o["status"] as? String ?? "", conclusion: o["conclusion"] as? String ?? "",
                  startedAt: (o["startedAt"] as? String).flatMap(iso.date(from:)),
                  updatedAt: (o["updatedAt"] as? String).flatMap(iso.date(from:)), title: o["displayTitle"] as? String ?? "")
    }

    init?(api o: [String: Any]) {
        guard let id = o["id"] as? Int else { return nil }
        let iso = ISO8601DateFormatter()
        self.init(id: id, workflow: o["name"] as? String ?? "", branch: o["head_branch"] as? String ?? "",
                  status: o["status"] as? String ?? "", conclusion: o["conclusion"] as? String ?? "",
                  startedAt: (o["run_started_at"] as? String).flatMap(iso.date(from:)),
                  updatedAt: (o["updated_at"] as? String).flatMap(iso.date(from:)), title: o["display_title"] as? String ?? "")
    }

    init(id: Int, workflow: String, branch: String, status: String, conclusion: String, startedAt: Date?, updatedAt: Date?, title: String) {
        self.id = id; self.workflow = workflow; self.branch = branch; self.status = status; self.conclusion = conclusion
        self.startedAt = startedAt; self.updatedAt = updatedAt; self.title = title
    }
}

enum Deployments {
    static let fallback: TimeInterval = 600
    static let recent: TimeInterval = 1800
    static let findWithin: TimeInterval = 300

    static func deploys(_ runs: [DeployRun], deploying: Set<String>) -> [DeployRun] {
        let named = runs.filter { $0.workflow.lowercased().contains("deploy") }
        return named.isEmpty ? runs.filter { deploying.contains($0.workflow) } : named
    }

    static let deployWords = ["environment:", "serverless deploy", "sls deploy", "flyctl", "vercel", "railway", "heroku", "kubectl",
                              "helm upgrade", "docker push", "gcloud", "cdk deploy", "netlify deploy", "wrangler deploy", "firebase deploy", "fly deploy"]

    static func deploys(onPushTo branch: String, workflow text: String) -> Bool {
        let t = text.lowercased()
        let b = NSRegularExpression.escapedPattern(for: branch.lowercased())
        let onPush = t.contains("push:") && t.range(of: "branches:\\s*\\[?[^\\]\\n]*\\b\(b)\\b", options: .regularExpression) != nil
        return onPush && deployWords.contains { t.contains($0) }
    }

    static func name(ofWorkflow text: String) -> String? {
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) where line.hasPrefix("name:") {
            let v = line.dropFirst(5).trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
            return v.isEmpty ? nil : v
        }
        return nil
    }

    static func usual(_ runs: [DeployRun]) -> TimeInterval {
        let took = runs.filter { $0.outcome == .live }.compactMap(\.took).sorted()
        guard !took.isEmpty else { return fallback }
        return took.count % 2 == 1 ? took[took.count / 2] : (took[took.count / 2 - 1] + took[took.count / 2]) / 2
    }

    static func isStale(_ runs: [DeployRun], known: DeployRun?) -> Bool {
        guard let known, let newest = runs.first else { return false }
        return newest.id < known.id
    }

    enum Change: Equatable {
        case started(DeployRun, elapsed: TimeInterval)
        case ended(DeployRun, DeployOutcome)
    }

    static func changes(was: DeployRun?, runs: [DeployRun], firstLook: Bool, at now: Date, watchingSince: Date? = nil) -> [Change] {
        guard let newest = runs.first else { return [] }
        func elapsed(_ r: DeployRun) -> TimeInterval { r.startedAt.map { max(0, now.timeIntervalSince($0)) } ?? 0 }
        if firstLook { return newest.running ? [.started(newest, elapsed: elapsed(newest))] : [] }
        var out: [Change] = []
        if let was, was.running {
            if was.id == newest.id {
                if let o = newest.outcome { out.append(.ended(newest, o)) }
                return out
            }
            let then = runs.first { $0.id == was.id }
            out.append(.ended(then ?? was, then?.outcome ?? .cancelled))
        } else if let was, was.id == newest.id {
            return []
        }
        if !newest.running, elapsed(newest) > recent { return out }
        if !newest.running, let since = watchingSince, let over = newest.updatedAt, over < since { return out }
        out.append(.started(newest, elapsed: elapsed(newest)))
        if let o = newest.outcome { out.append(.ended(newest, o)) }
        return out
    }
}

final class DeploySource: Intake {
    let name = "deploys"
    private weak var github: GitHubResolver?
    private let lock = NSLock()
    private var newest: [String: DeployRun] = [:]
    private var usualOf: [String: TimeInterval] = [:]
    private var watchedSince: [String: Date] = [:]
    private var workflows: [String: (names: Set<String>, at: Date)] = [:]
    private var pending: [Report] = []

    init(github: GitHubResolver) { self.github = github }

    func checks() -> [Watch.Check] {
        (github?.watchedRoots() ?? []).map { root in Watch.Check(root + "#watch:runs", .runs) { [weak self] in self?.detectRuns(root) } }
    }

    func reports() -> [Report] {
        lock.lock(); defer { lock.unlock() }
        let out = pending; pending = []; return out
    }

    func deploys(repoRoot: String) -> [(branch: String, production: Bool, newest: DeployRun?, usual: TimeInterval)] {
        guard let github else { return [] }
        let branches = deployBranches(github.pipeline(repoRoot: repoRoot))
        lock.lock(); defer { lock.unlock() }
        return branches.map { ($0.branch, $0.production, newest[repoRoot + "|" + $0.branch], usualOf[repoRoot + "|" + $0.branch] ?? Deployments.fallback) }
    }

    private func deployBranches(_ p: Pipeline) -> [(branch: String, production: Bool)] {
        if p.shipsOnMerge { return [(p.trunk, true)] }
        return [(p.staging, false), (p.production, true)].filter { !$0.branch.isEmpty }
    }

    private var runsSeen: [String: String] = [:]
    private var runsFallbackAt: [String: Date] = [:]

    private func detectRuns(_ repoRoot: String) {
        let key = repoRoot + "#watch:runs"
        guard let github, github.pipelineKnown(repoRoot: repoRoot) else { return }
        let owner = github.nameWithOwner(repoRoot: repoRoot)
        let branches = deployBranches(github.pipeline(repoRoot: repoRoot))
        let workflows = branches.map { deployingWorkflows(branch: $0.branch, repoRoot: repoRoot) }
        let shape = "\(branches.map(\.branch))|\(workflows.map { $0.sorted() })"
        var all: [DeployRun]
        if let owner, let answer = github.watch.ask(key, "repos/\(owner)/actions/runs?event=push&per_page=60") {
            lock.lock(); let same = runsSeen[repoRoot] == shape; runsSeen[repoRoot] = shape; lock.unlock()
            guard answer.changed || !same, let o = try? JSONSerialization.jsonObject(with: answer.data) as? [String: Any],
                  let arr = o["workflow_runs"] as? [[String: Any]] else { return }
            all = arr.compactMap(DeployRun.init(api:))
        } else if owner == nil || !github.watch.http.hasToken {
            lock.lock()
            let due = Date().timeIntervalSince(runsFallbackAt[repoRoot] ?? .distantPast) >= github.baseInterval
            if due { runsFallbackAt[repoRoot] = Date() }
            lock.unlock()
            guard due, let out = github.run(["gh", "run", "list", "--event", "push", "--limit", "60",
                                      "--json", "databaseId,workflowName,headBranch,status,conclusion,startedAt,updatedAt,displayTitle"], cwd: repoRoot),
                  let arr = try? JSONSerialization.jsonObject(with: out) as? [[String: Any]] else { return }
            all = arr.compactMap(DeployRun.init(json:))
        } else { return }
        var running = false, ended = false
        for ((branch, production), deploying) in zip(branches, workflows) {
            let key = repoRoot + "|" + branch
            let runs = Deployments.deploys(all.filter { $0.branch == branch }, deploying: deploying)
            lock.lock()
            if Deployments.isStale(runs, known: newest[key]) { lock.unlock(); github.trace("deploys \(branch): stale answer, left alone"); continue }
            let first = newest[key] == nil
            if watchedSince[key] == nil { watchedSince[key] = Date() }
            let changes = Deployments.changes(was: newest[key], runs: runs, firstLook: first, at: Date(), watchingSince: watchedSince[key])
            let usual = Deployments.usual(runs)
            usualOf[key] = usual
            if let latest = runs.first {
                newest[key] = latest
                let age = latest.startedAt.map { Date().timeIntervalSince($0) } ?? 0
                running = running || latest.running && age < max(3 * usual, 1800)
            }
            for c in changes {
                pending.append(.deploy(repoRoot: repoRoot, production: production, change: c, usual: usual))
                if case .ended = c { ended = true }
            }
            lock.unlock()
            for c in changes { github.trace("deploy \(branch) \(c)") }
        }
        github.watch.tune(key) { if running { $0.heat(for: 60, Date()) } else if ended { $0.cool() } }
        lock.lock(); let any = !pending.isEmpty; lock.unlock()
        if any { DispatchQueue.main.async { github.onUpdate?() } }
    }

    private func deployingWorkflows(branch: String, repoRoot: String) -> Set<String> {
        guard let github else { return [] }
        let key = repoRoot + "|" + branch
        lock.lock(); let cached = workflows[key]; lock.unlock()
        if let cached, Date().timeIntervalSince(cached.at) < 3600 { return cached.names }
        var names = Set<String>()
        let ref = github.run(["git", "rev-parse", "--verify", "-q", "origin/\(branch)"], cwd: repoRoot) != nil ? "origin/\(branch)" : "HEAD"
        if let listing = github.run(["git", "ls-tree", "--name-only", ref, ".github/workflows/"], cwd: repoRoot), let files = String(data: listing, encoding: .utf8) {
            for path in files.split(separator: "\n") where path.hasSuffix(".yml") || path.hasSuffix(".yaml") {
                guard let data = github.run(["git", "show", "\(ref):\(path)"], cwd: repoRoot), let text = String(data: data, encoding: .utf8) else { continue }
                guard Deployments.deploys(onPushTo: branch, workflow: text) else { continue }
                names.insert(Deployments.name(ofWorkflow: text) ?? String(path.split(separator: "/").last ?? ""))
            }
        }
        lock.lock(); workflows[key] = (names, Date()); lock.unlock()
        return names
    }

}
