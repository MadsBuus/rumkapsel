// A release leaving the hall, as the simulation runs it. At the merge the drones fly out to the field over the
// cleared rows and turn there in a ring; a vortex opens from the ring to the rocket's hatch, and it pulls the
// release's crates off their tiles one after another, through the field, and spirals them shrinking into the
// hold. Nobody carries a release out: the machines take what is ready, all of it. Every place is worked out on
// the station clock, so a headless capture draws it as the window does. No SceneKit: `VortexView.swift` draws it.

import Foundation
import simd

/// One release being pulled out through the field.
final class Vortex {
    /// The rocket it loads, by "station|repo".
    let key: String
    let station: String
    /// The crates still on their tiles, in the order they go.
    var waiting: [(crate: CrateRef, from: Spot)]
    /// The crates under way, and when each left its tile.
    var flying: [(crate: CrateRef, from: Spot, at: Double)] = []
    /// Where the ring turns, in world coordinates: just outside the field, level with the release's crates.
    let ring: SIMD3<Double>
    let openedAt: Double
    /// When the last crate went into the hold.
    var closedAt: Double?
    var nextAt: Double

    init(key: String, station: String, crates: [(crate: CrateRef, from: Spot)], ring: SIMD3<Double>, at clock: Double) {
        self.key = key; self.station = station; waiting = crates; self.ring = ring
        openedAt = clock
        nextAt = clock + Vortex.formSeconds
    }

    /// How long the drones take to fly out and form the ring, how far apart the crates leave, and each crate's
    /// three legs: up off its tile, across to the ring through the field, and the spiral into the hold.
    static let formSeconds = 2.6, every = 0.55
    static let liftSeconds = 0.6, crossSeconds = 1.1, spiralSeconds = 1.7
    static var flightSeconds: Double { liftSeconds + crossSeconds + spiralSeconds }
    /// How long the vortex takes to fade once the last crate is in.
    static let fadeSeconds = 1.2
    /// The ring's radius, how fast it turns, and how high off the floor it stands.
    static let radius = 0.42, turn = 1.8, height = 1.15
    /// How small a crate is when it reaches the hold.
    static let packed = 0.12

    /// How strongly the vortex shows at a moment, 0 to 1: rising as the ring forms, falling once it is done.
    func strength(at clock: Double) -> Double {
        let up = min(1, max(0, (clock - openedAt - Vortex.formSeconds * 0.6) / 0.8))
        guard let closedAt else { return up }
        return up * max(0, 1 - (clock - closedAt) / Vortex.fadeSeconds)
    }

    /// Where a crate under way is at a moment, and how big: lifted off its tile, drawn across through the field
    /// to the ring, then spiralled along the vortex into the hatch, shrinking as it turns.
    static func place(from: SIMD3<Double>, ring: SIMD3<Double>, hatch: SIMD3<Double>, leftAt: Double, at clock: Double) -> (pos: SIMD3<Double>, scale: Double)? {
        func ease(_ t: Double) -> Double { let k = min(1, max(0, t)); return k * k * (3 - 2 * k) }
        let t = clock - leftAt
        guard t >= 0 else { return (from, 1) }
        let up = from + SIMD3(0, 0.45, 0)
        if t < liftSeconds { return (from + (up - from) * ease(t / liftSeconds), 1) }
        let u = t - liftSeconds
        if u < crossSeconds {
            let k = ease(u / crossSeconds)
            // A shallow arc: it rises a little more on its way, the ring's pull taking it.
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

    /// Where drone `slot` of three holds the ring at a moment: round its middle, square to the vortex, turning.
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
    /// The release's crates go: the drones form the ring, and the vortex takes them off their rows, the cleared
    /// rows or, for a repository with no staging, storage. The order is what looks best: the nearest to the ring
    /// first, a stack's top before what is under it.
    func openVortex(_ r: RocketJob, station: Station, from area: String, crates numbers: [Int]) {
        guard vortices[r.key] == nil, !numbers.isEmpty else { return }
        let layout = world.yardLayout(station: station, area: area).filter { $0.repo == r.repo && !$0.carried && numbers.contains($0.number) }
        guard !layout.isEmpty, let field = station.padField else {
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
            world.claim(c.crate)   // off the rows from now: the vortex draws it
        }
        vortices[r.key] = Vortex(key: r.key, station: station.name, crates: crates, ring: ring, at: clock)
        StationLog.write("release", "\(r.key) vortex opens at \(String(format: "%.1f", clock)) for \(crates.map { "#\($0.crate.number)" }.joined(separator: " "))")
        cue(.redraw)
        onLog("\(r.repo): released, the drones pull \(crates.count == 1 ? "its crate" : "its \(crates.count) crates") out through the field")
    }

    /// Where a vortex ends: the hatch of its rocket as the rocket stands now.
    func vortexHatch(_ v: Vortex) -> SIMD3<Double>? {
        guard let station = fleet.stations[v.station], let r = rockets[v.key], let at = rocketSpot(station: station, repo: r.repo) else { return nil }
        let h = RocketGeometry.hatch(lift: r.lift)
        return SIMD3(station.offset.x + at.x + h.x, h.y, station.offset.y + at.y + h.z)
    }

    /// One frame of every vortex: the next crate leaves its tile on the beat, one in the hold is aboard, and a
    /// vortex with nothing left fades and lets its drones go home.
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
