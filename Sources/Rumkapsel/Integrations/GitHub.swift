import Foundation

struct PullRequest: Equatable {
    let number: Int
    let title: String
    let state: String
    let reviewDecision: String
    let isDraft: Bool
    let url: String
    var checks: String = ""
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
    let base: String
    let head: String
    let state: String
    let url: String
    let labels: [String]
    let mergedAt: Date?
    var production: Bool? = nil
    var staging: Bool? = nil
    var isProduction: Bool { production ?? (base == ConfigStore.shared.current.productionBranch) }
    var isStaging: Bool {
        if let staging { return staging }
        let name = ConfigStore.shared.current.stagingBranch
        return !name.isEmpty && base == name
    }
    var untested: Bool { labels.contains { $0.lowercased().contains("untested") } }
    var tag = false
    var hotfix = false
}

struct Pipeline: Equatable {
    var trunk: String
    var staging: String
    var production: String
    var releaseBranches: [String] = PipelineDetection.defaultReleaseBranches
    var boardColumns: Bool? = nil
    var source: String = "settings"
    var why: String = ""
    var ship: String = "release"
    var shipsOnMerge: Bool { ship == "merge" }
    var shipsOnTag: Bool { ship == "tag" }
    var shipsAtOnce: Bool { shipsOnMerge || shipsOnTag }
    var hasStaging: Bool { !staging.isEmpty }
    func isReleaseHead(_ head: String) -> Bool {
        head == trunk || (hasStaging && head == staging) || releaseBranches.contains { PipelineDetection.matches(head, $0) }
    }
    static var configured: Pipeline {
        let c = ConfigStore.shared.current
        return Pipeline(trunk: c.trunkBranch, staging: c.stagingBranch, production: c.productionBranch)
    }
}

struct FeedEvent: Equatable, Codable {
    let at: Date
    let actor: String
    let isBot: Bool
    let kind: String
    let branch: String?
    let prNumber: Int?
    let title: String?
    let url: String?
    let detail: String
}

struct ProjectItem: Equatable, Codable {
    let repo: String
    let number: Int
    let title: String
    let status: String
    let assignees: [String]
    let prURLs: [String]
    let url: String
    var updatedAt: Date? = nil
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

final class GitHubResolver {
    static func isBot(_ login: String) -> Bool {
        let l = login.lowercased()
        return l.contains("dependabot") || login.contains("[bot]") || l.hasSuffix("-bot") || l.contains("webhook")
    }

    static func quoted(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    var intervalMinutes = 5
    var frozen = false
    var injectSilently = false
    private var interval: TimeInterval { Double(intervalMinutes) * 60 }
    private var openPRs: [String: ([OpenPR], Date)] = [:]

    var hasAnswers: Bool { lock.lock(); defer { lock.unlock() }; return !openPRs.isEmpty }

    private var answeredLive: Set<String> = []
    func answered(repoRoot: String) -> Bool { lock.lock(); defer { lock.unlock() }; return answeredLive.contains(repoRoot) }
    private var fromCache: Set<String> = []

    func teamOpenPRs(repoRoot: String) -> [OpenPR]? {
        lock.lock(); defer { lock.unlock() }
        return openPRs[repoRoot]?.0
    }

    var holdUntil = Date.distantPast

    private static var cacheURL: URL { AppSupport.root.appendingPathComponent("rumkapsel.github.json") }

    func saveKnowledge(_ roots: [String: String]) {
        var out: [String: Knowledge] = [:]
        for (root, repo) in roots { if let k = knowledge(repoRoot: root, repo: repo) { out[root] = k } }
        guard !out.isEmpty, let json = try? JSONEncoder().encode(out) else { return }
        Fleet.writing.async { try? json.write(to: GitHubResolver.cacheURL) }
    }

    func loadKnowledge() {
        guard let data = try? Data(contentsOf: GitHubResolver.cacheURL),
              let saved = try? JSONDecoder().decode([String: Knowledge].self, from: data) else { return }
        for (root, k) in saved { adopt(k, repoRoot: root) }
        lock.lock(); fromCache.formUnion(saved.keys); lock.unlock()
    }

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
        let remembered = fromCache.remove(repoRoot) != nil
        if !remembered, let (_, at) = openPRs[repoRoot],
           Date().timeIntervalSince(at) < gate("openPRs:" + repoRoot, base: interval) { lock.unlock(); return }
        if inFlight.contains("o:" + repoRoot) { lock.unlock(); return }
        inFlight.insert("o:" + repoRoot)
        lock.unlock()
        trace("ask openPRs \(repoRoot)")
        queue.async { [self] in
            defer { lock.lock(); inFlight.remove("o:" + repoRoot); lock.unlock() }
            let iso = ISO8601DateFormatter()
            var found: [OpenPR] = []
            guard let out = run(["gh", "pr", "list", "--state", "open", "--limit", "40", "--json", "number,title,author,headRefName,url,createdAt,updatedAt"], cwd: repoRoot) else { trace("openPRs \(repoRoot) failed"); return }
            if let arr = try? JSONSerialization.jsonObject(with: out) as? [[String: Any]] {
                let stale = Date().addingTimeInterval(-14 * 24 * 3600)
                for o in arr {
                    if let u = (o["updatedAt"] as? String).flatMap(iso.date(from:)), u < stale { continue }
                    let a = o["author"] as? [String: Any]
                    let login = a?["login"] as? String ?? "?"
                    let isBot = (a?["is_bot"] as? Bool ?? false) || GitHubResolver.isBot(login)
                    found.append(OpenPR(number: o["number"] as? Int ?? 0, title: o["title"] as? String ?? "", author: login, isBot: isBot,
                                        branch: o["headRefName"] as? String ?? "", url: o["url"] as? String ?? "",
                                        createdAt: (o["createdAt"] as? String).flatMap(iso.date(from:)) ?? Date()))
                }
            }
            lock.lock()
            let changed = openPRs[repoRoot]?.0 != found
            openPRs[repoRoot] = (found, Date())
            let first = answeredLive.insert(repoRoot).inserted
            var learned = false
            if let repo = owners[repoRoot].map({ String($0.split(separator: "/").last ?? "") }) {
                for pr in found where !pr.isBot {
                    if note(repo: repo, number: pr.number, title: pr.title, author: pr.author, at: pr.createdAt) { learned = true }
                    if let issue = tasks[repo]?[pr.number] { if note(repo: repo, number: issue, author: pr.author) { learned = true } }
                }
            }
            let board = learned ? project : nil
            lock.unlock()
            if let (items, at) = board { saveBoard(items, at: at) }
            if changed || first { DispatchQueue.main.async { self.onUpdate?() } }
        }
    }

