// The staging pallet as the simulation runs it: ordered at the console, loaded by wand one crate at
// a time, pushed across to the deck leg by leg, unloaded. Its state is station truth's; what is on
// its way, in the air or being shoved, is the `PalletJob` here. No SceneKit: the scene draws the
// slab, the shadow, the light, the pusher's lean and the flying crate from these facts.

import Foundation

/// The hover pallet's shape, as numbers: the slab's size, how high it hovers, and where its crate
/// slots are on the top plate.
enum PalletGeometry {
    /// Four crates across, two deep, stacked two high. The depth is what matters: a yard's crate rows
    /// have a single cell of aisle between them, and a pallet three crates deep cannot float in one
    /// without standing in the stacks on either side.
    static let rows = 2, columns = 4, levels = 2, spacing = 0.42
    static var capacity: Int { rows * columns * levels }
    static let width = 1.8, depth = 0.92, lift = 0.12
    /// The slot an index counts to, filling a level before starting the next.
    static func slot(_ index: Int) -> (row: Int, column: Int, level: Int) {
        let onLevel = index % (rows * columns)
        return (row: onLevel / columns, column: onLevel % columns, level: index / (rows * columns))
    }
    /// That slot's place on the pallet's own top plate.
    static func offset(row: Int, column: Int, level: Int) -> SIMD3<Double> {
        SIMD3((Double(column) - Double(columns - 1) / 2) * spacing,
              0.025 + Double(level) * 0.34,
              (Double(row) - Double(rows - 1) / 2) * spacing)
    }
}

/// One pallet out on a station, and its errand as it stands.
final class PalletJob {
    let station: String
    let repo: String
    let number: Int
    /// Which body is running the errand.
    var dispatcher: String
    /// Where it hovers, in the station's own coordinates.
    var spot: SIMD2<Double>
    /// The way to the deck, leg by leg: each one an axis-aligned target for the pallet's centre.
    var route: [SIMD2<Double>] = []
    /// The leg in hand: where it started and when the pushing began, for the ease-in.
    var legFrom = SIMD2<Double>(0, 0)
    var legAt = 0.0
    /// True while hands are actually on it and it is creeping along a leg.
    var pushing = false
    /// How far off the middle of its back edge the pusher has its hands, across the way it is going.
    /// Nought where the floor behind it is clear, which the lane through storage is there to keep it.
    var pushAcross = 0.0
    /// Crates still to lift, top of each stack first, where each stands and where it goes.
    var toLoad: [(crate: CrateRef, from: Spot, slot: StationTruth.PalletSlot)] = []
    /// What stands on it now, in the order it was loaded.
    var aboard: [CrateRef] = []
    /// The crate in the air right now, if any. One at a time.
    var flight: Flight?
    /// When the pallet came out, so its fade-in rides the station's own clock.
    var bornAt = 0.0
    /// The clock the next crate leaves the ground.
    var nextAt = 0.0
    /// Asked for while it was still loading: push it out, or empty it back into storage.
    var wantsPush = false
    var wantsBack = false

    /// A crate on its way through the air, in world coordinates, on the station clock: onto the
    /// pallet, or off it onto a slot in a yard.
    struct Flight {
        let crate: CrateRef
        let from: SIMD3<Double>, to: SIMD3<Double>
        let fromYaw: Double, toYaw: Double
        let at: Double
        let seconds: Double
        /// Landing on the pallet; otherwise on `slot`, in `yard`.
        let slot: Spot?
        let yard: Yard?
        var aboard: Bool { slot == nil }
        /// Where it is at a moment: the eased line, with a hop up in the middle.
        func position(at clock: Double) -> (pos: SIMD3<Double>, yaw: Double, done: Bool) {
            let t = min(1, (clock - at) / seconds)
            let e = t * t * (3 - 2 * t)
            let p = from + (to - from) * e
            let turn = atan2(sin(toYaw - fromYaw), cos(toYaw - fromYaw))
            return (SIMD3(p.x, p.y + sin(t * .pi) * 0.7, p.z), fromYaw + turn * e, t >= 1)
        }
    }

