// The station apart from the picture: the clock, the bodies and the orders they run, the walks, the
// rest, the idle life and the hands. No SceneKit here. The scene draws what this says, frame by
// frame, and decides nothing: it reads a body's place, pose and load, and plays the cues it is handed.
// `Simulation<Minion>` is what the app runs; `Simulation<Body>` is what a model-only test can step.
//
// The scene's own are the nodes, the poses, the sounds and the decorations, and the reactions to a
// landing that redraw the rows; what it cannot see for itself is a cue from here.

import Foundation

/// A crate in motion: the command that moves it and what to do when it lands. The node that draws
/// it is the scene's, kept by command id.
struct Cargo {
    var command: Command; let onDone: () -> Void; var carrier: String?; var roomKey: String = ""
    /// The place the carry is aimed at: asked for when the order is taken, again with the crate on
    /// the arms, and grounded at set-down. The command itself names only the yard.
    var aim: Spot
    /// Carries queued behind this one: the carrier picks up the pace.
    var hurry = false
    /// Who gave this carry up: passed over for it while anyone else is free.
    var gaveUp: Set<String> = []
}

/// Something the simulation decided this tick that the scene shows once.
enum Cue {
    /// The bowl flushes behind a sitter who just stood up.
    case flush(station: String, bowl: SIMD2<Double>, front: Double)
    /// A sitter shuffles on the seat.
    case fidget(String)
    /// The towel comes off the rail onto a body's shoulders, or goes back.
    case towel(String, station: String, taken: Bool)
    /// The QA walker hops with impatience.
    case hop(String)
    /// A teammate's cones go with the end of their reaction.
    case clearCones(String)
    /// A carry landed: whatever the scene meant to do when it did.
    case landed(Cargo)
    /// A new office's crate is set down on its slot: the office unfolds round it.
    case reveal(String)
    /// The office an unfetched crate was for is gone: the crate folds away on the bay.
    case foldCrate(String)
    /// The cube on a body's head goes down onto its place on the floor.
    case stow(String)
    /// An office's package is packed and strapped, by key.
    case packed(String)
    /// The rows are drawn again.
    case redraw
    /// A crate leaves the ground for the pallet, or the pallet for a yard; and it came down.
    case palletLift(station: String, crate: CrateRef)
    case palletLanded(station: String, crate: CrateRef, aboard: Bool)
    /// A carry was ordered: the scene finds the crate's node for the arms.
    case carryOrdered(id: Int, crate: CrateRef)
    /// A shuttle is inbound, or a rocket goes up: the drone's sweep.
    case sweep(up: Bool)
    /// A new office's crate: ordered onto its bay slot, unseen; then dropped there by the ship.
    case crateOrdered(key: String, station: String, slot: Int, repo: String)
    case crateDropped(key: String, station: String, slot: Int)
    /// A rocket, by "station|repo": cleared to load, lifting off, steaming, gone; a crate into its hold.
    case rocketLoading(key: String)
    case liftOff(key: String)
    case steam(key: String)
    case rocketGone(key: String)
    case intoHold(key: String, command: Int)
}

/// Everything a crate does between two slots is timed from here. Every crate that moves by hand — a
/// carry, an office delivery, anything later — goes through one lift and one set-down, so there is one
/// lift on the station and one set-down. The arcs the scene draws and the phases the simulation times
/// are both derived from these numbers and nowhere else, so the two cannot drift.
enum Hands {
    /// The crate's two legs off its slot: back at its own height, then up onto the arms.
    static let liftFirst = 0.3, liftSecond = 0.35
    /// Crouched over it before the hands take hold.
    static let liftCrouch = 0.45
    /// Out of the arms, over the slot, and squarely down onto it.
    static let setDownFirst = 0.35, setDownSecond = 0.45
    /// A beat standing over it before straightening up.
    static let setDownSettle = 0.3
    static var liftArc: Double { liftFirst + liftSecond }
    static var liftSeconds: Double { liftCrouch + liftArc }
    static var setDownArc: Double { setDownFirst + setDownSecond }
    static var setDownSeconds: Double { setDownArc + setDownSettle }
    /// How high one crate stands on the next.
    static let level = 0.34
    /// An arm's length, and the slack either side of it.
    static let arm = 0.34, near = 0.28, far = 0.42
    /// How long a crate takes to settle down a level when the one under it is taken away.
    /// Low gravity in the yard: a crate with nothing under it any more takes its time coming down.
    static let settleSeconds = 2.0
}

