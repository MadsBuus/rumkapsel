// The shuttles and the rockets as the simulation runs them. A `Flight` is one shuttle's command,
// approach to leave, its position a number on the station clock; a `RocketJob` is one repository's
// rocket, standing by, loading, steaming or lifting off, a stage only ever moving forward. No
// SceneKit: the scene keeps a node per flight and per rocket and places it from these facts.

import Foundation

/// How a ship eases along one leg of its flight.
enum FlightEase {
    case linear, easeIn, easeOut, smooth
    func of(_ t: Double) -> Double {
        switch self {
        case .linear: return t
        case .easeIn: return t * t
        case .easeOut: return 1 - (1 - t) * (1 - t)
        case .smooth: return t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
        }
    }
}

/// One leg of a flight: the points the ship flies through after the one it starts from, how long it
/// takes over them, and how it eases along the way. The ship's nose follows the line it is flying,
/// so the points are the whole of the manoeuvre.
struct FlightLeg {
    let points: [SIMD3<Double>]
    let seconds: Double
    let ease: FlightEase
    init(_ points: [SIMD3<Double>], seconds: Double, ease: FlightEase = .smooth) {
        self.points = points; self.seconds = seconds; self.ease = ease
    }
    var last: SIMD3<Double> { points.last ?? .zero }

    /// A point along a run of waypoints, rounded off: Catmull-Rom through them, the ends held. The
    /// points are evenly spaced in time, so a wide gap is flown fast and a tight one slowly.
    static func sample(_ p: [SIMD3<Double>], _ t: Double) -> SIMD3<Double> {
        guard p.count > 1 else { return p.first ?? .zero }
        let u = min(max(0, t), 1) * Double(p.count - 1)
        let i = min(Int(u), p.count - 2)
        let f = u - Double(i), f2 = f * f, f3 = f2 * f
        let p0 = p[max(0, i - 1)], p1 = p[i], p2 = p[i + 1], p3 = p[min(p.count - 1, i + 2)]
        return 0.5 * (2 * p1 + (p2 - p0) * f + (2 * p0 - 5 * p1 + 4 * p2 - p3) * f2 + (3 * p1 - 3 * p2 + p3 - p0) * f3)
    }
}

/// How a ship comes in to its berth. The berth is the same under each; the way down to it is not.
/// `hover` is the high, gentle set-down; `sweep` runs in low across the bay's mouth and turns onto the
/// berth; `dive` drops out of the sky over it and flares; `run` flies a long shallow final straight in.
enum Arrival: CaseIterable { case hover, sweep, dive, run }

/// How a ship goes out again: straight up and away, a nose-over that accelerates out low, or a climb
/// steep enough to lose it in the sky over the bay.
enum Departure: CaseIterable { case climb, peel, boost }

/// The two legs of an arrival, in the station's own coordinates: `at` is the berth, `rest` how high the
/// ship holds over it, `side` the shoulder it works from. `hold` is where it waits out a taken berth.
func arrivalLegs(_ style: Arrival, at: SIMD3<Double>, rest: Double, side: Double) -> (start: SIMD3<Double>, approach: FlightLeg, descend: FlightLeg) {
    func p(_ x: Double, _ y: Double, _ z: Double) -> SIMD3<Double> { SIMD3(at.x + side * x, y, at.z + z) }
    switch style {
    case .hover:
        return (p(10, 9, 11),
                FlightLeg([p(3.2, 6.5, 3.4), p(0, 5, 0)], seconds: 3.2, ease: .easeOut),
                FlightLeg([p(0, rest + 1.4, 0), p(0, rest, 0)], seconds: 3.4))
    case .sweep:
        return (p(9, 4.6, 8),
                FlightLeg([p(5.4, 3.4, 4.6), p(3.2, 2.4, 2.4)], seconds: 3.0, ease: .easeOut),
                FlightLeg([p(2.0, 1.7, -0.6), p(0.4, rest + 0.7, -0.5), p(-0.2, rest, -0.1), p(0, rest, 0)], seconds: 3.0))
    case .dive:
        return (p(5, 13, 7),
                FlightLeg([p(2.4, 11, 2.6), p(0, 9.5, 0.8)], seconds: 2.6, ease: .easeOut),
                FlightLeg([p(0, 5.2, 0.5), p(0, 2.0, 0.2), p(0, rest + 0.5, 0.04), p(0, rest, 0)], seconds: 3.2, ease: .linear))
    case .run:
        return (p(0, 4.2, 19),
                FlightLeg([p(0, 3.4, 12.5), p(0, 2.6, 6.4)], seconds: 3.0, ease: .easeOut),
                FlightLeg([p(0, 1.5, 3.0), p(0, rest + 0.35, 0.9), p(0, rest, 0)], seconds: 3.4))
    }
}

