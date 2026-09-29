// The security unit at work, as the simulation runs it. A cleared crate is set down by the gate, on the deck
// side, and its carrier goes; the unit comes off its post, looks it over and scans it, and the crate floats
// through the gate onto its stack beside the rocket, shrinking as it goes. Clearance taken back runs the other
// way: the unit fetches the crate from its stack, scans it red and floats it out to the untested row. No
// SceneKit: the scene draws the unit, the waiting crates and the one in the air from these facts.

import Foundation

/// One station's gate: what waits there, and what the unit is doing about it.
final class GateJob {
    let station: String
    /// Where the unit is and which way it faces, in world coordinates.
    var unit: SIMD3<Double>
    var yaw: Double
    /// Crates set down by the gate, waiting to go through, and where each stands.
    var waiting: [(crate: CrateRef, at: SIMD3<Double>)] = []
    /// Crates whose clearance was taken back, standing on their stack until the unit fetches them.
    var ejecting: [(crate: CrateRef, at: SIMD3<Double>)] = []
    var phase = Phase.rest
    /// The scan showing now: passed or not, and until when.
    var scan: (passed: Bool, until: Double)?

    enum Phase {
        case rest
        case going(to: SIMD3<Double>)
        case inspecting(crate: CrateRef, at: SIMD3<Double>, began: Double, outbound: Bool)
        case carrying(GateFlight)
    }

    init(station: String, post: SIMD3<Double>, yaw: Double) { self.station = station; unit = post; self.yaw = yaw }

    /// The crate the unit is looking at or carrying right now.
    var busyWith: CrateRef? {
        switch phase {
        case .inspecting(let c, _, _, _): return c
        case .carrying(let f): return f.crate
        default: return nil
        }
    }
}

/// A crate floating through the gate on the station clock: an eased arc, its size changing on the way.
struct GateFlight {
    let crate: CrateRef
    let from: SIMD3<Double>, to: SIMD3<Double>
    let fromScale: Double, toScale: Double
    let at: Double, seconds: Double
    /// Where it lands, and whether it is going out to the untested row.
    let spot: Spot
    let outbound: Bool

    func position(at clock: Double) -> (pos: SIMD3<Double>, scale: Double, done: Bool) {
        let t = min(1, max(0, (clock - at) / seconds))
        let e = t * t * (3 - 2 * t)
        let p = from + (to - from) * e
        return (SIMD3(p.x, p.y + sin(t * .pi) * 0.6, p.z), fromScale + (toScale - fromScale) * e, t >= 1)
    }
}

extension Simulation {
    /// How the unit moves and looks: quick and restless, it is on duty.
    private static var unitSpeed: Double { 3.2 }
    private static var inspectSeconds: Double { 2.6 }
    private static var hover: Double { 0.28 }

    /// The job for a station with a gate and a post, made the first time it is needed.
    func gateJob(_ station: Station) -> GateJob? {
        if let g = gates[station.name] { return g }
        guard world.deckInUse(station: station.name), let post = station.securityPost, let g = station.gate else { return nil }
        let at = SIMD3(station.offset.x + Double(post.x), Simulation.hover, station.offset.y + Double(post.y))
        let job = GateJob(station: station.name, post: at, yaw: atan2(-g.inward.x, -g.inward.y))
        gates[station.name] = job
        return job
    }

    /// A carrier set a cleared crate down by the gate: it waits there for the unit.
    func gateReceived(_ crate: CrateRef, at spot: Spot) {
        guard let station = fleet.stations[crate.station], let job = gateJob(station) else { return }
        job.waiting.append((crate, spot.pos))
    }

    /// Clearance taken back: the unit fetches the crate from its stack. True when the gate takes it; false
    /// leaves it to a carrier.
    @discardableResult
    func gateEject(_ crate: CrateRef) -> Bool {
        guard let station = fleet.stations[crate.station], let job = gateJob(station),
              let here = world.testedStanding(station: station, crate: crate) else { return false }
        world.claim(crate)
        station.ledger.order(repo: crate.repo, number: crate.number, to: .deck)
        job.ejecting.append((crate, here))
        return true
    }