    init(station: String, repo: String, number: Int, dispatcher: String, spot: SIMD2<Double>) {
        self.station = station; self.repo = repo; self.number = number; self.dispatcher = dispatcher; self.spot = spot
    }

    var isEmpty: Bool { aboard.isEmpty && toLoad.isEmpty && flight == nil }
    var isSettled: Bool { toLoad.isEmpty && flight == nil }
    /// The cell the pallet hovers over right now.
    var cellUnder: Cell { Cell(x: Int(spot.x.rounded()), y: Int(spot.y.rounded())) }
}

extension Simulation {
    /// The pallet errand a body is on, if any: which station's pallet and whose crates.
    func palletErrand(of m: B?) -> (station: String, repo: String)? {
        switch m?.current?.kind {
        case .dispatch(let s, let r, _): return (s, r)
        case .loadPallet(let s, let r), .waitPallet(let s, let r), .pushPallet(let s, let r): return (s, r)
        case .unloadPallet(let s, let r, _): return (s, r)
        default: return nil
        }
    }

    // MARK: ordering

    /// A staging release opened: a pallet is ordered for that repository's crates.
    func orderPallet(station: Station, repo: String, number: Int) {
        world.truth.queuePallet(station: station.name, repo: repo, number: number)
        onLog("\(repo): staging release #\(number) open, a pallet is ordered")
        servicePallets()
    }

    /// Sends a free body to the storage console for anything still queued. One at a time per station.
    func servicePallets() {
        for station in fleet.stations.values where station.hasPad && !station.storageCells.isEmpty {
            for want in world.truth.palletQueue[station.name] ?? [] {
                // Someone is already on this errand: leave them to it.
                if bodies.values.contains(where: { palletErrand(of: $0)?.station == station.name && palletErrand(of: $0)?.repo == want.repo }) { continue }
                let console = station.storageConsole.cell
                // Free: no job, nothing on the arms, and not in the middle of a visit that lasts its whole time.
                let free = bodies.values.filter {
                    $0.station == station.name && !$0.onJob && !$0.hasLoad && !$0.isSubagent && !$0.bathing && !$0.exercising
                        && !$0.isCrew && !$0.isQA && $0.state != .leaving && $0.wakeUntil == 0
                }
                guard let m = free.min(by: { abs($0.cell.x - console.x) + abs($0.cell.y - console.y) < abs($1.cell.x - console.x) + abs($1.cell.y - console.y) }) else { break }
                m.couch = nil
                m.bed = nil
                start(m, .dispatch(station: station.name, repo: want.repo, number: want.number), announce: true)
                // Only a body whose order began walks: one that kept something else in hand is left to it.
                guard case .dispatch = m.current?.kind else { continue }
                m.place = .room("kind:storage")
                walk(m, to: console)
            }
        }
    }

    /// A crate reached storage while its repository's pallet was already out there. Rather than leave
    /// it behind on the rows, the wand comes out again and takes it aboard too: one still loading
    /// simply gains a slot, and one standing loaded goes back to loading for the one extra lift.
    @discardableResult
    func palletLatecomer(station: Station, repo: String, number: Int) -> Bool {
        guard let p = pallets[station.name], p.repo == repo, !p.wantsBack else { return false }
        let state = world.truth.pallets[station.name]?.state ?? .arriving
        guard state == .loading || state == .loaded else { return false }   // moving or unloading: too late
        let taken = (world.truth.pallets[station.name]?.crates.count ?? 0) + p.toLoad.count
        guard taken < PalletGeometry.capacity else { return false }
        let crate = CrateRef(station: station.name, repo: repo, number: number)
        guard let from = world.storageSpot(station: station, crate: crate) else { return false }
        let s = PalletGeometry.slot(taken)
        p.toLoad.append((crate, from, StationTruth.PalletSlot(row: s.row, column: s.column, level: s.level)))
        if state == .loaded {
            world.truth.setPallet(station: station.name, state: .loading)
            p.nextAt = clock + 0.8
            if let m = bodies[p.dispatcher], case .waitPallet = m.current?.kind {
                handOver(m, .loadPallet(station: station.name, repo: repo), announce: true)
            }
        }
        onLog("\(repo): #\(number) lands in time, it goes on the pallet too")
        return true
    }