/// The two legs of a departure, from the berth the ship is standing on.
func departureLegs(_ style: Departure, at: SIMD3<Double>, rest: Double, side: Double) -> (rise: FlightLeg, leave: FlightLeg) {
    func p(_ x: Double, _ y: Double, _ z: Double) -> SIMD3<Double> { SIMD3(at.x + side * x, y, at.z + z) }
    switch style {
    case .climb:
        return (FlightLeg([p(0, rest + 1.2, 0), p(0, 5, 0)], seconds: 2.4, ease: .easeOut),
                FlightLeg([p(3, 6.2, 4), p(9, 8.5, 12)], seconds: 3.2, ease: .easeIn))
    case .peel:
        return (FlightLeg([p(0, rest + 0.9, 0.2), p(0, 1.9, 1.2)], seconds: 1.8, ease: .easeOut),
                FlightLeg([p(1.4, 2.4, 4.2), p(5, 4.6, 9), p(10, 7, 16)], seconds: 3.4, ease: .easeIn))
    case .boost:
        return (FlightLeg([p(0, rest + 1.0, 0), p(0, 3.4, 0.4)], seconds: 2.0, ease: .easeOut),
                FlightLeg([p(0, 8, 2.2), p(2.5, 17, 6)], seconds: 3.0, ease: .easeIn))
    }
}

/// One shuttle flight. Its command's phases are the flight itself: approach, descend, unload, rise,
/// leave. The path is in the station's own coordinates, y up, and each phase is one leg of it.
final class Flight {
    let station: String
    /// Whose colours the ship flies.
    let repo: String
    let command: Command
    /// The berth it works and the far point it leaves to: what a look drawing its own path is given.
    let down: SIMD3<Double>, exit: SIMD3<Double>
    /// How far into the unload phase the cargo comes out, and how long the ship waits after.
    let unloadAt: Double, unloadFor: Double
    /// Setting the cargo down: the worker steps out, or the crate lands in the bay.
    let onUnload: () -> Void
    /// Whether the cargo may come out yet: a crate waits for its carrier to stand at the berth. The
    /// ship holds over the berth until this says so; nil unloads on its own clock.
    var ready: (() -> Bool)?
    /// Whether the berth is clear to come down onto: nothing of an earlier order on it, no other ship
    /// over it. Until it is, the ship holds where its approach left it.
    var clear: (() -> Bool)?
    var phase = 0
    var until = 0.0
    /// Where the ship is now, and the line it is flying, for whoever draws it. The heading is nil while
    /// it stands still, and whatever drew it last keeps its nose where it was.
    var pos: SIMD3<Double>
    var heading: SIMD3<Double>?
    private let legs: [Command.Phase: FlightLeg]
    private var curve: [SIMD3<Double>] = []
    private var unloaded = false
    private var startedAt = 0.0