    /// One frame of every gate: the unit goes to what waits, looks it over, and sends it through.
    func stepGates(dt: Double) {
        for (name, job) in gates {
            guard let station = fleet.stations[name], let post = station.securityPost else { continue }
            let home = SIMD3(station.offset.x + Double(post.x), Simulation.hover, station.offset.y + Double(post.y))
            switch job.phase {
            case .rest:
                if let next = job.waiting.first {
                    job.phase = .going(to: next.at + SIMD3(0, 0.62, 0))
                } else if let next = job.ejecting.first {
                    job.phase = .going(to: next.at + SIMD3(0, 0.5, 0))
                } else {
                    fly(job, toward: home, dt: dt, speed: 1.2)
                }
            case .going(let target):
                if fly(job, toward: target, dt: dt, speed: Simulation.unitSpeed) {
                    if let next = job.waiting.first {
                        job.phase = .inspecting(crate: next.crate, at: next.at, began: clock, outbound: false)
                    } else if let next = job.ejecting.first {
                        job.phase = .inspecting(crate: next.crate, at: next.at, began: clock, outbound: true)
                    } else {
                        job.phase = .rest
                    }
                }
            case .inspecting(let crate, let at, let began, let outbound):
                // Round it, low and quick, the eye on it the whole time.
                let t = clock - began, a = t * 4.2
                job.unit = at + SIMD3(cos(a) * 0.32, 0.5 + sin(t * 9) * 0.04, sin(a) * 0.32)
                job.yaw = atan2(at.x - job.unit.x, at.z - job.unit.z)
                guard t >= Simulation.inspectSeconds else { continue }
                sendThrough(job, crate: crate, from: at, outbound: outbound, station: station)
            case .carrying(let f):
                let p = f.position(at: clock)
                job.unit = p.pos + SIMD3(0, 0.45, 0)
                guard p.done else { continue }
                world.setDown(f.crate, at: f.spot)
                world.landed(station: station, repo: f.crate.repo, number: f.crate.number, in: .deck, at: now)
                cue(.gateLanded(station: name, crate: f.crate))
                job.phase = .rest
            }
        }
    }

    /// The scan's verdict and the crate in the air. Inbound, a crate still cleared passes and goes onto its
    /// stack; one whose clearance went while it waited is scanned red and goes to the untested row instead.
    private func sendThrough(_ job: GateJob, crate: CrateRef, from: SIMD3<Double>, outbound: Bool, station: Station) {
        if outbound { job.ejecting.removeAll { $0.crate == crate } } else { job.waiting.removeAll { $0.crate == crate } }
        world.freeGateSlot(crate)
        let row = station.ledger[crate.repo, crate.number]
        let passes = !outbound && (row?.cleared == true || row?.alien == true || !world.workflow(repo: crate.repo).has(.cleared))
        job.scan = (passes, clock + 1.2)
        cue(.gateScan(station: station.name, passed: passes))
        station.ledger.order(repo: crate.repo, number: crate.number, to: .deck)
        guard let to = world.slotNow(for: crate, toward: .deck, pastGate: true) else { job.phase = .rest; return }
        let small = to.area == .tested
        job.phase = .carrying(GateFlight(crate: crate, from: from, to: to.pos, fromScale: outbound ? Station.testedScale : 1,
                                         toScale: small ? Station.testedScale : 1, at: clock, seconds: 2.2, spot: to, outbound: !small))
        cue(.gateLift(station: station.name, crate: crate))
    }

    /// Moves the unit toward a point; true once it is there.
    @discardableResult
    private func fly(_ job: GateJob, toward target: SIMD3<Double>, dt: Double, speed: Double) -> Bool {
        let d = target - job.unit, dist = (d.x * d.x + d.y * d.y + d.z * d.z).squareRoot()
        if dist < 0.03 { job.unit = target; return true }
        job.unit += d / dist * min(dist, speed * dt)
        if (d.x * d.x + d.z * d.z) > 0.0004 { job.yaw = atan2(d.x, d.z) }
        return false
    }
}
