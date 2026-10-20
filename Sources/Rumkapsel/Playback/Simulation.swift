import Foundation

struct Cargo {
    var command: Command; var carrier: String?; var roomKey: String = ""
    var aim: Spot
    var hurry = false
    var gaveUp: Set<String> = []
    var postedAt = 0.0
    var prefer: String?
    var rank = Rank.yard
    let crate: CrateID
    var kind: MoveKind
    var blockedBy: Set<CrateID> = []
    var spot: YardSpot?
}

enum Cue {
    case flush(station: String, bowl: SIMD2<Double>, front: Double)
    case fidget(String)
    case towel(String, station: String, taken: Bool)
    case hop(String)
    case clearCones(String)
    case floor
    case built(String)
    case folds(String)
    case stow(String)
    case ownTaken(String, Command)
    case ownDropped(String, Command)
    case packed(String)
    case redraw
    case hatch(String)
    case appear(String, CrateID)
    case vanish(String, CrateID)
    case sweep(up: Bool)
    case crateOrdered(order: Int, station: String, slot: Int, room: String, color: RGB)
    case crateDropped(order: Int, station: String, slot: Int)
}

enum Hands {
    static let liftFirst = 0.3, liftSecond = 0.35
    static let liftCrouch = 0.45
    static let setDownFirst = 0.35, setDownSecond = 0.45
    static let setDownSettle = 0.3
    static var liftArc: Double { liftFirst + liftSecond }
    static var liftSeconds: Double { liftCrouch + liftArc }
    static var setDownArc: Double { setDownFirst + setDownSecond }
    static var setDownSeconds: Double { setDownArc + setDownSettle }
    static let level = 0.34
    static let arm = 0.34, near = 0.28, far = 0.42
    static let settleSeconds = 2.0
    static let toss = 1.7
    static let floatSeconds = 1.6
    static var tossSeconds: Double { setDownFirst + floatSeconds + setDownSettle }
}

enum Tempo {
    static let substep = 1.0 / 30
    static let beat = 0.5
    static let catchUp = 5.0
    static let frame = 0.25
}

enum Stepped { case waking, spent, posed, gone }

final class Simulation<B: Body> {
    let world: World
    var fleet: Fleet { world.fleet }
    var clock = 0.0
    var substep = Tempo.substep
    var live = false
    private var lastBeat = 0.0
    private var timers: [(at: Double, run: () -> Void)] = []
    var held: String?
    private(set) var stepped: [(body: B, how: Stepped)] = []
    var onBeat: (Bool) -> Void = { _ in }
    var onStep: (Double) -> Void = { _ in }
    var bodies: [String: B] = [:]
    var hooks: SimHooks?
    var cargo: [Int: Cargo] = [:]
    var vortices: [String: Vortex] = [:]
    var drones: [String: [PadDrone]] = [:]
    var ownOrders: [Int: OwnOrder] = [:]
    var idleRoll: () -> Double = { Double.random(in: 0..<1) }
    var spareHallway: [String: (cells: [Cell], since: Double)] = [:]
    var flights: [Flight] = []
    var shown: [String: Shown] = [:]
    var played: Set<String> = []
    var stalls: [String: (mark: String, since: Double)] = [:]
    var stirred: [String: (view: Shown, at: Double)] = [:]
    var calms: [String: Calm] = [:]
    var snapped = 0
    var lastDelivery = 0
    var packageCells: [String: Cell] = [:]
    var marked: [String: OfficeMarks] = [:]
    let epoch = Date()
    var now: Date { live ? Date() : epoch.addingTimeInterval(clock) }
    var visitLog: [(kind: String, lasted: Double, planned: Double)] = []
    private(set) var cues: [Cue] = []
    var onEvent: (WorldEvent) -> Void = { _ in }
    var onLog: (String) -> Void = { _ in }

    init(world: World) {
        self.world = world
        world.clock = { [weak self] in self?.now ?? Date() }
        world.onOffices = { [weak self] st, effects in self?.officesChanged(st, effects) }
        world.onFacts = { [weak self] st, effects in self?.factsChanged(st, effects) }
        world.onLoaded = { [weak self] in self?.loaded() }
    }

    // MARK: time

    func after(_ seconds: Double, _ run: @escaping () -> Void) { timers.append((clock + seconds, run)) }

    func step(dt: Double) {
        guard dt > 0 else { return }
        if dt > Tempo.catchUp {
            clock += dt - substep
            for m in bodies.values { m.stallMark = "" }
            skip()
            tick(substep)
            return
        }
        var left = dt
        while left > 1e-9 { let s = min(left, substep); left -= s; tick(s) }
    }

    private func tick(_ dt: Double) {
        clock += dt
        runTimers()
        if clock - lastBeat > Tempo.beat { lastBeat = clock; beat() }
        stepShuttles()
        stepRockets(dt: dt)
        stepVortices()
        stepDrones(dt: dt)
        stepBodies(dt: dt)
        onStep(dt)
    }

    private func runTimers() {
        guard !timers.isEmpty else { return }
        let due = timers.enumerated().filter { $0.element.at <= clock }
            .sorted { ($0.element.at, $0.offset) < ($1.element.at, $1.offset) }.map(\.element)
        timers.removeAll { $0.at <= clock }
        due.forEach { $0.run() }
    }

