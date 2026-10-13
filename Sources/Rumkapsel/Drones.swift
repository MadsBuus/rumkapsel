import Foundation
import simd

final class PadDrone {
    let id: String
    let station: String
    let berth: Int
    let berthYaw: Double
    var pos: SIMD3<Double>
    var vel = SIMD3<Double>(repeating: 0)
    var push = SIMD3<Double>(repeating: 0)
    var yaw = 0.0
    var task = Task.rest
    var route: [SIMD3<Double>] = []
    var torch = false
    var weldSide: Int?

    enum Task: Equatable {
        case rest
        case weld(String)
        case vortex(String, Int)
        case home
    }

    init(id: String, station: String, berth: Int, berthYaw: Double, at pos: SIMD3<Double>) {
        self.id = id; self.station = station; self.berth = berth; self.berthYaw = berthYaw; self.pos = pos; self.yaw = berthYaw
    }

    var isFree: Bool { task == .rest || task == .home }
}

enum DroneFlight {
    static let count = 3
    static let speed = 1.3, accel = 2.0
    static let low = 0.85, high = 2.3
    static let standOff = 0.19
    static let berthPitch = 0.3
}

extension Simulation {
    func padDrones(_ station: Station) -> [PadDrone] {
        if let d = drones[station.name] { return d }
        guard !station.hall.padCells.isEmpty, station.hall.droneRackCell != nil else { return [] }
        let along = rack(station)?.along ?? SIMD2(1, 0)
        let made = (0..<DroneFlight.count).map { k in
            PadDrone(id: "drone:\(station.name)#\(k)", station: station.name, berth: k, berthYaw: atan2(-along.y, along.x), at: berth(station, k))
        }
        drones[station.name] = made
        return made
    }

    func rack(_ station: Station) -> (at: SIMD2<Double>, along: SIMD2<Double>)? {
        guard let c = station.hall.droneRackCell else { return nil }
        return (SIMD2(Double(c.x), Double(c.y)), SIMD2(1, 0))
    }

    func berth(_ station: Station, _ k: Int) -> SIMD3<Double> {
        guard let r = rack(station) else { return SIMD3(station.offset.x, 0.2, station.offset.y) }
        let p = r.at + r.along * (Double(k) - Double(DroneFlight.count - 1) / 2) * DroneFlight.berthPitch
        return SIMD3(station.offset.x + p.x, 0.2, station.offset.y + p.y)
    }

    func stepDrones(dt: Double) {
        for station in fleet.stations.values {
            let fleet = padDrones(station)
            guard !fleet.isEmpty else { continue }
            assignDrones(station, fleet)
            for d in fleet {
                fly(d, dt: dt)
                work(d, station: station)
            }
        }
    }

    // MARK: who does what

    private func assignDrones(_ station: Station, _ fleet: [PadDrone]) {
        if let v = vortices.values.first(where: { $0.station == station.name && $0.closedAt == nil }) {
            for (k, d) in fleet.enumerated() where d.task != .vortex(v.key, k) {
                d.task = .vortex(v.key, k)
                d.torch = false
                d.weldSide = nil
                d.route = []
            }
        }
        func nearest(to p: SIMD3<Double>) -> PadDrone? {
            fleet.filter(\.isFree).min { simd_distance($0.pos, p) < simd_distance($1.pos, p) }
        }
        for r in rockets.values where r.station == station.name && r.welding {
            guard !fleet.contains(where: { $0.task == .weld(r.key) }),
                  let at = rocketSpot(station: station, key: r.key),
                  let d = nearest(to: SIMD3(station.offset.x + at.x, 1, station.offset.y + at.y)) else { continue }
            d.task = .weld(r.key)
            d.weldSide = nil
            d.route = []
        }
    }

    // MARK: flying

    private func plan(_ d: PadDrone, to: SIMD3<Double>, station: Station) -> [SIMD3<Double>] {
        let from = d.pos
        let flat = SIMD2(to.x - from.x, to.z - from.z)
        if simd_length(flat) < 0.35 { return [to] }
        let cruise = (crossesRocket(from, to, station: station) ? DroneFlight.high : DroneFlight.low) + Double(d.berth) * 0.08
        let up = max(cruise, from.y, to.y)
        return [SIMD3(from.x, up, from.z), SIMD3(to.x, up, to.z), to]
    }

