// The drones outside the hull: the machines that work the pad, where no minion goes. They stand for what the
// machines do on their own, the builds and the deploys. A drone takes a crate off the cargo lock's outer tray
// and flies it to its stack by the rocket or into the rocket's hatch; it brings a crate bound indoors back to
// the lock; it welds a tip while its staging deploy runs, circling the hull ring by ring as the weld climbs; and
// two of them fly a kick stage in under a tip when a production release opens, and out again if it closes.
// Between jobs the drones wait in their rack by the lock. They fly on puffs of thrust: up off the pad, across,
// down onto the work, over the rockets when those are in the way. No SceneKit: the scene
// draws them where this has them, on the station clock.

import Foundation
import simd

/// One drone: where it is, how it is moving, and what it is doing.
final class PadDrone {
    let id: String
    let station: String
    /// Its place in the rack, which also lifts its cruise a little so two crossing never meet.
    let berth: Int
    /// Where it is, in world coordinates, and how fast it is going.
    var pos: SIMD3<Double>
    var vel = SIMD3<Double>(repeating: 0)
    /// What its thrusters pushed it by last frame: the scene puffs gas the other way.
    var push = SIMD3<Double>(repeating: 0)
    /// Which way its nose points, on the floor plan.
    var yaw = 0.0
    var task = Task.rest
    /// Where it is flying, in order; empty once it is there.
    var route: [SIMD3<Double>] = []
    /// The crate in its grip.
    var holding: CrateRef?
    /// The end of a timed step: the claws closing on a crate or letting it go.
    var until = 0.0
    /// At a seam with the torch lit.
    var torch = false
    /// The side of a hull it is welding at, for the way round to the next.
    var weldSide: Int?

    enum Task: Equatable {
        /// In the rack.
        case rest
        /// Flying to a crate, closing its claws on it, flying it to its place, letting it go: by carry id.
        case fetch(Int), grab(Int), deliver(Int), release(Int)
        /// Welding a rocket's tip, by "station|repo".
        case weld(String)
        /// One of the two carrying a rocket's kick stage, by "station|repo", on its side of it.
        case ferry(String, Int)
        /// On its way back to the rack.
        case home
    }

    init(id: String, station: String, berth: Int, at pos: SIMD3<Double>) {
        self.id = id; self.station = station; self.berth = berth; self.pos = pos
    }

    var isFree: Bool { task == .rest || task == .home }
    /// The carry it is on, if any.
    var carry: Int? {
        switch task {
        case .fetch(let id), .grab(let id), .deliver(let id), .release(let id): return id
        default: return nil
        }
    }
}

/// How the drones fly.
enum DroneFlight {
    /// How many work a pad.
    static let count = 3
    /// Top speed and how hard the thrusters push, in tiles.
    static let speed = 1.3, accel = 2.0
    /// The height they cross the pad at: low, or over the rockets.
    static let low = 0.85, high = 2.3
    /// How far below the drone's middle a crate in its grip hangs: its top just under the claws.
    static let hang = 0.07
    /// How long the claws take to close on a crate or let it go.
    static let gripSeconds = 0.45
    /// How far off a hull it welds, from the side's middle out to its own.
    static let standOff = 0.19
    /// How far apart the berths are along the rack.
    static let berthPitch = 0.3
    /// How long two drones take to carry a kick stage in from out past the pad, or back out.
    static let ferrySeconds = 9.0
    /// How far out from the stage's middle each of the two holds it.
    static let ferrySpread = RocketGeometry.radius + 0.13
}

extension Simulation {
    /// A station's drones, made the first time its pad needs them: none without a lock to work.
    func padDrones(_ station: Station) -> [PadDrone] {
        if let d = drones[station.name] { return d }
        guard station.lock != nil, !station.padCells.isEmpty else { return [] }
        let made = (0..<DroneFlight.count).map { k in
            PadDrone(id: "drone:\(station.name)#\(k)", station: station.name, berth: k, at: berth(station, k))
        }
        drones[station.name] = made
        return made
    }

