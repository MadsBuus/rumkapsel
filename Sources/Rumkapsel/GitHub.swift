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

/// One entry from a repository's activity feed.
struct FeedEvent: Equatable {
    let at: Date
    let actor: String
    let isBot: Bool
    let kind: String        // push, pr_open, pr_merge, pr_close, review, comment, branch_create, branch_delete, issue_open, release
    let branch: String?
    let prNumber: Int?
    let title: String?
    let url: String?
    let detail: String      // review state, commit count, etc.
}

struct OpenPR: Equatable {
    let number: Int
    let title: String
    let author: String
    let isBot: Bool
    let branch: String
    let url: String
    let createdAt: Date
}

/// Resolves pull requests for task branches with the gh CLI, off the main thread.
final class GitHubResolver {
    private var openPRs: [String: ([OpenPR], Date)] = [:]

    func teamOpenPRs(repoRoot: String) -> [OpenPR]? {
        lock.lock(); defer { lock.unlock() }
        return openPRs[repoRoot]?.0
    }

    /// Everyone's open pull requests, every five minutes.
    func refreshOpenPRs(repoRoot: String) {
        lock.lock()
        if let (_, at) = openPRs[repoRoot], Date().timeIntervalSince(at) < 300 { lock.unlock(); return }
        if inFlight.contains("o:" + repoRoot) { lock.unlock(); return }
        inFlight.insert("o:" + repoRoot)
        lock.unlock()
        queue.async { [self] in
            defer { lock.lock(); inFlight.remove("o:" + repoRoot); lock.unlock() }
            let iso = ISO8601DateFormatter()
            var found: [OpenPR] = []
            // A failed call must not count as "no open PRs", or everything looks new on the next success.
            guard let out = run(["gh", "pr", "list", "--state", "open", "--limit", "40", "--json", "number,title,author,headRefName,url,createdAt,updatedAt"], cwd: repoRoot) else { return }
            if let arr = try? JSONSerialization.jsonObject(with: out) as? [[String: Any]] {
                let stale = Date().addingTimeInterval(-14 * 24 * 3600)
                for o in arr {
                    if let u = (o["updatedAt"] as? String).flatMap(iso.date(from:)), u < stale { continue }
                    let a = o["author"] as? [String: Any]
                    let login = a?["login"] as? String ?? "?"
                    let isBot = (a?["is_bot"] as? Bool ?? false) || login.lowercased().contains("dependabot") || login.contains("[bot]")
                    found.append(OpenPR(number: o["number"] as? Int ?? 0, title: o["title"] as? String ?? "", author: login, isBot: isBot,
                                        branch: o["headRefName"] as? String ?? "", url: o["url"] as? String ?? "",
                                        createdAt: (o["createdAt"] as? String).flatMap(iso.date(from:)) ?? Date()))
                }
            }
            lock.lock()
            let changed = openPRs[repoRoot]?.0 != found
            openPRs[repoRoot] = (found, Date())
            lock.unlock()
            if changed { DispatchQueue.main.async { self.onUpdate?() } }
        }
    }

    private var releases: [String: ([ReleasePR], Date)] = [:]
    private var pendingLaunches: [(repoRoot: String, pr: ReleasePR)] = []
    private var stateChanges: [(branch: String, pr: PullRequest)] = []
    private var feeds: [String: ([FeedEvent], Date)] = [:]
    private var me: String?

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

    func myLogin() -> String? { lock.lock(); defer { lock.unlock() }; return me }
    func feed(repoRoot: String) -> [FeedEvent]? {
        lock.lock(); defer { lock.unlock() }
        return feeds[repoRoot]?.0
    }

