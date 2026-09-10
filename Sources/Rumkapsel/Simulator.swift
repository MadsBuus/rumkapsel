import AppKit
import SwiftUI

/// A station driven by hand. The window holds a real `StationController` with the scanner, GitHub
/// and the network switched off, and a panel of buttons that write synthetic facts into the same
/// entry points production uses: `applyScan`, `applyGitHub`, `applyPeer`. Every `WorldEvent` and
/// every `Command` shows up in the log at the bottom, so a cue that never fires is visible.
///
/// The panel has one target: the office picked at the top. Every button acts on that office, or on
/// its repository. A button that cannot run is greyed with its reason as help text; a scripted press
/// of it logs "skipped: <reason>" rather than doing nothing quietly.
///
/// The names `--simulate` takes, in order of the panel:
///
///     Me:        Start session here, New branch in repo, Prompt, Busy, Quiet, Session ends,
///                Switch branch, Open PR, Approve PR, Checks failing, Merge PR, Close PR
///     Teammate:  Teammate: New branch, Teammate: Open PR, Teammate: Push, Teammate: Merge PR,
///                Teammate: Close PR
///     Peer:      Peer: Arrive, Peer: New office, Peer: Push branch, Peer: Leave, Peer: Kick office
///     Board:     Board: Move
///     Release:   Release: Staging opens, Release: Staging merges, Release: Staging closes,
///                Release: Production opens, Release: Mark tested, Release: Production merges
///     Station:   Night, Day, Everyone to lounge, Bath, Chore
///     Time:      Pause, Resume, Step, 1x, 4x, 16x
///
/// A script picks the target with "Target: <repo>#<number>", say "Target: web#455". Without one it
/// starts on the first office of mine, ios#298. "New branch in repo" makes its new office the target.
@MainActor
final class SimulatorController {
    let station: StationController
    let model: SimulatorModel
    /// Set by whoever owns the window: tear everything down and seed again.
    var onReset: (() -> Void)? { get { model.onReset } set { model.onReset = newValue } }
    let view = NSView()
    private let panelWidth = 280.0

    init(frame: NSRect) {
        let stationRect = NSRect(x: 0, y: 0, width: frame.width - panelWidth, height: frame.height)
        station = StationController(frame: stationRect, demo: false, simulated: true)
        model = SimulatorModel(station: station)
        view.frame = frame
        view.autoresizingMask = [.width, .height]
        station.view.frame = stationRect
        station.view.autoresizingMask = [.width, .height]
        station.viewSize = stationRect.size
        station.drone.isEnabled = false
        view.addSubview(station.view)
        let panel = NSHostingView(rootView: SimulatorPanel(model: model))
        panel.frame = NSRect(x: frame.width - panelWidth, y: 0, width: panelWidth, height: frame.height)
        panel.autoresizingMask = [.height, .minXMargin]
        view.addSubview(panel)
        model.seed()
    }

    /// The station beside the panel: SceneKit renders itself, the panel is cached off the view.
    func snapshot(to path: String) {
        let stationShot = station.view.snapshot()
        let image = NSImage(size: view.bounds.size)
        image.lockFocus()
        NSColor.windowBackgroundColor.setFill()
        NSBezierPath.fill(NSRect(origin: .zero, size: view.bounds.size))
        stationShot.draw(in: station.view.frame)
        if let panel = view.subviews.last, panel !== station.view, let layer = panel.layer,
           let ctx = NSGraphicsContext.current?.cgContext {
            ctx.saveGState()
            ctx.translateBy(x: panel.frame.minX, y: panel.frame.maxY)
            ctx.scaleBy(x: 1, y: -1)
            layer.render(in: ctx)
            ctx.restoreGState()
        }
        image.unlockFocus()
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: path))
    }
}

// MARK: the made-up org

/// Who an office belongs to.
enum SimOwner { case me, teammate, peer }

/// One office in the simulator's org, whoever it belongs to. This list is the whole truth: the
/// scan, the pull request lists and the peer snapshot are all derived from it before every push.
struct SimOffice: Identifiable {
    let uid: String                 // stable through a branch switch, so the picker keeps its choice
    var repo: String
    var number: Int
    var branch: String
    var title: String
    var owner: SimOwner
    var who: String                 // "me", the teammate's name, the peer's name
    var cwd = ""                    // mine: the checkout on disk
    var pushed = false
    var commits = 0                 // mine: commits ahead. Teammate: pushes on top of the branch. Peer: boxes.
    var pull: PullRequest?          // mine: what GitHub says about my branch
    var prOpen = false              // teammate: an open pull request on this branch
    var startedAt = Date()

