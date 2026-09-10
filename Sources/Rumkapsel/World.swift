import Foundation

/// The station's data layer: the sources, the floor plan they feed, and the diff between one answer
/// and the last. Nothing here draws anything and nothing here knows about SceneKit. The scene reads
/// this model for state and consumes the events `apply…` returns for cues.
///
/// A source's first answer is never an event: `readyRepos` holds the repositories GitHub has spoken
/// for, and a peer's first snapshot arrives in bulk rather than office by office.
final class World {
    let fleet = Fleet()
    let github = GitHubResolver()
    /// The demo runs on made-up rooms with no checkouts, so nothing is ever provisional.
    private let demo: Bool
    /// The simulator drives a made-up org: nothing here may read or write what the real app saved.
    var simulated = false

    init(demo: Bool) { self.demo = demo }

    /// How long an office is held for whoever last had it checked out, refreshed by their work.
    static let holdWindow: TimeInterval = 24 * 3600
    /// A teammate's action older than this is history, not news.
    static let crewRecent: TimeInterval = 30 * 60
    /// How long a session outside Conductor keeps its office.
    static let roomsWindow: TimeInterval = 12 * 3600

    private static let trunkBranches: Set<String> = ["develop", "staging", "main", "master", "production"]

    // MARK: model state

    /// Every repository we know a checkout of: its root, its name and the station it belongs to.
    private(set) var repoRoots: [String: (repo: String, station: String)] = [:]

    /// A teammate's office, as GitHub describes it.
    struct CrewRoomInfo { var repo: String; var branch: String; var prNumber: Int?; var title: String?; var author: String; var url: String?; var state: String; var last: Date }
    private(set) var crewRoomInfo: [String: CrewRoomInfo] = [:]
    private(set) var crewBoxes: [String: (count: Int, state: String, color: RGB)] = [:]
    private(set) var peerBoxes: [String: (count: Int, state: String, color: RGB)] = [:]

    // Peers on the local network: their snapshots and their claims on our floor.
    private(set) var peerSnapshots: [String: (snap: PeerSnapshot, at: Date)] = [:]
    private var peerFirstSeen: [String: Date] = [:]
    /// Peers' claims on offices of the work station, by room key ("work|task:…") then peer name.
    private(set) var peerOffices: [String: [String: PeerSnapshot.Office]] = [:]
    private(set) var pushedByPeer: Set<String> = []

    private var held: [String: Date] = [:]        // offices a peer left behind, held for a day
    private var retired: [String: Date] = [:]     // merged offices cleared away while their session lingers
    private(set) var roomCreated: [String: Date] = [:]
    private(set) var hauledAt: [String: Date] = [:]

    /// What is actually on the floor: crates by slot or on someone's arms, offices delivered or
    /// pending, who is doing what. Completions write here; the sources never do.
    var truth = StationTruth()

    /// Repositories GitHub has answered for at least once. A repository's first answer is taken quietly:
    /// nothing in it is new, whatever it holds. Only changes after that are events.
    private(set) var readyRepos: Set<String> = []
    private(set) var seenLogins: Set<String> = []
    private var crewSeen: Set<String> = []
    private var didLoadLayout = false

    /// What the scene knows and the model does not: a crate already on someone's arms, and a rocket
    /// mid-load. Both would make the yard reconciliation fight the minions carrying it out.
    var haulInFlight: (String) -> Bool = { _ in false }
    /// An office whose package is already on its way to storage.
    var haulingRoom: (String) -> Bool = { _ in false }
    /// Whether an office has a package standing on its floor at all.
    var hasPackage: (String) -> Bool = { _ in false }
    var rocketBusy: (String) -> Bool = { _ in false }

    func isReady(_ repo: String?) -> Bool { repo.map { readyRepos.contains($0) } ?? true }

    /// Settings changed: forget the fleet and start again from the next scan.
    func reset() {
        fleet.removeAllStations()
        repoRoots = [:]
        readyRepos = []
        didLoadLayout = false
    }

    // MARK: queries the scene draws from

    func crewName(_ login: String) -> String { ConfigStore.shared.current.crewNames[login] ?? login }

    /// The office key for a teammate's branch: the same key a local checkout of it would get.
    func crewKey(repo: String, branch: String) -> String { Home.from(repo: repo, branch: branch, cwd: "").key }

    func roomKey(_ station: Station, _ room: Room) -> String { "\(station.name)|\(room.key)" }

    var knownRepos: [String] { fleet.repoColors.keys.sorted() }

    /// A task room whose branch is not on GitHub yet: (unpushed, commits ahead).
    func localState(_ room: Room) -> (local: Bool, commits: Int) {
        guard room.key.hasPrefix("task:"), let w = room.worktree else { return (false, 0) }
        var pushed = github.branchPushed(worktree: w) ?? true
        if let b = room.branch, let r = room.repoRoot, github.pull(branch: b, repoRoot: r) != nil { pushed = true }
        return (!pushed, github.commitsAhead(worktree: w) ?? 0)
    }

    func checksFailing(_ room: Room) -> Bool {
        guard let b = room.branch, let r = room.repoRoot, let pr = github.pull(branch: b, repoRoot: r) else { return false }
        return pr.state == "OPEN" && pr.checks == "failure"
    }

    func isDusty(_ room: Room) -> Bool {
        !room.key.hasPrefix("kind:") && Date().timeIntervalSince(room.lastActive) > 7 * 24 * 3600
    }

    /// An office GitHub knows about that nobody here has checked out: a teammate's branch or pull request.
    func isRemoteOnly(_ station: Station, _ room: Room) -> Bool {
        let key = roomKey(station, room)
        return room.worktree == nil && (crewRoomInfo[key] != nil || pushedByPeer.contains(key))
    }

    /// An office that exists only on someone's disk, or is being held for them: drawn as an outline.
    func isProvisional(_ station: Station, _ room: Room) -> Bool {
        let key = roomKey(station, room)
        return !demo && room.worktree == nil && !room.key.hasPrefix("kind:") && crewRoomInfo[key] == nil && !pushedByPeer.contains(key)
    }

    /// Whose office this is, for the floor: the teammate GitHub names, else the peer who has it checked out.
    func occupant(of key: String) -> String? {
        if let info = crewRoomInfo[key] { return crewName(info.author) }
        if let peer = peerOffices[key]?.keys.sorted().first { return peer }
        let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
        if parts.count == 2, let room = fleet.stations[parts[0]]?.rooms[parts[1]], room.worktree != nil, room.key.hasPrefix("task:") {
            return github.myLogin().map(crewName) ?? "me"
        }
        return nil
    }

    /// Peers that have gone quiet.
    func stalePeers(olderThan seconds: TimeInterval) -> [String] {
        peerSnapshots.filter { Date().timeIntervalSince($0.value.at) > seconds }.map(\.key)
    }

    // MARK: kicking

    /// Offices thrown off the station, by room key: peers and GitHub may not put them back for a day.
    private var simKicked: [String: Date] = [:]
    private var kicked: [String: Date] {
        get { simulated ? simKicked : (UserDefaults.standard.dictionary(forKey: "kicked") as? [String: Date]) ?? [:] }
        set {
            let live = newValue.filter { Date().timeIntervalSince($0.value) < World.holdWindow }
            if simulated { simKicked = live } else { UserDefaults.standard.set(live, forKey: "kicked") }
        }
    }