    /// The repository's activity feed: everyone's pushes, pull requests, reviews and branches. Every two minutes.
    func refreshFeed(repoRoot: String) {
        lock.lock()
        if let (_, at) = feeds[repoRoot], Date().timeIntervalSince(at) < 120 { lock.unlock(); return }
        if inFlight.contains("f:" + repoRoot) { lock.unlock(); return }
        inFlight.insert("f:" + repoRoot)
        lock.unlock()
        queue.async { [self] in
            defer { lock.lock(); inFlight.remove("f:" + repoRoot); lock.unlock() }
            if me == nil, let out = run(["gh", "api", "user", "--jq", ".login"], cwd: repoRoot),
               let login = String(data: out, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !login.isEmpty {
                lock.lock(); me = login; lock.unlock()
            }
            var owner = nameWithOwner(repoRoot: repoRoot)
            if owner == nil, let out = run(["gh", "repo", "view", "--json", "nameWithOwner"], cwd: repoRoot),
               let obj = try? JSONSerialization.jsonObject(with: out) as? [String: Any], let n = obj["nameWithOwner"] as? String {
                lock.lock(); owners[repoRoot] = n; lock.unlock()
                owner = n
            }
            guard let owner else { return }
            let iso = ISO8601DateFormatter()
            var events: [FeedEvent] = []
            for page in 1...2 {
                guard let out = run(["gh", "api", "repos/\(owner)/events?per_page=100&page=\(page)"], cwd: repoRoot),
                      let arr = try? JSONSerialization.jsonObject(with: out) as? [[String: Any]] else { break }
                for e in arr {
                    guard let at = (e["created_at"] as? String).flatMap(iso.date(from:)) else { continue }
                    let actorObj = e["actor"] as? [String: Any]
                    let actor = actorObj?["login"] as? String ?? "?"
                    let isBot = actor.lowercased().contains("dependabot") || actor.contains("[bot]") || actor.lowercased().hasSuffix("-bot") || actor.lowercased().contains("webhook")
                    let payload = e["payload"] as? [String: Any] ?? [:]
                    let pr = payload["pull_request"] as? [String: Any]
                    let prNumber = pr?["number"] as? Int
                    let prTitle = pr?["title"] as? String
                    let prURL = pr?["html_url"] as? String
                    let prBranch = (pr?["head"] as? [String: Any])?["ref"] as? String
                    func add(_ kind: String, branch: String?, detail: String = "") {
                        events.append(FeedEvent(at: at, actor: actor, isBot: isBot, kind: kind, branch: branch, prNumber: prNumber,
                                                title: prTitle, url: prURL, detail: detail))
                    }
                    switch e["type"] as? String ?? "" {
                    case "PushEvent":
                        let ref = (payload["ref"] as? String ?? "").replacingOccurrences(of: "refs/heads/", with: "")
                        let n = (payload["commits"] as? [[String: Any]])?.count ?? (payload["size"] as? Int ?? 1)
                        add("push", branch: ref, detail: "\(max(1, n))")
                    case "PullRequestEvent":
                        let action = payload["action"] as? String ?? ""
                        let merged = (pr?["merged"] as? Bool ?? false) || action == "merged"
                        if action == "opened" || action == "reopened" { add("pr_open", branch: prBranch) }
                        else if action == "closed" || action == "merged" { add(merged ? "pr_merge" : "pr_close", branch: prBranch) }
                    case "PullRequestReviewEvent":
                        add("review", branch: prBranch, detail: ((payload["review"] as? [String: Any])?["state"] as? String ?? "").lowercased())
                    case "PullRequestReviewCommentEvent":
                        add("comment", branch: prBranch)
                    case "IssueCommentEvent":
                        if let issue = payload["issue"] as? [String: Any], issue["pull_request"] != nil { add("comment", branch: nil) }
                    case "CreateEvent":
                        if payload["ref_type"] as? String == "branch" { add("branch_create", branch: payload["ref"] as? String) }
                    case "DeleteEvent":
                        if payload["ref_type"] as? String == "branch" { add("branch_delete", branch: payload["ref"] as? String) }
                    case "IssuesEvent":
                        if payload["action"] as? String == "opened", let issue = payload["issue"] as? [String: Any] {
                            events.append(FeedEvent(at: at, actor: actor, isBot: isBot, kind: "issue_open", branch: nil, prNumber: issue["number"] as? Int,
                                                    title: issue["title"] as? String, url: issue["html_url"] as? String, detail: ""))
                        }
                    case "ReleaseEvent":
                        add("release", branch: nil, detail: ((payload["release"] as? [String: Any])?["tag_name"] as? String) ?? "")
                    default: break
                    }
                }
                if arr.count < 100 { break }
            }
            lock.lock()
            let changed = feeds[repoRoot]?.0 != events
            feeds[repoRoot] = (events, Date())
            lock.unlock()
            if changed { DispatchQueue.main.async { self.onUpdate?() } }
        }
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

    private let queue = DispatchQueue(label: "rumkapsel.github", qos: .utility, attributes: .concurrent)
    private var pulls: [String: (PullRequest?, Date)] = [:]
    private var commits: [String: (Int, Date)] = [:]
    private var pushed: [String: Bool] = [:]
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

    /// Whether the worktree's branch exists on origin, or nil if unknown yet.
    func branchPushed(worktree: String) -> Bool? {
        lock.lock(); defer { lock.unlock() }
        return pushed[worktree]
    }

    func refreshCommits(worktree: String) {
        lock.lock()
        if let (_, at) = commits[worktree], Date().timeIntervalSince(at) < 60 { lock.unlock(); return }
        if inFlight.contains("c:" + worktree) { lock.unlock(); return }
        inFlight.insert("c:" + worktree)
        lock.unlock()
        queue.async { [self] in
            // Work branches off develop where it exists; otherwise main, master, or the remote default.
            var base = "origin/HEAD"
            for candidate in ["origin/develop", "origin/main", "origin/master"] where run(["git", "rev-parse", "--verify", "--quiet", candidate], cwd: worktree) != nil {
                base = candidate; break
            }
            var isPushed = false
            if let out = run(["git", "branch", "--show-current"], cwd: worktree),
               let branch = String(data: out, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !branch.isEmpty {
                isPushed = run(["git", "rev-parse", "--verify", "--quiet", "origin/" + branch], cwd: worktree) != nil
            }
            var n = 0
            if let out = run(["git", "rev-list", "--count", "\(base)..HEAD"], cwd: worktree),
               let text = String(data: out, encoding: .utf8), let v = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)) {
                n = v
            }
            lock.lock()
            let changed = commits[worktree]?.0 != n || pushed[worktree] != isPushed
            commits[worktree] = (n, Date())
            pushed[worktree] = isPushed
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
