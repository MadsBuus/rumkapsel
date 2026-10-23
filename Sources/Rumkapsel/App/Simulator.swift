import AppKit
import SwiftUI

@MainActor
final class SimulatorController {
    let station: StationController
    let model: SimulatorModel
    var onReset: (() -> Void)? { get { model.onReset } set { model.onReset = newValue } }
    let view = NSView()

    init(frame: NSRect) {
        station = StationController(frame: NSRect(origin: .zero, size: frame.size), demo: false, simulated: true)
        model = SimulatorModel(station: station)
        view.frame = frame
        view.autoresizingMask = [.width, .height]
        station.view.frame = view.bounds
        station.view.autoresizingMask = [.width, .height]
        station.viewSize = frame.size
        station.drone.isEnabled = false
        view.addSubview(station.view)
        model.seed()
    }

    func snapshot(to path: String) { station.snapshot(to: path) }
}

// MARK: the made-up org

enum SimOwner { case me, teammate, peer }

struct SimOffice: Identifiable {
    let uid: String
    var repo: String
    var number: Int
    var branch: String
    var title: String
    var owner: SimOwner
    var who: String
    var cwd = ""
    var pushed = false
    var commits = 0
    var pull: PullRequest?
    var prOpen = false
    var startedAt = Date()

    var id: String { uid }
    var home: Home { Home.from(repo: repo, branch: branch, cwd: cwd) }
    var label: String { "\(repo)#\(number) \(title) (\(who))" }
}

private struct SimSession {
    var id: String
    var office: String
    var activity: Activity
    var last: Date
    var prompts = 0
    var queued = 0
    var markers: [StationEvent: String] = [:]
}

protocol SimStation: AnyObject {
    var world: World { get }
    var now: Date { get }
    var sim: SimHooks? { get }
    var missions: [Mission] { get }
    func handle(_ events: [WorldEvent])
    func handle(_ event: WorldEvent)
    func after(_ seconds: Double, _ run: @escaping () -> Void)
    func simulate(scan: ScanResult)
    func simulateGitHub()
    func simulate(peer: PeerSnapshot)
    func simulatePeerLeft(_ name: String)
    func simulateKick(roomKey key: String)
    func simulate(_ nudge: SimNudge)
}

extension StationController: SimStation {}

@MainActor
final class SimulatorModel: ObservableObject {
    static func speedValue(_ name: String) -> Double { ["¼x": 0.25, "½x": 0.5][name] ?? Double(name.dropLast()) ?? 1 }

    var onReset: (() -> Void)?
    let station: SimStation
    private var github: GitHubResolver { station.world.github }

    let repos = ["web", "api", "ios"]
    static let trunk = "develop"
    static let flow = Pipeline(trunk: trunk, staging: Pipeline.stagingName, production: Pipeline.productionName, source: "history")
    let teammate = "leo"
    let peerName = "kim"

    @Published var target = ""
    @Published var column = ""
    @Published var stageSource: Source = .board
    @Published var speed = 1.0
    @Published var paused = false
    @Published private(set) var offices: [SimOffice] = []

    private var sessions: [String: SimSession] = [:]
    private var probes: [String: [(id: String, activity: Activity)]] = [:]
    private var nextProbe = 0
    private var board: [ProjectItem] = []
    private var feeds: [String: [FeedEvent]] = [:]
    private var releases: [String: [ReleasePR]] = [:]
    private var noStaging: Set<String> = []
    private var shipsOnMerge: Set<String> = []
    private var shipsOnTag: Set<String> = []
    private var launches: [(repo: String, pr: ReleasePR)] = []
    private var hotfixPRs: [String: [ReleasePR]] = [:]
    private var hotfixLaunches: [(repo: String, pr: ReleasePR)] = []
    private var botPRs: [String: [(number: Int, title: String, branch: String)]] = [:]
    let bot = "dependabot[bot]"
    private var peerHere = false
    private var peerBeat: Timer?
    private var peerSharesTeammate = false
    private var peerDoing: String?
    private var nextIssues: [String: Int] = ["web": 460, "api": 5160, "ios": 300]
    private func nextIssue(_ repo: String) -> Int { nextIssues[repo, default: 700] += 1; return nextIssues[repo]! }
    private var nextRelease = 9000
    private var nextSession = 0
    private var nextOffice = 0

    private var statuses: AppConfig.ProjectStatuses { ConfigStore.shared.current.statuses }
    var columns: [String] {
        let s = statuses
        return [s.development, s.storage, s.deck, s.cleared, s.shipped]
    }

