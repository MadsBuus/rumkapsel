import Foundation

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

struct FlightLeg {
    let points: [SIMD3<Double>]
    let seconds: Double
    let ease: FlightEase
    init(_ points: [SIMD3<Double>], seconds: Double, ease: FlightEase = .smooth) {
        self.points = points; self.seconds = seconds; self.ease = ease
    }
    var last: SIMD3<Double> { points.last ?? .zero }

    static func sample(_ p: [SIMD3<Double>], _ t: Double) -> SIMD3<Double> {
        guard p.count > 1 else { return p.first ?? .zero }
        let u = min(max(0, t), 1) * Double(p.count - 1)
        let i = min(Int(u), p.count - 2)
        let f = u - Double(i), f2 = f * f, f3 = f2 * f
        let p0 = p[max(0, i - 1)], p1 = p[i], p2 = p[i + 1], p3 = p[min(p.count - 1, i + 2)]
        return 0.5 * (2 * p1 + (p2 - p0) * f + (2 * p0 - 5 * p1 + 4 * p2 - p3) * f2 + (3 * p1 - 3 * p2 + p3 - p0) * f3)
    }
}

enum Arrival: CaseIterable { case hover, sweep, dive, run }

enum Departure: CaseIterable { case climb, peel, boost }

struct BayMouth {
    let z: Double
    let height: Double
}

func arrivalLegs(_ style: Arrival, at: SIMD3<Double>, rest: Double, side: Double, mouth: BayMouth) -> (start: SIMD3<Double>, approach: FlightLeg, descend: FlightLeg) {
    func p(_ x: Double, _ y: Double, _ out: Double) -> SIMD3<Double> { SIMD3(at.x + side * x, y, mouth.z + out) }
    let h = mouth.height
    let lined = p(0, h, 1.8)
    let start: SIMD3<Double>, approach: FlightLeg
    switch style {
    case .hover:
        start = p(10, 9, 12)
        approach = FlightLeg([p(6, 6.4, 7.5), p(2.2, 3.2, 4.2), lined], seconds: 4.2, ease: .easeOut)
    case .sweep:
        start = p(14, 1.4, 3.4)
        approach = FlightLeg([p(8, 1.25, 3.4), p(3, 1.1, 2.8), lined], seconds: 4.0, ease: .easeOut)
    case .dive:
        start = p(2.5, 13, 8)
        approach = FlightLeg([p(1, 7, 5.5), p(0.2, 2.6, 3.2), lined], seconds: 3.6, ease: .easeOut)
    case .run:
        start = p(0, 1.7, 21)
        approach = FlightLeg([p(0, 1.45, 13), p(0, 1.15, 6), lined], seconds: 3.8, ease: .easeOut)
    }
    let descend = FlightLeg([p(0, h, -0.5), SIMD3(at.x, max(rest + 0.3, min(h, rest + 0.45)), at.z + 0.35), SIMD3(at.x, rest, at.z)],
                            seconds: 3.4)
    return (start, approach, descend)
}

func departureLegs(_ style: Departure, at: SIMD3<Double>, rest: Double, side: Double, mouth: BayMouth) -> (rise: FlightLeg, leave: FlightLeg) {
    func p(_ x: Double, _ y: Double, _ out: Double) -> SIMD3<Double> { SIMD3(at.x + side * x, y, mouth.z + out) }
    let h = mouth.height
    let rise = FlightLeg([SIMD3(at.x, max(rest + 0.3, min(h, rest + 0.45)), at.z + 0.2), p(0, h, -0.6)], seconds: 2.6, ease: .easeOut)
    switch style {
    case .climb:
        return (rise, FlightLeg([p(0, h, 2.2), p(2.5, 4, 6.5), p(9, 8.5, 13)], seconds: 3.8, ease: .easeIn))
    case .peel:
        return (rise, FlightLeg([p(0, h, 2.4), p(3, 1.4, 6), p(10, 3.2, 12), p(16, 6.5, 16)], seconds: 4.2, ease: .easeIn))
    case .boost:
        return (rise, FlightLeg([p(0, h, 2.2), p(0, 1.6, 7), p(1.5, 9, 15)], seconds: 3.4, ease: .easeIn))
    }
}

final class Flight {
    let station: String
    let repo: String
    let command: Command
    let down: SIMD3<Double>, exit: SIMD3<Double>
    let unloadAt: Double, unloadFor: Double
    let onUnload: () -> Void
    var ready: (() -> Bool)?
    var clear: (() -> Bool)?
    var phase = 0
    var until = 0.0
    var pos: SIMD3<Double>
    var heading: SIMD3<Double>?
    private let legs: [Command.Phase: FlightLeg]
    private var curve: [SIMD3<Double>] = []
    private var unloaded = false
    private var startedAt = 0.0

