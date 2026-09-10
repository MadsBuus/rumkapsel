import AppKit
import SwiftUI

/// A station driven by hand. The window holds a real `StationController` with the scanner, GitHub
/// and the network switched off, and a panel of buttons that write synthetic facts into the same
/// entry points production uses: `applyScan`, `applyGitHub`, `applyPeer`. Every `WorldEvent` and
/// every `Command` shows up in the log at the bottom, so a cue that never fires is visible.
@MainActor
final class SimulatorController {
    let station: StationController
    let model: SimulatorModel
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

/// One session in the simulator's org. The cwd is a real directory under a temp root, because the
/// model asks the file system whether a checkout is still there.
private struct SimSession {
    var id: String
    var repo: String
    var branch: String
    var cwd: String
    var activity: Activity
    var last: Date
    var prompts = 0
    var queued = 0
    var markers: [StationEvent: String] = [:]
}

@MainActor
final class SimulatorModel: ObservableObject {
    let station: StationController
    private var github: GitHubResolver { station.world.github }

    let repos = ["web", "api", "ios"]
    let teammate = "leo"
    let peerName = "kim"

    @Published var office = ""
    @Published var repo = "web"
    @Published var issue = ""
    @Published var column = ""
    @Published var speed = 1.0
    @Published var paused = false
    @Published var offices: [String] = []
    @Published var issues: [String] = []

    private var sessions: [String: SimSession] = [:]
    private var board: [ProjectItem] = []
    private var openPRs: [String: [OpenPR]] = [:]
    private var feeds: [String: [FeedEvent]] = [:]
    private var releases: [String: [ReleasePR]] = [:]
    private var peerOffices: [PeerSnapshot.Office] = []
    private var launches: [(repo: String, pr: ReleasePR)] = []
    private var peerHere = false
    private var peerBeat: Timer?
    private var nextIssue = 700
    private var nextRelease = 9000
    private var nextSession = 0

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

    /// A deterministic org: three repositories, four offices, three sessions, crates in storage and
    /// on the deck, one teammate with a pull request and one peer on the network.
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
        openPRs = [
            "api": [OpenPR(number: 5140, title: "settlement redesign", author: teammate, isBot: false,
                           branch: "gh-5140/settlement-redesign", url: "https://example.invalid/api/5140", createdAt: Date().addingTimeInterval(-7200))],
        ]
        addSession(repo: "web", slug: "damascus", branch: "gh-455/booking-flow", activity: .coding("app"), commits: 4)
        addSession(repo: "api", slug: "bismarck", branch: "gh-5158/offerings-gate", activity: .testing, commits: 2)
        addSession(repo: "ios", slug: "lima", branch: "gh-298/onboarding", activity: .waiting, commits: 1)
        peerOffices = [peerOffice(repo: "web", branch: "gh-460/artist-tags", name: "#460 artist tags", started: Date().addingTimeInterval(-3600), pushed: true)]