    init(station: SimStation) {
        self.station = station
        station.sim?.onEvent = { [weak self] e in
            self?.note("event", SimulatorModel.describe(e), .event(e))
        }
        station.sim?.onCommand = { [weak self] c, who in
            self?.note("command", "\(who): \(c.words)", .command(c, by: who))
        }
        station.sim?.pullState = { [weak self] repo, number in self?.pullFates["\(repo)#\(number)"] }
        peerBeat = Timer.scheduledTimer(withTimeInterval: 12, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pushPeer() }
        }
    }

    // MARK: paths

    private var base: String { NSTemporaryDirectory() + "rumkapsel-sim" }
    private func root(_ repo: String) -> String { base + "/dev/" + repo }
    private func worktree(_ repo: String, _ slug: String) -> String { base + "/conductor/workspaces/\(repo)/\(slug)" }
    private func makeDir(_ path: String) { try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true) }

    // MARK: the seed

    func seed(crowd: Bool = true) {
        for r in repos { makeDir(root(r)) }
        github.injectSilently = true
        github.simulationReset()
        github.inject(login: "me")
        for r in repos {
            github.inject(owner: "simcorp/" + r, for: root(r))
            github.inject(cargo: GitHubResolver.Cargo(storage: 0, deck: 0, storageNumbers: [], deckNumbers: []), for: root(r))
            github.inject(pipeline: SimulatorModel.flow, for: root(r))
        }
        board = [
            item("web", 455, "booking flow", statuses.development, "me"),
            item("web", 450, "hero image", statuses.development, "me"),
            item("api", 5158, "offerings gate", statuses.development, "me"),
            item("ios", 298, "onboarding", statuses.development, "me"),
            item("web", 440, "search fixes", statuses.storage, "me"),
            item("web", 441, "profile tidy", statuses.storage, "me"),
            item("api", 5100, "rate limits", statuses.storage, "me"),
            item("web", 430, "checkout copy", statuses.deck, "me"),
            item("web", 431, "cart summary", statuses.cleared, "me"),
            item("ios", 280, "push permissions", statuses.deck, "me"),
        ]
        addMine(repo: "web", number: 455, slug: "damascus", branch: "gh-455/booking-flow", title: "booking flow", activity: .coding("app"), commits: 4)
        if crowd {
            addMine(repo: "ios", number: 298, slug: "lima", branch: "gh-298/onboarding", title: "onboarding", activity: .waiting, commits: 1)
            addMine(repo: "api", number: 5158, slug: "bismarck", branch: "gh-5158/offerings-gate", title: "offerings gate", activity: .testing, commits: 2)
            var leo = makeOffice(repo: "api", number: 5140, branch: "gh-5140/settlement-redesign", title: "settlement redesign",
                                 owner: .teammate, who: teammate)
            leo.prOpen = true
            leo.pushed = true
            leo.startedAt = station.now.addingTimeInterval(-7200)
            offices.append(leo)
            var kim = makeOffice(repo: "web", number: 460, branch: "gh-460/artist-tags", title: "artist tags", owner: .peer, who: peerName)
            kim.pushed = true
            kim.commits = 2
            kim.startedAt = station.now.addingTimeInterval(-3600)
            offices.append(kim)
        }

        github.inject(project: board, quiet: true)
        github.injectSilently = false
        pushGitHub()
        pushScan()
        peerHere = crowd
        pushPeer()
        pushGitHub()
        refresh()
        note("sim", "org seeded: \(repos.joined(separator: ", "))")
    }

    private func item(_ repo: String, _ number: Int, _ title: String, _ status: String, _ who: String) -> ProjectItem {
        ProjectItem(repo: repo, number: number, title: title, status: status, assignees: [who],
                    prURLs: [], url: "https://example.invalid/\(repo)/\(number)", updatedAt: station.now)
    }

    private func makeOffice(repo: String, number: Int, branch: String, title: String, owner: SimOwner, who: String) -> SimOffice {
        nextOffice += 1
        return SimOffice(uid: "off-\(nextOffice)", repo: repo, number: number, branch: branch, title: title, owner: owner, who: who)
    }

    @discardableResult
    private func addMine(repo: String, number: Int, slug: String, branch: String, title: String,
                         activity: Activity, commits: Int) -> SimOffice {
        var o = makeOffice(repo: repo, number: number, branch: branch, title: title, owner: .me, who: "me")
        o.cwd = worktree(repo, slug)
        o.pushed = true
        o.commits = commits
        makeDir(o.cwd)
        offices.append(o)
        startSession(in: o.uid, activity: activity)
        return o
    }

    private func startSession(in uid: String, activity: Activity) {
        nextSession += 1
        sessions[uid] = SimSession(id: "sim-\(nextSession)", office: uid, activity: activity, last: station.now)
    }

    // MARK: pushing facts in

    private func info(_ o: SimOffice, _ s: SimSession) -> SessionInfo {
        SessionInfo(id: s.id, cwd: o.cwd, repo: o.repo, repoRoot: root(o.repo), owner: "simcorp", lastModified: s.last,
                    activity: s.activity, area: nil, title: nil, branch: o.branch, toolCount: 0, isSubagent: false,
                    cwdExists: true, promptCount: s.prompts, queuedCount: s.queued, eventMarkers: s.markers)
    }

    private func pushScan() {
        for o in offices where o.owner == .me {
            guard sessions[o.uid] != nil else { continue }
            github.inject(commits: o.commits, pushed: o.pushed, worktree: o.cwd)
        }
        var live = offices.compactMap { o in sessions[o.uid].map { info(o, $0) } }
        for o in offices {
            guard let s = sessions[o.uid] else { continue }
            for p in probes[o.uid] ?? [] {
                live.append(SessionInfo(id: p.id, cwd: o.cwd, repo: o.repo, repoRoot: root(o.repo), owner: "simcorp", lastModified: s.last,
                                        activity: p.activity, area: nil, title: nil, branch: o.branch, toolCount: 0, isSubagent: true,
                                        cwdExists: true, promptCount: 0, queuedCount: 0, eventMarkers: [:]))
            }
        }
        station.simulate(scan: ScanResult(sessions: live.sorted { $0.id < $1.id }))
    }

    private func pushGitHub(yardFirst: Bool = false) {
        github.injectSilently = true
        defer {
            github.injectSilently = false
            if yardFirst { station.handle(station.world.reconcileYards()) }
            station.simulateGitHub()
        }
        for r in repos {
            let sent = launches.filter { $0.repo == r }.map(\.pr)
            var open = offices.filter { $0.repo == r && ($0.owner == .teammate ? $0.prOpen : $0.pull?.state == "OPEN") }.map {
                OpenPR(number: $0.number, title: $0.title, author: $0.owner == .me ? "me" : $0.who, isBot: false, branch: $0.branch,
                       url: "https://example.invalid/\(r)/\($0.number)", createdAt: $0.startedAt)
            }
            open += (botPRs[r] ?? []).map {
                OpenPR(number: $0.number, title: $0.title, author: bot, isBot: true, branch: $0.branch,
                       url: "https://example.invalid/\(r)/\($0.number)", createdAt: station.now)
            }
            github.inject(openPRs: open, for: root(r))
            github.inject(feed: feeds[r] ?? [], for: root(r))
            github.inject(releases: releases[r] ?? [], for: root(r), merged: sent)
            github.inject(hotfixes: hotfixPRs[r] ?? [], for: root(r), merged: hotfixLaunches.filter { $0.repo == r }.map(\.pr))
        }
        launches = []
        hotfixLaunches = []
        github.inject(project: board)
    }

    private func pushPeer() {
        guard peerHere else { return }
        let mine = offices.filter { $0.owner == .peer }.map { o in
            PeerSnapshot.Office(key: o.home.key, name: o.home.name, repo: o.repo, branch: o.branch,
                                color: station.world.fleet.color(forRepo: o.repo), cells: [], pushed: o.pushed,
                                startedAt: o.startedAt, lastActive: station.now, boxes: o.commits, dim: false)
        }
        let asleep = station.sim?.night == true
        let office = peerSharesTeammate ? offices.first { $0.owner == .teammate }?.home.key : nil
        let ms = mine.prefix(1).map { PeerSnapshot.Minion(id: "kim-1", office: office ?? $0.key, asleep: asleep, busy: !asleep && peerDoing == nil, doing: peerDoing) }
        let snap = PeerSnapshot(version: PeerSnapshot.current, name: peerName, since: station.now.addingTimeInterval(-600),
                                offices: mine, minions: Array(ms), github: nil, project: nil)
        station.simulate(peer: snap)
    }

    private func feedEvent(_ kind: String, repo: String, branch: String?, pr: Int?, title: String?, detail: String = "", actor: String? = nil) {
        let e = FeedEvent(at: station.now, actor: actor ?? teammate, isBot: actor == bot, kind: kind, branch: branch, prNumber: pr,
                          title: title, url: "https://example.invalid/\(repo)", detail: detail)
        feeds[repo, default: []].insert(e, at: 0)
        feeds[repo] = Array(feeds[repo]!.prefix(40))
    }

    private var pullFates: [String: String] = [:]

    private func setPull(_ pr: PullRequest?, on uid: String) {
        guard let i = index(uid) else { return }
        offices[i].pull = pr
        if let pr { pullFates["\(offices[i].repo)#\(pr.number)"] = pr.state }
        github.inject(pull: pr, for: offices[i].branch, repoRoot: root(offices[i].repo))
        pushGitHub()
        pushScan()
    }

    private func move(_ items: [ProjectItem], to status: String, yardFirst: Bool = false) {
        for it in items {
            guard let i = board.firstIndex(where: { $0.repo == it.repo && $0.number == it.number }) else { continue }
            board[i] = ProjectItem(repo: it.repo, number: it.number, title: it.title, status: status,
                                   assignees: it.assignees, prURLs: it.prURLs, url: it.url, updatedAt: station.now)
        }
        pushGitHub(yardFirst: yardFirst)
    }

    private func index(_ uid: String) -> Int? { offices.firstIndex { $0.uid == uid } }

    func refresh() {
        if index(target) == nil { target = offices.first { $0.owner == .me }?.uid ?? offices.first?.uid ?? "" }
        if !columns.contains(column) { column = columns.first ?? "" }
        objectWillChange.send()
    }

    // MARK: what the target office has right now

    var office: SimOffice? { offices.first { $0.uid == target } }
    private var targetRepo: String { office?.repo ?? repos[0] }
    private var targetSession: SimSession? { office.flatMap { sessions[$0.uid] } }

    private var leoOffice: SimOffice? {
        if let o = office, o.owner == .teammate { return o }
        return offices.last { $0.owner == .teammate && $0.repo == targetRepo }
    }
    private var leoBranchWithoutPR: SimOffice? {
        if let o = office, o.owner == .teammate, !o.prOpen { return o }
        return offices.last { $0.owner == .teammate && $0.repo == targetRepo && !$0.prOpen }
    }
    private var leoOpenPR: SimOffice? {
        if let o = office, o.owner == .teammate, o.prOpen { return o }
        return offices.last { $0.owner == .teammate && $0.repo == targetRepo && $0.prOpen }
    }

    private var kimOffice: SimOffice? {
        if let o = office, o.owner == .peer { return o }
        return offices.last { $0.owner == .peer }
    }

    var status: [String] {
        guard let o = office else { return ["no office"] }
        var out: [String] = []
        out.append("session: " + (targetSession.map { $0.activity.label } ?? "none"))
        out.append("branch: \(o.branch), " + (o.pushed ? "pushed" : "not pushed"))
        out.append("pr: " + prText(o))
        out.append("crates: \(crateText(o)), board: " + (boardItem(o).map(\.status) ?? "not on the board"))
        out.append("claimed by: \(o.who)")
        return out
    }

    private func prText(_ o: SimOffice) -> String {
        switch o.owner {
        case .me:
            guard let pr = o.pull else { return "none" }
            switch pr.state {
            case "MERGED": return "merged"
            case "CLOSED": return "closed, not merged"
            default:
                if pr.checks == "failure" { return "open, checks failing" }
                return pr.reviewDecision == "APPROVED" ? "open, approved" : "open"
            }
        case .teammate: return o.prOpen ? "open, \(o.who)'s" : "none"
        case .peer: return "not on GitHub yet"
        }
    }

    private func crateText(_ o: SimOffice) -> String {
        switch o.owner {
        case .me:
            if o.pull != nil { return "one package" }
            return o.commits == 0 ? "none" : "\(min(16, Int(pow(Double(o.commits), 0.7).rounded(.up))))"
        case .teammate: return o.prOpen ? "one package" : "\(1 + o.commits)"
        case .peer: return o.commits == 0 ? "none" : "\(o.commits)"
        }
    }

    private func boardItem(_ o: SimOffice) -> ProjectItem? {
        board.first { $0.repo == o.repo && $0.number == o.number }
    }

    private func stationName(_ o: SimOffice) -> String {
        o.owner == .me ? ConfigStore.shared.current.station(cwd: o.cwd, owner: "simcorp", repo: o.repo) : "work"
    }

    private func openRelease(_ repo: String, production: Bool) -> Int? {
        releases[repo]?.lastIndex { $0.state == "OPEN" && (production ? $0.isProduction : $0.isStaging) }
    }

    private func onDeck(_ repo: String) -> [ProjectItem] {
        board.filter { $0.repo == repo && $0.status == statuses.deck }
    }
    // MARK: the board, and the moves on it

    enum Blocked {
        case missing(String, () -> Void)
        case already(String)

        var words: String {
            switch self {
            case .missing(let what, _): return "sets up " + what
            case .already(let why): return why
            }
        }
    }

    struct Button: Identifiable {
        let name: String
        let label: String
        let blocked: Blocked?
        var shown = true
        var id: String { name }
    }

    struct Group: Identifiable { let id: String; let note: String?; let buttons: [Button] }

    private func button(_ name: String, _ label: String? = nil, _ blocked: Blocked? = nil, shown: Bool = true) -> Button {
        Button(name: name, label: label ?? name, blocked: blocked, shown: shown)
    }

    struct Setting: Identifiable {
        let id: String
        let note: String?
        let kind: Kind

        enum Kind {
            case pick(_ options: [String], now: String, set: (String) -> Void)
            case flag(on: Bool, set: (Bool) -> Void)
            case count(now: Int, of: [Int], set: (Int) -> Void)
        }
    }

    // MARK: setting the board

    static let activities: [(name: String, act: Activity)] = [
        ("coding", .coding("src")), ("reading code", .exploring), ("testing", .testing),
        ("writing", .writing), ("thinking", .thinking), ("QA testing", .qa),
        ("web research", .researching), ("waiting for you", .waiting),
        ("sleeping", .sleeping),
    ]
    static let noSession = "no session"

    static let pullStates = ["none", "open", "approved", "checks failing", "merged", "closed"]

    private func pullOf(_ o: SimOffice) -> String {
        switch o.owner {
        case .teammate: return o.prOpen ? "open" : "none"
        case .peer: return "none"
        case .me:
            guard let pr = o.pull else { return "none" }
            switch pr.state {
            case "MERGED": return "merged"
            case "CLOSED": return "closed"
            default:
                if pr.checks == "failure" { return "checks failing" }
                return pr.reviewDecision == "APPROVED" ? "approved" : "open"
            }
        }
    }

    private func setPullState(_ state: String) {
        guard let o = office, let i = index(o.uid) else { return }
        if o.owner == .teammate {
            offices[i].prOpen = state != "none"
            if state != "none" { feedEvent("pr_open", repo: o.repo, branch: o.branch, pr: o.number, title: o.title) }
            return pushGitHub()
        }
        guard o.owner == .me else { return }
        guard state != "none" else { return setPull(nil, on: o.uid) }
        let n = o.home.issue ?? o.number
        let url = "https://example.invalid/\(o.repo)/\(n)", title = "work on \(o.branch)"
        var pr = PullRequest(number: n, title: title, state: "OPEN", reviewDecision: "REVIEW_REQUIRED", isDraft: false, url: url)
        switch state {
        case "approved": pr = PullRequest(number: n, title: title, state: "OPEN", reviewDecision: "APPROVED", isDraft: false, url: url)
        case "checks failing": pr.checks = "failure"
        case "merged": pr = PullRequest(number: n, title: title, state: "MERGED", reviewDecision: "APPROVED", isDraft: false, url: url)
        case "closed": pr = PullRequest(number: n, title: title, state: "CLOSED", reviewDecision: "", isDraft: false, url: url)
        default: break
        }
        setPull(pr, on: o.uid)
    }

    static let pipelines = ["trunk → staging → production", "no staging branch", "every merge deploys", "ships on tags"]
    private var pipelineOf: String {
        if shipsOnMerge.contains(targetRepo) { return SimulatorModel.pipelines[2] }
        if shipsOnTag.contains(targetRepo) { return SimulatorModel.pipelines[3] }
        return noStaging.contains(targetRepo) ? SimulatorModel.pipelines[1] : SimulatorModel.pipelines[0]
    }

    private func normalPipeline() {
        let repo = targetRepo, cfg = ConfigStore.shared.current
        noStaging.remove(repo)
        shipsOnMerge.remove(repo)
        shipsOnTag.remove(repo)
        github.inject(pipeline: SimulatorModel.flow, for: root(repo))
        pushGitHub()
    }

    static let releaseStates = ["none", "open", "merged"]
    static let productionStates = ["none", "open, untested", "open, tested", "merged"]

    private func stagingOf(_ repo: String) -> String {
        guard let last = releases[repo]?.last(where: { $0.isStaging }) else { return "none" }
        return last.state == "MERGED" ? "merged" : last.state == "OPEN" ? "open" : "none"
    }

    private func productionOf(_ repo: String) -> String {
        guard let last = releases[repo]?.last(where: { $0.isProduction }) else { return "none" }
        if last.state == "MERGED" { return "merged" }
        guard last.state == "OPEN" else { return "none" }
        return last.untested ? "open, untested" : "open, tested"
    }

    var position: [Setting] {
        let repo = targetRepo
        var out: [Setting] = []
        let now = office.flatMap { sessions[$0.uid] }
        let activityNow = now.flatMap { s in SimulatorModel.activities.first { $0.act == s.activity }?.name }
            ?? (now == nil ? SimulatorModel.noSession : SimulatorModel.activities[0].name)
        out.append(Setting(id: "session", note: nil, kind: .pick([SimulatorModel.noSession] + SimulatorModel.activities.map(\.name),
                                                                 now: activityNow) { [weak self] pick in
            self?.setSession(pick)
        }))
        if let o = office, o.owner != .peer {
            out.append(Setting(id: "pull request", note: nil, kind: .pick(o.owner == .teammate ? ["none", "open"] : SimulatorModel.pullStates,
                                                                          now: self.pullOf(o)) { [weak self] pick in
                self?.setPullState(pick)
            }))
        }
        out.append(Setting(id: "commits ahead", note: nil, kind: .count(now: self.office?.commits ?? 0, of: [0, 1, 2, 4, 8, 16]) { [weak self] n in
            guard let self, let i = self.office.flatMap({ self.index($0.uid) }) else { return }
            offices[i].commits = n
            pushScan()
            station.simulateGitHub()
        }))
        out.append(Setting(id: "branch pushed", note: nil, kind: .flag(on: self.office?.pushed ?? false) { [weak self] on in
            guard let self, let i = self.office.flatMap({ self.index($0.uid) }) else { return }
            offices[i].pushed = on
            pushScan()
        }))
        out.append(Setting(id: "on the board", note: nil,
                           kind: .pick([SimulatorModel.offBoard] + self.columns,
                                       now: self.office.flatMap(self.boardItem)?.status ?? SimulatorModel.offBoard) { [weak self] pick in
            self?.setColumn(pick)
        }))
        out.append(Setting(id: "\(repo)'s pipeline", note: nil, kind: .pick(SimulatorModel.pipelines, now: self.pipelineOf) { [weak self] pick in
            guard let self else { return }
            switch pick {
            case SimulatorModel.pipelines[1]: press("Repo: No staging")
            case SimulatorModel.pipelines[2]: press("Repo: Ships on merge")
            case SimulatorModel.pipelines[3]: press("Repo: Ships on tags")
            default: normalPipeline(); note("sim", "\(targetRepo): trunk → staging → production")
            }
        }))
        out.append(Setting(id: "\(repo)'s staging release", note: nil,
                           kind: .pick(SimulatorModel.releaseStates, now: self.stagingOf(repo)) { [weak self] pick in
            self?.setStaging(pick)
        }))
        out.append(Setting(id: "\(repo)'s production release", note: nil,
                           kind: .pick(SimulatorModel.productionStates, now: self.productionOf(repo)) { [weak self] pick in
            self?.setProduction(pick)
        }))
        out.append(Setting(id: "\(self.peerName) on the network", note: nil, kind: .flag(on: self.peerHere) { [weak self] on in
            self?.press(on ? "Peer: Arrive" : "Peer: Leave")
        }))
        out.append(Setting(id: "night", note: nil, kind: .flag(on: self.station.sim?.night == true) { [weak self] on in
            self?.press(on ? "Night" : "Day")
        }))
        return out
    }

    static let offBoard = "not on the board"

    private func setSession(_ pick: String) {
        guard let o = office else { return }
        guard pick != SimulatorModel.noSession else {
            sessions[o.uid] = nil
            return pushScan()
        }
        guard let act = SimulatorModel.activities.first(where: { $0.name == pick })?.act else { return }
        if sessions[o.uid] == nil {
            guard let i = index(o.uid) else { return }
            if offices[i].cwd.isEmpty { offices[i].cwd = worktree(o.repo, "sim-\(offices[i].number)") }
            makeDir(offices[i].cwd)
            offices[i].pushed = true
            offices[i].commits = max(1, offices[i].commits)
            startSession(in: o.uid, activity: act)
        }
        sessions[o.uid]?.activity = act
        sessions[o.uid]?.last = act == .waiting ? station.now.addingTimeInterval(-600) : station.now
        pushScan()
    }

    private func setColumn(_ pick: String) {
        guard let o = office else { return }
        if pick == SimulatorModel.offBoard {
            board.removeAll { $0.repo == o.repo && $0.number == o.number }
            return pushGitHub()
        }
        guard let it = boardItem(o) else {
            board.append(item(o.repo, o.number, o.title, pick, o.who))
            return pushGitHub()
        }
        move([it], to: pick)
    }

    private func setStaging(_ pick: String) {
        let repo = targetRepo
        switch pick {
        case "none": releases[repo]?.removeAll { $0.isStaging }; pushGitHub()
        case "open":
            if openRelease(repo, production: false) == nil { press("Release: Staging opens") }
        default:
            if openRelease(repo, production: false) == nil { press("Release: Staging opens") }
            station.after(1) { [weak self] in self?.press("Release: Staging merges") }
        }
    }

    private func setProduction(_ pick: String) {
        let repo = targetRepo
        switch pick {
        case "none": releases[repo]?.removeAll { $0.isProduction }; pushGitHub()
        case "open, untested":
            if openRelease(repo, production: true) == nil { press("Release: Production opens") }
        case "open, tested":
            if openRelease(repo, production: true) == nil { press("Release: Production opens") }
            station.after(1) { [weak self] in self?.press("Release: Mark tested") }
        default:
            if openRelease(repo, production: true) == nil { press("Release: Production opens") }
            station.after(1) { [weak self] in self?.press("Release: Mark tested") }
            station.after(2) { [weak self] in self?.press("Release: Production merges") }
        }
    }

    // MARK: laying the ground for a move

    private func layMine() {
        guard let o = office, let i = index(o.uid) else { return }
        if offices[i].owner != .me {
            offices[i].owner = .me
            offices[i].who = "me"
            offices[i].prOpen = false
        }
        if offices[i].cwd.isEmpty { offices[i].cwd = worktree(offices[i].repo, "sim-\(offices[i].number)") }
        makeDir(offices[i].cwd)
        offices[i].pushed = true
        offices[i].commits = max(1, offices[i].commits)
        if sessions[o.uid] == nil { startSession(in: o.uid, activity: .coding("src")) }
        pushScan()
        pushGitHub()
    }

    private func layOpenPull() {
        layMine()
        setPullState("open")
    }

    private func layTeammate(withPull: Bool) {
        if leoOffice == nil || (withPull && leoOpenPR == nil) || (!withPull && leoBranchWithoutPR == nil) {
            run("Teammate: New branch")
        }
        if withPull, let o = leoBranchWithoutPR, let i = index(o.uid) {
            offices[i].prOpen = true
            feedEvent("pr_open", repo: o.repo, branch: o.branch, pr: o.number, title: o.title)
            pushGitHub()
        }
    }

    private func layBotPull() {
        if botPRs[targetRepo]?.isEmpty != false { run("Bot: Open PR") }
    }

    private func layPeer() {
        if !peerHere { run("Peer: Arrive") }
        if kimOffice == nil { addPeerOffice(repo: targetRepo, aged: false); pushPeer() }
    }

    private func layInStorage() {
        let repo = targetRepo
        guard !board.contains(where: { $0.repo == repo && $0.status == statuses.storage }) else { return }
        if let o = office, boardItem(o) != nil { return setColumn(statuses.storage) }
        let n = nextIssue(repo)
        board.append(item(repo, n, "stored work \(n)", statuses.storage, "me"))
        pushGitHub()
    }

    private func layOnDeck() {
        let repo = targetRepo
        guard onDeck(repo).isEmpty else { return }
        let n = nextIssue(repo)
        board.append(item(repo, n, "tested work \(n)", statuses.deck, "me"))
        pushGitHub()
    }

    private func layStaging() {
        if noStaging.contains(targetRepo) { normalPipeline() }
        if openRelease(targetRepo, production: false) == nil { run("Release: Staging opens") }
    }

    private func layProduction() {
        if openRelease(targetRepo, production: true) == nil { run("Release: Production opens") }
    }

    // MARK: the moves

    var groups: [Group] {
        let repo = targetRepo
        let o = office
        let mine = o?.owner == .me
        let hasSession = targetSession != nil
        let needsMine: Blocked? = mine && hasSession ? nil
            : .missing(mine ? "a session here" : "this office as mine, with a session", { [weak self] in self?.layMine() })
        let needsOpenPull: Blocked? = mine && o?.pull?.state == "OPEN" ? nil
            : .missing("an open pull request here", { [weak self] in self?.layOpenPull() })
        let teammateBranch: Blocked? = leoBranchWithoutPR != nil ? nil
            : .missing("a branch of \(teammate)'s on \(repo)", { [weak self] in self?.layTeammate(withPull: false) })
        let teammateAny: Blocked? = leoOffice != nil ? nil
            : .missing("a branch of \(teammate)'s on \(repo)", { [weak self] in self?.layTeammate(withPull: false) })
        let teammatePull: Blocked? = leoOpenPR != nil ? nil
            : .missing("a pull request of \(teammate)'s on \(repo)", { [weak self] in self?.layTeammate(withPull: true) })
        let botPull: Blocked? = botPRs[repo]?.isEmpty == false ? nil
            : .missing("a pull request of the bot's on \(repo)", { [weak self] in self?.layBotPull() })
        let peerOffice: Blocked? = kimOffice != nil ? nil
            : .missing("an office of \(peerName)'s", { [weak self] in self?.layPeer() })
        let stagingOpen: Blocked? = openRelease(repo, production: false) != nil ? nil
            : .missing("an open staging release on \(repo)", { [weak self] in self?.layStaging() })
        let productionOpen: Blocked? = openRelease(repo, production: true) != nil ? nil
            : .missing("an open production release on \(repo)", { [weak self] in self?.layProduction() })

        return [
            Group(id: "Mine", note: "on the office picked above", buttons: [
                button("Prompt", "You prompt it", needsMine),
                button("Commit", "It commits", needsMine),
                button("Switch branch", "It switches branch", needsMine),
                button("Session ends", "The session ends", needsMine),
                button("Probe: Read code", "It sends a probe to read code", needsMine),
                button("Probe: Research", "It sends a probe to research the web", needsMine),
                button("Probe: Done", "Its oldest probe is done", probes[target]?.isEmpty == false ? nil : .already("no probe out from this office")),
                button("Open PR", "Opens a pull request",
                       mine && o?.pull != nil ? .already("this office already has a pull request") : needsMine),
                button("Approve PR", "…is approved", needsOpenPull),
                button("Checks failing", "…checks go red", needsOpenPull),
                button("Merge PR", "…is merged", needsOpenPull),
                button("Close PR", "…is closed unmerged", needsOpenPull),
                button("New branch in repo", "A new office of mine in \(repo)"),
                button("New branch, no issue", "A new office of mine in \(repo), on a branch with no issue in its name"),
            ]),
            Group(id: "Teammate (\(teammate))", note: "on the target office when it is \(teammate)'s, else on his newest branch in \(repo)", buttons: [
                button("Teammate: New branch", "A new branch in \(repo)"),
                button("Teammate: Push", "He pushes", teammateAny),
                button("Teammate: Open PR", "He opens a pull request", teammateBranch),
                button("Teammate: Merge PR", "…merges it", teammatePull),
                button("Teammate: Close PR", "…closes it unmerged", teammatePull),
                button("Teammate: Close PR (feed lags)", "…closes it, the feed lagging", teammatePull),
            ]),
            Group(id: "Bots (dependabot)", note: "on \(repo): an object in decon, cleared into storage on merge, ejected on close", buttons: [
                button("Bot: Open PR", "It opens a pull request in \(repo)"),
                button("Bot: Merge PR", "…is merged", botPull),
                button("Bot: Close PR", "…is closed unmerged", botPull),
            ]),
            Group(id: "Peer (\(peerName))", note: "over the network, on her newest office", buttons: [
                button("Peer: New office", "A new office in \(repo)"),
                button("Peer: Push branch", "She pushes", peerOffice),
                button("Peer: Kick office", "You kick this office off the station",
                       o == nil ? .already("no office picked") : nil),
                button("Peer: Same branch as teammate", "She is on leo's branch too"),
                button("Peer: To the lounge", "Her minion takes a break on the sofa", peerOffice),
                button("Peer: To the gym", "Her minion takes a turn in the gym", peerOffice),
                button("Peer: Back to work", "Her minion goes back to her office", peerOffice),
                button("Peer: Arrive", shown: false),
                button("Peer: Leave", shown: false),
            ]),
            Group(id: "A source speaks", note: "Says a stage to the record as the source picked, by the rules; the floor reacts. No GitHub, no board.", buttons:
                Stage.allCases.filter { $0 >= .ready }.map {
                    button("Stage: \($0)", "→ \($0)", o == nil ? .already("no office picked") : nil)
                }),
            Group(id: "Late polls", note: "a source asked again, or answering after the fact: where the ordering bugs live", buttons: [
                button("GitHub: Poll", "GitHub is asked again"),
                button("Scan: again", "The scanner looks again"),
                button("Board: Catch up", "The board catches up: \(repo) storage → deck",
                       board.contains { $0.repo == repo && $0.status == statuses.storage } ? nil
                           : .missing("something of \(repo) in storage", { [weak self] in self?.layInStorage() })),
                button("Board: Catch up (yard first)", "The board catches up and the yard sees it before the world does",
                       board.contains { $0.repo == repo && $0.status == statuses.storage } ? nil
                           : .missing("something of \(repo) in storage", { [weak self] in self?.layInStorage() })),
                button("Release: Staging merges (board lags)", "Staging merges, the board lagging", stagingOpen),
            ]),
            Group(id: "Release (\(repo))", note: nil, buttons: [
                button("Release: Staging opens", "Staging opens",
                       noStaging.contains(repo) ? .already("\(repo) has no staging branch")
                           : openRelease(repo, production: false) != nil ? .already("a staging release is already open") : nil),
                button("Release: Staging merges", "Staging merges", stagingOpen),
                button("Release: Staging closes", "Staging closes unmerged", stagingOpen),
                button("Release: Production opens", "Production opens, untested",
                       openRelease(repo, production: true) != nil ? .already("a production release is already open") : nil),
                button("Release: Mark tested", "QA passes it",
                       noStaging.contains(repo)
                           ? (releases[repo]?.contains(where: { $0.state == "OPEN" && $0.isProduction && $0.untested }) == true ? nil
                               : .missing("an untested release on \(repo)", { [weak self] in self?.layProduction() }))
                           : (onDeck(repo).isEmpty ? .missing("something on \(repo)'s deck", { [weak self] in self?.layOnDeck() }) : nil)),
                button("Release: Production merges", "Production merges: it ships", productionOpen),
                button("Release: Hotfix opens", "The office picked above opens a pull request straight into production",
                       hotfixPRs[repo]?.contains(where: { $0.state == "OPEN" }) == true ? .already("a hotfix is already open") : needsMine),
                button("Release: Hotfix merges", "The hotfix merges: it ships on its own",
                       hotfixPRs[repo]?.contains(where: { $0.state == "OPEN" }) == true ? nil : .missing("an open hotfix on \(repo)", { [weak self] in self?.run("Release: Hotfix opens") })),
                button("Deploy: Production starts", "A production deploy starts (usually a minute)",
                       inFlight(repo) ? .already("\(repo) is already in flight") : nil),
                button("Deploy: Goes live", "…it goes live", inFlight(repo) ? nil : .already("no deploy of \(repo) in flight")),
                button("Deploy: Fails", "…it fails", inFlight(repo) ? nil : .already("no deploy of \(repo) in flight")),
                button("Deploy: Cancelled", "…it is cancelled", inFlight(repo) ? nil : .already("no deploy of \(repo) in flight")),
                button("Deploy: Staging starts", "A staging deploy starts"),
                button("Errors: A new error", "Sentry: a new error"), button("Errors: A spike", "Sentry: an error spikes"),
                button("Deploy: Staging goes live", "…staging is live"),
                button("Deploy: Staging fails", "…the staging deploy fails"),
                button("Repo: No staging", shown: false),
                button("Repo: Ships on merge", shown: false),
                button("Repo: Ships on tags", shown: false),
                button("Release: Tag", "A release is tagged: it ships", shipsOnTag.contains(repo) ? nil : .already("\(repo) does not ship on tags")),
            ]),
            Group(id: "Everyone", note: nil, buttons: [
                button("Everyone to lounge", "To the lounge"), button("Breather", "One takes a break"),
                button("Everyone asleep", "All sessions quiet"),
                button("Bath", "To the bath"), button("Bath: the bowl", "A pee in the bath"),
                button("Chore", "A chore"), button("Workout", "A turn in the gym"),
                button("Coffee", "A coffee from the galley"), button("A bite", "A bite from the galley"),
                button("Mission control", "A turn in mission control"), button("Mission control: a console", "A seat at a console"),
                button("Mission control: the holo table", "A place at the holo table"),
                button("Meet in the hall", "A meeting in the hall"), button("Wedge carrier", "Wedge a carrier"),
                button("Night", shown: false), button("Day", shown: false),
                button("Hands: one free on the deck", shown: false),
            ]),
        ]
    }

    let timeNames = ["Pause", "Resume", "Step", "¼x", "½x", "1x", "4x", "16x"]

    var buttonNames: [String] { groups.flatMap(\.buttons).map(\.name) + timeNames }

    func quiesce() { peerBeat?.invalidate(); peerBeat = nil }

    private func inFlight(_ repo: String) -> Bool { station.missions.contains { $0.repo == repo && $0.ended == nil } }

    private func deployStation(_ repo: String) -> String {
        station.world.repoRoots.values.first { $0.repo == repo }?.station ?? station.world.fleet.ordered.first?.name ?? "work"
    }

    func press(_ name: String) {
        station.world.batch {
            note("press", name, .press(name))
            if name.hasPrefix("Target: ") {
                pick(String(name.dropFirst(8)))
            } else if name.hasPrefix("Board: Move "), let to = name.range(of: " to ") {
                let id = String(name[name.index(name.startIndex, offsetBy: 12)..<to.lowerBound])
                let column = String(name[to.upperBound...])
                guard let it = board.first(where: { "\($0.repo)#\($0.number)" == id }) else {
                    return note("skipped", "no board item \(id)", .skipped("no board item \(id)"))
                }
                move([it], to: column)
            } else if name.hasPrefix("Set: "), let eq = name.range(of: " = ") {
                setKnob(String(name[name.index(name.startIndex, offsetBy: 5)..<eq.lowerBound]), to: String(name[eq.upperBound...]))
            } else if timeNames.contains(name) {
                time(name)
            } else if let b = groups.flatMap(\.buttons).first(where: { $0.name == name }) {
                switch b.blocked {
                case nil:
                    run(name)
                case .already(let why):
                    note("skipped", why, .skipped(why))
                case .missing(let what, let lay):
                    note("set up", what)
                    lay()
                    station.after(1) { [weak self] in
                        guard let self else { return }
                        if let again = groups.flatMap(\.buttons).first(where: { $0.name == name }), let why = again.blocked {
                            return note("skipped", "set-up did not take: " + why.words, .skipped(why.words))
                        }
                        run(name)
                        refreshSoon()
                    }
                }
            } else {
                note("skipped", "no such button: \(name)", .skipped("no such button: \(name)"))
            }
            refreshSoon()
        }
    }

    private func refreshSoon() {
        guard !quiet else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.refresh() }
    }

    private func setKnob(_ id: String, to value: String) {
        let want = id.lowercased(), had = value.lowercased()
        guard let knob = position.first(where: { $0.id.lowercased() == want || $0.id.lowercased().hasSuffix(" " + want) }) else {
            return note("skipped", "no knob called \(id)", .skipped("no knob called \(id)"))
        }
        switch knob.kind {
        case .pick(let options, _, let set):
            guard let pick = options.first(where: { $0.lowercased() == had }) else {
                return note("skipped", "\(knob.id) has no setting \(value); it has " + options.joined(separator: ", "),
                            .skipped("\(knob.id) has no setting \(value)"))
            }
            set(pick)
            note("board", "\(knob.id): \(pick)")
        case .flag(_, let set):
            let on = ["yes", "on", "true"].contains(had)
            set(on)
            note("board", "\(knob.id): \(on ? "yes" : "no")")
        case .count(_, _, let set):
            guard let n = Int(had) else {
                return note("skipped", "\(knob.id) takes a number, not \(value)", .skipped("\(knob.id) takes a number"))
            }
            set(n)
            note("board", "\(knob.id): \(n)")
        }
    }

    private func pick(_ id: String) {
        guard let o = offices.first(where: { "\($0.repo)#\($0.number)" == id }) else {
            return note("skipped", "no office \(id)", .skipped("no office \(id)"))
        }
        target = o.uid
        note("sim", "target: " + o.label)
    }

    private func time(_ name: String) {
        switch name {
        case "Pause": paused = true; station.sim?.paused = true
        case "Resume": paused = false; station.sim?.paused = false
        case "Step": station.sim?.steps += 6
        default:
            speed = SimulatorModel.speedValue(name)
            station.sim?.timeScale = speed
        }
    }

    private func run(_ name: String) {
        let repo = targetRepo
        if name.hasPrefix("Stage: "), let stage = Stage.allCases.first(where: { "\($0)" == String(name.dropFirst(7)) }), let o = office {
            let works = station.world.works
            let record = works.find(repo: o.repo, issue: o.number) ?? works.find(repo: o.repo, pull: o.number)
                ?? works.note(repo: o.repo, branch: o.branch, issue: o.number)
            works.report(record, stage, by: stageSource, at: station.now)
            note("sim", "\(o.repo)#\(o.number) → \(stage) · \(stageSource.rawValue) · now \(record.stage.map { "\($0)" } ?? "-")")
            pushScan()
            return
        }
        switch name {
        case "New branch in repo":
            let n = nextIssue(repo)
            let o = addMine(repo: repo, number: n, slug: "sim-\(n)", branch: "gh-\(n)/new-work-\(n)",
                            title: "new work \(n)", activity: .coding("src"), commits: 2)
            board.append(item(repo, n, "new work \(n)", statuses.development, "me"))
            target = o.uid
            pushGitHub()
            pushScan()
        case "New branch, no issue":
            let n = nextIssue(repo)
            let o = addMine(repo: repo, number: n, slug: "sim-\(n)", branch: "claude/new-work-\(n)",
                            title: "new work \(n)", activity: .coding("src"), commits: 2)
            target = o.uid
            pushGitHub()
            pushScan()
        case "Commit":
            guard let o = office, let i = index(o.uid) else { return }
            offices[i].commits += 1
            pushScan()
            station.simulateGitHub()
        case "Prompt":
            guard var s = targetSession else { return }
            s.prompts += 1
            s.markers[.prompt] = UUID().uuidString
            s.last = station.now
            sessions[s.office] = s
            pushScan()
        case "Session ends":
            sessions[target] = nil
            probes[target] = nil
            pushScan()
        case "Probe: Read code", "Probe: Research":
            guard sessions[target] != nil else { return }
            nextProbe += 1
            probes[target, default: []].append((id: "probe-\(nextProbe)", activity: name.hasSuffix("Research") ? .researching : .exploring))
            pushScan()
        case "Probe: Done":
            guard probes[target]?.isEmpty == false else { return }
            probes[target]?.removeFirst()
            pushScan()
        case "Switch branch":
            guard let i = index(target) else { return }
            let n = nextIssue(offices[i].repo)
            offices[i].number = n
            offices[i].branch = "gh-\(n)/switched-\(n)"
            offices[i].title = "switched \(n)"
            offices[i].pull = nil
            board.append(item(offices[i].repo, n, "switched \(n)", statuses.development, "me"))
            sessions[target]?.last = station.now
            pushGitHub()
            pushScan()
        case "Open PR", "Approve PR", "Checks failing", "Merge PR", "Close PR":
            guard let o = office else { return }
            let n = o.home.issue ?? o.number
            let url = "https://example.invalid/\(o.repo)/\(n)"
            let title = "work on \(o.branch)"
            var pr = PullRequest(number: n, title: title, state: "OPEN", reviewDecision: "REVIEW_REQUIRED", isDraft: false, url: url)
            switch name {
            case "Approve PR": pr = PullRequest(number: n, title: title, state: "OPEN", reviewDecision: "APPROVED", isDraft: false, url: url)
            case "Checks failing": pr.checks = "failure"
            case "Merge PR": pr = PullRequest(number: n, title: title, state: "MERGED", reviewDecision: "APPROVED", isDraft: false, url: url)
            case "Close PR": pr = PullRequest(number: n, title: title, state: "CLOSED", reviewDecision: "", isDraft: false, url: url)
            default: break
            }
            setPull(pr, on: o.uid)

        case "Teammate: New branch":
            let n = nextIssue(repo)
            var o = makeOffice(repo: repo, number: n, branch: "gh-\(n)/teammate-\(n)", title: "teammate work \(n)",
                               owner: .teammate, who: teammate)
            o.pushed = true
            offices.append(o)
            board.append(item(repo, n, "teammate work \(n)", statuses.development, teammate))
            feedEvent("branch_create", repo: repo, branch: o.branch, pr: nil, title: nil)
            feedEvent("push", repo: repo, branch: o.branch, pr: nil, title: nil, detail: "1")
            pushGitHub()
        case "Teammate: Open PR":
            guard let o = leoBranchWithoutPR, let i = index(o.uid) else { return }
            offices[i].prOpen = true
            feedEvent("pr_open", repo: o.repo, branch: o.branch, pr: o.number, title: o.title)
            pushGitHub()
        case "Teammate: Push":
            guard let o = leoOffice, let i = index(o.uid) else { return }
            offices[i].commits += 1
            feedEvent("push", repo: o.repo, branch: o.branch, pr: o.prOpen ? o.number : nil, title: o.title,
                      detail: "\(offices[i].commits)")
            pushGitHub()
        case "Teammate: Merge PR", "Teammate: Close PR", "Teammate: Close PR (feed lags)":
            guard let o = leoOpenPR else { return }
            offices.removeAll { $0.uid == o.uid }
            let fate = name.contains("Merge PR") ? "MERGED" : "CLOSED"
            pullFates["\(o.repo)#\(o.number)"] = fate
            let answer = PullRequest(number: o.number, title: o.title, state: fate, reviewDecision: "", isDraft: false, url: "https://example.invalid/\(o.repo)/\(o.number)")
            github.inject(pull: answer, for: o.branch, repoRoot: root(o.repo))
            github.inject(pull: answer, number: o.number, repoRoot: root(o.repo))
            if !name.hasSuffix("(feed lags)") {
                feedEvent(fate == "MERGED" ? "pr_merge" : "pr_close", repo: o.repo, branch: o.branch, pr: o.number, title: o.title)
            }
            pushGitHub()

        case "Bot: Open PR":
            let n = nextIssue(repo)
            let names = ["lodash", "swift-argument-parser", "sentry", "alamofire", "rails"]
            let title = "bump \(names[n % names.count]) from 1.\(n % 9).0 to 1.\(n % 9 + 1).0"
            botPRs[repo, default: []].append((n, title, "dependabot/npm_and_yarn/\(names[n % names.count])-\(n)"))
            feedEvent("pr_open", repo: repo, branch: nil, pr: n, title: title, actor: bot)
            pushGitHub()
        case "Bot: Merge PR", "Bot: Close PR":
            guard let pr = botPRs[repo]?.first else { return }
            botPRs[repo]?.removeFirst()
            let fate = name == "Bot: Merge PR" ? "MERGED" : "CLOSED"
            pullFates["\(repo)#\(pr.number)"] = fate
            github.inject(pull: PullRequest(number: pr.number, title: pr.title, state: fate, reviewDecision: "", isDraft: false, url: "https://example.invalid/\(repo)/\(pr.number)"),
                          number: pr.number, repoRoot: root(repo))
            feedEvent(fate == "MERGED" ? "pr_merge" : "pr_close", repo: repo, branch: pr.branch, pr: pr.number, title: pr.title, actor: bot)
            pushGitHub()

        case "Peer: Arrive":
            peerHere = true
            if !offices.contains(where: { $0.owner == .peer }) { addPeerOffice(repo: repo, aged: true) }
            pushPeer()
        case "Peer: New office":
            peerHere = true
            addPeerOffice(repo: repo, aged: false)
            pushPeer()
        case "Peer: Push branch":
            guard let o = kimOffice, let i = index(o.uid) else { return }
            offices[i].pushed = true
            offices[i].commits += 1
            pushPeer()
        case "Peer: Leave":
            peerHere = false
            station.simulatePeerLeft(peerName)
        case "Peer: Kick office":
            guard let o = office else { return }
            station.simulateKick(roomKey: stationName(o) + "|" + o.home.key)

        case "GitHub: Poll":
            pushGitHub()
        case "Scan: again":
            pushScan()

        case "Board: Move":
            guard let it = office.flatMap(boardItem) else { return }
            move([it], to: column)
        case "Board: Catch up", "Board: Catch up (yard first)":
            move(board.filter { $0.repo == repo && $0.status == statuses.storage }, to: statuses.deck, yardFirst: name.hasSuffix("(yard first)"))

        case "Repo: Ships on merge":
            shipsOnMerge.insert(repo)
            github.inject(pipeline: Pipeline(trunk: SimulatorModel.trunk, staging: "", production: "", source: "workflow", why: "deploys on every push", ship: .merge), for: root(repo))
            pushGitHub()
        case "Repo: Ships on tags":
            shipsOnTag.insert(repo)
            github.inject(pipeline: Pipeline(trunk: SimulatorModel.trunk, staging: "", production: "", source: "tags",
                                             why: "no release branch: what is tagged on \(SimulatorModel.trunk) has shipped", ship: .tag), for: root(repo))
            move(board.filter { $0.repo == repo && ($0.status == statuses.deck || $0.status == statuses.cleared) }, to: statuses.storage)
            pushGitHub()
        case "Release: Tag":
            nextRelease += 1
            let name = "v0.\(nextRelease - 9000)"
            let tag = ReleasePR(number: 0, title: name, base: SimulatorModel.trunk, head: name, state: "MERGED",
                                url: "https://example.invalid/\(repo)/releases/tag/\(name)", labels: [], mergedAt: station.now,
                                production: true, staging: false, tag: true)
            releases[repo, default: []].append(tag)
            launches.append((repo, tag))
            pushGitHub()
        case "Repo: No staging":
            noStaging.insert(repo)
            github.inject(pipeline: Pipeline(trunk: SimulatorModel.trunk, staging: "", production: "master"), for: root(repo))
            move(board.filter { $0.repo == repo && ($0.status == statuses.deck || $0.status == statuses.cleared) }, to: statuses.storage)
            pushGitHub()
        case "Release: Staging opens":
            nextRelease += 1
            releases[repo, default: []].append(ReleasePR(number: nextRelease, title: "release to staging", base: Pipeline.stagingName,
                                                         head: SimulatorModel.trunk, state: "OPEN",
                                                         url: "https://example.invalid/\(repo)/\(nextRelease)", labels: [], mergedAt: nil))
            pushGitHub()
        case "Release: Staging merges", "Release: Staging merges (board lags)":
            guard let i = openRelease(repo, production: false) else { return }
            let pr = releases[repo]![i]
            releases[repo]![i] = ReleasePR(number: pr.number, title: pr.title, base: pr.base, head: pr.head, state: "MERGED",
                                           url: pr.url, labels: pr.labels, mergedAt: station.now, production: pr.production, staging: pr.staging)
            if ConfigStore.shared.current.project != nil { launches.append((repo, releases[repo]![i])) }
            pushGitHub()
            if name.hasSuffix("(board lags)") {
                let stored = board.indices.filter { board[$0].repo == repo && board[$0].status == statuses.storage }
                for i in stored { board[i].prURLs = ["https://example.invalid/\(repo)/pull/\(board[i].number + 1000)"] }
                var git = GitHubResolver.Cargo(storage: 0, deck: stored.count, storageNumbers: [], deckNumbers: stored.map { board[$0].number + 1000 })
                git.exact = true
                github.inject(cargo: git, for: root(repo))
                pushGitHub()
            } else {
                move(board.filter { $0.repo == repo && $0.status == statuses.storage }, to: statuses.deck)
            }
        case "Release: Staging closes":
            guard let i = openRelease(repo, production: false) else { return }
            let pr = releases[repo]![i]
            releases[repo]![i] = ReleasePR(number: pr.number, title: pr.title, base: pr.base, head: pr.head, state: "CLOSED",
                                           url: pr.url, labels: pr.labels, mergedAt: nil, production: pr.production, staging: pr.staging)
            pushGitHub()
        case "Deploy: Production starts":
            station.handle(.deployStarted(station: deployStation(repo), repo: repo, production: true, expected: 60, release: "#\(nextRelease + 1)"))
        case "Deploy: Goes live", "Deploy: Fails", "Deploy: Cancelled":
            let outcome: DeployOutcome = name.hasSuffix("live") ? .live : name.hasSuffix("Fails") ? .failed : .cancelled
            station.handle(.deployEnded(station: deployStation(repo), repo: repo, production: true, outcome: outcome))
        case "Errors: A new error", "Errors: A spike":
            let project = repo + "-production"
            var issues = station.world.errorsByProject[project]?.issues ?? []
            if issues.isEmpty { _ = station.world.hear([.errors(repo: repo, project: project, issues: [])]) }
            let n = issues.count + 1
            issues.insert(SentryIssue(id: "\(n)", title: name.hasSuffix("spike") ? "TypeError: Cannot read properties of undefined (reading 'artist')" : "PaymentError: card declined",
                                      count: name.hasSuffix("spike") ? 480 : 2, firstSeen: station.now.addingTimeInterval(name.hasSuffix("spike") ? -86400 : -90), lastSeen: station.now,
                                      hourly: name.hasSuffix("spike") ? Array(repeating: 4, count: 23) + [90] : []), at: 0)
            for e in station.world.hear([.errors(repo: repo, project: project, issues: issues)]) { station.handle(e) }
        case "Deploy: Staging starts":
            station.world.learn(.staging(repo: repo, .deploy(.running(since: station.now, usual: 40))), repo: repo)
            station.handle(.deployStarted(station: deployStation(repo), repo: repo, production: false, expected: 40, release: ""))
        case "Deploy: Staging goes live", "Deploy: Staging fails":
            let outcome: DeployOutcome = name.hasSuffix("live") ? .live : .failed
            station.world.learn(.staging(repo: repo, .deploy(outcome == .live ? .live : .failed)), repo: repo)
            station.handle(.deployEnded(station: deployStation(repo), repo: repo, production: false, outcome: outcome))
        case "Release: Production opens":
            nextRelease += 1
            let bare = noStaging.contains(repo)
            releases[repo, default: []].append(ReleasePR(number: nextRelease, title: "release to production", base: bare ? "master" : Pipeline.productionName,
                                                         head: bare ? "release/v\(nextRelease)" : Pipeline.stagingName, state: "OPEN",
                                                         url: "https://example.invalid/\(repo)/\(nextRelease)", labels: ["untested"], mergedAt: nil,
                                                         production: true, staging: false))
            pushGitHub()
        case "Release: Mark tested":
            if let i = releases[repo]?.lastIndex(where: { $0.state == "OPEN" && $0.isProduction && $0.untested }) {
                let pr = releases[repo]![i]
                releases[repo]![i] = ReleasePR(number: pr.number, title: pr.title, base: pr.base, head: pr.head,
                                               state: pr.state, url: pr.url,
                                               labels: pr.labels.filter { !$0.lowercased().contains("untested") }, mergedAt: nil, production: pr.production, staging: pr.staging)
            }
            move(onDeck(repo), to: statuses.cleared)
        case "Release: Production merges":
            guard let i = openRelease(repo, production: true) else { return }
            let pr = releases[repo]![i]
            let merged = ReleasePR(number: pr.number, title: pr.title, base: pr.base, head: pr.head, state: "MERGED",
                                   url: pr.url, labels: pr.labels.filter { $0 != "untested" }, mergedAt: station.now, production: pr.production, staging: pr.staging)
            releases[repo]![i] = merged
            launches.append((repo, merged))
            pushGitHub()
            let shipping = repo
            station.after(6) { [weak self] in
                guard let self else { return }
                let st = self.statuses
                move(board.filter { $0.repo == shipping && ($0.status == st.cleared || $0.status == st.deck || (self.noStaging.contains(shipping) && $0.status == st.storage)) }, to: st.shipped)
            }

        case "Release: Hotfix opens":
            guard let o = office, o.owner == .me else { return }
            let n = o.home.issue ?? o.number
            let url = "https://example.invalid/\(o.repo)/\(n)"
            setPull(PullRequest(number: n, title: "hotfix: \(o.title)", state: "OPEN", reviewDecision: "APPROVED", isDraft: false, url: url), on: o.uid)
            var pr = ReleasePR(number: n, title: "hotfix: \(o.title)", base: Pipeline.productionName, head: o.branch,
                               state: "OPEN", url: url, labels: [], mergedAt: nil, production: true, staging: false)
            pr.hotfix = true
            hotfixPRs[o.repo, default: []].append(pr)
            pushGitHub()
        case "Release: Hotfix merges":
            guard let i = hotfixPRs[repo]?.lastIndex(where: { $0.state == "OPEN" }) else { return }
            var pr = hotfixPRs[repo]![i]
            pr = { var m = ReleasePR(number: pr.number, title: pr.title, base: pr.base, head: pr.head, state: "MERGED", url: pr.url,
                                     labels: pr.labels, mergedAt: station.now, production: true, staging: false); m.hotfix = true; return m }()
            hotfixPRs[repo]![i] = pr
            hotfixLaunches.append((repo, pr))
            if let o = offices.first(where: { $0.repo == repo && $0.pull?.number == pr.number }) {
                setPull(PullRequest(number: pr.number, title: pr.title, state: "MERGED", reviewDecision: "APPROVED", isDraft: false, url: pr.url), on: o.uid)
            } else {
                pushGitHub()
            }
            let shipping = repo, number = pr.number
            station.after(6) { [weak self] in
                guard let self else { return }
                station.handle(.deployStarted(station: deployStation(shipping), repo: shipping, production: true, expected: 60, release: "#\(number)"))
            }
        case "Night": station.simulate(.night(true))
        case "Day": station.simulate(.night(false))
        case "Everyone to lounge": station.simulate(.lounge)
        case "Breather": station.simulate(.breather(.lounge))
        case "Everyone asleep": station.simulate(.turnIn)
        case "Peer: Same branch as teammate": peerSharesTeammate = true; pushPeer()
        case "Peer: To the lounge": peerDoing = "lounge"; pushPeer()
        case "Peer: To the gym": peerDoing = "gym"; pushPeer()
        case "Peer: Back to work": peerDoing = nil; pushPeer()
        case "Bath": station.simulate(.bath(shower: true))
        case "Bath: the bowl": station.simulate(.bath(shower: false))
        case "Chore": station.simulate(.chore)
        case "Meet in the hall": station.simulate(.meet)
        case "Workout": station.simulate(.workout)
        case "Mission control": station.simulate(.mission(seated: nil))
        case "Mission control: a console": station.simulate(.mission(seated: true))
        case "Mission control: the holo table": station.simulate(.mission(seated: false))
        case "Coffee": station.simulate(.galley(.coffee))
        case "A bite": station.simulate(.galley(.bite))
        case "Wedge carrier": station.simulate(.wedge)
        case "Hands: one free on the deck": station.simulate(.handFree)

        default:
            note("skipped", "no such button: \(name)", .skipped("no such button: \(name)"))
        }
    }

    private func addPeerOffice(repo: String, aged: Bool) {
        let n = nextIssue(repo)
        var o = makeOffice(repo: repo, number: n, branch: "gh-\(n)/peer-work-\(n)", title: "peer work \(n)",
                           owner: .peer, who: peerName)
        o.pushed = aged
        o.commits = aged ? 2 : 0
        o.startedAt = aged ? station.now.addingTimeInterval(-3600) : station.now
        offices.append(o)
    }

    // MARK: the log

    private let lines = SimLog()
    var quiet: Bool { get { lines.quiet } set { lines.quiet = newValue } }

    nonisolated func note(_ kind: String, _ text: String, _ record: SimRecord? = nil) {
        lines.add(kind: kind, text: text, record: record)
        guard !lines.quiet else { return }
        DispatchQueue.main.async { [weak self] in self?.objectWillChange.send() }
    }

    var logText: String { lines.text }
    var logLines: [String] { lines.ordered }
    var records: [SimRecord] { lines.records }

    nonisolated static func describe(_ e: WorldEvent) -> String {
        switch e {
        case .boardMoved(let it, let from, let to): return "boardMoved \(it.repo)#\(it.number) \(from ?? "—") -> \(to)"
        case .pullRequestOpened(let repo, let n, let who): return "pullRequestOpened \(repo)#\(n) by \(who)"
        case .pullRequestClosed(let repo, let who, let key): return "pullRequestClosed \(repo) \(who) \(key)"
        case .issueStarted(let repo, let n, let who, _): return "issueStarted \(repo)#\(n) by \(who)"
        case .peerArrived(let n): return "peerArrived \(n)"
        case .peerLeft(let n): return "peerLeft \(n)"
        case .office(let st, let news, let why):
            let what: String
            switch news {
            case .opened(let key, _, .shuttle(let who)): what = "opened \(st)|\(key) by shuttle for \(who ?? "anyone")"
            case .opened(let key, _, let via): what = "opened \(st)|\(key) \(via)"
            case .renamed(let from, let to): what = "renamed \(st)|\(from) -> \(to)"
            case .status(let key, _, let merged, let closedAt): what = "status \(st)|\(key)\(merged ? " merged" : "")\(closedAt == nil ? "" : " closed")"
            case .gone(let key): what = "gone \(st)|\(key)"
            }
            return "office " + what + (why.isEmpty ? "" : " (\(why))")
        case .crewRoster(let m): return "crewRoster \(m.keys.sorted().joined(separator: ","))"
        case .crewActivity(let a): return "crewActivity \(a.login) \(a.kind) \(a.label)"
        case .crewHidden: return "crewHidden"
        case .layoutChanged: return "layoutChanged"
        case .markersChanged: return "markersChanged"
        case .worldLoaded: return "worldLoaded"
        case .log(let t): return "log: \(t)"
        case .errorsClimbed(let repo, let level, let n): return "errorsClimbed \(repo) \(level.words) \(n) in the last hour"
        case .chime(let s): return "chime \(s)"
        case .deployStarted(_, let repo, let production, let expected, let release, _): return "deployStarted \(repo) \(release) \(production ? "production" : "staging") ~\(Int(expected))s"
        case .deployEnded(_, let repo, let production, let outcome): return "deployEnded \(repo) \(production ? "production" : "staging") \(outcome)"
        case .prompt(_, let key, _, let n): return "prompt \(key) x\(n)"
        }
    }
}

