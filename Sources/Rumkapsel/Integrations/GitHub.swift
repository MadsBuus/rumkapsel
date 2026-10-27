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
    var shipped = false
    var backMerge = false

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
    var isProduction: Bool { production ?? (base == Pipeline.productionName) }
    var isStaging: Bool { staging ?? (base == Pipeline.stagingName) }
    var untested: Bool { labels.contains { $0.lowercased().contains("untested") } }
    var tag = false
    var hotfix = false
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
    var id: String? = nil
}

struct ProjectItem: Equatable, Codable {
    let repo: String
    let number: Int
    let title: String
    let status: String
    let assignees: [String]
    var prURLs: [String]
    let url: String
    var updatedAt: Date? = nil
    var state: String = "OPEN"
    var isClosed: Bool { state == "CLOSED" }
}

extension ProjectItem {
    init?(rest o: [String: Any], status field: Int) {
        guard o["content_type"] as? String == "Issue", let c = o["content"] as? [String: Any], let number = c["number"] as? Int,
              let repo = (c["repository"] as? [String: Any])?["name"] as? String ?? (c["repository_url"] as? String)?.split(separator: "/").last.map(String.init)
        else { return nil }
        let fields = o["fields"] as? [[String: Any]] ?? []
        let status = ((fields.first { $0["id"] as? Int == field }?["value"] as? [String: Any])?["name"] as? [String: Any])?["raw"] as? String ?? ""
        let pulls = (fields.first { $0["data_type"] as? String == "linked_pull_requests" }?["value"] as? [[String: Any]] ?? [])
            .filter { $0["state"] as? String == "open" }.compactMap { $0["html_url"] as? String }
        self.init(repo: repo, number: number, title: c["title"] as? String ?? "", status: status,
                  assignees: (c["assignees"] as? [[String: Any]] ?? []).compactMap { $0["login"] as? String },
                  prURLs: pulls, url: c["html_url"] as? String ?? "",
                  updatedAt: (o["updated_at"] as? String).flatMap(ISO8601DateFormatter().date(from:)),
                  state: (c["state"] as? String ?? "open").uppercased())
    }
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
    struct ProjectKnowledge: Codable { var owner: String; var number: Int; var items: [ProjectItem]; var at: Date }
    func projectKnowledge(owner: String, number: Int) -> ProjectKnowledge? { board.knowledge(owner: owner, number: number) }

    struct Cargo: Equatable {
        var storage: Int; var deck: Int; var storageNumbers: [Int]; var deckNumbers: [Int]; var clearedNumbers: [Int] = []
        var updated: [Int: Date] = [:]
        var staged: [Int] = []
        var source: Source = .git
        var exact = false
        var at = Date.distantPast
    }
    private var pipelines: [String: Pipeline] = [:]
    func pipelineKnown(repoRoot: String) -> Bool { lock.lock(); defer { lock.unlock() }; return pipelines[repoRoot] != nil }
    func watchedRoots() -> [String] { lock.lock(); defer { lock.unlock() }; return frozen ? [] : Array(watched.keys) }
    var baseInterval: TimeInterval { interval }
    private var branchesOnGitHub: [String: Set<String>] = [:]
    private var pipelineCheckedAt: [String: Date] = [:]

    func cargo(repoRoot: String) -> Cargo? {
        lock.lock(); defer { lock.unlock() }
        if ConfigStore.shared.current.project != nil, !board.live || (board.items != nil && owners[repoRoot] == nil) { return nil }
        if let items = board.items, let owner = owners[repoRoot] {
            let repo = String(owner.split(separator: "/").last ?? "")
            let st = ConfigStore.shared.current.statuses
            let mine = items.filter { $0.repo == repo && !$0.status.isEmpty }
            if board.usesColumns(repo, decided: pipelines[repoRoot]?.boardColumns) {
            let storage = mine.filter { $0.status == st.storage }.map(\.number).sorted()
            let deck = mine.filter { $0.status == st.deck || $0.status == st.cleared }.map(\.number).sorted()
            let cleared = mine.filter { $0.status == st.cleared }.map(\.number).sorted()
            let updated = Dictionary(mine.compactMap { it in it.updatedAt.map { (it.number, $0) } }, uniquingKeysWith: { a, _ in a })
            let staged = git.counted(repoRoot: repoRoot).flatMap { $0.exact ? $0.deckNumbers : nil } ?? []
            return Cargo(storage: storage.count, deck: deck.count, storageNumbers: storage, deckNumbers: deck, clearedNumbers: cleared, updated: updated,
                         staged: staged, source: .board)
            }
        }
        guard var c = git.counted(repoRoot: repoRoot) else { return nil }
        if let owner = owners[repoRoot] {
            let repo = String(owner.split(separator: "/").last ?? "")
            c.storage = c.storageNumbers.count; c.deck = c.deckNumbers.count
        }
        return c
    }

