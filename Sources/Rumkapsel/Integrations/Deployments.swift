import Foundation

/// One run of a workflow on a push to a branch, as GitHub Actions reports it.
struct DeployRun: Equatable {
    let id: Int
    let workflow: String
    let branch: String
    /// queued, in_progress, waiting, requested, pending, or completed.
    let status: String
    /// success, failure, cancelled, skipped, timed_out…; empty while it runs.
    let conclusion: String
    let startedAt: Date?
    let updatedAt: Date?
    /// The run's title: the merge's subject, "Merge pull request #5466 from …".
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
    /// How long it took, once it is over.
    var took: TimeInterval? {
        guard !running, let s = startedAt, let u = updatedAt, u > s else { return nil }
        return u.timeIntervalSince(s)
    }
    /// The release it deploys, as the merge's title names it: "#5466", or nothing.
    var release: String {
        title.range(of: "#[0-9]+", options: .regularExpression).map { String(title[$0]) } ?? ""
    }

    /// From one entry of `gh run list --json databaseId,workflowName,headBranch,status,conclusion,startedAt,updatedAt,displayTitle`.
    init?(json o: [String: Any]) {
        guard let id = o["databaseId"] as? Int else { return nil }
        let iso = ISO8601DateFormatter()
        self.init(id: id, workflow: o["workflowName"] as? String ?? "", branch: o["headBranch"] as? String ?? "",
                  status: o["status"] as? String ?? "", conclusion: o["conclusion"] as? String ?? "",
                  startedAt: (o["startedAt"] as? String).flatMap(iso.date(from:)),
                  updatedAt: (o["updatedAt"] as? String).flatMap(iso.date(from:)), title: o["displayTitle"] as? String ?? "")
    }

    /// From one entry of the REST API's `workflow_runs`.
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

/// What GitHub Actions says about a repository's deploys, as flights: started, and ended live, failed or
/// cancelled. It reads and reports; it never looks at a run's steps, only at the run.
enum Deployments {
    /// How long a deploy is taken to last before a repository has finished one.
    static let fallback: TimeInterval = 600
    /// A deploy older than this when first heard of is history, never a flight; so is a merge heard of this late.
    static let recent: TimeInterval = 1800
    /// How long after a release merges its deploy has to show before the flight is given up on.
    static let findWithin: TimeInterval = 300

    /// The runs that are deploys: of a workflow named for deploying where the branch has one, else of one
    /// whose file deploys on a push to the branch. Newest first, as GitHub lists them.
    static func deploys(_ runs: [DeployRun], deploying: Set<String>) -> [DeployRun] {
        let named = runs.filter { $0.workflow.lowercased().contains("deploy") }
        return named.isEmpty ? runs.filter { deploying.contains($0.workflow) } : named
    }

    /// What a deploy step runs, in any workflow: a GitHub environment, or one of the usual deploy tools.
    static let deployWords = ["environment:", "serverless deploy", "sls deploy", "flyctl", "vercel", "railway", "heroku", "kubectl",
                              "helm upgrade", "docker push", "gcloud", "cdk deploy", "netlify deploy", "wrangler deploy", "firebase deploy", "fly deploy"]

    /// Whether a workflow file runs on a push to `branch` and deploys.
    static func deploys(onPushTo branch: String, workflow text: String) -> Bool {
        let t = text.lowercased()
        let b = NSRegularExpression.escapedPattern(for: branch.lowercased())
        // `branches: [staging]`, or a list whose first entry is on the next line.
        let onPush = t.contains("push:") && t.range(of: "branches:\\s*\\[?[^\\]\\n]*\\b\(b)\\b", options: .regularExpression) != nil
        return onPush && deployWords.contains { t.contains($0) }
    }

    /// The workflow's own name, from its top-level `name:`.
    static func name(ofWorkflow text: String) -> String? {
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) where line.hasPrefix("name:") {
            let v = line.dropFirst(5).trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
            return v.isEmpty ? nil : v
        }
        return nil
    }

    /// How long this repository's deploys usually take: the middle of its recent successful ones.
    static func usual(_ runs: [DeployRun]) -> TimeInterval {
        let took = runs.filter { $0.outcome == .live }.compactMap(\.took).sorted()
        guard !took.isEmpty else { return fallback }
        return took.count % 2 == 1 ? took[took.count / 2] : (took[took.count / 2 - 1] + took[took.count / 2]) / 2
    }

    /// An answer whose newest run is older than one already seen: GitHub's run listing now and then serves
    /// a snapshot weeks old. Run ids only grow, so such an answer is left alone.
    static func isStale(_ runs: [DeployRun], known: DeployRun?) -> Bool {
        guard let known, let newest = runs.first else { return false }
        return newest.id < known.id
    }

    enum Change: Equatable {
        /// Under way, and for how long already.
        case started(DeployRun, elapsed: TimeInterval)
        case ended(DeployRun, DeployOutcome)
    }

    /// What changed between the newest deploy known before and the runs read now. The first reading of a
    /// repository is quiet about deploys already over; one still running is joined where it has got to.
    /// A newer deploy takes over from an older one still running: the older is ended the way the list says,
    /// cancelled when the list no longer has it.
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
        // Over already and begun long ago: history, not a flight.
        if !newest.running, elapsed(newest) > recent { return out }
        // Over before the station was watching: history, however fresh. GitHub's first answer can be a
        // snapshot weeks old, so the first look is no guard on its own.
        if !newest.running, let since = watchingSince, let over = newest.updatedAt, over < since { return out }
        out.append(.started(newest, elapsed: elapsed(newest)))
        if let o = newest.outcome { out.append(.ended(newest, o)) }
        return out
    }
}