enum SimRecord {
    case press(String)
    case skipped(String)
    case event(WorldEvent)
    case command(Command, by: String)

    var words: String {
        switch self {
        case .press(let n): return "press \(n)"
        case .skipped(let why): return "skipped: \(why)"
        case .event(let e): return "event \(SimulatorModel.describe(e))"
        case .command(let c, let who): return "command \(who): \(c.words)"
        }
    }
}

final class SimLog: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []
    private var typed: [SimRecord] = []
    var quiet = false
    private static let stamp: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f
    }()

    private var whole: [String] = []

    func add(kind: String, text: String, record: SimRecord?) {
        lock.lock(); defer { lock.unlock() }
        let line = "\(SimLog.stamp.string(from: Date()))  \(kind)  \(text)"
        lines.insert(line, at: 0)
        if lines.count > 400 { lines.removeLast(lines.count - 400) }
        whole.append(line)
        if whole.count > 20000 { whole.removeFirst(whole.count - 20000) }
        if let record { typed.append(record) }
        if typed.count > 20000 { typed.removeFirst(typed.count - 20000) }
    }

    var records: [SimRecord] {
        lock.lock(); defer { lock.unlock() }
        return typed
    }

    var ordered: [String] {
        lock.lock(); defer { lock.unlock() }
        return whole
    }

    var text: String {
        lock.lock(); defer { lock.unlock() }
        return lines.joined(separator: "\n")
    }
}
// MARK: the simulator's way in