    init(station: String, repo: String, command: Command, arrival: Arrival, departure: Departure,
         at: SIMD3<Double>, rest: Double, side: Double, unloadAt: Double, unloadFor: Double,
         onUnload: @escaping () -> Void) {
        let into = arrivalLegs(arrival, at: at, rest: rest, side: side)
        let out = departureLegs(departure, at: at, rest: rest, side: side)
        self.station = station; self.repo = repo; self.command = command
        self.pos = into.start
        self.down = into.descend.last
        self.exit = out.leave.last
        self.legs = [.approach: into.approach, .descend: into.descend, .rise: out.rise, .leave: out.leave]
        self.unloadAt = unloadAt; self.unloadFor = unloadFor; self.onUnload = onUnload
    }

    var phaseKind: Command.Phase {
        let p = command.phases
        return p[min(phase, p.count - 1)]
    }

    /// How long the phase in hand lasts. The unload phase holds the ship still over its berth.
    private var duration: Double {
        if phaseKind == .unload { return unloadAt + unloadFor }
        return legs[phaseKind]?.seconds ?? 3.0
    }

    /// How far through the phase in hand, from 0 to 1: held at 1 while the ship waits for its berth.
    func progress(at clock: Double) -> Double {
        guard duration > 0 else { return 1 }
        return min(1, max(0, (clock - startedAt) / duration))
    }

    /// Starts the phase in hand: the leg is flown from wherever the ship stands.
    func begin(at clock: Double) {
        until = clock + duration
        startedAt = clock
        curve = [pos] + (legs[phaseKind]?.points ?? [])
        if phaseKind == .unload { heading = nil }
    }

    /// Where the ship is along the leg, and which way it is pointing: the line it is flying this instant.
    private func place(at clock: Double) {
        guard duration > 0, phaseKind != .unload, curve.count > 1 else { return }
        let e = (legs[phaseKind]?.ease ?? .smooth).of(min(1, max(0, (clock - startedAt) / duration)))
        pos = FlightLeg.sample(curve, e)
        let step = 0.02
        let ahead = FlightLeg.sample(curve, min(1, e + step)) - FlightLeg.sample(curve, max(0, e - step))
        heading = (ahead.x * ahead.x + ahead.y * ahead.y + ahead.z * ahead.z) > 1e-10 ? ahead : nil
        if e >= 1 { heading = nil }   // held over the berth: it keeps the nose it came in on
    }

    /// One frame of the flight. Returns false once the ship is gone.
    func advance(at clock: Double) -> Bool {
        place(at: clock)
        if phaseKind == .approach, clock >= until, let clear, !clear() { until = clock + 0.5; return true }   // holding off: the berth is taken
        if phaseKind == .unload, !unloaded, let ready, !ready() { until = clock + unloadAt + unloadFor; return true }   // holding over the berth
        if phaseKind == .unload, !unloaded, clock >= until - unloadFor { unloaded = true; onUnload() }
        guard clock >= until else { return true }
        guard phase + 1 < command.phases.count else { return false }
        phase += 1
        begin(at: clock)
        return true
    }
}

/// One repository's rocket. It runs one command at a time — standing by, loading, steaming, lifting
/// off — and a stage only ever moves forward.
final class RocketJob {
    let station: String
    let repo: String
    var command: Command
    var phase = 0
    /// When the climb is over and the rocket is gone.
    var until = 0.0
    var label = ""
    var untested = false
    /// A production rocket is the tall one.
    var tall = true
    /// How much cargo waits for it, for the size the scene draws it at while standing by.
    var cargo = 0
    /// Every crate handed a carry into this rocket, by `CrateRef.key`. The load is over when all of
    /// them have been set down on the pad and not one moment before: a rocket never launches empty.
    var assigned: Set<String> = []
    /// The carries ordered aboard that have not set their crate down yet, by command id.
    var pending: Set<Int> = []

    init(station: String, repo: String, command: Command) {
        self.station = station; self.repo = repo; self.command = command
    }

    var key: String { station + "|" + repo }

    var stage: Command.RocketStage {
        if case .rocket(let s, _, _) = command.kind { return s }
        return .standBy
    }

