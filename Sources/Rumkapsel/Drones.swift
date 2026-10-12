import Foundation
import simd

final class PadDrone {
    let id: String
    let station: String
    let berth: Int
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
        case ferry(String, Int)
        case vortex(String, Int)
        case home
    }

    init(id: String, station: String, berth: Int, at pos: SIMD3<Double>) {
        self.id = id; self.station = station; self.berth = berth; self.pos = pos
    }

    var isFree: Bool { task == .rest || task == .home }
}

enum DroneFlight {
    static let count = 3
    static let speed = 1.3, accel = 2.0
    static let low = 0.85, high = 2.3
    static let standOff = 0.19
    static let berthPitch = 0.3
    static let ferrySeconds = 9.0
    static let ferrySpread = RocketGeometry.radius + 0.13
}

extension Simulation {
    func padDrones(_ station: Station) -> [PadDrone] {
        if let d = drones[station.name] { return d }
        guard !station.padCells.isEmpty, station.droneRackCell != nil else { return [] }
        let made = (0..<DroneFlight.count).map { k in
            PadDrone(id: "drone:\(station.name)#\(k)", station: station.name, berth: k, at: berth(station, k))
        }
        drones[station.name] = made
        return made
    }

    func rack(_ station: Station) -> (at: SIMD2<Double>, along: SIMD2<Double>)? {
        guard let c = station.droneRackCell else { return nil }
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
            stepKicks(station, fleet)
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
                  let at = rocketSpot(station: station, repo: r.repo),
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
            guard r.station == station.name, let at = rocketSpot(station: station, repo: r.repo) else { return false }
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
        if simd_length(ground) > 0.2 {
            let want = atan2(ground.x, ground.y)
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
            guard let r = rockets[key], r.welding, let at = rocketSpot(station: station, repo: r.repo) else { goHome(d, station: station); return }
            weld(d, r, at: at, station: station)
        case .ferry(let key, _):
            if rockets[key].map({ $0.kick == .coming || $0.kick == .going }) != true { goHome(d, station: station) }
        case .vortex(let key, let slot):
            guard let v = vortices[key], v.closedAt == nil, let hatch = vortexHatch(v) else { goHome(d, station: station); return }
            let place = Vortex.ringPoint(ring: v.ring, hatch: hatch, slot: slot, at: clock)
            if d.route.count > 1 { return }
            if simd_distance(d.pos, place) > 0.6 { d.route = plan(d, to: place, station: station); return }
            d.route = [place]
        }
    }