    var id: String { uid }
    var home: Home { Home.from(repo: repo, branch: branch, cwd: cwd) }
    var label: String { "\(repo)#\(number) \(title) (\(who))" }
}

/// One session of mine, in the office it belongs to.
private struct SimSession {
    var id: String
    var office: String
    var activity: Activity
    var last: Date
    var prompts = 0
    var queued = 0
    var markers: [StationEvent: String] = [:]
}

@MainActor
final class SimulatorModel: ObservableObject {
    var onReset: (() -> Void)?
    let station: StationController
    private var github: GitHubResolver { station.world.github }

    let repos = ["web", "api", "ios"]
    let teammate = "leo"
    let peerName = "kim"

    /// The one office everything acts on, by uid.
    @Published var target = ""
    @Published var column = ""
    @Published var speed = 1.0
    @Published var paused = false
    @Published private(set) var offices: [SimOffice] = []

    private var sessions: [String: SimSession] = [:]     // by office uid
    private var board: [ProjectItem] = []
    private var feeds: [String: [FeedEvent]] = [:]
    private var releases: [String: [ReleasePR]] = [:]
    private var launches: [(repo: String, pr: ReleasePR)] = []
    private var peerHere = false
    private var peerBeat: Timer?
    /// Issue numbers per repository, continuing each one's own range so a new office reads like its neighbours.
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

    init(station: StationController) {
        self.station = station
        station.sim?.onEvent = { [weak self] e in
            self?.note("event", SimulatorModel.describe(e))
        }
        station.sim?.onCommand = { [weak self] c, who in
            self?.note("command", "\(who): \(c.words)")
        }
        // A peer that stops talking is dropped after twenty seconds, so keep saying the same thing.
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

    /// A deterministic org: three repositories, five offices, three sessions of mine, one teammate
    /// with a pull request, one peer on the network, and crates on the board.
    func seed() {
        for r in repos { makeDir(root(r)) }
        github.injectSilently = true
        github.simulationReset()
        github.inject(login: "me")
        for r in repos {
            github.inject(owner: "simcorp/" + r, for: root(r))
            github.inject(cargo: GitHubResolver.Cargo(storage: 0, deck: 0, storageNumbers: [], deckNumbers: []), for: root(r))
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
            item("ios", 280, "push permissions", statuses.deck, "me"),
        ]
        addMine(repo: "ios", number: 298, slug: "lima", branch: "gh-298/onboarding", title: "onboarding", activity: .waiting, commits: 1)
        addMine(repo: "web", number: 455, slug: "damascus", branch: "gh-455/booking-flow", title: "booking flow", activity: .coding("app"), commits: 4)
        addMine(repo: "api", number: 5158, slug: "bismarck", branch: "gh-5158/offerings-gate", title: "offerings gate", activity: .testing, commits: 2)
        var leo = makeOffice(repo: "api", number: 5140, branch: "gh-5140/settlement-redesign", title: "settlement redesign",
                             owner: .teammate, who: teammate)
        leo.prOpen = true
        leo.pushed = true
        leo.startedAt = Date().addingTimeInterval(-7200)
        offices.append(leo)
        var kim = makeOffice(repo: "web", number: 460, branch: "gh-460/artist-tags", title: "artist tags", owner: .peer, who: peerName)
        kim.pushed = true
        kim.commits = 2
        kim.startedAt = Date().addingTimeInterval(-3600)
        offices.append(kim)

        github.inject(project: board, quiet: true)
        github.injectSilently = false
        pushGitHub()          // taken quietly: the repositories answer for the first time here
        pushScan()
        peerHere = true
        pushPeer()
        pushGitHub()
        refresh()
        note("sim", "org seeded: \(repos.joined(separator: ", "))")
    }

    private func item(_ repo: String, _ number: Int, _ title: String, _ status: String, _ who: String) -> ProjectItem {
        ProjectItem(repo: repo, number: number, title: title, status: status, assignees: [who],
                    prURLs: [], url: "https://example.invalid/\(repo)/\(number)", updatedAt: Date())
    }

    private func makeOffice(repo: String, number: Int, branch: String, title: String, owner: SimOwner, who: String) -> SimOffice {
        nextOffice += 1
        return SimOffice(uid: "off-\(nextOffice)", repo: repo, number: number, branch: branch, title: title, owner: owner, who: who)
    }

    /// An office of mine with a session in it: the checkout is made, the branch is pushed.
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
        sessions[uid] = SimSession(id: "sim-\(nextSession)", office: uid, activity: activity, last: Date())
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
        let live = offices.compactMap { o in sessions[o.uid].map { info(o, $0) } }
        station.simulate(scan: ScanResult(sessions: live.sorted { $0.id < $1.id }))
    }