    // MARK: project board

    private(set) lazy var board: BoardSource = {
        let file = GitHubResolver.loadBoardFile()
        let b = BoardSource(github: self, saved: file.map { ($0.items, $0.at) }, yards: file?.yards ?? [])
        watch.add { [weak b] in b?.checks() ?? [] }
        return b
    }()
    private var owners: [String: String] = GitHubResolver.loadBoardFile()?.owners ?? [:]

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
    func saveBoard() {
        guard !frozen, let file = board.file else { return }
        let saved = SavedBoard(items: file.items, at: file.at, owners: owners,
                               tasks: tasks.mapValues { Dictionary(uniqueKeysWithValues: $0.map { (String($0.key), $0.value) }) },
                               yards: file.yards,
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
        let at = board.fetchedAt
        if boardIndexAt != at {
            boardIndex = Dictionary((board.items ?? []).map { ("\($0.repo)#\($0.number)", $0) }, uniquingKeysWith: { a, _ in a })
            boardIndexAt = at
        }
        return boardIndex["\(repo)#\(number)"]
    }

    func isMine(repo: String, number: Int) -> Bool {
        guard let me = myLogin() else { return false }
        return work(repo: repo, number: number)?.author == me
    }

    func note(task pr: PullRequest, repoRoot: String) {
        guard let issue = pr.closes.first else { return }
        lock.lock()
        guard let owner = owners[repoRoot] else { lock.unlock(); return }
        let repo = String(owner.split(separator: "/").last ?? "")
        let known = tasks[repo]?[pr.number]
        if known != issue { tasks[repo, default: [:]][pr.number] = issue }
        lock.unlock()
        if known != issue { saveBoard() }
    }

    func note(open prs: [OpenPR], repoRoot: String) {
        lock.lock()
        var learned = false
        if let repo = owners[repoRoot].map({ String($0.split(separator: "/").last ?? "") }) {
            for pr in prs where !pr.isBot {
                if note(repo: repo, number: pr.number, title: pr.title, author: pr.author, at: pr.createdAt) { learned = true }
                if let issue = tasks[repo]?[pr.number] { if note(repo: repo, number: issue, author: pr.author) { learned = true } }
            }
        }
        lock.unlock()
        if learned { saveBoard() }
    }

    func note(feed events: [FeedEvent], repoRoot: String) {
        lock.lock()
        var learned = false
        if let repo = owners[repoRoot].map({ String($0.split(separator: "/").last ?? "") }) {
            for e in events where !e.isBot {
                guard let n = e.prNumber else { continue }
                let opened = e.kind == "pr_open" || e.kind == "issue_open"
                if note(repo: repo, number: n, title: e.title, author: opened ? e.actor : nil, at: opened ? e.at : nil) { learned = true }
            }
        }
        lock.unlock()
        if learned { saveBoard() }
    }

    func note(author o: [String: Any], number: Int, repoRoot: String, issue: Int?) {
        let login = ((o["author"] as? [String: Any])?["login"] as? String) ?? ""
        let at = (o["createdAt"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) }
        lock.lock()
        guard let owner = owners[repoRoot] else { lock.unlock(); return }
        let repo = String(owner.split(separator: "/").last ?? "")
        var learned = note(repo: repo, number: number, title: o["title"] as? String, author: login, at: at)
        if let issue { learned = note(repo: repo, number: issue, author: login) || learned }
        lock.unlock()
        if learned { saveBoard() }
    }

    func note(authors: [Int: String], repoRoot: String) {
        lock.lock()
        if let repo = owners[repoRoot].map({ String($0.split(separator: "/").last ?? "") }) {
            for (n, login) in authors { note(repo: repo, number: n, author: login) }
        }
        lock.unlock()
    }

    func task(repo: String, pull: Int) -> Int? {
        lock.lock(); defer { lock.unlock() }
        return tasks[repo]?[pull]
    }
    func noteTasks(_ items: [ProjectItem]) {
        lock.lock()
        for it in items { for url in it.prURLs { if let n = Int(url.split(separator: "/").last ?? "") { tasks[it.repo, default: [:]][n] = it.number } } }
        lock.unlock()
    }

    func pulls(repo: String, task: Int) -> [Int] {
        lock.lock(); defer { lock.unlock() }
        return (tasks[repo] ?? [:]).filter { $0.value == task }.map(\.key).sorted()
    }
    private func learned(owner: String, repoRoot: String) {
        lock.lock(); owners[repoRoot] = owner; lock.unlock()
        saveBoard()
    }

    private let http = GitHubHTTP(token: GitHubHTTP.ghToken)
    private var askedWho = false
    private var me: String? = ConfigStore.shared.current.viewerLogin

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
        return pipelines[repoRoot] ?? .unread
    }