    /// The rack the drones wait in: on the pad beside the lock, its berths in a row along the gate.
    func rack(_ station: Station) -> (at: SIMD2<Double>, along: SIMD2<Double>)? {
        guard let lock = station.lock else { return nil }
        let along = SIMD2(-lock.inward.y, lock.inward.x)
        if let c = station.droneRackCell { return (SIMD2(Double(c.x), Double(c.y)), along) }
        // No pad floor beside the gate: out past the lock's tray.
        let outer = SIMD2(lock.outer.x - station.offset.x, lock.outer.z - station.offset.y)
        return (outer + lock.inward * 0.9, along)
    }

    /// A drone's berth in the rack, in world coordinates: sat on its cradle.
    func berth(_ station: Station, _ k: Int) -> SIMD3<Double> {
        guard let r = rack(station) else { return SIMD3(station.offset.x, 0.2, station.offset.y) }
        let p = r.at + r.along * (Double(k) - Double(DroneFlight.count - 1) / 2) * DroneFlight.berthPitch
        return SIMD3(station.offset.x + p.x, 0.2, station.offset.y + p.y)
    }

    /// The drone holding a crate, if a drone has it.
    func drone(holding crate: CrateRef) -> PadDrone? {
        drones[crate.station]?.first { $0.holding == crate }
    }

    /// One frame of every station's drones: free ones take what wants doing, then each flies and works.
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

    /// A tip being welded gets a drone, then every carry outside goes to the free drone nearest its crate.
    private func assignDrones(_ station: Station, _ fleet: [PadDrone]) {
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
        let open = cargo.filter { _, job in
            job.byDrone && !job.inLock && job.carrier == nil && job.command.crate?.station == station.name
                && job.command.after.allSatisfy { cargo[$0] == nil }
        }.sorted { $0.value.postedAt != $1.value.postedAt ? $0.value.postedAt < $1.value.postedAt : $0.key < $1.key }
        for (id, job) in open {
            guard case .carry(_, let from, _) = job.command.kind, let d = nearest(to: from.pos) else { break }
            cargo[id]?.carrier = d.id
            d.task = .fetch(id)
            d.route = plan(d, to: pickup(from), station: station)
        }
    }

    // MARK: flying

    /// Straight there if it is close; otherwise up to its cruise, across, and down. It crosses high where a
    /// rocket stands in the way, low where nothing does.
    private func plan(_ d: PadDrone, to: SIMD3<Double>, station: Station) -> [SIMD3<Double>] {
        let from = d.pos
        let flat = SIMD2(to.x - from.x, to.z - from.z)
        if simd_length(flat) < 0.35 { return [to] }
        let cruise = (crossesRocket(from, to, station: station) ? DroneFlight.high : DroneFlight.low) + Double(d.berth) * 0.08
        let up = max(cruise, from.y, to.y)
        return [SIMD3(from.x, up, from.z), SIMD3(to.x, up, to.z), to]
    }

    /// Whether the way across the pad from one point to another passes a standing rocket.
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

    /// A step along the route: thrust toward the next point, easing in on the last so it stops on it, and a
    /// turn of the nose the way it is going.
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

    /// Where a drone hovers to take a crate: its claws on the crate's top.
    private func pickup(_ spot: Spot) -> SIMD3<Double> {
        spot.pos + SIMD3(0, crateHeight(at: spot) + DroneFlight.hang, 0)
    }

    /// A crate's height where it stands: packed small outside, full size on the lock's inner tray.
    private func crateHeight(at spot: Spot) -> Double {
        let full = 0.38 * 0.8
        guard let station = fleet.stations[spot.station] else { return full }
        return station.isOutside(spot) ? full * Station.testedScale : full
    }

    /// Where a drone takes the crate in its grip, and what it does with it there: into a rocket's hatch, onto
    /// its place outside, or onto the lock's outer tray to go back in.
    private func dropPoint(_ job: Cargo, station: Station) -> (at: SIMD3<Double>, inward: Bool, hatch: Bool) {
        let small = 0.38 * 0.8 * Station.testedScale
        let aim = job.aim
        if aim.area == .pad, let r = rockets[station.name + "|" + aim.owner], let at = rocketSpot(station: station, repo: aim.owner) {
            // Held in front of the hatch, the crate's middle at the door's.
            let h = RocketGeometry.hatch(lift: r.lift)
            let door = SIMD3(station.offset.x + at.x + h.x + small * 0.5 + 0.02, h.y, station.offset.y + at.y + h.z)
            return (door + SIMD3(0, small * 0.5 + DroneFlight.hang, 0), false, true)
        }
        if !station.isOutside(aim), let lock = station.lock {
            let tray = lockEnd(station, lock, outer: true, crate: job.command.crate!)
            return (tray.pos + SIMD3(0, small + DroneFlight.hang, 0), true, false)
        }
        return (aim.pos + SIMD3(0, small + DroneFlight.hang, 0), false, false)
    }