    private func pushGitHub() {
        github.injectSilently = true
        defer { github.injectSilently = false; station.simulateGitHub() }
        for r in repos {
            let sent = launches.filter { $0.repo == r }.map(\.pr)
            let open = offices.filter { $0.repo == r && $0.owner == .teammate && $0.prOpen }.map {
                OpenPR(number: $0.number, title: $0.title, author: $0.who, isBot: false, branch: $0.branch,
                       url: "https://example.invalid/\(r)/\($0.number)", createdAt: $0.startedAt)
            }
            github.inject(openPRs: open, for: root(r))
            github.inject(feed: feeds[r] ?? [], for: root(r))
            github.inject(releases: releases[r] ?? [], for: root(r), merged: sent)
        }
        launches = []
        github.inject(project: board)
    }

    private func pushPeer() {
        guard peerHere else { return }
        let mine = offices.filter { $0.owner == .peer }.map { o in
            PeerSnapshot.Office(key: o.home.key, name: o.home.name, repo: o.repo, branch: o.branch,
                                color: station.world.fleet.color(forRepo: o.repo), cells: [], pushed: o.pushed,
                                startedAt: o.startedAt, lastActive: Date(), boxes: o.commits, dim: false)
        }
        let ms = mine.prefix(1).map { PeerSnapshot.Minion(id: "kim-1", office: $0.key, asleep: false, busy: true) }
        let snap = PeerSnapshot(version: PeerSnapshot.current, name: peerName, since: Date().addingTimeInterval(-600),
                                offices: mine, minions: Array(ms), github: nil, project: nil)
        station.simulate(peer: snap)
    }

    private func feedEvent(_ kind: String, repo: String, branch: String?, pr: Int?, title: String?, detail: String = "") {
        let e = FeedEvent(at: Date(), actor: teammate, isBot: false, kind: kind, branch: branch, prNumber: pr,
                          title: title, url: "https://example.invalid/\(repo)", detail: detail)
        feeds[repo, default: []].insert(e, at: 0)
        feeds[repo] = Array(feeds[repo]!.prefix(40))
    }

    private func setPull(_ pr: PullRequest?, on uid: String) {
        guard let i = index(uid) else { return }
        offices[i].pull = pr
        github.inject(pull: pr, for: offices[i].branch, repoRoot: root(offices[i].repo))
        pushGitHub()
        pushScan()
    }

    private func move(_ items: [ProjectItem], to status: String) {
        for it in items {
            guard let i = board.firstIndex(where: { $0.repo == it.repo && $0.number == it.number }) else { continue }
            board[i] = ProjectItem(repo: it.repo, number: it.number, title: it.title, status: status,
                                   assignees: it.assignees, prURLs: it.prURLs, url: it.url, updatedAt: Date())
        }
        pushGitHub()
    }

    private func index(_ uid: String) -> Int? { offices.firstIndex { $0.uid == uid } }

    /// Keeps the picker and the column choice on something that exists.
    func refresh() {
        if index(target) == nil { target = offices.first { $0.owner == .me }?.uid ?? offices.first?.uid ?? "" }
        if !columns.contains(column) { column = columns.first ?? "" }
        objectWillChange.send()
    }

    // MARK: what the target office has right now

    var office: SimOffice? { offices.first { $0.uid == target } }
    private var targetRepo: String { office?.repo ?? repos[0] }
    private var targetSession: SimSession? { office.flatMap { sessions[$0.uid] } }

    /// leo acts on the target when the target is his; otherwise on his newest office in the target's repository.
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

    /// kim acts on the target when the target is hers; otherwise on her newest office.
    private var kimOffice: SimOffice? {
        if let o = office, o.owner == .peer { return o }
        return offices.last { $0.owner == .peer }
    }

    /// What the target office has, in the panel's own words.
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

    // MARK: the buttons

    struct Button: Identifiable {
        let name: String        // the stable name, the one `--simulate` uses
        let label: String       // what the panel shows, with the target's repository filled in
        let blocked: String?    // why it cannot run right now, nil when it can
        var id: String { name }
    }