    var phaseKind: Command.Phase {
        let p = command.phases
        return p[min(phase, p.count - 1)]
    }

    /// Loading or steaming: the yard may not take its crates back and QA is over.
    var isBusy: Bool { stage.rank >= 1 }
    var isSteaming: Bool { if case .steam = stage { return true }; return false }
    var isLaunching: Bool { if case .launch = stage { return true }; return false }
}

extension Simulation {
    // MARK: shuttles

    /// How many shuttles are over a station's bay right now: the flights in the air, nothing else.
    func shipsInFlight(_ station: String) -> Int { flights.filter { $0.station == station }.count }

    /// A shuttle that dropped this office's crate and has not risen from the slot yet.
    func shipStillOver(order: Int, station: String) -> Bool {
        flights.contains { s in
            guard s.station == station, case .flight(let kind, _, _) = s.command.kind, case .dropCrate(let id) = kind, id == order else { return false }
            return s.phase < 3   // approach, descend, unload
        }
    }

    /// The ground a ship owns over a station's bay: the slot under every ship coming down or unloading.
    func groundHeldByShips(_ stationName: String) -> [SIMD2<Double>] {
        guard let station = fleet.stations[stationName] else { return [] }
        return flights.compactMap { s in
            guard s.station == stationName, case .flight(_, _, let slot) = s.command.kind, slot < station.hangarSlots.count,
                  s.phase < (s.command.phases.firstIndex(of: .rise) ?? Int.max) else { return nil }
            return station.hangarSlots[slot]
        }
    }

    /// Which shoulder of the bay a ship works from, and the way it flies in and out. Every ship draws
    /// its own, so two of them rarely come in the same way.
    private func flightStyle() -> (arrival: Arrival, departure: Departure, side: Double) {
        (Arrival.allCases.randomElement()!, Departure.allCases.randomElement()!, Bool.random() ? 1 : -1)
    }

    /// A new worker arrives by shuttle: it stays invisible until the ship has set down, then steps out.
    func arriveByShuttle(_ m: B) {
        guard let station = fleet.stations[m.station], station.hasHangar, !station.hangarSlots.isEmpty else { return }
        let slotIndex = shipsInFlight(m.station) % station.hangarSlots.count
        let slot = station.hangarSlots[slotIndex]
        m.pos = slot
        m.opacity = 0
        m.wakeUntil = clock + 8.1   // held until the ship lands
        let command = Command.flight(.bringWorker(m.id), station: m.station, slot: slotIndex,
                                     what: "a new worker for \(m.home.name)")
        let style = flightStyle()
        launch(Flight(station: m.station, repo: m.home.repo, command: command, arrival: style.arrival, departure: style.departure,
                      at: SIMD3(slot.x, 0, slot.y), rest: Station.restOnSkids, side: style.side,
                      unloadAt: 0.6, unloadFor: 1.0) { [weak m, weak self] in
            // Out of the ship, and standing by it for the second it takes to lift off: nobody walks out from under a shuttle.
            m?.opacity = 1
            m?.wakeUntil = (self?.clock ?? 0) + 1.0
        })
    }