    private func goHome(_ d: PadDrone, station: Station) {
        d.task = .home
        d.torch = false
        d.weldSide = nil
        d.route = plan(d, to: berth(station, d.berth), station: station)
    }

    /// What a drone does once it is where its route ends, or while it waits on its job.
    private func work(_ d: PadDrone, station: Station) {
        switch d.task {
        case .rest:
            break
        case .home:
            if d.route.isEmpty { d.task = .rest }
        case .fetch(let id):
            guard let job = cargo[id], job.carrier == d.id, case .carry(_, let from, _) = job.command.kind else { goHome(d, station: station); return }
            guard d.route.isEmpty else { return }
            if simd_distance(d.pos, pickup(from)) > 0.05 { d.route = plan(d, to: pickup(from), station: station); return }
            d.task = .grab(id)
            d.until = clock + DroneFlight.gripSeconds
        case .grab(let id):
            guard let job = cargo[id], job.carrier == d.id, let crate = job.command.crate else { goHome(d, station: station); return }
            guard clock >= d.until else { return }
            world.pickedUp(crate, by: d.id)
            d.holding = crate
            reaim(id)
            d.task = .deliver(id)
            if let job = cargo[id] { d.route = plan(d, to: dropPoint(job, station: station).at, station: station) }
        case .deliver(let id):
            guard let job = cargo[id], job.carrier == d.id else { dropHeld(d, station: station); goHome(d, station: station); return }
            // The place may move while it flies, a stack grown or the order sent back: it follows.
            let drop = dropPoint(job, station: station)
            if let end = d.route.last, simd_distance(end, drop.at) > 0.02 { d.route = plan(d, to: drop.at, station: station); return }
            guard d.route.isEmpty else { return }
            d.task = .release(id)
            d.until = clock + DroneFlight.gripSeconds
        case .release(let id):
            guard let job = cargo[id], job.carrier == d.id, let crate = job.command.crate else { dropHeld(d, station: station); goHome(d, station: station); return }
            guard clock >= d.until else { return }
            let drop = dropPoint(job, station: station)
            d.holding = nil
            if drop.inward, let lock = station.lock {
                // On the outer tray for the lock to take in. Indoors it is the same order, a hand's from the inner tray.
                world.setDown(crate, at: lockEnd(station, lock, outer: true, crate: crate))
                lockReturned(crate)
                cargo[id]?.command = job.command.from(lockEnd(station, lock, outer: false, crate: crate))
                cargo[id]?.carrier = nil
                cargo[id]?.inLock = true
                cargo[id]?.byDrone = false
                cargo[id]?.pastLock = false
            } else {
                world.setDown(crate, at: job.aim)
                cargo[id] = nil
                cue(.landed(job))
            }
            goHome(d, station: station)
        case .weld(let key):
            guard let r = rockets[key], r.welding, let at = rocketSpot(station: station, repo: r.repo) else { goHome(d, station: station); return }
            weld(d, r, at: at, station: station)
        case .ferry(let key, _):
            // The stage is the rocket's to say where it is (`stepKicks`); a ferry whose rocket has gone goes home.
            if rockets[key].map({ $0.kick == .coming || $0.kick == .going }) != true { goHome(d, station: station) }
        }
    }

    /// The carry it held went away while the crate was in its grip: the crate goes down where the order now
    /// says, or onto the pad under it.
    private func dropHeld(_ d: PadDrone, station: Station) {
        guard let crate = d.holding else { return }
        d.holding = nil
        let cell = Cell(x: Int((d.pos.x - station.offset.x).rounded()), y: Int((d.pos.z - station.offset.y).rounded()))
        world.setDown(crate, at: Spot(area: .pad, station: station.name, owner: crate.repo, label: crate.repo, cell: cell,
                                      pos: SIMD3(d.pos.x, 0, d.pos.z)))
        cue(.redraw)
    }

