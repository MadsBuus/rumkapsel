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
                start(m, .waitPallet(station: station.name, repo: repo, words: "waiting for a pallet"))
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
            else { start(m, .waitPallet(station: station.name, repo: repo, words: "waiting for the release to merge")) }

        case .pushPallet(_, let repo):
            guard let p = pallets[station.name], p.repo == repo else { finish(m); return }
            switch m.phaseKind {
            case .walk:
                advance(m)
            case .approach:
                // Squarely behind it, hands on the edge, facing the way out.
                let want = p.spot + SIMD2(0, 0.5 + Props.palletDepth / 2)
                let d = want - m.pos
                if abs(d.x) + abs(d.y) > 0.04 { m.pos += d * 0.25; m.facing = .pi; m.smoothFacing = .pi; return }
                m.facing = .pi
                advance(m)
                walk(m, to: deckTarget(station: station, repo: repo))
            default:
                world.truth.movePallet(station: station.name, cell: m.cell, pos: SIMD3(station.offset.x + p.spot.x, Props.palletLift, station.offset.y + p.spot.y))
                beginUnload(m, station: station, p, back: false)
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
        let spot = SIMD2(Double(cell.x) + 0.5, Double(cell.y))
        let pos = SIMD3(station.offset.x + spot.x, Props.palletLift, station.offset.y + spot.y)
        world.truth.startPallet(station: station.name, repo: repo, number: number, cell: cell, pos: pos)
        world.truth.setPallet(station: station.name, state: .loading)

        let node = Props.pallet(color: NSColor(fleet.color(forRepo: repo)))
        node.position = v3(pos.x, pos.y, pos.z)
        node.opacity = 0
        node.name = "pallet:" + station.name
        propRoot.addChildNode(node)

        let p = Pallet(station: station.name, repo: repo, number: number, node: node, dispatcher: m.id, spot: spot)
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
        start(m, .loadPallet(station: station.name, repo: repo), announce: true)
        m.setTool(.telekinesis)
        m.path = []
        logEvent("\(repo): a pallet floats out in storage")
    }

    /// Behind it, hands on the edge, and out through the doorway.
    private func beginPush(_ m: Minion, station: Station, _ p: Pallet) {
        p.state = .moving
        world.truth.setPallet(station: station.name, state: .moving)
        m.setTool(nil)
        start(m, .pushPallet(station: station.name, repo: p.repo), announce: true)
        walk(m, to: Cell(x: p.cellUnder.x, y: p.cellUnder.y + 1))
    }

    /// The wand out again: the crates float off, onto the deck or back into storage.
    private func beginUnload(_ m: Minion, station: Station, _ p: Pallet, back: Bool) {
        p.state = .unloading
        p.wantsBack = back
        world.truth.setPallet(station: station.name, state: .unloading)
        p.nextAt = clock + 0.8
        start(m, .unloadPallet(station: station.name, repo: p.repo, back: back), announce: true)
        m.setTool(.telekinesis)
    }

    /// Empty: the pallet fades and the station may put out the next one.
    private func endPallet(_ p: Pallet, station: Station) {
        fadingProps.append((p.node, clock))
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
            // Being pushed: it stays half a step ahead of the hands.
            if let m, case .pushPallet = m.current?.kind, m.phase >= 2 {
                let ahead = SIMD2(sin(m.smoothFacing), cos(m.smoothFacing)) * (0.5 + Props.palletDepth / 2)
                p.spot = m.pos + ahead
                p.node.eulerAngles.y = m.smoothFacing
            }
            let bob = sin((clock + p.bobPhase) * 0.8) * 0.025
            p.node.position = v3(station.offset.x + p.spot.x, Props.palletLift + bob, station.offset.y + p.spot.y)
            p.node.opacity = min(1, (clock - p.bornAt) / 0.9)
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
        case .loading: start(m, .loadPallet(station: station.name, repo: p.repo), announce: true)
        case .loaded, .arriving: start(m, .waitPallet(station: station.name, repo: p.repo, words: "waiting for the release to merge"), announce: true)
        default:
            // Half way across: it goes no further, the crates come off where it stands.
            p.state = .unloading
            world.truth.setPallet(station: station.name, state: .unloading)
            start(m, .unloadPallet(station: station.name, repo: p.repo, back: p.wantsBack), announce: true)
        }
        walk(m, to: p.cellUnder)
    }

    /// The shortest way round for a turn.
    private func shortWay(_ a: Double) -> Double { atan2(sin(a), cos(a)) }

    /// The next crate off the rows: it lifts, floats across and settles on its pallet slot.
    private func loadOne(_ p: Pallet, station: Station) {
        guard let item = p.toLoad.first else { return }
        p.toLoad.removeFirst()
        p.nextAt = clock + 3.0
        world.truth.putOnPallet(item.crate, at: item.slot)
        station.stored[item.crate.repo] = max(0, (station.stored[item.crate.repo] ?? 1) - 1)
        let to = Props.palletOffset(row: item.slot.row, column: item.slot.column, level: item.slot.level)
        // Into the pallet's own space, so it rides along once it has landed.
        let where_ = item.node.worldPosition
        let yaw = Double(item.node.eulerAngles.y) - Double(p.node.eulerAngles.y)
        item.node.removeAllActions()
        item.node.removeFromParentNode()
        p.node.addChildNode(item.node)
        let local = p.node.convertPosition(where_, from: nil)
        p.flight = Pallet.Flight(node: item.node, from: SIMD3(Double(local.x), Double(local.y), Double(local.z)), to: to,
                                 fromYaw: yaw, toYaw: 0, at: clock, seconds: 2.4) { [weak self, weak p] in
            item.node.position = v3(to.x, to.y, to.z)
            item.node.eulerAngles = SCNVector3(0, 0, 0)
            p?.aboard.append((item.crate, item.node))
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

    /// Where the pallet's group of crates stands on the untested row, and where the pusher stops behind it.
    private func deckTarget(station: Station, repo: String) -> Cell {
        let untested = world.yardLayout(station: station, area: "deck").filter { $0.repo == repo && !$0.cleared }
        let x = untested.first?.cell.x ?? station.palletCell.x
        let back = (station.deckCells.map(\.y).max() ?? 2)
        return Cell(x: x, y: back)
    }
}

extension Pallet {
    /// The cell the pallet hovers over right now.
    var cellUnder: Cell { Cell(x: Int(spot.x.rounded()), y: Int(spot.y.rounded())) }
}