    func isKicked(_ key: String) -> Bool { kicked[key].map { Date().timeIntervalSince($0) < World.holdWindow } ?? false }

    /// Throws an office off the station: nobody may put it back for a day.
    func kick(roomKey key: String) -> [WorldEvent] {
        let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2, let station = fleet.stations[parts[0]], let room = station.rooms[parts[1]] else { return [] }
        var k = kicked; k[key] = Date(); kicked = k
        crewRoomInfo[key] = nil; crewBoxes[key] = nil; peerOffices[key] = nil; peerBoxes[key] = nil; pushedByPeer.remove(key)
        var events: [WorldEvent] = [drop(station: station, room: room, announce: false, reason: "kicked")]
        events.append(.log("kicked \(room.name) off the station"))
        events.append(.layoutChanged)
        return events
    }

    /// Takes a room off the floor and describes it for the scene, which still has to tear its tiles down.
    private func drop(station: Station, room: Room, announce: Bool, reason: String) -> WorldEvent {
        let event = WorldEvent.officeArchived(station: station.name, key: roomKey(station, room), roomKey: room.key,
                                              name: room.name, hall: station.doorOutside(of: room.key), announce: announce, reason: reason)
        station.removeRoom(key: room.key)
        return event
    }

    // MARK: the session scan

    /// What the scene knows about where a session's worker stands, so a renamed office keeps its floor.
    struct MinionHome { var station: String; var key: String; var idle: Bool }

    /// The last prompt marker and count seen per session: a session's first answer is quiet here too.
    private var sessionPrompts: [String: (marker: String, count: Int)] = [:]