    private func beat() {
        world.settle(tick: true)
        play()
        assignOrders()
        reconcileBodies()
        refreshObstacles()
        onBeat(contractHallways())
        replanBlockedWalks()
    }

    func cue(_ c: Cue) { cues.append(c) }
    func drainCues() -> [Cue] { defer { cues = [] }; return cues }

    // MARK: commands

    func handOver(_ m: B, _ c: Command, announce: Bool = false) {
        m.current = nil
        begin(m, c, announce: announce)
    }

    @discardableResult
    func start(_ m: B, _ c: Command, announce: Bool = false) -> Bool {
        guard m.current == nil || (m.wakeUntil == 0 && !m.onJob && m.phaseKind.interruptible) else { return false }
        begin(m, c, announce: announce)
        return true
    }

    func issue(_ c: Command, by who: String, announce: Bool = false) {
        hooks?.onCommand?(c, who)
        if hooks == nil { StationLog.write("command", "\(who): \(c.words)") }
        if announce { onLog(c.words) }
    }

    private func begin(_ m: B, _ c: Command, announce: Bool = false) {
        if case .carry = c.kind, let job = cargo[c.id] {
            if let who = job.carrier, who != m.id { if m.current == nil { send(m, to: restPlace(m)) }; return }
            if job.carrier == nil { cargo[c.id]?.carrier = m.id }
        }
        issue(c, by: m.home.name)
        if let old = m.current, old.kindName != c.kindName, m.state == .settled {
            if case .work = c.kind { m.wonderUntil = clock + 0.15 } else { m.wonderUntil = clock + 0.5 }
        }
        rouse(m)
        if let old = m.current, old.kindName != c.kindName { dropLeftovers(m, of: old) }
        if !c.isRest, !c.holdsMug { m.mugUntil = 0; m.mealUntil = 0 }
        m.current = c
        m.phase = 0
        m.phaseUntil = 0
        m.actFor = c.visitSeconds ?? 0; m.actStartedAt = 0
        if announce { onLog(c.words) }
    }

    func dropLeftovers(_ m: B, of old: Command) {
        m.fetchSpot = nil
        m.seatedOnBowl = false
        m.napping = false
        if m.drying { m.drying = false; cue(.towel(m.id, station: m.station, taken: false)) }
        m.fixture = nil
        m.atCounter = false
        switch old.kind {
        case .bath(_, let back, _), .exercise(_, let back, _), .galley(_, let back, _):
            if m.place == .bath || m.place == .gym || m.place == .galley { m.place = back }
        default: break
        }
    }

    func advance(_ m: B) {
        guard let c = m.current else { return }
        m.phaseUntil = 0
        if m.phase + 1 < c.phases.count { m.phase += 1 }
    }

    func finish(_ m: B, to place: Place? = nil) {
        let last = m.current.map { rank(of: $0) }
        m.current = nil
        m.phase = 0
        m.phaseUntil = 0
        m.fetchSpot = nil
        if takeNext(m) { return }
        if let place { send(m, to: place) } else { idle(m, after: last) }
    }

    func idle(_ m: B, after last: Rank?) {
        guard let station = fleet.stations[m.station], !m.busy, !m.isSubagent, !m.isCrew, !m.isPeer, m.state == .settled else {
            send(m, to: restPlace(m)); return
        }
        switch IdleAfter.after(last, roll: idleRoll(), night: isNight(station), bath: station.rooms["kind:bath"] != nil,
                               galley: m.bathDue == 0 ? galleyFare(m, station: station) : nil) {
        case .rest:
            send(m, to: restPlace(m))
        case .bath(let shower):
            m.showering = shower
            if !visitBath(m, station: station) { send(m, to: restPlace(m)) }
        case .roam:
            if !startRoam(m, station: station) { send(m, to: restPlace(m)) }
        case .galley(let fare):
            if !visitGalley(m, station: station, fare: fare) { send(m, to: restPlace(m)) }
        }
    }

    // MARK: rest and walks

    func dismiss(_ m: B) {
        abandon(m)
        m.state = .leaving
        post(.leave, for: m, rank: .leaving, at: m.cell, place: .hangar)
    }

    func walkOut(_ m: B) {
        m.couch = nil; m.bed = nil
        guard let station = fleet.stations[m.station], let slot = callShip(for: m) else { return }
        m.place = .hangar
        m.path = route(m, to: station.bayStand(slot: slot))
    }

    func isNight(_ station: Station) -> Bool {
        if let forced = hooks?.night { return forced }
        let hour = Calendar.current.component(.hour, from: now)
        return hour >= 22 || hour < 7
    }

    func setNight(_ on: Bool?) {
        hooks?.night = on
        for m in bodies.values where !m.onJob { send(m, to: restPlace(m)) }
        onEvent(.log(on == true ? "night falls" : on == false ? "morning" : "back on the clock"))
    }

    func restPlace(_ m: B) -> Place {
        if m.isSubagent { return probePlace(m) }
        let place = Place.forActivity(m.activity, home: m.home.key, isSubagent: m.isSubagent, night: fleet.stations[m.station].map(isNight) ?? true)
        if case .room(let key) = place, let st = fleet.stations[m.station], !standing(st, key) { return .lounge }
        return place
    }