    private var releases: [String: ([ReleasePR], Date)] = [:]
    private var hotfixes: [String: ([ReleasePR], Date)] = [:]
    struct Cargo: Equatable {
        var storage: Int; var deck: Int; var storageNumbers: [Int]; var deckNumbers: [Int]; var clearedNumbers: [Int] = []
        var updated: [Int: Date] = [:]
        var source: Source = .git
        var exact = false
        var at = Date.distantPast
    }
    private var cargo: [String: Cargo] = [:]
    private var pipelines: [String: Pipeline] = [:]
    private var pipelineCheckedAt: [String: Date] = [:]
    private var boardYards: Set<String> = Set(GitHubResolver.loadBoardFile()?.yards ?? [])

    func cargo(repoRoot: String) -> Cargo? {
        lock.lock(); defer { lock.unlock() }
        if ConfigStore.shared.current.project != nil, project != nil, owners[repoRoot] == nil { return nil }
        if let items = project?.0, let owner = owners[repoRoot] {
            let repo = String(owner.split(separator: "/").last ?? "")
            let st = ConfigStore.shared.current.statuses
            let mine = items.filter { $0.repo == repo && !$0.status.isEmpty }
            let decided = pipelines[repoRoot]?.boardColumns
            if decided == nil, mine.contains(where: { [st.storage, st.deck, st.cleared].contains($0.status) }), !boardYards.contains(repo) {
                boardYards.insert(repo)
                if let (all, at) = project { saveBoard(all, at: at) }
            }
            if !mine.isEmpty, decided ?? boardYards.contains(repo) {
            let storage = mine.filter { $0.status == st.storage }.map(\.number).sorted()
            let deck = mine.filter { $0.status == st.deck || $0.status == st.cleared }.map(\.number).sorted()
            let cleared = mine.filter { $0.status == st.cleared }.map(\.number).sorted()
            let updated = Dictionary(mine.compactMap { it in it.updatedAt.map { (it.number, $0) } }, uniquingKeysWith: { a, _ in a })
            return Cargo(storage: storage.count, deck: deck.count, storageNumbers: storage, deckNumbers: deck, clearedNumbers: cleared, updated: updated, source: .board)
            }
        }
        guard var c = cargo[repoRoot] else { return nil }
        if let owner = owners[repoRoot] {
            let repo = String(owner.split(separator: "/").last ?? "")
            c.storage = c.storageNumbers.count; c.deck = c.deckNumbers.count
        }
        return c
    }

    // MARK: project board

    private var project: ([ProjectItem], Date)? = GitHubResolver.loadBoard() { didSet { BoardNumbers.note(project?.0 ?? []) } }
    private var owners: [String: String] = GitHubResolver.loadBoardFile()?.owners ?? [:]
    private var projectMoves: [(item: ProjectItem, from: String?)] = []

    private static var boardURL: URL {
        let dir = AppSupport.root.appendingPathComponent("Rumkapsel", isDirectory: true)
        return dir.appendingPathComponent("board.json")
    }
    private struct SavedBoard: Codable {
        var items: [ProjectItem]; var at: Date; var owners: [String: String]?; var tasks: [String: [String: Int]]?; var yards: [String]?
        var works: [String: [String: WorkNote]]? = nil
    }
    private static func loadBoardFile() -> SavedBoard? {
        guard let data = try? Data(contentsOf: boardURL) else { return nil }
        return try? JSONDecoder().decode(SavedBoard.self, from: data)
    }
    private static func loadBoard() -> ([ProjectItem], Date)? {
        let board = loadBoardFile().map { ($0.items, $0.at) }
        BoardNumbers.note(board?.0 ?? [])
        return board
    }
    private func saveBoard(_ items: [ProjectItem], at: Date) {
        if frozen { return }
        let saved = SavedBoard(items: items, at: at, owners: owners,
                               tasks: tasks.mapValues { Dictionary(uniqueKeysWithValues: $0.map { (String($0.key), $0.value) }) },
                               yards: boardYards.sorted(),
                               works: works.mapValues { Dictionary(uniqueKeysWithValues: $0.sorted { $0.key > $1.key }.prefix(500).map { (String($0.key), $0.value) }) })
        if let data = try? JSONEncoder().encode(saved) { try? data.write(to: GitHubResolver.boardURL) }
    }

    // MARK: tasks

    private var tasks: [String: [Int: Int]] = (GitHubResolver.loadBoardFile()?.tasks ?? [:])
        .mapValues { Dictionary(uniqueKeysWithValues: $0.compactMap { k, v in Int(k).map { ($0, v) } }) }

    // MARK: who and what

    struct WorkNote: Codable, Equatable {
        var title = ""
        var author: String?
        var at: Date?
        var isEmpty: Bool { title.isEmpty && author == nil && at == nil }
    }

    private var works: [String: [Int: WorkNote]] = (GitHubResolver.loadBoardFile()?.works ?? [:])
        .mapValues { Dictionary(uniqueKeysWithValues: $0.compactMap { k, v in Int(k).map { ($0, v) } }) }