final class Simulation<B: Body> {
    let world: World
    var fleet: Fleet { world.fleet }
    /// Station time: the wall clock in the app, the simulated clock in a simulator.
    var clock = 0.0
    var bodies: [String: B] = [:]
    /// Set only in a simulator: the event and command taps, the forced night, the clock the panel drives.
    var hooks: SimHooks?
    /// Crates under way, by command id.
    var cargo: [Int: Cargo] = [:]
    /// The one hover pallet a station may have out, by station name, and the wishes for pallets not
    /// out yet: true pushes it to the deck once loaded, false empties it back into storage.
    var pallets: [String: PalletJob] = [:]
    var palletWishes: [String: Bool] = [:]
    /// Every shuttle in the air, and one rocket per repository with a release on the pad, by "station|repo".
    var flights: [Flight] = []
    var rockets: [String: RocketJob] = [:]
    /// Station time as a date: the wall clock in the app, the simulated clock in a simulator, so a slow
    /// frame can never age a session or a landing.
    private let epoch = Date()
    var now: Date { hooks != nil ? epoch.addingTimeInterval(clock) : Date() }
    /// Visits that ran their course in a simulated run: kind, how long from arrival, and how long planned.
    var visitLog: [(kind: String, lasted: Double, planned: Double)] = []
    /// What the scene shows once, drained every frame.
    private(set) var cues: [Cue] = []
    /// The scene's ears: every event, and every line for the log.
    var onEvent: (WorldEvent) -> Void = { _ in }
    var onLog: (String) -> Void = { _ in }

    init(world: World) {
        self.world = world
        // What the world cannot see for itself: a rocket mid-load, which keeps the yard's crates where they are.
        world.rocketBusy = { [weak self] key in self?.rockets[key]?.isBusy ?? false }
    }

    func cue(_ c: Cue) { cues.append(c) }
    func drainCues() -> [Cue] { defer { cues = [] }; return cues }

    // MARK: commands

    /// A command that has run its course hands over to its successor: the pallet's push to its unload.
    /// Not a new order cutting in, so the interruptible rule does not apply.
    func handOver(_ m: B, _ c: Command, announce: Bool = false) {
        m.current = nil
        begin(m, c, announce: announce)
    }

    /// The one way to give a body an order. It takes over at the next interruptible phase; mid-lift or
    /// setting down it waits its turn, and only one waits at a time.
    func start(_ m: B, _ c: Command, announce: Bool = false) {
        guard m.current == nil || canInterrupt(m, with: c) else { m.pending = c; return }
        begin(m, c, announce: announce)
    }

    /// Walking and standing about can be cut into; a crouch cannot, and a carry only to send the
    /// crate on the arms somewhere else.
    private func canInterrupt(_ m: B, with c: Command) -> Bool {
        guard m.wakeUntil == 0 else { return false }   // still stepping out of the shuttle
        // A job holds something and is not simply dropped: only another job may cut in on it. A rest
        // or a message waits its turn, and begins the moment the job is done.
        if m.onJob, !c.isJob { return false }
        let phase = m.phaseKind
        if phase.takesNewDestination {
            guard let held = m.current?.crate, let want = c.crate else { return false }
            return held == want
        }
        return phase.interruptible
    }

    /// Every command issued, whoever runs it, goes past the taps: the log line and the panel.
    func issue(_ c: Command, by who: String, announce: Bool = false) {
        hooks?.onCommand?(c, who)
        if hooks == nil { StationLog.write("command", "\(who): \(c.words)") }
        if announce { onLog(c.words) }
    }

    private func begin(_ m: B, _ c: Command, announce: Bool = false) {
        // A carry is one body's from the moment it begins, however it began: from the scheduler or
        // from the pending slot after a pack. Somebody else already on it means this one stands down.
        if case .carry = c.kind, let job = cargo[c.id] {
            if let who = job.carrier, who != m.id { m.pending = nil; if m.current == nil { send(m, to: restPlace(m)) }; return }
            if job.carrier == nil { cargo[c.id]?.carrier = m.id }
        }
        issue(c, by: m.home.name)
        // Redirected mid-carry: keep the crate and walk on to the new spot.
        let redirected = m.hasLoad && m.current?.crate != nil && m.current?.crate == c.crate
        // A change of orders is visible: a beat standing, head up, then off. A message from you is urgent.
        if let old = m.current, !redirected, old.kindName != c.kindName, m.state == .settled {
            if case .work = c.kind { m.wonderUntil = clock + 0.15 } else { m.wonderUntil = clock + 0.5 }
        }
        // The order in hand owns the body's posture. A new order of another kind drops the old one's
        // leftovers, so nobody carries a fixture, a seat, a towel or a spot to shuffle to into the next thing.
        if let old = m.current, !redirected, old.kindName != c.kindName { dropLeftovers(m, of: old) }
        m.current = c
        m.phase = redirected ? (c.phases.firstIndex(of: .haul) ?? 0) : 0
        m.phaseUntil = 0
        m.actFor = c.visitSeconds ?? 0; m.actStartedAt = 0   // the order carries its visit's length; the clock starts on arrival
        // A job waiting its turn is not wiped by a rest re-planned over it: it begins when the rest ends.
        if !(c.isRest && m.pending?.isJob == true) || m.pending?.id == c.id { m.pending = nil }
        if announce { onLog(c.words) }
        if redirected, let aim = cargo[c.id]?.aim { walk(m, to: aim.cell) }
    }

    /// What an order leaves on the body when another cuts in: the spot it was shuffling to, the seat, the
    /// bench, the fixture it held, the towel; and a visit's place, which goes back to where the visit began.
    private func dropLeftovers(_ m: B, of old: Command) {
        m.fetchSpot = nil
        m.seated = false
        m.onBench = false
        if m.drying { m.drying = false; cue(.towel(m.id, station: m.station, taken: false)) }
        m.fixture = nil
        switch old.kind {
        case .bath(_, let back, _), .exercise(_, let back, _): if m.place == .bath || m.place == .gym { m.place = back }
        default: break
        }
    }

