import AppKit
import SwiftUI

/// A station driven by hand. The window holds a real `StationController` with the scanner, GitHub
/// and the network switched off, and a panel that writes synthetic facts into the same entry points
/// production uses: `applyScan`, `applyGitHub`, `applyPeer`. Every `WorldEvent` and every `Command`
/// shows up in the log at the bottom, so a cue that never fires is visible.
///
/// The panel is a chess board and the moves on it, with a line between them.
///
/// **The board** is the position: one knob per fact, each saying what is so and setting it when
/// moved — the session in the target office and what it is doing, its commits, whether its branch
/// is pushed, its pull request, its column, its repository's pipeline and open releases, whether
/// the peer is on the network, whether it is night. A knob is not a quieter kind of button: the
/// station reacts to a knob as it reacts to anything. It is the other half of the panel.
///
/// **The moves** are the things that happen, one press each. A move is one press away whatever the
/// board says: a move whose ground is not laid lays it first, quietly, and plays a beat later on
/// the station clock, saying in the log what it set up. So "Merge PR" on an office with no pull
/// request opens one and then merges it, rather than greying out and leaving you to work out the
/// order. Only a move that has already happened — a second staging release while one is open — is
/// out of reach, and it says why.
///
/// Everything the panel does is scriptable, which is how a picture is taken of a position:
///
///     Target: web#455                     the office every knob and move acts on
///     Set: <knob> = <value>               a knob, by its name or its last words
///     Set: pipeline = no staging branch
///     Set: commits ahead = 8              a count takes a number, a flag "yes" or "no"
///     Merge PR                            a move, by the name below
///
/// The names a move keeps, whatever the panel shows, since the scenarios press them:
///
///     Mine:      New branch in repo, Prompt, Commit, Session ends, Switch branch, Open PR,
///                Approve PR, Checks failing, Merge PR, Close PR
///     Teammate:  Teammate: New branch, Teammate: Open PR, Teammate: Push, Teammate: Merge PR,
///                Teammate: Close PR, Teammate: Close PR (feed lags)
///     Bots:      Bot: Open PR, Bot: Merge PR, Bot: Close PR
///     Peer:      Peer: Arrive, Peer: New office, Peer: Push branch, Peer: Leave, Peer: Kick office
///     Sources:   Stage: ready, Stage: stored, Stage: QA, Stage: cleared, Stage: shipped
///     Board:     Board: Move <repo>#<n> to <column>, Board: Catch up
///     Polls:     GitHub: Poll, Scan: again
///     Release:   Repo: No staging, Repo: Ships on merge, Release: Staging opens,
///                Release: Staging merges, Release: Staging merges (board lags),
///                Release: Staging closes, Release: Production opens, Release: Mark tested,
///                Release: Production merges
///     Everyone:  Night, Day, Everyone to lounge, Breather, Everyone asleep, Bath, Chore, Workout,
///                Meet in the hall,
///                Wedge carrier
///     Time:      Pause, Resume, Step, ¼x, ½x, 1x, 4x, 16x
///
/// Six of those have no button of their own, because a knob works them — the night, the peer and the
/// pipeline — and they keep their names only because the scenarios press them. Starting a session and
/// making one busy or quiet were dropped outright: the session knob is the whole of it.
/// Without a target the panel starts on the first office of mine, ios#298.
@MainActor
final class SimulatorController {
    let station: StationController
    let model: SimulatorModel
    /// Set by whoever owns the window: tear everything down and seed again.
    var onReset: (() -> Void)? { get { model.onReset } set { model.onReset = newValue } }
    let view = NSView()
    private let panelWidth = 330.0

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
    /// Who the stage panel speaks as: the station hears a stage by the rules, so the source matters.
    @Published var stageSource: Source = .board
    @Published var speed = 1.0
    @Published var paused = false
    @Published private(set) var offices: [SimOffice] = []