    func resettle(_ station: Station) {
        for m in bodies.values where m.station == station.name && !m.onJob && m.state != .leaving {
            let cells = station.cells(of: m.place)
            if m.path.isEmpty {
                if m.place == .core || cells.contains(m.cell) { continue }
            } else if let last = m.path.last {
                let dest = Cell(x: Int(last.x.rounded()), y: Int(last.y.rounded()))
                if cells.contains(dest) {
                    m.path = route(m, to: dest)
                    if !m.path.isEmpty || m.cell == dest { continue }
                }
            }
            send(m, to: m.place)
        }
    }

    func send(_ m: B, to place: Place) {
        if let c = m.current, !c.isRest { return }
        guard let station = fleet.stations[m.station] else { return }
        if case .room(let key) = place, !standing(station, key) { return send(m, to: .lounge) }
        if place != .quarters {
            rouse(m)
            m.bed = nil; m.napping = false
        }
        var place = place
        if place == .quarters, m.bed == nil {
            let used = Set(bodies.values.filter { $0.station == m.station && $0.id != m.id }.compactMap(\.bed))
            m.bed = station.beds.indices.first { !used.contains($0) }
            if m.bed == nil { place = .lounge }
        }
        if place != .lounge { m.couch = nil }
        if place == .lounge, m.couch == nil {
            let used = Set(bodies.values.filter { $0.station == m.station && $0.id != m.id }.compactMap(\.couch))
            m.couch = station.couches.indices.first { !used.contains($0) }
        }
        if place == .lounge, let c = m.couch, bodies.values.contains(where: { $0.id != m.id && $0.station == m.station && $0.couch == c }) {
            m.couch = nil
        }
        let cells = station.cells(of: place)
        let target: Cell
        if let b = m.bed, b < station.beds.count { target = station.beds[b].cell }
        else if place == .lounge, let c = m.couch, c < station.couches.count, let lounge = station.rooms["kind:lounge"] {
            let spot = station.couches[c]
            target = lounge.cells.min { a, b in hypot(Double(a.x) - spot.x, Double(a.y) - spot.y) < hypot(Double(b.x) - spot.x, Double(b.y) - spot.y) } ?? lounge.cells[0]
        }
        else {
            let door: Cell? = { if case .room(let k) = place { return station.doorCell(of: k) }; return nil }()
            var spots = cells.filter { $0 != door && !station.thresholds.contains($0) }
            if m.isSubagent { spots = unclaimed(spots, by: m) }
            guard let t = (spots.isEmpty ? cells : spots).randomElement() else { return }
            target = t
        }
        m.place = place
        start(m, .rest(place: place, home: m.home.key, office: station.rooms[m.home.key]?.name ?? m.home.name,
                       yours: !m.isCrew && !m.isPeer, asleep: m.activity == .sleeping))
        m.path = route(m, to: target)
        if m.path.isEmpty, abs(m.pos.x - Double(target.x)) + abs(m.pos.y - Double(target.y)) > 1 { m.path = [SIMD2(Double(target.x), Double(target.y))] }
        m.nextWanderAt = clock + Double.random(in: 1...3)
    }

    func walk(_ m: B, to cell: Cell) { m.path = route(m, to: cell) }

    func rouse(_ m: B) {
        guard m.lying, m.risingUntil == 0 else { return }
        m.risingUntil = clock + 1.1
        m.beddedDown = false
        m.napping = false
        m.bed = nil
    }

    func crowd(around m: B, round blocker: String? = nil) -> Set<Cell> {
        var out: Set<Cell> = []
        for o in bodies.values where o.id != m.id && o.station == m.station && o.state != .leaving && o.opacity > 0.5 {
            if o.lying || (o.couch != nil && o.path.isEmpty) { continue }
            let s = Station.sub(o.pos)
            if o.id == blocker { for dx in -1...1 { for dy in -1...1 { out.insert(Cell(x: s.x + dx, y: s.y + dy)) } } }
            else { out.insert(s) }
        }
        for at in groundHeldByShips(m.station) {
            let c = Station.sub(at)
            for dx in -2...2 { for dy in -2...2 {
                let sub = Cell(x: c.x + dx, y: c.y + dy), p = Station.point(ofSub: sub)
                if hypot(p.x - at.x, p.y - at.y) < Station.bayKeepOff { out.insert(sub) }
            } }
        }
        return out
    }

    func route(_ m: B, to cell: Cell, round blocker: String? = nil) -> [SIMD2<Double>] {
        guard let station = fleet.stations[m.station] else { return [] }
        rouse(m)
        var from = m.pos, back: [SIMD2<Double>] = []
        if !station.walkable.contains(m.cell), let floor = station.nearestFloor(to: m.pos) {
            from = SIMD2(Double(floor.x), Double(floor.y))
            back = [from]
            if floor == cell { return back }
        }
        let clear = station.path(from: from, to: cell, avoiding: crowd(around: m, round: blocker))
        return back + (clear.isEmpty ? station.path(from: from, to: cell) : clear)
    }

    func replanBlockedWalks() {
        for m in bodies.values where !m.path.isEmpty {
            guard let station = fleet.stations[m.station] else { continue }
            let blocked = m.path.contains { station.obstacles.contains(Station.sub($0)) }
            guard blocked, clock - m.lastReplanAt >= 1, let last = m.path.last else { continue }
            m.lastReplanAt = clock
            m.path = route(m, to: Cell(x: Int(last.x.rounded()), y: Int(last.y.rounded())))
        }
    }