    private func crossesRocket(_ a: SIMD3<Double>, _ b: SIMD3<Double>, station: Station) -> Bool {
        let p = SIMD2(a.x - station.offset.x, a.z - station.offset.y), q = SIMD2(b.x - station.offset.x, b.z - station.offset.y)
        func distance(to c: SIMD2<Double>) -> Double {
            let ab = q - p, len = simd_length_squared(ab)
            let t = len > 1e-9 ? min(1, max(0, simd_dot(c - p, ab) / len)) : 0
            return simd_distance(p + ab * t, c)
        }
        return rockets.values.contains { r in
            guard r.station == station.name, let at = rocketSpot(station: station, key: r.key) else { return false }
            return distance(to: at) < 0.42
        }
    }

    private func fly(_ d: PadDrone, dt: Double) {
        guard dt > 0 else { return }
        let before = d.vel
        if let target = d.route.first {
            let to = target - d.pos
            let dist = simd_length(to)
            let last = d.route.count == 1
            if dist < (last ? 0.015 : 0.1), !last || simd_length(d.vel) < 0.12 {
                d.route.removeFirst()
                if last { d.pos = target; d.vel = .zero }
            } else {
                let speed = min(DroneFlight.speed, (2 * DroneFlight.accel * dist).squareRoot() + (last ? 0 : 0.5))
                let want = to / max(dist, 1e-6) * speed
                let dv = want - d.vel, most = DroneFlight.accel * 1.6 * dt
                d.vel += simd_length(dv) > most ? dv / simd_length(dv) * most : dv
                d.pos += d.vel * dt
            }
        } else {
            d.vel *= max(0, 1 - dt * 8)
        }
        d.push = (d.vel - before) / dt
        let ground = SIMD2(d.vel.x, d.vel.z)
        let landing = (d.task == .home && d.route.count <= 1) || d.task == .rest
        if landing || simd_length(ground) > 0.2 {
            let want = landing ? d.berthYaw : atan2(ground.x, ground.y)
            d.yaw += atan2(sin(want - d.yaw), cos(want - d.yaw)) * min(1, dt * 5)
        }
    }

    // MARK: working

    private func goHome(_ d: PadDrone, station: Station) {
        d.task = .home
        d.torch = false
        d.weldSide = nil
        d.route = plan(d, to: berth(station, d.berth), station: station)
    }

    private func work(_ d: PadDrone, station: Station) {
        switch d.task {
        case .rest:
            break
        case .home:
            if d.route.isEmpty { d.task = .rest }
        case .weld(let key):
            guard let r = rockets[key], r.welding, let at = rocketSpot(station: station, key: r.key) else { goHome(d, station: station); return }
            weld(d, r, at: at, station: station)
        case .vortex(let key, let slot):
            guard let v = vortices[key], v.closedAt == nil, let hatch = vortexHatch(v) else { goHome(d, station: station); return }
            let place = Vortex.ringPoint(ring: v.ring, hatch: hatch, slot: slot, at: clock)
            if d.route.count > 1 { return }
            if simd_distance(d.pos, place) > 0.6 { d.route = plan(d, to: place, station: station); return }
            d.route = [place]
        }
    }

    private func weld(_ d: PadDrone, _ r: RocketJob, at spot: SIMD2<Double>, station: Station) {
        guard r.kick == .docked || r.kick == .none else {
            d.torch = false
            if d.route.isEmpty, d.pos.y < DroneFlight.low { d.route = [SIMD3(d.pos.x, DroneFlight.low, d.pos.z)] }
            d.weldSide = nil
            return
        }
        let panel = min(RocketGeometry.panels - 1, Int(r.welded))
        let ring = panel / 6, k = panel % 6
        let side = k
        let height = RocketGeometry.ringMiddle(ring, offset: r.tipOffset)
        func point(_ s: Int) -> SIMD3<Double> {
            let f = RocketGeometry.facing(side: s) * (RocketGeometry.apothem(at: RocketGeometry.ringMiddle(ring)) + DroneFlight.standOff)
            return SIMD3(station.offset.x + spot.x + f.x, height, station.offset.y + spot.y + f.y)
        }
        let face = RocketGeometry.facing(side: side)
        if d.weldSide == nil {
            d.weldSide = side
            d.route = plan(d, to: point(side), station: station)
            d.torch = false
            return
        }
        if d.weldSide != side || (d.route.isEmpty && simd_distance(d.pos, point(side)) > 0.03) {
            let from = d.weldSide ?? side
            let step = side > from ? 1 : -1
            d.route = stride(from: from + step, through: side, by: step).map(point)
            if d.route.isEmpty { d.route = [point(side)] }
            d.weldSide = side
            d.torch = false
            return
        }
        guard d.route.isEmpty else { return }
        d.yaw = atan2(-face.x, -face.y)
        d.torch = true
        r.seam = ring * 6 + k
    }
}