    private var sessions: [String: SimSession] = [:]     // by office uid
    private var board: [ProjectItem] = []
    private var feeds: [String: [FeedEvent]] = [:]
    private var releases: [String: [ReleasePR]] = [:]
    /// Repositories pressed to have no staging branch: develop to master through a release branch, like android.
    private var noStaging: Set<String> = []
    /// Repositories pressed to deploy on every merge, with no release at all.
    private var shipsOnMerge: Set<String> = []
    private var launches: [(repo: String, pr: ReleasePR)] = []
    /// Dependabot's open pull requests per repository: objects in decon, not offices.
    private var botPRs: [String: [(number: Int, title: String, branch: String)]] = [:]
    let bot = "dependabot[bot]"
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
            self?.note("event", SimulatorModel.describe(e), .event(e))
        }
        station.sim?.onCommand = { [weak self] c, who in
            self?.note("command", "\(who): \(c.words)", .command(c, by: who))
        }
        station.sim?.invariants.onViolation = { [weak self] text in self?.note("check", text, .violation(text)) }
        station.sim?.pullState = { [weak self] repo, number in self?.pullFates["\(repo)#\(number)"] }
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
    /// `crowd` is the rest of the desk: the other two offices of mine, the teammate and the peer. A play
    /// about one body in a dorm wants none of them, and the org is the same org without them.
    func seed(crowd: Bool = true) {
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
        pushGitHub()          // taken quietly: the repositories answer for the first time here
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
        let live = offices.compactMap { o in sessions[o.uid].map { info(o, $0) } }
        station.simulate(scan: ScanResult(sessions: live.sorted { $0.id < $1.id }))
    }

    private func pushGitHub() {
        github.injectSilently = true
        defer { github.injectSilently = false; station.simulateGitHub() }
        for r in repos {
            let sent = launches.filter { $0.repo == r }.map(\.pr)
            // `gh pr list` returns everyone's, your own included: that is how the station learns whose
            // work each crate is, so your own open pull requests belong in the answer too.
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
        }
        launches = []
        github.inject(project: board)
    }

    private func pushPeer() {
        guard peerHere else { return }
        let mine = offices.filter { $0.owner == .peer }.map { o in
            PeerSnapshot.Office(key: o.home.key, name: o.home.name, repo: o.repo, branch: o.branch,
                                color: station.world.fleet.color(forRepo: o.repo), cells: [], pushed: o.pushed,
                                startedAt: o.startedAt, lastActive: station.now, boxes: o.commits, dim: false)
        }
        // A peer is a person, and at night their session is as quiet as anyone's: without this the one
        // state a peer's body is hardest to place — asleep, wanting a bunk of its own — is unreachable.
        let asleep = station.sim?.night == true
        let ms = mine.prefix(1).map { PeerSnapshot.Minion(id: "kim-1", office: $0.key, asleep: asleep, busy: !asleep) }
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

    /// Every pull request's fate as the simulated GitHub knows it, by "repo#number".
    private var pullFates: [String: String] = [:]

    private func setPull(_ pr: PullRequest?, on uid: String) {
        guard let i = index(uid) else { return }
        offices[i].pull = pr
        if let pr { pullFates["\(offices[i].repo)#\(pr.number)"] = pr.state }
        github.inject(pull: pr, for: offices[i].branch, repoRoot: root(offices[i].repo))
        pushGitHub()
        pushScan()
    }

    private func move(_ items: [ProjectItem], to status: String) {
        for it in items {
            guard let i = board.firstIndex(where: { $0.repo == it.repo && $0.number == it.number }) else { continue }
            board[i] = ProjectItem(repo: it.repo, number: it.number, title: it.title, status: status,
                                   assignees: it.assignees, prURLs: it.prURLs, url: it.url, updatedAt: station.now)
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
    // MARK: the board, and the moves on it

    /// Why a move cannot be played right now. Two kinds, and they are not the same thing: a move
    /// whose ground is simply not laid yet can lay it and go, which is what keeps every move one
    /// press away however the board stands; a move that has already happened cannot happen twice
    /// and stays out of reach.
    enum Blocked {
        /// Something has to be there first. The closure puts it there.
        case missing(String, () -> Void)
        /// It is already so, or cannot be done from here. Nothing to arrange.
        case already(String)

        var words: String {
            switch self {
            case .missing(let what, _): return "sets up " + what
            case .already(let why): return why
            }
        }
    }

    /// One thing that can happen.
    struct Button: Identifiable {
        let name: String        // the stable name, the one `--simulate` and the scenarios use
        let label: String       // what the panel shows, with the target's repository filled in
        let blocked: Blocked?   // why it cannot run as things stand, nil when it can
        /// Whether it has a button of its own. A few moves are worked by a knob on the board
        /// instead, and keep their name only so a script can still press them.
        var shown = true
        var id: String { name }
    }

    struct Group: Identifiable { let id: String; let note: String?; let buttons: [Button] }

    private func button(_ name: String, _ label: String? = nil, _ blocked: Blocked? = nil, shown: Bool = true) -> Button {
        Button(name: name, label: label ?? name, blocked: blocked, shown: shown)
    }

    /// One knob on the board: what it says now, and what to do when it is moved. A knob is not a
    /// quieter kind of button — the station reacts to a knob as it reacts to anything — it is the
    /// other half of the panel: a knob says what the position *is*, a button plays one move on it.
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

    /// The activities a session can be in, as the panel offers them. "waiting for you" is the quiet
    /// one: its last word was ten minutes ago, which is what makes the office go quiet.
    static let activities: [(name: String, act: Activity)] = [
        ("coding", .coding("src")), ("reading code", .exploring), ("testing", .testing),
        ("writing", .writing), ("thinking", .thinking), ("QA testing", .qa),
        ("web research", .researching), ("waiting for you", .waiting),
        // A session gone quiet past `sleepMinutes` is asleep, and an asleep body is the only one the
        // night sends to a bunk: without this the knob could not reach the one state bedtime needs.
        ("sleeping", .sleeping),
    ]
    static let noSession = "no session"

    /// What a pull request of mine can be. `pullOf` reads one back.
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

    /// Puts the target's pull request into that state, whoever's office it is.
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

    static let pipelines = ["trunk → staging → production", "no staging branch", "every merge deploys"]
    private var pipelineOf: String {
        if shipsOnMerge.contains(targetRepo) { return SimulatorModel.pipelines[2] }
        return noStaging.contains(targetRepo) ? SimulatorModel.pipelines[1] : SimulatorModel.pipelines[0]
    }

    /// Back to a trunk, a staging branch and a production branch: the shape most repositories have,
    /// and the one the other two are pressed away from. Without this the panel is a one-way door.
    private func normalPipeline() {
        let repo = targetRepo, cfg = ConfigStore.shared.current
        noStaging.remove(repo)
        shipsOnMerge.remove(repo)
        github.inject(pipeline: Pipeline(trunk: cfg.trunkBranch, staging: cfg.stagingBranch, production: cfg.productionBranch),
                      for: root(repo))
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

    /// The position, knob by knob: everything above the line in the panel.
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
        // A new session needs a checkout on disk and a pushed branch, the way the scanner would find one.
        if sessions[o.uid] == nil {
            guard let i = index(o.uid) else { return }
            if offices[i].cwd.isEmpty { offices[i].cwd = worktree(o.repo, "sim-\(offices[i].number)") }
            makeDir(offices[i].cwd)
            offices[i].pushed = true
            offices[i].commits = max(1, offices[i].commits)
            startSession(in: o.uid, activity: act)
        }
        sessions[o.uid]?.activity = act
        // Quiet is the same session with nothing said for ten minutes; anything else is this moment.
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

    /// Whatever the target office needs to be a working office of mine: mine, checked out, pushed,
    /// with a session in it.
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

    /// And an open pull request on it.
    private func layOpenPull() {
        layMine()
        setPullState("open")
    }

    /// A branch of the teammate's on the target's repository, with or without a pull request on it.
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
        // What is not in place yet, and how to put it there. Nothing here refuses a move for want
        // of ground: it lays it.
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
                button("Open PR", "Opens a pull request",
                       mine && o?.pull != nil ? .already("this office already has a pull request") : needsMine),
                button("Approve PR", "…is approved", needsOpenPull),
                button("Checks failing", "…checks go red", needsOpenPull),
                button("Merge PR", "…is merged", needsOpenPull),
                button("Close PR", "…is closed unmerged", needsOpenPull),
                button("New branch in repo", "A new office of mine in \(repo)"),
            ]),
            Group(id: "Teammate (\(teammate))", note: "on the target office when it is \(teammate)'s, else on his newest branch in \(repo)", buttons: [
                button("Teammate: New branch", "A new branch in \(repo)"),
                button("Teammate: Push", "He pushes", teammateAny),
                button("Teammate: Open PR", "He opens a pull request", teammateBranch),
                button("Teammate: Merge PR", "…merges it", teammatePull),
                button("Teammate: Close PR", "…closes it unmerged", teammatePull),
                // The close is seen on the open list and answered when the pull request is asked,
                // but the activity feed has not caught up.
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
                button("Peer: Arrive", shown: false),
                button("Peer: Leave", shown: false),
            ]),
            // The station half on its own: a stage said straight to the record, no integration played.
            Group(id: "A source speaks", note: "Says a stage to the record as the source picked, by the rules; the floor reacts. No GitHub, no board.", buttons:
                Stage.allCases.filter { $0 >= .ready }.map {
                    button("Stage: \($0)", "→ \($0)", o == nil ? .already("no office picked") : nil)
                }),
            Group(id: "Late polls", note: "a source asked again, or answering after the fact: where the ordering bugs live", buttons: [
                // The app asks its sources again every few seconds or minutes, and some rules only
                // come round on a later answer: an office red for ten minutes clears on the poll
                // after the tenth. A scripted run gets one of each at press time and never sees
                // them, so both asks are moves of their own.
                button("GitHub: Poll", "GitHub is asked again"),
                button("Scan: again", "The scanner looks again"),
                // The board's own poll arriving late: everything of the repository still in storage moves to the deck.
                button("Board: Catch up", "The board catches up: \(repo) storage → deck",
                       board.contains { $0.repo == repo && $0.status == statuses.storage } ? nil
                           : .missing("something of \(repo) in storage", { [weak self] in self?.layInStorage() })),
                // The merge is seen but the board is not: its poll comes later, by "Board: Catch up".
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
                // Without staging there is no deck to test on: marking the release tested is the whole of it.
                button("Release: Mark tested", "QA passes it",
                       noStaging.contains(repo)
                           ? (releases[repo]?.contains(where: { $0.state == "OPEN" && $0.isProduction && $0.untested }) == true ? nil
                               : .missing("an untested release on \(repo)", { [weak self] in self?.layProduction() }))
                           : (onDeck(repo).isEmpty ? .missing("something on \(repo)'s deck", { [weak self] in self?.layOnDeck() }) : nil)),
                button("Release: Production merges", "Production merges: it ships", productionOpen),
                button("Repo: No staging", shown: false),
                button("Repo: Ships on merge", shown: false),
            ]),
            Group(id: "Everyone", note: nil, buttons: [
                button("Everyone to lounge", "To the lounge"), button("Breather", "One takes a break"),
                button("Everyone asleep", "All sessions quiet"),
                button("Bath", "To the bath"),
                button("Chore", "A chore"), button("Workout", "A turn in the gym"),
                button("Meet in the hall", "A meeting in the hall"), button("Wedge carrier", "Wedge a carrier"),
                button("Night", shown: false), button("Day", shown: false),
            ]),
        ]
    }

    /// The clock's own row, never blocked.
    let timeNames = ["Pause", "Resume", "Step", "¼x", "½x", "1x", "4x", "16x"]

    var buttonNames: [String] { groups.flatMap(\.buttons).map(\.name) + timeNames }

    /// Stops the beats this model keeps, for a station that is being thrown away.
    func quiesce() { peerBeat?.invalidate(); peerBeat = nil }

    func press(_ name: String) {
        note("press", name, .press(name))
        if name.hasPrefix("Target: ") {
            pick(String(name.dropFirst(8)))
        } else if name.hasPrefix("Board: Move "), let to = name.range(of: " to ") {
            // Scripted: "Board: Move api#5161 to Backlog", any item, any column, the picker untouched.
            let id = String(name[name.index(name.startIndex, offsetBy: 12)..<to.lowerBound])
            let column = String(name[to.upperBound...])
            guard let it = board.first(where: { "\($0.repo)#\($0.number)" == id }) else {
                return note("skipped", "no board item \(id)", .skipped("no board item \(id)"))
            }
            move([it], to: column)
        } else if name.hasPrefix("Set: "), let eq = name.range(of: " = ") {
            // Scripted: "Set: session = waiting for you", "Set: web's pipeline = no staging branch".
            // The knob's name may be given in full or by its last words, so "pipeline" finds it too.
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
                // The ground goes down without the move being played, and the move follows a beat
                // later, on the station clock, so what was just put there has been taken in first.
                note("set up", what)
                lay()
                station.after(1) { [weak self] in
                    guard let self else { return }
                    if let again = groups.flatMap(\.buttons).first(where: { $0.name == name }), let why = again.blocked {
                        return note("skipped", "set-up did not take: " + why.words, .skipped(why.words))
                    }
                    run(name)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.refresh() }
                }
            }
        } else {
            note("skipped", "no such button: \(name)", .skipped("no such button: \(name)"))
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.refresh() }
    }

    /// A knob of the board, from a script. The value must be one the knob offers; "yes" and "no"
    /// work a flag, and a number a count.
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

    /// The picker, from a script: "Target: web#455".
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
            speed = SimulatorPanel.speedValue(name)
            station.sim?.timeScale = speed
        }
    }

    /// Every button's work. Nothing here checks whether it applies: `press` did that.
    private func run(_ name: String) {
        let repo = targetRepo
        if name.hasPrefix("Stage: "), let stage = Stage.allCases.first(where: { "\($0)" == String(name.dropFirst(7)) }), let o = office {
            let works = station.world.works
            let record = works.find(repo: o.repo, issue: o.number) ?? works.find(repo: o.repo, pull: o.number)
                ?? works.note(repo: o.repo, branch: o.branch, issue: o.number)
            works.report(record, stage, by: stageSource, at: station.now)
            note("sim", "\(o.repo)#\(o.number) → \(stage) · \(stageSource.rawValue) · now \(record.stage.map { "\($0)" } ?? "-")")
            pushScan()   // nothing else the station watches has changed: its own sessions again, so it looks
            return
        }
        switch name {

        // Me
        case "New branch in repo":
            // A new office of mine beside the target, in the target's repository. It becomes the target.
            let n = nextIssue(repo)
            let o = addMine(repo: repo, number: n, slug: "sim-\(n)", branch: "gh-\(n)/new-work-\(n)",
                            title: "new work \(n)", activity: .coding("src"), commits: 2)
            board.append(item(repo, n, "new work \(n)", statuses.development, "me"))
            target = o.uid
            pushGitHub()
            pushScan()
        case "Commit":
            // One more commit ahead on the branch: the worker stows a cube for it.
            guard let o = office, let i = index(o.uid) else { return }
            offices[i].commits += 1
            pushScan()
            station.simulateGitHub()   // the commit count is GitHub's answer; a poll would have said so
        case "Prompt":
            guard var s = targetSession else { return }
            s.prompts += 1
            s.markers[.prompt] = UUID().uuidString
            s.last = station.now
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
        case "Teammate: Merge PR", "Teammate: Close PR", "Teammate: Close PR (feed lags)":
            guard let o = leoOpenPR else { return }
            offices.removeAll { $0.uid == o.uid }
            let fate = name.contains("Merge PR") ? "MERGED" : "CLOSED"
            pullFates["\(o.repo)#\(o.number)"] = fate
            // Asked by number or by branch, GitHub answers the pull request's state; the feed may or may not have it yet.
            let answer = PullRequest(number: o.number, title: o.title, state: fate, reviewDecision: "", isDraft: false, url: "https://example.invalid/\(o.repo)/\(o.number)")
            github.inject(pull: answer, for: o.branch, repoRoot: root(o.repo))
            github.inject(pull: answer, number: o.number, repoRoot: root(o.repo))
            if !name.hasSuffix("(feed lags)") {
                feedEvent(fate == "MERGED" ? "pr_merge" : "pr_close", repo: o.repo, branch: o.branch, pr: o.number, title: o.title)
            }
            pushGitHub()

        // Dependabot, through the open pull request list and the activity feed
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

        case "GitHub: Poll":
            pushGitHub()
        case "Scan: again":
            pushScan()

        // Board
        case "Board: Move":
            guard let it = office.flatMap(boardItem) else { return }
            move([it], to: column)
        case "Board: Catch up":
            move(board.filter { $0.repo == repo && $0.status == statuses.storage }, to: statuses.deck)

        // Releases, on the target's repository
        case "Repo: Ships on merge":
            shipsOnMerge.insert(repo)
            let cfg = ConfigStore.shared.current
            github.inject(pipeline: Pipeline(trunk: cfg.trunkBranch, staging: "", production: "", source: "workflow", why: "deploys on every push", ship: "merge"), for: root(repo))
            pushGitHub()
        case "Repo: No staging":
            noStaging.insert(repo)
            let cfg = ConfigStore.shared.current
            github.inject(pipeline: Pipeline(trunk: cfg.trunkBranch, staging: "", production: "master"), for: root(repo))
            // Without staging nothing of the repository is ever on a deck: whatever the seed put there waits in storage.
            move(board.filter { $0.repo == repo && ($0.status == statuses.deck || $0.status == statuses.cleared) }, to: statuses.storage)
            pushGitHub()
        case "Release: Staging opens":
            let cfg = ConfigStore.shared.current
            nextRelease += 1
            releases[repo, default: []].append(ReleasePR(number: nextRelease, title: "release to staging", base: cfg.stagingBranch,
                                                         head: cfg.trunkBranch, state: "OPEN",
                                                         url: "https://example.invalid/\(repo)/\(nextRelease)", labels: [], mergedAt: nil))
            pushGitHub()
        case "Release: Staging merges", "Release: Staging merges (board lags)":
            guard let i = openRelease(repo, production: false) else { return }
            let pr = releases[repo]![i]
            releases[repo]![i] = ReleasePR(number: pr.number, title: pr.title, base: pr.base, head: pr.head, state: "MERGED",
                                           url: pr.url, labels: pr.labels, mergedAt: station.now, production: pr.production, staging: pr.staging)
            // With a board, the merge is a bell; the crates move because the columns move.
            if ConfigStore.shared.current.project != nil { launches.append((repo, releases[repo]![i])) }
            pushGitHub()
            // The board is its own poll: in life it answers minutes after the release did. The lagging
            // press leaves it where it is, for "Board: Catch up" to move later.
            if !name.hasSuffix("(board lags)") { move(board.filter { $0.repo == repo && $0.status == statuses.storage }, to: statuses.deck) }
        case "Release: Staging closes":
            guard let i = openRelease(repo, production: false) else { return }
            let pr = releases[repo]![i]
            releases[repo]![i] = ReleasePR(number: pr.number, title: pr.title, base: pr.base, head: pr.head, state: "CLOSED",
                                           url: pr.url, labels: pr.labels, mergedAt: nil, production: pr.production, staging: pr.staging)
            pushGitHub()
        case "Release: Production opens":
            let cfg = ConfigStore.shared.current
            nextRelease += 1
            let bare = noStaging.contains(repo)
            releases[repo, default: []].append(ReleasePR(number: nextRelease, title: "release to production", base: bare ? "master" : cfg.productionBranch,
                                                         head: bare ? "release/v\(nextRelease)" : cfg.stagingBranch, state: "OPEN",
                                                         url: "https://example.invalid/\(repo)/\(nextRelease)", labels: ["untested"], mergedAt: nil,
                                                         production: true, staging: false))
            pushGitHub()
        case "Release: Mark tested":
            // QA passing takes the untested label off an open production release as well as
            // moving the column: that is what clears the rocket to load.
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
            // The board catches up after the rocket has been loaded, the way a later poll would;
            // moving the column in the same breath empties the deck before anyone can carry it.
            // On the station clock, so a stepped or paused station waits for it too.
            let shipping = repo
            station.after(6) { [weak self] in
                guard let self else { return }
                let st = self.statuses
                move(board.filter { $0.repo == shipping && ($0.status == st.cleared || $0.status == st.deck || (self.noStaging.contains(shipping) && $0.status == st.storage)) }, to: st.shipped)
            }

        // Station
        case "Night": station.simulate(.night(true))
        case "Day": station.simulate(.night(false))
        case "Everyone to lounge": station.simulate(.lounge)
        case "Breather": station.simulate(.breather(.lounge))
        case "Everyone asleep": station.simulate(.turnIn)
        case "Bath": station.simulate(.bath)
        case "Chore": station.simulate(.chore)
        case "Meet in the hall": station.simulate(.meet)
        case "Workout": station.simulate(.workout)
        case "Wedge carrier": station.simulate(.wedge)

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

    /// The event and command taps fire on the scene's render thread, so the log is kept behind a
    /// lock and the panel only asks it for text.
    private let lines = SimLog()

    /// A line for the panel, and, when it is one of the things a scenario judges, the typed record of it.
    nonisolated func note(_ kind: String, _ text: String, _ record: SimRecord? = nil) {
        lines.add(kind: kind, text: text, record: record)
        DispatchQueue.main.async { [weak self] in self?.objectWillChange.send() }
    }

    var logText: String { lines.text }
    /// The whole run as text, oldest first: what `--scenarios-verbose` prints.
    var logLines: [String] { lines.ordered }
    /// The whole run as it happened, typed: what `--scenarios` judges. Never the text.
    var records: [SimRecord] { lines.records }

    nonisolated static func describe(_ e: WorldEvent) -> String {
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
        case .crewRoster(let m): return "crewRoster \(m.keys.sorted().joined(separator: ","))"
        case .deconArrived(let st, let repo, let ns): return "deconArrived \(st) \(repo) \(ns.map { "#\($0)" }.joined(separator: ","))"
        case .deconCleared(_, let repo, let n): return "deconCleared \(repo)#\(n)"
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

/// One thing a simulated run did, as the value it was: what a scenario's expectations match on.
/// The text in the log is for reading; nothing judges it.
enum SimRecord {
    case press(String)
    /// A press the panel refused, and why.
    case skipped(String)
    case event(WorldEvent)
    /// A command and who ran it: a worker's office, or "shuttle" and "rocket".
    case command(Command, by: String)
    /// A rule of STATION.md broken, in the words `Invariants` gives it.
    case violation(String)

    var words: String {
        switch self {
        case .press(let n): return "press \(n)"
        case .skipped(let why): return "skipped: \(why)"
        case .event(let e): return "event \(SimulatorModel.describe(e))"
        case .command(let c, let who): return "command \(who): \(c.words)"
        case .violation(let t): return t
        }
    }
}

/// The simulator's log, written from any thread and read by the panel.
final class SimLog: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []
    /// The typed side of `whole`, kept only for the things a scenario can judge.
    private var typed: [SimRecord] = []
    private static let stamp: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f
    }()

    /// The same lines the panel shows, oldest first and uncapped: what a scripted run reads.
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
// MARK: the panel

/// Two halves, with a line between them. Above it, the board: what the position *is*, one knob per
/// fact — the session in the office, its commits, its pull request, its column, the repository's
/// pipeline and releases, whether the peer is on the network, whether it is night. Below it, the
/// moves: one press each, and each of them one press away whatever the board says, because a move
/// whose ground is not laid lays it first and then plays.
struct SimulatorPanel: View {
    /// The clock rate a speed button stands for.
    static func speedValue(_ name: String) -> Double { ["¼x": 0.25, "½x": 0.5][name] ?? Double(name.dropLast()) ?? 1 }

    @ObservedObject var model: SimulatorModel
    /// The board folds away once the position is set, so the moves are not pushed off the bottom.
    @AppStorage("simBoardOpen") private var boardOpen = true

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    time
                    targetBox
                    boardBox
                    Divider().padding(.vertical, 2)
                    ForEach(model.groups) { g in
                        let shown = g.buttons.filter(\.shown)
                        if !shown.isEmpty {
                            VStack(alignment: .leading, spacing: 5) {
                                header(g.id)
                                if let n = g.note {
                                    Text(n).font(.system(size: 9)).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)
                                }
                                if g.id.hasPrefix("A source speaks") {
                                    Picker("", selection: $model.stageSource) {
                                        ForEach(Source.allCases, id: \.self) { Text($0.title).tag($0) }
                                    }.labelsHidden().controlSize(.small)
                                }
                                ForEach(shown) { b in move(b) }
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

    /// One move. A move that has to lay its own ground says so rather than going grey: only a move
    /// that has already happened is out of reach.
    @ViewBuilder private func move(_ b: SimulatorModel.Button) -> some View {
        let lays: String? = { if case .missing(let what, _) = b.blocked { return what }; return nil }()
        let done: String? = { if case .already(let why) = b.blocked { return why }; return nil }()
        Button {
            model.press(b.name)
        } label: {
            HStack(spacing: 4) {
                Text(b.label)
                if lays != nil {
                    Image(systemName: "arrow.turn.down.right").font(.system(size: 8)).foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .controlSize(.small)
        .disabled(done != nil)
        .help(done ?? lays.map { "sets up \($0) first, then plays" } ?? b.name)
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

    /// The position: set it to whatever you want to watch a move land on.
    @ViewBuilder private var boardBox: some View {
        DisclosureGroup(isExpanded: $boardOpen) {
            VStack(alignment: .leading, spacing: 6) {
                knobs
            }
            .padding(.top, 4)
        } label: {
            header("The board")
        }
    }

    @ViewBuilder private var knobs: some View {
        Group {
            ForEach(model.position) { s in
                switch s.kind {
                case .pick(let options, let now, let set):
                    knob(s.id) {
                        Picker("", selection: Binding(get: { now }, set: { if $0 != now { set($0) } })) {
                            ForEach(options, id: \.self) { Text($0).tag($0) }
                        }.labelsHidden().controlSize(.small)
                    }
                case .flag(let on, let set):
                    knob(s.id) {
                        Toggle("", isOn: Binding(get: { on }, set: { if $0 != on { set($0) } }))
                            .labelsHidden().controlSize(.mini).toggleStyle(.switch)
                    }
                case .count(let now, let of, let set):
                    knob(s.id) {
                        Picker("", selection: Binding(get: { now }, set: { if $0 != now { set($0) } })) {
                            // Whatever it stands at now belongs in the list, even off the usual steps.
                            ForEach(of.contains(now) ? of : (of + [now]).sorted(), id: \.self) { Text("\($0)").tag($0) }
                        }.labelsHidden().controlSize(.small)
                    }
                }
            }
        }
    }

    /// One knob: its name on the left, the control on the right.
    private func knob<C: View>(_ name: String, @ViewBuilder _ control: () -> C) -> some View {
        HStack(spacing: 6) {
            Text(name).font(.system(size: 10)).foregroundStyle(.secondary)
                .frame(width: 96, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            control()
        }
    }

    @ViewBuilder private var time: some View {
        VStack(alignment: .leading, spacing: 5) {
            header("Time")
            HStack(spacing: 6) {
                Button { model.press(model.paused ? "Resume" : "Pause") } label: {
                    Image(systemName: model.paused ? "play.fill" : "pause.fill").frame(width: 22)
                }
                .help(model.paused ? "Resume" : "Pause")
                Button { model.press("Step") } label: { Image(systemName: "forward.frame.fill").frame(width: 22) }
                    .help("Step: a fifth of a second")
                Button("Reset org") { model.onReset?() }.help("Start over with a fresh station and org")
            }
            .controlSize(.small)
            HStack(spacing: 6) {
                ForEach(["¼x", "½x", "1x", "4x", "16x"], id: \.self) { s in
                    Button(s) { model.press(s) }
                        .buttonStyle(.borderedProminent)
                        .tint(model.speed == Self.speedValue(s) ? .accentColor : .gray)
                }
            }
            .controlSize(.small)
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
        .frame(height: 200)
    }
}

// MARK: the simulator's way in

/// What a simulator window plants in a live controller: the event and command taps, its own clock,
/// and the two things no source drives. A normal window leaves `sim` nil and none of this runs.
final class SimHooks {
    var onEvent: ((WorldEvent) -> Void)?
    /// What the simulated GitHub says a pull request's fate is, by repository and number: OPEN, MERGED
    /// or CLOSED, or nil for one it never spoke about. The rulebook's meaning checks read it.
    var pullState: ((String, Int) -> String?)?
    /// The command and who is running it: a worker's office, or "shuttle" and "rocket".
    var onCommand: ((Command, String) -> Void)?
    /// A rule of STATION.md the floor just broke, in the words `Invariants` gives it.
    var onViolation: ((String) -> Void)?
    /// The rulebook, checked at the end of every simulated step.
    let invariants = Invariants()
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
enum SimNudge { case bath, breather(Place), chore, lounge, meet, night(Bool?), turnIn, wedge, workout }

extension StationController {
    /// Small enough that a minion at sixteen times speed still walks rather than jumps.
    private static var simStep: Double { 1.0 / 30.0 }

    /// Station time, stepped directly with no frame and no wall clock: what the scenario suite runs on.
    func stepSimulated(seconds: Double) {
        guard let sim else { return }
        pendingLock.lock(); let work = pending; pending.removeAll(); pendingLock.unlock()
        for w in work { w() }
        var budget = seconds
        while budget > 0 {
            let step = min(StationController.simStep, budget)
            budget -= step
            sim.clock += step
            tick(now: sim.clock)
            sim.invariants.check(self)
        }
    }

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
            sim.invariants.check(self)
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

    /// A sim press says "now": whatever a minion was doing that is not a job is dropped so the press can take.
    private func free(_ m: Minion) {
        m.busy = false
        m.activity = .waiting
        if let c = m.current, !c.isRest { finish(m) }
    }

    func simulate(_ nudge: SimNudge) {
        enqueue { [self] in
            switch nudge {
            case .bath:
                // The press says "now": whoever is resting goes for a shower straight away, picked as for the gym.
                let could = minions.values.filter { !$0.isSubagent && !$0.onJob && !$0.bathing && !$0.exercising && !$0.hasLoad }
                let m = could.first(where: { !$0.isCrew && !$0.busy && $0.place == .lounge })
                    ?? could.first(where: { !$0.isCrew && !$0.busy })
                    ?? could.first(where: { !$0.isCrew && $0.activity == .waiting })
                    ?? could.first(where: { $0.isCrew && !$0.busy })
                    ?? could.first   // the press says now: a busy worker drops its work for it
                guard let m, let station = fleet.stations[m.station], station.rooms["kind:bath"] != nil else {
                    handle(.log(could.isEmpty ? "nobody free for the bath" : "no bath on the station")); return
                }
                free(m)
                m.showering = true
                if !visitBath(m, station: station) { handle(.log("both fixtures in the bath are taken")) }
            case .workout:
                // The press says "now": whoever is resting takes a turn straight away, night or not.
                // A worker on the couch first; then any worker not working; then a worker whose session is
                // quiet but still counted busy; then a teammate asleep in the quarters. Only a job, the
                // bath or a turn already in hand rules someone out.
                let could = minions.values.filter { !$0.isSubagent && !$0.onJob && !$0.bathing && !$0.exercising && !$0.hasLoad }
                let m = could.first(where: { !$0.isCrew && !$0.busy && $0.place == .lounge })
                    ?? could.first(where: { !$0.isCrew && !$0.busy })
                    ?? could.first(where: { !$0.isCrew && $0.activity == .waiting })
                    ?? could.first(where: { $0.isCrew && !$0.busy })
                    ?? could.first   // the press says now: a busy worker drops its work for it
                guard let m, let station = fleet.stations[m.station], let gym = station.rooms["kind:gym"] else {
                    handle(.log(could.isEmpty ? "nobody free for the gym" : "no gym on the station")); return
                }
                m.bathDue = 0
                m.nextWorkoutAt = 0
                free(m)
                if !takeTurnInGym(m, station: station, gym: gym) { handle(.log("every fixture in the gym is taken")) }
            case .wedge:
                // Whoever is carrying a crate stops dead: the station has to catch up without them.
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
                // Two free minions set at the two ends of the hall's east-west arm, facing each other, each
                // ordered straight along the row to the other's spot: they have to pass, and the walk rule shows how.
                // The press says "now": any two, whatever they were doing, the way "Everyone to lounge" does it.
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
                // Every session gone quiet at once, which is what a real night looks like and what a
                // single body in a dorm never tests: the bunks are claimed together and the walks to
                // them cross. Only a body whose session is asleep is ever sent to a bunk, so this says
                // that of all of them and lets the night do the rest.
                for m in minions.values where !m.isSubagent && !m.onJob && !m.hasLoad {
                    m.busy = false
                    m.activity = .sleeping
                    if let c = m.current, !c.isRest { finish(m) }
                    send(m, to: restPlace(m))
                }
            case .breather(let place):
                // "Everyone to lounge" ends the work: it makes a body idle and parks it there. This does
                // not. A body at work walks off, sits a moment and goes back to what it was doing, because
                // the trip is a reaction — the activity and the office are untouched, and when the reaction
                // runs out the body is sent back to its place. Nothing on the station ever chooses this;
                // it is a press, so the floor never tells you a session is resting when it is working.
                let atWork = minions.values.filter {
                    $0.busy && !$0.isSubagent && !$0.onJob && !$0.hasLoad && !$0.bathing && !$0.exercising
                }
                guard let m = atWork.first(where: { !$0.isCrew }) ?? atWork.first else {
                    handle(.log("nobody at work to send for a break")); return
                }
                react(m, m.activity, place: place, minutes: 12.0 / 60, words: "\(m.home.name) taking a break")
            case .night(let on):
                sim?.night = on
                for m in minions.values where !m.onJob { send(m, to: restPlace(m)) }
                handle(.log(on == true ? "night falls" : on == false ? "morning" : "back on the clock"))
            }
        }
    }


    func simulateLog(_ text: String) { enqueue { [self] in logEvent(text) } }
}

extension SimulatorModel {
    /// The board's knobs as lines of text: what `--dump-board` prints, so a scripted run can check
    /// the position without a picture of the panel.
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