    func contractHallways() -> Bool {
        guard !world.settling else { return false }
        var changed = false
        for station in fleet.stations.values {
            let spare = station.spareHallway()
            guard !spare.isEmpty else { spareHallway[station.name] = nil; continue }
            if spareHallway[station.name]?.cells != spare { spareHallway[station.name] = (spare, clock) }
            guard clock - spareHallway[station.name]!.since >= Patience.hallwayKept else { continue }
            let cells = Set(spare)
            let used = bodies.values.contains { m in m.station == station.name && walks(m, across: cells) }
                || station.obstacles.contains { cells.contains(Station.cell(ofSub: $0)) }
            guard !used else { continue }
            station.giveBack(spare)
            spareHallway[station.name] = nil
            changed = true
        }
        return changed
    }

    private func walks(_ m: B, across cells: Set<Cell>) -> Bool {
        func on(_ p: SIMD2<Double>) -> Bool { cells.contains(Cell(x: Int(p.x.rounded()), y: Int(p.y.rounded()))) }
        if on(m.pos) { return true }
        var at = m.pos
        for leg in m.path {
            let d = leg - at
            let steps = max(1, Int(((d.x * d.x + d.y * d.y).squareRoot() * 5).rounded(.up)))
            for i in 1...steps where on(at + d * (Double(i) / Double(steps))) { return true }
            at = leg
        }
        return false
    }

    // MARK: hands

    func atArmsLength(_ m: B, of spot: SIMD2<Double>, from side: SIMD2<Double>? = nil, square: Bool = false, dt: Double) -> Bool {
        let to = spot - m.pos
        let dist = (to.x * to.x + to.y * to.y).squareRoot()
        if dist > 0.05 { m.facing = atan2(to.x, to.y) }
        if dist > 0.9, let st = fleet.stations[m.station] {
            let near = side.map { spot + $0 } ?? spot
            let stand = standCell(st, near: Cell(x: Int(near.x.rounded()), y: Int(near.y.rounded())))
            let fromStand = SIMD2(Double(stand.x), Double(stand.y)) - spot
            let stepping = dist < (fromStand.x * fromStand.x + fromStand.y * fromStand.y).squareRoot() + 0.1
            if m.path.isEmpty, m.cell != stand, !stepping {
                let path = route(m, to: stand)
                let end = path.last.map { Cell(x: Int($0.x.rounded()), y: Int($0.y.rounded())) } ?? m.cell
                if end != m.cell || dist > 1.6 { m.path = path; return false }
            }
        }
        guard m.path.isEmpty else { return false }
        if square, let side, side.x != 0 || side.y != 0 {
            let want = spot + side / (side.x * side.x + side.y * side.y).squareRoot() * Hands.arm
            m.pos += (want - m.pos) * min(1, dt * 6)
            return (want - m.pos).x.magnitude + (want - m.pos).y.magnitude <= 0.02
        }
        let toss = fleet.stations[m.station].flatMap { tossFrom($0, to: Cell(x: Int(spot.x.rounded()), y: Int(spot.y.rounded()))) } != nil
        let reach = toss ? Hands.toss : Hands.arm
        guard dist < reach - (Hands.arm - Hands.near) || dist > reach + (Hands.far - Hands.arm) else { return true }
        let dir = dist > 0.001 ? to / dist : SIMD2(sin(m.facing), cos(m.facing))
        let want = spot - dir * reach
        m.pos += (want - m.pos) * min(1, dt * 6)
        return (want - m.pos).x.magnitude + (want - m.pos).y.magnitude <= 0.02
    }

    func standCell(_ st: Station, near cell: Cell) -> Cell {
        func blocked(_ c: Cell) -> Int {
            var n = 0
            for dx in -1...1 {
                for dy in -1...1 where st.obstacles.contains(Cell(x: c.x * Station.fine + dx, y: c.y * Station.fine + dy)) { n += 1 }
            }
            return n
        }
        let rows = st.hall.crateRows
        if let back = st.hall.backRow(cell) {
            let stand = tossFrom(st, to: cell) ?? back.over
            guard blocked(stand) > 0 else { return stand }
            let beside = stand.neighbours.filter { st.walkable.contains($0) && !rows.contains($0) && blocked($0) == 0 }
            return beside.min { abs($0.x - cell.x) + abs($0.y - cell.y) < abs($1.x - cell.x) + abs($1.y - cell.y) } ?? stand
        }
        if blocked(cell) == 0, st.walkable.contains(cell), !rows.contains(cell) { return cell }
        let options = cell.neighbours.filter { st.walkable.contains($0) }
        let aisle = options.filter { !rows.contains($0) }
        return (aisle.isEmpty ? options : aisle).min { blocked($0) < blocked($1) } ?? st.nearestFloor(to: SIMD2(Double(cell.x), Double(cell.y))) ?? cell
    }

    func tossFrom(_ st: Station, to cell: Cell) -> Cell? {
        guard let back = st.hall.backRow(cell) else { return nil }
        let f = Station.fine
        let taken = (-1...1).contains { dx in (-1...1).contains { dy in st.obstacles.contains(Cell(x: back.over.x * f + dx, y: back.over.y * f + dy)) } }
        return taken ? back.aisle : nil
    }

    func startLift(_ m: B, height: Double, far: Bool = false) {
        m.floating = far
        m.handsAt = far ? 2 : max(0, Int((height / Hands.level).rounded()))
        m.phaseUntil = clock + (far ? Hands.liftCrouch + Hands.floatSeconds : Hands.liftSeconds)
    }