    @discardableResult
    private func note(repo: String, number: Int, title: String? = nil, author: String? = nil, at: Date? = nil) -> Bool {
        guard !repo.isEmpty, number > 0 else { return false }
        var w = works[repo]?[number] ?? WorkNote()
        let before = w
        if w.title.isEmpty, let title, !title.isEmpty { w.title = title }
        if w.author == nil, let author, !author.isEmpty, author != "?" { w.author = author }
        if let at, w.at == nil || at < w.at! { w.at = at }
        guard w != before, !w.isEmpty else { return false }
        works[repo, default: [:]][number] = w
        return true
    }

    func work(repo: String, number: Int) -> WorkNote? {
        lock.lock(); defer { lock.unlock() }
        var w = works[repo]?[number] ?? WorkNote()
        if let item = boardItem(repo: repo, number: number) {
            if w.title.isEmpty { w.title = item.title }
            if w.author == nil { w.author = item.assignees.first }
        }
        if w.title.isEmpty || w.author == nil {
            for pull in (tasks[repo] ?? [:]).filter({ $0.value == number }).keys.sorted() {
                guard let p = works[repo]?[pull] else { continue }
                if w.title.isEmpty { w.title = p.title }
                if w.author == nil { w.author = p.author }
                if let a = p.at, w.at == nil || a < w.at! { w.at = a }
            }
        }
        return w.isEmpty ? nil : w
    }

    private var boardIndex: [String: ProjectItem] = [:]
    private var boardIndexAt: Date?
    private func boardItem(repo: String, number: Int) -> ProjectItem? {
        if boardIndexAt != project?.1 {
            boardIndex = Dictionary((project?.0 ?? []).map { ("\($0.repo)#\($0.number)", $0) }, uniquingKeysWith: { a, _ in a })
            boardIndexAt = project?.1
        }
        return boardIndex["\(repo)#\(number)"]
    }

    func isMine(repo: String, number: Int) -> Bool {
        guard let me = myLogin() else { return false }
        return work(repo: repo, number: number)?.author == me
    }

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

    private func noteAuthor(_ o: [String: Any], number: Int, repoRoot: String, issue: Int?) {
        let login = ((o["author"] as? [String: Any])?["login"] as? String) ?? ""
        let at = (o["createdAt"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) }
        lock.lock()
        guard let owner = owners[repoRoot] else { lock.unlock(); return }
        let repo = String(owner.split(separator: "/").last ?? "")
        var learned = note(repo: repo, number: number, title: o["title"] as? String, author: login, at: at)
        if let issue { learned = note(repo: repo, number: issue, author: login) || learned }
        let snapshot = learned ? project : nil
        lock.unlock()
        if let (items, at) = snapshot { saveBoard(items, at: at) }
    }

    func task(repo: String, pull: Int) -> Int? {
        lock.lock(); defer { lock.unlock() }
        return tasks[repo]?[pull]
    }
    func pulls(repo: String, task: Int) -> [Int] {
        lock.lock(); defer { lock.unlock() }
        return (tasks[repo] ?? [:]).filter { $0.value == task }.map(\.key).sorted()
    }
    private func learned(owner: String, repoRoot: String) {
        lock.lock(); owners[repoRoot] = owner; lock.unlock()
        if let (items, at) = project { saveBoard(items, at: at) }
    }

    func projectItems() -> [ProjectItem]? { lock.lock(); defer { lock.unlock() }; return project?.0 }
    func projectFetchedAt() -> Date? { lock.lock(); defer { lock.unlock() }; return project?.1 }

    func takeProjectMoves() -> [(item: ProjectItem, from: String?)] {
        lock.lock(); defer { lock.unlock() }
        let out = projectMoves; projectMoves = []; return out
    }