    /// A staging release merged: the loaded pallet goes to the deck. One still loading finishes first,
    /// and one not out yet is told the moment it appears.
    func palletMerged(station: Station, repo: String) { wish(station: station, repo: repo, push: true) }

    /// A staging release closed unmerged: the crates go back where they came from.
    func palletClosed(station: Station, repo: String) { wish(station: station, repo: repo, push: false) }

    private func wish(station: Station, repo: String, push: Bool) {
        if let p = pallets[station.name], p.repo == repo {
            p.wantsPush = push
            p.wantsBack = !push
            return
        }
        palletWishes[station.name + "|" + repo] = push
    }

    // MARK: the dispatcher's phases

    /// One frame of a pallet command, once the body has stopped walking. Nil when the command in hand
    /// is not a pallet errand.
    func stepPallet(_ m: B, station: Station, dt: Double) -> Outcome? {
        guard let c = m.current else { return nil }
        switch c.kind {
        case .dispatch(_, let repo, let number):
            guard m.phaseKind != .walk else { advance(m); return .spent }
            faceConsole(m, station)
            if world.truth.nextPallet(station: station.name)?.repo == repo {
                beginPallet(m, station: station, repo: repo, number: number)
            } else {
                // A pallet already out, or someone ahead in the queue: wait here and fidget.
                handOver(m, .waitPallet(station: station.name, repo: repo, words: "waiting for a pallet"))
            }
        case .waitPallet(_, let repo):
            guard m.phaseKind != .walk else { advance(m); return .spent }
            m.waitingOn = m.current?.words   // standing by is the errand: the release, or a pallet, is what it waits on
            if let p = pallets[station.name], p.repo == repo {
                // Beside a loaded pallet, waiting for the release to go one way or the other.
                if p.wantsBack { beginUnload(m, station: station, p, back: true) }
                else if p.wantsPush { beginPush(m, station: station, p) }
                return .spent
            }
            faceConsole(m, station)
            impatient(m, station: station)
            if let want = world.truth.nextPallet(station: station.name), want.repo == repo {
                beginPallet(m, station: station, repo: want.repo, number: want.number)
            }
        case .loadPallet(_, let repo):
            guard m.phaseKind != .walk else { advance(m); return .spent }
            guard let p = pallets[station.name], p.repo == repo else { finish(m); return .spent }
            guard p.isSettled else { m.waitingOn = "the pallet to settle"; return .spent }
            world.truth.setPallet(station: station.name, state: .loaded)
            if p.wantsBack { beginUnload(m, station: station, p, back: true) }
            else if p.wantsPush { beginPush(m, station: station, p) }
            else { handOver(m, .waitPallet(station: station.name, repo: repo, words: "waiting for the release to merge")) }
        case .pushPallet(_, let repo):
            guard let p = pallets[station.name], p.repo == repo else { finish(m); return .spent }
            switch m.phaseKind {
            case .walk:
                advance(m)
            case .approach:
                // Round the back of the pallet for this leg: squarely behind it, facing the way it goes.
                guard let leg = p.route.first else { arrive(m, station: station, p); return .spent }
                let (want, dir, across) = pushSpot(p, station: station, toward: leg)
                p.pushAcross = across
                m.facing = atan2(dir.x, dir.y)
                let d = want - m.pos
                // Round the pallet on foot, never through it: one walk to the cell behind it (the walk
                // stops short of the pallet's edge on its own), then the last bit is a shuffle.
                if m.fetchSpot == nil {
                    m.fetchSpot = want
                    m.path = route(m, to: Cell(x: Int(want.x.rounded()), y: Int(want.y.rounded())))
                    return .spent
                }
                guard m.path.isEmpty else { return .spent }
                // The last bit is a step at a walking pace, not a slide: the pathfinder will not route
                // onto a spot this close to the slab, so the body covers it itself.
                let gap = (d.x * d.x + d.y * d.y).squareRoot()
                if gap > 0.04 { m.pos += d / gap * min(gap, 1.4 * dt); return .spent }
                m.pos = want
                m.fetchSpot = nil
                p.legFrom = p.spot
                p.legAt = clock
                p.pushing = true
                advance(m)
            default:
                if p.pushing { return .spent }
                guard let leg = p.route.first else { arrive(m, station: station, p); return .spent }
                // The leg is done and the next one turns a corner: walk round to the new back side.
                m.phase = 0
                let (want, _, _) = pushSpot(p, station: station, toward: leg)
                walk(m, to: Cell(x: Int(want.x.rounded()), y: Int(want.y.rounded())))
            }
        case .unloadPallet(_, let repo, let back):
            guard m.phaseKind != .walk else { advance(m); return .spent }
            guard let p = pallets[station.name], p.repo == repo else { finish(m); return .spent }
            guard p.isEmpty else { return .spent }
            endPallet(p, station: station)
            finish(m)
            send(m, to: .lounge)
            onLog("\(repo): pallet empty" + (back ? ", the crates are back in storage" : ", the crates are on the deck"))
        default:
            return nil
        }
        return .spent
    }

