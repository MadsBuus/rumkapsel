import Foundation
import simd

final class Vortex {
    let key: String
    let station: String
    var waiting: [(crate: CrateRef, from: Spot, into: RocketID)]
    var flying: [(crate: CrateRef, from: Spot, into: RocketID, at: Double)] = []
    let ring: SIMD3<Double>
    let openedAt: Double
    var closedAt: Double?
    var nextAt: Double

    init(key: String, station: String, crates: [(crate: CrateRef, from: Spot, into: RocketID)], ring: SIMD3<Double>, at clock: Double) {
        self.key = key; self.station = station; waiting = crates; self.ring = ring
        openedAt = clock
        nextAt = clock + Vortex.formSeconds
    }

    static let formSeconds = 2.6, every = 0.55
    static let liftSeconds = 0.6, crossSeconds = 1.1, spiralSeconds = 1.7
    static var flightSeconds: Double { liftSeconds + crossSeconds + spiralSeconds }
    static let fadeSeconds = 1.2
    static let radius = 0.42, turn = 1.8, height = 1.15
    static let packed = 0.12

    func strength(at clock: Double) -> Double {
        let up = min(1, max(0, (clock - openedAt - Vortex.formSeconds * 0.6) / 0.8))
        guard let closedAt else { return up }
        return up * max(0, 1 - (clock - closedAt) / Vortex.fadeSeconds)
    }

    static func place(from: SIMD3<Double>, ring: SIMD3<Double>, hatch: SIMD3<Double>, leftAt: Double, at clock: Double) -> (pos: SIMD3<Double>, scale: Double)? {
        func ease(_ t: Double) -> Double { let k = min(1, max(0, t)); return k * k * (3 - 2 * k) }
        let t = clock - leftAt
        guard t >= 0 else { return (from, 1) }
        let up = from + SIMD3(0, 0.45, 0)
        if t < liftSeconds { return (from + (up - from) * ease(t / liftSeconds), 1) }
        let u = t - liftSeconds
        if u < crossSeconds {
            let k = ease(u / crossSeconds)
            let p = up + (ring - up) * k
            return (p + SIMD3(0, sin(k * .pi) * 0.15, 0), 1 - 0.15 * k)
        }
        let s = min(1, (u - crossSeconds) / spiralSeconds)
        guard s < 1 else { return nil }
        let axis = hatch - ring
        let along = simd_length(axis) > 1e-6 ? simd_normalize(axis) : SIMD3(0, 0, -1)
        let side = simd_normalize(simd_cross(along, SIMD3(0, 1, 0)) + SIMD3(0, 1e-6, 0))
        let lift = simd_cross(side, along)
        let k = ease(s)
        let angle = s * 2.5 * 2 * .pi
        let r = radius * 0.8 * (1 - k)
        let p = ring + axis * k + side * (cos(angle) * r) + lift * (sin(angle) * r)
        return (p, 0.85 + (packed - 0.85) * k)
    }

    static func ringPoint(ring: SIMD3<Double>, hatch: SIMD3<Double>, slot: Int, at clock: Double) -> SIMD3<Double> {
        let axis = hatch - ring
        let along = simd_length(axis) > 1e-6 ? simd_normalize(axis) : SIMD3(0, 0, -1)
        let side = simd_normalize(simd_cross(along, SIMD3(0, 1, 0)) + SIMD3(0, 1e-6, 0))
        let lift = simd_cross(side, along)
        let angle = clock * turn + Double(slot) * 2 * .pi / 3
        return ring + side * (cos(angle) * radius) + lift * (sin(angle) * radius)
    }
}

extension Simulation {
    func openVortex(_ r: RocketJob, station: Station) {
        guard vortices[r.key] == nil, let field = station.hall.padField, var view = shown[station.name] else { return }
        var standing: [(crate: CrateRef, from: Spot, into: RocketID)] = []
        for c in station.facts.crates.values.sorted(by: { $0.id < $1.id }) {
            guard case .aboard(let rocket) = c.place, loads(r, rocket) else { continue }
            let ref = CrateRef(station: station.name, repo: c.id.repo, number: c.id.number)
            switch view.crates[c.id] {
            case .row(let s)?: standing.append((ref, self.standing(station, c.id.repo, s), rocket))
            case .parked(let p)?: standing.append((ref, p, rocket))
            default: continue
            }
        }
        guard !standing.isEmpty else { return }
        let middle = standing.map { $0.from.pos.x }.reduce(0, +) / Double(standing.count)
        let x = min(max(middle, station.offset.x + field.from.x + 0.6), station.offset.x + field.to.x - 0.6)
        let ring = SIMD3(x, Vortex.height, station.offset.y + field.from.y - 0.55)
        let crates = standing.sorted { a, b in
            let da = simd_distance(SIMD2(a.from.pos.x, a.from.pos.z), SIMD2(ring.x, ring.z)), db = simd_distance(SIMD2(b.from.pos.x, b.from.pos.z), SIMD2(ring.x, ring.z))
            return abs(da - db) > 0.01 ? da < db : a.from.level > b.from.level
        }
        for c in crates {
            let id = CrateID(repo: c.crate.repo, number: c.crate.number)
            for (cid, job) in cargo where job.crate == id && job.command.crate?.station == station.name { callOff(cid) }
            view.crates[id] = .vortex(c.into)
        }
        shown[station.name] = view
        settle(station.name)
        vortices[r.key] = Vortex(key: r.key, station: station.name, crates: crates, ring: ring, at: clock)
        StationLog.write("release", "\(r.key) vortex opens at \(String(format: "%.1f", clock)) for \(crates.map { "#\($0.crate.number)" }.joined(separator: " "))")
        cue(.redraw)
        onLog("\(r.repo): released, the drones pull \(crates.count == 1 ? "its crate" : "its \(crates.count) crates") out through the field")
    }

    func vortexHatch(_ v: Vortex) -> SIMD3<Double>? {
        guard let station = fleet.stations[v.station], let r = rockets[v.key], let at = rocketSpot(station: station, key: r.key) else { return nil }
        let h = RocketGeometry.hatch(offset: r.tipOffset)
        return SIMD3(station.offset.x + at.x + h.x, h.y, station.offset.y + at.y + h.z)
    }

    func stepVortices() {
        for (key, v) in vortices {
            guard fleet.stations[v.station] != nil else { vortices[key] = nil; continue }
            if v.closedAt == nil, clock >= v.nextAt, !v.waiting.isEmpty {
                let next = v.waiting.removeFirst()
                v.flying.append((next.crate, next.from, next.into, clock))
                v.nextAt = clock + Vortex.every
            }
            for (i, f) in v.flying.enumerated().reversed() where clock - f.at >= Vortex.flightSeconds {
                v.flying.remove(at: i)
                shown[v.station]?.crates[CrateID(repo: f.crate.repo, number: f.crate.number)] = .aboard(f.into)
            }
            if v.closedAt == nil, v.waiting.isEmpty, v.flying.isEmpty {
                v.closedAt = clock
                StationLog.write("release", "\(key) vortex closes at \(String(format: "%.1f", clock)), rocket \(rockets[key].map { "\($0.phaseKind)" } ?? "gone")")
            }
            if let closed = v.closedAt, clock - closed >= Vortex.fadeSeconds { vortices[key] = nil }
        }
    }
}