    func liftDue(_ m: B) -> Bool { clock >= m.phaseUntil - (m.floating ? Hands.floatSeconds : Hands.liftArc) }

    // MARK: the idle life

    @discardableResult
    func visitBath(_ m: B, station: Station) -> Bool {
        guard let bath = station.rooms["kind:bath"] else { return false }
        let taken = Set(bodies.values.filter { $0.id != m.id && $0.station == m.station && $0.bathing }.compactMap(\.fixture))
        let want = m.showering ? 1 : 0
        guard let fixture = [want, 1 - want].first(where: { !taken.contains($0) }) else { return false }
        m.showering = fixture == 1
        m.bathDue = 0
        let back = m.place
        send(m, to: .bath)
        guard start(m, .bath(m.showering ? .shower : .quick, back: back, seconds: m.showering ? Double.random(in: 120...180) : 60)) else { return false }
        m.fixture = fixture
        let f = station.bathFixtures(bath: bath)
        let cell = m.showering ? f.shower : f.toilet
        m.path = route(m, to: cell)
        let nozzle = station.showerNozzle(bath: bath)
        m.fetchSpot = m.showering ? SIMD2(nozzle.x - station.offset.x, nozzle.y - station.offset.y)
                                  : SIMD2(Double(cell.x) + 0.02 * f.toiletCorner.x, Double(cell.y) - 0.1 * f.toiletCorner.y)
        m.facing = m.showering ? atan2(f.showerCorner.x, -f.showerCorner.y) : atan2(f.toiletCorner.x, f.toiletCorner.y)
        return true
    }

    func pickIdle(_ m: B, station: Station) {
        let gymFree = station.rooms["kind:gym"] != nil && freeGymFixture(m) != nil
        let pick = IdlePick.pick(roll: Double.random(in: 0..<1), night: isNight(station), crew: m.isCrew,
                                 gymFree: gymFree, bath: station.rooms["kind:bath"] != nil, shower: Bool.random(),
                                 galley: galleyFare(m, station: station))
        switch pick {
        case .roam:
            startRoam(m, station: station)
        case .gym:
            if let gym = station.rooms["kind:gym"], takeTurnInGym(m, station: station, gym: gym) { return }
            startRoam(m, station: station)
        case .bath(let shower):
            m.showering = shower
            if visitBath(m, station: station) { return }
            startRoam(m, station: station)
        case .galley(let fare):
            if visitGalley(m, station: station, fare: fare) { return }
            startRoam(m, station: station)
        case .read:
            break
        }
    }

    func galleyFare(_ m: B, station: Station) -> Command.Fare? {
        guard station.galley != nil, !isNight(station), !m.isCrew,
              !bodies.values.contains(where: { $0.id != m.id && $0.station == m.station && $0.fare != nil }) else { return nil }
        let hour = Calendar.current.component(.hour, from: now)
        return (11..<14).contains(hour) || (18..<20).contains(hour) ? .bite : .coffee
    }

    @discardableResult
    func visitGalley(_ m: B, station: Station, fare: Command.Fare) -> Bool {
        guard let galley = station.galley,
              !bodies.values.contains(where: { $0.id != m.id && $0.station == m.station && $0.fare != nil }) else { return false }
        let back = m.place == .lounge || m.place == .room(m.home.key) ? m.place : restPlace(m)
        guard start(m, .galley(fare, back: back, seconds: Double.random(in: fare.seconds)), announce: true) else { return false }
        m.couch = nil; m.bed = nil; m.napping = false
        m.place = .galley
        m.path = route(m, to: galley.cell)
        return true
    }

    @discardableResult
    func startRoam(_ m: B, station: Station) -> Bool {
        let rocketReady = (shown[station.name]?.rockets ?? [:]).contains { $0.value.venting || station.facts.rockets[$0.key]?.launched == true }
        let window = station.hall.windowWatch
        let doorways = Set(station.yardDoorways.flatMap { [$0.0, $0.1] } + station.rooms.keys.compactMap { station.doorOutside(of: $0) })
            .subtracting(window)
        let clear = (rocketReady && !window.isEmpty ? window : station.corridorCells + station.hall.aisleCells + station.hall.walkwayCells)
            .filter { !doorways.contains($0) }
            .filter { c in (-1...1).allSatisfy { dx in (-1...1).allSatisfy { dy in !station.obstacles.contains(Cell(x: c.x * Station.fine + dx, y: c.y * Station.fine + dy)) } } }
        let others = bodies.values.filter { $0.id != m.id && $0.station == m.station }
        let taken = others.map(\.cell) + others.compactMap { o -> Cell? in if case .chore(let spot, _) = o.current?.kind { return spot }; return nil }
        guard let spot = RoamSpots.choose(clear: clear, taken: taken, company: rocketReady) else { return false }
        start(m, .chore(spot: spot, seconds: Double.random(in: 120...240)))
        guard case .chore = m.current?.kind else { return false }
        m.couch = nil
        m.place = .core
        m.path = route(m, to: spot)
        m.nextWanderAt = clock + 60
        return true
    }

    func visitDone(_ m: B, _ kind: String) {
        guard hooks != nil else { return }
        visitLog.append((kind: kind, lasted: m.actStartedAt > 0 ? clock - m.actStartedAt : 0, planned: m.actFor))
    }