    // MARK: the pallet itself

    /// The order goes in: a pallet comes out by the near wall and the crates start coming off the rows.
    private func beginPallet(_ m: B, station: Station, repo: String, number: Int) {
        let cargo = world.palletCargo(station: station, repo: repo)
        guard !cargo.isEmpty else {
            // Nothing of that repository in storage: no pallet, and the hand carries have it.
            world.truth.startPallet(station: station.name, repo: repo, number: number, cell: station.palletCell, pos: .zero)
            world.truth.endPallet(station: station.name)
            palletWishes[station.name + "|" + repo] = nil
            finish(m)
            return
        }
        let spot = palletSpot(station: station)
        let cell = Cell(x: Int(spot.x.rounded()), y: Int(spot.y.rounded()))
        let pos = SIMD3(station.offset.x + spot.x, PalletGeometry.lift, station.offset.y + spot.y)
        world.truth.startPallet(station: station.name, repo: repo, number: number, cell: cell, pos: pos)
        world.truth.setPallet(station: station.name, state: .loading)
        let p = PalletJob(station: station.name, repo: repo, number: number, dispatcher: m.id, spot: spot)
        p.bornAt = clock
        for (i, item) in cargo.enumerated() {
            let s = PalletGeometry.slot(i)
            p.toLoad.append((item.crate, item.from, StationTruth.PalletSlot(row: s.row, column: s.column, level: s.level)))
        }
        p.nextAt = clock + 1.4
        // The release may already have gone one way or the other while the dispatcher walked.
        if let push = palletWishes.removeValue(forKey: station.name + "|" + repo) { p.wantsPush = push; p.wantsBack = !push }
        pallets[station.name] = p
        // The spot was picked to be clear, but a body may have wandered onto it while the order went in:
        // whoever is standing under the slab steps aside before it comes down.
        for other in bodies.values where other.station == station.name {
            let dx = abs(other.pos.x - spot.x) - PalletGeometry.width / 2
            let dy = abs(other.pos.y - spot.y) - PalletGeometry.depth / 2
            guard max(dx, dy) < 0.3 else { continue }
            walk(other, to: standCell(station, near: p.cellUnder))
        }
        handOver(m, .loadPallet(station: station.name, repo: repo), announce: true)
        m.path = []
        onLog("\(repo): a pallet floats out in storage")
    }

    /// Behind it, hands on the edge, and out through the doorway one leg at a time.
    private func beginPush(_ m: B, station: Station, _ p: PalletJob) {
        world.truth.setPallet(station: station.name, state: .moving)
        p.route = palletRoute(station: station, repo: p.repo, from: p.spot)
        p.pushing = false
        handOver(m, .pushPallet(station: station.name, repo: p.repo), announce: true)
        guard let leg = p.route.first else { arrive(m, station: station, p); return }
        let (want, _, _) = pushSpot(p, station: station, toward: leg)
        walk(m, to: Cell(x: Int(want.x.rounded()), y: Int(want.y.rounded())))
    }

