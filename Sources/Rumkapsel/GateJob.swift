// The X-ray at the gate, as the simulation runs it. A cleared crate is set on the belt at the deck end; the
// belt takes it into the tunnel, where it is looked at, and out the pad side packed small for flight, for a
// hand to carry to its stack by the rocket. A crate whose clearance went while it waited is sent back out the
// deck end, for a hand to carry to the untested row. No SceneKit: the scene draws the belt, the tunnel, the
// monitor and the crates on the belt from these facts.

import Foundation
import simd

/// One station's X-ray: what waits on the belt and what the belt is doing.
final class GateJob {
    let station: String
    /// Crates set on the belt's deck end, oldest first.
    var waiting: [CrateRef] = []
    var phase = Phase.rest
    /// The verdict showing now, and until when.
    var scan: (passed: Bool, until: Double)?

    enum Phase {
        case rest
        /// Into the tunnel, from the deck end.
        case intake(CrateRef, since: Double)
        /// In the tunnel, on the monitor.
        case scanning(CrateRef, since: Double)
        /// Out again: through to the pad end when it passed, back to the deck end when it did not.
        case outgoing(CrateRef, since: Double, passed: Bool)
    }

    init(station: String) { self.station = station }

    /// The crate on the belt past the deck end, if any.
    var moving: CrateRef? {
        switch phase {
        case .intake(let c, _), .scanning(let c, _), .outgoing(let c, _, _): return c
        case .rest: return nil
        }
    }
}

/// The belt through the arch, in world coordinates at its top: where a crate is set on it, the tunnel's
/// middle on the gate line, the pad end a crate is picked up from, and the way through.
struct Belt {
    let start: SIMD3<Double>, tunnel: SIMD3<Double>, exit: SIMD3<Double>
    let inward: SIMD2<Double>
    static let top = 0.14
    static let intakeSeconds = 1.4, scanSeconds = 2.8, outSeconds = 1.4

    /// Where the crate on the belt is, and how big, at a moment of its trip.
    func place(of phase: GateJob.Phase, at clock: Double) -> (pos: SIMD3<Double>, scale: Double)? {
        func ease(_ t: Double) -> Double { let k = min(1, max(0, t)); return k * k * (3 - 2 * k) }
        switch phase {
        case .rest: return nil
        case .intake(_, let since): return (start + (tunnel - start) * ease((clock - since) / Belt.intakeSeconds), 1)
        case .scanning: return (tunnel, 1)
        case .outgoing(_, let since, let passed):
            let e = ease((clock - since) / Belt.outSeconds)
            return passed ? (tunnel + (exit - tunnel) * e, 1 - (1 - Station.testedScale) * e) : (tunnel + (start - tunnel) * e, 1)
        }
    }
}

extension Station {
    /// The belt through the half of the arch nearer the operator, when the station has a gate.
    var belt: Belt? {
        guard let arch = throughGate(height: Belt.top), let g = gate else { return nil }
        let d = SIMD3(g.inward.x, 0, g.inward.y)
        return Belt(start: arch.middle - d * 0.75, tunnel: arch.middle, exit: arch.middle + d * 0.8, inward: g.inward)
    }
    /// The operator's place: on the deck, across the gate line from the post, beside the belt.
    var operatorCell: Cell? {
        guard let post = securityPost, let first = gateDoorway.first else { return nil }
        let c = Cell(x: post.x - (first.pad.x - first.deck.x), y: post.y - (first.pad.y - first.deck.y))
        return deckCells.contains(c) ? c : nil
    }
}

extension Simulation {
    /// Where a crate comes off the belt: the far end, on the pad, when it passed; the deck end when it did not.
    func beltEnd(_ station: Station, _ belt: Belt, passed: Bool, crate: CrateRef) -> Spot {
        let at = passed ? belt.exit : belt.start
        let cell = Cell(x: Int((at.x - station.offset.x).rounded()), y: Int((at.z - station.offset.y).rounded()))
        return Spot(area: .gate, station: station.name, owner: crate.repo, label: crate.repo, cell: cell,
                    pos: SIMD3(at.x, Belt.top, at.z), level: 0, yaw: 0)
    }

    /// The X-ray for a station with a gate, made the first time it is needed.
    func gateJob(_ station: Station) -> GateJob? {
        if let g = gates[station.name] { return g }
        guard world.deckInUse(station: station.name), station.belt != nil else { return nil }
        let job = GateJob(station: station.name)
        gates[station.name] = job
        return job
    }

    /// A carrier set a cleared crate on the belt: it waits there for its turn in the tunnel.
    func gateReceived(_ crate: CrateRef, at spot: Spot) {
        guard let station = fleet.stations[crate.station], let job = gateJob(station) else { return }
        job.waiting.append(crate)
    }

    /// One frame of every X-ray: the belt takes the next crate in, the monitor looks, the belt sends it on.
    func stepGates(dt: Double) {
        for (name, job) in gates {
            guard let station = fleet.stations[name], let belt = station.belt else { continue }
            switch job.phase {
            case .rest:
                guard let next = job.waiting.first else { continue }
                job.waiting.removeFirst()
                world.freeGateSlot(next)
                job.phase = .intake(next, since: clock)
            case .intake(let crate, let since):
                if clock - since >= Belt.intakeSeconds { job.phase = .scanning(crate, since: clock) }
            case .scanning(let crate, let since):
                guard clock - since >= Belt.scanSeconds else { continue }
                let row = station.ledger[crate.repo, crate.number]
                let passed = row?.cleared == true || row?.alien == true || !world.workflow(repo: crate.repo).has(.cleared)
                job.scan = (passed, clock + Belt.outSeconds + 1)
                cue(.gateScan(station: name, passed: passed))
                job.phase = .outgoing(crate, since: clock, passed: passed)
            case .outgoing(let crate, let since, let passed):
                guard clock - since >= Belt.outSeconds else { continue }
                // Off the belt: at its far end when it passed, back at the deck end when it did not. Whoever
                // set it on the belt is waiting for it; sent back, they walk round to the deck end for it.
                let spot = beltEnd(station, belt, passed: passed, crate: crate)
                world.setDown(crate, at: spot)
                let riding = cargo.first { $0.value.onBelt && $0.value.command.crate == crate }?.key
                if let id = riding, let command = cargo[id]?.command.from(spot) {
                    cargo[id]?.command = command
                    cargo[id]?.onBelt = false
                    cargo[id]?.pastGate = passed
                    if let who = cargo[id]?.carrier, let m = bodies[who], m.current?.id == id {
                        m.current = command
                        m.waitingOn = nil
                        if !passed { m.phase = 0; m.phaseUntil = 0; walk(m, to: standCell(station, near: spot.cell)) }
                    }
                }
                cue(.gateHandoff(station: name, crate: crate, from: spot, passed: passed, riding: riding != nil))
                job.phase = .rest
            }
        }
    }
}