    struct Group: Identifiable { let id: String; let note: String?; let buttons: [Button] }

    private func button(_ name: String, _ label: String? = nil, _ blocked: String? = nil) -> Button {
        Button(name: name, label: label ?? name, blocked: blocked)
    }

    var groups: [Group] {
        let repo = targetRepo
        let mine = office?.owner == .me
        let hasSession = targetSession != nil
        let noSession = hasSession ? nil : "no session in this office"
        let notMine = mine ? nil : "this office is \(office?.who ?? "nobody")'s"
        let myPR = mine ? office?.pull : nil
        let myOpenPR = myPR?.state == "OPEN" ? myPR : nil
        let openReason = notMine ?? noSession ?? (office?.pushed == false ? "branch not pushed" : nil)
            ?? (myPR != nil ? "already has a pull request" : nil)
        let onPR = notMine ?? (myOpenPR == nil ? "no open pull request in this office" : nil)

        return [
            Group(id: "Me", note: nil, buttons: [
                button("Start session here", "Start session here", notMine ?? (hasSession ? "a session is already here" : nil)),
                button("New branch in repo", "New branch in \(repo)"),
                button("Prompt", "Prompt", noSession),
                button("Busy", "Busy", noSession),
                button("Quiet", "Quiet", noSession),
                button("Session ends", "Session ends", noSession),
                button("Switch branch", "Switch branch", noSession),
                button("Open PR", "Open PR", openReason),
                button("Approve PR", "Approve PR", onPR),
                button("Checks failing", "Checks failing", onPR),
                button("Merge PR", "Merge PR", onPR),
                button("Close PR", "Close PR (not merged)", onPR),
            ]),
            Group(id: "Teammate (\(teammate))", note: "on the target office when it is \(teammate)'s, else on his newest branch in \(repo)", buttons: [
                button("Teammate: New branch", "New branch in \(repo)"),
                button("Teammate: Open PR", "Open PR",
                       leoBranchWithoutPR == nil ? "\(teammate) has no branch without a pull request on \(repo)" : nil),
                button("Teammate: Push", "Push", leoOffice == nil ? "\(teammate) has no branch on \(repo)" : nil),
                button("Teammate: Merge PR", "Merge PR", leoOpenPR == nil ? "\(teammate) has no open pull request on \(repo)" : nil),
                button("Teammate: Close PR", "Close PR (not merged)",
                       leoOpenPR == nil ? "\(teammate) has no open pull request on \(repo)" : nil),
            ]),
            Group(id: "Peer (\(peerName))", note: "on the target office when it is \(peerName)'s, else on her newest office", buttons: [
                button("Peer: Arrive", "Arrive with an office in \(repo)", peerHere ? "\(peerName) is already here" : nil),
                button("Peer: New office", "New office in \(repo)"),
                button("Peer: Push branch", "Push branch", kimOffice == nil ? "\(peerName) has no office" : nil),
                button("Peer: Leave", "Leave", peerHere ? nil : "\(peerName) is not here"),
                button("Peer: Kick office", "Kick this office", office == nil ? "no office picked" : nil),
            ]),
            Group(id: "Board", note: nil, buttons: [
                button("Board: Move", "Move \(office.map { "\($0.repo)#\($0.number)" } ?? "the issue") to \(column)",
                       office.flatMap(boardItem) == nil ? "the target has no issue on the board"
                        : (office.flatMap(boardItem)?.status == column ? "already in \(column)" : nil)),
            ]),
            Group(id: "Release (\(repo))", note: nil, buttons: [
                button("Release: Staging opens", "Staging opens",
                       openRelease(repo, production: false) != nil ? "a staging release is already open on \(repo)" : nil),
                button("Release: Staging merges", "Staging merges",
                       openRelease(repo, production: false) == nil ? "no open staging release on \(repo)" : nil),
                button("Release: Staging closes", "Staging closes (not merged)",
                       openRelease(repo, production: false) == nil ? "no open staging release on \(repo)" : nil),
                button("Release: Production opens", "Production opens (untested)",
                       openRelease(repo, production: true) != nil ? "a production release is already open on \(repo)" : nil),
                button("Release: Mark tested", "Mark tested",
                       onDeck(repo).isEmpty ? "nothing on the deck for \(repo)" : nil),
                button("Release: Production merges", "Production merges (ship)",
                       openRelease(repo, production: true) == nil ? "no open production release on \(repo)" : nil),
            ]),
            Group(id: "Station", note: nil, buttons: [
                button("Night"), button("Day"), button("Everyone to lounge"), button("Bath"), button("Chore"),
            ]),
        ]
    }