    /// At a tip with the torch: in front of the panel the weld is on, ring by ring up the hull. The way from side
    /// to side goes round the hull, past each side between.
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
            // Arriving: from wherever it is, onto the side.
            d.weldSide = side
            d.route = plan(d, to: point(side), station: station)
            d.torch = false
            return
        }
        if d.weldSide != side || (d.route.isEmpty && simd_distance(d.pos, point(side)) > 0.03) {
            // Round the hull to the next side, past each side between, or up to the next ring.
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

    /// Where kick stages are fetched from and taken back to: out past the pad's far edge, away from the deck, high.
    func kickDepot(_ station: Station) -> SIMD3<Double> {
        let pad = station.padCenter
        let deck = station.deckCells.isEmpty ? pad - SIMD2(0, -1) : SIMD2(Double(station.deckCells.map(\.x).reduce(0, +)) / Double(station.deckCells.count),
                                                                      Double(station.deckCells.map(\.y).reduce(0, +)) / Double(station.deckCells.count))
        var out = pad - deck
        out /= max(1e-6, simd_length(out))
        let p = pad + out * 6
        return SIMD3(station.offset.x + p.x, 2.6, station.offset.y + p.y)
    }

    /// The way a kick stage comes in under its tip: from the side with the most room round it, clear of the other
    /// rockets.
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
                // Nearest the stage comes to it on the way in, from out there to under the tip.
                let ab = spot - p, t = max(0, min(1, simd_dot(o - p, ab) / simd_dot(ab, ab)))
                return simd_distance(p + ab * t, o)
            }.min() ?? 9
        }
        return ways.max { room($0) < room($1) } ?? ways[0]
    }

    /// The way a kick stage's foot goes, from the depot to under its tip: across high over the pad, down beside the
    /// rocket on the side with room, and in under the tip low and level.
    private func kickPath(_ station: Station, at spot: SIMD2<Double>, from way: SIMD2<Double>) -> [SIMD3<Double>] {
        let under = SIMD3(station.offset.x + spot.x, 0, station.offset.y + spot.y)
        let beside = under + SIMD3(way.x, 0.02, way.y)
        return [kickDepot(station), beside + SIMD3(0, 2.4, 0), beside + SIMD3(0, 0.6, 0), beside, under]
    }

    /// Where each of the two holds the stage, its foot at `foot`: either side of it, square to the way it comes
    /// in, at its middle.
    private func grip(_ foot: SIMD3<Double>, role: Int, way: SIMD2<Double>) -> SIMD3<Double> {
        let across = SIMD2(-way.y, way.x) / max(1e-6, simd_length(way))
        let s = (role == 0 ? -1.0 : 1.0) * DroneFlight.ferrySpread
        return foot + SIMD3(across.x * s, RocketGeometry.kickGrip, across.y * s)
    }

    /// Each rocket's kick stage. A release that opens for production calls two free drones out to the depot; once
    /// both hold the stage they fly it in, the cradle raising the tip as it comes, and set it under the tip. A
    /// release that closes again before it lit has them take it back out, and the tip settles on its cradle. A
    /// rocket that lights has its stage, whatever was under way.
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
                    // A drone taken off it: the stage goes back where it was, and is asked for again.
                    for d in ferrying { goHome(d, station: station) }
                    r.kick = inbound ? .none : .docked
                    r.kickAt = nil
                    r.kickWay = nil
                    continue
                }
                if r.kickSince < 0 {
                    // Gathering round it: both there and still, and the carry starts.
                    guard ferrying.allSatisfy({ $0.route.isEmpty }) else { continue }
                    r.kickSince = clock
                }
                let t = min(1, (clock - r.kickSince) / DroneFlight.ferrySeconds)
                let along = inbound ? ease(t) : 1 - ease(t)
                let foot = FlightLeg.sample(path, along)
                r.kickAt = foot
                // The tip goes up on its cradle before the stage comes under it, and down once it has gone.
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
