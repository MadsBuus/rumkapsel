import Foundation

final class World {
    let fleet = Fleet()
    let github = GitHubResolver()
    let sentry = SentrySource()
    var errorsByProject: [String: (repo: String, issues: [SentryIssue])] = [:]
    var yardStamps: [String: String] = [:]
    private let demo: Bool
    var simulated = false

    let log: EventLog

    init(demo: Bool) {
        self.demo = demo
        log = EventLog(dir: demo ? nil : EventLog.home)
        if demo { fleet.persists = false }
        github.watch.add { [weak sentry] in sentry?.checks() ?? [] }
        fleet.works = works
    }

    func errors(repo: String) -> [SentryIssue]? {
        let mine = errorsByProject.values.filter { $0.repo == repo }
        return mine.isEmpty ? nil : mine.flatMap(\.issues)
    }

    static let holdWindow: TimeInterval = 24 * 3600
    static let crewRecent: TimeInterval = 30 * 60
    static let roomsWindow: TimeInterval = 12 * 3600

    // MARK: model state

    private(set) var repoRoots: [String: (repo: String, station: String)] = [:]
    private(set) var newRepos: [String] = []
    private var seen: Set<String>?
    var hasScanned: Bool { scans > 0 }
    private static var seenURL: URL { AppSupport.root.appendingPathComponent("Rumkapsel/seen-repos.json") }

    private func remember(_ repos: Set<String>) {
        guard !simulated, !demo else { return }
        let all = (seen ?? []).union(repos)
        guard all != seen else { return }
        seen = all
        if let data = try? JSONEncoder().encode(all.sorted()) { try? data.write(to: World.seenURL, options: .atomic) }
    }

    func announce(new repos: [String]) { for r in repos where !newRepos.contains(r) { newRepos.append(r) } }

    private func register(root: String, repo: String, station: String) {
        let real = GitWatch.real(root)
        guard !repoRoots.values.contains(where: { $0.repo == repo }), !repoRoots.keys.contains(where: { GitWatch.real($0) == real }) else { return }
        repoRoots[root] = (repo, station)
        if station == "work" { _ = fleet.color(forRepo: repo) }
        guard let seen else { return }
        if !simulated, !seen.contains(repo), ConfigStore.shared.current.repos[repo] == nil, !newRepos.contains(repo) { newRepos.append(repo) }
        remember([repo])
    }

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