    @discardableResult
    func takeTurnInGym(_ m: B, station: Station, gym: Room) -> Bool {
        guard let kind = freeGymFixture(m) else { return false }
        let back = m.place
        m.couch = nil
        send(m, to: .gym)
        start(m, .exercise(kind, back: back, seconds: Double.random(in: 240...480)), announce: true)
        let stand = station.gymStand(gym: gym, kind)
        m.path = route(m, to: stand.cell)
        m.fetchSpot = stand.spot
        m.facing = stand.facing
        return true
    }

    func freeGymFixture(_ m: B) -> Command.Workout? {
        let taken = Set(bodies.values.filter { $0.id != m.id && $0.station == m.station && $0.exercising }.compactMap(\.workout))
        return Command.Workout.allCases.filter { !taken.contains($0) }.randomElement()
    }

    // MARK: crew

    func react(_ m: B, _ activity: Activity, place: Place, minutes: Double, words: String) {
        m.activity = activity
        m.busy = true
        if case .react = m.current?.kind, let id = m.current?.id { ownOrders[id] = nil; m.current = nil; m.phase = 0; m.phaseUntil = 0 }
        if m.lying { m.napping = false; m.bed = nil; m.beddedDown = false }
        post(.react(activity, place: place, for: minutes * 60, words: words), for: m, rank: .crew, at: m.cell, place: place)
    }

    func crewRested(_ m: B) {
        m.busy = false
        m.activity = .sleeping
        m.pyramidCell = nil
        cue(.clearCones(m.id))
        if case .react = m.current?.kind, let id = m.current?.id { ownOrders[id] = nil; m.current = nil; m.phase = 0; m.phaseUntil = 0 }
        send(m, to: .quarters)
    }

    // MARK: the step

    enum Stride {
        case waking
        case walking
        case wondering
        case there
    }

    enum Outcome {
        case posed
        case spent
        case gone
    }

    func stepWalk(_ m: B, station: Station, dt: Double) -> Stride {
        m.waitingOn = nil
        let hurried = m.current.flatMap { cargo[$0.id]?.hurry } ?? false
        let pacing = m.isPacing(at: clock)
        let speed = m.wedged ? 0 : m.isHauling ? (hurried ? 1.7 : 1.1) : (clock < m.strollUntil ? 1.0 : (m.busy ? 2.4 : (pacing ? 0.8 : 1.4)))
        if !m.onJob, station.hangarCells.contains(m.cell), flights.contains(where: { f in
            guard f.station == m.station, f.phaseKind == .descend || f.phaseKind == .unload else { return false }
            if case .flight(.bringWorker(let id), _, _) = f.command.kind, id == m.id { return false }
            return true
        }) {
            m.waitingOn = Words.current.shipBeside
            return .waking
        }
        if m.risingUntil > 0 {
            if clock < m.risingUntil { return .waking }
            m.risingUntil = 0
        }
        if m.wakeUntil > 0 {
            if clock < m.wakeUntil { return .waking }
            m.wakeUntil = 0
        }
        if !m.path.isEmpty, clock >= m.wonderUntil {
            let others: [Body] = bodies.values.filter { o in
                o.id != m.id && o.station == m.station && o.state != .leaving && o.opacity > 0.5
                    && !o.lying && !(o.couch != nil && o.path.isEmpty)
            }
            m.blockedBy = Walk.step(m, speed: speed, dt: dt, others: others)?.id
            return .walking
        }
        return m.path.isEmpty ? .there : .wondering
    }