        github.inject(project: board, quiet: true)
        github.injectSilently = false
        pushGitHub()          // taken quietly: the repositories answer for the first time here
        pushScan()
        peerHere = true
        pushPeer()
        pushGitHub()
        refreshChoices()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.refreshChoices() }
        note("sim", "org seeded: \(repos.joined(separator: ", "))")
    }

    private func item(_ repo: String, _ number: Int, _ title: String, _ status: String, _ who: String) -> ProjectItem {
        ProjectItem(repo: repo, number: number, title: title, status: status, assignees: [who],
                    prURLs: [], url: "https://example.invalid/\(repo)/\(number)", updatedAt: Date())
    }

    @discardableResult
    private func addSession(repo: String, slug: String, branch: String, activity: Activity, commits: Int) -> String {
        let cwd = worktree(repo, slug)
        makeDir(cwd)
        nextSession += 1
        let id = "sim-\(nextSession)"
        sessions[id] = SimSession(id: id, repo: repo, branch: branch, cwd: cwd, activity: activity, last: Date())
        github.inject(commits: commits, pushed: true, worktree: cwd)
        return id
    }

    private func peerOffice(repo: String, branch: String, name: String, started: Date, pushed: Bool) -> PeerSnapshot.Office {
        PeerSnapshot.Office(key: Home.from(repo: repo, branch: branch, cwd: "").key, name: name, repo: repo, branch: branch,
                            color: station.world.fleet.color(forRepo: repo), cells: [], pushed: pushed,
                            startedAt: started, lastActive: Date(), boxes: 2, dim: false)
    }

    // MARK: pushing facts in

    private func info(_ s: SimSession) -> SessionInfo {
        SessionInfo(id: s.id, cwd: s.cwd, repo: s.repo, repoRoot: root(s.repo), owner: "simcorp", lastModified: s.last,
                    activity: s.activity, area: nil, title: nil, branch: s.branch, toolCount: 0, isSubagent: false,
                    cwdExists: true, promptCount: s.prompts, queuedCount: s.queued, eventMarkers: s.markers)
    }

    private func pushScan() {
        station.simulate(scan: ScanResult(sessions: sessions.values.map(info).sorted { $0.id < $1.id }))
    }

    private func pushGitHub() {
        github.injectSilently = true
        defer { github.injectSilently = false; station.simulateGitHub() }
        for r in repos {
            let sent = launches.filter { $0.repo == r }.map(\.pr)
            github.inject(openPRs: openPRs[r] ?? [], for: root(r))
            github.inject(feed: feeds[r] ?? [], for: root(r))
            github.inject(releases: releases[r] ?? [], for: root(r), merged: sent)
        }
        launches = []
        github.inject(project: board)
    }

    private func pushPeer() {
        guard peerHere else { return }
        let ms = peerOffices.prefix(1).map { PeerSnapshot.Minion(id: "kim-1", office: $0.key, asleep: false, busy: true) }
        let snap = PeerSnapshot(version: PeerSnapshot.current, name: peerName, since: Date().addingTimeInterval(-600),
                                offices: peerOffices, minions: Array(ms), github: nil, project: nil)
        station.simulate(peer: snap)
    }

    private func feedEvent(_ kind: String, repo: String, branch: String?, pr: Int?, title: String?, detail: String = "") {
        let e = FeedEvent(at: Date(), actor: teammate, isBot: false, kind: kind, branch: branch, prNumber: pr,
                          title: title, url: "https://example.invalid/\(repo)", detail: detail)
        feeds[repo, default: []].insert(e, at: 0)
        feeds[repo] = Array(feeds[repo]!.prefix(40))
    }

    /// The selected office's session, if it has one.
    private var selectedSession: SimSession? {
        guard let key = office.split(separator: "|", maxSplits: 1).last.map(String.init) else { return nil }
        return sessions.values.first { Home.from(repo: $0.repo, branch: $0.branch, cwd: $0.cwd).key == key }
    }

    private func setSession(_ s: SimSession) { sessions[s.id] = s }

    private var selectedIssue: ProjectItem? {
        board.first { "\($0.repo)#\($0.number)" == issue }
    }

    private func setPull(_ pr: PullRequest?, repo: String, branch: String) {
        github.inject(pull: pr, for: branch, repoRoot: root(repo))
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

    func refreshChoices() {
        station.simulatedOffices { [weak self] all in
            guard let self else { return }
            let mine = all.filter { !$0.contains("|kind:") }
            offices = mine
            // An office with a session of ours is the useful default: most buttons need one.
            let mine2 = sessions.values.map { "work|" + Home.from(repo: $0.repo, branch: $0.branch, cwd: $0.cwd).key }
            if !mine.contains(office) { office = mine.first { mine2.contains($0) } ?? mine.first ?? "" }
        }
        issues = board.map { "\($0.repo)#\($0.number)" }
        if !issues.contains(issue) { issue = issues.first ?? "" }
        if !columns.contains(column) { column = columns.first ?? "" }
    }

    // MARK: the buttons

    struct Group: Identifiable { let id: String; let picker: String?; let buttons: [String] }

    var groups: [Group] {
        [
            Group(id: "Sessions", picker: "office", buttons: [
                "New session on a new branch", "Session prompt (adds a cone)", "Session goes busy",
                "Session goes quiet", "Session ends", "Session switches branch",
            ]),
            Group(id: "Teammates", picker: "repo", buttons: [
                "Teammate opens PR", "Teammate pushes", "Teammate PR merged", "Teammate PR closed (not merged)",
            ]),
            Group(id: "Own office", picker: "office", buttons: [
                "Open PR", "PR approved", "Checks failing", "PR merged", "PR closed (not merged)",
            ]),
            Group(id: "Releases", picker: "repo", buttons: [
                "Staging release opens", "Staging release merges", "Staging release closes (not merged)",
                "Production release opens (untested)",
                "Mark tested / ready to ship (board)", "Production release merges (ship)",
            ]),
            Group(id: "Board", picker: "issue", buttons: ["Move issue"]),
            Group(id: "Peers", picker: "office", buttons: [
                "Peer arrives with an office", "Peer starts a new office", "Peer pushes branch", "Peer leaves", "Kick office",
            ]),
            Group(id: "Station", picker: nil, buttons: ["Night", "Day", "Everyone to lounge", "Trigger bath", "Trigger chore"]),
        ]
    }

    var buttonNames: [String] { groups.flatMap(\.buttons) + ["Pause", "Resume", "Step", "1x", "4x", "16x"] }

    func press(_ name: String) {
        note("press", name)
        switch name {

        // Sessions
        case "New session on a new branch":
            nextIssue += 1
            let n = nextIssue
            let branch = "gh-\(n)/new-work-\(n)"
            addSession(repo: repo, slug: "sim-\(n)", branch: branch, activity: .coding("src"), commits: 2)
            board.append(item(repo, n, "new work \(n)", statuses.development, "me"))
            pushGitHub()
            pushScan()
        case "Session prompt (adds a cone)":
            guard var s = selectedSession else { return miss("no session in that office") }
            s.prompts += 1
            s.markers[.prompt] = UUID().uuidString
            s.last = Date()
            setSession(s)
            pushScan()
        case "Session goes busy":
            guard var s = selectedSession else { return miss("no session in that office") }
            s.activity = .coding("src"); s.last = Date()
            setSession(s)
            pushScan()
        case "Session goes quiet":
            guard var s = selectedSession else { return miss("no session in that office") }
            s.activity = .waiting; s.last = Date().addingTimeInterval(-600)
            setSession(s)
            pushScan()
        case "Session ends":
            guard let s = selectedSession else { return miss("no session in that office") }
            sessions[s.id] = nil
            pushScan()
        case "Session switches branch":
            guard var s = selectedSession else { return miss("no session in that office") }
            nextIssue += 1
            s.branch = "gh-\(nextIssue)/switched-\(nextIssue)"
            s.last = Date()
            setSession(s)
            pushScan()

        // Teammates, through the open pull request list and the activity feed
        case "Teammate opens PR":
            nextIssue += 1
            let n = nextIssue
            let branch = "gh-\(n)/teammate-\(n)"
            openPRs[repo, default: []].append(OpenPR(number: n, title: "teammate work \(n)", author: teammate, isBot: false,
                                                     branch: branch, url: "https://example.invalid/\(repo)/\(n)", createdAt: Date()))
            feedEvent("pr_open", repo: repo, branch: branch, pr: n, title: "teammate work \(n)")
            pushGitHub()
        case "Teammate pushes":
            guard let pr = openPRs[repo]?.last else { return miss("\(teammate) has no open PR on \(repo)") }
            feedEvent("push", repo: repo, branch: pr.branch, pr: pr.number, title: pr.title, detail: "2")
            pushGitHub()
        case "Teammate PR merged", "Teammate PR closed (not merged)":
            guard let pr = openPRs[repo]?.last else { return miss("\(teammate) has no open PR on \(repo)") }
            openPRs[repo]?.removeLast()
            feedEvent(name.contains("merged") ? "pr_merge" : "pr_close", repo: repo, branch: pr.branch, pr: pr.number, title: pr.title)
            pushGitHub()

        // My own office
        case "Open PR", "PR approved", "Checks failing", "PR merged", "PR closed (not merged)":
            guard let s = selectedSession else { return miss("no session in that office") }
            let n = Home.from(repo: s.repo, branch: s.branch, cwd: s.cwd).issue ?? 1
            let url = "https://example.invalid/\(s.repo)/\(n)"
            var pr = PullRequest(number: n, title: "work on \(s.branch)", state: "OPEN", reviewDecision: "REVIEW_REQUIRED",
                                 isDraft: false, url: url)
            switch name {
            case "PR approved": pr = PullRequest(number: n, title: pr.title, state: "OPEN", reviewDecision: "APPROVED", isDraft: false, url: url)
            case "Checks failing":
                pr = PullRequest(number: n, title: pr.title, state: "OPEN", reviewDecision: "REVIEW_REQUIRED", isDraft: false, url: url)
                pr.checks = "failure"
            case "PR merged": pr = PullRequest(number: n, title: pr.title, state: "MERGED", reviewDecision: "APPROVED", isDraft: false, url: url)
            case "PR closed (not merged)": pr = PullRequest(number: n, title: pr.title, state: "CLOSED", reviewDecision: "", isDraft: false, url: url)
            default: break
            }
            setPull(pr, repo: s.repo, branch: s.branch)

        // Releases
        case "Staging release opens":
            let cfg = ConfigStore.shared.current
            nextRelease += 1
            releases[repo, default: []].append(ReleasePR(number: nextRelease, title: "release to staging", base: cfg.stagingBranch,
                                                         head: cfg.trunkBranch, state: "OPEN",
                                                         url: "https://example.invalid/\(repo)/\(nextRelease)", labels: [], mergedAt: nil))
            pushGitHub()
        case "Staging release merges":
            let cfg = ConfigStore.shared.current
            guard let i = releases[repo]?.lastIndex(where: { $0.state == "OPEN" && $0.isStaging }) else { return miss("no open staging release on \(repo)") }
            let pr = releases[repo]![i]
            releases[repo]![i] = ReleasePR(number: pr.number, title: pr.title, base: pr.base, head: pr.head, state: "MERGED",
                                           url: pr.url, labels: pr.labels, mergedAt: Date())
            // With a board, the merge is a bell; the crates move because the columns move.
            if cfg.project != nil { launches.append((repo, releases[repo]![i])) }
            pushGitHub()
            move(board.filter { $0.repo == repo && $0.status == statuses.storage }, to: statuses.deck)
        case "Staging release closes (not merged)":
            guard let i = releases[repo]?.lastIndex(where: { $0.state == "OPEN" && $0.isStaging }) else { return miss("no open staging release on \(repo)") }
            let pr = releases[repo]![i]
            releases[repo]![i] = ReleasePR(number: pr.number, title: pr.title, base: pr.base, head: pr.head, state: "CLOSED",
                                           url: pr.url, labels: pr.labels, mergedAt: nil)
            pushGitHub()
        case "Production release opens (untested)":
            let cfg = ConfigStore.shared.current
            nextRelease += 1
            releases[repo, default: []].append(ReleasePR(number: nextRelease, title: "release to production", base: cfg.productionBranch,
                                                         head: cfg.stagingBranch, state: "OPEN",
                                                         url: "https://example.invalid/\(repo)/\(nextRelease)", labels: ["untested"], mergedAt: nil))
            pushGitHub()
        case "Mark tested / ready to ship (board)":
            // QA passing takes the untested label off an open production release as well as
            // moving the column: that is what clears the rocket to load.
            if let i = releases[repo]?.lastIndex(where: { $0.state == "OPEN" && $0.isProduction && $0.untested }) {
                let pr = releases[repo]![i]
                releases[repo]![i] = ReleasePR(number: pr.number, title: pr.title, base: pr.base, head: pr.head,
                                               state: pr.state, url: pr.url, labels: pr.labels.filter { !$0.lowercased().contains("untested") },
                                               mergedAt: nil)
            }
            let onDeck = board.filter { $0.repo == repo && $0.status == statuses.deck }
            guard !onDeck.isEmpty else { pushGitHub(); return miss("nothing on the deck for \(repo)") }
            move(onDeck, to: statuses.cleared)
        case "Production release merges (ship)":
            guard let i = releases[repo]?.lastIndex(where: { $0.state == "OPEN" && $0.isProduction }) else { return miss("no open production release on \(repo)") }
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

        // Board
        case "Move issue":
            guard let it = selectedIssue else { return miss("no issue picked") }
            move([it], to: column)

        // Peers
        case "Peer arrives with an office":
            peerHere = true
            if peerOffices.isEmpty {
                peerOffices = [peerOffice(repo: repo, branch: "gh-460/artist-tags", name: "#460 artist tags",
                                          started: Date().addingTimeInterval(-3600), pushed: true)]
            }
            pushPeer()
        case "Peer starts a new office":
            peerHere = true
            nextIssue += 1
            let n = nextIssue
            peerOffices.append(peerOffice(repo: repo, branch: "gh-\(n)/peer-work-\(n)", name: "#\(n) peer work",
                                          started: Date(), pushed: false))
            pushPeer()
        case "Peer pushes branch":
            guard var last = peerOffices.last else { return miss("\(peerName) has no office") }
            last.pushed = true
            last.boxes += 1
            peerOffices[peerOffices.count - 1] = last
            pushPeer()
        case "Peer leaves":
            peerHere = false
            station.simulatePeerLeft(peerName)
        case "Kick office":
            guard !office.isEmpty else { return miss("no office picked") }
            station.simulateKick(roomKey: office)

        // Station
        case "Night": station.simulate(.night(true))
        case "Day": station.simulate(.night(false))
        case "Everyone to lounge": station.simulate(.lounge)
        case "Trigger bath": station.simulate(.bath)
        case "Trigger chore": station.simulate(.chore)

        // Time
        case "Pause": paused = true; station.sim?.paused = true
        case "Resume": paused = false; station.sim?.paused = false
        case "Step": station.sim?.steps += 6
        case "1x", "4x", "16x":
            speed = Double(name.dropLast()) ?? 1
            station.sim?.timeScale = speed

        default:
            miss("no such button: \(name)")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.refreshChoices() }
    }

    private func miss(_ why: String) { note("skipped", why) }



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
                    ForEach(model.groups) { g in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(g.id.uppercased()).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                            picker(g.picker)
                            if g.id == "Board" {
                                Picker("", selection: $model.column) {
                                    ForEach(model.columns, id: \.self) { Text($0).tag($0) }
                                }.labelsHidden().controlSize(.small)
                            }
                            ForEach(g.buttons, id: \.self) { b in
                                Button(b) { model.press(b) }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .controlSize(.small)
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

    @ViewBuilder private var time: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("TIME").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
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
        }
    }

    @ViewBuilder private func picker(_ kind: String?) -> some View {
        switch kind {
        case "office":
            Picker("", selection: $model.office) {
                ForEach(model.offices, id: \.self) { Text($0.replacingOccurrences(of: "work|task:", with: "")).tag($0) }
            }.labelsHidden().controlSize(.small)
        case "repo":
            Picker("", selection: $model.repo) {
                ForEach(model.repos, id: \.self) { Text($0).tag($0) }
            }.labelsHidden().controlSize(.small)
        case "issue":
            Picker("", selection: $model.issue) {
                ForEach(model.issues, id: \.self) { Text($0).tag($0) }
            }.labelsHidden().controlSize(.small)
        default:
            EmptyView()
        }
    }

    private var logView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("LOG").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
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

    /// Every office on the floor right now, keyed "station|roomKey". Read on the scene's own turn,
    /// because the floor plan changes there.
    func simulatedOffices(_ done: @escaping ([String]) -> Void) {
        enqueue { [self] in
            let list = fleet.stations.values.flatMap { st in st.rooms.keys.map { st.name + "|" + $0 } }.sorted()
            DispatchQueue.main.async { done(list) }
        }
    }

    func simulateLog(_ text: String) { enqueue { [self] in logEvent(text) } }
}