    let releases = ReleaseBook()
    let works = WorkBook()
    let feed = FactFeed()
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
        for (record, t) in transitions where t.to == .ready {
            guard let (station, room) = office(for: record) else { waiting.append((record, t)); continue }
            guard t.from != nil, isReady(record.repo) else { continue }
            let key = roomKey(station, room)
            let author = (crewRoomInfo[key] != nil ? record.author : nil) ?? github.myLogin() ?? ""
            if let number = record.pulls.keys.min() {
                events.append(.pullRequestOpened(repo: record.repo, number: number, author: author))
            }
        }
        transitions = waiting
        return events
    }

    func report(office key: String, repo: String, _ stage: Stage, by source: Source, at: Date) {
        guard let r = works.find(officeKey: key, repo: repo) else { return }
        works.report(r, stage, by: source, at: at)
    }
    func report(crate n: Int, repo: String, _ stage: Stage, by source: Source, at: Date) {
        works.report(works.note(repo: repo, crate: n), stage, by: source, at: at)
    }
    func report(pullState state: String?, record: WorkBook.Record?, shipped: Bool = false, at: Date) {
        guard let state, let record else { return }
        if !record.housekeeping, state == "MERGED", let root = repoRoots.first(where: { $0.value.repo == record.repo })?.key,
           record.pulls.keys.contains(where: { github.pulls.pull(number: $0, repoRoot: root)?.backMerge == true })
            || record.branches.contains(where: { github.pulls.pull(branch: $0, repoRoot: root)?.backMerge == true }) {
            record.housekeeping = true
            StationLog.write("stage", "\(record.repo) \(record.work().label): a back-merge, not work")
            if let n = record.number {
                learn(.work(WorkNews(crate: CrateID(repo: record.repo, number: n), stage: record.stage ?? .stored, quiet: true, housekeeping: true)), repo: record.repo)
            }
        }
        if shipped { return works.report(record, .shipped, by: .git, at: at) }
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
    func crewPull(_ key: String) -> Int? {
        guard crewRoomInfo[key] != nil, let r = record(office: key) else { return nil }
        if let p = r.pulls.keys.min() { return p }
        return r.number.flatMap { n in works.slices(repo: r.repo, of: n).filter { $0.stage == .ready }.compactMap { $0.pulls.keys.min() }.min() }
    }

    func workflow(repo: String) -> Workflow {
        if let w = ConfigStore.shared.current.repos[repo]?.workflow { return w }
        let root = repoRoots.first { $0.value.repo == repo }?.key
        let pipeline = root.map { github.pipeline(repoRoot: $0) } ?? .unread
        return Workflow.detected(pipeline: pipeline, board: ConfigStore.shared.current.project != nil)
    }
    func stage(office key: String, repo: String?) -> Stage? { repo.flatMap { works.find(officeKey: key, repo: $0) }?.stage }

    private(set) var readyRepos: Set<String> = []
    private(set) lazy var seenPeople: [String: SeenPerson] = waitsForGitHub ? SeenPerson.load() : [:]
    private var savedPeople: [String: SeenPerson] = [:]
    private var crewSeen: Set<String> = []
    private var didLoadLayout = false
    private var scans = 0
    private var savedKnowledgeAt = Date.distantPast
    static let officeGraceScans = 10
    var waitsForGitHub = true

    var clock: () -> Date = Date.init
    var onOffices: (Station, [Effect]) -> Void = { _, _ in }
    var onFacts: (Station, [Effect]) -> Void = { _, _ in }
    var onLoaded: () -> Void = {}
    var now: Date { clock() }

    func isReady(_ repo: String?) -> Bool { repo.map { readyRepos.contains($0) } ?? true }

    var allReady: Bool { !repoRoots.isEmpty && repoRoots.values.allSatisfy { readyRepos.contains($0.repo) } }

    var settling: Bool { waitsForGitHub && scans < World.officeGraceScans && !allReady && !knewAlready }

    private var knewAlready: Bool { github.pulls.hasAnswers }

    func reset() {
        fleet.save()
        Fleet.writing.sync {}
        fleet.unload()
        log.forget()
        repoRoots = [:]
        readyRepos = []
        didLoadLayout = false
        yardStamps = [:]
        works.reset()
        transitions = []
        crewRoomInfo = [:]
        crewBoxes = [:]
        scans = 0
        afresh = true
        feed.swept = []
    }

    private var afresh = false

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
        var pushed = github.git.branchPushed(worktree: w) ?? true
        if let b = room.branch, let r = room.repoRoot, github.pulls.pull(branch: b, repoRoot: r) != nil { pushed = true }
        return (!pushed, github.git.commitsAhead(worktree: w) ?? 0)
    }

    func cubes(_ room: Room) -> Int? {
        guard room.key.hasPrefix("task:"), let w = room.worktree else { return 0 }
        return github.git.commitsAhead(worktree: w).map { min(16, Int(pow(Double($0), 0.7).rounded(.up))) }
    }

    func checksFailing(_ room: Room) -> Bool {
        if room.branch == nil, let po = peerPull("work|" + room.key) { return po.pullState == "OPEN" && po.checks == "failure" }
        guard let b = room.branch, let r = room.repoRoot, let pr = github.pulls.pull(branch: b, repoRoot: r) else { return false }
        return pr.state == "OPEN" && pr.checks == "failure"
    }

    func isDusty(_ room: Room) -> Bool {
        !room.key.hasPrefix("kind:") && now.timeIntervalSince(room.lastActive) > 7 * 24 * 3600
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
        return repoRoots.isEmpty || repoRoots.keys.contains { !github.pulls.answered(repoRoot: $0) }
    }
    static let lookingScans = 60

    func lookedAt(_ repo: String?) -> Bool {
        guard waitsForGitHub else { return true }
        guard let repo else { return true }
        let roots = repoRoots.filter { $0.value.repo == repo }.map(\.key)
        return !roots.isEmpty && roots.contains { github.pulls.answered(repoRoot: $0) }
    }

    func peerLive(_ key: String) -> Bool {
        peerSnapshots.values.contains { entry in entry.snap.minions.contains { !$0.asleep && "work|" + $0.office == key } }
    }
    func isNeighbours(_ station: Station, _ room: Room) -> Bool {
        let key = roomKey(station, room)
        return room.worktree == nil && crewRoomInfo[key] == nil && peerOffices[key]?.isEmpty == false
    }
    func isOurs(_ station: Station, _ room: Room) -> Bool {
        room.worktree != nil || crewRoomInfo[roomKey(station, room)] != nil
            || !isNeighbours(station, room) && repoRoots.values.contains { $0.repo == room.repo }
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
        peerSnapshots.filter { now.timeIntervalSince($0.value.at) > seconds }.map(\.key)
    }

    // MARK: kicking

    private var simKicked: [String: Date] = [:]
    private var kicked: [String: Date] {
        get { simulated ? simKicked : (UserDefaults.standard.dictionary(forKey: "kicked") as? [String: Date]) ?? [:] }
        set {
            let live = newValue.filter { now.timeIntervalSince($0.value) < World.holdWindow }
            if simulated { simKicked = live } else { UserDefaults.standard.set(live, forKey: "kicked") }
        }
    }

    func isKicked(_ key: String) -> Bool { kicked[key].map { now.timeIntervalSince($0) < World.holdWindow } ?? false }

    func kick(roomKey key: String) -> [WorldEvent] {
        batch {
            let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
            guard parts.count == 2, let station = fleet.stations[parts[0]], let room = station.rooms[parts[1]] else { return [] }
            var k = kicked; k[key] = now; kicked = k
            crewRoomInfo[key] = nil; crewBoxes[key] = nil; peerOffices[key] = nil; peerBoxes[key] = nil; pushedByPeer.remove(key)
            var events = drop(station: station, room: room, announce: false, reason: "kicked")
            events.append(.log("\(Words.current.kicked) \(room.name) \(Words.current.kickedOff)"))
            events.append(.layoutChanged)
            return events
        }
    }

    private func drop(station: Station, room: Room, announce: Bool, reason: String) -> [WorldEvent] {
        station.removeRoom(key: room.key)
        learn(.gone(room.key), station: station.name)
        let gone = WorldEvent.office(station: station.name, .gone(room.key), reason: reason)
        return announce ? [gone, .log("archived: \(room.name)" + (reason.isEmpty ? "" : " · \(reason)"))] : [gone]
    }

    private func opened(_ station: Station, _ key: String, repo: String?, via: OfficeFact.Via) -> WorldEvent {
        let news = OfficeNews.opened(key, repo: repo, via: via)
        learn(news, station: station.name)
        if let repo, let r = works.find(officeKey: key, repo: repo), r.stage == .ready, let n = r.number {
            learn(.work(WorkNews(crate: CrateID(repo: repo, number: n), office: key, stage: .ready, quiet: true)), repo: repo)
        }
        return .office(station: station.name, news)
    }

    func restored() {
        for station in fleet.stations.values.sorted(by: { $0.name < $1.name }) {
            for o in station.facts.offices.values { if let at = o.closedAt { closedAt["\(station.name)|\(o.key)"] = at } }
            let drift = officeDrift(station)
            if !drift.isEmpty { _ = apply(drift, at: now, to: station) }
        }
        onLoaded()
    }

    private func status(_ station: Station, _ room: Room) {
        let record = room.repo.flatMap { works.find(officeKey: room.key, repo: $0) }
        let epic = record.flatMap(epic(of:))
        let crated = !(record.map(works.crateless) ?? false)
        let crate = crated ? record.flatMap { r in r.number.map { CrateID(repo: r.repo, number: $0) } } : nil
        let merged = crated && record?.stage.map { $0 >= .stored } ?? false
        let closed = closedAt[roomKey(station, room)]
        if let o = station.facts.offices[room.key], o.crate == crate, o.merged == merged, o.closedAt == closed, o.epic == Rules.epic(o.epic, epic) { return }
        learn(.status(room.key, crate: crate, merged: merged, closedAt: closed, epic: epic), station: station.name)
    }

    func epic(of r: WorkBook.Record) -> EpicNews? {
        guard r.epic == nil, let n = r.number, works.hasMergedSlice(repo: r.repo, of: n) else { return nil }
        let slices = works.slices(repo: r.repo, of: n)
        if let open = issueOpen(repo: r.repo, n) { r.issueOpen = open }
        switch r.issueOpen {
        case true?: return .open(shipped: slices.filter { $0.stage == .shipped }.count)
        case false?: return .closed
        case nil: return nil
        }
    }

    private func ownEpicOnBoard(_ station: Station, _ room: Room) -> Bool {
        let cfg = ConfigStore.shared.current
        guard station.name == "work", cfg.showCrew, let repo = room.repo, cfg.crewEnabled(repo: repo), let n = Work.number(inOfficeKey: room.key),
              works.hasMergedSlice(repo: repo, of: n), let me = github.myLogin(), let items = github.board.liveItems ?? github.board.items else { return false }
        return items.contains { $0.repo == repo && $0.number == n && !$0.isClosed && $0.status == cfg.statuses.development && $0.assignees.first == me }
    }

    private func issueOpen(repo: String, _ n: Int) -> Bool? {
        if let item = (github.board.liveItems ?? github.board.items)?.first(where: { $0.repo == repo && $0.number == n }) { return !item.isClosed }
        guard let root = repoRoots.first(where: { $0.value.repo == repo })?.key else { return nil }
        github.pulls.refresh(issue: n, repoRoot: root)
        return github.pulls.issueOpen(n, repoRoot: root)
    }

    func checkSlices() {
        for (root, info) in repoRoots.sorted(by: { $0.key < $1.key }) {
            let open = Set((github.pulls.teamOpenPRs(repoRoot: root) ?? []).map(\.number))
            let records = works.records(repo: info.repo), epics = Set(records.compactMap(\.epic))
            for r in records {
                if r.epic != nil {
                    for p in r.pulls.keys.sorted() where r.stage == .ready && !open.contains(p) {
                        github.pulls.refresh(pull: p, repoRoot: root)
                        if let pr = github.pulls.pull(number: p, repoRoot: root), pr.state != "OPEN" { report(pullState: pr.state, record: r, shipped: pr.shipped, at: now) }
                    }
                    continue
                }
                guard let n = r.branchIssue ?? r.issue else { continue }
                let shipped = (r.stage ?? .inbound) >= .shipped
                let unchecked = r.pulls.keys.filter { $0 != n && !slicesChecked.contains("\(info.repo)!\($0)") }.sorted()
                if shipped, !epics.contains(n) {
                    guard !unchecked.isEmpty, !shippedSettled.contains("\(info.repo)#\(n)"), let open = issueOpen(repo: info.repo, n) else { continue }
                    guard open else { shippedSettled.insert("\(info.repo)#\(n)"); continue }
                }
                for p in unchecked where slicesChecked.insert("\(info.repo)!\(p)").inserted {
                    github.pulls.refresh(pull: p, repoRoot: root)
                    guard let pr = github.pulls.pull(number: p, repoRoot: root), let closes = pr.closes else {
                        slicesChecked.remove("\(info.repo)!\(p)")
                        continue
                    }
                    guard let s = works.heard(repo: info.repo, pull: p, closes: closes, pullState: pr.state), s !== r else { continue }
                    StationLog.write("stage", "\(info.repo) #\(p): part of #\(n), not closing it: a \(Words.current.crate) of its own")
                    report(pullState: pr.state, record: s, shipped: pr.shipped || shipped, at: now)
                    yardStamps[root] = nil
                }
            }
        }
    }

    // MARK: the session scan

    struct MinionHome { var station: String; var key: String; var idle: Bool }

    private var sessionPrompts: [String: (marker: String, count: Int)] = [:]

    func applyScan(_ result: ScanResult, now: Date, minionHomes: [String: MinionHome]) -> [WorldEvent] {
        batch {
            var events: [WorldEvent] = []
            var changed = false
            let firstRun = !didLoadLayout
            if firstRun {
                didLoadLayout = true
                works.workflow = { [weak self] repo in self?.workflow(repo: repo) ?? Workflow() }
                works.clock = { [weak self] in self?.now ?? Date() }
                works.onTransition = { [weak self] r, t in
                    let who = r.number.map { "#\($0)" } ?? r.work().label
                    StationLog.write("stage", "\(r.repo) \(who): \(t.from.map { "\($0) → " } ?? "")\(t.to) · \(t.by.rawValue)\(t.back ? " (back)" : "")")
                    self?.transitions.append((r, t))
                    self?.launchShipped(r, t)
                    self?.learn(r, t)
                    if r.epic != nil, let (station, room) = self?.office(for: r) { self?.status(station, room) }
                }
                fleet.load(alone: peerSnapshots.isEmpty)
                if seen == nil, let data = try? Data(contentsOf: World.seenURL), let names = try? JSONDecoder().decode([String].self, from: data) { seen = Set(names) }
                restored()
                if waitsForGitHub { github.pulls.load() }
                changed = true
                events.append(.worldLoaded)
            }

            scans += 1
            var sessionRooms: Set<String> = []
            var holds: [String: String] = [:]
            let cfg = ConfigStore.shared.current
            let deciders = World.deciders(result.sessions)
            for s in result.sessions where s.cwdExists && Fleet.stationName(for: s.cwd, owner: s.owner, repo: s.repo) != "hidden"
                && (Fleet.stationName(for: s.cwd, owner: s.owner, repo: s.repo) == "work" || now.timeIntervalSince(s.lastModified) < World.roomsWindow) {
                let stationName = Fleet.stationName(for: s.cwd, owner: s.owner, repo: s.repo)
                let station = fleet.station(stationName)
                if let branch = s.branch, now.timeIntervalSince(s.lastModified) > 600 {
                    github.git.refreshCommits(worktree: s.cwd)
                    if let current = github.git.currentBranch(worktree: s.cwd), current != branch { continue }
                }
                let home = homeFor(deciders[s.cwd] ?? s, station: stationName)
                sessionRooms.insert("\(stationName)|\(home.key)")
                holds["\(stationName)|\(s.cwd)"] = home.key
                let held = settling && station.rooms[home.key] == nil
                if !held, station.rooms[home.key] == nil, let from = previousOffice(of: s, home: home, in: station, minionHomes: minionHomes) {
                    let promoted = from.key.hasPrefix("proj:") && home.key.hasPrefix("task:") && !firstRun && (minionHomes[s.id]?.idle ?? true)
                    station.renameRoom(from: from.key, to: home.key, name: home.name)
                    learn(.renamed(from: from.key, to: home.key), station: stationName)
                    events.append(.office(station: stationName, .renamed(from: from.key, to: home.key)))
                    if promoted { events.append(.log("\(home.name): branch created")) }
                    changed = true
                }
                if let r = station.rooms[home.key], r.worktree == nil, r.name != home.name { r.name = home.name; changed = true }
                if !held, station.ensureRoom(key: home.key, name: home.name, repo: home.repo, color: fleet.color(forRepo: home.repo), lastActive: s.lastModified) {
                    changed = true
                    roomCreated["\(stationName)|\(home.key)"] = now
                    events.append(opened(station, home.key, repo: home.repo,
                                         via: firstRun || scans <= World.officeGraceScans + 1 ? .appear : .shuttle(for: s.id)))
                    report(office: home.key, repo: home.repo, .inbound, by: .session, at: s.lastModified)
                }
                if let root = s.repoRoot { register(root: root, repo: s.repo, station: stationName) }
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
                    if let b = room.branch, let r = room.repoRoot { github.pulls.refresh(branch: b, repoRoot: r) }
                    if let w = room.worktree { github.git.refreshCommits(worktree: w) }
                }
            }
            for station in fleet.stations.values {
                var byWorkspace: [String: [Room]] = [:]
                for room in station.rooms.values where !room.key.hasPrefix("kind:") {
                    if stage(office: room.key, repo: room.repo).map({ $0 >= .stored }) == true { continue }
                    if let w = room.worktree { byWorkspace[w, default: []].append(room) }
                }
                for (w, rooms) in byWorkspace where rooms.count > 1 {
                    let holding = holds["\(station.name)|\(w)"]
                    let keep = rooms.first { $0.key == holding } ?? rooms.first { $0.key.contains("#") } ?? rooms.min { $0.key < $1.key }
                    for room in rooms where room !== keep {
                        events += drop(station: station, room: room, announce: false, reason: "one workspace, one office")
                        changed = true
                    }
                }
            }
            let livedIn = Set(sessionRooms.compactMap { key -> String? in
                let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
                return parts.count == 2 ? fleet.stations[parts[0]]?.rooms[parts[1]]?.worktree : nil
            })
            for station in fleet.stations.values {
                for room in Array(station.rooms.values) where !room.key.hasPrefix("kind:") {
                    let key = roomKey(station, room)
                    let pull = pulls.pull(ownOffice: room)
                    let state = pull?.state
                    if let pull, let repo = room.repo { report(pullState: state, record: works.note(repo: repo, branch: room.branch, folder: room.worktree, issue: pull.closes?.first, pull: pull.number, pullState: state, closes: pull.closes), shipped: pull.shipped, at: now) }
                    let merged = stage(office: room.key, repo: room.repo).map { $0 >= .stored } ?? false
                    var gone = room.worktree.map { !Workspaces.isOpen($0) } ?? false
                    if let w = room.worktree, let branch = room.branch, !sessionRooms.contains(key) {
                        github.git.refreshCommits(worktree: w)
                        if let current = github.git.currentBranch(worktree: w), current != branch { gone = true }
                    }
                    let closed = state == "CLOSED" && !merged
                    if closed, closedAt[key] == nil {
                        closedAt[key] = now
                        learnClosed(office: room.key, repo: room.repo)
                        events.append(.log("\(room.name): pull request closed, not merged"))
                    }
                    if state != nil, !closed { closedAt[key] = nil }
                    status(station, room)
                    let unclaimed = room.worktree == nil && crewRoomInfo[key] == nil && peerOffices[key] == nil && isReady(room.repo)
                        && (cfg.project == nil || github.board.liveItems != nil)
                    let unread = scans > World.officeGraceScans && room.repo != nil && room.worktree == nil && crewRoomInfo[key] == nil
                        && peerOffices[key] == nil && !repoRoots.values.contains { $0.repo == room.repo }
                    let orphan = unclaimed && (held[key].map { now.timeIntervalSince($0) > World.holdWindow } ?? true)
                        || unread && now.timeIntervalSince(max(held[key] ?? .distantPast, room.lastActive)) > World.holdWindow
                    let mine = room.worktree.map { Workspaces.isOpen($0) && (sessionRooms.contains(key) || !livedIn.contains($0)) } ?? false
                    let lan = peerOffices[key] != nil
                    let ended = crewRoomInfo[key] != nil ? nil : station.facts.offices[room.key].flatMap { Rules.officeEnds($0, now: now, mine: mine, lan: lan) }
                    if gone, ended == nil, ownEpicOnBoard(station, room) {
                        room.worktree = nil; room.branch = nil; room.repoRoot = nil
                        crewRoomInfo[key] = CrewRoomInfo(state: "OPEN", last: now)
                        changed = true
                        continue
                    }
                    if gone || ended != nil || orphan {
                        if ended != nil { retired[key] = now }
                        events += drop(station: station, room: room, announce: !firstRun, reason: gone ? "workspace archived" : ended ?? "nobody's")
                        changed = true
                    }
                }
            }

            if firstRun, !simulated {
                for (repo, root) in Discovery.conductor(home: FileManager.default.homeDirectoryForCurrentUser) {
                    guard cfg.shown(repo: repo) else { continue }
                    register(root: root, repo: repo, station: "work")
                }
                for (repo, o) in cfg.repos.sorted(by: { $0.key < $1.key }) where cfg.shown(repo: repo) {
                    guard let root = o.path, FileManager.default.fileExists(atPath: root + "/.git") else { continue }
                    register(root: root, repo: repo, station: "work")
                }
            }
            if firstRun, seen == nil { remember(Set(repoRoots.values.map(\.repo)).union(cfg.repos.keys).union(fleet.repoColors.keys)) }
            github.intervalMinutes = cfg.githubMinutes
            if let p = cfg.project { github.board.refresh(owner: p.owner, number: p.number) }
            github.watch(repoRoots.mapValues { $0.station == "work" }, board: cfg.project.map { ($0.owner, $0.number) })
            for (root, info) in repoRoots {
                github.releases.refresh(repoRoot: root)
                if info.station == "work" { github.pulls.refreshOpenPRs(repoRoot: root) }
            }
            events += hear(github.deployments.reports())
            events += lostDeploys()
            events += applyBoardMoves()
            events += hear(github.pulls.reports())
            events += hear(sentry.reports())
            events += stationEvents()
            if changed { events.append(.layoutChanged) }
            return events
        }
    }

    static func deciders(_ sessions: [SessionInfo]) -> [String: SessionInfo] {
        Dictionary(grouping: sessions, by: \.cwd).compactMapValues { here in
            here.max { ($0.isSubagent ? 0 : 1, $0.lastModified) < ($1.isSubagent ? 0 : 1, $1.lastModified) }
        }
    }

    private func previousOffice(of s: SessionInfo, home: Home, in station: Station, minionHomes: [String: MinionHome]) -> Room? {
        if let m = minionHomes[s.id], m.station == station.name, m.key != home.key, let r = station.rooms[m.key], r.repo == home.repo,
           !minionHomes.contains(where: { $0.key != s.id && $0.value.key == m.key && $0.value.station == station.name }) { return r }
        return station.rooms.values.first { $0.key.hasPrefix("proj:") && $0.repo == home.repo && $0.worktree == s.cwd && $0.key != home.key }
    }

    func homeFor(_ s: SessionInfo, station: String) -> Home {
        let pr = s.branch.flatMap { b in s.repoRoot.flatMap { github.pulls.pull(branch: b, repoRoot: $0) } }
        let home = works.note(repo: s.repo, branch: s.branch, folder: s.cwd, issue: pr?.closes?.first, pull: pr?.number, pullState: pr?.state, closes: pr?.closes)
            .work(branch: s.branch).home
        let closedEpic = home.issue.flatMap { works.find(repo: s.repo, issue: $0) }.map { $0.issueOpen == false && !works.slices(repo: s.repo, of: $0.number ?? 0).isEmpty } ?? false
        if closedEpic { return Home(key: "kind:lounge", name: home.name, repo: home.repo, issue: nil) }
        if let at = retired["\(station)|\(home.key)"], now.timeIntervalSince(at) < World.holdWindow {
            return Home(key: "kind:lounge", name: home.name, repo: home.repo, issue: nil)
        }
        return home
    }

    // MARK: github

    func applyGitHub(now: Date, timed: ((String, () -> [WorldEvent]) -> [WorldEvent])? = nil) -> [WorldEvent] {
        batch {
            let run = timed ?? { _, b in b() }
            placementsLeft = false
            checkSlices()
            var events = run("gh.releases") { self.applyReleases() }
            events += run("gh.board") { self.applyBoardMoves() }
            events += run("gh.crew") { self.rebuildCrew(now: now) }
            if didLoadLayout { afresh = false }
            events += stationEvents()
            return events
        }
    }

    private func applyBoardMoves() -> [WorldEvent] { hear(github.board.reports()) }

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
                events += drop(station: station, room: room, announce: false, reason: "crew hidden")
            }
            crewRoomInfo = [:]; crewBoxes = [:]
            events.append(.layoutChanged)
            return events
        }
        var changed = false
        var open: [(repo: String, pr: OpenPR)] = []
        var feed: [(repo: String, e: FeedEvent)] = []
        for (root, info) in repoRoots where info.station == "work" && cfg.crewEnabled(repo: info.repo) {
            for pr in github.pulls.teamOpenPRs(repoRoot: root) ?? [] where !Work.longLived.contains(pr.branch) {
                let checkedOutHere = station.rooms.values.contains { $0.worktree != nil && $0.repo == info.repo && ($0.branch == pr.branch || $0.key == Work(repo: info.repo, branch: pr.branch, pull: pr.number).officeKey) }
                if pr.author != me || !checkedOutHere { open.append((info.repo, pr)) }
            }
            for e in github.pulls.feed(repoRoot: root) ?? [] where e.actor != me { feed.append((info.repo, e)) }
        }
        var boardOffices: [(repo: String, item: ProjectItem, login: String)] = []
        if cfg.project != nil, !me.isEmpty, let items = github.board.liveItems {
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
                guard let login = it.assignees.first else { continue }
                if login == me, !works.hasMergedSlice(repo: it.repo, of: it.number) || station.rooms[key]?.worktree != nil { continue }
                if open.contains(where: { $0.repo == it.repo && crewKey(repo: $0.repo, branch: $0.pr.branch) == key }) { continue }
                let working = !it.prURLs.isEmpty || branched.contains("\(it.repo)#\(it.number)") || peerOffices[sk + key] != nil || station.rooms[key]?.worktree != nil
                    || !works.slices(repo: it.repo, of: it.number).isEmpty
                guard working else { continue }
                boardOffices.append((it.repo, it, login))
            }
        }
        for old in ["kind:bots", "kind:mail"] where station.rooms[old] != nil { station.removeRoom(key: old); changed = true }
        var deconMoved = false
        events += screen(station: station, open: open, feed: feed, moved: &deconMoved)
        let inDecon = station.facts.crates.values.contains { $0.zone == .decon }
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
            let root = repoRoots.first { $0.value.repo == room.repo }?.key
            if let known, known.pulls.isEmpty, let n = known.number, case let slices = works.slices(repo: known.repo, of: n), !slices.isEmpty {
                status(station, room)
                if station.facts.offices[room.key]?.epic != nil {
                    guard let fact = station.facts.offices[room.key], let why = Rules.officeEnds(fact, now: now, mine: false, lan: false) else { continue }
                    crewRoomInfo[key] = nil; crewBoxes[key] = nil
                    events += drop(station: station, room: room, announce: false, reason: why)
                    changed = true
                    continue
                }
                if known.issueOpen == nil, slices.contains(where: { ($0.stage ?? .inbound) >= .stored }) { continue }
            }
            guard let state = pulls.state(crewOffice: room, known: known, repoRoot: root, feed: feed) else { continue }
            if state == "NONE" {
                if peerOffices[key] != nil { continue }
                closedAt[key] = nil
                crewRoomInfo[key] = nil; crewBoxes[key] = nil
                events += drop(station: station, room: room, announce: false, reason: "no longer in development")
                changed = true
                continue
            }
            if let repo = room.repo { report(pullState: state, record: known?.pulls.keys.min().map { works.note(repo: repo, pull: $0, pullState: state) } ?? known, at: now) }
            crewRoomInfo[key]?.state = state
            let merged = stage(office: room.key, repo: room.repo).map { $0 >= .stored } ?? false
            if !merged, closedAt[key] == nil {
                closedAt[key] = now
                learnClosed(office: room.key, repo: room.repo)
                events.append(.log("\(room.name): pull request closed, not merged"))
            }
            status(station, room)
            guard let fact = station.facts.offices[room.key], Rules.officeEnds(fact, now: now, mine: false, lan: false) != nil else { continue }
            if merged, isReady(room.repo) { events.append(.pullRequestClosed(repo: room.repo ?? "", author: author, roomKey: room.key)) }
            closedAt[key] = nil
            crewRoomInfo[key] = nil; crewBoxes[key] = nil
            events += drop(station: station, room: room, announce: isReady(room.repo), reason: "pull request closed")
            changed = true
        }
        for (repo, pr) in open where !pr.isBot && !isKicked(sk + work(repo, pr).officeKey) {
            let record = works.note(repo: repo, branch: pr.branch, pull: pr.number, pullState: "OPEN", closes: pr.closes, author: pr.author, title: pr.title, url: pr.url)
            works.report(record, .ready, by: .pulls, at: pr.createdAt)
            let home = work(repo, pr).home
            let key = home.key
            let name = home.name
            if let r = station.rooms[key], r.worktree == nil, r.name != name { r.name = name; changed = true }
            if station.rooms[key] == nil {
                guard afresh || placed < World.placementsPerPass else { placementsLeft = true; continue }
                placed += 1
            }
            if station.ensureRoom(key: key, name: name, repo: repo, color: fleet.color(forRepo: repo), lastActive: now) {
                changed = true
                events.append(opened(station, key, repo: repo, via: isReady(repo) && !afresh ? .shuttle(for: "crew:" + pr.author) : .appear))
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
            if let r = station.rooms[key], r.worktree == nil, r.name != name, login != me { r.name = name; changed = true }
            if station.rooms[key] == nil {
                guard afresh || placed < World.placementsPerPass else { placementsLeft = true; continue }
                placed += 1
            }
            if station.ensureRoom(key: key, name: name, repo: repo, color: fleet.color(forRepo: repo), lastActive: now) {
                changed = true
                events.append(opened(station, key, repo: repo, via: isReady(repo) && !afresh && login != me ? .shuttle(for: "crew:" + login) : .appear))
                if isReady(repo) && !afresh && login != me {
                    report(office: key, repo: repo, .inbound, by: .board, at: now)
                    events.append(.issueStarted(repo: repo, number: it.number, author: login, roomKey: key))
                }
            }
            crewRoomInfo[sk + key] = CrewRoomInfo(state: "OPEN", last: now)
            crewBoxes[sk + key] = (1, "NONE", fleet.color(forRepo: repo))
        }

        var logins = Set(open.filter { !$0.pr.isBot && $0.pr.author != me }.map(\.pr.author))
        logins.formUnion(boardOffices.map(\.login).filter { $0 != me })
        logins.formUnion(feed.filter { !$0.e.isBot && now.timeIntervalSince($0.e.at) < 2 * 3600 }.map(\.e.actor))
        for (repo, e) in feed where !e.isBot { seen(e.actor, in: repo, at: e.at) }
        for (repo, pr) in open where !pr.isBot { seen(pr.author, in: repo, at: pr.createdAt) }
        for o in boardOffices where o.login != me { seen(o.login, in: o.repo, at: o.item.updatedAt ?? now) }
        var roster: [String: CrewMember] = [:]
        for login in logins {
            let epic = boardOffices.first { $0.login == login && station.facts.offices[Work(repo: $0.repo, issue: $0.item.number).officeKey]?.epic != nil }
            let homeKey = open.first { $0.pr.author == login }.map { crewKey(repo: $0.repo, branch: $0.pr.branch) }
                ?? epic.map { Work(repo: $0.repo, issue: $0.item.number).officeKey } ?? "kind:quarters"
            roster[login] = CrewMember(homeKey: homeKey, repo: open.first { $0.pr.author == login }?.repo ?? epic?.repo ?? "crew")
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
        for (root, info) in repoRoots where info.station == "work" && github.pulls.teamOpenPRs(repoRoot: root) != nil { readyRepos.insert(info.repo) }
        if waitsForGitHub, readyRepos.count != before || Date().timeIntervalSince(savedKnowledgeAt) > 60 {
            savedKnowledgeAt = Date()
            github.pulls.save(repoRoots.mapValues(\.repo))
            if seenPeople != savedPeople { savedPeople = seenPeople; SeenPerson.save(seenPeople) }
        }
    }

    private func screen(station: Station, open: [(repo: String, pr: OpenPR)], feed: [(repo: String, e: FeedEvent)],
                        moved: inout Bool) -> [WorldEvent] {
        var events: [WorldEvent] = []
        let cfg = ConfigStore.shared.current
        for (root, info) in repoRoots.sorted(by: { $0.key < $1.key }) where info.station == station.name && cfg.crewEnabled(repo: info.repo) {
            guard github.pulls.teamOpenPRs(repoRoot: root) != nil else { continue }
            let bots = open.filter { $0.repo == info.repo && $0.pr.isBot }.map(\.pr.number)
            let known = station.facts.crates.values.filter { $0.id.repo == info.repo }
            if bots.contains(where: { n in !known.contains { $0.id.number == n } }) { moved = true }
            learn(.decon(repo: info.repo, open: bots, quiet: deconHeard.insert(info.repo).inserted), repo: info.repo)
            let gone = known.filter { $0.zone == .decon && !bots.contains($0.id.number) && !deconSettled.contains($0.id) }.map(\.id.number).sorted()
            for n in gone {
                var state: String?
                if feed.contains(where: { $0.repo == info.repo && $0.e.kind == "pr_close" && $0.e.prNumber == n }) { state = "CLOSED" }
                else if feed.contains(where: { $0.repo == info.repo && $0.e.kind == "pr_merge" && $0.e.prNumber == n }) { state = "MERGED" }
                else {
                    github.pulls.refresh(pull: n, repoRoot: root)
                    if github.pulls.pullAnswered(number: n, repoRoot: root) { state = github.pulls.pull(number: n, repoRoot: root)?.state }
                }
                guard let state else { continue }
                moved = true
                deconSettled.insert(CrateID(repo: info.repo, number: n))
                if state == "MERGED", station.hasPad {
                    events.append(.log("#\(n) \(Words.current.clearedDecon)"))
                    learn(.work(WorkNews(crate: CrateID(repo: info.repo, number: n), stage: .stored)), repo: info.repo)
                    report(crate: n, repo: info.repo, .stored, by: .pulls, at: now)
                } else {
                    learn(.deconClosed(CrateID(repo: info.repo, number: n)), repo: info.repo)
                }
            }
        }
        return events
    }

    // MARK: peers

    var peerName = ""
    private var unplaceable: [String: [Cell]] = [:]

    func applyPeer(_ snap: PeerSnapshot, now: Date) -> [WorldEvent] {
        batch {
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
            if let colors = snap.colors, snap.name < peerName,
               fleet.adopt(colors.filter { cfg.repos[$0.key]?.color == nil && cfg.shown(repo: $0.key) }) {
                changed = true
                events.append(.log("repository colours now match \(snap.name)'s"))
            }
            let mine = Set(peerOffices.filter { $0.value[snap.name] != nil }.map(\.key))
            var live: Set<String> = []
            var disputed: [(key: String, cells: [Cell])] = []
            for o in snap.offices where cfg.shown(repo: o.repo) && !isKicked(sk + o.key) {
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
                    if r.cells != o.cells, !o.cells.isEmpty, snap.name < peerName, unplaceable[key] != o.cells { disputed.append((o.key, o.cells)) }
                    continue
                }
                let color = fleet.color(forRepo: o.repo)
                guard station.ensureRoom(key: o.key, name: o.name, repo: o.repo, color: color, lastActive: now, preferredCells: o.cells) else { continue }
                changed = true
                if !bulk, now.timeIntervalSince(o.startedAt) < 3 * 60 {
                    events.append(opened(station, o.key, repo: o.repo, via: .shuttle(for: nil)))
                    report(office: o.key, repo: o.repo, .inbound, by: .neighbour, at: o.startedAt)
                    events.append(.log("\(snap.name) started \(o.name)"))
                } else {
                    events.append(opened(station, o.key, repo: o.repo, via: .fade))
                }
            }
            let moved = station.replaceRooms(disputed)
            for d in disputed where !moved.contains(d.key) { unplaceable[sk + d.key] = d.cells }
            if !moved.isEmpty {
                touch(station)
                changed = true
                events.append(.log("\(moved.count) office\(moved.count == 1 ? " stands" : "s stand") where \(snap.name) put \(moved.count == 1 ? "it" : "them")"))
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
                github.board.adopt(b.items, at: b.at)
                events += applyBoardMoves()
            }
            for k in snap.github ?? [] where cfg.shared(repo: k.repo) {
                for (root, info) in repoRoots where info.repo == k.repo && info.station == "work" { github.pulls.adopt(k, repoRoot: root) }
            }
            return events
        }
    }

    func dropPeer(_ name: String) -> [WorldEvent] {
        batch {
            peerSnapshots[name] = nil; peerFirstSeen[name] = nil
            for (key, claims) in peerOffices where claims[name] != nil {
                peerOffices[key]?[name] = nil
                if peerOffices[key]?.isEmpty == true { peerOffices[key] = nil; peerBoxes[key] = nil; held[key] = now }
            }
            return [.peerLeft(name), .markersChanged]
        }
    }

    private(set) var closedAt: [String: Date] = [:]
    func isClosed(_ roomKey: String) -> Bool { closedAt[roomKey] != nil }

    private var deconSettled: Set<CrateID> = []
    private var slicesChecked: Set<String> = []
    private var shippedSettled: Set<String> = []
    private var deconHeard: Set<String> = []
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
