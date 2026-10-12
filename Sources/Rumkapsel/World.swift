import Foundation

final class World {
    let fleet = Fleet()
    let github = GitHubResolver()
    private let demo: Bool
    var simulated = false

    init(demo: Bool) { self.demo = demo }

    static let holdWindow: TimeInterval = 24 * 3600
    static let crewRecent: TimeInterval = 30 * 60
    static let roomsWindow: TimeInterval = 12 * 3600

    // MARK: model state

    private(set) var repoRoots: [String: (repo: String, station: String)] = [:]

    struct CrewRoomInfo { var state: String; var last: Date }
    private(set) var crewRoomInfo: [String: CrewRoomInfo] = [:]
    private(set) var crewBoxes: [String: (count: Int, state: String, color: RGB)] = [:]
    private(set) var peerBoxes: [String: (count: Int, state: String, color: RGB)] = [:]

    private(set) var peerSnapshots: [String: (snap: PeerSnapshot, at: Date)] = [:]
    private var peerFirstSeen: [String: Date] = [:]
    private(set) var peerOffices: [String: [String: PeerSnapshot.Office]] = [:]
    private(set) var pushedByPeer: Set<String> = []

    private var held: [String: Date] = [:]
    private var retired: [String: Date] = [:]
    private(set) var roomCreated: [String: Date] = [:]

    var truth = StationTruth()
    private(set) var officeCrates: [String: CrateRef] = [:]
    let works = WorkBook()
    var pulls: PullRequests { PullRequests(github: github) }
    private var transitions: [(record: WorkBook.Record, t: Transition)] = []