    /// On to the next phase of the command in hand.
    func advance(_ m: B) {
        guard let c = m.current else { return }
        m.phaseUntil = 0
        if m.phase + 1 < c.phases.count { m.phase += 1 }
    }

    /// Done, or given up: whatever was queued starts now, else the body goes back to resting.
    /// The destination, when given, is where the body goes back to: one order, not a rest and then another.
    func finish(_ m: B, to place: Place? = nil) {
        m.current = nil
        m.phase = 0
        m.phaseUntil = 0
        m.fetchSpot = nil
        if let next = m.pending {
            m.pending = nil
            // A reaction that waited behind a visit has its walk still to plan: nothing but rest moved the
            // body while the visit lasted, so it is planned now, with nothing in hand for a moment.
            if case .react(_, let where_, _) = next.kind, m.place != where_ { send(m, to: where_) }
            begin(m, next, announce: next.isJob)
        } else { send(m, to: place ?? restPlace(m)) }
    }

    /// With the crate on the arms, the slot is asked for again: the stack as it is now, not as it
    /// was when the order went out. The order keeps its id; only its destination moves.
    func reaim(_ id: Int) {
        guard let job = cargo[id], case .carry(let crate, _, let yard) = job.command.kind,
              let fresh = world.slotNow(for: crate, toward: yard), fresh.pos != job.aim.pos else { return }
        cargo[id]?.aim = fresh
    }

    // MARK: rest and walks

    /// Off the station: through the airlock when there is one, and gone once inside.
    func dismiss(_ m: B) {
        m.state = .leaving
        start(m, .leave)
        m.couch = nil; m.bed = nil
        guard let station = fleet.stations[m.station], let hatch = station.airlockHatches.randomElement(),
              let inner = station.airlockInner.first(where: { $0.x == hatch.inside.x }) else { return }
        m.place = .airlock
        m.path = route(m, to: inner)
        // Then, after the cycle, out through the hatch onto the bay: where the shuttle would pick them up.
        let wait = SIMD2(Double(inner.x), Double(inner.y))
        m.path += [wait] + station.path(from: wait, to: hatch.bay)
    }

    /// Night on a station is the clock's business alone: a quiet afternoon is a lounge afternoon, not bedtime.
    func isNight(_ station: Station) -> Bool {
        if let forced = hooks?.night { return forced }
        let hour = Calendar.current.component(.hour, from: Date())
        return hour >= 22 || hour < 7
    }

    /// Where a body belongs given what it is doing and the hour.
    func restPlace(_ m: B) -> Place {
        Place.forActivity(m.activity, home: m.home.key, isSubagent: m.isSubagent, night: fleet.stations[m.station].map(isNight) ?? true)
    }