    private func weld(_ d: PadDrone, _ r: RocketJob, at spot: SIMD2<Double>, station: Station) {
        let panel = min(RocketGeometry.panels - 1, Int(r.welded))
        let ring = panel / 6, k = panel % 6
        let side = k
        let height = RocketGeometry.ringMiddle(ring, lift: r.lift)
        func point(_ s: Int) -> SIMD3<Double> {
            let f = RocketGeometry.facing(side: s) * (RocketGeometry.apothem + DroneFlight.standOff)
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

    // MARK: the kick stage

    func kickDepot(_ station: Station) -> SIMD3<Double> {
        let pad = station.padCenter
        let deck = station.deckCells.isEmpty ? pad - SIMD2(0, -1) : SIMD2(Double(station.deckCells.map(\.x).reduce(0, +)) / Double(station.deckCells.count),
                                                                      Double(station.deckCells.map(\.y).reduce(0, +)) / Double(station.deckCells.count))
        var out = pad - deck
        out /= max(1e-6, simd_length(out))
        let p = pad + out * 6
        return SIMD3(station.offset.x + p.x, 2.6, station.offset.y + p.y)
    }

    private func kickSide(_ station: Station, at spot: SIMD2<Double>, key: String) -> SIMD2<Double> {
        var others: [SIMD2<Double>] = []
        for r in rockets.values where r.station == station.name && r.key != key {
            if let at = rocketSpot(station: station, repo: r.repo) { others.append(at) }
        }
        let pad = Set(station.padCells)
        let ways = [SIMD2(-1.0, 0), SIMD2(0, 1), SIMD2(0, -1), SIMD2(-0.7, 0.7), SIMD2(-0.7, -0.7)]
        func room(_ w: SIMD2<Double>) -> Double {
            let p = spot + w * 1.0
            guard pad.contains(Cell(x: Int(p.x.rounded()), y: Int(p.y.rounded()))) else { return -1 }
            return others.map { o -> Double in
                let ab = spot - p, t = max(0, min(1, simd_dot(o - p, ab) / simd_dot(ab, ab)))
                return simd_distance(p + ab * t, o)
            }.min() ?? 9
        }
        return ways.max { room($0) < room($1) } ?? ways[0]
    }

    private func kickPath(_ station: Station, at spot: SIMD2<Double>, from way: SIMD2<Double>) -> [SIMD3<Double>] {
        let under = SIMD3(station.offset.x + spot.x, 0, station.offset.y + spot.y)
        let beside = under + SIMD3(way.x, 0.02, way.y)
        return [kickDepot(station), beside + SIMD3(0, 2.4, 0), beside + SIMD3(0, 0.6, 0), beside, under]
    }

    private func grip(_ foot: SIMD3<Double>, role: Int, way: SIMD2<Double>) -> SIMD3<Double> {
        let across = SIMD2(-way.y, way.x) / max(1e-6, simd_length(way))
        let s = (role == 0 ? -1.0 : 1.0) * DroneFlight.ferrySpread
        return foot + SIMD3(across.x * s, RocketGeometry.kickGrip, across.y * s)
    }

    private func stepKicks(_ station: Station, _ fleet: [PadDrone]) {
        func ease(_ t: Double) -> Double { let k = min(1, max(0, t)); return k * k * (3 - 2 * k) }
        for r in rockets.values where r.station == station.name {
            let key = r.key
            let ferrying = fleet.filter { if case .ferry(let k, _) = $0.task { return k == key }; return false }
            guard let spot = rocketSpot(station: station, repo: r.repo) else { continue }
            if r.stage.rank >= 3 {
                if r.kick != .docked { r.kick = .docked; r.kickAt = nil; r.lift = 1 }
                for d in ferrying { goHome(d, station: station) }
                continue
            }
            let way = r.kickWay ?? kickSide(station, at: spot, key: key)
            let path = kickPath(station, at: spot, from: way)
            switch r.kick {
            case .none:
                guard r.tall else { r.lift = max(0, r.lift - 0.02); continue }
                let free = fleet.filter(\.isFree).sorted { simd_distance($0.pos, path[0]) < simd_distance($1.pos, path[0]) }
                guard free.count >= 2 else { continue }
                r.kick = .coming
                r.kickSince = -1
                r.kickAt = path[0]
                r.kickWay = way
                for (role, d) in free.prefix(2).enumerated() {
                    d.task = .ferry(key, role)
                    d.route = plan(d, to: grip(path[0], role: role, way: way), station: station)
                }
            case .docked:
                r.lift = 1
                guard !r.tall else { continue }
                let free = fleet.filter(\.isFree).sorted { simd_distance($0.pos, path.last!) < simd_distance($1.pos, path.last!) }
                guard free.count >= 2 else { continue }
                r.kick = .going
                r.kickSince = -1
                r.kickAt = path.last!
                r.kickWay = way
                for (role, d) in free.prefix(2).enumerated() {
                    d.task = .ferry(key, role)
                    d.route = plan(d, to: grip(path.last!, role: role, way: way), station: station)
                }
            case .coming, .going:
                let inbound = r.kick == .coming
                if ferrying.count < 2 {
                    for d in ferrying { goHome(d, station: station) }
                    r.kick = inbound ? .none : .docked
                    r.kickAt = nil
                    r.kickWay = nil
                    continue
                }
                if r.kickSince < 0 {
                    guard ferrying.allSatisfy({ $0.route.isEmpty }) else { continue }
                    r.kickSince = clock
                }
                let t = min(1, (clock - r.kickSince) / DroneFlight.ferrySeconds)
                let along = inbound ? ease(t) : 1 - ease(t)
                let foot = FlightLeg.sample(path, along)
                r.kickAt = foot
                r.lift = inbound ? ease(t / 0.55) : 1 - ease((t - 0.35) / 0.4)
                for d in ferrying {
                    guard case .ferry(_, let role) = d.task else { continue }
                    let want = grip(foot, role: role, way: way)
                    d.push = (want - d.pos) / max(1e-3, 1.0 / 30) * 0.2
                    d.vel = .zero
                    d.pos = want
                    let toStage = SIMD2(foot.x - want.x, foot.z - want.z)
                    d.yaw = atan2(toStage.x, toStage.y)
                }
                guard t >= 1 else { continue }
                r.kick = inbound ? .docked : .none
                r.kickAt = nil
                r.kickWay = nil
                r.lift = inbound ? 1 : 0
                for d in ferrying { goHome(d, station: station) }
            }
        }
    }
}