    func refreshProject(owner: String, number: Int) {
        if frozen { return }
        lock.lock()
        if Date() < holdUntil { trace("project held until \(holdUntil)"); lock.unlock(); return }
        if let (_, at) = project, Date().timeIntervalSince(at) < interval { lock.unlock(); return }
        if inFlight.contains("project") { lock.unlock(); return }
        inFlight.insert("project")
        lock.unlock()
        trace("ask project (whole board)")
        queue.async { [self] in
            defer { lock.lock(); inFlight.remove("project"); lock.unlock() }
            let fieldName = GitHubResolver.quoted(ConfigStore.shared.current.statusField)
            let iso = ISO8601DateFormatter()
            var items: [ProjectItem] = []
            var cursor = "null"
            for _ in 0..<6 {
                let query = """
                { organization(login: "\(owner)") { projectV2(number: \(number)) { items(first: 100, after: \(cursor)) {
                  pageInfo { hasNextPage endCursor }
                  nodes { updatedAt
                    fieldValueByName(name: \(fieldName)) { ... on ProjectV2ItemFieldSingleSelectValue { name } }
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

    private var deltaAt = Date.distantPast
    private var deltaSince: Date?

    private var deltaPage = 0

    func refreshProjectDelta(owner: String, number: Int) {
        if frozen { return }
        lock.lock()
        guard let (items, at) = project else { lock.unlock(); return }
        if Date() < holdUntil { lock.unlock(); return }
        if Date().timeIntervalSince(deltaAt) < gate("projectDelta", base: 20) { lock.unlock(); return }
        if inFlight.contains("projectDelta") { lock.unlock(); return }
        inFlight.insert("projectDelta")
        deltaAt = Date()
        let since = (deltaSince ?? items.compactMap(\.updatedAt).max() ?? at).addingTimeInterval(-60)
        lock.unlock()
        let iso = ISO8601DateFormatter()
        trace("ask project delta since \(iso.string(from: since))")
        queue.async { [self] in
            defer { lock.lock(); inFlight.remove("projectDelta"); lock.unlock() }
            let fieldName = GitHubResolver.quoted(ConfigStore.shared.current.statusField)
            let query = """
            { search(query: "project:\(owner)/\(number) updated:>=\(iso.string(from: since))", type: ISSUE, first: 50) { nodes { ... on Issue {
              number title url state repository { name } assignees(first: 5) { nodes { login } }
              closedByPullRequestsReferences(first: 5) { nodes { url state } }
              projectItems(first: 5) { nodes { updatedAt project { number } fieldValueByName(name: \(fieldName)) { ... on ProjectV2ItemFieldSingleSelectValue { name } } } } } } } }
            """
            var nodes: [[String: Any]] = []
            if let out = run(["gh", "api", "graphql", "-f", "query=" + query], cwd: FileManager.default.homeDirectoryForCurrentUser.path),
               let obj = try? JSONSerialization.jsonObject(with: out) as? [String: Any],
               let found = ((obj["data"] as? [String: Any])?["search"] as? [String: Any])?["nodes"] as? [[String: Any]] { nodes += found }
            let shipped = ConfigStore.shared.current.statuses.shipped
            let live = items.filter { shipped.isEmpty || $0.status != shipped }.sorted { ($0.repo, $0.number) < ($1.repo, $1.number) }
            if !live.isEmpty {
                let page = 100
                let start = min(deltaPage * page, max(0, live.count - 1)) / page * page
                deltaPage = (start / page + 1) * page < live.count ? start / page + 1 : 0
                let batch = live[start..<min(live.count, start + page)]
                let fields = """
                number title url repository { name } assignees(first: 5) { nodes { login } }
                closedByPullRequestsReferences(first: 5) { nodes { url state } }
                projectItems(first: 5) { nodes { updatedAt project { number } fieldValueByName(name: \(fieldName)) { ... on ProjectV2ItemFieldSingleSelectValue { name } } } }
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
                for (it, _) in moved { for url in it.prURLs { if let n = Int(url.split(separator: "/").last ?? "") { expect("pull#:\(it.repo)#\(n)", for: 120, every: 15) } } }
                DispatchQueue.main.async { self.onUpdate?() }
            }
        }
    }

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
    private var pendingHotfixes: [(repoRoot: String, pr: ReleasePR)] = []
    private let http = GitHubHTTP(token: GitHubHTTP.ghToken)
    private var pullsSeen: [String: [Int: String]] = [:]
    private var pullsWatchedAt: [String: Date] = [:]
    private var deployNewest: [String: DeployRun] = [:]
    private var deployUsual: [String: TimeInterval] = [:]
    private var deploysRead: [String: Date] = [:]
    private var deployWatchedSince: [String: Date] = [:]
    private var deployWorkflows: [String: (names: Set<String>, at: Date)] = [:]
    private var pendingDeploys: [(repoRoot: String, production: Bool, change: Deployments.Change, usual: TimeInterval)] = []
    private var stateChanges: [(branch: String, pr: PullRequest, previous: PullRequest?)] = []
    private var feeds: [String: ([FeedEvent], Date)] = [:]
    private var askedWho = false
    private var me: String? = ConfigStore.shared.current.viewerLogin

    func openReleases(repoRoot: String) -> [ReleasePR]? {
        lock.lock(); defer { lock.unlock() }
        return releases[repoRoot]?.0.filter { $0.state == "OPEN" }
    }

    func releases(repoRoot: String) -> [ReleasePR]? {
        lock.lock(); defer { lock.unlock() }
        return releases[repoRoot]?.0
    }

    func hotfixes(repoRoot: String) -> [ReleasePR]? {
        lock.lock(); defer { lock.unlock() }
        return hotfixes[repoRoot]?.0
    }

    func takeHotfixLaunches() -> [(repoRoot: String, pr: ReleasePR)] {
        lock.lock(); defer { lock.unlock() }
        let out = pendingHotfixes; pendingHotfixes = []; return out
    }