    func stepThere(_ m: B, station: Station, dt: Double) -> Outcome {
        if let crate = stepCrate(m, station: station, dt: dt) { return crate }
        if case .react(_, _, let seconds) = m.current?.kind {
            if m.phaseKind == .walk { advance(m); m.phaseUntil = clock + seconds; return .spent }
            if clock >= m.phaseUntil { crewRested(m) }
        }
        if m.path.isEmpty, m.phaseKind == .walk, let c = m.current {
            switch c.kind {
            case .goTo, .bath, .exercise, .galley, .chore, .qa, .sleep, .work, .react, .leave, .pack, .stow:
                advance(m)
                if case .work = c.kind { ownOrders[c.id] = nil }
                if m.actFor > 0 { m.phaseUntil = clock + m.actFor; m.actStartedAt = clock }
            default: break
            }
        }
        switch m.state {
        case .arriving:
            m.state = .settled
        case .settled:
            if m.isQA, clock >= m.nextWanderAt {
                let stacks = Dictionary(grouping: Layout.spots(station.facts, station.yard).values.filter { $0.zone == .testing }, by: \.column)
                    .values.compactMap { $0.min { $0.level < $1.level } }.sorted { $0.column < $1.column }
                if !stacks.isEmpty {
                    let stack = stacks[m.qaStop % stacks.count]
                    m.qaStop += 1
                    let aisle = [Cell(x: stack.cell.x, y: stack.cell.y - 1), Cell(x: stack.cell.x, y: stack.cell.y + 1)]
                        .first { station.hall.deckCells.contains($0) } ?? stack.cell
                    m.path = route(m, to: aisle)
                    m.facing = atan2(stack.pos.x - station.offset.x - Double(aisle.x), stack.pos.z - station.offset.y - Double(aisle.y))
                }
                m.nextWanderAt = clock + Double.random(in: 4...7)
                if clock >= m.nextImpatience {
                    m.nextImpatience = clock + Double.random(in: 5...9)
                    cue(.hop(m.id))
                }
            }
            if m.busy && !m.wasBusy { m.busySince = clock; m.bathDue = 0 }
            if !m.busy && m.wasBusy && !m.isSubagent {
                let stretch = clock - m.busySince
                if stretch > 20 * 60 { m.bathDue = clock + Double.random(in: 3...20); m.showering = true }
                else if stretch > 3 * 60 { m.shortStretches += 1; if m.shortStretches % 2 == 0 { m.bathDue = clock + Double.random(in: 3...20); m.showering = false } }
            }
            m.wasBusy = m.busy
            let settled = m.path.isEmpty
            if m.isChore {
                if settled, m.phase > 0, clock >= m.phaseUntil { visitDone(m, "roam"); finish(m, to: .lounge) }
            } else if m.place == .lounge, !m.busy, m.isResting, settled, !m.isSubagent, m.bathDue == 0, !m.hasLoad {
                if m.idle.tick(at: clock, lounging: true, busy: false) { pickIdle(m, station: station); return .spent }
            }
            if m.busy { _ = m.idle.tick(at: clock, lounging: false, busy: true) }
            if m.place == .bath {
                if settled, let spot = m.fetchSpot {
                    let d = spot - m.pos
                    if (d.x * d.x + d.y * d.y).squareRoot() > 0.03 { m.pos += d * min(1, dt * 5); return .spent }
                    m.fetchSpot = nil
                    if let bath = station.rooms["kind:bath"] {
                        let f = station.bathFixtures(bath: bath)
                        let corner = m.showering ? f.showerCorner : f.toiletCorner
                        m.facing = m.drying ? atan2(f.showerCorner.x, 0) : atan2(corner.x, corner.y)
                    }
                }
                if settled, !m.showering, let bath = station.rooms["kind:bath"] {
                    let standAt = m.phaseUntil - 0.7
                    let bowl = station.bowlSpot(bath: bath)
                    let f = station.bathFixtures(bath: bath)
                    if !m.seatedOnBowl, clock < standAt, m.phaseUntil > 0 {
                        let to = bowl - station.offset - m.pos
                        m.facing = atan2(0, -f.toiletCorner.y)
                        let across = to.x * cos(m.facing) - to.y * sin(m.facing), ahead = to.x * sin(m.facing) + to.y * cos(m.facing)
                        m.seatedOnBowl = true
                        m.seatOffset = SIMD2(across, ahead - 0.02 + B.seatReach)
                        m.nextFidgetAt = clock + Double.random(in: 1.5...3)
                    } else if m.seatedOnBowl, clock >= standAt {
                        m.seatedOnBowl = false
                        cue(.flush(station: station.name, bowl: bowl, front: f.toiletCorner.y))
                    } else if m.seatedOnBowl, clock >= m.nextFidgetAt {
                        m.nextFidgetAt = clock + Double.random(in: 1.5...3.5)
                        cue(.fidget(m.id))
                    }
                }
                if clock >= m.phaseUntil && settled {
                    if m.showering, !m.drying, let bath = station.rooms["kind:bath"] {
                        m.drying = true
                        m.phaseUntil = clock + 4
                        m.fetchSpot = station.towelStand(bath: bath) - station.offset
                        cue(.towel(m.id, station: station.name, taken: true))
                    } else {
                        if m.drying { m.drying = false; cue(.towel(m.id, station: station.name, taken: false)) }
                        m.seatedOnBowl = false
                        m.fixture = nil
                        var back = restPlace(m)
                        if !m.busy, case .bath(_, let where_, _) = m.current?.kind { back = where_ }
                        visitDone(m, "bath")
                        finish(m, to: back)
                    }
                }
            } else if m.bathDue > 0, clock >= m.bathDue, !m.busy, !m.onJob, !m.hasLoad, !m.isSubagent, m.fare == nil, m.place != .quarters, settled, station.rooms["kind:bath"] != nil {
                if !visitBath(m, station: station) { return .spent }
            }
            if m.place == .gym, m.exercising {
                if settled, let spot = m.fetchSpot {
                    let d = spot - m.pos
                    if (d.x * d.x + d.y * d.y).squareRoot() > 0.03 { m.pos += d * min(1, dt * 5); return .spent }
                    m.fetchSpot = nil
                    if let gym = station.rooms["kind:gym"], let kind = m.workout { m.facing = station.gymStand(gym: gym, kind).facing }
                }
                if clock >= m.phaseUntil && settled && m.fetchSpot == nil {
                    var back = restPlace(m)
                    if !m.busy, case .exercise(_, let where_, _) = m.current?.kind { back = where_ }
                    visitDone(m, "gym")
                    finish(m, to: back)
                }
            }
            if m.place == .galley, let fare = m.fare, let galley = station.galley {
                if settled, m.phaseKind == .act {
                    if !m.atCounter {
                        guard atArmsLength(m, of: galley.machine(fare), from: -galley.back, square: true, dt: dt) else { return .spent }
                        m.atCounter = true
                        m.actStartedAt = clock
                        m.phaseUntil = clock + m.actFor
                    }
                    m.facing = galley.facing
                }
                if m.atCounter, clock >= m.phaseUntil {
                    var back = restPlace(m)
                    if !m.busy, case .galley(_, let where_, _) = m.current?.kind { back = fare == .bite ? .lounge : where_ }
                    switch fare {
                    case .coffee: m.mugUntil = clock + Double.random(in: 150...360)
                    case .bite: m.mealFor = Double.random(in: 70...110); m.mealUntil = clock + m.mealFor
                    }
                    visitDone(m, "galley")
                    m.atCounter = false
                    finish(m, to: back)
                    return .spent
                }
            }
            if m.isSubagent, settled { makeRoom(m, station: station); tripOn(m, station: station) }
            if let pc = m.pyramidCell, !m.onJob, m.place == .room(m.home.key) {
                if abs(m.cell.x - pc.x) + abs(m.cell.y - pc.y) > 1 { walk(m, to: pc) }
            } else if clock >= m.nextWanderAt, m.activity != .sleeping, !m.bathing, !m.exercising, m.place != .quarters, !(m.place == .lounge && m.couch != nil), !m.isJumping(at: clock) {
                let door: Cell? = { if case .room(let k) = m.place { return station.doorCell(of: k) }; return nil }()
                var choices = station.cells(of: m.place).filter { $0 != m.cell && $0 != door && !station.thresholds.contains($0) }
                if m.isSubagent { choices = unclaimed(choices, by: m) }
                if let dest = choices.randomElement() { m.path = route(m, to: dest) }
                m.nextWanderAt = clock + (m.isPacing(at: clock) ? Double.random(in: 2.5...6) : m.busy ? Double.random(in: 2...5) : Double.random(in: 8...20))
            }
        case .leaving:
            if m.isSubagent { return dock(m, station: station, dt: dt) }
            guard let ship = pickup(for: m), case .flight(_, _, let slot) = ship.command.kind, slot < station.hangarSlots.count else {
                if station.hangarSlots.isEmpty || station.hangarCells.contains(m.cell) {
                    m.opacity -= dt * 1.2
                    if m.opacity <= 0 { return .gone }
                }
                return .posed
            }
            guard m.path.isEmpty else { return .posed }
            if m.phaseKind == .walk { advance(m) }
            let berth = station.hangarSlots[slot]
            guard ship.phaseKind == .unload else {
                m.waitingOn = Words.current.shipComing
                let d = berth - m.pos
                m.facing = atan2(d.x, d.y)
                return .posed
            }
            guard atArmsLength(m, of: berth, dt: dt) else { return .posed }
            m.opacity -= dt * 1.6
            if m.opacity <= 0 { return .gone }
        }
        return .posed
    }