    /// Hands a flight to a new shuttle: the log and the panel see the command, the tick flies it.
    private func launch(_ ship: Flight) {
        // Two ships never come down on one slot: the later holds high until the earlier has left it, and
        // an office's crate ship waits for any earlier order still on that slot to be fetched.
        guard case .flight(let job, _, let slot) = ship.command.kind else { return }
        let stationName = ship.station
        ship.clear = { [weak self, weak ship] in
            guard let self, let ship else { return true }
            if self.flights.contains(where: { o in
                guard o !== ship, o.station == stationName, case .flight(_, _, let s) = o.command.kind, s == slot else { return false }
                if o.phaseKind == .descend || o.phaseKind == .unload { return true }
                // Two approaching the same slot: the one launched first goes first.
                guard o.phaseKind == .approach, let i = self.flights.firstIndex(where: { $0 === o }), let j = self.flights.firstIndex(where: { $0 === ship }) else { return false }
                return i < j
            }) { return false }
            if case .dropCrate(let order) = job,
               self.world.truth.deliveries.values.contains(where: { $0.station == stationName && $0.slot == slot && $0.id < order }) { return false }
            // Nobody within a tile of the slot but this ship's own carrier or passenger: a neighbour's carrier
            // lifting a crate, say, is left to finish before the next ship comes down beside it.
            guard let station = self.fleet.stations[stationName], slot < station.hangarSlots.count else { return true }
            let at = station.hangarSlots[slot]
            for b in self.bodies.values where b.station == stationName && hypot(b.pos.x - at.x, b.pos.y - at.y) < Station.bayKeepOff {
                switch job {
                case .bringWorker(let id) where id == b.id: continue
                case .dropCrate(let order): if case .deliverOffice(let k) = b.current?.kind, k == order { continue }
                default: break
                }
                return false
            }
            return true
        }
        issue(ship.command, by: "shuttle", announce: true)
        ship.begin(at: clock)
        flights.append(ship)
        cue(.sweep(up: false))
    }

    /// One frame of every flight in the air.
    func stepShuttles() {
        // Each ship steps with the list untouched (a ship's `clear` reads the others), then the gone ones go.
        var gone: [Flight] = []
        for s in flights where !s.advance(at: clock) { gone.append(s) }
        if !gone.isEmpty { flights.removeAll { f in gone.contains { $0 === f } } }
    }

    /// A shuttle descends slowly onto a free hangar slot, sets down a crate, and lifts away. The crate is
    /// the scene's to draw: ordered, it lies unseen on its slot; dropped, it comes down onto the floor.
    func startDelivery(_ m: B, roomKey: String) {
        guard let station = fleet.stations[m.station], station.hasHangar, !station.hangarSlots.isEmpty,
              let room = station.rooms[roomKey] else { return }
        let key = "\(station.name)|\(roomKey)"
        // A slot with nothing on it and no ship bound for it; every slot taken, the least recently ordered.
        let slotIndex = world.truth.freeSlots(station: station.name, of: station.hangarSlots.count).first
            ?? shipsInFlight(m.station) % station.hangarSlots.count
        let order = world.truth.orderDelivery(station: station.name, roomKey: roomKey, slot: slotIndex, session: m.id)
        cue(.crateOrdered(key: key, station: station.name, slot: slotIndex, repo: room.repo ?? m.home.repo))
        let spot = station.hangarSlots[slotIndex]
        let command = Command.flight(.dropCrate(order: order), station: m.station, slot: slotIndex,
                                     what: "the office for \(room.name)")
        let style = flightStyle()
        let flight = Flight(station: m.station, repo: room.repo ?? m.home.repo, command: command,
                            arrival: style.arrival, departure: style.departure,
                            at: SIMD3(spot.x, 0, spot.y), rest: Station.restOverCrate, side: style.side,
                            unloadAt: 0.8, unloadFor: 1.2) { [weak self] in
            self?.world.truth.crateLanded(order: order)   // on the floor now: it will be fetched, by whoever is free
            self?.cue(.crateDropped(key: key, station: station.name, slot: slotIndex))
        }
        // A hard sequence: the crate comes out only once its carrier stands at the slot. With no carrier
        // left for it, the ship unloads anyway and the crate waits on the floor.
        let stationName = m.station
        flight.ready = { [weak self] in
            guard let self, let carrier = self.bodies.values.first(where: { o in
                guard o.station == stationName, case .deliverOffice(let k) = o.current?.kind else { return false }
                return k == order
            }) else { return true }
            return carrier.path.isEmpty && hypot(carrier.pos.x - spot.x, carrier.pos.y - spot.y) < 1.3
        }
        launch(flight)
        start(m, .deliverOffice(order: order, name: room.name), announce: false)
        m.place = .hangar
        m.fetchSpot = spot
        walk(m, to: station.bayStand(slot: slotIndex))
    }