    func office(for record: WorkBook.Record) -> (station: Station, room: Room)? {
        for station in fleet.stations.values {
            for key in record.officeKeys { if let room = station.rooms[key] { return (station, room) } }
        }
        return nil
    }

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
            case .qa where t.from == .cleared:
                continue
            case .qa where t.from != nil:
                guard let info = repoRoots.first(where: { $0.value.repo == record.repo }), let station = fleet.stations[info.value.station],
                      let number = record.number, isReady(record.repo) else { continue }
                guard station.hasPad, !station.hall.deckCells.isEmpty, github.pipeline(repoRoot: info.key).hasStaging else { continue }
                let row = station.ledger[record.repo, number]
                if row?.placed == .deck || row?.heading == .deck { continue }
                guard row?.placed == .storage, !(row?.inTransit ?? false) else { waiting.append((record, t)); continue }
                toDeck[station.name + "|" + record.repo, default: []].append(number)
            case .cleared where t.from != nil:
                guard let info = repoRoots.values.first(where: { $0.repo == record.repo }), let number = record.number, isReady(record.repo) else { continue }
                events.append(.crateCleared(station: info.station, repo: record.repo, number: number))
            case .shipped where t.from != nil:
                guard let (root, info) = repoRoots.first(where: { $0.value.repo == record.repo }).map({ ($0.key, $0.value) }) else { continue }
                if github.pipeline(repoRoot: root).shipsOnTag { continue }
                let key = info.station + "|" + info.repo
                if !t.wasQuiet || padSlotOf[key] != nil { launches.insert(key) }
            default: break
            }
        }
        transitions = waiting
        if !launches.isEmpty { assignPads() }
        for (key, numbers) in toDeck.sorted(by: { $0.key < $1.key }) {
            let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
            guard let station = fleet.stations[parts[0]] else { continue }
            let commands = station.carryToDeck(repo: parts[1], numbers: numbers)
            if !commands.isEmpty { events.append(.carryToDeck(station: station.name, repo: parts[1], commands: commands)) }
        }
        for key in launches.sorted() {
            guard let station = fleet.stations[String(key.split(separator: "|")[0])] else { continue }
            let repo = String(key.split(separator: "|", maxSplits: 1)[1])
            if mergeLaunches.contains(key) || launchedThisPass.contains(key) { continue }
            events.append(wish(.launch, station: station, repo: repo, waiting: cargoWaiting(station: station, repo: repo), cleared: true))
        }
        return events
    }
    private var launchedThisPass: Set<String> = []

    func report(office key: String, repo: String, _ stage: Stage, by source: Source, at: Date = Date()) {
        guard let r = works.find(officeKey: key, repo: repo) else { return }
        works.report(r, stage, by: source, at: at)
    }
    func report(crate n: Int, repo: String, _ stage: Stage, by source: Source, at: Date = Date()) {
        works.report(works.note(repo: repo, crate: n), stage, by: source, at: at)
    }
    func report(pullState state: String?, record: WorkBook.Record?, at: Date = Date()) {
        guard let state, let record else { return }
        works.report(record, PullRequests.stage(for: state), by: .pulls, at: at)
    }
    func isMine(office key: String) -> Bool {
        let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2, let room = fleet.stations[parts[0]]?.rooms[parts[1]] else { return false }
        if room.worktree != nil { return true }
        guard let me = github.myLogin(), let repo = room.repo else { return false }
        return works.find(officeKey: room.key, repo: repo)?.author == me
    }
    func isMine(repo: String, number: Int) -> Bool {
        guard let me = github.myLogin() else { return false }
        return works.find(repo: repo, crate: number)?.author == me || github.isMine(repo: repo, number: number)
    }

    func record(office key: String) -> WorkBook.Record? {
        let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2, let room = fleet.stations[parts[0]]?.rooms[parts[1]], let repo = room.repo else { return nil }
        return works.find(officeKey: room.key, repo: repo)
    }
    func crewPull(_ key: String) -> Int? { crewRoomInfo[key] != nil ? record(office: key)?.pulls.keys.min() : nil }

    func workflow(repo: String) -> Workflow {
        if let w = ConfigStore.shared.current.repos[repo]?.workflow { return w }
        let root = repoRoots.first { $0.value.repo == repo }?.key
        let pipeline = root.map { github.pipeline(repoRoot: $0) } ?? .configured
        return Workflow.detected(pipeline: pipeline, board: ConfigStore.shared.current.project != nil)
    }
    func stage(office key: String, repo: String?) -> Stage? { repo.flatMap { works.find(officeKey: key, repo: $0) }?.stage }

    // MARK: a crate's row, from the floor's side

    func crate(_ c: CrateRef) -> Ledger.Crate? { fleet.stations[c.station]?.ledger[c.repo, c.number] }
    func isCarried(_ c: CrateRef) -> Bool { crate(c)?.isCarried ?? false }
    func area(of c: CrateRef) -> Spot.Area? { crate(c)?.area }
    func carriedCount(station: String, repo: String) -> Int { fleet.stations[station]?.ledger.carriedCount(repo: repo) ?? 0 }
    func aboard(station: String, repo: String) -> Int { fleet.stations[station]?.ledger.aboard(repo: repo) ?? 0 }

    func claim(_ c: CrateRef) { fleet.stations[c.station]?.ledger.claim(repo: c.repo, number: c.number) }
    func pickedUp(_ c: CrateRef, by minion: String) { fleet.stations[c.station]?.ledger.pickedUp(repo: c.repo, number: c.number, by: minion) }
    func setDown(_ c: CrateRef, at spot: Spot) {
        fleet.stations[c.station]?.ledger.setDown(repo: c.repo, number: c.number, at: spot)
    }
    func forgetPlacement(_ c: CrateRef) { fleet.stations[c.station]?.ledger.forgetPlacement(repo: c.repo, number: c.number) }
    func dropped(by minion: String) { for st in fleet.stations.values { st.ledger.dropped(by: minion) } }
    func clearPad(station: String, repo: String) { fleet.stations[station]?.ledger.clearPad(repo: repo) }

    // MARK: office hauls

    func haulOrdered(office key: String, crate: CrateRef) { officeCrates[key] = crate; claim(crate) }
    func haulOrdered(office key: String) -> Bool { officeCrates[key] != nil }
    func haulLanded(office key: String) -> Bool {
        guard let c = officeCrates[key], let row = crate(c), let area = row.area else { return false }
        return area != .office
    }
    func haulUnderway(office key: String) -> Bool { haulOrdered(office: key) && !haulLanded(office: key) }
    func forgetOffice(_ key: String) { officeCrates[key] = nil }

    private(set) var readyRepos: Set<String> = []
    private(set) lazy var seenPeople: [String: SeenPerson] = waitsForGitHub ? SeenPerson.load() : [:]
    private var savedPeople: [String: SeenPerson] = [:]
    private var crewSeen: Set<String> = []
    private var didLoadLayout = false
    private var scans = 0
    private var savedKnowledgeAt = Date.distantPast
    static let officeGraceScans = 10
    var waitsForGitHub = true

    var hasPackage: (String) -> Bool = { _ in false }
    var rocketBusy: (String) -> Bool = { _ in false }
    var stagingUnderway: (String) -> Bool = { _ in false }

    func isReady(_ repo: String?) -> Bool { repo.map { readyRepos.contains($0) } ?? true }

    var allReady: Bool { !repoRoots.isEmpty && repoRoots.values.allSatisfy { readyRepos.contains($0.repo) } }

    var settling: Bool { waitsForGitHub && scans < World.officeGraceScans && !allReady && !knewAlready }

    private var knewAlready: Bool { github.hasAnswers }

    func reset() {
        fleet.removeAllStations()
        repoRoots = [:]
        readyRepos = []
        didLoadLayout = false
    }

    // MARK: queries the scene draws from

    func crewName(_ login: String) -> String { ConfigStore.shared.current.crewNames[login] ?? login }

    func taskNumber(_ room: Room) -> Int? { Work.number(inOfficeKey: room.key) }

    func crewKey(repo: String, branch: String) -> String { Work(repo: repo, branch: branch).officeKey }

    func roomKey(_ station: Station, _ room: Room) -> String { "\(station.name)|\(room.key)" }

    var knownRepos: [String] {
        var names = Set(repoRoots.values.map(\.repo)).union(ConfigStore.shared.current.repos.keys)
        for s in fleet.stations.values { for r in s.rooms.values { if let repo = r.repo { names.insert(repo) } } }
        return names.sorted()
    }

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

    func isRemoteOnly(_ station: Station, _ room: Room) -> Bool {
        let key = roomKey(station, room)
        return room.worktree == nil && (crewRoomInfo[key] != nil || pushedByPeer.contains(key))
    }

    func isProvisional(_ station: Station, _ room: Room) -> Bool {
        let key = roomKey(station, room)
        return !demo && room.worktree == nil && !room.key.hasPrefix("kind:") && crewRoomInfo[key] == nil && !pushedByPeer.contains(key) && !peerLive(key)
    }

    func isUnchecked(_ station: Station, _ room: Room) -> Bool {
        !demo && !room.key.hasPrefix("kind:") && !lookedAt(room.repo)
    }

    var stillLooking: Bool {
        guard waitsForGitHub, scans < World.lookingScans else { return false }
        return repoRoots.isEmpty || repoRoots.keys.contains { !github.answered(repoRoot: $0) }
    }
    static let lookingScans = 60

    func lookedAt(_ repo: String?) -> Bool {
        guard waitsForGitHub else { return true }
        guard let repo else { return true }
        let roots = repoRoots.filter { $0.value.repo == repo }.map(\.key)
        return !roots.isEmpty && roots.contains { github.answered(repoRoot: $0) }
    }

    func peerLive(_ key: String) -> Bool {
        peerSnapshots.values.contains { entry in entry.snap.minions.contains { !$0.asleep && "work|" + $0.office == key } }
    }
    func isLocalLive(_ station: Station, _ room: Room) -> Bool {
        let key = roomKey(station, room)
        return room.worktree == nil && !room.key.hasPrefix("kind:") && crewRoomInfo[key] == nil && !pushedByPeer.contains(key) && peerLive(key)
    }
    func peerDim(_ key: String) -> Bool { peerOffices[key].map { !$0.isEmpty && $0.values.allSatisfy(\.dim) } ?? false }
    func peerPull(_ key: String) -> PeerSnapshot.Office? { peerOffices[key]?.values.first { $0.pull != nil } }

    func occupant(of key: String) -> String? {
        if crewRoomInfo[key] != nil, let author = record(office: key)?.author { return crewName(author) }
        if let peer = peerOffices[key]?.keys.sorted().first { return peer }
        let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
        if parts.count == 2, let room = fleet.stations[parts[0]]?.rooms[parts[1]], room.worktree != nil, room.key.hasPrefix("task:") {
            return github.myLogin().map(crewName) ?? "me"
        }
        return nil
    }

    static let peerQuiet: TimeInterval = 60

    func stalePeers(olderThan seconds: TimeInterval) -> [String] {
        peerSnapshots.filter { Date().timeIntervalSince($0.value.at) > seconds }.map(\.key)
    }

    // MARK: kicking

    private var simKicked: [String: Date] = [:]
    private var kicked: [String: Date] {
        get { simulated ? simKicked : (UserDefaults.standard.dictionary(forKey: "kicked") as? [String: Date]) ?? [:] }
        set {
            let live = newValue.filter { Date().timeIntervalSince($0.value) < World.holdWindow }
            if simulated { simKicked = live } else { UserDefaults.standard.set(live, forKey: "kicked") }
        }
    }

    func isKicked(_ key: String) -> Bool { kicked[key].map { Date().timeIntervalSince($0) < World.holdWindow } ?? false }

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

    private func drop(station: Station, room: Room, announce: Bool, reason: String) -> WorldEvent {
        let event = WorldEvent.officeArchived(station: station.name, key: roomKey(station, room), roomKey: room.key,
                                              name: room.name, hall: station.doorOutside(of: room.key), announce: announce, reason: reason)
        station.removeRoom(key: room.key)
        return event
    }

    // MARK: the session scan

    struct MinionHome { var station: String; var key: String; var idle: Bool }

    private var sessionPrompts: [String: (marker: String, count: Int)] = [:]

    func applyScan(_ result: ScanResult, now: Date, minionHomes: [String: MinionHome]) -> [WorldEvent] {
        var events: [WorldEvent] = []
        var changed = false
        let firstRun = !didLoadLayout
        if firstRun {
            didLoadLayout = true
            works.workflow = { [weak self] repo in self?.workflow(repo: repo) ?? Workflow() }
            works.onTransition = { [weak self] r, t in
                let who = r.number.map { "#\($0)" } ?? r.work().label
                StationLog.write("stage", "\(r.repo) \(who): \(t.from.map { "\($0) → " } ?? "")\(t.to) · \(t.by.rawValue)\(t.back ? " (back)" : "")")
                self?.transitions.append((r, t))
            }
            fleet.load(alone: peerSnapshots.isEmpty)
            if waitsForGitHub { github.loadKnowledge() }
            changed = true
            events.append(.worldLoaded)
        }

        scans += 1
        var sessionRooms: Set<String> = []
        let cfg = ConfigStore.shared.current
        for s in result.sessions where s.cwdExists && Fleet.stationName(for: s.cwd, owner: s.owner, repo: s.repo) != "hidden"
            && (Fleet.stationName(for: s.cwd, owner: s.owner, repo: s.repo) == "work" || now.timeIntervalSince(s.lastModified) < World.roomsWindow) {
            let stationName = Fleet.stationName(for: s.cwd, owner: s.owner, repo: s.repo)
            let station = fleet.station(stationName)
            if let branch = s.branch, now.timeIntervalSince(s.lastModified) > 600 {
                github.refreshCommits(worktree: s.cwd)
                if let current = github.currentBranch(worktree: s.cwd), current != branch { continue }
            }
            let home = homeFor(s, station: stationName)
            sessionRooms.insert("\(stationName)|\(home.key)")
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
                events.append(.officeOpened(station: stationName, key: home.key, source: .session(s.id),
                                            arrival: firstRun || scans <= World.officeGraceScans + 1 ? .appear : .shuttle))
                report(office: home.key, repo: home.repo, .inbound, by: .session, at: s.lastModified)
            }
            if let root = s.repoRoot, !repoRoots.values.contains(where: { $0.repo == s.repo }) {
                repoRoots[root] = (s.repo, stationName)
            }
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
        for station in fleet.stations.values {
            var byWorkspace: [String: [Room]] = [:]
            for room in station.rooms.values where !room.key.hasPrefix("kind:") {
                if stage(office: room.key, repo: room.repo).map({ $0 >= .stored }) == true { continue }
                if let w = room.worktree { byWorkspace[w, default: []].append(room) }
            }
            for (_, rooms) in byWorkspace where rooms.count > 1 {
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
                let pull = pulls.pull(ownOffice: room)
                let state = pull?.state
                if let pull, let repo = room.repo { report(pullState: state, record: works.note(repo: repo, branch: room.branch, folder: room.worktree, issue: pull.closes.first, pull: pull.number, pullState: state)) }
                let merged = stage(office: room.key, repo: room.repo).map { $0 >= .stored } ?? false
                var gone = (room.worktree.map { !Workspaces.isOpen($0) } ?? false) && !haulUnderway(office: key)
                if let w = room.worktree, let branch = room.branch, !sessionRooms.contains(key) {
                    github.refreshCommits(worktree: w)
                    if let current = github.currentBranch(worktree: w), current != branch, !haulUnderway(office: key) { gone = true }
                }
                let closed = state == "CLOSED" && !merged
                if closed, closedAt[key] == nil { closedAt[key] = now; events.append(.log("\(room.name): pull request closed, not merged")) }
                if state != nil, !closed { closedAt[key] = nil }
                if merged, station.hasPad, !haulOrdered(office: key) { events += haulMerged(station: station, room: room) }
                let cleared = (merged && (!station.hasPad || haulLanded(office: key) || nothingToHaul.contains(key)))
                    || (closed && now.timeIntervalSince(closedAt[key] ?? now) > World.closedWindow)
                let unclaimed = room.worktree == nil && crewRoomInfo[key] == nil && peerOffices[key] == nil && isReady(room.repo)
                    && (cfg.project == nil || github.projectItems() != nil)
                let orphan = unclaimed && (held[key].map { now.timeIntervalSince($0) > World.holdWindow } ?? true)
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
            github.refreshDeploys(repoRoot: root)
            github.watchPulls(repoRoot: root)
            if info.station == "work" { github.refreshFeed(repoRoot: root); github.refreshOpenPRs(repoRoot: root) }
        }
        for d in github.takeDeploys() {
            guard let info = repoRoots[d.repoRoot] else { continue }
            if d.production { awaitingDeploy[d.repoRoot] = nil }
            switch d.change {
            case .started(let run, let elapsed):
                events.append(.deployStarted(station: info.station, repo: info.repo, production: d.production, expected: d.usual,
                                             release: run.release, elapsed: elapsed))
            case .ended(_, let outcome):
                events.append(.deployEnded(station: info.station, repo: info.repo, production: d.production, outcome: outcome))
            }
        }
        events += lostDeploys()
        events += applyBoardMoves()
        for change in github.takeStateChanges() {
            for station in fleet.stations.values {
                for room in station.rooms.values where room.branch == change.branch {
                    if let repo = room.repo { works.note(repo: repo, branch: change.branch, issue: change.pr.closes.first, pull: change.pr.number, pullState: change.pr.state) }
                }
            }
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
        events += stationEvents()
        if changed { events.append(.layoutChanged) }
        return events
    }

    func homeFor(_ s: SessionInfo, station: String) -> Home {
        let pr = s.branch.flatMap { b in s.repoRoot.flatMap { github.pull(branch: b, repoRoot: $0) } }
        let home = works.note(repo: s.repo, branch: s.branch, folder: s.cwd, issue: pr?.closes.first, pull: pr?.number, pullState: pr?.state)
            .work(branch: s.branch).home
        if let at = retired["\(station)|\(home.key)"], Date().timeIntervalSince(at) < World.holdWindow {
            return Home(key: "kind:lounge", name: home.name, repo: home.repo, issue: nil)
        }
        return home
    }

    // MARK: github

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

    private var announcedReleases: Set<String> = []
    private var releasesSeen: Set<String> = []

    private var stagingPRs: [String: (number: Int, state: String)] = [:]
    private var stagingSeen: Set<String> = []

    func root(station: String, repo: String) -> String? { repoRoots.first { $0.value.station == station && $0.value.repo == repo }?.key }
    func stagingIsDeck(station: String, repo: String) -> Bool {
        root(station: station, repo: repo).map { github.pipeline(repoRoot: $0).hasStaging } ?? !ConfigStore.shared.current.stagingBranch.isEmpty
    }
    func shipsOnMerge(station: String, repo: String) -> Bool {
        root(station: station, repo: repo).map { github.pipeline(repoRoot: $0).shipsOnMerge } ?? false
    }
    func forgetShipped(station: String, repo: String) {
        guard let st = fleet.stations[station] else { return }
        for c in st.ledger.crates(of: repo) where c.placed == .pad {
            report(crate: c.number, repo: repo, .shipped, by: mergeLaunches.contains(station + "|" + repo) ? .git : .pulls)
            st.ledger.forget(repo: repo, number: c.number)
        }
    }
    var mergeLaunches: Set<String> = []
    func deckInUse(station: String) -> Bool {
        let roots = repoRoots.filter { $0.value.station == station }.map(\.key)
        return roots.isEmpty ? !ConfigStore.shared.current.stagingBranch.isEmpty : roots.contains { github.pipeline(repoRoot: $0).hasStaging }
    }

    private func padRelease(root: String) -> ReleasePR? {
        guard let open = github.openReleases(repoRoot: root) else { return nil }
        let hasProduction = open.contains(where: \.isProduction)
        return open.first { $0.isProduction || (!hasProduction && !github.pipeline(repoRoot: root).hasStaging) }
    }

    func waiting(repo: String, station: String) -> [WorkBook.Record] {
        let from: Stage = stagingIsDeck(station: station, repo: repo) ? .qa : .stored
        return works.records(repo: repo).filter { r in
            guard let stage = r.stage, stage >= from, stage < .shipped else { return false }
            return !r.quiet || r.words[.git] != nil || r.words[.board] != nil
        }
    }
    func clearedToLoad(repo: String, station: String) -> Bool {
        let w = waiting(repo: repo, station: station)
        return !w.isEmpty && (!workflow(repo: repo).has(.cleared) || w.allSatisfy { $0.stage.map { $0 >= .cleared } ?? false })
    }

    func padRockets() -> Set<String> {
        var pads = Set(repoRoots.compactMap { root, info in padRelease(root: root) != nil ? info.station + "|" + info.repo : nil }).union(mergeLaunches)
        for (root, info) in repoRoots where fleet.stations[info.station]?.hasPad == true && !workflow(repo: info.repo).shipped.isEmpty
            && !github.pipeline(repoRoot: root).shipsAtOnce && !waiting(repo: info.repo, station: info.station).isEmpty { pads.insert(info.station + "|" + info.repo) }
        return pads
    }

    private var awaitingDeploy: [String: Date] = [:]

    private func flyAtMerge(repoRoot: String, station: String, repo: String, pr: ReleasePR) -> [WorldEvent] {
        guard let d = github.deploys(repoRoot: repoRoot).first(where: \.production), let newest = d.newest else { return [] }
        let merged = pr.mergedAt ?? Date()
        guard Date().timeIntervalSince(merged) < Deployments.recent else { return [] }
        if let began = newest.startedAt, began > merged.addingTimeInterval(-120) { return [] }
        awaitingDeploy[repoRoot] = Date()
        return [.deployStarted(station: station, repo: repo, production: true, expected: d.usual,
                               release: pr.tag ? pr.title : "#\(pr.number)", elapsed: max(0, Date().timeIntervalSince(merged)))]
    }

    private func lostDeploys() -> [WorldEvent] {
        let now = Date()
        var out: [WorldEvent] = []
        for (root, at) in awaitingDeploy where now.timeIntervalSince(at) > Deployments.findWithin {
            awaitingDeploy[root] = nil
            if let info = repoRoots[root] { out.append(.deployEnded(station: info.station, repo: info.repo, production: true, outcome: .lost)) }
        }
        return out
    }

    private func wish(_ stage: Command.RocketStage, station: Station, repo: String, waiting n: Int, cleared: Bool) -> WorldEvent {
        let status = " · " + (cleared ? Words.current.cleared : Words.current.holding)
        let label = "rocket:\(waitingURL(repo: repo))|\(repo) · \(n) \(n == 1 ? Words.current.crate : Words.current.crates) waiting for a release\(status)"
        return .rocketCommand(station: station.name, repo: repo, label: label, untested: !cleared, tall: stage.rank >= 3, cargo: n,
                              command: .rocket(stage, station: station.name, repo: repo))
    }

    func waitingURL(repo: String) -> String {
        guard let root = repoRoots.first(where: { $0.value.repo == repo })?.key, let owner = github.nameWithOwner(repoRoot: root) else { return "" }
        let p = github.pipeline(repoRoot: root)
        let shipped = github.releases(repoRoot: root)?.first(where: \.tag)?.head ?? p.production
        return shipped.isEmpty ? "https://github.com/\(owner)" : "https://github.com/\(owner)/compare/\(shipped)...\(p.trunk)"
    }

    private func wish(_ stage: Command.RocketStage, station: Station, repo: String, pr: ReleasePR, cleared: Bool? = nil) -> WorldEvent {
        let cleared = cleared ?? !pr.untested
        let status = " · " + (cleared ? Words.current.cleared : Words.current.holding)
        let label = pr.tag ? "rocket:\(pr.url)|\(repo) · \(pr.title) tagged on \(pr.base)\(status)"
            : "rocket:\(pr.url)|\(repo) · \(pr.head) → \(pr.base) · #\(pr.number) \(pr.title)\(status)"
        return .rocketCommand(station: station.name, repo: repo, label: label, untested: !cleared,
                              tall: pr.isProduction, cargo: cargoWaiting(station: station, repo: repo),
                              command: .rocket(stage, station: station.name, repo: repo))
    }

    func cargoWaiting(station: Station, repo: String) -> Int {
        (stagingIsDeck(station: station.name, repo: repo) ? station.staged : station.stored)[repo] ?? 0
    }

    func applyReleases() -> [WorldEvent] {
        var events: [WorldEvent] = []
        var launched: Set<String> = []
        launchedThisPass = []
        assignPads()
        for launch in github.takeLaunches() {
            guard let info = repoRoots[launch.repoRoot], let station = fleet.stations[info.station] else { continue }
            let pr = launch.pr
            events.append(.releaseMerged(station: info.station, repo: info.repo, number: pr.number, base: pr.base,
                                         title: pr.title, isProduction: pr.isProduction))
            events.append(.chime(pr.number))
            guard pr.isProduction else { continue }
            launched.insert(info.station + "|" + info.repo)
            events += flyAtMerge(repoRoot: launch.repoRoot, station: info.station, repo: info.repo, pr: pr)
            for r in waiting(repo: info.repo, station: station.name) {
                works.report(r, .shipped, by: pr.tag ? .git : .pulls, at: pr.mergedAt ?? Date())
                if let n = r.number { report(crate: n, repo: info.repo, .shipped, by: pr.tag ? .git : .pulls, at: pr.mergedAt ?? Date()) }
            }
            for c in station.ledger.crates(of: info.repo) where c.placed == .pad { report(crate: c.number, repo: info.repo, .shipped, by: pr.tag ? .git : .pulls, at: pr.mergedAt ?? Date()) }
            announcedReleases = announcedReleases.filter { !$0.hasPrefix("\(info.station)|\(info.repo)|") }
            events.append(.log(pr.tag ? "\(info.repo) \(Words.current.launchedTo) \(pr.title)"
                                       : "\(info.repo) \(Words.current.launchedTo) \(pr.base): \(pr.title)"))
            events.append(wish(.launch, station: station, repo: info.repo, pr: pr))
            launchedThisPass.insert(info.station + "|" + info.repo)
        }
        for (root, info) in repoRoots {
            guard let station = fleet.stations[info.station], github.openReleases(repoRoot: root) != nil else { continue }
            let quiet = !releasesSeen.contains(root)
            releasesSeen.insert(root)
            let key = info.station + "|" + info.repo
            guard !launched.contains(key) else { continue }
            guard padSlotOf[key] != nil || padRelease(root: root) == nil else { continue }
            guard let pr = padRelease(root: root) else {
                let w = waiting(repo: info.repo, station: station.name)
                guard station.hasPad, !w.isEmpty, !workflow(repo: info.repo).shipped.isEmpty, !mergeLaunches.contains(key),
                      !github.pipeline(repoRoot: root).shipsAtOnce, padSlotOf[key] != nil else { continue }
                let cleared = clearedToLoad(repo: info.repo, station: station.name)
                if !cleared { events += standDown(station: station, repo: info.repo) }
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
            let labelClears = !pr.untested && workflow(repo: info.repo).cleared?.contains(.pulls) == true
            if labelClears { for r in waiting(repo: info.repo, station: station.name) { works.report(r, .cleared, by: .pulls) } }
            let cleared = pr.isProduction && (labelClears || clearedToLoad(repo: info.repo, station: station.name))
            if !cleared { events += standDown(station: station, repo: info.repo) }
            events.append(wish(cleared ? .load(cargoWaiting(station: station, repo: info.repo)) : .standBy,
                               station: station, repo: info.repo, pr: pr, cleared: cleared))
        }
        return events + applyStaging()
    }

    private func standDown(station: Station, repo: String) -> [WorldEvent] {
        let yard: Yard = stagingIsDeck(station: station.name, repo: repo) ? .deck : .storage
        let back = station.ledger.unload(repo: repo, to: yard)
        guard !back.isEmpty else { return [] }
        return [.log("\(repo): not cleared to ship, \(back.count) back off the rocket"), .layoutChanged]
    }

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

    private func applyBoardMoves() -> [WorldEvent] {
        let st = ConfigStore.shared.current.statuses
        return github.takeProjectMoves().map { .boardMoved(item: $0.item, from: $0.from, to: st.stage(of: $0.item.status)) }
    }

    static let placementsPerPass = 1
    private(set) var placementsLeft = false

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
            for pr in github.teamOpenPRs(repoRoot: root) ?? [] where !Work.longLived.contains(pr.branch) {
                let checkedOutHere = station.rooms.values.contains { $0.worktree != nil && $0.repo == info.repo && ($0.branch == pr.branch || $0.key == Work(repo: info.repo, branch: pr.branch, pull: pr.number).officeKey) }
                if pr.author != me || !checkedOutHere { open.append((info.repo, pr)) }
            }
            for e in github.feed(repoRoot: root) ?? [] where e.actor != me { feed.append((info.repo, e)) }
        }
        var boardOffices: [(repo: String, item: ProjectItem, login: String)] = []
        if cfg.project != nil, !me.isEmpty, let items = github.projectItems() {
            let workRepos = Set(repoRoots.values.filter { $0.station == "work" && cfg.crewEnabled(repo: $0.repo) }.map(\.repo))
            var branched: Set<String> = []
            let recent = now.addingTimeInterval(-14 * 24 * 3600)
            for (repo, e) in feed.sorted(by: { $0.e.at < $1.e.at }) where e.at > recent {
                guard let b = e.branch, let n = Work.issue(inBranch: b, repo: repo) else { continue }
                switch e.kind {
                case "push", "branch_create", "pr_open": branched.insert("\(repo)#\(n)")
                case "branch_delete", "pr_close", "pr_merge": branched.remove("\(repo)#\(n)")
                default: break
                }
            }
            for it in items where it.status == cfg.statuses.development && workRepos.contains(it.repo) {
                if it.isClosed { continue }
                let key = Work(repo: it.repo, issue: it.number).officeKey
                guard let login = it.assignees.first, login != me else { continue }
                if open.contains(where: { $0.repo == it.repo && crewKey(repo: $0.repo, branch: $0.pr.branch) == key }) { continue }
                let working = !it.prURLs.isEmpty || branched.contains("\(it.repo)#\(it.number)") || peerOffices[sk + key] != nil || station.rooms[key]?.worktree != nil
                guard working else { continue }
                boardOffices.append((it.repo, it, login))
            }
        }
        for old in ["kind:bots", "kind:mail"] where station.rooms[old] != nil { station.removeRoom(key: old); changed = true }
        var deconMoved = false
        events += screen(station: station, open: open, feed: feed, moved: &deconMoved)
        let inDecon = station.ledger.allCrates.contains { $0.alien && $0.placed == .decon }
        guard !open.isEmpty || !feed.isEmpty || !boardOffices.isEmpty || inDecon else {
            if changed || deconMoved { events.append(changed ? .layoutChanged : .markersChanged) }
            noteAnswered()
            return events
        }

        func work(_ repo: String, _ pr: OpenPR) -> Work { pr.author == me ? Work(repo: repo, branch: pr.branch, pull: pr.number) : Work(repo: repo, branch: pr.branch) }
        var liveKeys = Set(open.filter { !$0.pr.isBot }.map { work($0.repo, $0.pr).officeKey })
        liveKeys.formUnion(boardOffices.map { Work(repo: $0.repo, issue: $0.item.number).officeKey })
        for k in liveKeys where crewRoomInfo[sk + k] != nil { closedAt[sk + k] = nil }
        for room in Array(station.rooms.values) where crewRoomInfo[sk + room.key] != nil && !liveKeys.contains(room.key) {
            let key = sk + room.key
            let known = room.repo.flatMap { works.find(officeKey: room.key, repo: $0) }
            let author = known?.author ?? ""
            guard room.worktree == nil else { crewRoomInfo[key] = nil; crewBoxes[key] = nil; continue }
            var hauling = false
            let root = repoRoots.first { $0.value.repo == room.repo }?.key
            guard let state = pulls.state(crewOffice: room, known: known, repoRoot: root, feed: feed) else { continue }
            if state == "NONE" {
                if peerOffices[key] != nil { continue }
                closedAt[key] = nil
                crewRoomInfo[key] = nil; crewBoxes[key] = nil
                events.append(drop(station: station, room: room, announce: false, reason: "no longer in development"))
                changed = true
                continue
            }
            if let repo = room.repo { report(pullState: state, record: known?.pulls.keys.min().map { works.note(repo: repo, pull: $0, pullState: state) } ?? known) }
            crewRoomInfo[key]?.state = state
            let closedUnmerged = !(stage(office: room.key, repo: room.repo).map { $0 >= .stored } ?? false)
            if closedUnmerged {
                if let n = known?.number { station.ledger.forget(repo: room.repo ?? "", number: n) }
                if closedAt[key] == nil { closedAt[key] = now; events.append(.log("\(room.name): pull request closed, not merged")) }
                if now.timeIntervalSince(closedAt[key] ?? now) < World.closedWindow { continue }
            } else if !haulOrdered(office: key), station.hasPad {
                let merged = haulMerged(station: station, room: room)
                hauling = !merged.isEmpty
                events += merged
                if isReady(room.repo) { events.append(.pullRequestClosed(repo: room.repo ?? "", author: author, roomKey: room.key)) }
            }
            guard !station.hasPad || !(hauling || haulUnderway(office: key)) else { continue }
            closedAt[key] = nil
            crewRoomInfo[key] = nil; crewBoxes[key] = nil
            events.append(drop(station: station, room: room, announce: isReady(room.repo), reason: "pull request closed"))
            changed = true
        }
        for (repo, pr) in open where !pr.isBot && !isKicked(sk + work(repo, pr).officeKey) {
            let record = works.note(repo: repo, branch: pr.branch, pull: pr.number, pullState: "OPEN", author: pr.author, title: pr.title, url: pr.url)
            works.report(record, .ready, by: .pulls, at: pr.createdAt)
            let home = work(repo, pr).home
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

        var logins = Set(open.filter { !$0.pr.isBot && $0.pr.author != me }.map(\.pr.author))
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
        noteAnswered()
        return events
    }

    private func noteAnswered() {
        let before = readyRepos.count
        for (root, info) in repoRoots where info.station == "work" && github.teamOpenPRs(repoRoot: root) != nil { readyRepos.insert(info.repo) }
        if waitsForGitHub, readyRepos.count != before || Date().timeIntervalSince(savedKnowledgeAt) > 60 {
            savedKnowledgeAt = Date()
            github.saveKnowledge(repoRoots.mapValues(\.repo))
            if seenPeople != savedPeople { savedPeople = seenPeople; SeenPerson.save(seenPeople) }
        }
    }

    private func screen(station: Station, open: [(repo: String, pr: OpenPR)], feed: [(repo: String, e: FeedEvent)],
                        moved: inout Bool) -> [WorldEvent] {
        var events: [WorldEvent] = []
        let cfg = ConfigStore.shared.current
        for (root, info) in repoRoots.sorted(by: { $0.key < $1.key }) where info.station == station.name && cfg.crewEnabled(repo: info.repo) {
            guard github.teamOpenPRs(repoRoot: root) != nil else { continue }
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

    var peerName = ""

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
        var markers = false
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
            if before?.dim != o.dim { changed = true }
            if before?.pull != o.pull || before?.pullState != o.pullState || before?.checks != o.checks || before?.review != o.review { markers = true }
            if o.pushed, pushedByPeer.insert(key).inserted { changed = true }
            let boxesBefore = peerBoxes[key]?.count
            if o.boxes > 0 || o.pull != nil { peerBoxes[key] = (max(1, o.boxes), o.pullState ?? "NONE", o.color) } else { peerBoxes[key] = nil }
            if peerBoxes[key]?.count != boxesBefore { markers = true }
            if let r = station.rooms[o.key] {
                r.lastActive = max(r.lastActive, o.lastActive, now)
                if r.worktree == nil, crewRoomInfo[key] == nil, r.name != o.name { r.name = o.name; changed = true }
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
        func working(_ s: PeerSnapshot?) -> Set<String> { Set((s?.minions ?? []).filter { !$0.asleep }.map { sk + $0.office }) }
        if working(previousSnap) != working(snap) { changed = true }
        if changed { events.append(.layoutChanged) }
        else if markers { events.append(.markersChanged) }

        if let b = snap.project, let p = cfg.project, b.owner == p.owner, b.number == p.number {
            github.adoptProject(b.items, at: b.at)
            events += applyBoardMoves()
        }
        for k in snap.github ?? [] where cfg.shared(repo: k.repo) {
            for (root, info) in repoRoots where info.repo == k.repo && info.station == "work" { github.adopt(k, repoRoot: root) }
        }
        return events
    }

    func dropPeer(_ name: String) -> [WorldEvent] {
        peerSnapshots[name] = nil; peerFirstSeen[name] = nil
        for (key, claims) in peerOffices where claims[name] != nil {
            peerOffices[key]?[name] = nil
            if peerOffices[key]?.isEmpty == true { peerOffices[key] = nil; peerBoxes[key] = nil; held[key] = Date() }
        }
        return [.peerLeft(name), .markersChanged]
    }

    // MARK: the yard

    func reconcile(station: Station, repo: String, root: String, cargo c: GitHubResolver.Cargo) {
        let k = station.name + "|" + repo
        if github.pipeline(repoRoot: root).shipsOnMerge { return }
        for n in c.storageNumbers { report(crate: n, repo: repo, .stored, by: c.source, at: c.updated[n] ?? Date()) }
        for n in c.deckNumbers where !c.clearedNumbers.contains(n) { report(crate: n, repo: repo, .qa, by: c.source, at: c.updated[n] ?? Date()) }
        for n in c.clearedNumbers { report(crate: n, repo: repo, .cleared, by: c.source, at: c.updated[n] ?? Date()) }
        let listed = Set(c.storageNumbers + c.deckNumbers + c.clearedNumbers)
        let shippedColumn = ConfigStore.shared.current.statuses.shipped
        for r in works.records(repo: repo) {
            guard let n = r.number, let stage = r.stage, stage >= .stored, stage < .shipped else { continue }
            if c.source == .git, c.exact, !listed.contains(n), !r.pulls.keys.contains(where: listed.contains),
               let at = r.stagedAt, at < c.at {
                works.report(r, .shipped, by: .git, at: c.at)
            } else if !shippedColumn.isEmpty, github.projectItems()?.contains(where: { $0.repo == repo && $0.number == n && $0.status == shippedColumn }) == true {
                works.report(r, .shipped, by: .board)
            }
        }
        station.ledger.adopt(yardWord(repo: repo, station: station), repo: repo)
        let open = station.ledger.disagreements(repo: repo)
        guard !open.isEmpty else { return }
        if open.contains(where: { $0.placed == .storage && $0.wanted == .deck && $0.heading == .deck }) { return }
        let launching = rocketBusy(k) || github.hasPendingLaunch(repoRoot: root) || (github.openReleases(repoRoot: root)?.contains(where: \.isProduction) ?? false)
        for crate in open {
            if launching, crate.placed == .deck { continue }
            station.ledger.snap(repo: repo, number: crate.number)
        }
    }

    func yardWord(repo: String, station: Station) -> Ledger.Word {
        var word = Ledger.Word(storage: [], deck: [])
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

    func slotNow(for crate: CrateRef, toward yard: Yard) -> Spot? {
        guard let station = fleet.stations[crate.station] else { return nil }
        return yard == .pad ? padSpot(station: station, repo: crate.repo) : station.spot(for: crate, toward: yard)
    }

    func padSlots(station: Station) -> [SIMD2<Double>] { station.hall.padSlots }

    private(set) var padSlotOf: [String: Int] = [:]

    func assignPads() {
        let wanted = padRockets().union(padSlotOf.keys.filter(rocketBusy))
        for key in padSlotOf.keys where !wanted.contains(key) { padSlotOf[key] = nil }
        for station in fleet.stations.values {
            let prefix = station.name + "|"
            let count = padSlots(station: station).count
            func urgent(_ key: String) -> Bool {
                if mergeLaunches.contains(key) || rocketBusy(key) { return true }
                let repo = String(key.dropFirst(prefix.count))
                if stagingUnderway(key) { return true }
                return repoRoots.contains { $0.value.repo == repo && $0.value.station == station.name && padRelease(root: $0.key) != nil }
            }
            let keys = wanted.filter { $0.hasPrefix(prefix) }.sorted { a, b in urgent(a) != urgent(b) ? urgent(a) : a < b }
            for key in keys where padSlotOf[key] == nil {
                let taken = Set(padSlotOf.filter { $0.key.hasPrefix(prefix) }.values)
                if let free = (0..<count).first(where: { !taken.contains($0) }) { padSlotOf[key] = free; continue }
                guard urgent(key), let victim = padSlotOf.keys.filter({ $0.hasPrefix(prefix) && !urgent($0) }).sorted().last else { continue }
                padSlotOf[key] = padSlotOf.removeValue(forKey: victim)
            }
        }
    }
    func padOrder(station: Station) -> [String] {
        padSlotOf.filter { $0.key.hasPrefix(station.name + "|") }.sorted { $0.value < $1.value }.map(\.key)
    }
    func padKeys() -> Set<String> { Set(padSlotOf.keys) }

    func padSpot(station: Station, repo: String) -> Spot {
        let slots = padSlots(station: station)
        let slot = padSlotOf[station.name + "|" + repo] ?? 0
        let pc = slots[slot % slots.count]
        let foot = SIMD2(pc.x, pc.y + 1.05)
        let stand = Cell(x: Int(foot.x.rounded()), y: Int(foot.y.rounded()))
        let cell = station.hall.padCells.contains(stand) ? stand : (station.hall.padCells.first ?? Cell(x: 0, y: 0))
        return Spot(area: .pad, station: station.name, owner: repo, label: repo, cell: cell,
                    pos: SIMD3(station.offset.x + foot.x, 0, station.offset.y + foot.y))
    }

    // MARK: commands the reconciler issues

    private func haulMerged(station: Station, room: Room) -> [WorldEvent] {
        let key = roomKey(station, room)
        guard station.hasPad, !haulOrdered(office: key) else { return [] }
        guard hasPackage(key) else { nothingToHaul.insert(key); return [] }
        let repo = room.repo ?? "work"
        let pull = pulls.pull(ownOffice: room)
        let known = works.find(officeKey: room.key, repo: repo)
        guard let prNumber = pull?.number ?? known?.pulls.keys.min(), prNumber > 0 else { nothingToHaul.insert(key); return [] }
        let record = works.note(repo: repo, branch: room.branch, folder: room.worktree, issue: pull?.closes.first, pull: prNumber, pullState: pull?.state)
        guard let number = record.number else { return [] }
        if record.quiet { nothingToHaul.insert(key); return [] }
        haulOrdered(office: key, crate: CrateRef(station: station.name, repo: repo, number: number))
        works.report(record, .stored, by: .pulls)
        return [.officeMerged(station: station.name, key: room.key, repo: repo, number: number)]
    }

    private(set) var closedAt: [String: Date] = [:]
    static let closedWindow: TimeInterval = 10 * 60
    func isClosed(_ roomKey: String) -> Bool { closedAt[roomKey] != nil }

    private var nothingToHaul: Set<String> = []

    func landed(station: Station, repo: String, number: Int, in yard: Yard, at now: Date) {
        station.ledger.landed(repo: repo, number: number, in: yard, at: now)
        fleet.save()
    }

    func unorder(_ crate: CrateRef) {
        fleet.stations[crate.station]?.ledger.unorder(repo: crate.repo, number: crate.number)
    }
}

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