final class SimHooks {
    var onEvent: ((WorldEvent) -> Void)?
    var pullState: ((String, Int) -> String?)?
    var onCommand: ((Command, String) -> Void)?
    var timeScale = 1.0
    var paused = false
    var steps = 0
    var night: Bool?
    var clock = 0.0
    var lastReal = 0.0
}

enum SimNudge { case bath(shower: Bool), breather(Place), chore, galley(Command.Fare), handFree, lounge, meet, mission(seated: Bool?), night(Bool?), turnIn, wedge, workout }

extension StationController {
    func stepSimulated(seconds: Double) {
        guard let sim else { return }
        pendingLock.lock(); let work = pending; pending.removeAll(); pendingLock.unlock()
        for w in work { w() }
        var budget = seconds
        while budget > 0 {
            let step = min(simulation.substep, budget)
            budget -= step
            sim.clock += step
            tick(now: sim.clock)
        }
    }

    func advanceSimulated(to time: TimeInterval) {
        guard let sim else { return }
        let real = sim.lastReal == 0 ? 0 : min(0.25, max(0, time - sim.lastReal))
        sim.lastReal = time
        var budget = sim.paused ? Double(sim.steps) * simulation.substep : real * sim.timeScale
        sim.steps = 0
        while budget > 0 {
            let step = min(simulation.substep, budget)
            budget -= step
            sim.clock += step
            tick(now: sim.clock)
        }
    }