    /// The clock's own row, never blocked.
    let timeNames = ["Pause", "Resume", "Step", "1x", "4x", "16x"]

    var buttonNames: [String] { groups.flatMap(\.buttons).map(\.name) + timeNames }

    func press(_ name: String) {
        note("press", name)
        if name.hasPrefix("Target: ") {
            pick(String(name.dropFirst(8)))
        } else if timeNames.contains(name) {
            time(name)
        } else if let b = groups.flatMap(\.buttons).first(where: { $0.name == name }) {
            if let why = b.blocked { note("skipped", why) } else { run(name) }
        } else {
            note("skipped", "no such button: \(name)")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.refresh() }
    }

    /// The picker, from a script: "Target: web#455".
    private func pick(_ id: String) {
        guard let o = offices.first(where: { "\($0.repo)#\($0.number)" == id }) else {
            return note("skipped", "no office \(id)")
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
            speed = Double(name.dropLast()) ?? 1
            station.sim?.timeScale = speed
        }
    }

    /// Every button's work. Nothing here checks whether it applies: `press` did that.
    private func run(_ name: String) {
        let repo = targetRepo
        switch name {

        // Me
        case "Start session here":
            guard let i = index(target) else { return }
            if offices[i].cwd.isEmpty { offices[i].cwd = worktree(repo, "sim-\(offices[i].number)") }
            makeDir(offices[i].cwd)
            offices[i].pushed = true
            offices[i].commits = max(1, offices[i].commits)
            startSession(in: offices[i].uid, activity: .coding("src"))
            pushScan()
        case "New branch in repo":
            // A new office of mine beside the target, in the target's repository. It becomes the target.
            let n = nextIssue(repo)
            let o = addMine(repo: repo, number: n, slug: "sim-\(n)", branch: "gh-\(n)/new-work-\(n)",
                            title: "new work \(n)", activity: .coding("src"), commits: 2)
            board.append(item(repo, n, "new work \(n)", statuses.development, "me"))
            target = o.uid
            pushGitHub()
            pushScan()
        case "Prompt":
            guard var s = targetSession else { return }
            s.prompts += 1
            s.markers[.prompt] = UUID().uuidString
            s.last = Date()
            sessions[s.office] = s
            pushScan()
        case "Busy":
            guard var s = targetSession else { return }
            s.activity = .coding("src"); s.last = Date()
            sessions[s.office] = s
            pushScan()
        case "Quiet":
            guard var s = targetSession else { return }
            s.activity = .waiting; s.last = Date().addingTimeInterval(-600)
            sessions[s.office] = s
            pushScan()
        case "Session ends":
            // The office stays in the picker with no session in it, which is a state worth pressing on.
            sessions[target] = nil
            pushScan()
        case "Switch branch":
            guard let i = index(target) else { return }
            let n = nextIssue(offices[i].repo)
            offices[i].number = n
            offices[i].branch = "gh-\(n)/switched-\(n)"
            offices[i].title = "switched \(n)"
            offices[i].pull = nil
            board.append(item(offices[i].repo, n, "switched \(n)", statuses.development, "me"))
            sessions[target]?.last = Date()
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

        // The teammate, through the open pull request list and the activity feed
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
        case "Teammate: Merge PR", "Teammate: Close PR":
            guard let o = leoOpenPR else { return }
            offices.removeAll { $0.uid == o.uid }
            feedEvent(name.hasSuffix("Merge PR") ? "pr_merge" : "pr_close", repo: o.repo, branch: o.branch,
                      pr: o.number, title: o.title)
            pushGitHub()

        // The peer, over the network
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

        // Board
        case "Board: Move":
            guard let it = office.flatMap(boardItem) else { return }
            move([it], to: column)

        // Releases, on the target's repository
        case "Release: Staging opens":
            let cfg = ConfigStore.shared.current
            nextRelease += 1
            releases[repo, default: []].append(ReleasePR(number: nextRelease, title: "release to staging", base: cfg.stagingBranch,
                                                         head: cfg.trunkBranch, state: "OPEN",
                                                         url: "https://example.invalid/\(repo)/\(nextRelease)", labels: [], mergedAt: nil))
            pushGitHub()
        case "Release: Staging merges":
            guard let i = openRelease(repo, production: false) else { return }
            let pr = releases[repo]![i]
            releases[repo]![i] = ReleasePR(number: pr.number, title: pr.title, base: pr.base, head: pr.head, state: "MERGED",
                                           url: pr.url, labels: pr.labels, mergedAt: Date())
            // With a board, the merge is a bell; the crates move because the columns move.
            if ConfigStore.shared.current.project != nil { launches.append((repo, releases[repo]![i])) }
            pushGitHub()
            move(board.filter { $0.repo == repo && $0.status == statuses.storage }, to: statuses.deck)
        case "Release: Staging closes":
            guard let i = openRelease(repo, production: false) else { return }
            let pr = releases[repo]![i]
            releases[repo]![i] = ReleasePR(number: pr.number, title: pr.title, base: pr.base, head: pr.head, state: "CLOSED",
                                           url: pr.url, labels: pr.labels, mergedAt: nil)
            pushGitHub()
        case "Release: Production opens":
            let cfg = ConfigStore.shared.current
            nextRelease += 1
            releases[repo, default: []].append(ReleasePR(number: nextRelease, title: "release to production", base: cfg.productionBranch,
                                                         head: cfg.stagingBranch, state: "OPEN",
                                                         url: "https://example.invalid/\(repo)/\(nextRelease)", labels: ["untested"], mergedAt: nil))
            pushGitHub()
        case "Release: Mark tested":
            // QA passing takes the untested label off an open production release as well as
            // moving the column: that is what clears the rocket to load.
            if let i = releases[repo]?.lastIndex(where: { $0.state == "OPEN" && $0.isProduction && $0.untested }) {
                let pr = releases[repo]![i]
                releases[repo]![i] = ReleasePR(number: pr.number, title: pr.title, base: pr.base, head: pr.head,
                                               state: pr.state, url: pr.url,
                                               labels: pr.labels.filter { !$0.lowercased().contains("untested") }, mergedAt: nil)
            }
            move(onDeck(repo), to: statuses.cleared)
        case "Release: Production merges":
            guard let i = openRelease(repo, production: true) else { return }
            let pr = releases[repo]![i]
            let merged = ReleasePR(number: pr.number, title: pr.title, base: pr.base, head: pr.head, state: "MERGED",
                                   url: pr.url, labels: pr.labels.filter { $0 != "untested" }, mergedAt: Date())
            releases[repo]![i] = merged
            launches.append((repo, merged))
            pushGitHub()
            // The board catches up after the rocket has been loaded, the way a later poll would;
            // moving the column in the same breath empties the deck before anyone can carry it.
            let shipping = repo
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
                guard let self else { return }
                let st = self.statuses
                move(board.filter { $0.repo == shipping && ($0.status == st.cleared || $0.status == st.deck) }, to: st.shipped)
            }

        // Station
        case "Night": station.simulate(.night(true))
        case "Day": station.simulate(.night(false))
        case "Everyone to lounge": station.simulate(.lounge)
        case "Bath": station.simulate(.bath)
        case "Chore": station.simulate(.chore)

        default:
            note("skipped", "no such button: \(name)")
        }
    }

    private func addPeerOffice(repo: String, aged: Bool) {
        let n = nextIssue(repo)
        var o = makeOffice(repo: repo, number: n, branch: "gh-\(n)/peer-work-\(n)", title: "peer work \(n)",
                           owner: .peer, who: peerName)
        o.pushed = aged
        o.commits = aged ? 2 : 0
        o.startedAt = aged ? Date().addingTimeInterval(-3600) : Date()
        offices.append(o)
    }

    // MARK: the log

    /// The event and command taps fire on the scene's render thread, so the log is kept behind a
    /// lock and the panel only asks it for text.
    private let lines = SimLog()

    nonisolated func note(_ kind: String, _ text: String) {
        lines.add(kind: kind, text: text)
        DispatchQueue.main.async { [weak self] in self?.objectWillChange.send() }
    }

    var logText: String { lines.text }

    static func describe(_ e: WorldEvent) -> String {
        switch e {
        case .boardMoved(let it, let from, let to): return "boardMoved \(it.repo)#\(it.number) \(from ?? "—") -> \(to)"
        case .pullRequestOpened(let repo, let n, let who, _): return "pullRequestOpened \(repo)#\(n) by \(who)"
        case .pullRequestClosed(let repo, let who, let key): return "pullRequestClosed \(repo) \(who) \(key)"
        case .issueStarted(let repo, let n, let who, _): return "issueStarted \(repo)#\(n) by \(who)"
        case .peerArrived(let n): return "peerArrived \(n)"
        case .peerLeft(let n): return "peerLeft \(n)"
        case .officeOpened(let st, let key, let src, let arrival): return "officeOpened \(st)|\(key) \(src) \(arrival)"
        case .officeRenamed(_, let from, let to, _, _, let promoted): return "officeRenamed \(from) -> \(to)\(promoted ? " promoted" : "")"
        case .officeArchived(_, let key, _, _, _, _, let why): return "officeArchived \(key) (\(why))"
        case .officeMerged(_, let key, let repo, let n): return "officeMerged \(key) \(repo)#\(n)"
        case .carryToDeck(_, let repo, let cs): return "carryToDeck \(repo) x\(cs.count)"
        case .crateCleared(_, let repo, let n): return "crateCleared \(repo)#\(n)"
        case .crewRoster(let m, let bots): return "crewRoster \(m.keys.sorted().joined(separator: ",")) bots \(bots)"
        case .crewActivity(let a): return "crewActivity \(a.login) \(a.kind) \(a.label)"
        case .crewHidden: return "crewHidden"
        case .layoutChanged: return "layoutChanged"
        case .markersChanged: return "markersChanged"
        case .worldLoaded: return "worldLoaded"
        case .log(let t): return "log: \(t)"
        case .chime(let s): return "chime \(s)"
        case .releaseOpened(_, let repo, let n, let base, let untested, _):
            return "releaseOpened \(repo)#\(n) -> \(base)\(untested ? " untested" : "")"
        case .releaseMerged(_, let repo, let n, let base, _, let production):
            return "releaseMerged \(repo)#\(n) -> \(base)\(production ? " production" : "")"
        case .rocketCommand(_, let repo, _, _, _, _, let c): return "rocketCommand \(repo): \(c.words)"
        case .stagingOpened(_, let repo, let n): return "stagingOpened \(repo)#\(n)"
        case .stagingMerged(_, let repo, let n): return "stagingMerged \(repo)#\(n)"
        case .stagingClosed(_, let repo, let n): return "stagingClosed \(repo)#\(n)"
        case .prompt(_, let key, _, let n): return "prompt \(key) x\(n)"
        }
    }
}