    /// The last leg is behind it: the pallet stands on the deck and the crates come off.
    private func arrive(_ m: B, station: Station, _ p: PalletJob) {
        p.pushing = false
        p.route = []
        world.truth.movePallet(station: station.name, cell: p.cellUnder,
                               pos: SIMD3(station.offset.x + p.spot.x, PalletGeometry.lift, station.offset.y + p.spot.y))
        beginUnload(m, station: station, p, back: false)
    }

    /// Where a pallet floats out: along storage's aisle, at the place with the most air round it. The
    /// crates standing in the rows and the bodies on the floor both push it away; where nothing does,
    /// it comes out on the doorway's own columns, lined up with the way it will leave.
    func palletSpot(station: Station) -> SIMD2<Double> {
        let rows = Set(station.storageCells.map(\.y)).sorted()
        // Every other row holds crates: only the aisles between them are floor a pallet can stand on.
        let aisles = rows.enumerated().filter { $0.offset % 2 == 1 }.map(\.element)
        let lanes = aisles.isEmpty ? rows : aisles
        // What it must keep off: a crate's own box, turned and nudged where storage is untidy, and a
        // body's shoulders. Anything further than a crate's width away is as good as anywhere else.
        let crates = world.yardLayout(station: station, area: "storage").filter { !$0.carried }
            .map { (at: SIMD2($0.pos.x - station.offset.x, $0.pos.z - station.offset.y), half: 0.27) }
        let crowd = bodies.values.filter { $0.station == station.name }.map { (at: $0.pos, half: 0.3) }
        let near = crates + crowd
        /// How much air is left between the plate and the nearest thing standing. Below zero they overlap.
        func clearance(_ spot: SIMD2<Double>) -> Double {
            near.reduce(9.9) { least, o in
                let dx = abs(o.at.x - spot.x) - (PalletGeometry.width / 2 + o.half)
                let dy = abs(o.at.y - spot.y) - (PalletGeometry.depth / 2 + o.half)
                return min(least, max(dx, dy))
            }
        }
        // Home is the doorway's own columns on the first aisle: a pallet stands by the door it will
        // leave through, and gives that up only where there is no room to float.
        let doorX = deckDoorX(station: station) ?? Double(station.palletCell.x) + 0.5
        let home = SIMD2(doorX, Double(lanes[0]))
        var best = clampToYard(home, station.storageCells)
        var bestKey = (-1, 0.0, 0.0)
        for y in lanes {
            for step in 0...16 {
                let spot = clampToYard(SIMD2(doorX - 1.6 + Double(step) * 0.2, Double(y)), station.storageCells)
                let clear = clearance(spot)
                // Room enough comes first, then nearness to home; a row away costs more than sliding along one.
                let key = (clear >= 0.08 ? 1 : 0, -(abs(spot.x - home.x) + abs(spot.y - home.y) * 2), clear)
                if key > bestKey { bestKey = key; best = spot }
            }
        }
        return best
    }

    /// The middle of the doorway between storage and the deck, in the station's own coordinates: the
    /// column a pallet leaves through, and the one it lines up on while it loads.
    private func deckDoorX(station: Station) -> Double? {
        let deck = station.deckCells, storage = station.storageCells
        let xs = station.yardDoorways.filter {
            (storage.contains($0.0) && deck.contains($0.1)) || (storage.contains($0.1) && deck.contains($0.0))
        }.flatMap { [$0.0.x, $0.1.x] }
        guard let lo = xs.min(), let hi = xs.max() else { return nil }
        return (Double(lo) + Double(hi)) / 2
    }