    static func tags(repoRoot: String, run: ([String], String) -> Data?) -> [(name: String, at: Date)] {
        _ = run(["git", "fetch", "-q", "--tags", "origin"], repoRoot)
        guard let out = run(["git", "for-each-ref", "--sort=-creatordate", "--count=8",
                             "--format=%(refname:short)|%(creatordate:iso-strict)", "refs/tags"], repoRoot),
              let text = String(data: out, encoding: .utf8) else { return [] }
        let iso = ISO8601DateFormatter()
        let all: [(name: String, at: Date)] = text.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "|", maxSplits: 1)
            guard parts.count == 2, let at = iso.date(from: String(parts[1])) else { return nil }
            return (String(parts[0]), at)
        }
        let versions = all.filter { $0.name.firstMatch(of: #/^v?\d+(\.\d+)*$/#) != nil }
        return versions.isEmpty ? all : versions
    }

    private func workflowsDeploy(onPushTo trunk: String, repoRoot: String) -> Bool {
        let ref = run(["git", "rev-parse", "--verify", "-q", "origin/\(trunk)"], cwd: repoRoot) != nil ? "origin/\(trunk)" : "HEAD"
        guard let listing = run(["git", "ls-tree", "--name-only", ref, ".github/workflows/"], cwd: repoRoot),
              let names = String(data: listing, encoding: .utf8) else { return false }
        for path in names.split(separator: "\n") where path.hasSuffix(".yml") || path.hasSuffix(".yaml") {
            guard let data = run(["git", "show", "\(ref):\(path)"], cwd: repoRoot), let text = String(data: data, encoding: .utf8) else { continue }
            if Deployments.deploys(onPushTo: trunk, workflow: text) { return true }
        }
        return false
    }

    func pipeline(repoRoot: String) -> Pipeline { detectedPipeline(repoRoot: repoRoot).overridden(by: Pipeline.override(forRoot: repoRoot)) }

    func detectedPipeline(repoRoot: String) -> Pipeline {
        lock.lock(); defer { lock.unlock() }
        return pipelines[repoRoot] ?? .configured
    }

    func hasPendingLaunch(repoRoot: String) -> Bool { lock.lock(); defer { lock.unlock() }; return pendingLaunches.contains { $0.repoRoot == repoRoot } }

    func takeLaunches() -> [(repoRoot: String, pr: ReleasePR)] {
        lock.lock(); defer { lock.unlock() }
        let out = pendingLaunches; pendingLaunches = []; return out
    }

    func takeDeploys() -> [(repoRoot: String, production: Bool, change: Deployments.Change, usual: TimeInterval)] {
        lock.lock(); defer { lock.unlock() }
        let out = pendingDeploys; pendingDeploys = []; return out
    }

    func deploys(repoRoot: String) -> [(branch: String, production: Bool, newest: DeployRun?, usual: TimeInterval)] {
        let branches = deployBranches(pipeline(repoRoot: repoRoot))
        lock.lock(); defer { lock.unlock() }
        return branches.map { ($0.branch, $0.production, deployNewest[repoRoot + "|" + $0.branch], deployUsual[repoRoot + "|" + $0.branch] ?? Deployments.fallback) }
    }

    private func deployBranches(_ p: Pipeline) -> [(branch: String, production: Bool)] {
        if p.shipsOnMerge { return [(p.trunk, true)] }
        return [(p.staging, false), (p.production, true)].filter { !$0.branch.isEmpty }
    }

    func refreshDeploys(repoRoot: String) {
        if frozen { return }
        lock.lock()
        let slow = owners[repoRoot] != nil && http.hasToken ? 15 : interval
        if let at = deploysRead[repoRoot], Date().timeIntervalSince(at) < gate("deploys:" + repoRoot, base: slow) { lock.unlock(); return }
        if inFlight.contains("d:" + repoRoot) || pipelines[repoRoot] == nil { lock.unlock(); return }
        inFlight.insert("d:" + repoRoot)
        lock.unlock()
        let p = pipeline(repoRoot: repoRoot)
        queue.async { [self] in
            defer { lock.lock(); inFlight.remove("d:" + repoRoot); deploysRead[repoRoot] = Date(); lock.unlock() }
            var running = false, ended = false
            var all: [DeployRun]
            lock.lock(); let owner = owners[repoRoot]; lock.unlock()
            if let owner, let answer = http.get("repos/\(owner)/actions/runs?event=push&per_page=60") {
                guard let o = try? JSONSerialization.jsonObject(with: answer.data) as? [String: Any],
                      let arr = o["workflow_runs"] as? [[String: Any]] else { return }
                all = arr.compactMap(DeployRun.init(api:))
            } else {
                guard let out = run(["gh", "run", "list", "--event", "push", "--limit", "60",
                                     "--json", "databaseId,workflowName,headBranch,status,conclusion,startedAt,updatedAt,displayTitle"], cwd: repoRoot),
                      let arr = try? JSONSerialization.jsonObject(with: out) as? [[String: Any]] else { return }
                all = arr.compactMap(DeployRun.init(json:))
            }
            for (branch, production) in deployBranches(p) {
                let key = repoRoot + "|" + branch
                let runs = Deployments.deploys(all.filter { $0.branch == branch }, deploying: deployingWorkflows(branch: branch, repoRoot: repoRoot))
                lock.lock()
                if Deployments.isStale(runs, known: deployNewest[key]) { lock.unlock(); trace("deploys \(branch): stale answer, left alone"); continue }
                let first = deployNewest[key] == nil
                if deployWatchedSince[key] == nil { deployWatchedSince[key] = Date() }
                let changes = Deployments.changes(was: deployNewest[key], runs: runs, firstLook: first, at: Date(), watchingSince: deployWatchedSince[key])
                let usual = Deployments.usual(runs)
                deployUsual[key] = usual
                if let newest = runs.first {
                    deployNewest[key] = newest
                    let age = newest.startedAt.map { Date().timeIntervalSince($0) } ?? 0
                    running = running || newest.running && age < max(3 * usual, 1800)
                }
                for c in changes {
                    pendingDeploys.append((repoRoot, production, c, usual))
                    if case .ended = c { ended = true }
                }
                lock.unlock()
                for c in changes { trace("deploy \(branch) \(c)") }
            }
            if running { expect("deploys:" + repoRoot, for: 60, every: 10) }
            else if ended { lock.lock(); expected["deploys:" + repoRoot] = nil; lock.unlock() }
            lock.lock(); let any = !pendingDeploys.isEmpty; lock.unlock()
            if any { DispatchQueue.main.async { self.onUpdate?() } }
        }
    }

    func watchPulls(repoRoot: String) {
        if frozen { return }
        lock.lock()
        guard let owner = owners[repoRoot], Date().timeIntervalSince(pullsWatchedAt[repoRoot] ?? .distantPast) >= 10,
              !inFlight.contains("w:" + repoRoot) else { lock.unlock(); return }
        inFlight.insert("w:" + repoRoot)
        pullsWatchedAt[repoRoot] = Date()
        lock.unlock()
        let p = pipeline(repoRoot: repoRoot)
        queue.async { [self] in
            defer { lock.lock(); inFlight.remove("w:" + repoRoot); lock.unlock() }
            guard let answer = http.get("repos/\(owner)/pulls?state=all&sort=updated&direction=desc&per_page=20"), answer.changed,
                  let arr = try? JSONSerialization.jsonObject(with: answer.data) as? [[String: Any]] else { return }
            lock.lock(); let before = pullsSeen[repoRoot]; lock.unlock()
            var now: [Int: String] = [:]
            for o in arr {
                guard let n = o["number"] as? Int, let updated = o["updated_at"] as? String else { continue }
                now[n] = updated
                guard let before, before[n] != updated else { continue }
                let base = (o["base"] as? [String: Any])?["ref"] as? String ?? ""
                let head = (o["head"] as? [String: Any])?["ref"] as? String ?? ""
                trace("watch: #\(n) moved (\(head) → \(base))")
                expect("openPRs:" + repoRoot, for: 60, every: 5)
                expect("pull#:" + repoRoot + "#\(n)", for: 60, every: 5)
                if !head.isEmpty { expect("pull:" + repoRoot + "@" + head, for: 60, every: 5) }
                if base == p.staging || base == p.production || (o["merged_at"] as? String) != nil {
                    expect("releases:" + repoRoot, for: 60, every: 5)
                    expect("deploys:" + repoRoot, for: Deployments.findWithin, every: 10)
                }
            }
            lock.lock(); pullsSeen[repoRoot] = now; lock.unlock()
        }
    }

    private func deployingWorkflows(branch: String, repoRoot: String) -> Set<String> {
        let key = repoRoot + "|" + branch
        lock.lock(); let cached = deployWorkflows[key]; lock.unlock()
        if let cached, Date().timeIntervalSince(cached.at) < 3600 { return cached.names }
        var names = Set<String>()
        let ref = run(["git", "rev-parse", "--verify", "-q", "origin/\(branch)"], cwd: repoRoot) != nil ? "origin/\(branch)" : "HEAD"
        if let listing = run(["git", "ls-tree", "--name-only", ref, ".github/workflows/"], cwd: repoRoot), let files = String(data: listing, encoding: .utf8) {
            for path in files.split(separator: "\n") where path.hasSuffix(".yml") || path.hasSuffix(".yaml") {
                guard let data = run(["git", "show", "\(ref):\(path)"], cwd: repoRoot), let text = String(data: data, encoding: .utf8) else { continue }
                guard Deployments.deploys(onPushTo: branch, workflow: text) else { continue }
                names.insert(Deployments.name(ofWorkflow: text) ?? String(path.split(separator: "/").last ?? ""))
            }
        }
        lock.lock(); deployWorkflows[key] = (names, Date()); lock.unlock()
        return names
    }

    func takeStateChanges() -> [(branch: String, pr: PullRequest, previous: PullRequest?)] {
        lock.lock(); defer { lock.unlock() }
        let out = stateChanges; stateChanges = []; return out
    }

    func myLogin() -> String? { lock.lock(); defer { lock.unlock() }; return me }

    func isBusy(repoRoot: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return inFlight.contains { $0.hasSuffix(repoRoot) || $0.hasPrefix(repoRoot + "@") || $0.hasPrefix("c:" + repoRoot) }
    }
    func feed(repoRoot: String) -> [FeedEvent]? {
        lock.lock(); defer { lock.unlock() }
        return feeds[repoRoot]?.0
    }

    private var feedETags: [String: String] = [:]

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
            if !askedWho, let out = run(["gh", "api", "user", "--jq", ".login"], cwd: repoRoot),
               let login = String(data: out, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !login.isEmpty {
                lock.lock(); askedWho = true; let changed = me != login; me = login; lock.unlock()
                if changed { ConfigStore.shared.update { $0.viewerLogin = login } }
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
                    var args = ["gh", "api", "-i", "repos/\(owner)/events?per_page=100&page=1"]
                    if let etag { args += ["-H", "If-None-Match: \(etag)"] }
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
                    let isBot = GitHubResolver.isBot(actor)
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
            var learned = false
            if let repo = owners[repoRoot].map({ String($0.split(separator: "/").last ?? "") }) {
                for e in events where !e.isBot {
                    guard let n = e.prNumber else { continue }
                    let opened = e.kind == "pr_open" || e.kind == "issue_open"
                    if note(repo: repo, number: n, title: e.title, author: opened ? e.actor : nil, at: opened ? e.at : nil) { learned = true }
                }
            }
            let board = learned ? project : nil
            lock.unlock()
            if let (items, at) = board { saveBoard(items, at: at) }
            if let known {
                let newest = known.map(\.at).max() ?? .distantPast
                for e in events where e.at > newest {
                    switch e.kind {
                    case "pr_open", "pr_merge", "pr_close":
                        expect("openPRs:" + repoRoot, for: 120, every: 15)
                        if let n = e.prNumber { expect("pull#:" + repoRoot + "#\(n)", for: 120, every: 15) }
                        if let b = e.branch { expect("pull:" + repoRoot + "@" + b, for: 120, every: 15) }
                        if e.kind == "pr_merge" {
                            expect("releases:" + repoRoot, for: 300, every: 30); expect("projectDelta", for: 120, every: 10)
                            expect("deploys:" + repoRoot, for: 300, every: 20)
                        }
                    case "push":
                        if let b = e.branch { expect("pull:" + repoRoot + "@" + b, for: 180, every: 30) }
                    case "release":
                        expect("releases:" + repoRoot, for: 120, every: 15)
                    default: break
                    }
                }
            }
            if changed { DispatchQueue.main.async { self.onUpdate?() } }
        }
    }

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

    func invalidate(repoRoot: String) {
        lock.lock(); defer { lock.unlock() }
        let old = Date.distantPast
        for k in pulls.keys where k.hasPrefix(repoRoot + "@") { pulls[k] = (pulls[k]!.0, old) }
        if let r = releases[repoRoot] { releases[repoRoot] = (r.0, old) }
    }

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
            let countBegan = Date()
            var found: [ReleasePR] = []
            let cfg = ConfigStore.shared.current
            var remoteBranches = Set<String>()
            if let out = run(["git", "branch", "-r", "--format=%(refname:short)"], cwd: repoRoot), let text = String(data: out, encoding: .utf8) {
                for line in text.split(separator: "\n") { remoteBranches.insert(line.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "origin/", with: "")) }
            }
            lock.lock(); let cached = pipelines[repoRoot]; let checked = pipelineCheckedAt[repoRoot]; lock.unlock()
            let detected: Pipeline
            if let cached, let checked, Date().timeIntervalSince(checked) < 3600, cached.source != "settings" {
                detected = cached
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
                let file = run(["gh", "api", "-H", "Accept: application/vnd.github.raw+json", "repos/{owner}/{repo}/contents/.github/rumkapsel.json"], cwd: repoRoot)
                    .flatMap { try? JSONDecoder().decode(ReleaseFile.self, from: $0) }
                let names = (cfg.trunkBranch, cfg.stagingBranch, cfg.productionBranch)
                var read = PipelineDetection.detect(branches: remoteBranches, merges: merges, file: file, names: names)
                if read.production.isEmpty, file?.ship == nil, workflowsDeploy(onPushTo: read.trunk, repoRoot: repoRoot) {
                    read = PipelineDetection.detect(branches: remoteBranches, merges: merges, file: file, names: names, deploysOnPush: true)
                } else if read.production.isEmpty, file?.ship == nil, !GitHubResolver.tags(repoRoot: repoRoot, run: run).isEmpty {
                    read = PipelineDetection.detect(branches: remoteBranches, merges: merges, file: file, names: names, tagged: true)
                }
                detected = read
                if answered { lock.lock(); pipelineCheckedAt[repoRoot] = Date(); lock.unlock() }
            }
            let pipe = detected.overridden(by: Pipeline.override(forRoot: repoRoot))
            let trunk = pipe.trunk, stagingBranch = pipe.staging, productionBranch = pipe.production
            var foundHotfixes: [ReleasePR] = []
            let bases = [stagingBranch, productionBranch].filter { !$0.isEmpty }
            func isReleaseHead(_ head: String) -> Bool { pipe.isReleaseHead(head) }
            for base in bases {
                guard let out = run(["gh", "pr", "list", "--base", base, "--state", "all", "--limit", "5",
                                     "--json", "number,title,baseRefName,headRefName,state,url,labels,mergedAt"], cwd: repoRoot),
                      let arr = try? JSONSerialization.jsonObject(with: out) as? [[String: Any]] else { continue }
                for o in arr {
                    let head = o["headRefName"] as? String ?? ""
                    let hotfix = base == productionBranch && !isReleaseHead(head)
                    guard isReleaseHead(head) || hotfix else { continue }
                    let labels = (o["labels"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
                    var pr = ReleasePR(number: o["number"] as? Int ?? 0, title: o["title"] as? String ?? "", base: base,
                                       head: head, state: o["state"] as? String ?? "", url: o["url"] as? String ?? "", labels: labels,
                                       mergedAt: (o["mergedAt"] as? String).flatMap(ISO8601DateFormatter().date(from:)),
                                       production: base == productionBranch, staging: !stagingBranch.isEmpty && base == stagingBranch)
                    pr.hotfix = hotfix
                    if hotfix { foundHotfixes.append(pr) } else { found.append(pr) }
                }
            }
            if pipe.shipsOnTag, let newest = GitHubResolver.tags(repoRoot: repoRoot, run: run).first {
                lock.lock(); let owner = owners[repoRoot]; lock.unlock()
                let url = owner.map { "https://github.com/\($0)/releases/tag/\(newest.name)" } ?? ""
                found.append(ReleasePR(number: 0, title: newest.name, base: trunk, head: newest.name, state: "MERGED",
                                       url: url, labels: [], mergedAt: newest.at, production: true, staging: false, tag: true))
            }
            let iso = ISO8601DateFormatter()
            let lastStaging = found.filter { $0.base == stagingBranch && $0.state == "MERGED" }.compactMap(\.mergedAt).max()
            let lastProduction = found.filter { $0.base == productionBranch && $0.state == "MERGED" }.compactMap(\.mergedAt).max()
            var newCargo = Cargo(storage: 0, deck: 0, storageNumbers: [], deckNumbers: [])
            let hasPipeline = (!bases.isEmpty && (lastStaging != nil || lastProduction != nil)) || pipe.shipsOnTag
            let floor = Date().addingTimeInterval(-30 * 24 * 3600)
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
            if hasPipeline, !exact, pipe.shipsOnTag, let tag = found.first(where: \.tag)?.head {
                _ = run(["git", "fetch", "-q", "origin", trunk], cwd: repoRoot)
                if let storage = prNumbers("\(tag)..origin/\(trunk)") {
                    newCargo.storageNumbers = storage
                    newCargo.storage = storage.count
                    exact = true
                }
            }
            if hasPipeline, !exact, stagingBranch.isEmpty, !productionBranch.isEmpty {
                _ = run(["git", "fetch", "-q", "origin", trunk, productionBranch], cwd: repoRoot)
                if let storage = prNumbers("origin/\(productionBranch)..origin/\(trunk)") {
                    let releaseNumbers = Set(found.map(\.number))
                    newCargo.storageNumbers = storage.filter { !releaseNumbers.contains($0) }
                    newCargo.storage = newCargo.storageNumbers.count
                    exact = true
                }
            }
            var merged: [Int: String] = [:]
            if hasPipeline, !exact, let out = run(["gh", "pr", "list", "--base", trunk, "--state", "merged", "--limit", "80", "--json", "number,mergedAt,author"], cwd: repoRoot),
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
            lock.lock()
            if let repo = owners[repoRoot].map({ String($0.split(separator: "/").last ?? "") }) {
                for (n, login) in merged { note(repo: repo, number: n, author: login) }
            }
            let previous = releases[repoRoot]?.0 ?? []
            for pr in found where pr.state == "MERGED" && previous.contains(where: { $0.number == pr.number && $0.state == "OPEN" }) {
                pendingLaunches.append((repoRoot, pr))
                expectLocked("deploys:" + repoRoot, for: Deployments.findWithin, every: 10)
            }
            if let tag = found.first(where: \.tag), !previous.isEmpty, !previous.contains(where: { $0.tag && $0.head == tag.head }) {
                pendingLaunches.append((repoRoot, tag))
            }
            if let (before, at) = hotfixes[repoRoot] {
                for pr in foundHotfixes where pr.state == "MERGED" {
                    let was = before.first { $0.number == pr.number }
                    guard was?.state == "OPEN" || (was == nil && (pr.mergedAt ?? .distantPast) > at) else { continue }
                    pendingHotfixes.append((repoRoot, pr))
                    expectLocked("deploys:" + repoRoot, for: Deployments.findWithin, every: 10)
                }
            }
            let hotfixesChanged = hotfixes[repoRoot]?.0 != foundHotfixes
            hotfixes[repoRoot] = (foundHotfixes, Date())
            let pipelineChanged = pipelines[repoRoot] != detected
            let changed = previous != found || hotfixesChanged || cargo[repoRoot] != newCargo || pipelineChanged
            pipelines[repoRoot] = detected
            newCargo.exact = exact
            newCargo.at = countBegan
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

    private var expected: [String: (until: Date, every: TimeInterval)] = [:]

    func expect(_ key: String, for seconds: TimeInterval = 120, every: TimeInterval = 15) {
        lock.lock(); defer { lock.unlock() }
        expectLocked(key, for: seconds, every: every)
    }

    private func expectLocked(_ key: String, for seconds: TimeInterval, every: TimeInterval) {
        let until = Date().addingTimeInterval(seconds)
        if let e = expected[key], e.until > until, e.every <= every { return }
        expected[key] = (until, every)
        trace("expect \(key) every \(Int(every))s for \(Int(seconds))s")
    }

    private func gate(_ key: String, base: TimeInterval) -> TimeInterval {
        if let e = expected[key] {
            if Date() < e.until { return e.every }
            expected[key] = nil
        }
        return base
    }

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

    func pullAnswered(branch: String, repoRoot: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return pulls[repoRoot + "@" + branch] != nil
    }

    // MARK: a pull request by number

    private var pullsByNumber: [String: (PullRequest?, Date)] = [:]

    func pull(number: Int, repoRoot: String) -> PullRequest? {
        lock.lock(); defer { lock.unlock() }
        return pullsByNumber[repoRoot + "#\(number)"]?.0
    }
    func pullAnswered(number: Int, repoRoot: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return pullsByNumber[repoRoot + "#\(number)"] != nil
    }

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
            guard let out = run(["gh", "pr", "view", "\(number)", "--json", "number,title,state,reviewDecision,isDraft,url,author,createdAt,closingIssuesReferences"], cwd: repoRoot),
                  let o = try? JSONSerialization.jsonObject(with: out) as? [String: Any] else { return }
            var pr = PullRequest(number: o["number"] as? Int ?? number, title: o["title"] as? String ?? "",
                                 state: o["state"] as? String ?? "", reviewDecision: o["reviewDecision"] as? String ?? "",
                                 isDraft: o["isDraft"] as? Bool ?? false, url: o["url"] as? String ?? "")
            pr.closes = GitHubResolver.closes(o)
            lock.lock(); pullsByNumber[key] = (pr, Date()); lock.unlock()
            noteTask(pr, repoRoot: repoRoot)
            noteAuthor(o, number: pr.number, repoRoot: repoRoot, issue: pr.closes.first)
            DispatchQueue.main.async { self.onUpdate?() }
        }
    }