    /// After the floor changes, everyone carries on: settled somewhere still valid, stay; walking to a
    /// spot that still exists, keep it and re-plan from here; only if the target is gone, go somewhere new.
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
        // One owner per body: the command in hand owns place, path and pose. Rest may only be planned
        // for a body with nothing but rest in hand; a job or a visit is finished first by its own
        // end, and only then does the body go back. A session's refresh, a floor change or the
        // panel asking for rest under a command in hand changes nothing.
        if let c = m.current, !c.isRest { return }
        guard let station = fleet.stations[m.station] else { return }
        if place != .quarters { m.bed = nil; m.napping = false }
        var place = place
        if place == .quarters, m.bed == nil {
            let used = Set(bodies.values.filter { $0.station == m.station && $0.id != m.id }.compactMap(\.bed))
            m.bed = station.beds.indices.first { !used.contains($0) }
            if m.bed == nil { place = .lounge }   // every bed taken: the lounge
        }
        if place != .lounge { m.couch = nil }
        if place == .lounge, m.couch == nil {
            let used = Set(bodies.values.filter { $0.station == m.station && $0.id != m.id }.compactMap(\.couch))
            m.couch = station.couches.indices.first { !used.contains($0) }
        }
        // One to a couch: if someone already holds this seat, give it up and stand at the table.
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
            // Never the doorway: a body settled there shuts the room to everyone else.
            let door: Cell? = { if case .room(let k) = place { return station.doorCell(of: k) }; return nil }()
            let spots = cells.filter { $0 != door }
            guard let t = (spots.isEmpty ? cells : spots).randomElement() else { return }
            target = t
        }
        m.place = place
        start(m, .rest(place: place, home: m.home.key, name: m.home.name, asleep: m.activity == .sleeping))
        m.path = route(m, to: target)
        // No way found and far off: walk straight rather than stand still or slide.
        if m.path.isEmpty, abs(m.pos.x - Double(target.x)) + abs(m.pos.y - Double(target.y)) > 1 { m.path = [SIMD2(Double(target.x), Double(target.y))] }
        m.nextWanderAt = clock + Double.random(in: 1...3)
    }

    func walk(_ m: B, to cell: Cell) { m.path = route(m, to: cell) }

    /// Spots taken by the other bodies on a station, as the pathfinder sees them: solid, like props.
    func crowd(around m: B, round blocker: String? = nil) -> Set<Cell> {
        var out: Set<Cell> = []
        for o in bodies.values where o.id != m.id && o.station == m.station && o.state != .leaving && o.opacity > 0.5 {
            // A body, standing or lying, is solid at the middle of its tile, like a crate: the way past
            // runs along the tile's edge, a third of a tile off. Two can pass on one tile, never through
            // each other; that is the walk's own rule, which waits on whoever is in the way in step.
            // Whoever just stood in the way gets a whole tile's berth, so two walkers meeting head-on
            // both go round rather than each waiting on the other.
            if o.lying || (o.couch != nil && o.path.isEmpty) { continue }   // on the furniture: off the walkway
            let s = Station.sub(o.pos)
            if o.id == blocker { for dx in -1...1 { for dy in -1...1 { out.insert(Cell(x: s.x + dx, y: s.y + dy)) } } }
            else { out.insert(s) }
        }
        // A ship over its slot, coming down or unloading, owns the ground under it: walks keep half a
        // tile off, so a carrier waiting on a crate stands beside the slot and never under the ship.
        for at in groundHeldByShips(m.station) {
            let c = Station.sub(at)
            for dx in -2...2 { for dy in -2...2 {
                let sub = Cell(x: c.x + dx, y: c.y + dy), p = Station.point(ofSub: sub)
                if hypot(p.x - at.x, p.y - at.y) < 0.55 { out.insert(sub) }
            } }
        }
        return out
    }

    /// A walk for a body: round the props and round everyone else. When the only way through is
    /// past someone standing in it, a doorway say, the walk goes that way and waits on them in step.
    func route(_ m: B, to cell: Cell, round blocker: String? = nil) -> [SIMD2<Double>] {
        guard let station = fleet.stations[m.station] else { return [] }
        let clear = station.path(from: m.pos, to: cell, avoiding: crowd(around: m, round: blocker))
        return clear.isEmpty ? station.path(from: m.pos, to: cell) : clear
    }

    /// The floor changed under a walk, a crate or a pallet arrived in the way: the walk is planned again
    /// from where the body stands to where it was going.
    func replanBlockedWalks() {
        for m in bodies.values where !m.path.isEmpty {
            guard let station = fleet.stations[m.station] else { continue }
            let blocked = m.path.contains { station.obstacles.contains(Station.sub($0)) }
            guard blocked, clock - m.lastReplanAt >= 1, let last = m.path.last else { continue }
            m.lastReplanAt = clock
            m.path = route(m, to: Cell(x: Int(last.x.rounded()), y: Int(last.y.rounded())))
        }
    }

    // MARK: hands

    /// Stands an arm's length from what it is about to work on, facing it. True once it stands right.
    func atArmsLength(_ m: B, of spot: SIMD2<Double>, dt: Double) -> Bool {
        let to = spot - m.pos
        let dist = (to.x * to.x + to.y * to.y).squareRoot()
        if dist > 0.05 { m.facing = atan2(to.x, to.y) }
        // Far off: walked to the cell beside it, round whatever stands in the way. From there the last
        // bit is a shuffle, and a cell it already stands on is never walked to again.
        if dist > 0.9, let st = fleet.stations[m.station] {
            let stand = standCell(st, near: Cell(x: Int(spot.x.rounded()), y: Int(spot.y.rounded())))
            if m.path.isEmpty, m.cell != stand { m.path = route(m, to: stand); return false }
        }
        guard m.path.isEmpty else { return false }
        guard dist < Hands.near || dist > Hands.far else { return true }
        // Right on top of the slot: a step back the way it is facing, so the crate goes down in front.
        let dir = dist > 0.001 ? to / dist : SIMD2(sin(m.facing), cos(m.facing))
        let want = spot - dir * Hands.arm
        m.pos += (want - m.pos) * min(1, dt * 6)
        return (want - m.pos).x.magnitude + (want - m.pos).y.magnitude <= 0.02
    }

    /// Where to stand for a slot: its own cell when the centre is clear, else the neighbouring cell with
    /// the clearest centre. A crate row is never walked into; the aisle beside it is.
    func standCell(_ st: Station, near cell: Cell) -> Cell {
        func blocked(_ c: Cell) -> Int {
            var n = 0
            for dx in -1...1 {
                for dy in -1...1 where st.obstacles.contains(Cell(x: c.x * Station.fine + dx, y: c.y * Station.fine + dy)) { n += 1 }
            }
            return n
        }
        if blocked(cell) == 0 { return cell }
        let options = cell.neighbours.filter { st.walkable.contains($0) }
        return options.min { blocked($0) < blocked($1) } ?? cell
    }

    /// Crouching to a crate: how high it stands decides the posture, and the lift decides the clock.
    func startLift(_ m: B, height: Double) {
        m.handsAt = max(0, Int((height / Hands.level).rounded()))
        m.phaseUntil = clock + Hands.liftSeconds
    }

    /// True once the crouch is over and the hands should be on the crate.
    func liftDue(_ m: B) -> Bool { clock >= m.phaseUntil - Hands.liftArc }

    // MARK: the idle life

    /// A visit to the bath: the shower or the bowl, whichever is free, walked to and acted for its
    /// whole time, then back to where the body came from. False when both fixtures are taken.
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
        start(m, .bath(m.showering ? .shower : .quick, back: back, seconds: m.showering ? Double.random(in: 120...180) : 60))   // a shower two to three minutes, the toilet one
        m.fixture = fixture   // held from here: the order is in hand, and the last order's leftovers are gone
        let f = station.bathFixtures(bath: bath)
        let cell = m.showering ? f.shower : f.toilet
        m.path = route(m, to: cell)
        // Then the exact spot: under the nozzle with the wall at the back, or a step in front of the bowl, facing it.
        let nozzle = station.showerNozzle(bath: bath)
        m.fetchSpot = m.showering ? SIMD2(nozzle.x - station.offset.x, nozzle.y - station.offset.y)
                                  : SIMD2(Double(cell.x) + 0.02 * f.toiletCorner.x, Double(cell.y) - 0.1 * f.toiletCorner.y)
        m.facing = m.showering ? atan2(f.showerCorner.x, -f.showerCorner.y) : atan2(f.toiletCorner.x, f.toiletCorner.y)
        return true
    }

    /// A lounger's idle clock ran out: one thing to do, by weight (`IdlePick`). A look round the station
    /// most often, a turn in the gym by day, the bath, and now and then simply staying on the couch with a book.
    func pickIdle(_ m: B, station: Station) {
        let gymFree = station.rooms["kind:gym"] != nil && freeGymFixture(m) != nil
        let pick = IdlePick.pick(roll: Double.random(in: 0..<1), night: isNight(station), crew: m.isCrew,
                                 gymFree: gymFree, bath: station.rooms["kind:bath"] != nil, shower: Bool.random())
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
        case .read:
            break   // reading on the couch: nothing to walk to, and the clock starts again
        }
    }

    /// A look round the station: a clear spot out of every doorway, apart from where others stand and
    /// where other roamers are headed; beside the pad when a loaded rocket steams, where company is fine.
    @discardableResult
    func startRoam(_ m: B, station: Station) -> Bool {
        let rocketReady = rockets.values.contains { $0.station == station.name && ($0.isSteaming || $0.isLaunching) }
        let padSide = station.deckCells.filter { $0.y == (station.deckCells.map(\.y).min() ?? 0) + 1 }
        let doorways = Set(station.yardDoorways.flatMap { [$0.0, $0.1] } + station.rooms.keys.compactMap { station.doorOutside(of: $0) })
        let clear = (rocketReady && !padSide.isEmpty ? padSide : station.corridorCells + station.storageCells + station.deckCells)   // never the bay: that is outside
            .filter { !doorways.contains($0) }
            .filter { c in (-1...1).allSatisfy { dx in (-1...1).allSatisfy { dy in !station.obstacles.contains(Cell(x: c.x * Station.fine + dx, y: c.y * Station.fine + dy)) } } }
        let others = bodies.values.filter { $0.id != m.id && $0.station == m.station }
        let taken = others.map(\.cell) + others.compactMap { o -> Cell? in if case .chore(let spot, _) = o.current?.kind { return spot }; return nil }
        guard let spot = RoamSpots.choose(clear: clear, taken: taken, company: rocketReady) else { return false }
        start(m, .chore(spot: spot, seconds: Double.random(in: 120...240)))   // two to four minutes looking round
        guard case .chore = m.current?.kind else { return false }
        m.couch = nil
        m.place = .core
        m.path = route(m, to: spot)
        m.nextWanderAt = clock + 60   // lingering at the spot, not wandering off it
        return true
    }

    /// A visit ran its course: how long it lasted from arrival, against how long it was meant to. For the checks.
    func visitDone(_ m: B, _ kind: String) {
        guard hooks != nil else { return }
        visitLog.append((kind: kind, lasted: m.actStartedAt > 0 ? clock - m.actStartedAt : 0, planned: m.actFor))
    }

    /// A turn in the gym, on a fixture nobody else is on: walked to, then acted for its whole time,
    /// then back to where the body came from. False when every fixture is taken.
    @discardableResult
    func takeTurnInGym(_ m: B, station: Station, gym: Room) -> Bool {
        guard let kind = freeGymFixture(m) else { return false }
        let back = m.place
        m.couch = nil
        send(m, to: .gym)
        start(m, .exercise(kind, back: back, seconds: Double.random(in: 240...480)), announce: true)   // four to eight minutes on a fixture
        let stand = station.gymStand(gym: gym, kind)
        m.path = route(m, to: stand.cell)
        m.fetchSpot = stand.spot
        m.facing = stand.facing
        return true
    }

    /// A gym fixture nobody else on the station is on, at random; nil when every one is taken.
    func freeGymFixture(_ m: B) -> Command.Workout? {
        let taken = Set(bodies.values.filter { $0.id != m.id && $0.station == m.station && $0.exercising }.compactMap(\.workout))
        return Command.Workout.allCases.filter { !taken.contains($0) }.randomElement()
    }

    // MARK: crew

    /// Hands a teammate a reaction: where to be, what to do there, and until when.
    func react(_ m: B, _ activity: Activity, place: Place, minutes: Double, words: String) {
        m.activity = activity
        m.busy = true
        if case .react = m.current?.kind { m.current = nil; m.phase = 0; m.phaseUntil = 0 }   // a new reaction ends the one in hand
        if m.lying { m.lying = false; m.bed = nil }
        if m.place != place || m.path.isEmpty { send(m, to: place) }
        start(m, .react(activity, place: place, for: minutes * 60, words: words))
    }

    /// A teammate's reaction has run its course: back to the quarters.
    func crewRested(_ m: B) {
        m.busy = false
        m.activity = .sleeping
        m.pyramidCell = nil
        cue(.clearCones(m.id))
        if case .react = m.current?.kind { m.current = nil; m.phase = 0; m.phaseUntil = 0 }   // the reaction is over: only then may rest move the body
        send(m, to: .quarters)
    }

    // MARK: the step

    /// What a body's walk came to this frame.
    enum Stride {
        /// Still stepping out of the shuttle, or sitting up: nothing else this frame.
        case waking
        /// A step along the path.
        case walking
        /// A beat of wondering with a walk ahead: nothing acts yet.
        case wondering
        /// Nowhere to walk: the command in hand acts, or the body is there.
        case there
    }

    /// What the body's being there came to this frame.
    enum Outcome {
        /// Posed by the scene as usual.
        case posed
        /// The frame is spent on a shuffle or a fresh order: nothing more this frame.
        case spent
        /// Faded out through the airlock: off the station.
        case gone
    }

    /// One frame of one body's walk: the wake from a bed or a shuttle, then a step along the path,
    /// passing whoever is in the way (`Walk`).
    func stepWalk(_ m: B, station: Station, dt: Double) -> Stride {
        m.waitingOn = nil
        // Pace by the task, not by who: a loaded body is the slowest thing on the station, below
        // a stroll; hurrying to work is the fastest; pacing while waiting is slower still.
        // A hurried haul is quicker on its feet, still below a busy walk: the crate is heavy all the same.
        let hurried = m.current.flatMap { cargo[$0.id]?.hurry } ?? false
        let pacing = m.isPacing(at: clock)
        let speed = m.wedged ? 0 : m.isHauling ? (hurried ? 1.7 : 1.1) : (clock < m.strollUntil ? 1.0 : (m.busy ? 2.4 : (pacing ? 0.8 : 1.4)))
        if m.lying, !m.path.isEmpty, m.wakeUntil == 0 { m.wakeUntil = clock + 1.1; m.lying = false; m.bed = nil }
        // A worker out of one shuttle stands by it while any other shuttle is coming down or unloading in
        // the bay, then walks in. A carrier on a job has its own wait for its crate's ship.
        if !m.onJob, station.hangarCells.contains(m.cell), flights.contains(where: { f in
            guard f.station == m.station, f.phaseKind == .descend || f.phaseKind == .unload else { return false }
            if case .flight(.bringWorker(let id), _, _) = f.command.kind, id == m.id { return false }
            return true
        }) {
            m.waitingOn = "a ship coming down beside"
            return .waking
        }
        if m.wakeUntil > 0 {
            if clock < m.wakeUntil { return .waking }
            m.wakeUntil = 0
            // Out of the shuttle: a job handed over while still stepping out begins now.
            if let next = m.pending, next.isJob { m.pending = nil; handOver(m, next, announce: true) }
        }
        if !m.path.isEmpty, clock >= m.wonderUntil {
            // One rule for meeting anyone: drift a third of a tile to the side, pass, drift back onto
            // the line. The other does the same, so two head-on pass without either stopping or
            // planning again. Someone on a couch or in bed is on the furniture, not in the way.
            let others: [Body] = bodies.values.filter { o in
                o.id != m.id && o.station == m.station && o.state != .leaving && o.opacity > 0.5
                    && !o.lying && !(o.couch != nil && o.path.isEmpty)
            }
            m.blockedBy = Walk.step(m, speed: speed, dt: dt, others: others)?.id
            return .walking
        }
        return m.path.isEmpty ? .there : .wondering
    }

    /// One frame of a body with nowhere to walk: a pallet errand (`Pallet.swift`), a crate seen to
    /// (`Carries.swift`), a reaction's time, the arrival that turns a walk into being there, and the settled
    /// life — QA's rows, the bath and gym rules, the idle clock, the visits, the wander — or the way
    /// out through the airlock.
    func stepThere(_ m: B, station: Station, dt: Double) -> Outcome {
        if let pallet = stepPallet(m, station: station, dt: dt) { return pallet }
        if let crate = stepCrate(m, station: station, dt: dt) { return crate }
        if case .react(_, _, let seconds) = m.current?.kind {
            // There: work at it for its span of station time, then back to the quarters.
            if m.phaseKind == .walk { advance(m); m.phaseUntil = clock + seconds; return .spent }
            if clock >= m.phaseUntil { crewRested(m) }
        }
        // There: the quiet commands move on from walking to being there, so truth says so too.
        if m.path.isEmpty, m.phaseKind == .walk, let c = m.current {
            switch c.kind {
            case .goTo, .bath, .exercise, .chore, .qa, .sleep, .work, .react, .leave, .pack, .stow:
                advance(m)
                // A visit's time starts here, on arrival, not when the walk began.
                if m.actFor > 0 { m.phaseUntil = clock + m.actFor; m.actStartedAt = clock }
            default: break
            }
        }
        switch m.state {
        case .arriving:
            m.state = .settled
        case .settled:
            if m.isQA, clock >= m.nextWanderAt {
                // Stack by stack along the untested row: stand in the aisle beside it, face it, sweep it.
                let stacks = Dictionary(grouping: world.yardLayout(station: station, area: "deck").filter { !$0.cleared }, by: \.column)
                    .values.compactMap { $0.first }.sorted { $0.column < $1.column }
                if !stacks.isEmpty {
                    let stack = stacks[m.qaStop % stacks.count]
                    m.qaStop += 1
                    let aisle = [Cell(x: stack.cell.x, y: stack.cell.y - 1), Cell(x: stack.cell.x, y: stack.cell.y + 1)]
                        .first { station.deckCells.contains($0) } ?? stack.cell
                    m.path = route(m, to: aisle)
                    m.facing = atan2(stack.pos.x - station.offset.x - Double(aisle.x), stack.pos.z - station.offset.y - Double(aisle.y))
                }
                m.nextWanderAt = clock + Double.random(in: 4...7)
                if clock >= m.nextImpatience {
                    m.nextImpatience = clock + Double.random(in: 5...9)
                    cue(.hop(m.id))
                }
            }
            // Bath rules: a shower after a long stretch of work, maybe a pee after a short one,
            // and loungers go now and then. Never while busy, carrying, on a job or in bed.
            if m.busy && !m.wasBusy { m.busySince = clock; m.bathDue = 0 }
            if !m.busy && m.wasBusy && !m.isSubagent {
                let stretch = clock - m.busySince
                if stretch > 20 * 60 { m.bathDue = clock + Double.random(in: 3...20); m.showering = true }
                else if stretch > 3 * 60 { m.shortStretches += 1; if m.shortStretches % 2 == 0 { m.bathDue = clock + Double.random(in: 3...20); m.showering = false } }
            }
            m.wasBusy = m.busy
            let settled = m.path.isEmpty
            // Roaming: a look round the station, lingering at the spot for its time, then back to the couch.
            if m.isChore {
                if settled, m.phase > 0, clock >= m.phaseUntil { visitDone(m, "roam"); finish(m, to: .lounge) }
            } else if m.place == .lounge, !m.busy, m.isResting, settled, !m.isSubagent, m.bathDue == 0, !m.hasLoad {
                // One idle clock per lounger (`IdleClock`). When it runs out one thing is picked, and the clock
                // starts again only once that is done and the lounger is back: leaving does not reset it.
                // Whatever was picked starts from the next frame: this frame's "settled" is from the couch.
                if m.idle.tick(at: clock, lounging: true, busy: false) { pickIdle(m, station: station); return .spent }
            }
            if m.busy { _ = m.idle.tick(at: clock, lounging: false, busy: true) }
            if m.place == .bath {
                // Once in the cell, shuffle to the fixture itself: under the nozzle, or in front of the bowl.
                if settled, let spot = m.fetchSpot {
                    let d = spot - m.pos
                    if (d.x * d.x + d.y * d.y).squareRoot() > 0.03 { m.pos += d * min(1, dt * 5); return .spent }
                    m.fetchSpot = nil
                    // Squared up to the fixture, the wall or the bowl, for the whole visit.
                    if let bath = station.rooms["kind:bath"] {
                        let f = station.bathFixtures(bath: bath)
                        let corner = m.showering ? f.showerCorner : f.toiletCorner
                        m.facing = m.drying ? atan2(f.showerCorner.x, 0) : atan2(corner.x, corner.y)   // drying: square to the rail's wall
                    }
                }
                if settled, !m.showering, let bath = station.rooms["kind:bath"] {
                    // The bowl: turn round and sit, a fidget now and then, up again just before the
                    // visit ends with the flush behind. All on the visit's own clock.
                    let standAt = m.phaseUntil - 0.7
                    let bowl = station.bowlSpot(bath: bath)
                    let f = station.bathFixtures(bath: bath)
                    if !m.seated, clock < standAt, m.phaseUntil > 0 {
                        // Sat square on the WC, facing straight out from the tank, wherever it stood.
                        let to = bowl - station.offset - m.pos
                        m.facing = atan2(0, -f.toiletCorner.y)
                        let across = to.x * cos(m.facing) - to.y * sin(m.facing), ahead = to.x * sin(m.facing) + to.y * cos(m.facing)
                        m.seated = true
                        m.seatOffset = SIMD2(across, ahead - 0.02)
                        m.nextFidgetAt = clock + Double.random(in: 1.5...3)
                    } else if m.seated, clock >= standAt {
                        m.seated = false
                        cue(.flush(station: station.name, bowl: bowl, front: f.toiletCorner.y))
                    } else if m.seated, clock >= m.nextFidgetAt {
                        m.nextFidgetAt = clock + Double.random(in: 1.5...3.5)
                        cue(.fidget(m.id))
                    }
                }
                if clock >= m.phaseUntil && settled {   // done; work waits its turn
                    if m.showering, !m.drying, let bath = station.rooms["kind:bath"] {
                        // Out from under the water and over to the rail: a few seconds with the towel before going.
                        m.drying = true
                        m.phaseUntil = clock + 4
                        m.fetchSpot = station.towelStand(bath: bath) - station.offset
                        cue(.towel(m.id, station: station.name, taken: true))
                    } else {
                        if m.drying { m.drying = false; cue(.towel(m.id, station: station.name, taken: false)) }
                        m.seated = false
                        m.fixture = nil
                        var back = restPlace(m)
                        if !m.busy, case .bath(_, let where_, _) = m.current?.kind { back = where_ }
                        visitDone(m, "bath")
                        finish(m, to: back)   // the visit is over: one order back, to where it came from
                    }
                }
            } else if m.bathDue > 0, clock >= m.bathDue, !m.busy, !m.onJob, !m.hasLoad, !m.isSubagent, m.place != .quarters, settled, station.rooms["kind:bath"] != nil {
                if !visitBath(m, station: station) { return .spent }   // both fixtures taken: wait
            }
            if m.place == .gym, m.exercising {
                // Once on the tile, shuffle onto the fixture itself and square up to it.
                if settled, let spot = m.fetchSpot {
                    let d = spot - m.pos
                    if (d.x * d.x + d.y * d.y).squareRoot() > 0.03 { m.pos += d * min(1, dt * 5); return .spent }
                    m.fetchSpot = nil
                    if let gym = station.rooms["kind:gym"], let kind = m.workout { m.facing = station.gymStand(gym: gym, kind).facing }
                    if m.workout == .bench { m.onBench = true }
                }
                if clock >= m.phaseUntil && settled && m.fetchSpot == nil {   // done: back to where it was
                    m.onBench = false
                    var back = restPlace(m)
                    if !m.busy, case .exercise(_, let where_, _) = m.current?.kind { back = where_ }
                    visitDone(m, "gym")
                    finish(m, to: back)   // the turn is over: one order back, to where it came from
                }
            }
            if let pc = m.pyramidCell, !m.onJob, m.place == .room(m.home.key) {
                if abs(m.cell.x - pc.x) + abs(m.cell.y - pc.y) > 1 { walk(m, to: pc) }
            } else if clock >= m.nextWanderAt, m.activity != .sleeping, !m.bathing, !m.exercising, m.place != .quarters, !(m.place == .lounge && m.couch != nil), !m.isJumping(at: clock) {
                let door: Cell? = { if case .room(let k) = m.place { return station.doorCell(of: k) }; return nil }()
                let choices = station.cells(of: m.place).filter { $0 != m.cell && $0 != door }   // wander anywhere but the doorway
                if let dest = choices.randomElement() { m.path = route(m, to: dest) }
                m.nextWanderAt = clock + (m.isPacing(at: clock) ? Double.random(in: 2.5...6) : m.busy ? Double.random(in: 2...5) : Double.random(in: 8...20))
            }
        case .leaving:
            // Solid all the way to the airlock. Inside, the inner door shuts and the chamber
            // cycles for a beat; then out through the hatch, fading onto the bay.
            let inChamber = station.airlockCells.contains(m.cell) || station.hangarCells.contains(m.cell)
            if station.airlockCells.isEmpty || (inChamber && m.phaseKind != .walk) {
                m.opacity -= dt * 1.2
                if m.opacity <= 0 { return .gone }
            } else if inChamber, m.phaseKind == .walk, station.airlockInner.contains(m.cell) {
                advance(m)
                m.wonderUntil = clock + 1.5   // the cycle
            }
        }
        return .posed
    }

    /// One frame of every body, with no scene in between: the walk, the quiet commands, the rest. What a
    /// model-only run steps; the scene runs the same three steps itself, its own commands between the
    /// walk and the settling, until those have moved in too.
    func stepBodies(dt: Double) {
        for m in Array(bodies.values) {
            guard let station = fleet.stations[m.station] else { bodies[m.id] = nil; continue }
            switch stepWalk(m, station: station, dt: dt) {
            case .waking: continue
            case .walking, .wondering: break
            case .there:
                switch stepThere(m, station: station, dt: dt) {
                case .gone: bodies[m.id] = nil; continue
                case .spent: continue
                case .posed: break
                }
            }
            stepRest(m, station: station, dt: dt)
        }
    }

    /// The rest of a frame for any body that is still on the station: fading in, drawn onto the couch
    /// or the bed while it has nothing else to do, and lying down where it is meant to lie.
    func stepRest(_ m: B, station: Station, dt: Double) {
        if m.state != .leaving { m.opacity = min(1, m.opacity + dt * 2) }
        // Seats and beds draw a body in only while it has nothing else to do.
        if m.path.isEmpty, m.isResting, m.place == .lounge, let c = m.couch, c < station.couches.count {
            m.pos += (station.couches[c] - m.pos) * min(1, dt * 4)
        }
        if m.path.isEmpty, m.isResting, m.place == .quarters, let b = m.bed, b < station.beds.count {
            m.pos += (station.beds[b].pos - m.pos) * min(1, dt * 4)
        }
        let resting = m.path.isEmpty && m.state == .settled
        if resting && (m.activity == .sleeping || m.napping) && m.place == .quarters { m.lying = true }
        // On the bench: flat on the back along it; the walk step sits it up again when the turn is over.
        if m.exercising, m.phaseKind == .act, m.path.isEmpty, m.fetchSpot == nil, m.workout == .bench { m.lying = true }
    }
}