    /// Where the pusher stands for a leg: behind the pallet on the leg's own axis, a step back from its
    /// edge, with the direction it is heading. Squarely behind is a crate row as often as not, so it
    /// slides along the back edge to the nearest place that is clear floor it can be walked to, rather
    /// than aiming at a stack and creeping the last stretch in a straight line through it.
    func pushSpot(_ p: PalletJob, station: Station, toward target: SIMD2<Double>) -> (spot: SIMD2<Double>, dir: SIMD2<Double>, across: Double) {
        let d = target - p.spot
        let dir = abs(d.x) >= abs(d.y) ? SIMD2(d.x < 0 ? -1.0 : 1.0, 0.0) : SIMD2(0.0, d.y < 0 ? -1.0 : 1.0)
        let back = p.spot - dir * (palletHalf(dir) + 0.42)
        let across = SIMD2(-dir.y, dir.x)
        // No further out than the pallet's own back edge: past that the hands are not on it.
        let reach = (dir.x != 0 ? PalletGeometry.depth : PalletGeometry.width) / 2 - 0.2
        var out = 0.0
        while out <= reach {
            for side in out == 0 ? [1.0] : [-1.0, 1.0] {
                let off = out * side
                if standable(station, at: back + across * off) { return (back + across * off, dir, off) }
            }
            out += 0.3
        }
        return (back, dir, 0)
    }

    /// Where the pusher's hands are on a leg, once it has found its place: the middle of the back edge,
    /// or as far off it as it had to stand to be on clear floor.
    private func pushStand(_ p: PalletJob, dir: SIMD2<Double>) -> SIMD2<Double> {
        p.spot - dir * (palletHalf(dir) + 0.42) + SIMD2(-dir.y, dir.x) * p.pushAcross
    }

    /// Clear floor a body can stand on: one of the station's tiles, with nothing standing on the spot.
    private func standable(_ station: Station, at spot: SIMD2<Double>) -> Bool {
        station.walkable.contains(Cell(x: Int(spot.x.rounded()), y: Int(spot.y.rounded())))
            && !station.obstacles.contains(Station.sub(spot))
    }

    /// Half the pallet across the axis it is travelling along.
    private func palletHalf(_ dir: SIMD2<Double>) -> Double { dir.x != 0 ? PalletGeometry.width / 2 : PalletGeometry.depth / 2 }

    /// Keeps the whole footprint on a block's tiles: the pallet never hangs over the floor's edge.
    func clampToYard(_ p: SIMD2<Double>, _ cells: [Cell]) -> SIMD2<Double> {
        guard let minX = cells.map(\.x).min(), let maxX = cells.map(\.x).max(),
              let minY = cells.map(\.y).min(), let maxY = cells.map(\.y).max() else { return p }
        // A tile's own edge is drawn a little inside its cell, so keep off the rim by that much too.
        let hx = PalletGeometry.width / 2 + 0.1, hy = PalletGeometry.depth / 2 + 0.1
        let lo = SIMD2(Double(minX) - 0.5 + hx, Double(minY) - 0.5 + hy)
        let hi = SIMD2(Double(maxX) + 0.5 - hx, Double(maxY) + 0.5 - hy)
        return SIMD2(min(max(p.x, lo.x), hi.x), min(max(p.y, lo.y), hi.y))
    }

    /// The way out, as axis-aligned legs: line up on the deck doorway's two columns, out through it
    /// onto the deck's aisle row, then along that aisle to the repository's group. Never diagonal,
    /// never off the tiles.
    private func palletRoute(station: Station, repo: String, from: SIMD2<Double>) -> [SIMD2<Double>] {
        let deck = station.deckCells, storage = station.storageCells
        guard !deck.isEmpty, !storage.isEmpty else { return [] }
        let doorX = deckDoorX(station: station) ?? from.x
        // The crate rows are every other row; the pallet travels the aisles between them. The aisle it
        // takes is the one the doorway opens onto, so it never crosses a row of crates to reach it.
        let rows = Set(deck.map(\.y)).sorted()
        let crateRows = Set(rows.enumerated().filter { $0.offset % 2 == 0 }.map(\.element))
        let aisles = rows.filter { !crateRows.contains($0) }
        let near = Double(station.storageNearRow)
        let aisleY = Double(aisles.min { abs(Double($0) - near) < abs(Double($1) - near) } ?? rows.last!)
        // Beside the repository's group on the untested row.
        let untested = world.yardLayout(station: station, area: "deck").filter { $0.repo == repo && !$0.cleared }
        let groupX = untested.first.map { Double($0.cell.x) } ?? doorX

        var legs: [SIMD2<Double>] = []
        var at = from
        func leg(_ to: SIMD2<Double>) {
            guard abs(to.x - at.x) + abs(to.y - at.y) > 0.05 else { return }
            legs.append(to)
            at = to
        }
        leg(clampToYard(SIMD2(doorX, at.y), storage))
        leg(clampToYard(SIMD2(at.x, aisleY), deck))
        leg(clampToYard(SIMD2(groupX, aisleY), deck))
        return legs
    }

