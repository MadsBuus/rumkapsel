import Foundation

struct PullRequest: Equatable {
    let number: Int
    let title: String
    let state: String          // OPEN, MERGED, CLOSED
    let reviewDecision: String // APPROVED, CHANGES_REQUESTED, REVIEW_REQUIRED or empty
    let isDraft: Bool
    let url: String
    var checks: String = ""    // failure, pending, success or empty

    var summary: String {
        var s = "PR #\(number) " + (isDraft ? "draft" : state.lowercased())
        switch reviewDecision {
        case "APPROVED": s += " · approved"
        case "CHANGES_REQUESTED": s += " · changes requested"
        case "REVIEW_REQUIRED": s += " · awaiting review"
        default: break
        }
        switch checks {
        case "failure": s += " · checks failing"
        case "pending": s += " · checks running"
        case "success": s += " · checks green"
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
    let mergedAt: Date?
    var isProduction: Bool { base == ConfigStore.shared.current.productionBranch }
    var untested: Bool { labels.contains { $0.lowercased().contains("untested") } }
}

/// One entry from a repository's activity feed.
struct FeedEvent: Equatable, Codable {
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

/// One issue on the team's GitHub project, with where the Status field says it is.
struct ProjectItem: Equatable, Codable {
    let repo: String          // repository name without the owner
    let number: Int
    let title: String
    let status: String
    let assignees: [String]
    let prURLs: [String]
    let url: String
    var updatedAt: Date? = nil
}

struct OpenPR: Equatable, Codable {
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
    /// Poll interval for pull requests, releases and open PRs; the feed stays at two minutes.
    var intervalMinutes = 5
    private var interval: TimeInterval { Double(intervalMinutes) * 60 }
    private var openPRs: [String: ([OpenPR], Date)] = [:]

    func teamOpenPRs(repoRoot: String) -> [OpenPR]? {
        lock.lock(); defer { lock.unlock() }
        return openPRs[repoRoot]?.0
    }

    /// Everyone's open pull requests, every five minutes.
    /// Polls wait until this moment: a random hold at start-up so apps opening together on one
    /// network don't all ask GitHub at once, and the first one to answer feeds the rest.
    var holdUntil = Date.distantPast

    /// What a peer could use: everyone's open pull requests and the recent feed, with fetch times.
    struct Knowledge: Codable { var repo: String; var openPRs: [OpenPR]?; var prsAt: Date?; var feed: [FeedEvent]?; var feedAt: Date? }
    struct ProjectKnowledge: Codable { var owner: String; var number: Int; var items: [ProjectItem]; var at: Date }
    func projectKnowledge(owner: String, number: Int) -> ProjectKnowledge? {
        lock.lock(); defer { lock.unlock() }
        guard let p = project else { return nil }
        return ProjectKnowledge(owner: owner, number: number, items: p.0, at: p.1)
    }

    func knowledge(repoRoot: String, repo: String) -> Knowledge? {
        lock.lock(); defer { lock.unlock() }
        let prs = openPRs[repoRoot], f = feeds[repoRoot]
        guard prs != nil || f != nil else { return nil }
        let recent = Date().addingTimeInterval(-24 * 3600)
        return Knowledge(repo: repo, openPRs: prs?.0, prsAt: prs?.1, feed: f.map { Array($0.0.filter { $0.at > recent }.prefix(80)) }, feedAt: f?.1)
    }

    /// Takes a peer's fresher answer instead of asking GitHub again.
    func adopt(_ k: Knowledge, repoRoot: String) {
        var changed = false
        lock.lock()
        if let prs = k.openPRs, let at = k.prsAt, at > (openPRs[repoRoot]?.1 ?? .distantPast) {
            changed = openPRs[repoRoot]?.0 != prs
            openPRs[repoRoot] = (prs, at)
        }
        if let f = k.feed, let at = k.feedAt, at > (feeds[repoRoot]?.1 ?? .distantPast) {
            changed = changed || feeds[repoRoot]?.0 != f
            feeds[repoRoot] = (f, at)
        }
        lock.unlock()
        if changed { DispatchQueue.main.async { self.onUpdate?() } }
    }

    func refreshOpenPRs(repoRoot: String) {
        lock.lock()
        if Date() < holdUntil { lock.unlock(); return }
        if let (_, at) = openPRs[repoRoot], Date().timeIntervalSince(at) < interval { lock.unlock(); return }
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
    /// Packages waiting per repo: merged into trunk but not yet on staging, and on staging but not yet in production.
    struct Cargo: Equatable { var storage: Int; var deck: Int; var storageNumbers: [Int]; var deckNumbers: [Int]; var clearedNumbers: [Int] = [] }
    private var cargo: [String: Cargo] = [:]

    /// What waits where for a repository: from the project board when one is configured, else from git history.
    func cargo(repoRoot: String) -> Cargo? {
        lock.lock(); defer { lock.unlock() }
        if let items = project?.0, let owner = owners[repoRoot] {
            let repo = String(owner.split(separator: "/").last ?? "")
            let st = ConfigStore.shared.current.statuses
            let mine = items.filter { $0.repo == repo }
            guard !mine.isEmpty else { return cargo[repoRoot] }   // a repository not on the board keeps the git-history yard
            let storage = mine.filter { $0.status == st.storage }.map(\.number).sorted()
            let deck = mine.filter { $0.status == st.deck || $0.status == st.cleared }.map(\.number).sorted()
            let cleared = mine.filter { $0.status == st.cleared }.map(\.number).sorted()
            return Cargo(storage: storage.count, deck: deck.count, storageNumbers: storage, deckNumbers: deck, clearedNumbers: cleared)
        }
        return cargo[repoRoot]
    }

    // MARK: project board

    private var project: ([ProjectItem], Date)?
    private var projectMoves: [(item: ProjectItem, from: String?)] = []

    func projectItems() -> [ProjectItem]? { lock.lock(); defer { lock.unlock() }; return project?.0 }
    func projectFetchedAt() -> Date? { lock.lock(); defer { lock.unlock() }; return project?.1 }

    /// Items whose Status changed since the previous read, each returned once.
    func takeProjectMoves() -> [(item: ProjectItem, from: String?)] {
        lock.lock(); defer { lock.unlock() }
        let out = projectMoves; projectMoves = []; return out
    }

    /// One read of the whole board: every issue, its status, its assignees and linked pull requests.
    func refreshProject(owner: String, number: Int) {
        lock.lock()
        if Date() < holdUntil { lock.unlock(); return }
        if let (_, at) = project, Date().timeIntervalSince(at) < interval { lock.unlock(); return }
        if inFlight.contains("project") { lock.unlock(); return }
        inFlight.insert("project")
        lock.unlock()
        queue.async { [self] in
            defer { lock.lock(); inFlight.remove("project"); lock.unlock() }
            // GraphQL rather than `gh project item-list`: it carries when each item last moved.
            let iso = ISO8601DateFormatter()
            var items: [ProjectItem] = []
            var cursor = "null"
            for _ in 0..<6 {
                let query = """
                { organization(login: "\(owner)") { projectV2(number: \(number)) { items(first: 100, after: \(cursor)) {
                  pageInfo { hasNextPage endCursor }
                  nodes { updatedAt
                    fieldValueByName(name: "Status") { ... on ProjectV2ItemFieldSingleSelectValue { name } }
                    content { ... on Issue { number title url repository { name } assignees(first: 5) { nodes { login } }
                      closedByPullRequestsReferences(first: 5) { nodes { url } } } } } } } } }
                """
                guard let out = run(["gh", "api", "graphql", "-f", "query=" + query], cwd: FileManager.default.homeDirectoryForCurrentUser.path),
                      let obj = try? JSONSerialization.jsonObject(with: out) as? [String: Any],
                      let itemsObj = ((obj["data"] as? [String: Any])?["organization"] as? [String: Any]).flatMap({ $0["projectV2"] as? [String: Any] })?["items"] as? [String: Any],
                      let nodes = itemsObj["nodes"] as? [[String: Any]] else { return }
                for o in nodes {
                    guard let content = o["content"] as? [String: Any], let n = content["number"] as? Int,
                          let repo = (content["repository"] as? [String: Any])?["name"] as? String else { continue }
                    let status = (o["fieldValueByName"] as? [String: Any])?["name"] as? String ?? ""
                    let assignees = ((content["assignees"] as? [String: Any])?["nodes"] as? [[String: Any]] ?? []).compactMap { $0["login"] as? String }
                    let prs = ((content["closedByPullRequestsReferences"] as? [String: Any])?["nodes"] as? [[String: Any]] ?? []).compactMap { $0["url"] as? String }
                    items.append(ProjectItem(repo: repo, number: n, title: content["title"] as? String ?? "", status: status, assignees: assignees,
                                             prURLs: prs, url: content["url"] as? String ?? "", updatedAt: (o["updatedAt"] as? String).flatMap(iso.date(from:))))
                }
                let page = itemsObj["pageInfo"] as? [String: Any]
                guard page?["hasNextPage"] as? Bool == true, let end = page?["endCursor"] as? String else { break }
                cursor = "\"\(end)\""
            }
            adoptProject(items, at: Date())
        }
    }

    /// Takes a board read, ours or a peer's, when it is fresher than what we hold; notes every move.
    func adoptProject(_ items: [ProjectItem], at: Date) {
        lock.lock()
        guard at > (project?.1 ?? .distantPast) else { lock.unlock(); return }
        let previous = project?.0
        if let previous {
            let before = Dictionary(previous.map { ("\($0.repo)#\($0.number)", $0.status) }, uniquingKeysWith: { a, _ in a })
            for it in items where before["\(it.repo)#\(it.number)"] != it.status { projectMoves.append((it, before["\(it.repo)#\(it.number)"])) }
        }
        let changed = previous != items
        project = (items, at)
        lock.unlock()
        if changed { DispatchQueue.main.async { self.onUpdate?() } }
    }
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

    /// True while any GitHub or git call for the repository is running.
    func isBusy(repoRoot: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return inFlight.contains { $0.hasSuffix(repoRoot) || $0.hasPrefix(repoRoot + "@") || $0.hasPrefix("c:" + repoRoot) }
    }
    func feed(repoRoot: String) -> [FeedEvent]? {
        lock.lock(); defer { lock.unlock() }
        return feeds[repoRoot]?.0
    }

    /// The repository's activity feed: everyone's pushes, pull requests, reviews and branches. Every two minutes.
    func refreshFeed(repoRoot: String) {
        lock.lock()
        if Date() < holdUntil { lock.unlock(); return }
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
        if let (_, at) = releases[repoRoot], Date().timeIntervalSince(at) < interval { lock.unlock(); return }
        if inFlight.contains("r:" + repoRoot) { lock.unlock(); return }
        inFlight.insert("r:" + repoRoot)
        lock.unlock()
        queue.async { [self] in
            var found: [ReleasePR] = []
            let cfg = ConfigStore.shared.current
            // Which of the configured branches this repository actually has.
            var remoteBranches = Set<String>()
            if let out = run(["git", "branch", "-r", "--format=%(refname:short)"], cwd: repoRoot), let text = String(data: out, encoding: .utf8) {
                for line in text.split(separator: "\n") { remoteBranches.insert(line.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "origin/", with: "")) }
            }
            let stagingBranch = remoteBranches.contains(cfg.stagingBranch) ? cfg.stagingBranch : ""
            // Production: the configured branch if the repo has it, else main, else master (never the trunk itself).
            let productionBranch = [cfg.productionBranch, "main", "master"].first { !$0.isEmpty && $0 != cfg.trunkBranch && remoteBranches.contains($0) } ?? ""
            let bases = [stagingBranch, productionBranch].filter { !$0.isEmpty }
            let heads: Set<String> = [cfg.trunkBranch, stagingBranch].filter { !$0.isEmpty }.reduce(into: []) { $0.insert($1) }
            for base in bases {
                guard let out = run(["gh", "pr", "list", "--base", base, "--state", "all", "--limit", "5",
                                     "--json", "number,title,baseRefName,headRefName,state,url,labels,mergedAt"], cwd: repoRoot),
                      let arr = try? JSONSerialization.jsonObject(with: out) as? [[String: Any]] else { continue }
                for o in arr {
                    let head = o["headRefName"] as? String ?? ""
                    guard heads.contains(head) else { continue }
                    let labels = (o["labels"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
                    found.append(ReleasePR(number: o["number"] as? Int ?? 0, title: o["title"] as? String ?? "", base: base,
                                           head: head, state: o["state"] as? String ?? "", url: o["url"] as? String ?? "", labels: labels,
                                           mergedAt: (o["mergedAt"] as? String).flatMap(ISO8601DateFormatter().date(from:))))
                }
            }
            // Cargo: PRs merged into trunk, split by the last staging and production releases.
            let iso = ISO8601DateFormatter()
            let lastStaging = found.filter { $0.base == stagingBranch && $0.state == "MERGED" }.compactMap(\.mergedAt).max()
            let lastProduction = found.filter { $0.base == productionBranch && $0.state == "MERGED" }.compactMap(\.mergedAt).max()
            var newCargo = Cargo(storage: 0, deck: 0, storageNumbers: [], deckNumbers: [])
            // No release pipeline in this repository: nothing waits for a launch here.
            let hasPipeline = !bases.isEmpty && (lastStaging != nil || lastProduction != nil)
            let floor = Date().addingTimeInterval(-30 * 24 * 3600)
            // Exact diff between branches when they all exist: pull request numbers named in the commits.
            func prNumbers(_ range: String) -> [Int]? {
                guard let out = run(["git", "log", "--format=%s", "--no-merges", "--max-count=300", range], cwd: repoRoot),
                      let text = String(data: out, encoding: .utf8) else { return nil }
                var found: [Int] = []
                for line in text.split(separator: "\n") {
                    if let m = line.firstMatch(of: #/\(#(\d+)\)\s*$/#), let n = Int(m.1) { found.append(n) }
                }
                if let out = run(["git", "log", "--format=%s", "--merges", "--max-count=300", range], cwd: repoRoot), let t = String(data: out, encoding: .utf8) {
                    for line in t.split(separator: "\n") {
                        if let m = line.firstMatch(of: #/Merge pull request #(\d+)/#), let n = Int(m.1) { found.append(n) }
                    }
                }
                return Array(Set(found)).sorted(by: >)
            }
            var exact = false
            if hasPipeline, !stagingBranch.isEmpty, !productionBranch.isEmpty {
                _ = run(["git", "fetch", "-q", "origin", cfg.trunkBranch, stagingBranch, productionBranch], cwd: repoRoot)
                if let deck = prNumbers("origin/\(productionBranch)..origin/\(stagingBranch)"),
                   let storage = prNumbers("origin/\(stagingBranch)..origin/\(cfg.trunkBranch)") {
                    let releaseNumbers = Set(found.map(\.number))
                    newCargo.deckNumbers = deck.filter { !releaseNumbers.contains($0) }
                    newCargo.storageNumbers = storage.filter { !releaseNumbers.contains($0) }
                    newCargo.deck = newCargo.deckNumbers.count
                    newCargo.storage = newCargo.storageNumbers.count
                    exact = true
                }
            }
            if hasPipeline, !exact, let out = run(["gh", "pr", "list", "--base", cfg.trunkBranch, "--state", "merged", "--limit", "80", "--json", "number,mergedAt,author"], cwd: repoRoot),
               let arr = try? JSONSerialization.jsonObject(with: out) as? [[String: Any]] {
                for o in arr {
                    guard let m = (o["mergedAt"] as? String).flatMap(iso.date(from:)), let n = o["number"] as? Int else { continue }
                    let a = o["author"] as? [String: Any]
                    let login = a?["login"] as? String ?? ""
                    if (a?["is_bot"] as? Bool ?? false) || login.lowercased().contains("dependabot") || login.contains("[bot]") { continue }
                    if m < floor { continue }
                    if let lp = lastProduction, m <= lp { continue }                 // already shipped
                    if stagingBranch.isEmpty || lastStaging == nil || m > lastStaging! { newCargo.storage += 1; newCargo.storageNumbers.append(n) }
                    else { newCargo.deck += 1; newCargo.deckNumbers.append(n) }
                }
            }
            lock.lock()
            let previous = releases[repoRoot]?.0 ?? []
            for pr in found where pr.state == "MERGED" && previous.contains(where: { $0.number == pr.number && $0.state == "OPEN" }) {
                pendingLaunches.append((repoRoot, pr))
            }
            let changed = previous != found || cargo[repoRoot] != newCargo
            cargo[repoRoot] = newCargo
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
    private var dirty: [String: Int] = [:]
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

    /// Changed or new files not yet committed in the worktree.
    func dirtyFiles(worktree: String) -> Int {
        lock.lock(); defer { lock.unlock() }
        return dirty[worktree] ?? 0
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
            let trunk = ConfigStore.shared.current.trunkBranch
            for candidate in ["origin/" + trunk, "origin/develop", "origin/main", "origin/master"] where run(["git", "rev-parse", "--verify", "--quiet", candidate], cwd: worktree) != nil {
                base = candidate; break
            }
            var isPushed = false
            if let out = run(["git", "branch", "--show-current"], cwd: worktree),
               let branch = String(data: out, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !branch.isEmpty {
                isPushed = run(["git", "rev-parse", "--verify", "--quiet", "origin/" + branch], cwd: worktree) != nil
            }
            var changed = 0
            if let out = run(["git", "status", "--porcelain"], cwd: worktree), let text = String(data: out, encoding: .utf8) {
                changed = text.split(separator: "\n").count
            }
            var n = 0
            if let out = run(["git", "rev-list", "--count", "\(base)..HEAD"], cwd: worktree),
               let text = String(data: out, encoding: .utf8), let v = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)) {
                n = v
            }
            lock.lock()
            let changedResult = commits[worktree]?.0 != n || pushed[worktree] != isPushed || dirty[worktree] != changed
            commits[worktree] = (n, Date())
            pushed[worktree] = isPushed
            dirty[worktree] = changed
            inFlight.remove("c:" + worktree)
            lock.unlock()
            if changedResult { DispatchQueue.main.async { self.onUpdate?() } }
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
        if let (_, at) = pulls[key], Date().timeIntervalSince(at) < interval { lock.unlock(); return }
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
                var checks = ""
                if let rollup = o["statusCheckRollup"] as? [[String: Any]], !rollup.isEmpty {
                    let conclusions = rollup.map { ($0["conclusion"] as? String ?? "").uppercased() }
                    let statuses = rollup.map { ($0["status"] as? String ?? $0["state"] as? String ?? "").uppercased() }
                    if conclusions.contains(where: { ["FAILURE", "TIMED_OUT", "CANCELLED", "ACTION_REQUIRED", "ERROR"].contains($0) }) || statuses.contains("FAILURE") || statuses.contains("ERROR") { checks = "failure" }
                    else if statuses.contains(where: { ["IN_PROGRESS", "QUEUED", "PENDING", "WAITING"].contains($0) }) || conclusions.contains("") { checks = "pending" }
                    else { checks = "success" }
                }
                var pr = PullRequest(number: o["number"] as? Int ?? 0, title: o["title"] as? String ?? "",
                                     state: o["state"] as? String ?? "", reviewDecision: o["reviewDecision"] as? String ?? "",
                                     isDraft: o["isDraft"] as? Bool ?? false, url: o["url"] as? String ?? "")
                pr.checks = checks
                return pr
            }
            let fields = "number,title,state,reviewDecision,isDraft,url,statusCheckRollup"
            var answered = false   // a failed call is not "no pull request": keep what we knew
            if let out = run(["gh", "pr", "view", branch, "--json", fields], cwd: repoRoot),
               let o = try? JSONSerialization.jsonObject(with: out) as? [String: Any] {
                pr = parse(o); answered = true
            } else if let out = run(["gh", "pr", "list", "--head", branch, "--state", "all", "--limit", "1", "--json", fields], cwd: repoRoot),
                      let arr = try? JSONSerialization.jsonObject(with: out) as? [[String: Any]] {
                pr = arr.first.map(parse); answered = true
            }
            lock.lock()
            if !answered, let old = pulls[key] {
                pulls[key] = (old.0, Date().addingTimeInterval(60 - interval))   // try again in a minute
                inFlight.remove(key)
                lock.unlock()
                return
            }
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
