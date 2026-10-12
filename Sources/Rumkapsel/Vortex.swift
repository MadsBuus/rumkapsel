import Foundation
import simd

final class Vortex {
    let key: String
    let station: String
    var waiting: [(crate: CrateRef, from: Spot)]
    var flying: [(crate: CrateRef, from: Spot, at: Double)] = []
    let ring: SIMD3<Double>
    let openedAt: Double
    var closedAt: Double?
    var nextAt: Double

    init(key: String, station: String, crates: [(crate: CrateRef, from: Spot)], ring: SIMD3<Double>, at clock: Double) {
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
    func openVortex(_ r: RocketJob, station: Station, from area: String, crates numbers: [Int]) {
        guard vortices[r.key] == nil, !numbers.isEmpty else { return }
        let layout = world.yardLayout(station: station, area: area).filter { $0.repo == r.repo && !$0.carried && numbers.contains($0.number) }
        guard !layout.isEmpty, let field = station.hall.padField else {
            StationLog.write("release", "\(r.key) no vortex: nothing of \(numbers) on the \(area) rows")
            return
        }
        let middle = layout.map { $0.pos.x }.reduce(0, +) / Double(layout.count)
        let x = min(max(middle, station.offset.x + field.from.x + 0.6), station.offset.x + field.to.x - 0.6)
        let ring = SIMD3(x, Vortex.height, station.offset.y + field.from.y - 0.55)
        let crates = layout.sorted { a, b in
            let da = simd_distance(SIMD2(a.pos.x, a.pos.z), SIMD2(ring.x, ring.z)), db = simd_distance(SIMD2(b.pos.x, b.pos.z), SIMD2(ring.x, ring.z))
            return abs(da - db) > 0.01 ? da < db : a.level > b.level
        }.map { s -> (crate: CrateRef, from: Spot) in
            (CrateRef(station: station.name, repo: s.repo, number: s.number),
             Spot(area: area == "deck" ? .tested : .storage, station: station.name, owner: s.repo, label: s.repo, cell: s.cell, pos: s.pos, level: s.level, yaw: s.yaw))
        }
        for c in crates {
            station.ledger.order(repo: c.crate.repo, number: c.crate.number, to: .pad)
            world.claim(c.crate)
        }
        vortices[r.key] = Vortex(key: r.key, station: station.name, crates: crates, ring: ring, at: clock)
        StationLog.write("release", "\(r.key) vortex opens at \(String(format: "%.1f", clock)) for \(crates.map { "#\($0.crate.number)" }.joined(separator: " "))")
        cue(.redraw)
        onLog("\(r.repo): released, the drones pull \(crates.count == 1 ? "its crate" : "its \(crates.count) crates") out through the field")
    }

    func vortexHatch(_ v: Vortex) -> SIMD3<Double>? {
        guard let station = fleet.stations[v.station], let r = rockets[v.key], let at = rocketSpot(station: station, repo: r.repo) else { return nil }
        let h = RocketGeometry.hatch(lift: r.lift)
        return SIMD3(station.offset.x + at.x + h.x, h.y, station.offset.y + at.y + h.z)
    }

    func stepVortices() {
        for (key, v) in vortices {
            guard let station = fleet.stations[v.station] else { vortices[key] = nil; continue }
            if v.closedAt == nil, clock >= v.nextAt, !v.waiting.isEmpty {
                let next = v.waiting.removeFirst()
                v.flying.append((next.crate, next.from, clock))
                v.nextAt = clock + Vortex.every
            }
            for (i, f) in v.flying.enumerated().reversed() where clock - f.at >= Vortex.flightSeconds {
                v.flying.remove(at: i)
                world.setDown(f.crate, at: world.padSpot(station: station, repo: f.crate.repo))
                world.landed(station: station, repo: f.crate.repo, number: f.crate.number, in: .pad, at: now)
            }
            if v.closedAt == nil, v.waiting.isEmpty, v.flying.isEmpty {
                v.closedAt = clock
                StationLog.write("release", "\(key) vortex closes at \(String(format: "%.1f", clock)), rocket \(rockets[key].map { "\($0.phaseKind)" } ?? "gone")")
                fleet.save()
            }
            if let closed = v.closedAt, clock - closed >= Vortex.fadeSeconds { vortices[key] = nil }
        }
    }
}