    func stepBodies(dt: Double) {
        stepped = []
        for m in Array(bodies.values) where m.id != held {
            guard let station = fleet.stations[m.station] else { forget(m); stepped.append((m, .gone)); continue }
            stepped.append((m, stepBody(m, station: station, dt: dt)))
        }
    }

    private func stepBody(_ m: B, station: Station, dt: Double) -> Stepped {
        switch stepWalk(m, station: station, dt: dt) {
        case .waking: return .waking
        case .walking, .wondering: break
        case .there:
            switch stepThere(m, station: station, dt: dt) {
            case .gone: forget(m); return .gone
            case .spent: return .spent
            case .posed: break
            }
        }
        stepRest(m, station: station, dt: dt)
        return .posed
    }

    func stepRest(_ m: B, station: Station, dt: Double) {
        if m.state != .leaving { m.opacity = min(1, m.opacity + dt * 0.9) }
        if m.path.isEmpty, m.isResting, m.place == .lounge, let c = m.couch, c < station.couches.count {
            let spot = station.couches[c]
            var stand = spot
            if let lounge = station.rooms["kind:lounge"], !lounge.cells.isEmpty {
                let xs = lounge.cells.map { Double($0.x) }, ys = lounge.cells.map { Double($0.y) }
                let mid = SIMD2(xs.reduce(0, +) / Double(xs.count), ys.reduce(0, +) / Double(ys.count))
                let d = mid - spot, far = (d.x * d.x + d.y * d.y).squareRoot()
                if far > 0.01 {
                    stand = spot + d / far * B.seatReach
                    if m.onCouch { m.facing = atan2(d.x, d.y) }
                }
            }
            m.pos += (stand - m.pos) * min(1, dt * 4)
        }
        if m.path.isEmpty, m.isResting, m.place == .quarters, let b = m.bed, b < station.beds.count {
            let spot = station.beds[b].pos
            let aim = m.path.first ?? m.pos
            let outward = SIMD2(aim.x >= spot.x ? 1.0 : -1.0, 0)
            let stand = spot + outward * B.seatReach
            if !m.beddedDown, m.beddingUntil == 0, m.activity == .sleeping || m.napping {
                let gap = stand - m.pos
                if (gap.x * gap.x + gap.y * gap.y).squareRoot() < 0.08 {
                    m.beddingUntil = clock + 1.1 + Double.random(in: 0...0.8)
                    m.facing = atan2(outward.x, outward.y)
                }
            }
            if m.beddingUntil > 0, clock >= m.beddingUntil { m.beddingUntil = 0; m.beddedDown = true }
            let stretching = m.beddingUntil > 0 && m.beddingUntil - clock <= B.riseSit
            m.pos += ((m.lying || stretching ? spot : stand) - m.pos) * min(1, dt * 4)
        }
    }
}
