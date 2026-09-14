import Foundation

struct PullRequest: Equatable {
    let number: Int
    let title: String
    let state: String          // OPEN, MERGED, CLOSED
    let reviewDecision: String // APPROVED, CHANGES_REQUESTED, REVIEW_REQUIRED or empty
    let isDraft: Bool
    let url: String
    var checks: String = ""    // failure, pending, success or empty
    /// The issues this pull request closes: the tasks its work is for. With a board, the first is the crate.
    var closes: [Int] = []

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
    /// Whether the base is this repository's own production or staging branch, set when the release is
    /// read against the repository's pipeline. Nil falls back to the branch names in the settings.
    var production: Bool? = nil
    var staging: Bool? = nil
    var isProduction: Bool { production ?? (base == ConfigStore.shared.current.productionBranch) }
    /// A release into the staging branch: what the pallet carries crates for.
    var isStaging: Bool {
        if let staging { return staging }
        let name = ConfigStore.shared.current.stagingBranch
        return !name.isEmpty && base == name
    }
    var untested: Bool { labels.contains { $0.lowercased().contains("untested") } }
}

/// A repository's own way to production: the branch work merges into, an optional staging branch
/// between, and the branch releases go into. Read from the branches the repository actually has.
struct Pipeline: Equatable {
    var trunk: String
    var staging: String
    var production: String
    /// Head branches a release may come from besides the trunk and staging: "release*" matches release/v9.7.1.
    var releaseBranches: [String] = PipelineDetection.defaultReleaseBranches
    /// Whether the board's storage and QA columns fill this repository's yard; nil lets the board decide.
    var boardColumns: Bool? = nil
    /// Where this came from, "file", "history", "branches" or "settings", and in a few words why.
    var source: String = "settings"
    var why: String = ""
    /// "merge" when every merge into the trunk deploys and ships at once; "release" when releases do.
    var ship: String = "release"
    var shipsOnMerge: Bool { ship == "merge" }
    var hasStaging: Bool { !staging.isEmpty }
    func isReleaseHead(_ head: String) -> Bool {
        head == trunk || (hasStaging && head == staging) || releaseBranches.contains { PipelineDetection.matches(head, $0) }
    }
    /// The settings' names, for a repository whose branches have not been read yet.
    static var configured: Pipeline {
        let c = ConfigStore.shared.current
        return Pipeline(trunk: c.trunkBranch, staging: c.stagingBranch, production: c.productionBranch)
    }
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
    /// The issue's own state, OPEN or CLOSED: a closed issue is finished work, whatever column it sits in.
    var state: String = "OPEN"
    var isClosed: Bool { state == "CLOSED" }
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
    /// Frozen: every refresh is a no-op and nothing is written to disk. Only the simulator sets it,
    /// and only a frozen resolver accepts injected answers.
    var frozen = false
    /// Set while the simulator writes a batch of answers, so one push wakes the scene once.
    var injectSilently = false
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
        if frozen { return }
        lock.lock()
        if Date() < holdUntil { lock.unlock(); return }
        if let (_, at) = openPRs[repoRoot], Date().timeIntervalSince(at) < gate("openPRs:" + repoRoot, base: interval) { lock.unlock(); return }
        if inFlight.contains("o:" + repoRoot) { lock.unlock(); return }
        inFlight.insert("o:" + repoRoot)
        lock.unlock()
        trace("ask openPRs \(repoRoot)")
        queue.async { [self] in
            defer { lock.lock(); inFlight.remove("o:" + repoRoot); lock.unlock() }
            let iso = ISO8601DateFormatter()
            var found: [OpenPR] = []
            // A failed call must not count as "no open PRs", or everything looks new on the next success.
            guard let out = run(["gh", "pr", "list", "--state", "open", "--limit", "40", "--json", "number,title,author,headRefName,url,createdAt,updatedAt"], cwd: repoRoot) else { trace("openPRs \(repoRoot) failed"); return }
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
    /// What a source counts where for a repository. `updated` is the source's own time per number,
    /// when it has one: a board item carries when it last moved; git history carries nothing.
    struct Cargo: Equatable {
        var storage: Int; var deck: Int; var storageNumbers: [Int]; var deckNumbers: [Int]; var clearedNumbers: [Int] = []
        var updated: [Int: Date] = [:]
    }
    private var cargo: [String: Cargo] = [:]
    /// Each repository's pipeline, as its branches said at the last release read.
    private var pipelines: [String: Pipeline] = [:]
    /// When each repository's history and file were last read: at most once an hour.
    private var pipelineCheckedAt: [String: Date] = [:]
    /// Repositories whose work moves through the board's storage and QA columns: their yard is the board's.
    private var boardYards: Set<String> = Set(GitHubResolver.loadBoardFile()?.yards ?? [])

    /// What waits where for a repository: from the project board when one is configured, else from git history.
    func cargo(repoRoot: String) -> Cargo? {
        lock.lock(); defer { lock.unlock() }
        // A board is configured but this repository's name is not known yet: nothing is drawn rather
        // than the git-history yard, which the board's answer would only redraw a moment later.
        if ConfigStore.shared.current.project != nil, project != nil, owners[repoRoot] == nil { return nil }
        if let items = project?.0, let owner = owners[repoRoot] {
            let repo = String(owner.split(separator: "/").last ?? "")
            let st = ConfigStore.shared.current.statuses
            let mine = items.filter { $0.repo == repo }
            // The board fills a repository's yard only once the repository moves work through the storage and
            // QA columns. One that goes from development straight to shipped is on the board but not in its
            // middle: its yard comes from git, like a repository not on the board at all.
            let decided = pipelines[repoRoot]?.boardColumns   // the repository's own file says, when it says
            if decided == nil, mine.contains(where: { [st.storage, st.deck, st.cleared].contains($0.status) }), !boardYards.contains(repo) {
                boardYards.insert(repo)
                if let (all, at) = project { saveBoard(all, at: at) }
            }
            if !mine.isEmpty, decided ?? boardYards.contains(repo) {
            let storage = mine.filter { $0.status == st.storage }.map(\.number).sorted()
            let deck = mine.filter { $0.status == st.deck || $0.status == st.cleared }.map(\.number).sorted()
            let cleared = mine.filter { $0.status == st.cleared }.map(\.number).sorted()
            let updated = Dictionary(mine.compactMap { it in it.updatedAt.map { (it.number, $0) } }, uniquingKeysWith: { a, _ in a })
            return Cargo(storage: storage.count, deck: deck.count, storageNumbers: storage, deckNumbers: deck, clearedNumbers: cleared, updated: updated)
            }
        }
        guard var c = cargo[repoRoot] else { return nil }
        // Releases are made of pull requests; the floor shows tasks. Where the link is known, translate.
        if let owner = owners[repoRoot] {
            let repo = String(owner.split(separator: "/").last ?? "")
            c.storageNumbers = asTasks(c.storageNumbers, repo: repo)
            c.deckNumbers = asTasks(c.deckNumbers, repo: repo)
            c.clearedNumbers = asTasks(c.clearedNumbers, repo: repo)
            c.storage = c.storageNumbers.count; c.deck = c.deckNumbers.count
        }
        return c
    }

    // MARK: project board

    private var project: ([ProjectItem], Date)? = GitHubResolver.loadBoard()
    /// "owner/name" per checkout, learned once from `gh repo view` and kept with the board: the yard
    /// cannot tell which board items are a repository's until it knows the repository's name.
    private var owners: [String: String] = GitHubResolver.loadBoardFile()?.owners ?? [:]
    private var projectMoves: [(item: ProjectItem, from: String?)] = []

    /// The last board read is kept on disk, so the first read after a launch still knows what moved.
    private static var boardURL: URL {
        let dir = AppSupport.root.appendingPathComponent("Rumkapsel", isDirectory: true)
        return dir.appendingPathComponent("board.json")
    }
    private struct SavedBoard: Codable { var items: [ProjectItem]; var at: Date; var owners: [String: String]?; var tasks: [String: [String: Int]]?; var yards: [String]? }
    private static func loadBoardFile() -> SavedBoard? {
        guard let data = try? Data(contentsOf: boardURL) else { return nil }
        return try? JSONDecoder().decode(SavedBoard.self, from: data)
    }
    private static func loadBoard() -> ([ProjectItem], Date)? { loadBoardFile().map { ($0.items, $0.at) } }
    private func saveBoard(_ items: [ProjectItem], at: Date) {
        if frozen { return }
        let saved = SavedBoard(items: items, at: at, owners: owners,
                               tasks: tasks.mapValues { Dictionary(uniqueKeysWithValues: $0.map { (String($0.key), $0.value) }) },
                               yards: boardYards.sorted())
        if let data = try? JSONEncoder().encode(saved) { try? data.write(to: GitHubResolver.boardURL) }
    }

    // MARK: tasks

    /// Which issue each pull request's work is for, by repository name then pull request number: an
    /// issue is the task, the pull request the work done for it. Learned from every pull request answer
    /// and from the board's links, and kept with the board, since the board forgets a link on merge.
    private var tasks: [String: [Int: Int]] = (GitHubResolver.loadBoardFile()?.tasks ?? [:])
        .mapValues { Dictionary(uniqueKeysWithValues: $0.compactMap { k, v in Int(k).map { ($0, v) } }) }

    private static func closes(_ o: [String: Any]) -> [Int] {
        ((o["closingIssuesReferences"] as? [[String: Any]]) ?? []).compactMap { $0["number"] as? Int }
    }

    private func noteTask(_ pr: PullRequest, repoRoot: String) {
        guard let issue = pr.closes.first else { return }
        lock.lock()
        guard let owner = owners[repoRoot] else { lock.unlock(); return }
        let repo = String(owner.split(separator: "/").last ?? "")
        let known = tasks[repo]?[pr.number]
        if known != issue { tasks[repo, default: [:]][pr.number] = issue }
        let snapshot = project
        lock.unlock()
        if known != issue, let (items, at) = snapshot { saveBoard(items, at: at) }
    }

    /// The task a pull request's work is for, if known.
    func task(repo: String, pull: Int) -> Int? {
        lock.lock(); defer { lock.unlock() }
        return tasks[repo]?[pull]
    }
    /// The pull requests known to work on a task.
    func pulls(repo: String, task: Int) -> [Int] {
        lock.lock(); defer { lock.unlock() }
        return (tasks[repo] ?? [:]).filter { $0.value == task }.map(\.key).sorted()
    }
    /// Git history names pull requests; on the floor a crate is its task where one is known.
    private func asTasks(_ numbers: [Int], repo: String) -> [Int] {
        var out: [Int] = []
        for n in numbers { let t = tasks[repo]?[n] ?? n; if !out.contains(t) { out.append(t) } }
        return out
    }
    /// A repository's name just learned: written down with the board so the next launch starts knowing it.
    private func learned(owner: String, repoRoot: String) {
        lock.lock(); owners[repoRoot] = owner; lock.unlock()
        if let (items, at) = project { saveBoard(items, at: at) }
    }

    func projectItems() -> [ProjectItem]? { lock.lock(); defer { lock.unlock() }; return project?.0 }
    func projectFetchedAt() -> Date? { lock.lock(); defer { lock.unlock() }; return project?.1 }

    /// Items whose Status changed since the previous read, each returned once.
    func takeProjectMoves() -> [(item: ProjectItem, from: String?)] {
        lock.lock(); defer { lock.unlock() }
        let out = projectMoves; projectMoves = []; return out
    }

    /// One read of the whole board: every issue, its status, its assignees and linked pull requests.
    func refreshProject(owner: String, number: Int) {
        if frozen { return }
        lock.lock()
        if Date() < holdUntil { trace("project held until \(holdUntil)"); lock.unlock(); return }
        // The whole board on the slow cadence, as the backstop; `refreshProjectDelta` is the pace.
        if let (_, at) = project, Date().timeIntervalSince(at) < interval { lock.unlock(); return }
        if inFlight.contains("project") { lock.unlock(); return }
        inFlight.insert("project")
        lock.unlock()
        trace("ask project (whole board)")
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
                    content { ... on Issue { number title url state repository { name } assignees(first: 5) { nodes { login } }
                      closedByPullRequestsReferences(first: 5) { nodes { url state } } } } } } } } }
                """
                guard let out = run(["gh", "api", "graphql", "-f", "query=" + query], cwd: FileManager.default.homeDirectoryForCurrentUser.path),
                      let obj = try? JSONSerialization.jsonObject(with: out) as? [String: Any],
                      let itemsObj = ((obj["data"] as? [String: Any])?["organization"] as? [String: Any]).flatMap({ $0["projectV2"] as? [String: Any] })?["items"] as? [String: Any],
                      let nodes = itemsObj["nodes"] as? [[String: Any]] else { trace("project read failed at page \(cursor)"); return }
                for o in nodes {
                    guard let content = o["content"] as? [String: Any], let n = content["number"] as? Int,
                          let repo = (content["repository"] as? [String: Any])?["name"] as? String else { continue }
                    let status = (o["fieldValueByName"] as? [String: Any])?["name"] as? String ?? ""
                    let assignees = ((content["assignees"] as? [String: Any])?["nodes"] as? [[String: Any]] ?? []).compactMap { $0["login"] as? String }
                    let prs = ((content["closedByPullRequestsReferences"] as? [String: Any])?["nodes"] as? [[String: Any]] ?? [])
                        .filter { $0["state"] as? String == "OPEN" }.compactMap { $0["url"] as? String }
                    items.append(ProjectItem(repo: repo, number: n, title: content["title"] as? String ?? "", status: status, assignees: assignees,
                                             prURLs: prs, url: content["url"] as? String ?? "", updatedAt: (o["updatedAt"] as? String).flatMap(iso.date(from:)), state: content["state"] as? String ?? "OPEN"))
                }
                let page = itemsObj["pageInfo"] as? [String: Any]
                guard page?["hasNextPage"] as? Bool == true, let end = page?["endCursor"] as? String else { break }
                cursor = "\"\(end)\""
            }
            adoptProject(items, at: Date())
        }
    }

    /// When the delta was last asked, and the newest item time it has seen: the next ask starts there.
    private var deltaAt = Date.distantPast
    private var deltaSince: Date?

    /// The board's changes only: items updated since the last look, by search, every twenty seconds. A
    /// board grows, Shipped most of all, and the whole of it is read only as a backstop; what moved
    /// in the last while is a handful of items and one small query. Each moved item's linked pull
    /// requests are then expected to change, and asked.
    /// Which hundred of the not-shipped items the next delta asks by number.
    private var deltaPage = 0

    func refreshProjectDelta(owner: String, number: Int) {
        if frozen { return }
        lock.lock()
        guard let (items, at) = project else { lock.unlock(); return }   // nothing to add to yet: the whole read comes first
        if Date() < holdUntil { lock.unlock(); return }
        if Date().timeIntervalSince(deltaAt) < gate("projectDelta", base: 20) { lock.unlock(); return }
        if inFlight.contains("projectDelta") { lock.unlock(); return }
        inFlight.insert("projectDelta")
        deltaAt = Date()
        // From the newest change we know of, less a minute for the search index to catch up.
        let since = (deltaSince ?? items.compactMap(\.updatedAt).max() ?? at).addingTimeInterval(-60)
        lock.unlock()
        let iso = ISO8601DateFormatter()
        trace("ask project delta since \(iso.string(from: since))")
        queue.async { [self] in
            defer { lock.lock(); inFlight.remove("projectDelta"); lock.unlock() }
            let query = """
            { search(query: "project:\(owner)/\(number) updated:>=\(iso.string(from: since))", type: ISSUE, first: 50) { nodes { ... on Issue {
              number title url state repository { name } assignees(first: 5) { nodes { login } }
              closedByPullRequestsReferences(first: 5) { nodes { url state } }
              projectItems(first: 5) { nodes { updatedAt project { number } fieldValueByName(name: "Status") { ... on ProjectV2ItemFieldSingleSelectValue { name } } } } } } } }
            """
            var nodes: [[String: Any]] = []
            if let out = run(["gh", "api", "graphql", "-f", "query=" + query], cwd: FileManager.default.homeDirectoryForCurrentUser.path),
               let obj = try? JSONSerialization.jsonObject(with: out) as? [String: Any],
               let found = ((obj["data"] as? [String: Any])?["search"] as? [String: Any])?["nodes"] as? [[String: Any]] { nodes += found }
            // A move on the board does not touch the issue's own timestamp, so the search above never
            // sees one. The items that can still move, everything not shipped, are asked by number,
            // a hundred at a time, round and round: a move shows within a round.
            let shipped = ConfigStore.shared.current.statuses.shipped
            let live = items.filter { $0.status != shipped }.sorted { ($0.repo, $0.number) < ($1.repo, $1.number) }
            if !live.isEmpty {
                let page = 100
                let start = min(deltaPage * page, max(0, live.count - 1)) / page * page
                deltaPage = (start / page + 1) * page < live.count ? start / page + 1 : 0
                let batch = live[start..<min(live.count, start + page)]
                let fields = """
                number title url repository { name } assignees(first: 5) { nodes { login } }
                closedByPullRequestsReferences(first: 5) { nodes { url state } }
                projectItems(first: 5) { nodes { updatedAt project { number } fieldValueByName(name: "Status") { ... on ProjectV2ItemFieldSingleSelectValue { name } } } }
                """
                let parts = batch.enumerated().map { i, it in
                    "i\(i): repository(owner: \"\(owner)\", name: \"\(it.repo)\") { issue(number: \(it.number)) { \(fields) } }"
                }
                trace("ask project items \(batch.count) of \(live.count) not shipped")
                if let out = run(["gh", "api", "graphql", "-f", "query={ " + parts.joined(separator: " ") + " }"], cwd: FileManager.default.homeDirectoryForCurrentUser.path),
                   let obj = try? JSONSerialization.jsonObject(with: out) as? [String: Any], let data = obj["data"] as? [String: Any] {
                    for (_, v) in data { if let issue = (v as? [String: Any])?["issue"] as? [String: Any] { nodes.append(issue) } }
                }
            }
            var fresh: [ProjectItem] = []
            for content in nodes {
                guard let n = content["number"] as? Int, let repo = (content["repository"] as? [String: Any])?["name"] as? String,
                      let pis = (content["projectItems"] as? [String: Any])?["nodes"] as? [[String: Any]],
                      let mine = pis.first(where: { ($0["project"] as? [String: Any])?["number"] as? Int == number }) else { continue }
                let status = (mine["fieldValueByName"] as? [String: Any])?["name"] as? String ?? ""
                let assignees = ((content["assignees"] as? [String: Any])?["nodes"] as? [[String: Any]] ?? []).compactMap { $0["login"] as? String }
                let prs = ((content["closedByPullRequestsReferences"] as? [String: Any])?["nodes"] as? [[String: Any]] ?? [])
                    .filter { $0["state"] as? String == "OPEN" }.compactMap { $0["url"] as? String }
                fresh.append(ProjectItem(repo: repo, number: n, title: content["title"] as? String ?? "", status: status, assignees: assignees,
                                         prURLs: prs, url: content["url"] as? String ?? "", updatedAt: (mine["updatedAt"] as? String).flatMap(iso.date(from:)), state: content["state"] as? String ?? "OPEN"))
            }
            lock.lock()
            guard let (current, _) = project else { lock.unlock(); return }
            var merged = current
            var moved: [(ProjectItem, String?)] = []
            for f in fresh {
                if let i = merged.firstIndex(where: { $0.repo == f.repo && $0.number == f.number }) {
                    if merged[i] != f { if merged[i].status != f.status { moved.append((f, merged[i].status)) }; merged[i] = f }
                } else { merged.append(f); moved.append((f, nil)) }
            }
            if let newest = fresh.compactMap(\.updatedAt).max() { deltaSince = max(deltaSince ?? .distantPast, newest) }
            let changed = merged != current
            if changed { project = (merged, Date()); projectMoves += moved }
            for it in fresh { for url in it.prURLs { if let n = Int(url.split(separator: "/").last ?? "") { tasks[it.repo, default: [:]][n] = it.number } } }
            lock.unlock()
            trace("project delta: \(fresh.count) item(s), \(moved.count) moved")
            if changed {
                saveBoard(merged, at: Date())
                // Each moved item's pull requests are what change next: ask them soon.
                for (it, _) in moved { for url in it.prURLs { if let n = Int(url.split(separator: "/").last ?? "") { expect("pull#:\(it.repo)#\(n)", for: 120, every: 15) } } }
                DispatchQueue.main.async { self.onUpdate?() }
            }
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
        if changed { saveBoard(items, at: at); DispatchQueue.main.async { self.onUpdate?() } }
    }
    private var pendingLaunches: [(repoRoot: String, pr: ReleasePR)] = []
    private var stateChanges: [(branch: String, pr: PullRequest, previous: PullRequest?)] = []
    private var feeds: [String: ([FeedEvent], Date)] = [:]
    private var me: String?

    /// Open release pull requests for a repository, or nil if not fetched yet.
    func openReleases(repoRoot: String) -> [ReleasePR]? {
        lock.lock(); defer { lock.unlock() }
        return releases[repoRoot]?.0.filter { $0.state == "OPEN" }
    }

    /// Every release pull request a repository has answered with, whatever its state.
    func releases(repoRoot: String) -> [ReleasePR]? {
        lock.lock(); defer { lock.unlock() }
        return releases[repoRoot]?.0
    }

    /// Whether one of the repository's workflows, as the trunk has them, deploys on a push to the trunk.
    private func workflowsDeploy(onPushTo trunk: String, repoRoot: String) -> Bool {
        let ref = run(["git", "rev-parse", "--verify", "-q", "origin/\(trunk)"], cwd: repoRoot) != nil ? "origin/\(trunk)" : "HEAD"
        guard let listing = run(["git", "ls-tree", "--name-only", ref, ".github/workflows/"], cwd: repoRoot),
              let names = String(data: listing, encoding: .utf8) else { return false }
        let deployWords = ["deploy", "serverless", "flyctl", "vercel", "railway", "heroku", "kubectl", "helm upgrade", "docker push", "gcloud", "cdk deploy"]
        for path in names.split(separator: "\n") where path.hasSuffix(".yml") || path.hasSuffix(".yaml") {
            guard let data = run(["git", "show", "\(ref):\(path)"], cwd: repoRoot), let text = String(data: data, encoding: .utf8)?.lowercased() else { continue }
            let onPush = text.contains("push:") && text.range(of: "branches:\\s*\\[?[^\\]\\n]*\\b\(NSRegularExpression.escapedPattern(for: trunk.lowercased()))\\b", options: .regularExpression) != nil
            if onPush, deployWords.contains(where: { text.contains($0) }) { return true }
        }
        return false
    }

    /// The repository's pipeline as its branches say, or the settings' names until they have been read.
    func pipeline(repoRoot: String) -> Pipeline {
        lock.lock(); defer { lock.unlock() }
        return pipelines[repoRoot] ?? .configured
    }

    /// Release pull requests that merged since the last poll, each returned once.
    /// A release merged that the scene has not launched yet: the deck must keep its crates for it.
    func hasPendingLaunch(repoRoot: String) -> Bool { lock.lock(); defer { lock.unlock() }; return pendingLaunches.contains { $0.repoRoot == repoRoot } }

    func takeLaunches() -> [(repoRoot: String, pr: ReleasePR)] {
        lock.lock(); defer { lock.unlock() }
        let out = pendingLaunches; pendingLaunches = []; return out
    }

    /// Task pull requests whose state changed since the last poll, each returned once.
    func takeStateChanges() -> [(branch: String, pr: PullRequest, previous: PullRequest?)] {
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

    /// The feed's ETag per repository: an unchanged feed answers 304, which costs nothing.
    private var feedETags: [String: String] = [:]

    /// The repository's activity feed: everyone's pushes, pull requests, reviews and branches. Once a
    /// minute, the pace GitHub asks for, on a conditional request so a quiet repository costs nothing.
    /// It is also the doorbell: a pull request opened, merged or closed in it, or a push, has the
    /// pull request itself asked right away and for a while after.
    func refreshFeed(repoRoot: String) {
        if frozen { return }
        lock.lock()
        if Date() < holdUntil { lock.unlock(); return }
        if let (_, at) = feeds[repoRoot], Date().timeIntervalSince(at) < gate("feed:" + repoRoot, base: 60) { lock.unlock(); return }
        if inFlight.contains("f:" + repoRoot) { lock.unlock(); return }
        inFlight.insert("f:" + repoRoot)
        lock.unlock()
        trace("ask feed \(repoRoot)")
        queue.async { [self] in
            defer { lock.lock(); inFlight.remove("f:" + repoRoot); lock.unlock() }
            if me == nil, let out = run(["gh", "api", "user", "--jq", ".login"], cwd: repoRoot),
               let login = String(data: out, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !login.isEmpty {
                lock.lock(); me = login; lock.unlock()
            }
            var owner = nameWithOwner(repoRoot: repoRoot)
            if owner == nil, let out = run(["gh", "repo", "view", "--json", "nameWithOwner"], cwd: repoRoot),
               let obj = try? JSONSerialization.jsonObject(with: out) as? [String: Any], let n = obj["nameWithOwner"] as? String {
                learned(owner: n, repoRoot: repoRoot)
                owner = n
            }
            guard let owner else { return }
            let iso = ISO8601DateFormatter()
            var events: [FeedEvent] = []
            lock.lock(); let etag = feedETags[repoRoot]; lock.unlock()
            for page in 1...2 {
                let arr: [[String: Any]]
                if page == 1 {
                    // The first page carries the ETag: nothing new means a 304 and the answer stands.
                    var args = ["gh", "api", "-i", "repos/\(owner)/events?per_page=100&page=1"]
                    if let etag { args += ["-H", "If-None-Match: \(etag)"] }
                    // A failed call is not an empty feed: what was known stands until the next ask.
                    guard let (_, raw) = runRaw(args, cwd: repoRoot), let (status, headers, body) = GitHubResolver.split(raw) else { return }
                    if status == 304 {
                        trace("feed \(repoRoot) unchanged (304)")
                        lock.lock(); if let old = feeds[repoRoot] { feeds[repoRoot] = (old.0, Date()) }; lock.unlock()
                        return
                    }
                    guard status == 200, let parsed = try? JSONSerialization.jsonObject(with: body) as? [[String: Any]] else { return }
                    if let tag = headers["etag"] { lock.lock(); feedETags[repoRoot] = tag; lock.unlock() }
                    arr = parsed
                } else {
                    guard let out = run(["gh", "api", "repos/\(owner)/events?per_page=100&page=\(page)"], cwd: repoRoot),
                          let parsed = try? JSONSerialization.jsonObject(with: out) as? [[String: Any]] else { break }
                    arr = parsed
                }
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
            let known = feeds[repoRoot]?.0
            let changed = known != events
            feeds[repoRoot] = (events, Date())
            lock.unlock()
            // The doorbell: what the feed has that it did not have last time names what to ask about.
            if let known {
                let newest = known.map(\.at).max() ?? .distantPast
                for e in events where e.at > newest {
                    switch e.kind {
                    case "pr_open", "pr_merge", "pr_close":
                        expect("openPRs:" + repoRoot, for: 120, every: 15)
                        if let n = e.prNumber { expect("pull#:" + repoRoot + "#\(n)", for: 120, every: 15) }
                        if let b = e.branch { expect("pull:" + repoRoot + "@" + b, for: 120, every: 15) }
                        if e.kind == "pr_merge" { expect("releases:" + repoRoot, for: 300, every: 30); expect("projectDelta", for: 120, every: 10) }
                    case "push":
                        if let b = e.branch { expect("pull:" + repoRoot + "@" + b, for: 180, every: 30) }   // checks will run
                    case "release":
                        expect("releases:" + repoRoot, for: 120, every: 15)
                    default: break
                    }
                }
            }
            if changed { DispatchQueue.main.async { self.onUpdate?() } }
        }
    }

    /// `gh api -i` output split into the status, the headers (lower-cased names) and the body.
    private static func split(_ raw: Data) -> (Int, [String: String], Data)? {
        guard let sep = raw.range(of: Data("\r\n\r\n".utf8)) ?? raw.range(of: Data("\n\n".utf8)) else { return nil }
        guard let head = String(data: raw[..<sep.lowerBound], encoding: .utf8) else { return nil }
        let lines = head.split(whereSeparator: { $0 == "\n" || $0 == "\r\n" }).map(String.init)
        guard let first = lines.first, let status = Int(first.split(separator: " ").dropFirst().first ?? "") else { return nil }
        var headers: [String: String] = [:]
        for l in lines.dropFirst() {
            guard let c = l.firstIndex(of: ":") else { continue }
            headers[l[..<c].lowercased()] = l[l.index(after: c)...].trimmingCharacters(in: .whitespaces)
        }
        return (status, headers, raw[sep.upperBound...])
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
        if frozen { return }
        lock.lock()
        if let (_, at) = releases[repoRoot], Date().timeIntervalSince(at) < gate("releases:" + repoRoot, base: interval) { lock.unlock(); return }
        if inFlight.contains("r:" + repoRoot) { lock.unlock(); return }
        inFlight.insert("r:" + repoRoot)
        lock.unlock()
        trace("ask releases \(repoRoot)")
        queue.async { [self] in
            var found: [ReleasePR] = []
            let cfg = ConfigStore.shared.current
            // Which of the configured branches this repository actually has.
            var remoteBranches = Set<String>()
            if let out = run(["git", "branch", "-r", "--format=%(refname:short)"], cwd: repoRoot), let text = String(data: out, encoding: .utf8) {
                for line in text.split(separator: "\n") { remoteBranches.insert(line.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "origin/", with: "")) }
            }
            // This repository's own pipeline: its file, else its release history, else its branch names.
            // History and file are asked at most once an hour; the branch list is read every time.
            lock.lock(); let cached = pipelines[repoRoot]; let checked = pipelineCheckedAt[repoRoot]; lock.unlock()
            let pipe: Pipeline
            if let cached, let checked, Date().timeIntervalSince(checked) < 3600, cached.source != "settings" {
                pipe = cached
            } else {
                var merges: [PipelineDetection.Merge] = []
                var answered = false
                if let out = run(["gh", "pr", "list", "--state", "merged", "--limit", "100", "--json", "baseRefName,headRefName"], cwd: repoRoot),
                   let arr = try? JSONSerialization.jsonObject(with: out) as? [[String: Any]] {
                    answered = true
                    merges = arr.compactMap { o in
                        guard let b = o["baseRefName"] as? String, let h = o["headRefName"] as? String else { return nil }
                        return PipelineDetection.Merge(base: b, head: h)
                    }
                }
                // A missing file is a failed call: no file.
                let file = run(["gh", "api", "-H", "Accept: application/vnd.github.raw+json", "repos/{owner}/{repo}/contents/.github/rumkapsel.json"], cwd: repoRoot)
                    .flatMap { try? JSONDecoder().decode(ReleaseFile.self, from: $0) }
                let names = (cfg.trunkBranch, cfg.stagingBranch, cfg.productionBranch)
                var detected = PipelineDetection.detect(branches: remoteBranches, merges: merges, file: file, names: names)
                // No releases found: a workflow that deploys on every push to the trunk means every merge ships.
                if detected.production.isEmpty, file?.ship == nil, workflowsDeploy(onPushTo: detected.trunk, repoRoot: repoRoot) {
                    detected = PipelineDetection.detect(branches: remoteBranches, merges: merges, file: file, names: names, deploysOnPush: true)
                }
                pipe = detected
                if answered { lock.lock(); pipelineCheckedAt[repoRoot] = Date(); lock.unlock() }
            }
            let trunk = pipe.trunk, stagingBranch = pipe.staging, productionBranch = pipe.production
            let bases = [stagingBranch, productionBranch].filter { !$0.isEmpty }
            func isReleaseHead(_ head: String) -> Bool { pipe.isReleaseHead(head) }
            for base in bases {
                guard let out = run(["gh", "pr", "list", "--base", base, "--state", "all", "--limit", "5",
                                     "--json", "number,title,baseRefName,headRefName,state,url,labels,mergedAt"], cwd: repoRoot),
                      let arr = try? JSONSerialization.jsonObject(with: out) as? [[String: Any]] else { continue }
                for o in arr {
                    let head = o["headRefName"] as? String ?? ""
                    guard isReleaseHead(head) else { continue }
                    let labels = (o["labels"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
                    found.append(ReleasePR(number: o["number"] as? Int ?? 0, title: o["title"] as? String ?? "", base: base,
                                           head: head, state: o["state"] as? String ?? "", url: o["url"] as? String ?? "", labels: labels,
                                           mergedAt: (o["mergedAt"] as? String).flatMap(ISO8601DateFormatter().date(from:)),
                                           production: base == productionBranch, staging: !stagingBranch.isEmpty && base == stagingBranch))
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
                _ = run(["git", "fetch", "-q", "origin", trunk, stagingBranch, productionBranch], cwd: repoRoot)
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
            // No staging: what the trunk has that production has not is waiting in storage, whatever route the
            // release takes to production, a release branch included.
            if hasPipeline, !exact, stagingBranch.isEmpty, !productionBranch.isEmpty {
                _ = run(["git", "fetch", "-q", "origin", trunk, productionBranch], cwd: repoRoot)
                if let storage = prNumbers("origin/\(productionBranch)..origin/\(trunk)") {
                    let releaseNumbers = Set(found.map(\.number))
                    newCargo.storageNumbers = storage.filter { !releaseNumbers.contains($0) }
                    newCargo.storage = newCargo.storageNumbers.count
                    exact = true
                }
            }
            if hasPipeline, !exact, let out = run(["gh", "pr", "list", "--base", trunk, "--state", "merged", "--limit", "80", "--json", "number,mergedAt,author"], cwd: repoRoot),
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
            let pipelineChanged = pipelines[repoRoot] != pipe
            let changed = previous != found || cargo[repoRoot] != newCargo || pipelineChanged
            pipelines[repoRoot] = pipe
            cargo[repoRoot] = newCargo
            releases[repoRoot] = (found, Date())
            inFlight.remove("r:" + repoRoot)
            lock.unlock()
            if pipelineChanged {
                trace("pipeline \(repoRoot): \(pipe.trunk) → \(pipe.staging.isEmpty ? "-" : pipe.staging) → \(pipe.production.isEmpty ? "-" : pipe.production) · \(pipe.source): \(pipe.why)")
            }
            if changed { DispatchQueue.main.async { self.onUpdate?() } }
        }
    }

    private let queue = DispatchQueue(label: "rumkapsel.github", qos: .utility, attributes: .concurrent)

    // MARK: expecting a change

    /// Something is expected to change soon at one key: a pull request just opened here, a push whose
    /// checks will run, an issue the board just moved, a merge seen in the feed. For a while that key
    /// is asked every few seconds instead of on the slow cadence. Keys: "openPRs:<root>",
    /// "pull:<root>@<branch>", "pull#:<root>#<n>", "releases:<root>", "feed:<root>", "projectDelta".
    private var expected: [String: (until: Date, every: TimeInterval)] = [:]

    func expect(_ key: String, for seconds: TimeInterval = 120, every: TimeInterval = 15) {
        lock.lock(); defer { lock.unlock() }
        let until = Date().addingTimeInterval(seconds)
        if let e = expected[key], e.until > until, e.every <= every { return }
        expected[key] = (until, every)
        trace("expect \(key) every \(Int(every))s for \(Int(seconds))s")
    }

    /// How long an answer at this key stays fresh: the burst's pace while one is expected, else the base.
    private func gate(_ key: String, base: TimeInterval) -> TimeInterval {
        if let e = expected[key] {
            if Date() < e.until { return e.every }
            expected[key] = nil
        }
        return base
    }

    /// What the poller is doing, on stderr, when GITHUB_DIAG is set or `--github-diag` runs.
    static var diag = ProcessInfo.processInfo.environment["GITHUB_DIAG"] != nil
    private func trace(_ text: String) {
        StationLog.write("github", text)
        guard GitHubResolver.diag else { return }
        FileHandle.standardError.write("GH \(ISO8601DateFormatter().string(from: Date())) \(text)\n".data(using: .utf8)!)
    }
    private var pulls: [String: (PullRequest?, Date)] = [:]
    private var commits: [String: (Int, Date)] = [:]
    private var pushed: [String: Bool] = [:]
    private var dirty: [String: Int] = [:]
    private var inFlight = Set<String>()
    private let lock = NSLock()
    var onUpdate: (() -> Void)?

    func pull(branch: String, repoRoot: String) -> PullRequest? {
        lock.lock(); defer { lock.unlock() }
        return pulls[repoRoot + "@" + branch]?.0
    }

    /// Whether the branch's pull request has been asked for and answered at all, even with "none".
    func pullAnswered(branch: String, repoRoot: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return pulls[repoRoot + "@" + branch] != nil
    }

    // MARK: a pull request by number

    /// Pull requests asked for by number, by "root#number": the authority on whether one merged or
    /// closed once it has left the open list, when the branch it came from is not known for sure.
    private var pullsByNumber: [String: (PullRequest?, Date)] = [:]

    func pull(number: Int, repoRoot: String) -> PullRequest? {
        lock.lock(); defer { lock.unlock() }
        return pullsByNumber[repoRoot + "#\(number)"]?.0
    }
    func pullAnswered(number: Int, repoRoot: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return pullsByNumber[repoRoot + "#\(number)"] != nil
    }

    /// Asks GitHub for one pull request by number. A failed call keeps what was known.
    func refresh(pull number: Int, repoRoot: String) {
        if frozen { return }
        let key = repoRoot + "#\(number)"
        lock.lock()
        if let (_, at) = pullsByNumber[key], Date().timeIntervalSince(at) < gate("pull#:" + key, base: interval) { lock.unlock(); return }
        if inFlight.contains(key) { lock.unlock(); return }
        inFlight.insert(key)
        lock.unlock()
        trace("ask pull \(key)")
        queue.async { [self] in
            defer { lock.lock(); inFlight.remove(key); lock.unlock() }
            guard let out = run(["gh", "pr", "view", "\(number)", "--json", "number,title,state,reviewDecision,isDraft,url,closingIssuesReferences"], cwd: repoRoot),
                  let o = try? JSONSerialization.jsonObject(with: out) as? [String: Any] else { return }
            var pr = PullRequest(number: o["number"] as? Int ?? number, title: o["title"] as? String ?? "",
                                 state: o["state"] as? String ?? "", reviewDecision: o["reviewDecision"] as? String ?? "",
                                 isDraft: o["isDraft"] as? Bool ?? false, url: o["url"] as? String ?? "")
            pr.closes = GitHubResolver.closes(o)
            lock.lock(); pullsByNumber[key] = (pr, Date()); lock.unlock()
            noteTask(pr, repoRoot: repoRoot)
            DispatchQueue.main.async { self.onUpdate?() }
        }
    }

    /// The simulator's answer for a pull request asked by number.
    func inject(pull pr: PullRequest, number: Int, repoRoot: String) {
        guard frozen else { return }
        lock.lock(); pullsByNumber[repoRoot + "#\(number)"] = (pr, Date()); lock.unlock()
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
        if frozen { return }
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
        if frozen { return }
        let key = repoRoot + "@" + branch
        lock.lock()
        if let (_, at) = pulls[key], Date().timeIntervalSince(at) < gate("pull:" + key, base: interval) { lock.unlock(); return }
        if inFlight.contains(key) { lock.unlock(); return }
        inFlight.insert(key)
        lock.unlock()
        trace("ask pull \(key)")

        queue.async { [self] in
            if nameWithOwner(repoRoot: repoRoot) == nil,
               let out = run(["gh", "repo", "view", "--json", "nameWithOwner"], cwd: repoRoot),
               let obj = try? JSONSerialization.jsonObject(with: out) as? [String: Any],
               let n = obj["nameWithOwner"] as? String {
                learned(owner: n, repoRoot: repoRoot)
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
                pr.closes = GitHubResolver.closes(o)
                noteTask(pr, repoRoot: repoRoot)
                return pr
            }
            let fields = "number,title,state,reviewDecision,isDraft,url,statusCheckRollup,closingIssuesReferences"
            var answered = false   // a failed call is not "no pull request": keep what we knew
            if let out = run(["gh", "pr", "list", "--head", branch, "--state", "open", "--limit", "1", "--json", fields], cwd: repoRoot),
               let arr = try? JSONSerialization.jsonObject(with: out) as? [[String: Any]], let o = arr.first {
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
            if changed, let pr, let old = pulls[key] { stateChanges.append((branch, pr, old.0)) }
            pulls[key] = (pr, Date())
            // Checks still running, or approved and open: this one is about to change; keep asking.
            if let pr, pr.state == "OPEN", pr.checks == "pending" || pr.reviewDecision == "APPROVED" {
                expected["pull:" + key] = (Date().addingTimeInterval(180), 30)
            }
            inFlight.remove(key)
            lock.unlock()
            if changed { DispatchQueue.main.async { self.onUpdate?() } }
        }
    }

    private func run(_ args: [String], cwd: String) -> Data? {
        guard let (status, data) = runRaw(args, cwd: cwd), status == 0 else { return nil }
        return data
    }

    /// The command's exit status and output, whatever the status: `gh api -i` exits non-zero on a 304
    /// and still prints the headers, which is the answer.
    private func runRaw(_ args: [String], cwd: String) -> (Int32, Data)? {
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
        return (p.terminationStatus, data)
    }
}

// MARK: injection

/// What the simulator writes into the resolver in place of an answer from GitHub. Every one of these
/// is a no-op unless `frozen` is set, so nothing outside the simulator can push facts in here.
extension GitHubResolver {
    /// Forgets every cached answer, including the board read that came off disk at launch.
    func simulationReset() {
        guard frozen else { return }
        lock.lock()
        openPRs = [:]; feeds = [:]; releases = [:]; cargo = [:]; pulls = [:]; commits = [:]
        pushed = [:]; dirty = [:]; owners = [:]; project = nil
        projectMoves = []; pendingLaunches = []; stateChanges = []; me = nil
        lock.unlock()
    }

    func inject(login: String) {
        guard frozen else { return }
        lock.lock(); me = login; lock.unlock()
    }

    func inject(owner nameWithOwner: String, for repoRoot: String) {
        guard frozen else { return }
        lock.lock(); owners[repoRoot] = nameWithOwner; lock.unlock()
    }

    func inject(openPRs prs: [OpenPR], for repoRoot: String) {
        guard frozen else { return }
        lock.lock(); openPRs[repoRoot] = (prs, Date()); lock.unlock()
        notify()
    }

    /// A branch's pull request. `changed` puts it in the queue `takeStateChanges` drains, the way a
    /// real poll would when the state moved.
    func inject(pull pr: PullRequest?, for branch: String, repoRoot: String, changed: Bool = true) {
        guard frozen else { return }
        lock.lock()
        let previous = pulls[repoRoot + "@" + branch]?.0
        pulls[repoRoot + "@" + branch] = (pr, Date())
        if changed, let pr { stateChanges.append((branch, pr, previous)) }
        lock.unlock()
        notify()
    }

    func inject(feed events: [FeedEvent], for repoRoot: String) {
        guard frozen else { return }
        lock.lock(); feeds[repoRoot] = (events, Date()); lock.unlock()
        notify()
    }

    func inject(cargo c: Cargo, for repoRoot: String) {
        guard frozen else { return }
        lock.lock(); cargo[repoRoot] = c; lock.unlock()
        notify()
    }

    /// A repository's pipeline, in place of the one its branches would have said.
    func inject(pipeline p: Pipeline, for repoRoot: String) {
        guard frozen else { return }
        lock.lock(); pipelines[repoRoot] = p; lock.unlock()
        notify()
    }

    /// Release pull requests for a repository. Anything in `merged` is queued for `takeLaunches`.
    func inject(releases rs: [ReleasePR], for repoRoot: String, merged: [ReleasePR] = []) {
        guard frozen else { return }
        lock.lock()
        releases[repoRoot] = (rs, Date())
        for pr in merged { pendingLaunches.append((repoRoot, pr)) }
        lock.unlock()
        notify()
    }

    /// The board, without the freshness check `adoptProject` applies to a peer's copy.
    func inject(project items: [ProjectItem], at: Date = Date(), quiet: Bool = false) {
        guard frozen else { return }
        lock.lock()
        if !quiet, let previous = project?.0 {
            let before = Dictionary(previous.map { ("\($0.repo)#\($0.number)", $0.status) }, uniquingKeysWith: { a, _ in a })
            for it in items where before["\(it.repo)#\(it.number)"] != it.status { projectMoves.append((it, before["\(it.repo)#\(it.number)"])) }
        }
        project = (items, at)
        lock.unlock()
        notify()
    }

    func inject(commits n: Int, pushed isPushed: Bool, dirty files: Int = 0, worktree: String) {
        guard frozen else { return }
        lock.lock()
        commits[worktree] = (n, Date()); pushed[worktree] = isPushed; dirty[worktree] = files
        lock.unlock()
        notify()
    }

    private func notify() {
        guard !injectSilently else { return }
        DispatchQueue.main.async { self.onUpdate?() }
    }
}