    /// The wand out again: the crates float off, onto the deck or back into storage.
    private func beginUnload(_ m: B, station: Station, _ p: PalletJob, back: Bool) {
        p.wantsBack = back
        world.truth.setPallet(station: station.name, state: .unloading)
        p.nextAt = clock + 0.8
        handOver(m, .unloadPallet(station: station.name, repo: p.repo, back: back), announce: true)
    }

    /// Empty: the pallet goes and the station may put out the next one.
    private func endPallet(_ p: PalletJob, station: Station) {
        pallets[station.name] = nil
        world.truth.endPallet(station: station.name)
        servicePallets()
    }

    // MARK: the frame

    /// One frame of every pallet out: the push, and one crate at a time through the air.
    func stepPallets(dt: Double) {
        for (name, p) in pallets {
            guard let station = fleet.stations[name] else { continue }
            if palletErrand(of: bodies[p.dispatcher]).map({ $0.repo != p.repo }) ?? true { adopt(p, station: station) }
            let m = bodies[p.dispatcher]
            // Being pushed: one axis at a time, slowly, easing in, with the pusher behind it.
            if let m, p.pushing, case .pushPallet = m.current?.kind, let leg = p.route.first {
                let full = leg - p.legFrom
                let total = (full.x * full.x + full.y * full.y).squareRoot()
                let dir = total > 0.001 ? full / total : SIMD2(0.0, 0.0)
                let t = max(0, clock - p.legAt)
                // A loaded pallet takes a second to get going: half a cell a second once it is moving.
                let speed = 0.45, ramp = 1.0
                let gone = t < ramp ? speed * t * t / (2 * ramp) : speed * (t - ramp / 2)
                p.spot = p.legFrom + dir * min(total, gone)
                m.pos = pushStand(p, dir: dir)
                m.path = []
                m.facing = atan2(dir.x, dir.y)
                if gone >= total { p.route.removeFirst(); p.pushing = false; p.pushAcross = 0 }
            }
            // A crate in the air lands on the station's own clock, whatever is drawing.
            if let f = p.flight {
                guard f.position(at: clock).done else { continue }
                p.flight = nil
                land(f, p, station: station)
                continue
            }
            guard clock >= p.nextAt else { continue }
            switch world.truth.pallets[p.station]?.state ?? .arriving {
            case .loading: loadOne(p, station: station)
            case .unloading: unloadOne(p, station: station)
            default: break
            }
        }
    }

    /// The dispatcher went away mid-errand: whoever is free takes the pallet over where it stands.
    private func adopt(_ p: PalletJob, station: Station) {
        let free = bodies.values.filter {
            $0.station == station.name && !$0.onJob && !$0.hasLoad && !$0.isSubagent
                && !$0.isCrew && !$0.isQA && $0.state != .leaving && $0.wakeUntil == 0
        }
        guard let m = free.min(by: { abs($0.cell.x - p.cellUnder.x) + abs($0.cell.y - p.cellUnder.y) < abs($1.cell.x - p.cellUnder.x) + abs($1.cell.y - p.cellUnder.y) }) else { return }
        p.dispatcher = m.id
        m.couch = nil; m.bed = nil
        m.place = .room(station.storageCells.contains(p.cellUnder) ? "kind:storage" : "kind:deck")
        switch world.truth.pallets[p.station]?.state ?? .arriving {
        case .loading: handOver(m, .loadPallet(station: station.name, repo: p.repo), announce: true)
        case .loaded, .arriving: handOver(m, .waitPallet(station: station.name, repo: p.repo, words: "taking over the pallet, waiting for the release to merge"), announce: true)
        default:
            // Half way across: it goes no further, the crates come off where it stands.
            world.truth.setPallet(station: station.name, state: .unloading)
            handOver(m, .unloadPallet(station: station.name, repo: p.repo, back: p.wantsBack), announce: true)
        }
        walk(m, to: standCell(station, near: p.cellUnder))   // beside it, never onto it
    }

