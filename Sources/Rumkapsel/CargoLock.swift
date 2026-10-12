// The cargo lock between the deck and the pad, as the simulation runs it: a chamber in the gate with a door on
// each side, the one way a crate crosses the hull. Out: a carrier sets a crate on the tray before the inner door
// and goes about its day; the chamber takes it in, the door shuts, the air goes while a scan sweeps the crate
// and packs it small for flight, and the outer door opens it onto the pad's tray for a drone. A crate whose
// clearance went while it waited is refused: the outer door stays shut and it comes back out onto the deck for
// a hand. In: a drone sets a crate bound indoors on the outer tray; the chamber takes it, fills with air, and
// opens onto the deck. No SceneKit: the scene draws the doors, the chamber and the crates in it from these facts.

import Foundation
import simd

/// One station's lock: what waits on its trays and what the chamber is doing.
final class LockJob {
    let station: String
    /// Crates on the inner tray bound out, oldest first, and on the outer tray bound in.
    var waiting: [CrateRef] = []
    var returning: [CrateRef] = []
    var phase = Phase.rest
    /// The verdict showing now, and until when.
    var scan: (passed: Bool, until: Double)?

    /// A crate through the chamber, and which way.
    struct Trip { let crate: CrateRef; let inbound: Bool }

    enum Phase {
        case rest
        /// In off its tray, the door behind it shutting.
        case intake(Trip, since: Double)
        /// Shut in: the air going for a crate bound out while the scan sweeps it, coming for one bound in.
        case cycling(Trip, since: Double)
        /// Out onto the far tray, or back onto the tray it came from when refused.
        case outgoing(Trip, since: Double, passed: Bool)
    }

    init(station: String) { self.station = station }

    /// The crate in the chamber or on its way through, if any.
    var trip: Trip? {
        switch phase {
        case .intake(let t, _), .cycling(let t, _), .outgoing(let t, _, _): return t
        case .rest: return nil
        }
    }
}

/// The lock in the gate, in world coordinates at its trays' top: the inner tray on the deck where a crate is
/// set down, the chamber's middle on the gate's line, the outer tray on the pad a drone takes it from.
struct CargoLock {
    let inner: SIMD3<Double>, chamber: SIMD3<Double>, outer: SIMD3<Double>
    let inward: SIMD2<Double>
    static let top = 0.14
    static let intakeSeconds = 1.4, cycleSeconds = 3.2, outSeconds = 1.4
    /// How far along the gate's line the chamber reaches either side of its middle, and how deep it is.
    static let halfWidth = 0.4, halfDepth = 0.36
    /// How high its walls stand: the yard's walls' height, its glass roof on top.
    static let height = 0.62

    /// Where the crate in the chamber is, and how big, at a moment of its trip: full size indoors, packed small
    /// for flight outside, the change made while the chamber cycles.
    func place(of phase: LockJob.Phase, at clock: Double) -> (pos: SIMD3<Double>, scale: Double)? {
        func ease(_ t: Double) -> Double { let k = min(1, max(0, t)); return k * k * (3 - 2 * k) }
        let small = Station.testedScale
        switch phase {
        case .rest: return nil
        case .intake(let t, let since):
            let from = t.inbound ? outer : inner
            return (from + (chamber - from) * ease((clock - since) / CargoLock.intakeSeconds), t.inbound ? small : 1)
        case .cycling(let t, let since):
            let k = ease((clock - since) / CargoLock.cycleSeconds)
            return (chamber, t.inbound ? small + (1 - small) * k : 1 - (1 - small) * k)
        case .outgoing(let t, let since, let passed):
            let e = ease((clock - since) / CargoLock.outSeconds)
            // Through to the far side when it passed; refused, back the way it came and back to its size.
            let to = passed ? (t.inbound ? inner : outer) : (t.inbound ? outer : inner)
            let size = passed ? (t.inbound ? 1 : small) : (t.inbound ? small : small + (1 - small) * e)
            return (chamber + (to - chamber) * e, size)
        }
    }

    /// How open each door is at a moment, from shut (0) to open (1): the inner on the deck, the outer on the pad.
    func doors(of phase: LockJob.Phase, at clock: Double) -> (inner: Double, outer: Double) {
        func ramp(_ t: Double, _ span: Double) -> Double { min(1, max(0, t / span)) }
        switch phase {
        case .rest: return (0, 0)
        case .intake(let t, let since):
            // Open for the crate coming in, shut behind it over the last of the intake.
            let left = CargoLock.intakeSeconds - (clock - since)
            let open = min(ramp(clock - since, 0.3), ramp(left, 0.4))
            return t.inbound ? (0, open) : (open, 0)
        case .cycling: return (0, 0)
        case .outgoing(let t, let since, let passed):
            let left = CargoLock.outSeconds - (clock - since)
            let open = min(ramp(clock - since, 0.3), ramp(left + 0.2, 0.4))
            let outward = passed != t.inbound   // through to the pad: out and passed, or in and refused
            return outward ? (0, open) : (open, 0)
        }
    }
}

extension Station {
    /// The lock in the half of the gate away from where the hallway comes onto the deck.
    var lock: CargoLock? {
        guard let through = throughLock(height: CargoLock.top), let g = gate else { return nil }
        let d = SIMD3(g.inward.x, 0, g.inward.y)
        return CargoLock(inner: through.middle - d * 0.75, chamber: through.middle, outer: through.middle + d * 0.8, inward: g.inward)
    }

    /// Whether a spot is outside the hull, on the pad, where only drones work.
    func isOutside(_ spot: Spot) -> Bool { spot.area == .pad || padCells.contains(spot.cell) }

