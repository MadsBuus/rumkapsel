import Foundation

final class BoardSource: Intake {
    let name = "board"
    private weak var github: GitHubResolver?
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "rumkapsel.board", qos: .utility)
    private var project: ([ProjectItem], Date)? { didSet { BoardNumbers.note(project?.0 ?? []) } }
    private var saved = false
    private var moves: [Report] = []
    private var fields: (status: Int, pulls: Int?)?
    private var fullAt = Date.distantPast
    private var reading = false
    private var yards: Set<String>
    private var target: (owner: String, number: Int)?

    init(github: GitHubResolver, saved file: (items: [ProjectItem], at: Date)?, yards: [String]) {
        self.github = github
        self.yards = Set(yards)
        if let file { project = (file.items, file.at); saved = true }
        BoardNumbers.note(project?.0 ?? [])
    }

    func watch(_ board: (owner: String, number: Int)?) { lock.lock(); target = board; lock.unlock() }

    func checks() -> [Watch.Check] {
        lock.lock(); defer { lock.unlock() }
        guard let b = target, project != nil, github?.frozen == false else { return [] }
        return [Watch.Check("watch:board", .board) { [weak self] in self?.detect(owner: b.owner, number: b.number) }]
    }

    func reports() -> [Report] {
        lock.lock(); defer { lock.unlock() }
        let out = moves; moves = []; return out
    }

    var items: [ProjectItem]? { lock.lock(); defer { lock.unlock() }; return project?.0 }
    var liveItems: [ProjectItem]? { lock.lock(); defer { lock.unlock() }; return saved ? nil : project?.0 }
    var live: Bool { lock.lock(); defer { lock.unlock() }; return !saved }
    var fetchedAt: Date? { lock.lock(); defer { lock.unlock() }; return project?.1 }
    var file: (items: [ProjectItem], at: Date, yards: [String])? {
        lock.lock(); defer { lock.unlock() }
        return project.map { ($0.0, $0.1, yards.sorted()) }
    }

    func knowledge(owner: String, number: Int) -> GitHubResolver.ProjectKnowledge? {
        lock.lock(); defer { lock.unlock() }
        guard let p = project else { return nil }
        return GitHubResolver.ProjectKnowledge(owner: owner, number: number, items: p.0, at: p.1)
    }

    func usesColumns(_ repo: String, decided: Bool?) -> Bool {
        let st = ConfigStore.shared.current.statuses
        lock.lock()
        let mine = (project?.0 ?? []).filter { $0.repo == repo && !$0.status.isEmpty }
        var learned = false
        if decided == nil, mine.contains(where: { [st.storage, st.deck, st.cleared].contains($0.status) }), !yards.contains(repo) {
            yards.insert(repo); learned = true
        }
        let uses = !mine.isEmpty && (decided ?? yards.contains(repo))
        lock.unlock()
        if learned { github?.saveBoard() }
        return uses
    }

    func refresh(owner: String, number: Int) {
        guard let github, !github.frozen else { return }
        lock.lock()
        if Date().timeIntervalSince(fullAt) < github.baseInterval || reading { lock.unlock(); return }
        reading = true
        fullAt = Date()
        lock.unlock()
        github.trace("ask project (whole board)")
        queue.async { [self] in
            defer { lock.lock(); reading = false; lock.unlock() }
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
                guard let out = github.run(["gh", "api", "graphql", "-f", "query=" + query], cwd: FileManager.default.homeDirectoryForCurrentUser.path),
                      let obj = try? JSONSerialization.jsonObject(with: out) as? [String: Any],
                      let itemsObj = ((obj["data"] as? [String: Any])?["organization"] as? [String: Any]).flatMap({ $0["projectV2"] as? [String: Any] })?["items"] as? [String: Any],
                      let nodes = itemsObj["nodes"] as? [[String: Any]] else { github.trace("project read failed at page \(cursor)"); return }
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
            adopt(items, at: Date())
        }
    }

    private func detect(owner: String, number: Int) {
        guard let github else { return }
        let key = "watch:board"
        let base = "orgs/\(owner)/projectsV2/\(number)"
        lock.lock(); var known = fields; lock.unlock()
        if known == nil {
            guard let answer = github.watch.ask(key, base + "/fields") else { return }
            guard let arr = try? JSONSerialization.jsonObject(with: answer.data) as? [[String: Any]],
                  let status = arr.first(where: { $0["name"] as? String == ConfigStore.shared.current.statusField })?["id"] as? Int
            else { github.watch.tune(key) { $0.failed() }; github.trace("board: no \(ConfigStore.shared.current.statusField) field"); return }
            known = (status, arr.first { $0["data_type"] as? String == "linked_pull_requests" }?["id"] as? Int)
            lock.lock(); fields = known; lock.unlock()
        }
        guard let known else { return }
        let day = DateFormatter()
        day.dateFormat = "yyyy-MM-dd"; day.timeZone = TimeZone(identifier: "UTC"); day.locale = Locale(identifier: "en_US_POSIX")
        let since = day.string(from: Date().addingTimeInterval(-24 * 3600))
        let ids = ([known.status] + (known.pulls.map { [$0] } ?? [])).map(String.init).joined(separator: ",")
        guard let answer = github.watch.ask(key, base + "/items?per_page=100&fields=\(ids)&q=updated:%3E%3D\(since)", cache: base + "/items"), answer.changed,
              let arr = try? JSONSerialization.jsonObject(with: answer.data) as? [[String: Any]] else { return }
        if arr.count >= 100 {
            github.trace("board: a full page since \(since), reading the whole board")
            lock.lock(); fullAt = .distantPast; lock.unlock()
            refresh(owner: owner, number: number)
            return
        }
        let fresh = arr.compactMap { ProjectItem(rest: $0, status: known.status) }
        lock.lock()
        guard let (current, _) = project else { lock.unlock(); return }
        var merged = current
        var moved: [Report] = []
        for var f in fresh {
            if let i = merged.firstIndex(where: { $0.repo == f.repo && $0.number == f.number }) {
                if known.pulls == nil { f.prURLs = merged[i].prURLs }
                if merged[i] != f { if merged[i].status != f.status { moved.append(.cardMoved(f, from: merged[i].status)) }; merged[i] = f }
            } else { merged.append(f); moved.append(.cardMoved(f, from: nil)) }
        }
        let changed = merged != current
        if changed { project = (merged, Date()); moves += moved }
        lock.unlock()
        github.noteTasks(fresh)
        github.trace("board: \(fresh.count) item(s) updated since \(since), \(moved.count) moved")
        if changed {
            github.saveBoard()
            DispatchQueue.main.async { github.onUpdate?() }
        }
    }

    func adopt(_ items: [ProjectItem], at: Date) {
        lock.lock()
        guard at > (project?.1 ?? .distantPast) else { lock.unlock(); return }
        let previous = project?.0
        let wasSaved = saved
        saved = false
        let held = Dictionary((previous ?? []).map { ("\($0.repo)#\($0.number)", $0) }, uniquingKeysWith: { a, _ in a })
        let items = items.map { it in
            wasSaved ? it : held["\(it.repo)#\(it.number)"].flatMap { h in (h.updatedAt ?? .distantPast) > (it.updatedAt ?? .distantPast) ? h : nil } ?? it
        }
        if previous != nil, !wasSaved {
            for it in items where held["\(it.repo)#\(it.number)"]?.status != it.status { moves.append(.cardMoved(it, from: held["\(it.repo)#\(it.number)"]?.status)) }
        }
        let changed = previous != items || wasSaved
        project = (items, at)
        lock.unlock()
        if changed { github?.saveBoard(); DispatchQueue.main.async { [weak github] in github?.onUpdate?() } }
    }

    func reset() {
        lock.lock(); project = nil; moves = []; lock.unlock()
    }

    func inject(saved items: [ProjectItem]) {
        lock.lock(); project = (items, Date()); saved = true; lock.unlock()
    }

    func inject(_ items: [ProjectItem], at: Date, quiet: Bool) {
        lock.lock()
        if !quiet, let previous = project?.0 {
            let before = Dictionary(previous.map { ("\($0.repo)#\($0.number)", $0.status) }, uniquingKeysWith: { a, _ in a })
            for it in items where before["\(it.repo)#\(it.number)"] != it.status { moves.append(.cardMoved(it, from: before["\(it.repo)#\(it.number)"])) }
        }
        project = (items, at)
        saved = false
        lock.unlock()
    }
}