    // MARK: rockets

    /// The reconciler says what a repository's rocket should be doing. An empty pad gets a new rocket;
    /// one already there only takes a stage it has not reached yet, so a repeated wish changes nothing.
    func rocket(station: String, repo: String, label: String, untested: Bool, tall: Bool, cargo: Int, command: Command) {
        guard fleet.stations[station] != nil, case .rocket(let stage, _, _) = command.kind else { return }
        let key = station + "|" + repo
        if let r = rockets[key] {
            r.label = label
            // Whatever it is carrying, it says so, right up to the moment it lights: a rocket that takes
            // on untested work while it waits is a rocket carrying untested work, and the tape saying
            // otherwise would be the floor telling you something the release will not honour. Once it is
            // climbing nothing changes what went up.
            if r.stage.rank < 3 { r.cargo = cargo; r.untested = untested }
            guard stage.rank > r.stage.rank else { return }
            take(r, command)
            return
        }
        let r = RocketJob(station: station, repo: repo, command: command)
        r.label = label; r.untested = untested; r.tall = tall; r.cargo = cargo
        rockets[key] = r
        take(r, command)
    }

    /// A repository whose merges deploy: a small rocket takes what is waiting in storage straight up.
    func launchOnMerge(station: Station, repo: String) {
        let key = station.name + "|" + repo
        guard rockets[key] == nil else { return }   // one going up already: the next goes when it has climbed
        world.mergeLaunches.insert(key)
        rocket(station: station.name, repo: repo, label: "rocket:\(world.waitingURL(repo: repo))|\(repo) · deployed on merge", untested: false, tall: false, cargo: 1,
               command: .rocket(.launch, station: station.name, repo: repo))
    }

    /// The rocket takes a new command and starts its first phase.
    private func take(_ r: RocketJob, _ command: Command) {
        r.command = command
        r.phase = 0
        r.assigned = []   // a new stage orders its own cargo; what is already aboard stays aboard
        r.pending = []
        // Nothing left to load: everything is aboard already, and the rocket goes straight on to steam.
        var empty = false
        if case .rocket(.load(0), _, _) = command.kind { empty = true }
        issue(command, by: "rocket", announce: !empty)
        beginRocketPhase(r)
    }

    private func beginRocketPhase(_ r: RocketJob) {
        switch r.phaseKind {
        case .load:
            cue(.rocketLoading(key: r.key))   // cleared: the tape comes down
            loadCrates(r)
        case .climb:
            world.clearPad(station: r.station, repo: r.repo)
            if world.mergeLaunches.contains(r.key) { world.forgetShipped(station: r.station, repo: r.repo) }
            cue(.liftOff(key: r.key))
            r.until = clock + 15
            fleet.save()
        default:
            if r.isSteaming { cue(.steam(key: r.key)) }
        }
    }

    /// One pass over every rocket: loading watches station truth, the climb watches the clock.
    func stepRockets() {
        for r in Array(rockets.values) {
            // Loaded and waiting is not finished loading. A production release stays open while staging
            // keeps moving, and work merged there after the rocket filled up rides the same release, so
            // the doors stay open until it lights.
            if r.stage.rank == 2, world.productionOpen(station: r.station, repo: r.repo) { loadCrates(r) }
            switch r.phaseKind {
            case .load:
                loadCrates(r)
                // A rocket never launches empty. The load is over when every crate this rocket was
                // given a carry for stands on the pad, and nothing of the repository is left on the
                // rows or on anyone's arms. A release with no cargo at all — nothing was ever
                // assigned — goes as soon as the rows are clear.
                // Unnumbered crates of a repository share one truth key, so the count aboard can
                // read short of what is really on the pad: the carries themselves are the second,
                // exact witness, and both have to agree before the rocket may go.
                let short = r.assigned.count - world.aboard(station: r.station, repo: r.repo)
                guard padClear(r), r.pending.isEmpty, short <= 0 else { continue }
                advanceRocket(r)
            case .climb:
                if clock >= r.until {
                    rockets[r.key] = nil
                    cue(.rocketGone(key: r.key))
                    // A merge that landed while this one climbed goes up next.
                    if world.mergeLaunches.remove(r.key) != nil, let st = fleet.stations[r.station],
                       st.ledger.crates(of: r.repo).contains(where: { $0.placed == .storage }) {
                        launchOnMerge(station: st, repo: r.repo)
                    }
                }
            default: continue
            }
        }
    }