    init(station: String, repo: String, command: Command, arrival: Arrival, departure: Departure,
         at: SIMD3<Double>, rest: Double, side: Double, mouth: BayMouth, unloadAt: Double, unloadFor: Double,
         onUnload: @escaping () -> Void) {
        let into = arrivalLegs(arrival, at: at, rest: rest, side: side, mouth: mouth)
        let out = departureLegs(departure, at: at, rest: rest, side: side, mouth: mouth)
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

    private var duration: Double {
        if phaseKind == .unload { return unloadAt + unloadFor }
        return legs[phaseKind]?.seconds ?? 3.0
    }

    func progress(at clock: Double) -> Double {
        guard duration > 0 else { return 1 }
        return min(1, max(0, (clock - startedAt) / duration))
    }

    func begin(at clock: Double) {
        until = clock + duration
        startedAt = clock
        curve = [pos] + (legs[phaseKind]?.points ?? [])
        if phaseKind == .unload { heading = nil }
    }

    private func place(at clock: Double) {
        guard duration > 0, phaseKind != .unload, curve.count > 1 else { return }
        let e = (legs[phaseKind]?.ease ?? .smooth).of(min(1, max(0, (clock - startedAt) / duration)))
        pos = FlightLeg.sample(curve, e)
        let step = 0.02
        let ahead = FlightLeg.sample(curve, min(1, e + step)) - FlightLeg.sample(curve, max(0, e - step))
        heading = (ahead.x * ahead.x + ahead.y * ahead.y + ahead.z * ahead.z) > 1e-10 ? ahead : nil
        if e >= 1 { heading = nil }
    }

    func advance(at clock: Double) -> Bool {
        place(at: clock)
        if phaseKind == .approach, clock >= until, let clear, !clear() { until = clock + 0.5; return true }
        if phaseKind == .unload, !unloaded, let ready, !ready() { until = clock + unloadAt + unloadFor; return true }
        if phaseKind == .unload, !unloaded, clock >= until - unloadFor { unloaded = true; onUnload() }
        guard clock >= until else { return true }
        guard phase + 1 < command.phases.count else { return false }
        phase += 1
        begin(at: clock)
        return true
    }
}

extension Simulation {
    func shipsInFlight(_ station: String) -> Int { flights.filter { $0.station == station }.count }

    func shipStillOver(order: Int, station: String) -> Bool {
        flights.contains { s in
            guard s.station == station, case .flight(let kind, _, _) = s.command.kind, case .dropCrate(let id) = kind, id == order else { return false }
            return s.phase < 3
        }
    }

    func groundHeldByShips(_ stationName: String) -> [SIMD2<Double>] {
        guard let station = fleet.stations[stationName] else { return [] }
        return flights.compactMap { s in
            guard s.station == stationName, case .flight(_, _, let slot) = s.command.kind, slot < station.hangarSlots.count,
                  s.phase < (s.command.phases.firstIndex(of: .rise) ?? Int.max) else { return nil }
            return station.hangarSlots[slot]
        }
    }

    private func flightStyle() -> (arrival: Arrival, departure: Departure, side: Double) {
        (Arrival.allCases.randomElement()!, Departure.allCases.randomElement()!, Bool.random() ? 1 : -1)
    }

    func arriveByShuttle(_ m: B) {
        guard let station = fleet.stations[m.station], station.hasHangar, !station.hangarSlots.isEmpty else { return }
        let slotIndex = shipsInFlight(m.station) % station.hangarSlots.count
        let slot = station.hangarSlots[slotIndex]
        m.pos = slot
        m.opacity = 0
        m.wakeUntil = clock + 8.1
        let command = Command.flight(.bringWorker(m.id), station: m.station, slot: slotIndex,
                                     what: "a new worker for \(m.home.name)")
        let style = flightStyle()
        launch(Flight(station: m.station, repo: m.home.repo, command: command, arrival: style.arrival, departure: style.departure,
                      at: SIMD3(slot.x, 0, slot.y), rest: Station.restOnSkids, side: style.side, mouth: station.bayMouth,
                      unloadAt: 0.6, unloadFor: 1.0) { [weak m, weak self] in
            m?.opacity = 1
            m?.wakeUntil = (self?.clock ?? 0) + 1.0
        })
    }