    var signedIn: Bool? { frozen ? true : http.signedIn }

    func pipelineRead(repoRoot: String) -> Bool { lock.lock(); defer { lock.unlock() }; return pipelines[repoRoot] != nil }

    func githubBranches(repoRoot: String) -> Set<String>? { lock.lock(); defer { lock.unlock() }; return branchesOnGitHub[repoRoot] }

    private func defaultBranch(_ repoRoot: String) -> String? {
        if nameWithOwner(repoRoot: repoRoot) == nil { learnOwner(repoRoot) }
        if let owner = nameWithOwner(repoRoot: repoRoot), let a = http.get("repos/\(owner)", key: repoRoot + "#repo"),
           let o = try? JSONSerialization.jsonObject(with: a.data) as? [String: Any], let b = o["default_branch"] as? String, !b.isEmpty {
            return b
        }
        guard let out = run(["git", "symbolic-ref", "--short", "refs/remotes/origin/HEAD"], cwd: repoRoot),
              let ref = String(data: out, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), ref.hasPrefix("origin/") else { return nil }
        return String(ref.dropFirst(7))
    }

    func myLogin() -> String? { lock.lock(); defer { lock.unlock() }; return me }

    func isBusy(repoRoot: String) -> Bool {
        return pulls.isBusy(repoRoot: repoRoot) || releases.isBusy(repoRoot: repoRoot) || git.isBusy(repoRoot: repoRoot)
    }
    func askWho() {
        lock.lock(); let who = !askedWho; askedWho = true; lock.unlock()
        guard who else { return }
        if let a = http.get("user"), let o = try? JSONSerialization.jsonObject(with: a.data) as? [String: Any], let login = o["login"] as? String {
            lock.lock(); let changed = me != login; me = login; lock.unlock()
            if changed { ConfigStore.shared.update { $0.viewerLogin = login } }
        } else { lock.lock(); askedWho = false; lock.unlock() }
    }

    // MARK: watching

    private(set) lazy var watch: Watch = {
        let w = Watch(http: http)
        w.trace = { [weak self] in self?.trace($0) }
        w.add { [weak self] in self?.checks() ?? [] }
        return w
    }()
    private(set) lazy var deployments: DeploySource = {
        let d = DeploySource(github: self)
        watch.add { [weak d] in d?.checks() ?? [] }
        return d
    }()
    private(set) lazy var releases = ReleaseSource(github: self)
    private(set) lazy var git = GitSource(github: self)
    private(set) lazy var pulls: PullSource = {
        let p = PullSource(github: self)
        watch.add { [weak p] in p?.checks() ?? [] }
        return p
    }()
    var front: Bool { get { watch.front } set { watch.front = newValue } }
    var worked: Date { get { watch.worked } set { watch.worked = newValue } }
    var pace: Pace { get { watch.pace } set { watch.pace = newValue } }

    private var watched: [String: Bool] = [:]

    func watch(_ roots: [String: Bool], board: (owner: String, number: Int)?) {
        if frozen { return }
        lock.lock()
        watched = roots
        lock.unlock()
        _ = deployments
        pulls.watch(roots)
        self.board.watch(board)
        watch.start()
        git.watch(Array(roots.keys))
    }

    private func checks() -> [Watch.Check] {
        lock.lock(); defer { lock.unlock() }
        guard !frozen else { return [] }
        var out: [Watch.Check] = []
        for root in watched.keys {
            guard owners[root] != nil else {
                out.append(.init(root + "#watch:owner", Detector(every: [300, 300, 300])) { self.learnOwner(root) })
                continue
            }
        }
        out.append(.init("watch:limits", Detector(every: [300, 300, 300])) { self.http.readLimits() })
        return out
    }

    func ring(repoRoot: String) { watch.ring(repoRoot: repoRoot) }

