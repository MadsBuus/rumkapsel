// The staging pallet: ordering one at the console, loading it by wand, pushing it across to the deck.

import AppKit
import SceneKit

extension StationController {
    /// The pallet errand a worker is on, if any: which station's pallet and whose crates.
    func palletErrand(of m: Minion?) -> (station: String, repo: String)? {
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
        logEvent("\(repo): staging release #\(number) open, a pallet is ordered")
        servicePallets()
    }

    /// Sends a free worker to the storage console for anything still queued. One at a time per station.
    func servicePallets() {
        for station in fleet.stations.values where station.hasPad && !station.storageCells.isEmpty {
            for want in world.truth.palletQueue[station.name] ?? [] {
                // Someone is already on this errand: leave them to it.
                if minions.values.contains(where: { palletErrand(of: $0)?.station == station.name && palletErrand(of: $0)?.repo == want.repo }) { continue }
                let console = station.storageConsole.cell
                let free = minions.values.filter {
                    $0.station == station.name && !$0.onJob && $0.carried == nil && !$0.isSubagent
                        && !$0.isCrew && !$0.isQA && $0.state != .leaving && $0.wakeUntil == 0
                }
                guard let m = free.min(by: { abs($0.cell.x - console.x) + abs($0.cell.y - console.y) < abs($1.cell.x - console.x) + abs($1.cell.y - console.y) }) else { break }
                m.couch = nil
                m.bed = nil
                m.place = .room("kind:storage")
                start(m, .dispatch(station: station.name, repo: want.repo, number: want.number), announce: true)
                m.setTool(.clipboard)
                walk(m, to: console)
            }
        }
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

    /// One frame of a pallet command, once the worker has stopped walking. The scene's tick calls this
    /// where it branches on the command in hand.
    func palletStep(_ m: Minion, station: Station) {
        guard let c = m.current else { return }
        switch c.kind {
        case .dispatch(_, let repo, let number):
            guard m.phaseKind != .walk else { advance(m); return }
            faceConsole(m, station)
            if world.truth.nextPallet(station: station.name)?.repo == repo {
                beginPallet(m, station: station, repo: repo, number: number)
            } else {
                // A pallet already out, or someone ahead in the queue: wait here and fidget.
                handOver(m, .waitPallet(station: station.name, repo: repo, words: "waiting for a pallet"))
            }

        case .waitPallet(_, let repo):
            guard m.phaseKind != .walk else { advance(m); return }
            if let p = pallets[station.name], p.repo == repo {
                // Beside a loaded pallet, waiting for the release to go one way or the other.
                if p.wantsBack { beginUnload(m, station: station, p, back: true) }
                else if p.wantsPush { beginPush(m, station: station, p) }
                return
            }
            faceConsole(m, station)
            impatient(m, station: station)
            if let want = world.truth.nextPallet(station: station.name), want.repo == repo {
                beginPallet(m, station: station, repo: want.repo, number: want.number)
            }

        case .loadPallet(_, let repo):
            guard m.phaseKind != .walk else { advance(m); return }
            guard let p = pallets[station.name], p.repo == repo else { finish(m); return }
            m.setTool(.telekinesis)
            guard p.isSettled else { return }
            p.state = .loaded
            world.truth.setPallet(station: station.name, state: .loaded)
            if p.wantsBack { beginUnload(m, station: station, p, back: true) }
            else if p.wantsPush { beginPush(m, station: station, p) }
            else { handOver(m, .waitPallet(station: station.name, repo: repo, words: "waiting for the release to merge")) }

        case .pushPallet(_, let repo):
            guard let p = pallets[station.name], p.repo == repo else { finish(m); return }
            switch m.phaseKind {
            case .walk:
                advance(m)
            case .approach:
                // Round the back of the pallet for this leg: squarely behind it, facing the way it goes.
                guard let leg = p.route.first else { arrive(m, station: station, p); return }
                let (want, dir) = pushSpot(p, toward: leg)
                m.facing = atan2(dir.x, dir.y)
                m.smoothFacing = m.facing
                let d = want - m.pos
                // Round the pallet on foot, never through it: one walk to the cell behind it (the walk
                // stops short of the pallet's edge on its own), then the last bit is a shuffle.
                if m.fetchSpot == nil {
                    m.fetchSpot = want
                    m.path = route(m, to: Cell(x: Int(want.x.rounded()), y: Int(want.y.rounded())))
                    return
                }
                guard m.path.isEmpty else { return }
                if abs(d.x) + abs(d.y) > 0.04 { m.pos += d * min(1, 6 * (1.0 / 60)); placePusher(m, station: station); return }
                m.pos = want
                m.fetchSpot = nil
                placePusher(m, station: station)
                m.setTool(.hands)
                p.legFrom = p.spot
                p.legAt = clock
                p.pushing = true
                advance(m)
            default:
                if p.pushing { return }
                guard let leg = p.route.first else { arrive(m, station: station, p); return }
                // The leg is done and the next one turns a corner: walk round to the new back side.
                m.setTool(nil)
                m.tilt.eulerAngles = SCNVector3(0, 0, 0)
                m.phase = 0
                world.truth.jobs[m.id] = (c, 0)
                let (want, _) = pushSpot(p, toward: leg)
                walk(m, to: Cell(x: Int(want.x.rounded()), y: Int(want.y.rounded())))
            }

        case .unloadPallet(_, let repo, let back):
            guard m.phaseKind != .walk else { advance(m); return }
            guard let p = pallets[station.name], p.repo == repo else { finish(m); return }
            m.setTool(.telekinesis)
            guard p.isEmpty else { return }
            endPallet(p, station: station)
            m.setTool(nil)
            finish(m)
            send(m, to: .lounge)
            logEvent("\(repo): pallet empty" + (back ? ", the crates are back in storage" : ", the crates are on the deck"))
        default:
            break
        }
    }

    // MARK: the pallet itself

    /// The order goes in: a pallet fades in by the near wall and the crates start coming off the rows.
    private func beginPallet(_ m: Minion, station: Station, repo: String, number: Int) {
        let cargo = world.palletCargo(station: station, repo: repo)
        guard !cargo.isEmpty else {
            // Nothing of that repository in storage: no pallet, and the hand carries have it.
            world.truth.startPallet(station: station.name, repo: repo, number: number, cell: station.palletCell, pos: .zero)
            world.truth.endPallet(station: station.name)
            palletWishes[station.name + "|" + repo] = nil
            m.setTool(nil)
            finish(m)
            return
        }
        let cell = station.palletCell
        let spot = clampToYard(SIMD2(Double(cell.x) + 0.5, Double(cell.y)), station.storageCells)
        let pos = SIMD3(station.offset.x + spot.x, Props.palletLift, station.offset.y + spot.y)
        world.truth.startPallet(station: station.name, repo: repo, number: number, cell: cell, pos: pos)
        world.truth.setPallet(station: station.name, state: .loading)

        let node = Props.pallet(color: NSColor(fleet.color(forRepo: repo)))
        node.position = v3(pos.x, pos.y, pos.z)
        node.opacity = 0
        node.name = "pallet:" + station.name
        propRoot.addChildNode(node)
        let shadow = Props.palletShadow()
        shadow.position = v3(pos.x, 0.006, pos.z)
        shadow.opacity = 0
        propRoot.addChildNode(shadow)

        let p = Pallet(station: station.name, repo: repo, number: number, node: node, shadow: shadow, dispatcher: m.id, spot: spot)
        p.state = .loading
        p.bornAt = clock
        for (i, item) in cargo.enumerated() {
            guard let n = crateNode("storage", item.crate, at: item.from) else { continue }
            let s = Props.palletSlot(i)
            p.toLoad.append((item.crate, n, StationTruth.PalletSlot(row: s.row, column: s.column, level: s.level)))
        }
        p.nextAt = clock + 1.4
        // The release may already have gone one way or the other while the dispatcher walked.
        if let push = palletWishes.removeValue(forKey: station.name + "|" + repo) { p.wantsPush = push; p.wantsBack = !push }
        pallets[station.name] = p
        handOver(m, .loadPallet(station: station.name, repo: repo), announce: true)
        m.setTool(.telekinesis)
        m.path = []
        logEvent("\(repo): a pallet floats out in storage")
    }

    /// Behind it, hands on the edge, and out through the doorway one leg at a time.
    private func beginPush(_ m: Minion, station: Station, _ p: Pallet) {
        p.state = .moving
        world.truth.setPallet(station: station.name, state: .moving)
        p.route = palletRoute(station: station, repo: p.repo, from: p.spot)
        p.pushing = false
        m.setTool(nil)
        handOver(m, .pushPallet(station: station.name, repo: p.repo), announce: true)
        guard let leg = p.route.first else { arrive(m, station: station, p); return }
        let (want, _) = pushSpot(p, toward: leg)
        walk(m, to: Cell(x: Int(want.x.rounded()), y: Int(want.y.rounded())))
    }

    /// The last leg is behind it: the pallet stands on the deck and the crates come off.
    private func arrive(_ m: Minion, station: Station, _ p: Pallet) {
        p.pushing = false
        p.route = []
        world.truth.movePallet(station: station.name, cell: p.cellUnder,
                               pos: SIMD3(station.offset.x + p.spot.x, Props.palletLift, station.offset.y + p.spot.y))
        m.setTool(nil)
        m.tilt.eulerAngles = SCNVector3(0, 0, 0)
        beginUnload(m, station: station, p, back: false)
    }

    /// Where the pusher stands for a leg: squarely behind the pallet on the leg's own axis, a step
    /// back from its edge, with the direction it is heading.
    private func pushSpot(_ p: Pallet, toward target: SIMD2<Double>) -> (spot: SIMD2<Double>, dir: SIMD2<Double>) {
        let d = target - p.spot
        let dir = abs(d.x) >= abs(d.y) ? SIMD2(d.x < 0 ? -1.0 : 1.0, 0.0) : SIMD2(0.0, d.y < 0 ? -1.0 : 1.0)
        return (p.spot - dir * (palletHalf(dir) + 0.42), dir)
    }

    /// Half the pallet across the axis it is travelling along.
    private func palletHalf(_ dir: SIMD2<Double>) -> Double { dir.x != 0 ? Props.palletWidth / 2 : Props.palletDepth / 2 }

    /// Keeps the whole footprint on a block's tiles: the pallet never hangs over the floor's edge.
    func clampToYard(_ p: SIMD2<Double>, _ cells: [Cell]) -> SIMD2<Double> {
        guard let minX = cells.map(\.x).min(), let maxX = cells.map(\.x).max(),
              let minY = cells.map(\.y).min(), let maxY = cells.map(\.y).max() else { return p }
        // A tile's own edge is drawn a little inside its cell, so keep off the rim by that much too.
        let hx = Props.palletWidth / 2 + 0.1, hy = Props.palletDepth / 2 + 0.1
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
        let gates = station.yardDoorways.filter {
            (storage.contains($0.0) && deck.contains($0.1)) || (storage.contains($0.1) && deck.contains($0.0))
        }
        let xs = gates.flatMap { [$0.0.x, $0.1.x] }
        let doorX = xs.isEmpty ? from.x : (Double(xs.min()!) + Double(xs.max()!)) / 2
        // The crate rows are every other row; the pallet travels the aisles between them.
        let rows = Set(deck.map(\.y)).sorted()
        let crateRows = Set(rows.enumerated().filter { $0.offset % 2 == 0 }.map(\.element))
        let aisles = rows.filter { !crateRows.contains($0) }
        let mid = Double(rows.reduce(0, +)) / Double(rows.count)
        let aisleY = Double(aisles.min { abs(Double($0) - mid) < abs(Double($1) - mid) } ?? rows.last!)
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

    /// Puts the pusher's body where its position says, with the lean it is holding. The minion tick
    /// skips this for anyone on a pallet errand, so the push does it itself.
    private func placePusher(_ m: Minion, station: Station, tilt: Double = 0, shove: Double = 0) {
        m.node.position = v3(station.offset.x + m.pos.x + sin(m.facing) * shove, 0,
                             station.offset.y + m.pos.y + cos(m.facing) * shove)
        m.node.eulerAngles = SCNVector3(0, m.smoothFacing, 0)
        m.tilt.eulerAngles = SCNVector3(tilt, 0, 0)
    }

    /// The wand out again: the crates float off, onto the deck or back into storage.
    private func beginUnload(_ m: Minion, station: Station, _ p: Pallet, back: Bool) {
        p.state = .unloading
        p.wantsBack = back
        world.truth.setPallet(station: station.name, state: .unloading)
        p.nextAt = clock + 0.8
        handOver(m, .unloadPallet(station: station.name, repo: p.repo, back: back), announce: true)
        m.setTool(.telekinesis)
    }

    /// Empty: the pallet fades and the station may put out the next one.
    private func endPallet(_ p: Pallet, station: Station) {
        fadingProps.append((p.node, clock))
        fadingProps.append((p.shadow, clock))
        pallets[station.name] = nil
        world.truth.endPallet(station: station.name)
        servicePallets()
    }

    // MARK: the frame

    /// One frame of every pallet out: the bob, the push, and one crate at a time through the air.
    func tickPallets() {
        // The panel by the storage doorway blinks while an order stands unanswered.
        for station in fleet.stations.values where consolePanels[station.name] != nil {
            if world.truth.palletQueue[station.name]?.isEmpty == false { flashConsole(station) } else { stopConsole(station) }
        }
        for (name, p) in pallets {
            guard let station = fleet.stations[name] else { continue }
            if palletErrand(of: minions[p.dispatcher]).map({ $0.repo != p.repo }) ?? true { adopt(p, station: station) }
            let m = minions[p.dispatcher]
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
                m.pos = p.spot - dir * (palletHalf(dir) + 0.42)
                m.path = []
                m.facing = atan2(dir.x, dir.y)
                m.smoothFacing = m.facing
                // Leaning into it, with the shove and give of real effort. The tick's minion loop
                // leaves a pallet errand's body alone, so the pusher is placed here.
                placePusher(m, station: station, tilt: 0.35, shove: sin(clock * 3.6 + p.bobPhase) * 0.02)
                if gone >= total { p.route.removeFirst(); p.pushing = false }
            }
            // A slow, plain sine: the slab rides its cushion of light.
            let bob = sin(clock * (2 * .pi / 2.4) + p.bobPhase) * 0.06
            p.node.position = v3(station.offset.x + p.spot.x, Props.palletLift + bob, station.offset.y + p.spot.y)
            p.node.eulerAngles.y = 0
            p.node.opacity = min(1, (clock - p.bornAt) / 0.9)
            // The shadow keeps to the floor: it tightens and darkens as the slab comes down.
            let high = bob / 0.06 * 0.5 + 0.5
            p.shadow.position = v3(station.offset.x + p.spot.x, 0.006, station.offset.y + p.spot.y)
            p.shadow.scale = SCNVector3(1.06 - high * 0.12, 1.06 - high * 0.12, 1)
            p.shadow.opacity = p.node.opacity * CGFloat(1.06 - high * 0.26)
            // The corner light: half a second on, half off, off the station's own clock.
            if let beacon = p.beacon {
                let on = clock.truncatingRemainder(dividingBy: 1.0) < 0.5
                beacon.geometry?.firstMaterial?.diffuse.contents = on ? Props.palletAmber : Props.palletAmberOff
                beacon.geometry?.firstMaterial?.emission.contents = on ? Props.palletAmber : NSColor.black
            }
            if m?.tool == .telekinesis { m?.setWand(lifting: p.flight != nil) }
            // A crate in the air: an arc on the station's own clock, so it lands whatever is drawing.
            if let f = p.flight {
                let t = min(1, (clock - f.at) / f.seconds)
                let e = t * t * (3 - 2 * t)
                let at = f.from + (f.to - f.from) * e
                f.node.position = v3(at.x, at.y + sin(t * .pi) * 0.7, at.z)
                f.node.eulerAngles = SCNVector3(0, f.fromYaw + shortWay(f.toYaw - f.fromYaw) * e, 0)
                guard t >= 1 else { continue }
                p.flight = nil
                f.land()
                continue
            }
            guard clock >= p.nextAt else { continue }
            switch p.state {
            case .loading: loadOne(p, station: station)
            case .unloading: unloadOne(p, station: station)
            default: break
            }
        }
        // Pallets on their way out, fading where they stood.
        for (i, f) in fadingProps.enumerated().reversed() {
            let t = (clock - f.at) / 0.9
            f.node.opacity = max(0, 1 - t)
            if t >= 1 { f.node.removeFromParentNode(); fadingProps.remove(at: i) }
        }
    }

    /// The dispatcher went away mid-errand: whoever is free takes the pallet over where it stands.
    private func adopt(_ p: Pallet, station: Station) {
        let free = minions.values.filter {
            $0.station == station.name && !$0.onJob && $0.carried == nil && !$0.isSubagent
                && !$0.isCrew && !$0.isQA && $0.state != .leaving && $0.wakeUntil == 0
        }
        guard let m = free.min(by: { abs($0.cell.x - p.cellUnder.x) + abs($0.cell.y - p.cellUnder.y) < abs($1.cell.x - p.cellUnder.x) + abs($1.cell.y - p.cellUnder.y) }) else { return }
        p.dispatcher = m.id
        m.couch = nil; m.bed = nil
        m.place = .room(station.storageCells.contains(p.cellUnder) ? "kind:storage" : "kind:deck")
        switch p.state {
        case .loading: handOver(m, .loadPallet(station: station.name, repo: p.repo), announce: true)
        case .loaded, .arriving: handOver(m, .waitPallet(station: station.name, repo: p.repo, words: "taking over the pallet, waiting for the release to merge"), announce: true)
        default:
            // Half way across: it goes no further, the crates come off where it stands.
            p.state = .unloading
            world.truth.setPallet(station: station.name, state: .unloading)
            handOver(m, .unloadPallet(station: station.name, repo: p.repo, back: p.wantsBack), announce: true)
        }
        walk(m, to: standCell(station, near: p.cellUnder))   // beside it, never onto it
    }

    /// The shortest way round for a turn.
    private func shortWay(_ a: Double) -> Double { atan2(sin(a), cos(a)) }

    /// The next crate off the rows: it lifts, floats across and settles on its pallet slot.
    private func loadOne(_ p: Pallet, station: Station) {
        guard let item = p.toLoad.first else { return }
        p.toLoad.removeFirst()
        p.nextAt = clock + 3.0
        // The rows are redrawn every time one leaves, so take the crate standing there now, not the
        // node this pallet was handed when it was ordered: that one is long gone from the scene.
        let node = crateNode("storage", item.crate) ?? item.node
        world.truth.putOnPallet(item.crate, at: item.slot)
        station.stored[item.crate.repo] = max(0, (station.stored[item.crate.repo] ?? 1) - 1)
        let to = Props.palletOffset(row: item.slot.row, column: item.slot.column, level: item.slot.level)
        // Into the pallet's own space, so it rides along once it has landed.
        let where_ = node.worldPosition
        let yaw = Double(node.eulerAngles.y) - Double(p.node.eulerAngles.y)
        node.removeAllActions()
        node.removeFromParentNode()
        p.node.addChildNode(node)
        let local = p.node.convertPosition(where_, from: nil)
        p.flight = Pallet.Flight(node: node, from: SIMD3(Double(local.x), Double(local.y), Double(local.z)), to: to,
                                 fromYaw: yaw, toYaw: 0, at: clock, seconds: 2.4) { [weak self, weak p] in
            node.position = v3(to.x, to.y, to.z)
            node.eulerAngles = SCNVector3(0, 0, 0)
            p?.aboard.append((item.crate, node))
            self?.drone.thud()
        }
        rebuildMarkers()   // the rows are one crate lighter now
    }

    /// The next crate off the pallet: onto its deck slot, or back onto its stack in storage.
    private func unloadOne(_ p: Pallet, station: Station) {
        guard let item = p.aboard.first else { return }
        p.aboard.removeFirst()
        p.nextAt = clock + 3.0
        let repo = item.crate.repo
        let to = p.wantsBack ? world.storageSlot(station: station, repo: repo, number: item.crate.number)
                             : world.deckSlot(station: station, repo: repo, index: station.staged[repo] ?? 0, number: item.crate.number)
        world.truth.takeOffPallet(item.crate)
        let where_ = item.node.worldPosition
        let yaw = Double(p.node.eulerAngles.y) + Double(item.node.eulerAngles.y)
        item.node.removeAllActions()
        item.node.removeFromParentNode()
        propRoot.addChildNode(item.node)
        p.flight = Pallet.Flight(node: item.node, from: SIMD3(Double(where_.x), Double(where_.y), Double(where_.z)),
                                 to: to.pos, fromYaw: yaw, toYaw: to.yaw, at: clock, seconds: 2.4) { [weak self] in
            guard let self else { return }
            world.truth.setDown(item.crate, at: to)
            if p.wantsBack { world.landedInStorage(station: station, repo: repo, number: item.crate.number) }
            else { station.staged[repo, default: 0] += 1; fleet.save() }
            item.node.removeFromParentNode()
            drone.thud()
            rebuildMarkers()
            refreshRockets()
        }
    }

    // MARK: the console

    /// The panel by the storage doorway blinks while an order is being placed.
    private func flashConsole(_ station: Station) {
        guard let panel = consolePanels[station.name], panel.action(forKey: "flash") == nil else { return }
        panel.runAction(.repeatForever(.sequence([.fadeOpacity(to: 0.3, duration: 0.5), .fadeOpacity(to: 1, duration: 0.5)])), forKey: "flash")
    }

    private func stopConsole(_ station: Station) {
        guard let panel = consolePanels[station.name] else { return }
        panel.removeAction(forKey: "flash")
        panel.opacity = 1
    }

    private func faceConsole(_ m: Minion, _ station: Station) {
        let f = station.storageConsole.facing
        m.facing = atan2(f.x, f.y)
    }

    /// Waiting on you: a hop now and then, and a step or two along the wall.
    private func impatient(_ m: Minion, station: Station) {
        guard clock >= m.nextImpatience else { return }
        m.nextImpatience = clock + Double.random(in: 5...9)
        if Bool.random(), let spot = station.storageCells.filter({ $0.y == station.storageNearRow && $0 != m.cell }).randomElement() {
            walk(m, to: spot)
            return
        }
        m.node.runAction(.sequence([.moveBy(x: 0, y: 0.12, z: 0, duration: 0.08), .moveBy(x: 0, y: -0.12, z: 0, duration: 0.08),
                                    .moveBy(x: 0, y: 0.12, z: 0, duration: 0.08), .moveBy(x: 0, y: -0.12, z: 0, duration: 0.08)]))
    }

}

extension Pallet {
    /// The cell the pallet hovers over right now.
    var cellUnder: Cell { Cell(x: Int(spot.x.rounded()), y: Int(spot.y.rounded())) }
}