    @discardableResult
    func callShip(for m: B) -> Int? {
        guard let station = fleet.stations[m.station], station.hasHangar, !station.hangarSlots.isEmpty else { return nil }
        if let ship = pickup(for: m), case .flight(_, _, let slot) = ship.command.kind { return slot }
        let count = station.hangarSlots.count
        let busy = Set(flights.compactMap { f -> Int? in
            guard f.station == m.station, case .flight(_, _, let s) = f.command.kind else { return nil }
            return s
        })
        let taken = busy.union(world.truth.deliveries.values.filter { $0.station == m.station }.map(\.slot))
        let slotIndex = (0..<count).first { !taken.contains($0) } ?? shipsInFlight(m.station) % count
        let slot = station.hangarSlots[slotIndex]
        let command = Command.flight(.takeWorker(m.id), station: m.station, slot: slotIndex, what: "a seat for \(m.home.name)")
        let style = flightStyle()
        let leaver = m.id
        let ship = Flight(station: m.station, repo: m.home.repo, command: command, arrival: style.arrival, departure: style.departure,
                          at: SIMD3(slot.x, 0, slot.y), rest: Station.restOnSkids, side: style.side, mouth: station.bayMouth,
                          unloadAt: 0.2, unloadFor: 1.0) {}
        ship.ready = { [weak self] in
            guard let self, let b = self.bodies[leaver] else { return true }
            return b.opacity <= 0 || b.state != .leaving
        }
        launch(ship)
        return slotIndex
    }

    func pickup(for m: B) -> Flight? {
        flights.first { if case .flight(.takeWorker(let id), _, _) = $0.command.kind { return id == m.id }; return false }
    }

    private func launch(_ ship: Flight) {
        guard case .flight(let job, _, let slot) = ship.command.kind else { return }
        let stationName = ship.station
        ship.clear = { [weak self, weak ship] in
            guard let self, let ship else { return true }
            if self.flights.contains(where: { o in
                guard o !== ship, o.station == stationName, case .flight(_, _, let s) = o.command.kind, s == slot else { return false }
                if o.phaseKind == .descend || o.phaseKind == .unload { return true }
                guard o.phaseKind == .approach, let i = self.flights.firstIndex(where: { $0 === o }), let j = self.flights.firstIndex(where: { $0 === ship }) else { return false }
                return i < j
            }) { return false }
            if case .dropCrate(let order) = job,
               self.world.truth.deliveries.values.contains(where: { $0.station == stationName && $0.slot == slot && $0.id < order }) { return false }
            guard let station = self.fleet.stations[stationName], slot < station.hangarSlots.count else { return true }
            let at = station.hangarSlots[slot]
            for b in self.bodies.values where b.station == stationName && hypot(b.pos.x - at.x, b.pos.y - at.y) < Station.bayKeepOff {
                switch job {
                case .bringWorker(let id) where id == b.id: continue
                case .takeWorker(let id) where id == b.id: continue
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

    func stepShuttles() {
        var gone: [Flight] = []
        for s in flights where !s.advance(at: clock) { gone.append(s) }
        if !gone.isEmpty { flights.removeAll { f in gone.contains { $0 === f } } }
    }

    func startDelivery(_ m: B, roomKey: String) {
        guard let station = fleet.stations[m.station], station.hasHangar, !station.hangarSlots.isEmpty,
              station.rooms[roomKey] != nil else { return }
        orderDelivery(station: station, roomKey: roomKey, for: m)
        assignOrders()
    }

    func orderDelivery(station: Station, roomKey: String, for m: B?) {
        guard station.hasHangar, !station.hangarSlots.isEmpty, let room = station.rooms[roomKey] else { return }
        let repo = room.repo ?? m?.home.repo ?? ""
        let key = "\(station.name)|\(roomKey)"
        let slotIndex = world.truth.freeSlots(station: station.name, of: station.hangarSlots.count).first
            ?? shipsInFlight(station.name) % station.hangarSlots.count
        let order = world.truth.orderDelivery(station: station.name, roomKey: roomKey, slot: slotIndex, session: m?.id)
        cue(.crateOrdered(key: key, station: station.name, slot: slotIndex, repo: repo))
        let spot = station.hangarSlots[slotIndex]
        let command = Command.flight(.dropCrate(order: order), station: station.name, slot: slotIndex,
                                     what: "the office for \(room.name)")
        let style = flightStyle()
        let flight = Flight(station: station.name, repo: repo, command: command,
                            arrival: style.arrival, departure: style.departure,
                            at: SIMD3(spot.x, 0, spot.y), rest: Station.restOverCrate, side: style.side, mouth: station.bayMouth,
                            unloadAt: 0.8, unloadFor: 1.2) { [weak self] in
            self?.world.truth.crateLanded(order: order)
            self?.cue(.crateDropped(key: key, station: station.name, slot: slotIndex))
        }
        let stationName = station.name
        flight.ready = { [weak self] in
            guard let self, let carrier = self.bodies.values.first(where: { o in
                guard o.station == stationName, case .deliverOffice(let k) = o.current?.kind else { return false }
                return k == order
            }) else { return true }
            return carrier.path.isEmpty && hypot(carrier.pos.x - spot.x, carrier.pos.y - spot.y) < 1.3
        }
        launch(flight)
    }
}