    func simulate(scan: ScanResult) { enqueue { [self] in apply(scan) } }

    func simulateGitHub() { enqueue { [self] in onGitHubUpdate() } }

    func simulate(peer: PeerSnapshot) { enqueue { [self] in receivePeer(peer) } }
    func simulatePeerLeft(_ name: String) { enqueue { [self] in dropPeer(name) } }

    func simulateKick(roomKey key: String) {
        enqueue { [self] in handle(world.kick(roomKey: key)); flushScene() }
    }

    private func free(_ m: Minion) {
        m.busy = false
        m.activity = .waiting
        if let c = m.current, !c.isRest { finish(m) }
    }

    func simulate(_ nudge: SimNudge) {
        enqueue { [self] in
            switch nudge {
            case .bath(let shower):
                let could = minions.values.filter { !$0.isSubagent && !$0.onJob && !$0.bathing && !$0.exercising && !$0.hasLoad }
                let m = could.first(where: { !$0.isCrew && !$0.busy && $0.place == .lounge })
                    ?? could.first(where: { !$0.isCrew && !$0.busy })
                    ?? could.first(where: { !$0.isCrew && $0.activity == .waiting })
                    ?? could.first(where: { $0.isCrew && !$0.busy })
                    ?? could.first
                guard let m, let station = fleet.stations[m.station], station.rooms["kind:bath"] != nil else {
                    handle(.log(could.isEmpty ? "nobody free for the bath" : "no bath on the station")); return
                }
                free(m)
                m.showering = shower
                if !visitBath(m, station: station) { handle(.log("both fixtures in the bath are taken")) }
            case .workout:
                let could = minions.values.filter { !$0.isSubagent && !$0.onJob && !$0.bathing && !$0.exercising && !$0.hasLoad }
                let m = could.first(where: { !$0.isCrew && !$0.busy && $0.place == .lounge })
                    ?? could.first(where: { !$0.isCrew && !$0.busy })
                    ?? could.first(where: { !$0.isCrew && $0.activity == .waiting })
                    ?? could.first(where: { $0.isCrew && !$0.busy })
                    ?? could.first
                guard let m, let station = fleet.stations[m.station], let gym = station.rooms["kind:gym"] else {
                    handle(.log(could.isEmpty ? "nobody free for the gym" : "no gym on the station")); return
                }
                m.bathDue = 0
                m.nextWorkoutAt = 0
                free(m)
                if !takeTurnInGym(m, station: station, gym: gym) { handle(.log("every fixture in the gym is taken")) }
            case .mission(let seated):
                let could = minions.values.filter { !$0.isSubagent && !$0.isCrew && !$0.onJob && !$0.hasLoad && $0.using?.room != "kind:mission" }
                let m = could.first(where: { !$0.busy && $0.place == .lounge }) ?? could.first(where: { !$0.busy }) ?? could.first
                guard let m, let station = fleet.stations[m.station] else { handle(.log("nobody free for mission control")); return }
                free(m)
                if !takeTurnInMission(m, station: station, seated: seated) { handle(.log("no free place in mission control")) }
            case .galley(let fare):
                let could = minions.values.filter { !$0.isSubagent && !$0.onJob && !$0.bathing && !$0.exercising && !$0.hasLoad && $0.fare == nil }
                let m = could.first(where: { !$0.isCrew && !$0.busy && $0.place == .lounge })
                    ?? could.first(where: { !$0.isCrew && !$0.busy })
                    ?? could.first
                guard let m, let station = fleet.stations[m.station], station.galley != nil else {
                    handle(.log(could.isEmpty ? "nobody free for the galley" : "no galley on the station")); return
                }
                m.bathDue = 0
                free(m)
                if !visitGalley(m, station: station, fare: fare) { handle(.log("someone is already at the galley")) }
            case .wedge:
                guard let m = minions.values.first(where: { !$0.wedged && { if case .carry = $0.current?.kind { return true }; return false }($0) }) else {
                    handle(.log("nobody is carrying anything to wedge")); return
                }
                m.wedged = true
                handle(.log("\(m.home.name) is wedged: not another step"))
            case .chore:
                let could = minions.values.filter { !$0.isSubagent && !$0.onJob && !$0.isChore && !$0.hasLoad }
                guard let m = could.first(where: { !$0.isCrew && !$0.busy }) ?? could.first(where: { !$0.isCrew }) ?? could.first else {
                    handle(.log("nobody to send on a chore")); return
                }
                free(m)
                m.bathDue = 0
                if let st = fleet.stations[m.station], !startRoam(m, station: st) { handle(.log("nowhere clear to roam")) }
            case .meet:
                let any = minions.values.filter { !$0.isSubagent && !$0.onJob && !$0.hasLoad }.sorted { $0.isCrew == $1.isCrew ? $0.id < $1.id : !$0.isCrew }
                guard any.count >= 2, let st = fleet.stations[any[0].station] else { handle(.log("fewer than two minions to meet")); return }
                let a = any[0], b = any.first { $0.station == a.station && $0.id != a.id } ?? any[1]
                let half = st.corridorCells.map(\.x).max() ?? 2
                for (m, from, to) in [(a, -half, half), (b, half, -half)] {
                    m.busy = false; m.activity = .waiting
                    m.couch = nil; m.bed = nil
                    m.napping = false
                    m.current = nil
                    send(m, to: .core)
                    m.pos = SIMD2(Double(from), 0)
                    m.facing = atan2(Double(to - from), 0)
                    m.path = stride(from: from, through: to, by: to > from ? 1 : -1).dropFirst().map { SIMD2(Double($0), 0) }
                }
                handle(.log("\(a.home.name) and \(b.home.name) meet in the hall"))
            case .lounge:
                for m in minions.values where !m.isCrew && !m.onJob {
                    m.busy = false
                    m.activity = .waiting
                    send(m, to: .lounge)
                }
            case .turnIn:
                for m in minions.values where !m.isSubagent && !m.onJob && !m.hasLoad {
                    m.busy = false
                    m.activity = .sleeping
                    if let c = m.current, !c.isRest { finish(m) }
                    send(m, to: restPlace(m))
                }
            case .breather(let place):
                let atWork = minions.values.filter {
                    $0.busy && !$0.isSubagent && !$0.onJob && !$0.hasLoad && !$0.bathing && !$0.exercising
                }
                guard let m = atWork.first(where: { !$0.isCrew }) ?? atWork.first else {
                    handle(.log("nobody at work to send for a break")); return
                }
                react(m, m.activity, place: place, minutes: 12.0 / 60, words: "\(m.home.name) taking a break")
            case .handFree:
                guard let st = fleet.stations.values.first(where: { !$0.hall.aisleCells.isEmpty }), let cell = st.hall.aisleCells.first,
                      let m = minions.values.filter({ $0.isFree }).sorted(by: { $0.id < $1.id }).first
                          ?? minions.values.filter({ !$0.isCrew && !$0.isPeer && !$0.isSubagent }).sorted(by: { $0.id < $1.id }).first else { return }
                m.path = []
                m.pos = SIMD2(Double(cell.x), Double(cell.y))
            case .night(let on):
                simulation.setNight(on)
            }
        }
    }

    func simulateLog(_ text: String) { enqueue { [self] in logEvent(text) } }
}

extension SimulatorModel {
    var boardLines: [String] {
        position.map { s in
            switch s.kind {
            case .pick(_, let now, _): return "\(s.id): \(now)"
            case .flag(let on, _): return "\(s.id): \(on ? "yes" : "no")"
            case .count(let now, _, _): return "\(s.id): \(now)"
            }
        }
    }
}