    private func ringLocked(repoRoot: String?) { watch.ring(repoRoot: repoRoot) }

    func learnOwner(_ repoRoot: String) {
        guard let out = run(["gh", "repo", "view", "--json", "nameWithOwner"], cwd: repoRoot),
              let obj = try? JSONSerialization.jsonObject(with: out) as? [String: Any], let n = obj["nameWithOwner"] as? String else { return }
        learned(owner: n, repoRoot: repoRoot)
    }

    func invalidate(repoRoot: String) {
        lock.lock(); defer { lock.unlock() }
        ringLocked(repoRoot: repoRoot)
        pulls.invalidate(repoRoot: repoRoot)
        releases.invalidate(repoRoot: repoRoot)
    }

    func invalidate() {
        lock.lock(); defer { lock.unlock() }
        ringLocked(repoRoot: nil)
        pulls.invalidate(repoRoot: nil)
        releases.invalidate(repoRoot: nil)
        git.invalidate()
    }

    func readPipeline(repoRoot: String) -> (pipe: Pipeline, changed: Bool) {
        let remote = Discovery.githubRemote(repoRoot) || nameWithOwner(repoRoot: repoRoot) != nil
        if remote { http.askToken() }
        var remoteBranches = Set<String>()
        if let out = run(["git", "branch", "-r", "--format=%(refname:short)"], cwd: repoRoot), let text = String(data: out, encoding: .utf8) {
            for line in text.split(separator: "\n") { remoteBranches.insert(line.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "origin/", with: "")) }
        }
        remoteBranches.remove("HEAD")
        lock.lock(); let cached = pipelines[repoRoot]; let checked = pipelineCheckedAt[repoRoot]; if !remote { branchesOnGitHub[repoRoot] = nil }; lock.unlock()
        var settled: Pipeline?
        if let cached, let checked, Date().timeIntervalSince(checked) < 3600, cached.remote == remote {
            settled = cached
        } else if !remote {
            var local = Set<String>()
            if let out = run(["git", "branch", "--format=%(refname:short)"], cwd: repoRoot), let text = String(data: out, encoding: .utf8) {
                for line in text.split(separator: "\n") { local.insert(line.trimmingCharacters(in: .whitespaces)) }
            }
            settled = PipelineDetection.detect(branches: local, merges: [], file: nil, remote: false)
            lock.lock(); pipelineCheckedAt[repoRoot] = Date(); lock.unlock()
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
            let asked = runReporting(["gh", "api", "-H", "Accept: application/vnd.github.raw+json", "repos/{owner}/{repo}/contents/.github/rumkapsel.json"], cwd: repoRoot)
            let file = asked.data.flatMap { try? JSONDecoder().decode(ReleaseFile.self, from: $0) }
            let fileFailed = asked.data == nil && !asked.err.contains("404")
            let named = defaultBranch(repoRoot)
            let probe = PipelineDetection.detect(branches: remoteBranches, merges: merges, file: file, defaultBranch: named, history: answered)
            var deploys = false, tagged = false
            if file?.ship == nil, probe.production.isEmpty || probe.source == "branches" {
                deploys = workflowsDeploy(onPushTo: probe.trunk, repoRoot: repoRoot)
                tagged = !deploys && PipelineDetection.tagged(GitHubResolver.tags(repoRoot: repoRoot, run: run), now: Date())
            }
            let read = PipelineDetection.detect(branches: remoteBranches, merges: merges, file: file, defaultBranch: named, history: answered,
                                                deploysOnPush: deploys, tagged: tagged)
            if let out = run(["git", "ls-remote", "--heads", "origin"], cwd: repoRoot), let text = String(data: out, encoding: .utf8) {
                let heads = Set(text.split(separator: "\n").compactMap { $0.split(separator: "\t").last.map(String.init) }
                    .filter { $0.hasPrefix("refs/heads/") }.map { String($0.dropFirst(11)) })
                lock.lock(); branchesOnGitHub[repoRoot] = heads; lock.unlock()
            }
            let failed = !answered || fileFailed
            settled = PipelineDetection.settle(cached: cached, read: read, failed: failed)
            if !failed { lock.lock(); pipelineCheckedAt[repoRoot] = Date(); lock.unlock() }
        }
        let pipe = (settled ?? .unread).overridden(by: Pipeline.override(forRoot: repoRoot))
        lock.lock()
        let changed = settled.map { pipelines[repoRoot] != $0 } ?? (pipelines[repoRoot] != nil)
        pipelines[repoRoot] = settled
        lock.unlock()
        if changed {
            trace("pipeline \(repoRoot): \(pipe.trunk) → \(pipe.staging.isEmpty ? "-" : pipe.staging) → \(pipe.production.isEmpty ? "-" : pipe.production) · \(pipe.source): \(pipe.why)")
        }
        return (pipe, changed)
    }

    static var diag = ProcessInfo.processInfo.environment["GITHUB_DIAG"] != nil
    func trace(_ text: String) {
        StationLog.write("github", text)
        guard GitHubResolver.diag else { return }
        FileHandle.standardError.write("GH \(ISO8601DateFormatter().string(from: Date())) \(text)\n".data(using: .utf8)!)
    }
    private let lock = NSLock()
    var onUpdate: (() -> Void)?

    func nameWithOwner(repoRoot: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return owners[repoRoot]
    }

    func run(_ args: [String], cwd: String) -> Data? { runReporting(args, cwd: cwd, errors: false).data }

    private func runReporting(_ args: [String], cwd: String, errors: Bool = true) -> (data: Data?, err: String) {
        guard FileManager.default.fileExists(atPath: cwd), args.first != "gh" || http.ghOpen else { return (nil, "") }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = args
        p.currentDirectoryURL = URL(fileURLWithPath: cwd)
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (env["PATH"] ?? "")
        p.environment = env
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = errors ? err : FileHandle.nullDevice
        do { try p.run() } catch { return (nil, "") }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        let said = errors ? String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "" : ""
        p.waitUntilExit()
        GitHubMeter.ran(args, ok: p.terminationStatus == 0, bytes: data.count)
        if args.starts(with: ["git", "fetch"]) { git.fetched(cwd) }
        return (p.terminationStatus == 0 ? data : nil, said)
    }
}