/// The simulator's log, written from any thread and read by the panel.
final class SimLog: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []
    private static let stamp: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f
    }()

    func add(kind: String, text: String) {
        lock.lock(); defer { lock.unlock() }
        lines.insert("\(SimLog.stamp.string(from: Date()))  \(kind)  \(text)", at: 0)
        if lines.count > 400 { lines.removeLast(lines.count - 400) }
    }

    var text: String {
        lock.lock(); defer { lock.unlock() }
        return lines.joined(separator: "\n")
    }
}

// MARK: the panel

struct SimulatorPanel: View {
    @ObservedObject var model: SimulatorModel

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    time
                    targetBox
                    ForEach(model.groups) { g in
                        VStack(alignment: .leading, spacing: 5) {
                            header(g.id)
                            if let n = g.note {
                                Text(n).font(.system(size: 9)).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
                            }
                            if g.id == "Board" {
                                Picker("", selection: $model.column) {
                                    ForEach(model.columns, id: \.self) { Text($0).tag($0) }
                                }.labelsHidden().controlSize(.small)
                            }
                            ForEach(g.buttons) { b in
                                Button(b.label) { model.press(b.name) }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .controlSize(.small)
                                    .disabled(b.blocked != nil)
                                    .help(b.blocked ?? b.name)
                            }
                        }
                    }
                }
                .padding(12)
            }
            Divider()
            logView
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func header(_ text: String) -> some View {
        Text(text.uppercased()).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
    }

    /// The one office everything below acts on, and what it has right now.
    @ViewBuilder private var targetBox: some View {
        VStack(alignment: .leading, spacing: 5) {
            header("Target office")
            Picker("", selection: $model.target) {
                ForEach(model.offices) { Text($0.label).tag($0.uid) }
            }.labelsHidden().controlSize(.small)
            VStack(alignment: .leading, spacing: 2) {
                ForEach(model.status, id: \.self) { line in
                    Text(line).font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
            .background(Color.secondary.opacity(0.08))
            .cornerRadius(4)
        }
    }

    @ViewBuilder private var time: some View {
        VStack(alignment: .leading, spacing: 5) {
            header("Time")
            HStack(spacing: 6) {
                Button(model.paused ? "Resume" : "Pause") { model.press(model.paused ? "Resume" : "Pause") }
                Button("Step") { model.press("Step") }
                ForEach(["1x", "4x", "16x"], id: \.self) { s in
                    Button(s) { model.press(s) }
                        .buttonStyle(.borderedProminent)
                        .tint(model.speed == (Double(s.dropLast()) ?? 1) ? .accentColor : .gray)
                }
            }
            .controlSize(.small)
            Button("Reset org") { model.onReset?() }.help("Start over with a fresh station and org").controlSize(.small)
        }
    }

    private var logView: some View {
        VStack(alignment: .leading, spacing: 4) {
            header("Log")
                .padding(.horizontal, 12).padding(.top, 8)
            ScrollView {
                Text(model.logText)
                    .font(.system(size: 10, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
            }
        }
        .frame(height: 220)
    }
}

// MARK: the simulator's way in

/// What a simulator window plants in a live controller: the event and command taps, its own clock,
/// and the two things no source drives. A normal window leaves `sim` nil and none of this runs.
final class SimHooks {
    var onEvent: ((WorldEvent) -> Void)?
    /// The command and who is running it: a worker's office, or "shuttle" and "rocket".
    var onCommand: ((Command, String) -> Void)?
    /// 1, 4 or 16: how fast the tick's dt runs.
    var timeScale = 1.0
    var paused = false
    /// Single ticks asked for while paused.
    var steps = 0
    /// Night forced on or off; nil leaves it to the clock.
    var night: Bool?
    var clock = 0.0
    var lastReal = 0.0
}

/// Something to poke that no source can say: a bath, a chore, everyone to the lounge.
enum SimNudge { case bath, chore, lounge, night(Bool?) }

extension StationController {
    /// Small enough that a minion at sixteen times speed still walks rather than jumps.
    private static var simStep: Double { 1.0 / 30.0 }

    /// The simulator's clock: real time scaled, or one step at a time while paused.
    func advanceSimulated(to time: TimeInterval) {
        guard let sim else { return }
        let real = sim.lastReal == 0 ? 0 : min(0.25, max(0, time - sim.lastReal))
        sim.lastReal = time
        var budget = sim.paused ? Double(sim.steps) * StationController.simStep : real * sim.timeScale
        sim.steps = 0
        while budget > 0 {
            let step = min(StationController.simStep, budget)
            budget -= step
            sim.clock += step
            tick(now: sim.clock)
        }
    }

    /// A scan, as the transcript reader would have handed it over.
    func simulate(scan: ScanResult) { enqueue { [self] in apply(scan) } }

    /// GitHub answered: the same path a poll takes when something came back changed.
    func simulateGitHub() { enqueue { [self] in onGitHubUpdate() } }

    /// A snapshot off the network, and a peer going quiet.
    func simulate(peer: PeerSnapshot) { enqueue { [self] in receivePeer(peer) } }
    func simulatePeerLeft(_ name: String) { enqueue { [self] in dropPeer(name) } }

    /// The right-click menu's kick, without the menu.
    func simulateKick(roomKey key: String) {
        enqueue { [self] in handle(world.kick(roomKey: key)); flushScene() }
    }

    func simulate(_ nudge: SimNudge) {
        enqueue { [self] in
            switch nudge {
            case .bath:
                // The bath only pulls on someone settled and not working: send them to the couch first.
                let free = minions.values.filter { !$0.isCrew && !$0.isSubagent && !$0.onJob && !$0.bathing && !$0.busy }
                guard let m = free.first(where: { $0.place == .lounge }) ?? free.first else {
                    handle(.log("nobody free for the bath")); return
                }
                if m.place != .lounge { send(m, to: .lounge) }
                m.bathDue = clock
                m.showering = true
            case .chore:
                guard let m = minions.values.first(where: { !$0.isCrew && !$0.isSubagent && !$0.onJob && !$0.busy && !$0.isChore }) else {
                    handle(.log("nobody free for a chore")); return
                }
                m.nextChoreAt = clock
                m.bathDue = 0
                if m.place != .lounge { send(m, to: .lounge) }
            case .lounge:
                for m in minions.values where !m.isCrew && !m.onJob {
                    m.busy = false
                    m.activity = .waiting
                    send(m, to: .lounge)
                }
            case .night(let on):
                sim?.night = on
                for m in minions.values where !m.onJob { send(m, to: restPlace(m)) }
                handle(.log(on == true ? "night falls" : on == false ? "morning" : "back on the clock"))
            }
        }
    }


    func simulateLog(_ text: String) { enqueue { [self] in logEvent(text) } }
}
