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


    // MARK: model state

    /// Every repository we know a checkout of: its root, its name and the station it belongs to.
    private(set) var repoRoots: [String: (repo: String, station: String)] = [:]

    /// A teammate's office, as GitHub describes it.
    /// An office that is GitHub's on this station, a teammate's pull request or a board issue, and what
    /// state it was last heard in. Whose it is, what it is called and its numbers are the record's.
    struct CrewRoomInfo { var state: String; var last: Date }
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

    /// What the props and plots are doing: the pallet, the offices ordered, the crates in the bay.
    /// Where each crate is lives on its ledger row, on the station.
    var truth = StationTruth()
    /// The crate each merged office's package became, by office key ("station|roomKey"), from the
    /// moment its haul was ordered. Whether it has left is read off the crate's row, never a flag.
    private(set) var officeCrates: [String: CrateRef] = [:]
    /// Every piece of work by every name it goes by; see `WorkBook`.
    let works = WorkBook()
    /// Stage changes heard since the last pass, waiting to become station events; see `stationEvents`.
    private var transitions: [(record: WorkBook.Record, t: Transition)] = []

    /// The office on the floor for a piece of work, under whichever key it stands.
    func office(for record: WorkBook.Record) -> (station: Station, room: Room)? {
        for station in fleet.stations.values {
            for key in record.officeKeys { if let room = station.rooms[key] { return (station, room) } }
        }
        return nil
    }

    /// The stage changes heard this pass, as what the station does about them. A change whose office is
    /// not on the floor yet waits for it. A change in a repository nobody has answered for yet is history,
    /// not news, and is taken quietly, as every source's first answer is.
    func stationEvents() -> [WorldEvent] {
        var events: [WorldEvent] = []
        var waiting: [(record: WorkBook.Record, t: Transition)] = []
        var launches: Set<String> = []
        var toDeck: [String: [Int]] = [:]
        for (record, t) in transitions {
            switch t.to {
            case .ready:
                guard let (station, room) = office(for: record) else { waiting.append((record, t)); continue }
                guard t.from != nil, isReady(record.repo) else { continue }
                let key = roomKey(station, room)
                let author = (crewRoomInfo[key] != nil ? record.author : nil) ?? github.myLogin() ?? ""
                if let number = record.pulls.keys.min() {
                    events.append(.pullRequestOpened(repo: record.repo, number: number, author: author, roomKey: room.key))
                }
            case .qa where t.from != nil:
                // To the staging area, once the crate stands in storage and no pallet has the repository.
                guard let info = repoRoots.first(where: { $0.value.repo == record.repo }), let station = fleet.stations[info.value.station],
                      let number = record.number, isReady(record.repo) else { continue }
                guard station.hasPad, !station.deckCells.isEmpty, github.pipeline(repoRoot: info.key).hasStaging else { continue }
                let row = station.ledger[record.repo, number]
                if row?.placed == .deck || row?.heading == .deck { continue }
                let pallet = truth.pallets[station.name]?.repo == record.repo || truth.palletQueue[station.name]?.contains { $0.repo == record.repo } == true
                guard row?.placed == .storage, !(row?.inTransit ?? false), !pallet else { waiting.append((record, t)); continue }
                toDeck[station.name + "|" + record.repo, default: []].append(number)
            case .cleared where t.from != nil:
                guard let info = repoRoots.values.first(where: { $0.repo == record.repo }), let number = record.number, isReady(record.repo) else { continue }
                events.append(.crateCleared(station: info.station, repo: record.repo, number: number))
            case .shipped where t.from != nil:
                guard let info = repoRoots.values.first(where: { $0.repo == record.repo }), let station = fleet.stations[info.station] else { continue }
                launches.insert(info.station + "|" + info.repo)
                _ = station
            default: break
            }
        }
        transitions = waiting
        for (key, numbers) in toDeck.sorted(by: { $0.key < $1.key }) {
            let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
            guard let station = fleet.stations[parts[0]] else { continue }
            let commands = carryToDeck(station: station, repo: parts[1], numbers: numbers)
            if !commands.isEmpty { events.append(.carryToDeck(station: station.name, repo: parts[1], commands: commands)) }
        }
        // One launch per repository per pass, however many pieces of work went up in it.
        for key in launches.sorted() {
            guard let station = fleet.stations[String(key.split(separator: "|")[0])] else { continue }
            let repo = String(key.split(separator: "|", maxSplits: 1)[1])
            if mergeLaunches.contains(key) { continue }   // its own small rocket is already going up
            events.append(launchLabels.removeValue(forKey: key)
                          ?? wish(.launch, station: station, repo: repo, waiting: cargoWaiting(station: station, repo: repo), cleared: true))
        }
        return events
    }
    /// The launch a merged release wrote on the rocket, for the drain to send up with the record's word.
    private var launchLabels: [String: WorldEvent] = [:]

    /// A source's word about the work an office holds, for the record. The station does not act on the
    /// record yet: it shadows what the floor does, and the trace says where the two part ways.
    func report(office key: String, repo: String, _ stage: Stage, by source: Source, at: Date = Date()) {
        guard let r = works.find(officeKey: key, repo: repo) else { return }
        works.report(r, stage, by: source, at: at)
    }
    func report(crate n: Int, repo: String, _ stage: Stage, by source: Source, at: Date = Date()) {
        works.report(works.note(repo: repo, crate: n), stage, by: source, at: at)
    }
    /// A pull request's state as its own word about the work: open is ready, merged is stored, closed
    /// unmerged is back to working. Said on every pass, so a state remembered from last run counts too.
    func report(pullState state: String?, record: WorkBook.Record?, at: Date = Date()) {
        guard let state, let record else { return }
        switch state {
        case "OPEN": works.report(record, .ready, by: .pulls, at: at)
        case "MERGED": works.report(record, .stored, by: .pulls, at: at)
        default: works.report(record, .working, by: .pulls, at: at)
        }
    }
    /// The record behind an office on this station, by "station|key".
    func record(office key: String) -> WorkBook.Record? {
        let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2, let room = fleet.stations[parts[0]]?.rooms[parts[1]], let repo = room.repo else { return nil }
        return works.find(officeKey: room.key, repo: repo)
    }
    /// A teammate's pull request on an office, if GitHub has said one.
    func crewPull(_ key: String) -> Int? { crewRoomInfo[key] != nil ? record(office: key)?.pulls.keys.min() : nil }

    /// A repository's workflow: set by hand, else detected from its pipeline and whether a board follows it.
    func workflow(repo: String) -> Workflow {
        if let w = ConfigStore.shared.current.repos[repo]?.workflow { return w }
        let root = repoRoots.first { $0.value.repo == repo }?.key
        let pipeline = root.map { github.pipeline(repoRoot: $0) } ?? .configured
        return Workflow.detected(pipeline: pipeline, board: ConfigStore.shared.current.project != nil)
    }
    /// Where the record says an office's work is. The floor acts on this, not on any one source.
    func stage(office key: String, repo: String?) -> Stage? { repo.flatMap { works.find(officeKey: key, repo: $0) }?.stage }

    // MARK: a crate's row, from the floor's side

    func crate(_ c: CrateRef) -> Ledger.Crate? { fleet.stations[c.station]?.ledger[c.repo, c.number] }
    func isCarried(_ c: CrateRef) -> Bool { crate(c)?.isCarried ?? false }
    func isOnPallet(_ c: CrateRef) -> Bool { crate(c)?.isOnPallet ?? false }
    func area(of c: CrateRef) -> Spot.Area? { crate(c)?.area }
    func carriedCount(station: String, repo: String) -> Int { fleet.stations[station]?.ledger.carriedCount(repo: repo) ?? 0 }
    func aboard(station: String, repo: String) -> Int { fleet.stations[station]?.ledger.aboard(repo: repo) ?? 0 }

    /// Spoken for by a carry: off the rows from here, drawn once, on the arms once picked up.
    func claim(_ c: CrateRef) { fleet.stations[c.station]?.ledger.claim(repo: c.repo, number: c.number) }
    func pickedUp(_ c: CrateRef, by minion: String) { fleet.stations[c.station]?.ledger.pickedUp(repo: c.repo, number: c.number, by: minion) }
    func setDown(_ c: CrateRef, at spot: Spot) {
        truth.takeOffPallet(c)
        fleet.stations[c.station]?.ledger.setDown(repo: c.repo, number: c.number, at: spot)
    }
    func putOnPallet(_ c: CrateRef, at slot: StationTruth.PalletSlot) {
        truth.putOnPallet(c, at: slot)
        fleet.stations[c.station]?.ledger.onPallet(repo: c.repo, number: c.number, row: slot.row, column: slot.column, level: slot.level)
    }
    /// Nowhere in particular any more: the rows draw it where its row says it belongs.
    func forgetPlacement(_ c: CrateRef) { fleet.stations[c.station]?.ledger.forgetPlacement(repo: c.repo, number: c.number) }
    /// Whatever this minion was holding is no longer on anyone's arms.
    func dropped(by minion: String) { for st in fleet.stations.values { st.ledger.dropped(by: minion) } }
    /// The rocket left: what it carried is off the station.
    func clearPad(station: String, repo: String) { fleet.stations[station]?.ledger.clearPad(repo: repo) }

    // MARK: office hauls

    /// A merged office's package is to go to storage: spoken for from now on.
    func haulOrdered(office key: String, crate: CrateRef) { officeCrates[key] = crate; claim(crate) }
    func haulOrdered(office key: String) -> Bool { officeCrates[key] != nil }
    /// The package is down in the yard, or on a pallet already: the office may clear.
    func haulLanded(office key: String) -> Bool {
        guard let c = officeCrates[key], let row = crate(c) else { return false }
        if let area = row.area { return area != .office }
        return row.isOnPallet
    }
    /// Ordered and not yet down anywhere in the yard: on the office floor still, or on someone's arms.
    func haulUnderway(office key: String) -> Bool { haulOrdered(office: key) && !haulLanded(office: key) }
    func forgetOffice(_ key: String) { officeCrates[key] = nil }

    /// Repositories GitHub has answered for at least once. A repository's first answer is taken quietly:
    /// nothing in it is new, whatever it holds. Only changes after that are events.
    private(set) var readyRepos: Set<String> = []
    /// Everyone seen in a repository's feed, pull requests or board, with where and when last: the
    /// Teammates list in Settings. Kept across launches, so the list is there before the feeds answer.
    private(set) lazy var seenPeople: [String: SeenPerson] = waitsForGitHub ? SeenPerson.load() : [:]
    private var savedPeople: [String: SeenPerson] = [:]
    private var crewSeen: Set<String> = []
    private var didLoadLayout = false
    /// Scans since this run began, for the moment the floor waits before putting offices up on its own.
    /// Counted in scans rather than seconds because a scripted run lives out a whole day in under one.
    private var scans = 0
    /// When last run's answers were last written down.
    private var savedKnowledgeAt = Date.distantPast
    /// How many scans offices wait for GitHub's first word. A station with no network is still your
    /// station, so they go up regardless after this.
    static let officeGraceScans = 10
    /// Whether offices wait for GitHub at all. A real station does, so that the offices everyone can
    /// see are laid down before the ones only this machine knows about. Nothing scripted does: a
    /// scenario, a model test and the gallery all have to put a station up without a network, and a
    /// floor that stayed empty until GitHub answered would leave them with nothing to run on.
    var waitsForGitHub = true

    /// Whether an office has a package standing on its floor at all.
    var hasPackage: (String) -> Bool = { _ in false }
    var rocketBusy: (String) -> Bool = { _ in false }

    func isReady(_ repo: String?) -> Bool { repo.map { readyRepos.contains($0) } ?? true }

    /// Every repository the floor has found has spoken. Not one of them: offices go down in one go or
    /// not at all, since a floor that fills a repository at a time is a stutter with a pause in it.
    var allReady: Bool { !repoRoots.isEmpty && repoRoots.values.allSatisfy { readyRepos.contains($0.repo) } }

    /// The floor is still waiting to hear from GitHub, and holding its offices back until it does.
    var settling: Bool { waitsForGitHub && scans < World.officeGraceScans && !allReady && !knewAlready }

    /// The floor came back with last run's answers, so there is nothing to wait for. What arrives now
    /// corrects a station already standing, and a room nothing vouches for yet stays provisional.
    private var knewAlready: Bool { github.hasAnswers }

    /// Settings changed: forget the fleet and start again from the next scan.
    func reset() {
        fleet.removeAllStations()
        repoRoots = [:]
        readyRepos = []
        didLoadLayout = false
    }

    // MARK: queries the scene draws from

    func crewName(_ login: String) -> String { ConfigStore.shared.current.crewNames[login] ?? login }

    /// The issue an office is for, where its key says so: `task:repo#128`. A branch with no issue behind
    /// it has none.
    func taskNumber(_ room: Room) -> Int? { Work.number(inOfficeKey: room.key) }

    /// The office key for a teammate's branch: the same key a local checkout of it would get.
    func crewKey(repo: String, branch: String) -> String { Work(repo: repo, branch: branch).officeKey }

    func roomKey(_ station: Station, _ room: Room) -> String { "\(station.name)|\(room.key)" }

    /// The repositories Settings lists: every checkout the station knows, every repository with an office
    /// on it, a neighbour's too, and every one with settings of its own, hidden or added by hand.
    var knownRepos: [String] {
        var names = Set(repoRoots.values.map(\.repo)).union(ConfigStore.shared.current.repos.keys)
        for s in fleet.stations.values { for r in s.rooms.values { if let repo = r.repo { names.insert(repo) } } }
        return names.sorted()
    }

    /// A task room whose branch is not on GitHub yet: (unpushed, commits ahead).
    func localState(_ room: Room) -> (local: Bool, commits: Int) {
        guard room.key.hasPrefix("task:"), let w = room.worktree else { return (false, 0) }
        var pushed = github.branchPushed(worktree: w) ?? true
        if let b = room.branch, let r = room.repoRoot, github.pull(branch: b, repoRoot: r) != nil { pushed = true }
        return (!pushed, github.commitsAhead(worktree: w) ?? 0)
    }

    func checksFailing(_ room: Room) -> Bool {
        if room.branch == nil, let po = peerPull("work|" + room.key) { return po.pullState == "OPEN" && po.checks == "failure" }
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
        return !demo && room.worktree == nil && !room.key.hasPrefix("kind:") && crewRoomInfo[key] == nil && !pushedByPeer.contains(key) && !peerLive(key)
    }

    /// Drawn from last night's notes and not yet confirmed today. A different thing from provisional,
    /// which is about whether anybody vouches for an office at all: this is about whether we have looked.
    func isUnchecked(_ station: Station, _ room: Room) -> Bool {
        !demo && !room.key.hasPrefix("kind:") && !lookedAt(room.repo)
    }

    /// The floor is still arriving: some repository has not been looked at today, or none has been found
    /// yet — which is the first second or two of every launch, and precisely when it must not be taken
    /// for "nothing left to wait for". Bounded, so a repository that never answers cannot hold it open.
    var stillLooking: Bool {
        guard waitsForGitHub, scans < World.lookingScans else { return false }
        return repoRoots.isEmpty || repoRoots.keys.contains { !github.answered(repoRoot: $0) }
    }
    /// The most scans the floor will call itself still arriving for.
    static let lookingScans = 60

    /// GitHub has answered for this repository over the wire in this run — not from last night's notes,
    /// and not from a neighbour. Repositories the floor has not even found yet count as unlooked-at.
    func lookedAt(_ repo: String?) -> Bool {
        guard waitsForGitHub else { return true }
        guard let repo else { return true }
        let roots = repoRoots.filter { $0.value.repo == repo }.map(\.key)
        return !roots.isEmpty && roots.contains { github.answered(repoRoot: $0) }
    }

    /// Someone is at work in a peer's office right now: a session awake in it on their machine.
    func peerLive(_ key: String) -> Bool {
        peerSnapshots.values.contains { entry in entry.snap.minions.contains { !$0.asleep && "work|" + $0.office == key } }
    }
    /// A peer's office in use but not on GitHub yet: drawn solid, with its outline kept as the mark.
    func isLocalLive(_ station: Station, _ room: Room) -> Bool {
        let key = roomKey(station, room)
        return room.worktree == nil && !room.key.hasPrefix("kind:") && crewRoomInfo[key] == nil && !pushedByPeer.contains(key) && peerLive(key)
    }
    /// Every peer claiming this office says it is idle.
    func peerDim(_ key: String) -> Bool { peerOffices[key].map { !$0.isEmpty && $0.values.allSatisfy(\.dim) } ?? false }
    /// A peer's pull request on this office, as they last said.
    func peerPull(_ key: String) -> PeerSnapshot.Office? { peerOffices[key]?.values.first { $0.pull != nil } }

    /// Whose office this is, for the floor: the teammate GitHub names, else the peer who has it checked out.
    func occupant(of key: String) -> String? {
        if crewRoomInfo[key] != nil, let author = record(office: key)?.author { return crewName(author) }
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
        events.append(.log("\(Words.current.kicked) \(room.name) \(Words.current.kickedOff)"))
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

    /// Every session touched today keeps its office alive; archived workspaces lose theirs. Archived
    /// means two different things: Conductor deletes the worktree, Claude Code leaves it and drops its
    /// lease, and a station that watched only the disk kept an office for every workspace ever opened.
    func applyScan(_ result: ScanResult, now: Date, minionHomes: [String: MinionHome]) -> [WorldEvent] {
        var events: [WorldEvent] = []
        var changed = false
        let firstRun = !didLoadLayout
        if firstRun {
            didLoadLayout = true
            // The record shadows the floor for now; the trace is where the two are compared.
            works.workflow = { [weak self] repo in self?.workflow(repo: repo) ?? Workflow() }
            works.onTransition = { [weak self] r, t in
                let who = r.number.map { "#\($0)" } ?? r.work().label
                StationLog.write("stage", "\(r.repo) \(who): \(t.from.map { "\($0) → " } ?? "")\(t.to) · \(t.by.rawValue)\(t.back ? " (back)" : "")")
                self?.transitions.append((r, t))
            }
            fleet.load()
            // Last run's answers come back with the floor, so the station stands whole from the first
            // frame and the asks going out are corrections rather than the thing it is waiting for.
            if waitsForGitHub { github.loadKnowledge() }
            changed = true
            events.append(.worldLoaded)
        }

        scans += 1
        let cfg = ConfigStore.shared.current
        for s in result.sessions where s.cwdExists && Fleet.stationName(for: s.cwd, owner: s.owner, repo: s.repo) != "hidden"
            && (Fleet.stationName(for: s.cwd, owner: s.owner, repo: s.repo) == "work" || now.timeIntervalSince(s.lastModified) < World.roomsWindow) {
            let stationName = Fleet.stationName(for: s.cwd, owner: s.owner, repo: s.repo)
            let station = fleet.station(stationName)
            let home = homeFor(s, station: stationName)
            // The shared offices go down first, so that two stations seeing the same pull requests dig
            // the same floor: yours are held until GitHub has spoken for the repository, by which time
            // its own offices are already placed. An office already on the floor is never held, and
            // nothing waits forever — after a moment they go up regardless. The whole floor is held
            // as one, not a repository at a time, so the wait ends in a station and not a dribble.
            let held = settling && station.rooms[home.key] == nil
            if !held, let m = minionHomes[s.id], m.key != home.key, station.rooms[home.key] == nil, station.rooms[m.key] != nil,
               !minionHomes.contains(where: { $0.key != s.id && $0.value.key == m.key && $0.value.station == stationName }) {
                let promoted = m.key.hasPrefix("proj:") && home.key.hasPrefix("task:")
                station.renameRoom(from: m.key, to: home.key, name: home.name)
                events.append(.officeRenamed(station: stationName, from: m.key, to: home.key, name: home.name, session: s.id,
                                             promoted: promoted && !firstRun && m.idle))
                changed = true
            }
            if let r = station.rooms[home.key], r.worktree == nil, r.name != home.name { r.name = home.name; changed = true }
            if !held, station.ensureRoom(key: home.key, name: home.name, repo: home.repo, color: fleet.color(forRepo: home.repo), lastActive: s.lastModified) {
                changed = true
                roomCreated["\(stationName)|\(home.key)"] = now
                // A floor still settling puts its offices up where they stand; a shuttle is for one that
                // arrives on a station already at work.
                events.append(.officeOpened(station: stationName, key: home.key, source: .session(s.id),
                                            arrival: firstRun || scans <= World.officeGraceScans + 1 ? .appear : .shuttle))
                report(office: home.key, repo: home.repo, .inbound, by: .session, at: s.lastModified)
            }
            if let root = s.repoRoot, !repoRoots.values.contains(where: { $0.repo == s.repo }) {
                repoRoots[root] = (s.repo, stationName)
            }
            // A message arrived since the last scan: cones on the office floor, and its worker over to them.
            let marker = s.eventMarkers[.prompt] ?? ""
            if let seen = sessionPrompts[s.id], seen.marker != marker, !firstRun, !s.isSubagent {
                events.append(.prompt(station: stationName, key: home.key, minionId: s.id,
                                      count: max(1, s.promptCount - seen.count)))
                report(office: home.key, repo: home.repo, .working, by: .session, at: s.lastModified)
            }
            sessionPrompts[s.id] = (marker, s.promptCount)
            if let room = station.rooms[home.key], !home.key.hasPrefix("kind:") {
                room.worktree = s.cwd
                if home.key.hasPrefix("task:") { room.branch = s.branch; room.repoRoot = s.repoRoot }
                if let b = room.branch, let r = room.repoRoot { github.refresh(branch: b, repoRoot: r) }
                if let w = room.worktree { github.refreshCommits(worktree: w) }
            }
        }
        // One workspace, one office. An office is keyed by its branch until GitHub names a pull request
        // for it and then by the number, and the room under the old key was being left where it stood —
        // so a workspace with a pull request open had two offices on the floor, both of them live.
        for station in fleet.stations.values {
            var byWorkspace: [String: [Room]] = [:]
            for room in station.rooms.values where !room.key.hasPrefix("kind:") {
                if let w = room.worktree { byWorkspace[w, default: []].append(room) }
            }
            for (_, rooms) in byWorkspace where rooms.count > 1 {
                // The one named for the pull request keeps the desk; it is the one the crates know.
                let keep = rooms.first { $0.key.contains("#") } ?? rooms.min { $0.key < $1.key }
                for room in rooms where room !== keep {
                    events.append(drop(station: station, room: room, announce: false, reason: "one workspace, one office"))
                    changed = true
                }
            }
        }
        for station in fleet.stations.values {
            for room in Array(station.rooms.values) where !room.key.hasPrefix("kind:") {
                let key = roomKey(station, room)
                let pull = room.branch.flatMap { b in room.repoRoot.flatMap { github.pull(branch: b, repoRoot: $0) } }
                let state = pull?.state
                if let pull, let repo = room.repo { report(pullState: state, record: works.note(repo: repo, branch: room.branch, folder: room.worktree, issue: pull.closes.first, pull: pull.number, pullState: state)) }
                // Merged is the record's word, whoever said it: the pull request, the board's column or git history.
                let merged = stage(office: room.key, repo: room.repo).map { $0 >= .stored } ?? false
                // A checkout that went away still waits for its crate to reach storage: the office
                // stays open until the haul lands, the way it does for any merged office.
                let gone = (room.worktree.map { !Workspaces.isOpen($0) } ?? false) && !haulUnderway(office: key)
                // Closed without merging: the work goes nowhere. The crate turns red, sits for ten minutes, then the office clears.
                let closed = state == "CLOSED" && !merged
                if closed, closedAt[key] == nil { closedAt[key] = now; events.append(.log("\(room.name): pull request closed, not merged")) }
                if !closed { closedAt[key] = nil }
                if merged, station.hasPad, !haulOrdered(office: key) { events += haulMerged(station: station, room: room) }
                // A merged office clears once its crate is down in the yard, or when there was nothing to carry.
                let cleared = (merged && (!station.hasPad || haulLanded(office: key) || nothingToHaul.contains(key)))
                    || (closed && now.timeIntervalSince(closedAt[key] ?? now) > World.closedWindow)
                // Nobody's: no checkout here, no peer claiming it, nothing on GitHub once GitHub has answered.
                // An office a peer left behind is held for a day so their return does not move it.
                let unclaimed = room.worktree == nil && crewRoomInfo[key] == nil && peerOffices[key] == nil && isReady(room.repo)
                    && (cfg.project == nil || github.projectItems() != nil)
                let orphan = unclaimed && (held[key].map { now.timeIntervalSince($0) > World.holdWindow } ?? true)
                // An office of three kinds, and they do not end the same way. One of yours is backed by
                // a checkout on this disk and one of a neighbour's by their word over the network, and
                // both last until the workspace itself is archived — a merged pull request says the work
                // shipped, not that the desk was cleared. An office that is only GitHub's has nothing
                // else to go on: the merge is the last anybody hears of it, since branches are left to
                // die with their pull requests rather than deleted.
                let mine = room.worktree.map { Workspaces.isOpen($0) } ?? false
                let lan = peerOffices[key] != nil
                let ended = cleared && !mine && !lan
                if gone || ended || orphan {
                    if ended { retired[key] = now }
                    events.append(drop(station: station, room: room, announce: !firstRun,
                                       reason: gone ? "workspace archived" : closed ? "closed, not merged" : ended ? "merged and hauled" : "nobody's"))
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
            // A checkout added by hand in Settings is on the station the same way.
            for (repo, o) in cfg.repos where cfg.shown(repo: repo) {
                guard let root = o.path, FileManager.default.fileExists(atPath: root + "/.git"),
                      !repoRoots.values.contains(where: { $0.repo == repo }) else { continue }
                repoRoots[root] = (repo, "work")
                _ = fleet.color(forRepo: repo)
            }
        }
        github.intervalMinutes = cfg.githubMinutes
        if let p = cfg.project { github.refreshProject(owner: p.owner, number: p.number); github.refreshProjectDelta(owner: p.owner, number: p.number) }
        for (root, info) in repoRoots {
            github.refreshReleases(repoRoot: root)
            if info.station == "work" { github.refreshFeed(repoRoot: root); github.refreshOpenPRs(repoRoot: root) }
        }
        events += applyBoardMoves()
        for change in github.takeStateChanges() {
            for station in fleet.stations.values {
                for room in station.rooms.values where room.branch == change.branch {
                    if let repo = room.repo { works.note(repo: repo, branch: change.branch, issue: change.pr.closes.first, pull: change.pr.number, pullState: change.pr.state) }
                }
            }
            // The pull request's own word: open is ready, merged is stored, closed unmerged is back to working.
            for station in fleet.stations.values {
                for room in station.rooms.values where room.branch == change.branch {
                    guard let repo = room.repo else { continue }
                    report(pullState: change.pr.state, record: works.find(repo: repo, pull: change.pr.number))
                }
            }
            let who = Work(repo: "", branch: change.branch).label
            events.append(.log("\(who): \(change.pr.summary)"))
            events.append(.chime(change.pr.number))
        }
        events += stationEvents()   // a pull request newly open has its office's worker pack the crate
        if changed { events.append(.layoutChanged) }
        return events
    }

    /// A session's office, unless that office was merged and cleared while the session lingers on the
    /// branch: then the minion waits in the lounge rather than rebuilding the office every scan.
    func homeFor(_ s: SessionInfo, station: String) -> Home {
        // A branch names an office until GitHub says which pull request it is, and after that the pull
        // request does. Otherwise the same work is one office here, under the branch it is checked out
        // on, and another from GitHub under its number — and neither knows about the other, so the
        // rules that keep your own office standing never see the remote one at all. A branch named
        // `gh-N/…` already arrives as `#N`; this is for every branch that is not.
        let pr = s.branch.flatMap { b in s.repoRoot.flatMap { github.pull(branch: b, repoRoot: $0) } }
        let home = works.note(repo: s.repo, branch: s.branch, folder: s.cwd, issue: pr?.closes.first, pull: pr?.number, pullState: pr?.state)
            .work(branch: s.branch).home
        if let at = retired["\(station)|\(home.key)"], Date().timeIntervalSince(at) < World.holdWindow {
            return Home(key: "kind:lounge", name: home.name, repo: home.repo, issue: nil)
        }
        return home
    }

    // MARK: github

    /// A fresh answer from GitHub: board columns that moved, and the crew's floor rebuilt around it.
    func applyGitHub(now: Date, timed: ((String, () -> [WorldEvent]) -> [WorldEvent])? = nil) -> [WorldEvent] {
        let run = timed ?? { _, b in b() }
        placementsLeft = false
        var events = run("gh.releases") { self.applyReleases() }
        events += run("gh.board") { self.applyBoardMoves() }
        events += run("gh.crew") { self.rebuildCrew(now: now) }
        events += stationEvents()
        return events
    }

    // MARK: releases and the pad

    /// Releases already announced, so an open one on the pad is only said once: "station|repo|number|untested".
    private var announcedReleases: Set<String> = []
    /// Repositories whose releases have answered once. The first answer is quiet: whatever is on the
    /// pad already existed, and the rocket simply stands there.
    private var releasesSeen: Set<String> = []

    /// The staging release each repository is known to have, by "station|repo": its number and state.
    private var stagingPRs: [String: (number: Int, state: String)] = [:]
    /// Repositories whose releases have answered once. The first answer is quiet: whatever it holds already existed.
    private var stagingSeen: Set<String> = []

    /// A repository's checkout, by station and name.
    func root(station: String, repo: String) -> String? { repoRoots.first { $0.value.station == station && $0.value.repo == repo }?.key }
    /// Whether the deck, rather than storage, is what a repository's rocket loads from: it has a staging branch.
    func stagingIsDeck(station: String, repo: String) -> Bool {
        root(station: station, repo: repo).map { github.pipeline(repoRoot: $0).hasStaging } ?? !ConfigStore.shared.current.stagingBranch.isEmpty
    }
    /// Whether a repository's merges deploy at once, rather than waiting for a release.
    func shipsOnMerge(station: String, repo: String) -> Bool {
        root(station: station, repo: repo).map { github.pipeline(repoRoot: $0).shipsOnMerge } ?? false
    }
    /// A merge launch has climbed: its crates are gone from the ledger outright. No source will ever say
    /// they shipped, so nothing else would take the rows away.
    func forgetShipped(station: String, repo: String) {
        guard let st = fleet.stations[station] else { return }
        for c in st.ledger.crates(of: repo) where c.placed == .pad {
            report(crate: c.number, repo: repo, .shipped, by: mergeLaunches.contains(station + "|" + repo) ? .git : .pulls)
            st.ledger.forget(repo: repo, number: c.number)
        }
    }
    /// Rockets going up for a merge rather than a release, as "station|repo": they stand on the pad too.
    var mergeLaunches: Set<String> = []
    /// Whether a station's deck is in use: some repository on it has a staging branch.
    func deckInUse(station: String) -> Bool {
        let roots = repoRoots.filter { $0.value.station == station }.map(\.key)
        return roots.isEmpty ? !ConfigStore.shared.current.stagingBranch.isEmpty : roots.contains { github.pipeline(repoRoot: $0).hasStaging }
    }

    /// The release pull request whose rocket a repository's pad should hold, if any.
    private func padRelease(root: String) -> ReleasePR? {
        guard let open = github.openReleases(repoRoot: root) else { return nil }
        let hasProduction = open.contains(where: \.isProduction)
        return open.first { $0.isProduction || (!hasProduction && !github.pipeline(repoRoot: root).hasStaging) }
    }

    /// The work of a repository the next rocket is for: what is cleared or in QA when the repository has
    /// a staging area, and what is stored besides when it has not.
    func waiting(repo: String, station: String) -> [WorkBook.Record] {
        let from: Stage = stagingIsDeck(station: station, repo: repo) ? .qa : .stored
        return works.records(repo: repo).filter { r in r.stage.map { $0 >= from && $0 < .shipped } ?? false }
    }
    /// Whether the rocket may load a repository's waiting work: all of it cleared, or nothing to clear here.
    func clearedToLoad(repo: String, station: String) -> Bool {
        let w = waiting(repo: repo, station: station)
        return !w.isEmpty && (!workflow(repo: repo).has(.cleared) || w.allSatisfy { $0.stage.map { $0 >= .cleared } ?? false })
    }

    /// Pads that should hold a rocket right now, as "station|repo": a release open, a merge going up, or
    /// work waiting for a release in a repository that has a way to ship.
    func padRockets() -> Set<String> {
        var pads = Set(repoRoots.compactMap { root, info in padRelease(root: root) != nil ? info.station + "|" + info.repo : nil }).union(mergeLaunches)
        for (root, info) in repoRoots where fleet.stations[info.station]?.hasPad == true && !workflow(repo: info.repo).shipped.isEmpty
            && !github.pipeline(repoRoot: root).shipsOnMerge && !waiting(repo: info.repo, station: info.station).isEmpty { pads.insert(info.station + "|" + info.repo) }
        return pads
    }

    /// A rocket for work waiting with no release opened for it yet: what is stored since the last one went.
    private func wish(_ stage: Command.RocketStage, station: Station, repo: String, waiting n: Int, cleared: Bool) -> WorldEvent {
        let status = " · " + (cleared ? Words.current.cleared : Words.current.holding)
        let label = "rocket:|\(repo) · \(n) \(n == 1 ? Words.current.crate : Words.current.crates) waiting for a release\(status)"
        return .rocketCommand(station: station.name, repo: repo, label: label, untested: !cleared, tall: true, cargo: n,
                              command: .rocket(stage, station: station.name, repo: repo))
    }

    /// One rocket command, with what to write on the prop and how much cargo it should be sized for.
    private func wish(_ stage: Command.RocketStage, station: Station, repo: String, pr: ReleasePR) -> WorldEvent {
        let status = " · " + (pr.untested ? Words.current.holding : Words.current.cleared)
        // A tag has no number and no branch it came from: it is a name and a moment.
        let label = pr.tag ? "rocket:\(pr.url)|\(repo) · \(pr.title) tagged on \(pr.base)\(status)"
            : "rocket:\(pr.url)|\(repo) · \(pr.head) → \(pr.base) · #\(pr.number) \(pr.title)\(status)"
        return .rocketCommand(station: station.name, repo: repo, label: label, untested: pr.untested,
                              tall: pr.isProduction, cargo: cargoWaiting(station: station, repo: repo),
                              command: .rocket(stage, station: station.name, repo: repo))
    }

    /// Crates a rocket would load: the deck when there is a staging branch, storage otherwise.
    func cargoWaiting(station: Station, repo: String) -> Int {
        (stagingIsDeck(station: station.name, repo: repo) ? station.staged : station.stored)[repo] ?? 0
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
            // The release ships what was waiting for it; the launch itself follows from the record.
            for r in waiting(repo: info.repo, station: station.name) { works.report(r, .shipped, by: pr.tag ? .git : .pulls, at: pr.mergedAt ?? Date()) }
            for c in station.ledger.crates(of: info.repo) where c.placed == .pad { report(crate: c.number, repo: info.repo, .shipped, by: pr.tag ? .git : .pulls, at: pr.mergedAt ?? Date()) }
            announcedReleases = announcedReleases.filter { !$0.hasPrefix("\(info.station)|\(info.repo)|") }
            events.append(.log(pr.tag ? "\(info.repo) \(Words.current.launchedTo) \(pr.title)"
                                       : "\(info.repo) \(Words.current.launchedTo) \(pr.base): \(pr.title)"))
            launchLabels[info.station + "|" + info.repo] = wish(.launch, station: station, repo: info.repo, pr: pr)
        }
        for (root, info) in repoRoots {
            guard let station = fleet.stations[info.station], github.openReleases(repoRoot: root) != nil else { continue }
            let quiet = !releasesSeen.contains(root)
            releasesSeen.insert(root)
            let key = info.station + "|" + info.repo
            guard !launched.contains(key) else { continue }
            guard let pr = padRelease(root: root) else {
                // No release opened yet: work waiting for one has a rocket standing all the same, loaded
                // once every piece of it is cleared, or at once where nothing clears here.
                let w = waiting(repo: info.repo, station: station.name)
                guard station.hasPad, !w.isEmpty, !workflow(repo: info.repo).shipped.isEmpty, !mergeLaunches.contains(key),
                      !github.pipeline(repoRoot: root).shipsOnMerge else { continue }   // a merge's rocket is its own, one per merge
                let cleared = clearedToLoad(repo: info.repo, station: station.name)
                events.append(wish(cleared ? .load(cargoWaiting(station: station, repo: info.repo)) : .standBy,
                                   station: station, repo: info.repo, waiting: w.count, cleared: cleared))
                continue
            }
            let mark = "\(key)|\(pr.number)|\(pr.untested)"
            if quiet { announcedReleases.insert(mark) }
            if !announcedReleases.contains(mark) {
                announcedReleases.insert(mark)
                events.append(.releaseOpened(station: info.station, repo: info.repo, number: pr.number, base: pr.base,
                                             untested: pr.untested, isProduction: pr.isProduction))
                events.append(.log("\(info.repo): release to \(pr.base) \(Words.current.onThePad)" + (pr.untested ? " (untested)" : "")))
            }
            // Untested, or not for production: the rocket only stands there. Cleared: it takes the cargo aboard.
            let cleared = pr.isProduction && !pr.untested
            if cleared { for r in waiting(repo: info.repo, station: station.name) { works.report(r, .cleared, by: .pulls) } }
            events.append(wish(cleared ? .load(cargoWaiting(station: station, repo: info.repo)) : .standBy,
                               station: station, repo: info.repo, pr: pr))
        }
        return events + applyStaging()
    }

    /// The staging release of each repository, diffed against the last answer: opened, merged, or
    /// closed without merging. One open staging release per repository at a time, which is what the
    /// one pallet per station is for.
    private func applyStaging() -> [WorldEvent] {
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

    /// How many offices may be found a place in one go. Finding one somewhere to stand is a search over
    /// the whole floor, about a fiftieth of a second each, and a launch has a dozen of them to place —
    /// which is a quarter of a second of the window standing still if they are all done at once. Waiting
    /// on GitHub costs nothing; it is what arrives with the answer that has to be paced.
    static let placementsPerPass = 1
    /// True while offices are still waiting for somewhere to stand, so the next pass comes round.
    private(set) var placementsLeft = false

    /// Crew station: an office per open teammate pull request, boxes per push, and minions that
    /// react only to what just happened in the repositories' activity feeds.
    private func rebuildCrew(now: Date) -> [WorldEvent] {
        var placed = 0
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
            for pr in github.teamOpenPRs(repoRoot: root) ?? [] where pr.author != me && !Work.longLived.contains(pr.branch) { open.append((info.repo, pr)) }
            for e in github.feed(repoRoot: root) ?? [] where e.actor != me { feed.append((info.repo, e)) }
        }
        // Issues the board says are in development, assigned to someone else: offices too, even before a pull request.
        var boardOffices: [(repo: String, item: ProjectItem, login: String)] = []
        if cfg.project != nil, !me.isEmpty, let items = github.projectItems() {   // not before GitHub has said who I am
            let workRepos = Set(repoRoots.values.filter { $0.station == "work" && cfg.crewEnabled(repo: $0.repo) }.map(\.repo))
            // The column says an office is solid; it does not make one. An issue needs a sign of work:
            // a linked pull request, a branch seen in the feed, or a room a session or peer already claims.
            // "repo#N" with a gh-N/… branch pushed in the last two weeks, and not deleted or closed since:
            // a branch that is gone is no sign of work, however recently it went.
            var branched: Set<String> = []
            let recent = now.addingTimeInterval(-14 * 24 * 3600)
            for (repo, e) in feed.sorted(by: { $0.e.at < $1.e.at }) where e.at > recent {
                guard let b = e.branch, let n = Work.issue(inBranch: b) else { continue }
                switch e.kind {
                case "push", "branch_create", "pr_open": branched.insert("\(repo)#\(n)")
                case "branch_delete", "pr_close", "pr_merge": branched.remove("\(repo)#\(n)")
                default: break
                }
            }
            for it in items where it.status == cfg.statuses.development && workRepos.contains(it.repo) {
                if it.isClosed { continue }   // finished work, whatever column the board left it in
                let key = Work(repo: it.repo, issue: it.number).officeKey
                guard let login = it.assignees.first, login != me else { continue }
                if open.contains(where: { $0.repo == it.repo && crewKey(repo: $0.repo, branch: $0.pr.branch) == key }) { continue }
                let working = !it.prURLs.isEmpty || branched.contains("\(it.repo)#\(it.number)") || peerOffices[sk + key] != nil || station.rooms[key]?.worktree != nil
                guard working else { continue }
                boardOffices.append((it.repo, it, login))
            }
        }
        // Bot pull requests are not work: each is an object of unknown origin in decon, no office and
        // nobody for it. The bots' room of old, if a saved layout still has one, goes.
        for old in ["kind:bots", "kind:mail"] where station.rooms[old] != nil { station.removeRoom(key: old); changed = true }
        var deconMoved = false
        events += screen(station: station, open: open, feed: feed, moved: &deconMoved)
        let inDecon = station.ledger.allCrates.contains { $0.alien && $0.placed == .decon }
        guard !open.isEmpty || !feed.isEmpty || !boardOffices.isEmpty || inDecon else {
            if changed || deconMoved { events.append(changed ? .layoutChanged : .markersChanged) }
            return events
        }

        // Offices for open pull requests; a new one arrives by shuttle, a gone one is archived.
        var liveKeys = Set(open.filter { !$0.pr.isBot }.map { crewKey(repo: $0.repo, branch: $0.pr.branch) })
        liveKeys.formUnion(boardOffices.map { Work(repo: $0.repo, issue: $0.item.number).officeKey })
        for room in Array(station.rooms.values) where crewRoomInfo[sk + room.key] != nil && !liveKeys.contains(room.key) {
            let key = sk + room.key
            let known = room.repo.flatMap { works.find(officeKey: room.key, repo: $0) }
            let author = known?.author ?? ""
            // A teammate's office that we also have checked out stays: the local scan decides its fate.
            guard room.worktree == nil else { crewRoomInfo[key] = nil; crewBoxes[key] = nil; continue }
            // Gone from the open list: merged, or closed without merging. The pull request itself is the
            // authority on which. The feed may already say; otherwise it is asked, and until it answers
            // nothing moves: a crate that was never merged work must not be carried to storage.
            var hauling = false
            let branch = known?.work().branch ?? known?.branches.sorted().first ?? ""
            let root = repoRoots.first { $0.value.repo == room.repo }?.key
            var state: String?
            if feed.contains(where: { $0.repo == room.repo && $0.e.kind == "pr_close" && $0.e.branch == branch }) { state = "CLOSED" }
            else if feed.contains(where: { $0.repo == room.repo && $0.e.kind == "pr_merge" && $0.e.branch == branch }) { state = "MERGED" }
            else if let root, let number = known?.pulls.keys.min() {
                // By number: the office may have lived on as a board office, whose branch is only a guess.
                github.refresh(pull: number, repoRoot: root)
                if github.pullAnswered(number: number, repoRoot: root) { state = github.pull(number: number, repoRoot: root)?.state }
            } else if let root {
                github.refresh(branch: branch, repoRoot: root)
                if github.pullAnswered(branch: branch, repoRoot: root) { state = github.pull(branch: branch, repoRoot: root)?.state ?? "CLOSED" }
            } else { state = "MERGED" }   // no checkout of the repository here: nothing to ask, and nothing on the floor to carry
            guard let state else { continue }
            if let repo = room.repo { report(pullState: state, record: known?.pulls.keys.min().map { works.note(repo: repo, pull: $0, pullState: state) } ?? known) }
            crewRoomInfo[key]?.state = state
            let closedUnmerged = !(stage(office: room.key, repo: room.repo).map { $0 >= .stored } ?? false)
            if closedUnmerged {
                // Closed without merging: red for ten minutes, then gone. Nothing to carry, and no crate.
                if let n = known?.number { station.ledger.forget(repo: room.repo ?? "", number: n) }
                if closedAt[key] == nil { closedAt[key] = now; events.append(.log("\(room.name): pull request closed, not merged")) }
                if now.timeIntervalSince(closedAt[key] ?? now) < World.closedWindow { continue }
            } else if !haulOrdered(office: key), station.hasPad {
                let merged = haulMerged(station: station, room: room)
                hauling = !merged.isEmpty   // the scene is about to start carrying: the office waits for it
                events += merged
                if isReady(room.repo) { events.append(.pullRequestClosed(repo: room.repo ?? "", author: author, roomKey: room.key)) }
            }
            guard !station.hasPad || !(hauling || haulUnderway(office: key)) else { continue }
            closedAt[key] = nil
            crewRoomInfo[key] = nil; crewBoxes[key] = nil
            events.append(drop(station: station, room: room, announce: isReady(room.repo), reason: "pull request closed"))
            changed = true
        }
        for (repo, pr) in open where !pr.isBot && !isKicked(sk + crewKey(repo: repo, branch: pr.branch)) {
            let record = works.note(repo: repo, branch: pr.branch, pull: pr.number, pullState: "OPEN", author: pr.author, title: pr.title, url: pr.url)
            works.report(record, .ready, by: .pulls, at: pr.createdAt)   // every pass: the office may have been the board's first
            let home = Work(repo: repo, branch: pr.branch).home
            let key = home.key
            let name = home.name
            if let r = station.rooms[key], r.worktree == nil, r.name != name { r.name = name; changed = true }
            if station.rooms[key] == nil {
                guard placed < World.placementsPerPass else { placementsLeft = true; continue }
                placed += 1
            }
            if station.ensureRoom(key: key, name: name, repo: repo, color: fleet.color(forRepo: repo), lastActive: now) {
                changed = true
                if isReady(repo) {
                    events.append(.officeOpened(station: station.name, key: key, source: .github(pr.author), arrival: .shuttle))
                }
            }
            crewRoomInfo[sk + key] = CrewRoomInfo(state: "OPEN", last: pr.createdAt)
            let pushes = feed.filter { $0.repo == repo && $0.e.kind == "push" && $0.e.branch == pr.branch && $0.e.at > pr.createdAt }.map { Int($0.e.detail) ?? 1 }.reduce(0, +)
            crewBoxes[sk + key] = (1 + pushes, "OPEN", fleet.color(forRepo: repo))
        }
        for (repo, it, login) in boardOffices where !isKicked(sk + Work(repo: repo, issue: it.number).officeKey) {
            let key = Work(repo: repo, issue: it.number).officeKey
            works.note(repo: repo, issue: it.number, pull: it.prURLs.first.flatMap { Int($0.split(separator: "/").last ?? "") },
                       author: login, title: it.title, url: it.url)
            let name = "#\(it.number) " + String(it.title.prefix(22))
            if let r = station.rooms[key], r.worktree == nil, r.name != name { r.name = name; changed = true }
            if station.rooms[key] == nil {
                guard placed < World.placementsPerPass else { placementsLeft = true; continue }
                placed += 1
            }
            if station.ensureRoom(key: key, name: name, repo: repo, color: fleet.color(forRepo: repo), lastActive: now) {
                changed = true
                if isReady(repo) {
                    events.append(.officeOpened(station: station.name, key: key, source: .board(login), arrival: .shuttle))
                    report(office: key, repo: repo, .inbound, by: .board)
                    events.append(.issueStarted(repo: repo, number: it.number, author: login, roomKey: key))
                }
            }
            crewRoomInfo[sk + key] = CrewRoomInfo(state: "OPEN", last: now)
            crewBoxes[sk + key] = (1, "NONE", fleet.color(forRepo: repo))
        }

        // One grey minion per teammate with an open PR or recent activity.
        var logins = Set(open.filter { !$0.pr.isBot }.map(\.pr.author))
        logins.formUnion(boardOffices.map(\.login))
        logins.formUnion(feed.filter { !$0.e.isBot && now.timeIntervalSince($0.e.at) < 2 * 3600 }.map(\.e.actor))
        for (repo, e) in feed where !e.isBot { seen(e.actor, in: repo, at: e.at) }
        for (repo, pr) in open where !pr.isBot { seen(pr.author, in: repo, at: pr.createdAt) }
        for o in boardOffices { seen(o.login, in: o.repo, at: o.item.updatedAt ?? now) }
        var roster: [String: CrewMember] = [:]
        for login in logins {
            let homeKey = open.first { $0.pr.author == login }.map { crewKey(repo: $0.repo, branch: $0.pr.branch) } ?? "kind:quarters"
            roster[login] = CrewMember(homeKey: homeKey, repo: open.first { $0.pr.author == login }?.repo ?? "crew")
        }
        events.append(.crewRoster(members: roster))
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
        let lookedBefore = repoRoots.keys.filter { github.answered(repoRoot: $0) }.count
        let before = readyRepos.count
        for (root, info) in repoRoots where info.station == "work" && github.teamOpenPRs(repoRoot: root) != nil { readyRepos.insert(info.repo) }
        // Kept up to date, not just filled in once: an office that has gone from GitHub is dropped on
        // the floor and must go from what next launch is told as well, or it comes back from the dead
        // every morning. Written when a repository first answers, and now and then after that.
        if waitsForGitHub, readyRepos.count != before || Date().timeIntervalSince(savedKnowledgeAt) > 60 {
            savedKnowledgeAt = Date()
            github.saveKnowledge(repoRoots.mapValues(\.repo))
            if seenPeople != savedPeople { savedPeople = seenPeople; SeenPerson.save(seenPeople) }
        }
        return events
    }

    /// Decon: bot pull requests, one object each. An arrival is a new number on a repository's open
    /// list, and the hatch says so. An object gone from the list is asked after: the feed may say, else
    /// the pull request is fetched, and until it answers the object stays. Merged, it is cleared and
    /// ordered into storage like any merged crate; closed, it is ejected.
    private func screen(station: Station, open: [(repo: String, pr: OpenPR)], feed: [(repo: String, e: FeedEvent)],
                        moved: inout Bool) -> [WorldEvent] {
        var events: [WorldEvent] = []
        let cfg = ConfigStore.shared.current
        for (root, info) in repoRoots.sorted(by: { $0.key < $1.key }) where info.station == station.name && cfg.crewEnabled(repo: info.repo) {
            guard github.teamOpenPRs(repoRoot: root) != nil else { continue }   // not answered yet: nothing has gone
            let bots = open.filter { $0.repo == info.repo && $0.pr.isBot }
            let (arrived, gone) = station.ledger.adoptDecon(open: bots.map(\.pr.number), repo: info.repo)
            if !arrived.isEmpty { moved = true }
            if !arrived.isEmpty, isReady(info.repo) { events.append(.deconArrived(station: station.name, repo: info.repo, numbers: arrived)) }
            for n in arrived where isReady(info.repo) {
                let title = bots.first { $0.pr.number == n }?.pr.title ?? ""
                events.append(.log("\(Words.current.unidentified) #\(n) in \(Words.current.inDecon) · \(title.prefix(48))"))
            }
            for n in gone {
                var state: String?
                if feed.contains(where: { $0.repo == info.repo && $0.e.kind == "pr_close" && $0.e.prNumber == n }) { state = "CLOSED" }
                else if feed.contains(where: { $0.repo == info.repo && $0.e.kind == "pr_merge" && $0.e.prNumber == n }) { state = "MERGED" }
                else {
                    github.refresh(pull: n, repoRoot: root)
                    if github.pullAnswered(number: n, repoRoot: root) { state = github.pull(number: n, repoRoot: root)?.state }
                }
                guard let state else { continue }
                moved = true
                if state == "MERGED", station.hasPad {
                    station.ledger.order(repo: info.repo, number: n, to: .storage)
                    events.append(.deconCleared(station: station.name, repo: info.repo, number: n))
                    report(crate: n, repo: info.repo, .stored, by: .pulls)
                } else {
                    station.ledger.forget(repo: info.repo, number: n)
                    events.append(.log("#\(n) \(Words.current.ejected)" + (state == "MERGED" ? "" : ", never cleared")))
                }
            }
        }
        return events
    }

    // MARK: peers

    /// This machine's own name on the local network, for the tie-break below. Empty until sharing starts.
    var peerName = ""

    /// A peer's claim lands on our work station: its offices get the same key here, adopting the
    /// peer's floor plan when that floor is free. A whole peer arriving fades in; one new checkout
    /// on a peer we already follow earns a shuttle, like a new session of our own.
    func applyPeer(_ snap: PeerSnapshot, now: Date) -> [WorldEvent] {
        var events: [WorldEvent] = []
        let isNewPeer = peerFirstSeen[snap.name] == nil
        if isNewPeer { peerFirstSeen[snap.name] = now; events.append(.peerArrived(snap.name)) }
        let bulk = isNewPeer || now.timeIntervalSince(peerFirstSeen[snap.name]!) < 15
        let previousSnap = peerSnapshots[snap.name]?.snap
        peerSnapshots[snap.name] = (snap, now)
        let station = fleet.station("work")
        let sk = station.name + "|"
        var changed = false
        var markers = false   // a peer says the same thing every few seconds: only a difference is worth a redraw
        let cfg = ConfigStore.shared.current
        let mine = Set(peerOffices.filter { $0.value[snap.name] != nil }.map(\.key))
        var live: Set<String> = []
        var disputed: [(key: String, cells: [Cell])] = []
        for o in snap.offices where cfg.repos[o.repo]?.station != "hidden" && !isKicked(sk + o.key) {
            works.note(repo: o.repo, branch: o.branch, pull: o.pull, pullState: o.pullState)
            let key = sk + o.key
            live.insert(key)
            let before = peerOffices[key]?[snap.name]
            peerOffices[key, default: [:]][snap.name] = o
            // What the floor draws from the claim: the power on the tiles, the pull request on the package.
            if before?.dim != o.dim { changed = true }
            if before?.pull != o.pull || before?.pullState != o.pullState || before?.checks != o.checks || before?.review != o.review { markers = true }
            if o.pushed, pushedByPeer.insert(key).inserted { changed = true }   // an outline becomes a room
            let boxesBefore = peerBoxes[key]?.count
            if o.boxes > 0 || o.pull != nil { peerBoxes[key] = (max(1, o.boxes), o.pullState ?? "NONE", o.color) } else { peerBoxes[key] = nil }
            if peerBoxes[key]?.count != boxesBefore { markers = true }
            if let r = station.rooms[o.key] {
                r.lastActive = max(r.lastActive, o.lastActive, now)
                if r.worktree == nil, crewRoomInfo[key] == nil, r.name != o.name { r.name = o.name; changed = true }
                // The same room in two places: both placed it before hearing the other. The lower name's
                // cells stand; the other side takes them, so the two stations agree within one round.
                if r.cells != o.cells, !o.cells.isEmpty, snap.name < peerName { disputed.append((o.key, o.cells)) }
                continue
            }
            let color = fleet.color(forRepo: o.repo)
            guard station.ensureRoom(key: o.key, name: o.name, repo: o.repo, color: color, lastActive: now, preferredCells: o.cells) else { continue }
            changed = true
            if !bulk, now.timeIntervalSince(o.startedAt) < 3 * 60 {
                events.append(.officeOpened(station: station.name, key: o.key, source: .peer(snap.name), arrival: .shuttle))
                report(office: o.key, repo: o.repo, .inbound, by: .neighbour, at: o.startedAt)
                events.append(.log("\(snap.name) started \(o.name)"))
            } else {
                events.append(.officeOpened(station: station.name, key: o.key, source: .peer(snap.name), arrival: .fade))
            }
        }
        if station.replaceRooms(disputed) {
            changed = true
            events.append(.log("\(disputed.count) office\(disputed.count == 1 ? " stands" : "s stand") where \(snap.name) put \(disputed.count == 1 ? "it" : "them")"))
        }
        for key in mine where !live.contains(key) {
            peerOffices[key]?[snap.name] = nil
            if peerOffices[key]?.isEmpty == true { peerOffices[key] = nil; if peerBoxes.removeValue(forKey: key) != nil { markers = true } }
        }
        // Someone starting or stopping work in an office changes whether it is outlined.
        func working(_ s: PeerSnapshot?) -> Set<String> { Set((s?.minions ?? []).filter { !$0.asleep }.map { sk + $0.office }) }
        if working(previousSnap) != working(snap) { changed = true }
        if changed { events.append(.layoutChanged) }
        else if markers { events.append(.markersChanged) }

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
        /// A bot's pull request, of unknown origin: grey, whichever yard it stands in.
        let alien: Bool
        /// Your own work: strapped in white, so your crates pick out of a row of them.
        var mine = false
        let group: Int; let column: Int; let level: Int
        let cell: Cell; let pos: SIMD3<Double>; let yaw: Double
        /// Not standing here: on its way in, its place spoken for. The rows do not draw it and nothing
        /// else is put there.
        var carried = false
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

    /// Where every crate stands in storage or on the deck, from the ledger's rows, so a carrier can be
    /// sent to the exact spot a crate will occupy and nothing jumps when the layout is redrawn.
    /// Every other row holds crates with aisles between; the deck keeps tested crates on the row nearest
    /// the pad and untested on the far row; within a row, crates group by repository in stacks of three.
    /// A crate keeps the place its row records until it leaves; a crate bound for the yard holds the
    /// place spoken for ahead of it and comes back `carried`. A crate with no place yet is given one
    /// here and the row remembers it. `stillUntested` keeps one deck crate in the untested row even
    /// though the board has cleared it: that is where it still stands. `aside` names crates
    /// ("repo#number") to give a fresh place away from the column they stand in.
    func yardLayout(station: Station, area: String, stillUntested: Int? = nil, aside: [String: Int] = [:]) -> [YardSlot] {
        let cells = area == "deck" ? station.deckCells : area == "decon" ? station.deconCells : station.storageCells
        let neat = area != "storage"
        let yard: Yard = area == "deck" ? .deck : area == "decon" ? .decon : .storage
        guard !cells.isEmpty else { return [] }
        let rows = Set(cells.map(\.y)).sorted()
        // Every other row holds crates with aisles between. In decon the objects stand along the back
        // wall by the hatch, and the row by storage is the aisle a carrier reaches them from.
        let crateRows = area == "decon" ? Set(rows.suffix(1)) : Set(rows.enumerated().filter { $0.offset % 2 == 0 }.map(\.element))
        // Storage keeps the pallet's lane out of its doorway free: no crate is ever given one of those cells.
        let lane = area == "storage" ? station.palletLane : []
        let sorted = cells.filter { crateRows.contains($0.y) && !lane.contains($0) }.sorted { ($0.y, $0.x) < ($1.y, $1.x) }
        let rowList = crateRows.sorted()
        let testedRow = sorted.filter { $0.y == rowList.first }, untestedRow = sorted.filter { $0.y == rowList.last }
        func row(_ group: Int) -> [Cell] { area == "deck" && rowList.count > 1 ? (group == 0 ? testedRow : untestedRow) : sorted }

        struct Entry { let crate: Ledger.Crate; let group: Int; let cleared: Bool; let carried: Bool; let index: Int; var slot: Ledger.Slot? }
        var entries: [Entry] = []
        for repo in Set(station.ledger.crates.values.map(\.repo)).sorted() {
            let mine = station.ledger.crates(of: repo).filter { $0.stands(in: yard) || $0.heading == yard }.prefix(48)
            for (k, c) in mine.enumerated() {
                let carried = !c.stands(in: yard)
                var cleared = area == "deck" && c.cleared
                if cleared, c.number == stillUntested { cleared = false }
                let group = (area == "deck" && rowList.count > 1) ? (cleared ? 0 : 1) : 0
                var slot = carried ? c.bound : c.slot
                if let s = slot, s.yard != yard || s.group != group { slot = nil }   // from another yard or row: asked for again
                if aside["\(repo)#\(c.number)"] != nil { slot = nil }
                entries.append(Entry(crate: c, group: group, cleared: cleared, carried: carried, index: k, slot: slot))
            }
        }
        // Decon shows a dozen objects at most, the oldest first; the rest are counted, not stacked to the ceiling.
        if area == "decon" { entries = Array(entries.sorted { $0.crate.number < $1.crate.number }.prefix(12)) }
        // Places already held come first, so a newcomer sees them; then each crate without one is given one.
        var held: [(repo: String, slot: Ledger.Slot)] = entries.compactMap { e in e.slot.map { (e.crate.repo, $0) } }
        for i in entries.indices where entries[i].slot == nil {
            let e = entries[i]
            let slot = Ledger.place(repo: e.crate.repo, in: yard, group: e.group, among: held, cap: row(e.group).count * 2,
                                    avoiding: aside["\(e.crate.repo)#\(e.crate.number)"], tall: area == "decon")
            entries[i].slot = slot
            held.append((e.crate.repo, slot))
            if e.carried { station.ledger.setBound(repo: e.crate.repo, number: e.crate.number, slot) }
            else { station.ledger.setSlot(repo: e.crate.repo, number: e.crate.number, slot) }
        }
        // Levels: rank within the column by the order each crate was given, so a stack settles from the floor.
        var out: [YardSlot] = []
        for e in entries {
            let s = e.slot!
            let level = held.filter { $0.slot.group == s.group && $0.slot.column == s.column && $0.slot.order < s.order }.count
            let cellsOfRow = row(s.group)
            let cell = cellsOfRow[min(s.column / 2, cellsOfRow.count - 1)], side = Double(s.column % 2) * 0.5 - 0.25
            let (jx, jz, yaw) = neat ? (0, 0, 0) : World.jitter(repo: e.crate.repo, number: e.crate.number)
            // The rows leave the pallet's lane empty, but the lane is only as wide as the slab, so an
            // untidy crate beside it could lean over the line. The nudge is taken back to the edge.
            var x = Double(cell.x) + side + jx
            if !lane.isEmpty, let lo = lane.map(\.x).min(), let hi = lane.map(\.x).max() {
                let edge = 0.3   // a crate's own half, and a hair
                if x > Double(lo) - 0.5 - edge && x < Double(hi) + 0.5 + edge {
                    x = x < (Double(lo) + Double(hi)) / 2 ? Double(lo) - 0.5 - edge : Double(hi) + 0.5 + edge
                }
            }
            let pos = SIMD3(station.offset.x + x, Double(level) * 0.34, station.offset.y + Double(cell.y) + jz)
            out.append(YardSlot(repo: e.crate.repo, number: e.crate.number, index: e.index, cleared: e.cleared, alien: e.crate.alien,
                                mine: !e.crate.alien && github.isMine(repo: e.crate.repo, number: e.crate.number), group: s.group,
                                column: s.column, level: level, cell: cell, pos: pos, yaw: yaw, carried: e.carried))
        }
        return out
    }

    /// A little disorder in storage, seeded per crate so a crate keeps its own nudge and turn wherever
    /// it lands in the rows.
    private static func jitter(repo: String, number: Int) -> (Double, Double, Double) {
        var seed = stableHash("\(repo)#\(number)") | 1
        func rnd() -> Double { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Double(seed >> 11) / Double(1 << 53) }
        return ((rnd() - 0.5) * 0.22, (rnd() - 0.5) * 0.3, (rnd() - 0.5) * 0.7)
    }

    /// Brings the yard in line with the source, one crate at a time. The source's answer is taken into
    /// the ledger first; then every crate the two sides disagree about is either handed to a carrier,
    /// storage across to the deck, or, where no carry exists, redrawn where the source says. A crate
    /// already under way is left to its carrier; a pallet holds its whole repository; and a deck a
    /// rocket is about to load from keeps its crates.
    @discardableResult
    func reconcile(station: Station, repo: String, root: String, cargo c: GitHubResolver.Cargo) -> YardChange {
        let k = station.name + "|" + repo
        // A repository whose merges ship has no release and no board word about its crates: the floor's
        // own moves are the only truth, and an empty answer must not take a crate off the pad before it goes.
        if github.pipeline(repoRoot: root).shipsOnMerge { return .snapped }
        for n in c.storageNumbers { report(crate: n, repo: repo, .stored, by: c.source, at: c.updated[n] ?? Date()) }
        // One word per crate: the deck's count carries the cleared ones too, and QA said after cleared would take them back.
        for n in c.deckNumbers where !c.clearedNumbers.contains(n) { report(crate: n, repo: repo, .qa, by: c.source, at: c.updated[n] ?? Date()) }
        for n in c.clearedNumbers { report(crate: n, repo: repo, .cleared, by: c.source, at: c.updated[n] ?? Date()) }
        // The ledger hears the record, not the counts: where each piece of work is by the record's word,
        // whoever said it, and when it was last moved on. The counts above were only signals into it.
        station.ledger.adopt(yardWord(repo: repo, station: station), repo: repo)
        // The pallet is the hand carry for this repository from the moment one is ordered: nothing
        // else moves its crates until it has been emptied.
        guard truth.pallets[station.name]?.repo != repo,
              truth.palletQueue[station.name]?.contains(where: { $0.repo == repo }) != true else { return .waiting }
        let open = station.ledger.disagreements(repo: repo)
        guard !open.isEmpty else { return .snapped }
        // A crate the source wants on the deck is carried there on the record's word, in the drain; what
        // is left disagreeing here is snapped, and a crate on its way keeps its carry.
        if open.contains(where: { $0.placed == .storage && $0.wanted == .deck && $0.heading == .deck }) { return .waiting }
        let launching = rocketBusy(k) || github.hasPendingLaunch(repoRoot: root) || (github.openReleases(repoRoot: root)?.contains(where: \.isProduction) ?? false)
        for crate in open {
            if launching, crate.placed == .deck { continue }   // the rocket takes these; the source's word comes after
            station.ledger.snap(repo: repo, number: crate.number)
        }
        return .snapped
    }

    /// The record's word about a repository's crates, in the yard's terms: stored is storage, QA and
    /// cleared are the deck, shipped is gone, and a crate is cleared from cleared on.
    func yardWord(repo: String, station: Station) -> Ledger.Word {
        var word = Ledger.Word(storage: [], deck: [])
        // Without a staging area there is no deck: QA and cleared work waits in storage like the rest.
        let deck = stagingIsDeck(station: station.name, repo: repo)
        for r in works.records(repo: repo) {
            guard let n = r.number, let stage = r.stage else { continue }
            switch stage {
            case .stored: word.storage.append(n)
            case .qa, .cleared: if deck { word.deck.append(n) } else { word.storage.append(n) }
            default: continue
            }
            if stage >= .cleared { word.cleared.append(n) }
            if let at = r.stagedAt { word.updated[n] = at }
        }
        return word
    }

    // MARK: places, asked for

    /// The place a crate bound for a yard will land on, asked for now: the row holds it from the
    /// first ask. Storage or the deck by the rows; the rocket by its hatch.
    func slotNow(for crate: CrateRef, toward yard: Yard) -> Spot? {
        guard let station = fleet.stations[crate.station] else { return nil }
        switch yard {
        case .storage, .deck, .decon:
            let area = yard == .deck ? "deck" : yard == .decon ? "decon" : "storage"
            let plain: Spot.Area = yard == .deck ? .deck : yard == .decon ? .decon : .storage
            let layout = yardLayout(station: station, area: area)
            guard let s = layout.first(where: { $0.repo == crate.repo && $0.number == crate.number }) else {
                return floorSpot(plain, station: station, repo: crate.repo,
                                 cell: (yard == .deck ? station.deckCells : yard == .decon ? station.deconCells : station.storageCells).first ?? Cell(x: 0, y: 0))
            }
            return yardSpot(s.cleared ? .tested : plain, station: station, repo: crate.repo, slot: grounded(s, in: layout))
        case .pad:
            return padSpot(station: station, repo: crate.repo)
        }
    }

    /// On the floor in front of the loading hatch, on the deck side of the hull: an ordinary set-down.
    /// Where a crate for a rocket goes: at the foot of that repository's own rocket, in front of it,
    /// and the carrier stands on the tile in front of that. The rocket's place on the pad is the same
    /// rule the scene draws it by: repositories with a rocket, in name order, on the pad's slots.
    static let padSlotOffsets: [SIMD2<Double>] = [SIMD2(0, 0), SIMD2(1.3, 0), SIMD2(-1.3, 0), SIMD2(0, 1.2)]
    func padSpot(station: Station, repo: String) -> Spot {
        let slot = padRockets().sorted().firstIndex(of: station.name + "|" + repo) ?? 0
        let pc = station.padCenter + World.padSlotOffsets[slot % World.padSlotOffsets.count]
        // The foot: a tile's length before the hull, so the tile it rounds to is clear of the rocket and the
        // carrier can stand on it, an arm's length back, and the crate goes down between them and the hull.
        let foot = SIMD2(pc.x, pc.y + 1.05)
        let stand = Cell(x: Int(foot.x.rounded()), y: Int(foot.y.rounded()))
        let cell = station.padCells.contains(stand) ? stand : (station.padCells.first ?? Cell(x: 0, y: 0))
        return Spot(area: .pad, station: station.name, owner: repo, label: repo, cell: cell,
                    pos: SIMD3(station.offset.x + foot.x, 0, station.offset.y + foot.y))
    }

    /// Stacks are built from the ground up. If a landing place has come out with air under it, a crate
    /// under it still on someone's arms, the crate lands on the lowest free level of the column instead.
    private func grounded(_ slot: YardSlot, in layout: [YardSlot]) -> YardSlot {
        let column = layout.filter { $0.group == slot.group && $0.column == slot.column && $0.number != slot.number && !$0.carried }
        let taken = Set(column.map(\.level))
        var level = slot.level
        while level > 0 && !taken.contains(level - 1) { level -= 1 }
        while taken.contains(level) { level += 1 }
        guard level != slot.level else { return slot }
        return YardSlot(repo: slot.repo, number: slot.number, index: slot.index, cleared: slot.cleared, alien: slot.alien, mine: slot.mine,
                        group: slot.group, column: slot.column, level: level, cell: slot.cell,
                        pos: SIMD3(slot.pos.x, Double(level) * 0.34, slot.pos.z), yaw: slot.yaw, carried: slot.carried)
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

    /// The spot a crate stands on in a yard right now, for a carry's `from`.
    private func standingSpot(_ s: YardSlot, area: String, station: Station) -> Spot {
        yardSpot(area == "deck" ? (s.cleared ? .tested : .deck) : area == "decon" ? .decon : .storage, station: station, repo: s.repo, slot: s)
    }

    // MARK: commands the reconciler issues

    /// Stacks are taken from the top. Whatever stands on `slot` in its column and is not itself going
    /// is moved aside first, top down, each to a fresh place on another of the repository's columns in
    /// the same yard: a carry within the yard. Nothing is ever pulled out from under another crate.
    private func aside(station: Station, area: String, above slot: YardSlot, going: Set<Int>, standing: [YardSlot], after: inout [Int: Int]) -> [Command] {
        let blockers = standing.filter { $0.group == slot.group && $0.column == slot.column && $0.level > slot.level && !going.contains($0.number) }
            .sorted { $0.level > $1.level }
        guard !blockers.isEmpty else { return [] }
        let yard: Yard = area == "deck" ? .deck : area == "decon" ? .decon : .storage
        let moved = yardLayout(station: station, area: area, aside: Dictionary(uniqueKeysWithValues: blockers.map { ("\($0.repo)#\($0.number)", $0.column) }))
        var out: [Command] = []
        for b in blockers {
            guard moved.contains(where: { $0.repo == b.repo && $0.number == b.number }) else { continue }
            let crate = CrateRef(station: station.name, repo: b.repo, number: b.number)
            station.ledger.order(repo: b.repo, number: b.number, to: yard)
            let command = Command.carry(crate, from: standingSpot(b, area: area, station: station), to: yard, after: after[b.column].map { [$0] } ?? [])
            after[b.column] = command.id
            out.append(command)
        }
        return out
    }

    /// Storage crates the source says reached staging, by number: one carry each to the deck, the
    /// deck holding a place for each from the order, blockers moved aside first.
    func carryToDeck(station: Station, repo: String, numbers: [Int]) -> [Command] {
        let wanted = Set(numbers)
        let standing = yardLayout(station: station, area: "storage").filter { $0.repo == repo && !$0.carried }
        let going = standing.filter { wanted.contains($0.number) }.sorted { ($0.level, $0.index) > ($1.level, $1.index) }
        guard !going.isEmpty else { return [] }
        var out: [Command] = []
        var above: [Int: Int] = [:]     // per storage column: the carry that has to clear it before the crate under moves
        var landed: [String: Int] = [:] // per deck place: the carry whose crate has to be down before anything is set on top
        for slot in going { out += aside(station: station, area: "storage", above: slot, going: wanted, standing: standing, after: &above) }
        for slot in going {
            let crate = CrateRef(station: station.name, repo: repo, number: slot.number)
            station.ledger.order(repo: repo, number: slot.number, to: .deck)
            guard let to = slotNow(for: crate, toward: .deck) else { continue }
            let column = "\(Int((to.pos.x * 100).rounded()))|\(Int((to.pos.z * 100).rounded()))"
            var waits: [Int] = []
            if let clear = above[slot.column] { waits.append(clear) }
            if to.level > 0, let under = landed["\(column)|\(to.level - 1)"] { waits.append(under) }
            let command = Command.carry(crate, from: standingSpot(slot, area: "storage", station: station), to: .deck, after: waits)
            above[slot.column] = command.id
            landed["\(column)|\(to.level)"] = command.id
            out.append(command)
        }
        return out
    }

    /// What a pallet takes: every crate of a repository standing in storage, top of each stack first,
    /// a pallet's worth at most. Anything already on someone's arms stays where it is.
    func palletCargo(station: Station, repo: String) -> [(crate: CrateRef, from: Spot)] {
        yardLayout(station: station, area: "storage").filter { $0.repo == repo && !$0.carried }
            .sorted { ($0.level, $0.index) > ($1.level, $1.index) }
            .map { (CrateRef(station: station.name, repo: repo, number: $0.number), standingSpot($0, area: "storage", station: station)) }
            .prefix(PalletGeometry.capacity).map { $0 }
    }

    /// Where one crate stands in storage right now, if it is on the rows and not on anyone's arms.
    /// The rows are re-laid every time a crate leaves them, so a place asked for earlier goes stale.
    func storageSpot(station: Station, crate: CrateRef) -> Spot? {
        guard let s = yardLayout(station: station, area: "storage")
            .first(where: { $0.repo == crate.repo && $0.number == crate.number && !$0.carried }) else { return nil }
        return standingSpot(s, area: "storage", station: station)
    }

    /// A merged office's package, from the office door to storage. Storage holds a place for it from
    /// the order; the place itself is asked for with the crate on the arms.
    func carryToStorage(station: Station, room: Room, repo: String, number: Int) -> Command {
        station.ledger.order(repo: repo, number: number, to: .storage)
        let door = station.doorCell(of: room.key) ?? room.cells.first ?? Cell(x: 0, y: 0)
        let from = Spot(area: .office, station: station.name, owner: room.key, label: room.name, cell: door,
                        pos: SIMD3(station.offset.x + Double(door.x), 0, station.offset.y + Double(door.y)))
        return .carry(CrateRef(station: station.name, repo: repo, number: number), from: from, to: .storage)
    }

    /// An object cleared from decon, from where it stands to storage next door. Pulled straight out,
    /// wherever it is in its stack: nobody is careful with unscreened things, and whatever was on top
    /// drops. Nil when it is not standing there: on someone's arms already, or never drawn.
    func carryFromDecon(station: Station, repo: String, number: Int) -> Command? {
        guard let here = yardLayout(station: station, area: "decon").first(where: { $0.repo == repo && $0.number == number && !$0.carried }) else { return nil }
        station.ledger.order(repo: repo, number: number, to: .storage)
        return .carry(CrateRef(station: station.name, repo: repo, number: number), from: standingSpot(here, area: "decon", station: station), to: .storage)
    }

    /// One crate passed QA: across the aisle to the tested row. A named crate, so whatever is stacked on
    /// top of it moves aside first.
    func carryToTested(station: Station, repo: String, number: Int) -> [Command] {
        let crate = CrateRef(station: station.name, repo: repo, number: number)
        guard !isCarried(crate) else { return [] }
        let standing = yardLayout(station: station, area: "deck", stillUntested: number).filter { !$0.carried }
        guard let here = standing.first(where: { $0.repo == repo && $0.number == number }) else { return [] }
        var above: [Int: Int] = [:]
        var out = aside(station: station, area: "deck", above: here, going: [number], standing: standing, after: &above)
        station.ledger.order(repo: repo, number: number, to: .deck)
        out.append(.carry(crate, from: standingSpot(here, area: "deck", station: station), to: .deck, after: above[here.column].map { [$0] } ?? []))
        return out
    }

    /// Cleared to launch: every crate named goes from its row into the rocket on the pad, stacks taken
    /// from the top down.
    func carryToPad(station: Station, repo: String, from area: String, numbers: [Int]) -> [Command] {
        let slots = yardLayout(station: station, area: area).filter { !$0.carried }
        let order = numbers.sorted { a, b in
            let sa = slots.first { $0.repo == repo && $0.number == a }, sb = slots.first { $0.repo == repo && $0.number == b }
            return (sa?.level ?? 0, a) > (sb?.level ?? 0, b)
        }
        var out: [Command] = []
        var above: [Int: Int] = [:]
        for number in order {
            let slot = slots.first { $0.repo == repo && $0.number == number }
            let from = slot.map { standingSpot($0, area: area, station: station) }
                ?? floorSpot(area == "deck" ? .deck : .storage, station: station, repo: repo, cell: station.padCells.first ?? Cell(x: 0, y: 0))
            let key = (slot?.group ?? 0) * 1000 + (slot?.column ?? 0)
            station.ledger.order(repo: repo, number: number, to: .pad)
            let command = Command.carry(CrateRef(station: station.name, repo: repo, number: number), from: from, to: .pad,
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
        guard station.hasPad, !haulOrdered(office: key) else { return [] }
        guard hasPackage(key) else { nothingToHaul.insert(key); return [] }   // nothing to carry: free to clear at once
        let repo = room.repo ?? "work"
        // A crate is a task: the issue the pull request closes when it closes one, else the pull request
        // itself. With no pull request known there is nothing the yard could hold.
        let pull = room.branch.flatMap { b in room.repoRoot.flatMap { github.pull(branch: b, repoRoot: $0) } }
        let known = works.find(officeKey: room.key, repo: repo)
        guard let prNumber = pull?.number ?? known?.pulls.keys.min(), prNumber > 0 else { nothingToHaul.insert(key); return [] }
        // Git history names pull requests and the board names issues; the register knows which is which.
        let record = works.note(repo: repo, branch: room.branch, folder: room.worktree, issue: pull?.closes.first, pull: prNumber, pullState: pull?.state)
        guard let number = record.number else { return [] }
        haulOrdered(office: key, crate: CrateRef(station: station.name, repo: repo, number: number))
        works.report(record, .stored, by: .pulls)
        return [.officeMerged(station: station.name, key: room.key, repo: repo, number: number)]
    }

    /// When an office's pull request was closed without merging, so its red crate can fade in time.
    private(set) var closedAt: [String: Date] = [:]
    static let closedWindow: TimeInterval = 10 * 60
    func isClosed(_ roomKey: String) -> Bool { closedAt[roomKey] != nil }

    /// Merged offices that had no package on the floor to carry: free to clear at once.
    private var nothingToHaul: Set<String> = []

    /// A completion: a crate is down in a yard by hand, in storage, on the deck, or aboard the rocket
    /// on the pad. The station's word on it from here until the source says something newer.
    func landed(station: Station, repo: String, number: Int, in yard: Yard, at now: Date) {
        station.ledger.landed(repo: repo, number: number, in: yard, at: now)
        fleet.save()
    }

    /// A carry that will not happen after all: the crate stays where it is and its slot ahead is free.
    func unorder(_ crate: CrateRef) {
        fleet.stations[crate.station]?.ledger.unorder(repo: crate.repo, number: crate.number)
    }

}

/// Where and when a GitHub login was last seen, for the Teammates list.
struct SeenPerson: Codable, Equatable {
    var repo: String
    var at: Date

    private static var url: URL { AppSupport.root.appendingPathComponent("Rumkapsel/people.json") }
    static func load() -> [String: SeenPerson] {
        (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode([String: SeenPerson].self, from: $0) } ?? [:]
    }
    static func save(_ people: [String: SeenPerson]) {
        guard let data = try? JSONEncoder().encode(people) else { return }
        Fleet.writing.async { try? data.write(to: url) }
    }
}

extension World {
    fileprivate func seen(_ login: String, in repo: String, at: Date) {
        if let s = seenPeople[login], s.at >= at { return }
        seenPeople[login] = SeenPerson(repo: repo, at: at)
    }
}