    /// Where the pallet's plate is, in world coordinates, and a slot on it.
    func palletWorld(_ p: PalletJob, station: Station, slot: StationTruth.PalletSlot? = nil) -> SIMD3<Double> {
        let base = SIMD3(station.offset.x + p.spot.x, PalletGeometry.lift, station.offset.y + p.spot.y)
        guard let slot else { return base }
        return base + PalletGeometry.offset(row: slot.row, column: slot.column, level: slot.level)
    }

    /// The next crate off the rows: it lifts, floats across and settles on its pallet slot.
    private func loadOne(_ p: PalletJob, station: Station) {
        guard let item = p.toLoad.first else { return }
        p.toLoad.removeFirst()
        p.nextAt = clock + 3.0
        // The rows shifted while it waited its turn: lift it from where it stands now.
        let from = world.storageSpot(station: station, crate: item.crate) ?? item.from
        world.putOnPallet(item.crate, at: item.slot)
        p.flight = PalletJob.Flight(crate: item.crate, from: from.pos, to: palletWorld(p, station: station, slot: item.slot),
                                    fromYaw: from.yaw, toYaw: 0, at: clock, seconds: 2.4, slot: nil, yard: nil)
        cue(.palletLift(station: station.name, crate: item.crate))   // the rows are one crate lighter now
    }

    /// The next crate off the pallet: onto its deck slot, or back onto its stack in storage.
    private func unloadOne(_ p: PalletJob, station: Station) {
        guard let crate = p.aboard.first else { return }
        p.aboard.removeFirst()
        p.nextAt = clock + 3.0
        // Bound for a yard from here: that yard holds a place for it, asked for now that it is coming down.
        let yard: Yard = p.wantsBack ? .storage : .deck
        station.ledger.order(repo: crate.repo, number: crate.number, to: yard)
        guard let to = world.slotNow(for: crate, toward: yard) else { return }
        let from = palletWorld(p, station: station, slot: world.truth.pallets[p.station]?.crates[crate.key])
        world.truth.takeOffPallet(crate)   // off the pallet's slot; its row still says pallet until it is down
        p.flight = PalletJob.Flight(crate: crate, from: from, to: to.pos, fromYaw: 0, toYaw: to.yaw, at: clock, seconds: 2.4, slot: to, yard: yard)
        cue(.palletLift(station: station.name, crate: crate))
    }

    /// A crate landed: on the pallet, or down in a yard by hand, the station's word on where it stands.
    private func land(_ f: PalletJob.Flight, _ p: PalletJob, station: Station) {
        if let slot = f.slot, let yard = f.yard {
            world.setDown(f.crate, at: slot)
            world.landed(station: station, repo: f.crate.repo, number: f.crate.number, in: yard, at: now)
        } else {
            p.aboard.append(f.crate)
        }
        cue(.palletLanded(station: station.name, crate: f.crate, aboard: f.aboard))
    }

    // MARK: the console

    private func faceConsole(_ m: B, _ station: Station) {
        let f = station.storageConsole.facing
        m.facing = atan2(f.x, f.y)
    }

    /// Waiting on you: a hop now and then, and a step or two along the wall.
    private func impatient(_ m: B, station: Station) {
        guard clock >= m.nextImpatience else { return }
        m.nextImpatience = clock + Double.random(in: 5...9)
        if Bool.random(), let spot = station.storageCells.filter({ $0.y == station.storageNearRow && $0 != m.cell }).randomElement() {
            walk(m, to: spot)
            return
        }
        cue(.hop(m.id))
    }
}