    /// The floor the lock stands on, cell by cell: the chamber and the inner tray in front of it. No crate row
    /// is laid on these cells, and nobody walks through them.
    var lockFootprint: Set<Cell> {
        guard let lock else { return [] }
        func cell(_ p: SIMD2<Double>) -> Cell { Cell(x: Int(p.x.rounded()), y: Int(p.y.rounded())) }
        let a = SIMD2(lock.inner.x - offset.x, lock.inner.z - offset.y) - lock.inward * 0.25
        let b = SIMD2(lock.outer.x - offset.x, lock.outer.z - offset.y) + lock.inward * 0.25
        let across = SIMD2(-lock.inward.y, lock.inward.x)
        var out = Set<Cell>()
        for k in 0...12 {
            let p = a + (b - a) * Double(k) / 12
            for w in [-0.3, 0, 0.3] { out.insert(cell(p + across * w)) }
        }
        return out
    }
}

extension Simulation {
    /// Where a carrier stands to take a crate off the inner tray: on the deck, straight out from the door.
    func besideLock(_ station: Station, _ lock: CargoLock) -> Cell {
        let near = SIMD2(lock.inner.x - station.offset.x, lock.inner.z - station.offset.y) - lock.inward
        return standCell(station, near: Cell(x: Int(near.x.rounded()), y: Int(near.y.rounded())))
    }

    /// A crate on one of the lock's trays: the inner on the deck, the outer on the pad.
    func lockEnd(_ station: Station, _ lock: CargoLock, outer: Bool, crate: CrateRef) -> Spot {
        let at = outer ? lock.outer : lock.inner
        let cell = Cell(x: Int((at.x - station.offset.x).rounded()), y: Int((at.z - station.offset.y).rounded()))
        return Spot(area: .lock, station: station.name, owner: crate.repo, label: crate.repo, cell: cell,
                    pos: SIMD3(at.x, CargoLock.top, at.z), level: 0, yaw: 0)
    }

    /// The lock for a station with a pad beside its deck, made the first time it is needed.
    func lockJob(_ station: Station) -> LockJob? {
        if let l = locks[station.name] { return l }
        guard station.lock != nil else { return nil }
        let job = LockJob(station: station.name)
        locks[station.name] = job
        return job
    }

    /// A carrier or the pallet's wand set a crate on the inner tray: it waits there for its turn in the chamber.
    func lockReceived(_ crate: CrateRef) {
        guard let station = fleet.stations[crate.station], let job = lockJob(station) else { return }
        job.waiting.append(crate)
    }

    /// A drone set a crate bound indoors on the outer tray.
    func lockReturned(_ crate: CrateRef) {
        guard let station = fleet.stations[crate.station], let job = lockJob(station) else { return }
        job.returning.append(crate)
    }

    /// One frame of every lock: the chamber takes the next crate in, cycles, and sends it on. Crates bound out go
    /// first: a release is waiting on them.
    func stepLocks(dt: Double) {
        for (name, job) in locks {
            guard let station = fleet.stations[name], let lock = station.lock else { continue }
            switch job.phase {
            case .rest:
                if let next = job.waiting.first {
                    job.waiting.removeFirst()
                    world.freeLockSlot(next)
                    job.phase = .intake(LockJob.Trip(crate: next, inbound: false), since: clock)
                } else if let next = job.returning.first {
                    job.returning.removeFirst()
                    job.phase = .intake(LockJob.Trip(crate: next, inbound: true), since: clock)
                }
            case .intake(let trip, let since):
                if clock - since >= CargoLock.intakeSeconds { job.phase = .cycling(trip, since: clock) }
            case .cycling(let trip, let since):
                guard clock - since >= CargoLock.cycleSeconds else { continue }
                var passed = true
                if !trip.inbound {
                    // Bound for its stack by the rocket, it must still be cleared; into the rocket, the rocket's own
                    // clearance speaks for it.
                    let collect = cargo.first { $0.value.inLock && $0.value.command.crate == trip.crate }?.value
                    let toRocket: Bool = { if case .carry(_, _, .pad)? = collect?.command.kind { return true }; return false }()
                    let row = station.ledger[trip.crate.repo, trip.crate.number]
                    passed = toRocket || row?.cleared == true || row?.alien == true || !world.workflow(repo: trip.crate.repo).has(.cleared)
                    job.scan = (passed, clock + CargoLock.outSeconds + 1)
                }
                cue(.lockCycled(station: name, inbound: trip.inbound, passed: passed))
                job.phase = .outgoing(trip, since: clock, passed: passed)
            case .outgoing(let trip, let since, let passed):
                guard clock - since >= CargoLock.outSeconds else { continue }
                // Out on a tray: the far one when it passed, back on its own when refused. The carry waiting for
                // it starts from there, a drone's outside and a hand's indoors.
                let outside = passed != trip.inbound
                let spot = lockEnd(station, lock, outer: outside, crate: trip.crate)
                world.setDown(trip.crate, at: spot)
                let waiting = cargo.first { $0.value.inLock && $0.value.command.crate == trip.crate }?.key
                if let id = waiting, let command = cargo[id]?.command.from(spot) {
                    cargo[id]?.command = command
                    cargo[id]?.inLock = false
                    cargo[id]?.byDrone = outside
                    cargo[id]?.pastLock = outside
                    if !passed { reaim(id) }
                }
                cue(.lockHandoff(station: name, crate: trip.crate, from: spot, collect: waiting))
                job.phase = .rest
            }
        }
    }
}