    func inject(pull pr: PullRequest, number: Int, repoRoot: String) {
        guard frozen else { return }
        lock.lock(); pullsByNumber[repoRoot + "#\(number)"] = (pr, Date()); lock.unlock()
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
    private var checkedOut: [String: String] = [:]

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
            var base = "origin/HEAD"
            let trunk = ConfigStore.shared.current.trunkBranch
            for candidate in ["origin/" + trunk, "origin/develop", "origin/main", "origin/master"] where run(["git", "rev-parse", "--verify", "--quiet", candidate], cwd: worktree) != nil {
                base = candidate; break
            }
            var isPushed = false
            var onBranch: String?
            if let out = run(["git", "branch", "--show-current"], cwd: worktree),
               let branch = String(data: out, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !branch.isEmpty {
                isPushed = run(["git", "rev-parse", "--verify", "--quiet", "origin/" + branch], cwd: worktree) != nil
                onBranch = branch
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
            checkedOut[worktree] = onBranch
            inFlight.remove("c:" + worktree)
            lock.unlock()
            if changedResult { DispatchQueue.main.async { self.onUpdate?() } }
        }
    }

    func nameWithOwner(repoRoot: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return owners[repoRoot]
    }

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
                noteAuthor(o, number: pr.number, repoRoot: repoRoot, issue: pr.closes.first)
                return pr
            }
            let fields = "number,title,state,reviewDecision,isDraft,url,author,createdAt,statusCheckRollup,closingIssuesReferences"
            var answered = false
            if let out = run(["gh", "pr", "list", "--head", branch, "--state", "open", "--limit", "1", "--json", fields], cwd: repoRoot),
               let arr = try? JSONSerialization.jsonObject(with: out) as? [[String: Any]], let o = arr.first {
                pr = parse(o); answered = true
            } else if let out = run(["gh", "pr", "list", "--head", branch, "--state", "all", "--limit", "1", "--json", fields], cwd: repoRoot),
                      let arr = try? JSONSerialization.jsonObject(with: out) as? [[String: Any]] {
                pr = arr.first.map(parse); answered = true
            }
            lock.lock()
            if !answered, let old = pulls[key] {
                pulls[key] = (old.0, Date().addingTimeInterval(60 - interval))
                inFlight.remove(key)
                lock.unlock()
                return
            }
            let changed = pulls[key]?.0 != pr
            if changed, let pr, let old = pulls[key] { stateChanges.append((branch, pr, old.0)) }
            pulls[key] = (pr, Date())
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

extension GitHubResolver {
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

    func inject(pipeline p: Pipeline, for repoRoot: String) {
        guard frozen else { return }
        lock.lock(); pipelines[repoRoot] = p; lock.unlock()
        notify()
    }

    func inject(releases rs: [ReleasePR], for repoRoot: String, merged: [ReleasePR] = []) {
        guard frozen else { return }
        lock.lock()
        releases[repoRoot] = (rs, Date())
        for pr in merged { pendingLaunches.append((repoRoot, pr)) }
        lock.unlock()
        notify()
    }

    func inject(hotfixes hs: [ReleasePR], for repoRoot: String, merged: [ReleasePR] = []) {
        guard frozen else { return }
        lock.lock()
        hotfixes[repoRoot] = (hs, Date())
        for pr in merged { pendingHotfixes.append((repoRoot, pr)) }
        lock.unlock()
        notify()
    }

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