// MARK: injection

extension GitHubResolver {
    func simulationReset() {
        guard frozen else { return }
        lock.lock()
        pipelines = [:]; owners = [:]
        me = nil
        lock.unlock()
        pulls.reset()
        releases.reset()
        git.reset()
        board.reset()
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
        pulls.inject(open: prs, for: repoRoot, saved: false)
        notify()
    }

    func inject(pull pr: PullRequest?, for branch: String, repoRoot: String, changed: Bool = true) {
        guard frozen else { return }
        pulls.inject(pull: pr, for: branch, repoRoot: repoRoot, changed: changed)
        notify()
    }

    func inject(pull pr: PullRequest, number: Int, repoRoot: String) {
        guard frozen else { return }
        pulls.inject(pull: pr, number: number, repoRoot: repoRoot)
    }

    func inject(feed events: [FeedEvent], for repoRoot: String) {
        guard frozen else { return }
        pulls.inject(feed: events, for: repoRoot)
        notify()
    }

    func inject(cargo c: Cargo, for repoRoot: String) {
        guard frozen else { return }
        git.inject(cargo: c, for: repoRoot)
        notify()
    }

    func inject(pipeline p: Pipeline, for repoRoot: String) {
        guard frozen else { return }
        lock.lock(); pipelines[repoRoot] = p; lock.unlock()
        notify()
    }

    func inject(releases rs: [ReleasePR], for repoRoot: String, merged: [ReleasePR] = []) {
        guard frozen else { return }
        releases.inject(releases: rs, for: repoRoot, merged: merged)
        notify()
    }

    func inject(hotfixes hs: [ReleasePR], for repoRoot: String, merged: [ReleasePR] = []) {
        guard frozen else { return }
        releases.inject(hotfixes: hs, for: repoRoot, merged: merged)
        notify()
    }

    func inject(savedProject items: [ProjectItem]) {
        guard frozen else { return }
        board.inject(saved: items)
        notify()
    }

    func inject(savedOpenPRs prs: [OpenPR], for repoRoot: String) {
        guard frozen else { return }
        pulls.inject(open: prs, for: repoRoot, saved: true)
        notify()
    }

    func inject(project items: [ProjectItem], at: Date = Date(), quiet: Bool = false) {
        guard frozen else { return }
        board.inject(items, at: at, quiet: quiet)
        noteTasks(items)
        notify()
    }

    func inject(commits n: Int, pushed isPushed: Bool, dirty files: Int = 0, worktree: String) {
        guard frozen else { return }
        git.inject(commits: n, pushed: isPushed, dirty: files, worktree: worktree)
        notify()
    }

    private func notify() {
        guard !injectSilently else { return }
        DispatchQueue.main.async { self.onUpdate?() }
    }
}