    /// Every session touched today keeps its office alive; archived worktrees lose theirs.
    func applyScan(_ result: ScanResult, now: Date, minionHomes: [String: MinionHome]) -> [WorldEvent] {
        var events: [WorldEvent] = []
        var changed = false
        let firstRun = !didLoadLayout
        if firstRun {
            didLoadLayout = true
            fleet.load()
            changed = true
            events.append(.worldLoaded)
        }

        let cfg = ConfigStore.shared.current
        for s in result.sessions where s.cwdExists && Fleet.stationName(for: s.cwd, owner: s.owner, repo: s.repo) != "hidden"
            && (Fleet.stationName(for: s.cwd, owner: s.owner, repo: s.repo) == "work" || now.timeIntervalSince(s.lastModified) < World.roomsWindow) {
            let stationName = Fleet.stationName(for: s.cwd, owner: s.owner, repo: s.repo)
            let station = fleet.station(stationName)
            let home = homeFor(s, station: stationName)
            if let m = minionHomes[s.id], m.key != home.key, station.rooms[home.key] == nil, station.rooms[m.key] != nil,
               !minionHomes.contains(where: { $0.key != s.id && $0.value.key == m.key && $0.value.station == stationName }) {
                let promoted = m.key.hasPrefix("proj:") && home.key.hasPrefix("task:")
                station.renameRoom(from: m.key, to: home.key, name: home.name)
                events.append(.officeRenamed(station: stationName, from: m.key, to: home.key, name: home.name, session: s.id,
                                             promoted: promoted && !firstRun && m.idle))
                changed = true
            }
            if let r = station.rooms[home.key], r.worktree == nil, r.name != home.name { r.name = home.name; changed = true }
            if station.ensureRoom(key: home.key, name: home.name, repo: home.repo, color: fleet.color(forRepo: home.repo), lastActive: s.lastModified) {
                changed = true
                roomCreated["\(stationName)|\(home.key)"] = now
                events.append(.officeOpened(station: stationName, key: home.key, source: .session(s.id), arrival: firstRun ? .appear : .shuttle))
            }
            if let root = s.repoRoot, !repoRoots.values.contains(where: { $0.repo == s.repo }) {
                repoRoots[root] = (s.repo, stationName)
            }
            // A message arrived since the last scan: cones on the office floor, and its worker over to them.
            let marker = s.eventMarkers[.prompt] ?? ""
            if let seen = sessionPrompts[s.id], seen.marker != marker, !firstRun, !s.isSubagent {
                events.append(.prompt(station: stationName, key: home.key, minionId: s.id,
                                      count: max(1, s.promptCount - seen.count)))
            }
            sessionPrompts[s.id] = (marker, s.promptCount)
            if let room = station.rooms[home.key], !home.key.hasPrefix("kind:") {
                room.worktree = s.cwd
                if home.key.hasPrefix("task:") { room.branch = s.branch; room.repoRoot = s.repoRoot }
                if let b = room.branch, let r = room.repoRoot { github.refresh(branch: b, repoRoot: r) }
                if let w = room.worktree { github.refreshCommits(worktree: w) }
            }
        }
        for station in fleet.stations.values {
            for room in Array(station.rooms.values) where !room.key.hasPrefix("kind:") {
                let key = roomKey(station, room)
                let gone = room.worktree.map { !FileManager.default.fileExists(atPath: $0) } ?? false
                let state = room.branch.flatMap { b in room.repoRoot.flatMap { github.pull(branch: b, repoRoot: $0) } }?.state
                let merged = state == "MERGED"
                // Closed without merging: the work goes nowhere. The crate turns red, sits for ten minutes, then the office clears.
                let closed = state == "CLOSED"
                if closed, closedAt[key] == nil { closedAt[key] = now; events.append(.log("\(room.name): pull request closed, not merged")) }
                if !closed { closedAt[key] = nil }
                if merged, station.hasPad, hauledAt[key] == nil { events += haulMerged(station: station, room: room) }
                let cleared = (merged && (!station.hasPad || (hauledAt[key].map { now.timeIntervalSince($0) > 60 } ?? false && !haulInFlight(key))))
                    || (closed && now.timeIntervalSince(closedAt[key] ?? now) > World.closedWindow)
                // Nobody's: no checkout here, no peer claiming it, nothing on GitHub once GitHub has answered.
                // An office a peer left behind is held for a day so their return does not move it.
                let unclaimed = room.worktree == nil && crewRoomInfo[key] == nil && peerOffices[key] == nil && isReady(room.repo)
                    && (cfg.project == nil || github.projectItems() != nil)
                let orphan = unclaimed && (held[key].map { now.timeIntervalSince($0) > World.holdWindow } ?? true)
                if gone || cleared || orphan {
                    if cleared { retired[key] = now }
                    events.append(drop(station: station, room: room, announce: !firstRun,
                                       reason: gone ? "worktree gone" : closed ? "closed, not merged" : cleared ? "merged and hauled" : "nobody's"))
                    changed = true
                }
            }
        }

        // Every Conductor repo with a checkout under ~/dev counts as a work repo for releases,
        // even with no session today, so a release on the pad never depends on someone working.
        if firstRun, !simulated {
            let home = FileManager.default.homeDirectoryForCurrentUser
            let workspaces = home.appendingPathComponent("conductor/workspaces")
            if let repos = try? FileManager.default.contentsOfDirectory(atPath: workspaces.path) {
                for repo in repos {
                    let root = home.appendingPathComponent("dev/\(repo)").path
                    if FileManager.default.fileExists(atPath: root + "/.git"), !repoRoots.values.contains(where: { $0.repo == repo }) {
                        repoRoots[root] = (repo, "work")
                        _ = fleet.color(forRepo: repo)
                    }
                }
            }
        }
        github.intervalMinutes = cfg.githubMinutes
        if let p = cfg.project { github.refreshProject(owner: p.owner, number: p.number) }
        for (root, info) in repoRoots {
            github.refreshReleases(repoRoot: root)
            if info.station == "work" { github.refreshFeed(repoRoot: root); github.refreshOpenPRs(repoRoot: root) }
        }
        events += applyBoardMoves()
        for change in github.takeStateChanges() {
            let who = change.branch.firstMatch(of: #/^gh-(\d+)\//#).map { "#\($0.1)" } ?? change.branch
            events.append(.log("\(who): \(change.pr.summary)"))
            events.append(.chime(change.pr.number))
        }
        // Merged offices are hauled from the scan loop above; a second pass here would announce them twice.
        if changed { events.append(.layoutChanged) }
        return events
    }

    /// A session's office, unless that office was merged and cleared while the session lingers on the
    /// branch: then the minion waits in the lounge rather than rebuilding the office every scan.
    func homeFor(_ s: SessionInfo, station: String) -> Home {
        let home = Home.from(repo: s.repo, branch: s.branch, cwd: s.cwd)
        if let at = retired["\(station)|\(home.key)"], Date().timeIntervalSince(at) < World.holdWindow {
            return Home(key: "kind:lounge", name: home.name, repo: home.repo, issue: nil)
        }
        return home
    }

    // MARK: github

    /// A fresh answer from GitHub: board columns that moved, and the crew's floor rebuilt around it.
    func applyGitHub(now: Date) -> [WorldEvent] {
        var events = applyReleases()
        events += applyBoardMoves()
        events += rebuildCrew(now: now)
        return events
    }

    // MARK: releases and the pad

    /// Releases already announced, so an open one on the pad is only said once: "station|repo|number|untested".
    private var announcedReleases: Set<String> = []

    /// The staging release each repository is known to have, by "station|repo": its number and state.
    private var stagingPRs: [String: (number: Int, state: String)] = [:]
    /// Repositories whose releases have answered once. The first answer is quiet: whatever it holds already existed.
    private var stagingSeen: Set<String> = []

    /// Whether the deck, rather than storage, is what a rocket loads from.
    private var stagingIsDeck: Bool { !ConfigStore.shared.current.stagingBranch.isEmpty }

    /// The release pull request whose rocket a repository's pad should hold, if any.
    private func padRelease(root: String) -> ReleasePR? {
        guard let open = github.openReleases(repoRoot: root) else { return nil }
        let hasProduction = open.contains(where: \.isProduction)
        return open.first { $0.isProduction || (!hasProduction && !stagingIsDeck) }
    }

    /// Pads that should hold a rocket right now, as "station|repo".
    func padRockets() -> Set<String> {
        Set(repoRoots.compactMap { root, info in padRelease(root: root) != nil ? info.station + "|" + info.repo : nil })
    }

    /// One rocket command, with what to write on the prop and how much cargo it should be sized for.
    private func wish(_ stage: Command.RocketStage, station: Station, repo: String, pr: ReleasePR) -> WorldEvent {
        let status = pr.untested ? " · untested, holding on the pad" : " · cleared for launch"
        let label = "rocket:\(pr.url)|\(repo) · \(pr.head) → \(pr.base) · #\(pr.number) \(pr.title)\(status)"
        return .rocketCommand(station: station.name, repo: repo, label: label, untested: pr.untested,
                              tall: pr.isProduction, cargo: cargoWaiting(station: station, repo: repo),
                              command: .rocket(stage, station: station.name, repo: repo))
    }

    /// Crates a rocket would load: the deck when there is a staging branch, storage otherwise.
    func cargoWaiting(station: Station, repo: String) -> Int {
        (stagingIsDeck ? station.staged : station.stored)[repo] ?? 0
    }

    /// The launch queue and the open releases, turned into events and rocket commands. A merged
    /// production release launches; an open one stands by while untested and loads once it is cleared.
    func applyReleases() -> [WorldEvent] {
        var events: [WorldEvent] = []
        var launched: Set<String> = []
        for launch in github.takeLaunches() {
            guard let info = repoRoots[launch.repoRoot], let station = fleet.stations[info.station] else { continue }
            let pr = launch.pr
            events.append(.releaseMerged(station: info.station, repo: info.repo, number: pr.number, base: pr.base,
                                         title: pr.title, isProduction: pr.isProduction))
            events.append(.chime(pr.number))
            guard pr.isProduction else { continue }
            launched.insert(info.station + "|" + info.repo)
            announcedReleases = announcedReleases.filter { !$0.hasPrefix("\(info.station)|\(info.repo)|") }
            events.append(.log("\(info.repo) launched to \(pr.base): \(pr.title)"))
            events.append(wish(.launch, station: station, repo: info.repo, pr: pr))
        }
        for (root, info) in repoRoots {
            guard let station = fleet.stations[info.station], let pr = padRelease(root: root) else { continue }
            let key = info.station + "|" + info.repo
            guard !launched.contains(key) else { continue }
            let mark = "\(key)|\(pr.number)|\(pr.untested)"
            if !announcedReleases.contains(mark) {
                announcedReleases.insert(mark)
                events.append(.releaseOpened(station: info.station, repo: info.repo, number: pr.number, base: pr.base,
                                             untested: pr.untested, isProduction: pr.isProduction))
                events.append(.log("\(info.repo): release to \(pr.base) on the pad" + (pr.untested ? " (untested)" : "")))
            }
            // Untested, or not for production: the rocket only stands there. Cleared: it takes the cargo aboard.
            let cleared = pr.isProduction && !pr.untested
            events.append(wish(cleared ? .load(cargoWaiting(station: station, repo: info.repo)) : .standBy,
                               station: station, repo: info.repo, pr: pr))
        }
        return events + applyStaging()
    }

    /// The staging release of each repository, diffed against the last answer: opened, merged, or
    /// closed without merging. One open staging release per repository at a time, which is what the
    /// one pallet per station is for.
    private func applyStaging() -> [WorldEvent] {
        guard !ConfigStore.shared.current.stagingBranch.isEmpty else { return [] }
        var events: [WorldEvent] = []
        for (root, info) in repoRoots.sorted(by: { $0.key < $1.key }) {
            guard fleet.stations[info.station] != nil, let all = github.releases(repoRoot: root) else { continue }
            let key = info.station + "|" + info.repo
            let staging = all.filter(\.isStaging)
            let open = staging.first { $0.state == "OPEN" }
            guard stagingSeen.contains(key) else {
                stagingSeen.insert(key)
                if let open { stagingPRs[key] = (open.number, "OPEN") }
                continue
            }
            if let open, stagingPRs[key]?.number != open.number {
                stagingPRs[key] = (open.number, "OPEN")
                events.append(.stagingOpened(station: info.station, repo: info.repo, number: open.number))
                continue
            }
            guard let known = stagingPRs[key], known.state == "OPEN",
                  let pr = staging.first(where: { $0.number == known.number }), pr.state != "OPEN" else { continue }
            stagingPRs[key] = (pr.number, pr.state)
            let merged = pr.state == "MERGED"
            events.append(merged ? .stagingMerged(station: info.station, repo: info.repo, number: pr.number)
                                 : .stagingClosed(station: info.station, repo: info.repo, number: pr.number))
        }
        return events
    }

    /// Status moves on the board are the station's cues: a crate to the deck, a tick from QA, a launch.
    private func applyBoardMoves() -> [WorldEvent] {
        let st = ConfigStore.shared.current.statuses
        return github.takeProjectMoves().map { .boardMoved(item: $0.item, from: $0.from, to: st.stage(of: $0.item.status)) }
    }

    /// Crew station: an office per open teammate pull request, boxes per push, and minions that
    /// react only to what just happened in the repositories' activity feeds.
    private func rebuildCrew(now: Date) -> [WorldEvent] {
        var events: [WorldEvent] = []
        let me = github.myLogin() ?? ""
        let cfg = ConfigStore.shared.current
        let station = fleet.station("work")
        let sk = station.name + "|"
        guard cfg.showCrew else {
            guard !crewRoomInfo.isEmpty else { return [.crewHidden] }
            events.append(.crewHidden)
            for room in Array(station.rooms.values) where isRemoteOnly(station, room) {
                events.append(drop(station: station, room: room, announce: false, reason: "crew hidden"))
            }
            crewRoomInfo = [:]; crewBoxes = [:]
            events.append(.layoutChanged)
            return events
        }
        var changed = false
        var open: [(repo: String, pr: OpenPR)] = []
        var feed: [(repo: String, e: FeedEvent)] = []
        for (root, info) in repoRoots where info.station == "work" && cfg.crewEnabled(repo: info.repo) {
            for pr in github.teamOpenPRs(repoRoot: root) ?? [] where pr.author != me && !World.trunkBranches.contains(pr.branch) { open.append((info.repo, pr)) }
            for e in github.feed(repoRoot: root) ?? [] where e.actor != me { feed.append((info.repo, e)) }
        }
        // Issues the board says are in development, assigned to someone else: offices too, even before a pull request.
        var boardOffices: [(repo: String, item: ProjectItem, login: String)] = []
        if cfg.project != nil, !me.isEmpty, let items = github.projectItems() {   // not before GitHub has said who I am
            let workRepos = Set(repoRoots.values.filter { $0.station == "work" && cfg.crewEnabled(repo: $0.repo) }.map(\.repo))
            // The column says an office is solid; it does not make one. An issue needs a sign of work:
            // a linked pull request, a branch seen in the feed, or a room a session or peer already claims.
            var branched: Set<String> = []   // "repo#N" with a gh-N/… branch pushed in the last two weeks
            let recent = now.addingTimeInterval(-14 * 24 * 3600)
            for (repo, e) in feed where e.at > recent { if let b = e.branch, let m = b.firstMatch(of: #/^gh-(\d+)\//#) { branched.insert("\(repo)#\(m.1)") } }
            for it in items where it.status == cfg.statuses.development && workRepos.contains(it.repo) {
                let key = "task:\(it.repo)#\(it.number)"
                guard let login = it.assignees.first, login != me else { continue }
                if open.contains(where: { $0.repo == it.repo && crewKey(repo: $0.repo, branch: $0.pr.branch) == key }) { continue }
                let working = !it.prURLs.isEmpty || branched.contains("\(it.repo)#\(it.number)") || peerOffices[sk + key] != nil || station.rooms[key]?.worktree != nil
                guard working else { continue }
                boardOffices.append((it.repo, it, login))
            }
        }
        guard !open.isEmpty || !feed.isEmpty || !boardOffices.isEmpty else { return events }

        // Offices for open pull requests; a new one arrives by shuttle, a gone one is archived.
        var liveKeys = Set(open.filter { !$0.pr.isBot }.map { crewKey(repo: $0.repo, branch: $0.pr.branch) })
        liveKeys.formUnion(boardOffices.map { "task:\($0.repo)#\($0.item.number)" })
        for room in Array(station.rooms.values) where crewRoomInfo[sk + room.key] != nil && !liveKeys.contains(room.key) {
            let key = sk + room.key
            let author = crewRoomInfo[key]?.author ?? ""
            // A teammate's office that we also have checked out stays: the local scan decides its fate.
            guard room.worktree == nil else { crewRoomInfo[key] = nil; crewBoxes[key] = nil; continue }
            // Its crate goes to storage on someone's arms first; the office clears once that is done.
            var hauling = false
            let branch = crewRoomInfo[key]?.branch ?? ""
            let closedUnmerged = feed.contains { $0.repo == room.repo && $0.e.kind == "pr_close" && $0.e.branch == branch }
            if closedUnmerged {
                // Closed without merging: red for ten minutes, then gone. Nothing to carry.
                if closedAt[key] == nil { closedAt[key] = now; events.append(.log("\(room.name): pull request closed, not merged")) }
                if now.timeIntervalSince(closedAt[key] ?? now) < World.closedWindow { continue }
            } else if hauledAt[key] == nil, station.hasPad {
                let merged = haulMerged(station: station, room: room)
                hauling = !merged.isEmpty   // the scene is about to start carrying: the office waits for it
                events += merged
                if isReady(room.repo) { events.append(.pullRequestClosed(repo: room.repo ?? "", author: author, roomKey: room.key)) }
            }
            guard !station.hasPad || !(hauling || haulInFlight(key)) else { continue }
            closedAt[key] = nil
            crewRoomInfo[key] = nil; crewBoxes[key] = nil
            events.append(drop(station: station, room: room, announce: isReady(room.repo), reason: "pull request closed"))
            changed = true
        }
        for (repo, pr) in open where !pr.isBot && !isKicked(sk + Home.from(repo: repo, branch: pr.branch, cwd: "").key) {
            let home = Home.from(repo: repo, branch: pr.branch, cwd: "")
            let key = home.key
            let name = home.name
            if let r = station.rooms[key], r.worktree == nil, r.name != name { r.name = name; changed = true }
            if station.ensureRoom(key: key, name: name, repo: repo, color: fleet.color(forRepo: repo), lastActive: now) {
                changed = true
                if isReady(repo) {
                    events.append(.officeOpened(station: station.name, key: key, source: .github(pr.author), arrival: .shuttle))
                    events.append(.pullRequestOpened(repo: repo, number: pr.number, author: pr.author, roomKey: key))
                }
            }
            crewRoomInfo[sk + key] = CrewRoomInfo(repo: repo, branch: pr.branch, prNumber: pr.number, title: pr.title, author: pr.author, url: pr.url, state: "OPEN", last: pr.createdAt)
            let pushes = feed.filter { $0.repo == repo && $0.e.kind == "push" && $0.e.branch == pr.branch && $0.e.at > pr.createdAt }.map { Int($0.e.detail) ?? 1 }.reduce(0, +)
            crewBoxes[sk + key] = (1 + pushes, "OPEN", fleet.color(forRepo: repo))
        }
        for (repo, it, login) in boardOffices where !isKicked(sk + "task:\(repo)#\(it.number)") {
            let key = "task:\(repo)#\(it.number)"
            let name = "#\(it.number) " + String(it.title.prefix(22))
            if let r = station.rooms[key], r.worktree == nil, r.name != name { r.name = name; changed = true }
            if station.ensureRoom(key: key, name: name, repo: repo, color: fleet.color(forRepo: repo), lastActive: now) {
                changed = true
                if isReady(repo) {
                    events.append(.officeOpened(station: station.name, key: key, source: .board(login), arrival: .shuttle))
                    events.append(.issueStarted(repo: repo, number: it.number, author: login, roomKey: key))
                }
            }
            let prNumber = it.prURLs.first.flatMap { Int($0.split(separator: "/").last ?? "") }
            crewRoomInfo[sk + key] = CrewRoomInfo(repo: repo, branch: "gh-\(it.number)", prNumber: prNumber, title: it.title, author: login, url: it.url, state: "OPEN", last: now)
            crewBoxes[sk + key] = (1, "NONE", fleet.color(forRepo: repo))
        }
        let botCount = open.filter(\.pr.isBot).count
        if botCount > 0 {
            if station.ensureRoom(key: "kind:bots", name: "bots", repo: nil, color: RGB(r: 0.36, g: 0.40, b: 0.50), lastActive: .distantFuture, shape: Station.rect(2, 2)) { changed = true }
            crewBoxes[sk + "kind:bots"] = (botCount, "NONE", RGB(r: 0.55, g: 0.6, b: 0.7))
        }

        // One grey minion per teammate with an open PR or recent activity.
        var logins = Set(open.filter { !$0.pr.isBot }.map(\.pr.author))
        logins.formUnion(boardOffices.map(\.login))
        logins.formUnion(feed.filter { !$0.e.isBot && now.timeIntervalSince($0.e.at) < 2 * 3600 }.map(\.e.actor))
        seenLogins.formUnion(feed.filter { !$0.e.isBot }.map(\.e.actor)); seenLogins.formUnion(logins)
        var roster: [String: CrewMember] = [:]
        for login in logins {
            let homeKey = open.first { $0.pr.author == login }.map { crewKey(repo: $0.repo, branch: $0.pr.branch) } ?? "kind:quarters"
            roster[login] = CrewMember(homeKey: homeKey, repo: open.first { $0.pr.author == login }?.repo ?? "crew")
        }
        events.append(.crewRoster(members: roster, bots: botCount))
        events.append(changed ? .layoutChanged : .markersChanged)

        // What just happened: only fresh events move minions and make the log.
        for (repo, e) in feed.sorted(by: { $0.e.at < $1.e.at }) where !e.isBot {
            let id = "\(repo)|\(e.at.timeIntervalSince1970)|\(e.actor)|\(e.kind)|\(e.branch ?? "")"
            guard !crewSeen.contains(id) else { continue }
            crewSeen.insert(id)
            guard now.timeIntervalSince(e.at) < World.crewRecent else { continue }
            let roomKey = e.branch.map { crewKey(repo: repo, branch: $0) } ?? ""
            events.append(.crewActivity(CrewActivity(login: e.actor, kind: e.kind, repo: repo, roomKey: roomKey,
                                                     hasRoom: station.rooms[roomKey] != nil,
                                                     label: e.prNumber.map { "#\($0)" } ?? (e.branch ?? ""),
                                                     detail: e.detail, branch: e.branch, title: e.title, ready: isReady(repo))))
        }
        // Each repository counts as answered from its first reply on; the reply itself was taken quietly above.
        for (root, info) in repoRoots where info.station == "work" && github.teamOpenPRs(repoRoot: root) != nil { readyRepos.insert(info.repo) }
        return events
    }

    // MARK: peers

    /// A peer's claim lands on our work station: its offices get the same key here, adopting the
    /// peer's floor plan when that floor is free. A whole peer arriving fades in; one new checkout
    /// on a peer we already follow earns a shuttle, like a new session of our own.
    func applyPeer(_ snap: PeerSnapshot, now: Date) -> [WorldEvent] {
        var events: [WorldEvent] = []
        let isNewPeer = peerFirstSeen[snap.name] == nil
        if isNewPeer { peerFirstSeen[snap.name] = now; events.append(.peerArrived(snap.name)) }
        let bulk = isNewPeer || now.timeIntervalSince(peerFirstSeen[snap.name]!) < 15
        peerSnapshots[snap.name] = (snap, now)
        let station = fleet.station("work")
        let sk = station.name + "|"
        var changed = false
        let cfg = ConfigStore.shared.current
        let mine = Set(peerOffices.filter { $0.value[snap.name] != nil }.map(\.key))
        var live: Set<String> = []
        for o in snap.offices where cfg.repos[o.repo]?.station != "hidden" && !isKicked(sk + o.key) {
            let key = sk + o.key
            live.insert(key)
            peerOffices[key, default: [:]][snap.name] = o
            if o.pushed { pushedByPeer.insert(key) }
            if o.boxes > 0 { peerBoxes[key] = (o.boxes, "NONE", o.color) } else { peerBoxes[key] = nil }
            if let r = station.rooms[o.key] {
                r.lastActive = max(r.lastActive, o.lastActive, now)
                if r.worktree == nil, crewRoomInfo[key] == nil, r.name != o.name { r.name = o.name; changed = true }
                continue
            }
            let color = fleet.color(forRepo: o.repo)
            guard station.ensureRoom(key: o.key, name: o.name, repo: o.repo, color: color, lastActive: now, preferredCells: o.cells) else { continue }
            changed = true
            if !bulk, now.timeIntervalSince(o.startedAt) < 3 * 60 {
                events.append(.officeOpened(station: station.name, key: o.key, source: .peer(snap.name), arrival: .shuttle))
                events.append(.log("\(snap.name) started \(o.name)"))
            } else {
                events.append(.officeOpened(station: station.name, key: o.key, source: .peer(snap.name), arrival: .fade))
            }
        }
        for key in mine where !live.contains(key) {
            peerOffices[key]?[snap.name] = nil
            if peerOffices[key]?.isEmpty == true { peerOffices[key] = nil; peerBoxes[key] = nil }
        }
        if changed { events.append(.layoutChanged) }
        else if !snap.offices.isEmpty { events.append(.markersChanged) }

        // Their GitHub answers for repositories we also watch save us a poll; same for the board.
        if let b = snap.project, let p = cfg.project, b.owner == p.owner, b.number == p.number {
            github.adoptProject(b.items, at: b.at)
            events += applyBoardMoves()
        }
        for k in snap.github ?? [] where cfg.shared(repo: k.repo) {
            for (root, info) in repoRoots where info.repo == k.repo && info.station == "work" { github.adopt(k, repoRoot: root) }
        }
        return events
    }

    /// A peer has gone quiet: its figures leave, its offices stay held until their hold runs out.
    func dropPeer(_ name: String) -> [WorldEvent] {
        peerSnapshots[name] = nil; peerFirstSeen[name] = nil
        for (key, claims) in peerOffices where claims[name] != nil {
            peerOffices[key]?[name] = nil
            if peerOffices[key]?.isEmpty == true { peerOffices[key] = nil; peerBoxes[key] = nil; held[key] = Date() }
        }
        return [.peerLeft(name), .markersChanged]
    }

    // MARK: the yard

    /// One crate's place in a yard: which repository's, its number, where it stands and which way it turns.
    /// `column` names the stack it belongs to — one square of floor, one half of a cell — and `level`
    /// how high in that stack it sits, counted from the floor. Only the top of a column can be picked.
    struct YardSlot {
        let repo: String; let number: Int; let index: Int; let cleared: Bool
        let group: Int; let column: Int; let level: Int
        let cell: Cell; let pos: SIMD3<Double>; let yaw: Double
    }

    /// What the yard reconciliation decided for one repository.
    enum YardChange {
        /// Crates the board says reached staging: one carry each, from storage across to the deck.
        case carryToDeck([Command])
        /// Nothing to carry: the counts were redrawn where they stand.
        case snapped
        /// Not now: carriers are still on their way.
        case waiting
    }

    /// Where every crate stands in storage or on the deck, from the counts alone, so a carrier can be
    /// sent to the exact spot a crate will occupy and nothing jumps when the layout is redrawn.
    /// Every other row holds crates with aisles between; the deck keeps tested crates on the row nearest
    /// the pad and untested on the far row; within a row, crates group by repository in stacks of three.
    /// `extra` adds one more crate of a repository, as it will be once a haul in flight has landed.
    /// `stillUntested` keeps one deck crate in the untested row even though the board has cleared it:
    /// that is where it still stands, and a carry to the tested row has to start from there.
    func yardLayout(station: Station, area: String, extra: (repo: String, number: Int)? = nil,
                    stillUntested: Int? = nil) -> [YardSlot] {
        let cells = area == "deck" ? station.deckCells : station.storageCells
        let neat = area == "deck"
        var piles = area == "deck" ? station.staged : station.stored
        if let extra { piles[extra.repo, default: 0] += 1 }
        guard !cells.isEmpty else { return [] }
        let rows = Set(cells.map(\.y)).sorted()
        let crateRows = Set(rows.enumerated().filter { $0.offset % 2 == 0 }.map(\.element))
        let sorted = cells.filter { crateRows.contains($0.y) }.sorted { ($0.y, $0.x) < ($1.y, $1.x) }
        let rowList = crateRows.sorted()
        let testedRow = sorted.filter { $0.y == rowList.first }, untestedRow = sorted.filter { $0.y == rowList.last }
        func row(_ group: Int) -> [Cell] { area == "deck" && rowList.count > 1 ? (group == 0 ? testedRow : untestedRow) : sorted }
        let cargoByRepo = Dictionary(repoRoots.filter { $0.value.station == station.name }.compactMap { (root, info) -> (String, GitHubResolver.Cargo)? in
            github.cargo(repoRoot: root).map { (info.repo, $0) } }, uniquingKeysWith: { a, _ in a })

        // Every crate keeps the slot it was given until it leaves: a column of its repository's, and a rank
        // in that column. Ranks re-settle when a crate below is taken out, so a stack never floats. New
        // crates take the lowest free rank in the repository's columns, or the lowest free column.
        let yardKey = "\(station.name)|\(area)"
        var slots = yardSlots[yardKey] ?? [:]
        var present: Set<String> = []
        var out: [YardSlot] = []
        func owner(group: Int, column: Int) -> String? {
            slots.first { $0.key.hasPrefix("\(group)|") && $0.value.column == column }?.key.split(separator: "|")[1].split(separator: "#").first.map(String.init)
        }
        for (repo, n) in piles.sorted(by: { $0.key < $1.key }) where n > 0 {
            var numbers = area == "deck" ? (cargoByRepo[repo]?.deckNumbers ?? []) : (cargoByRepo[repo]?.storageNumbers ?? [])
            if area == "storage" { numbers += truth.freshLanded(station: station.name, repo: repo, counted: numbers).filter { !numbers.contains($0) } }
            // A crate on the pallet stands on the pallet: the rows are not to draw it again.
            numbers = numbers.filter { !truth.isOnPallet(station: station.name, repo: repo, number: $0) }
            if let extra, extra.repo == repo, !numbers.contains(extra.number) { numbers.append(extra.number) }
            for k in 0..<min(n, 48) {
                let number = k < numbers.count ? numbers[k] : 0
                var cleared = area == "deck" && (cargoByRepo[repo]?.clearedNumbers.contains(number) ?? false)
                if cleared, number != 0, number == stillUntested { cleared = false }
                let group = (area == "deck" && rowList.count > 1) ? (cleared ? 0 : 1) : 0
                let key = "\(group)|\(repo)#\(number > 0 ? "\(number)" : "i\(k)")"
                present.insert(key)
                if slots[key] == nil {
                    let cap = row(group).count * 2
                    let mine = Set(slots.filter { $0.key.hasPrefix("\(group)|\(repo)#") }.map { $0.value.column }).sorted()
                    var chosen: (column: Int, order: Int)?
                    for column in mine {   // the repository's own columns first, lowest free rank
                        let filled = slots.filter { $0.key.hasPrefix("\(group)|") && $0.value.column == column }.count
                        if filled < 3 { chosen = (column, filled); break }
                    }
                    if chosen == nil {   // a fresh column, the lowest one nobody holds
                        if let free = (0..<cap).first(where: { owner(group: group, column: $0) == nil }) { chosen = (free, 0) }
                        else if let column = mine.first { chosen = (column, slots.filter { $0.key.hasPrefix("\(group)|") && $0.value.column == column }.count) }
                        else { chosen = (0, 0) }
                    }
                    slots[key] = (column: chosen!.column, order: chosen!.order)
                }
                out.append(YardSlot(repo: repo, number: number, index: k, cleared: cleared, group: group,
                                    column: slots[key]!.column, level: 0, cell: row(group)[slots[key]!.column / 2], pos: .zero, yaw: 0))
            }
        }
        for key in slots.keys where !present.contains(key) { slots[key] = nil }   // gone: the slot is free again
        // Levels: rank within the column by the order each crate was given, so a stack settles from the floor.
        var ranked: [YardSlot] = []
        for slot in out {
            let key = "\(slot.group)|\(slot.repo)#\(slot.number > 0 ? "\(slot.number)" : "i\(slot.index)")"
            let mine = slots[key]!
            let level = slots.filter { $0.key.hasPrefix("\(slot.group)|") && $0.value.column == mine.column && $0.value.order < mine.order }.count
            let cellsOfRow = row(slot.group)
            let cell = cellsOfRow[mine.column / 2], side = Double(mine.column % 2) * 0.5 - 0.25
            let (jx, jz, yaw) = neat ? (0, 0, 0) : World.jitter(repo: slot.repo, number: slot.number, index: slot.index)
            let pos = SIMD3(station.offset.x + Double(cell.x) + side + jx, Double(level) * 0.34, station.offset.y + Double(cell.y) + jz)
            ranked.append(YardSlot(repo: slot.repo, number: slot.number, index: slot.index, cleared: slot.cleared, group: slot.group,
                                   column: mine.column, level: level, cell: cell, pos: pos, yaw: yaw))
        }
        yardSlots[yardKey] = slots
        return ranked
    }

    /// Each crate's slot in a yard, by "station|area" then "group|repo#number": its column and the order
    /// it was given, from which its level is ranked.
    private var yardSlots: [String: [String: (column: Int, order: Int)]] = [:]

    /// A little disorder in storage, seeded per crate so a crate keeps its own nudge and turn wherever
    /// it lands in the rows. Unnumbered crates fall back to their place in the pile.
    private static func jitter(repo: String, number: Int, index: Int) -> (Double, Double, Double) {
        var seed = UInt64(truncatingIfNeeded: (number > 0 ? "\(repo)#\(number)" : "\(repo)#i\(index)").hashValue) | 1
        func rnd() -> Double { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Double(seed >> 11) / Double(1 << 53) }
        return ((rnd() - 0.5) * 0.22, (rnd() - 0.5) * 0.3, (rnd() - 0.5) * 0.7)
    }

    /// Brings the yard in line with GitHub. Crates the board says went to staging are carried across
    /// from storage; counts snap only for what cannot be carried, and never for a deck that is about to
    /// be loaded into a rocket.
    @discardableResult
    func reconcile(station: Station, repo: String, root: String, cargo c: GitHubResolver.Cargo) -> YardChange {
        let k = station.name + "|" + repo
        guard truth.inFlightToDeck(k) == 0 else { return .waiting }   // let the carriers land first
        // The pallet is the hand carry for this repository from the moment one is ordered: nothing
        // else moves its crates until it has been emptied.
        guard truth.pallets[station.name]?.repo != repo,
              truth.palletQueue[station.name]?.contains(where: { $0.repo == repo }) != true else { return .waiting }
        let shownStorage = station.stored[repo] ?? 0, shownDeck = station.staged[repo] ?? 0
        let fresh = truth.freshLanded(station: station.name, repo: repo, counted: c.storageNumbers)
        let toDeck = min(c.deck - shownDeck, shownStorage)
        if toDeck > 0, station.hasPad, !station.deckCells.isEmpty, !ConfigStore.shared.current.stagingBranch.isEmpty {
            let commands = carryToDeck(station: station, repo: repo, count: toDeck)
            if !commands.isEmpty { return .carryToDeck(commands) }
        }
        let launching = rocketBusy(k) || github.hasPendingLaunch(repoRoot: root) || (github.openReleases(repoRoot: root)?.contains(where: \.isProduction) ?? false)
        station.stored[repo] = c.storage + fresh.count
        if !(launching && c.deck < shownDeck) { station.staged[repo] = c.deck }
        return .snapped
    }

    // MARK: commands the reconciler issues

    /// Where crate `index` of a repository will stand on the deck once `index + 1` of them are staged.
    func deckSlot(station: Station, repo: String, index: Int, number: Int) -> Spot {
        let saved = station.staged
        station.staged[repo] = index + 1
        defer { station.staged = saved }
        let deck = yardLayout(station: station, area: "deck")
        // A numbered crate goes to its own slot; an unnumbered one to the slot of its place in the pile.
        if let s = deck.first(where: { $0.repo == repo && $0.number == number && number != 0 }) ?? deck.first(where: { $0.repo == repo && $0.index == index }) {
            return yardSpot(s.cleared ? .tested : .deck, station: station, repo: repo,
                            slot: grounded(s, in: deck, station: station.name))
        }
        let c = station.deckCells[index % max(1, station.deckCells.count)]
        return Spot(area: .deck, station: station.name, owner: repo, label: repo, cell: c,
                    pos: SIMD3(station.offset.x + Double(c.x), 0, station.offset.y + Double(c.y)))
    }

    /// Stacks are built from the ground up. If a landing slot has come out with air under it — a count
    /// that shifted, a crate already on someone's arms — the crate lands on the lowest free level of the
    /// same column instead.
    private func grounded(_ slot: YardSlot, in layout: [YardSlot], station: String) -> YardSlot {
        let column = layout.filter {
            $0.group == slot.group && $0.column == slot.column && $0.index != slot.index
                && !truth.isCarried(station: station, repo: $0.repo, number: $0.number)
        }
        let taken = Set(column.map(\.level))
        var level = slot.level
        while level > 0 && !taken.contains(level - 1) { level -= 1 }
        while taken.contains(level) { level += 1 }
        guard level != slot.level else { return slot }
        return YardSlot(repo: slot.repo, number: slot.number, index: slot.index, cleared: slot.cleared,
                        group: slot.group, column: slot.column, level: level, cell: slot.cell,
                        pos: SIMD3(slot.pos.x, Double(level) * 0.34, slot.pos.z), yaw: slot.yaw)
    }

    private func yardSpot(_ area: Spot.Area, station: Station, repo: String, slot: YardSlot) -> Spot {
        Spot(area: area, station: station.name, owner: repo, label: repo, cell: slot.cell, pos: slot.pos,
             level: slot.level, yaw: slot.yaw)
    }

    /// The floor of a yard cell, for when the layout has nothing to say.
    private func floorSpot(_ area: Spot.Area, station: Station, repo: String, cell: Cell) -> Spot {
        Spot(area: area, station: station.name, owner: repo, label: repo, cell: cell,
             pos: SIMD3(station.offset.x + Double(cell.x), 0, station.offset.y + Double(cell.y)))
    }

    /// Storage crates the board says reached staging: one carry each, from the slot a crate stands on
    /// to the slot the deck layout will give it. Interchangeable crates, so the top of a stack goes
    /// first and nothing is ever pulled out from under another crate.
    func carryToDeck(station: Station, repo: String, count: Int) -> [Command] {
        let stored = yardLayout(station: station, area: "storage").filter { $0.repo == repo }
            .sorted { ($0.level, $0.index) > ($1.level, $1.index) }
        let already = station.staged[repo] ?? 0
        var out: [Command] = []
        var above: [Int: Int] = [:]     // the carry that has to clear a column before the crate under it moves
        var landed: [String: Int] = [:] // and the one that has to land before anything is set on top of it
        for slot in stored {
            guard out.count < count else { break }
            let crate = CrateRef(station: station.name, repo: repo, number: slot.number)
            guard !truth.isCarried(crate) else { continue }
            let to = deckSlot(station: station, repo: repo, index: already + out.count, number: slot.number)
            let column = "\(Int((to.pos.x * 100).rounded()))|\(Int((to.pos.z * 100).rounded()))"
            var waits: [Int] = []
            if let clear = above[slot.column] { waits.append(clear) }
            if to.level > 0, let under = landed["\(column)|\(to.level - 1)"] { waits.append(under) }
            let command = Command.carry(crate, from: yardSpot(.storage, station: station, repo: repo, slot: slot), to: to, after: waits)
            above[slot.column] = command.id
            landed["\(column)|\(to.level)"] = command.id
            out.append(command)
        }
        return out
    }

    /// What a pallet takes: every crate of a repository standing in storage, top of each stack first,
    /// twelve at most. Anything already on someone's arms stays where it is.
    func palletCargo(station: Station, repo: String) -> [(crate: CrateRef, from: Spot)] {
        yardLayout(station: station, area: "storage").filter { $0.repo == repo }
            .sorted { ($0.level, $0.index) > ($1.level, $1.index) }
            .compactMap { slot in
                let crate = CrateRef(station: station.name, repo: repo, number: slot.number)
                guard !truth.isCarried(crate) else { return nil }
                return (crate, yardSpot(.storage, station: station, repo: repo, slot: slot))
            }
            .prefix(12).map { $0 }
    }

    /// Where a crate coming off the pallet lands in storage: the next free place on the repository's
    /// stacks, the same slot a merged office's package would be given.
    func storageSlot(station: Station, repo: String, number: Int) -> Spot {
        let layout = yardLayout(station: station, area: "storage", extra: (repo, number))
        guard let slot = layout.last(where: { $0.repo == repo && $0.number == number }) ?? layout.last(where: { $0.repo == repo }) else {
            return floorSpot(.storage, station: station, repo: repo, cell: station.storageCells.first ?? Cell(x: 0, y: 0))
        }
        return yardSpot(.storage, station: station, repo: repo, slot: grounded(slot, in: layout, station: station.name))
    }

    /// A merged office's package, from the office floor to the slot storage will give it: the next free
    /// place on the repository's stacks, top of the current one or a new one.
    func carryToStorage(station: Station, room: Room, repo: String, number: Int) -> Command {
        let layout = yardLayout(station: station, area: "storage", extra: (repo, number))
        let slot = layout.last { $0.repo == repo && $0.number == number } ?? layout.last { $0.repo == repo }
        let cell = slot?.cell ?? station.storageCells.first ?? Cell(x: 0, y: 0)
        let to = slot.map { yardSpot(.storage, station: station, repo: repo, slot: grounded($0, in: layout, station: station.name)) }
            ?? floorSpot(.storage, station: station, repo: repo, cell: cell)
        let door = station.doorCell(of: room.key) ?? room.cells.first ?? cell
        let from = Spot(area: .office, station: station.name, owner: room.key, label: room.name, cell: door,
                        pos: SIMD3(station.offset.x + Double(door.x), 0, station.offset.y + Double(door.y)))
        return .carry(CrateRef(station: station.name, repo: repo, number: number), from: from, to: to)
    }

    /// One crate passed QA: across the aisle to the tested row. A named crate, so whatever is stacked on
    /// top of it moves aside first, each to the slot the redraw will give it.
    func carryToTested(station: Station, repo: String, number: Int) -> [Command] {
        let crate = CrateRef(station: station.name, repo: repo, number: number)
        guard !truth.isCarried(crate) else { return [] }
        let standing = yardLayout(station: station, area: "deck", stillUntested: number)
        let settled = yardLayout(station: station, area: "deck")
        guard let here = standing.first(where: { $0.repo == repo && $0.number == number }) else {
            let cell = station.deckCells.first ?? Cell(x: 0, y: 0)
            return [.carry(crate, from: floorSpot(.deck, station: station, repo: repo, cell: cell),
                           to: floorSpot(.tested, station: station, repo: repo, cell: cell))]
        }
        var out: [Command] = []
        var previous: [Int] = []
        for above in standing.filter({ $0.group == here.group && $0.column == here.column && $0.level > here.level })
                             .sorted(by: { $0.level > $1.level }) {
            let other = CrateRef(station: station.name, repo: above.repo, number: above.number)
            guard !truth.isCarried(other),
                  let dest = settled.first(where: { $0.repo == above.repo && $0.number == above.number && $0.number != 0 }),
                  dest.pos != above.pos else { continue }
            let command = Command.carry(other, from: yardSpot(above.cleared ? .tested : .deck, station: station, repo: above.repo, slot: above),
                                        to: yardSpot(dest.cleared ? .tested : .deck, station: station, repo: above.repo, slot: dest),
                                        after: previous)
            previous = [command.id]
            out.append(command)
        }
        let landing = settled.first { $0.repo == repo && $0.number == number }
        let to = landing.map { yardSpot(.tested, station: station, repo: repo, slot: $0) }
            ?? floorSpot(.tested, station: station, repo: repo, cell: here.cell)
        out.append(.carry(crate, from: yardSpot(.deck, station: station, repo: repo, slot: here), to: to, after: previous))
        return out
    }

    /// Cleared to launch: every crate named goes from its row into the rocket on the pad, stacks taken
    /// from the top down.
    func carryToPad(station: Station, repo: String, from area: String, numbers: [Int]) -> [Command] {
        let cell = station.padCells.first ?? Cell(x: 0, y: 0)
        let pc = station.padCenter
        let to = Spot(area: .pad, station: station.name, owner: repo, label: repo, cell: cell,
                      pos: SIMD3(station.offset.x + pc.x, 0.6, station.offset.y + pc.y))
        let slots = yardLayout(station: station, area: area)
        let order = numbers.sorted { a, b in
            let sa = slots.first { $0.repo == repo && $0.number == a }, sb = slots.first { $0.repo == repo && $0.number == b }
            return (sa?.level ?? 0, a) > (sb?.level ?? 0, b)
        }
        var out: [Command] = []
        var above: [Int: Int] = [:]
        for number in order {
            let slot = slots.first { $0.repo == repo && $0.number == number }
            let from = slot.map { yardSpot(area == "deck" ? ($0.cleared ? .tested : .deck) : .storage, station: station, repo: repo, slot: $0) }
                ?? floorSpot(area == "deck" ? .deck : .storage, station: station, repo: repo, cell: cell)
            let key = (slot?.group ?? 0) * 1000 + (slot?.column ?? 0)
            let command = Command.carry(CrateRef(station: station.name, repo: repo, number: number), from: from, to: to,
                                        after: above[key].map { [$0] } ?? [])
            if slot != nil { above[key] = command.id }
            out.append(command)
        }
        return out
    }

    /// Merged: the office's package belongs in the storage bay. The office is free to clear from now on,
    /// whether or not there is anything on the floor to carry.
    private func haulMerged(station: Station, room: Room) -> [WorldEvent] {
        let key = roomKey(station, room)
        guard station.hasPad, !haulingRoom(key) else { return [] }
        hauledAt[key] = Date()   // even with nothing to carry, the office is now free to clear
        guard hasPackage(key) else { return [] }
        let repo = room.repo ?? "work"
        let number = room.branch.flatMap { b in room.repoRoot.flatMap { github.pull(branch: b, repoRoot: $0)?.number } } ?? crewRoomInfo[key]?.prNumber ?? 0
        return [.officeMerged(station: station.name, key: room.key, repo: repo, number: number)]
    }

    /// When an office's pull request was closed without merging, so its red crate can fade in time.
    private(set) var closedAt: [String: Date] = [:]
    static let closedWindow: TimeInterval = 10 * 60
    func isClosed(_ roomKey: String) -> Bool { closedAt[roomKey] != nil }

    /// The scene has taken a merged office's package off the floor.
    func hauled(roomKey key: String) { hauledAt[key] = Date() }

    /// A crate was set down in storage by hand: ours to keep until GitHub counts it.
    func landedInStorage(station: Station, repo: String, number: Int) {
        truth.landedByHand(CrateRef(station: station.name, repo: repo, number: number))
        station.stored[repo, default: 0] += 1
        fleet.save()
    }
}