    /// The end of the load phase: on to the climb if the command has one, otherwise the rocket steams.
    private func advanceRocket(_ r: RocketJob) {
        if r.phase + 1 < r.command.phases.count {
            r.phase += 1
            beginRocketPhase(r)
            return
        }
        take(r, .rocket(.steam, station: r.station, repo: r.repo))
    }

    /// Which row a rocket loads from: the deck when releases go through staging, storage otherwise.
    private func loadSource(_ r: RocketJob) -> String { world.stagingIsDeck(station: r.station, repo: r.repo) ? "deck" : "storage" }

    private func padClear(_ r: RocketJob) -> Bool {
        let yard: Yard = loadSource(r) == "deck" ? .deck : .storage
        let left = fleet.stations[r.station]?.ledger.crates(of: r.repo).contains { $0.placed == yard } ?? false
        return !left && world.carriedCount(station: r.station, repo: r.repo) == 0
    }

    /// Hands out a carry for every crate of the repository still standing on its row. A crate already
    /// spoken for is off the floor, so this can run every pass without doubling up.
    private func loadCrates(_ r: RocketJob) {
        guard let station = fleet.stations[r.station] else { return }
        let source = loadSource(r)
        let repo = r.repo
        let yard: Yard = source == "deck" ? .deck : .storage
        // A load takes everything cleared to go; a launch that has to load first takes only what the record
        // says shipped, so a stage said for one crate ships that crate and leaves the rest.
        let standing = station.ledger.crates(of: repo).filter { $0.stands(in: yard) }.map(\.number)
        func shipped(_ n: Int) -> Bool? { world.works.find(repo: repo, crate: n).map { r in r.stage.map { $0 >= .shipped } ?? true } }
        var launching = false   // asked of the record: a crate aboard is off the rows before the rocket goes
        if case .rocket(.launch, _, _) = r.command.kind { launching = world.works.records(repo: repo).contains { r in r.stage.map { $0 >= .shipped } ?? false } }
        let numbers = launching ? standing.filter { shipped($0) ?? true } : standing
        guard !numbers.isEmpty else { return }
        for command in world.carryToPad(station: station, repo: repo, from: source, numbers: numbers) {
            guard let crate = command.crate else { continue }
            let id = command.id
            let carried = carry(command) { [weak self, weak r] in
                guard let self else { return }
                r?.pending.remove(id)
                // Aboard by hand: the rows may not draw it again until the board says it has shipped.
                world.landed(station: station, repo: repo, number: crate.number, in: .pad, at: now)
                cue(.intoHold(key: r?.key ?? "", command: id))
                fleet.save()
            }
            guard carried else { world.unorder(crate); continue }
            r.assigned.insert(crate.key)   // ordered aboard: the launch waits for it
            r.pending.insert(id)
        }
    }

    /// Pads whose release is gone lose their rocket; one standing by is sized to the pile.
    func refreshRockets() {
        let live = world.padKeys()   // a rocket without a slot on the pad steps off it until one frees
        for (key, r) in rockets {
            guard let st = fleet.stations[r.station] else { continue }
            if !live.contains(key), !r.isBusy {
                rockets[key] = nil
                cue(.rocketGone(key: key))
                continue
            }
            if r.stage.rank == 0 { r.cargo = world.cargoWaiting(station: st, repo: r.repo) }
        }
    }
}
