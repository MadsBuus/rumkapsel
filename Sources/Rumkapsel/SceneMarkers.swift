// Everything that comes and goes on top of the floor: crates, cones, rockets, steam, power and beams.

import AppKit
import SceneKit

extension StationController {
    /// Tells each station what is standing on its floor, so walks thread between the props.
    func refreshObstacles() {
        var blocked: [String: Set<Cell>] = [:]
        func mark(_ station: String, _ node: SCNNode, offset: SIMD2<Double>) {
            let (lo, hi) = node.boundingBox
            let p = SIMD2(Double(node.position.x) - offset.x, Double(node.position.z) - offset.y)
            let r = Double(max(hi.x - lo.x, hi.z - lo.z)) / 2 * 0.8
            let f = Double(Station.fine)
            for sx in Int(((p.x - r) * f).rounded())...Int(((p.x + r) * f).rounded()) {
                for sy in Int(((p.y - r) * f).rounded())...Int(((p.y + r) * f).rounded()) { blocked[station, default: []].insert(Cell(x: sx, y: sy)) }
            }
        }
        for n in markerRoot.childNodes {
            guard let name = n.name, let colon = name.firstIndex(of: ":"), let bar = name.firstIndex(of: "|"), colon < bar else { continue }
            let stationName = String(name[name.index(after: colon)..<bar])
            guard let st = fleet.stations[stationName] else { continue }
            mark(stationName, n, offset: st.offset)
        }
        for m in minions.values {
            for p in m.pyramids + m.queuedCones { mark(m.station, p, offset: .zero) }
        }
        // Furniture and fixtures: anything standing on a room's floor that is not a tile.
        for n in staticRoot.childNodes where n.geometry != nil && !(n.geometry is SCNPlane) && (n.name ?? "").hasPrefix("room:") {
            let key = String(n.name!.dropFirst(5))
            guard let bar = key.firstIndex(of: "|"), let st = fleet.stations[String(key[..<bar])] else { continue }
            mark(st.name, n, offset: st.offset)
        }
        for st in fleet.stations.values { st.obstacles = blocked[st.name] ?? [] }
    }

    /// Grey boxes pile up in an office as commits land; the pull request state colours them.
    func rebuildMarkers() {
        // Storage and the deck follow GitHub, but through the minions: what should move is carried,
        // and only the rest is redrawn. Decide that before the old crates are taken off the floor.
        for station in fleet.stations.values where station.hasPad {
            for (root, info) in world.repoRoots where info.station == station.name {
                if let c = github.cargo(repoRoot: root), case .carryToDeck(let commands) = world.reconcile(station: station, repo: info.repo, root: root, cargo: c) {
                    handle(.carryToDeck(station: station.name, repo: info.repo, commands: commands))
                }
            }
        }
        markerRoot.childNodes.filter { $0.name != "haul" }.forEach { $0.removeFromParentNode() }   // a crate waiting for its carrier stays
        for station in fleet.stations.values {
            for room in station.rooms.values where room.branch != nil || world.crewBoxes[roomKey(station, room)] != nil || world.peerBoxes[roomKey(station, room)] != nil {
                let key = roomKey(station, room)
                var count: Int
                var ghosts = 0                 // uncommitted work: unfinished, translucent boxes
                var pr: PullRequest?
                var packaged = false           // a pull request bundles everything into one strapped package
                var boxOpacity = 1.0
                if room.branch == nil {
                    guard let cb = world.crewBoxes[key] ?? world.peerBoxes[key] else { continue }
                    count = min(16, max(1, cb.count))
                    // A teammate's pull request is a crate with its sticker; pushes before a PR are cubes.
                    let prNumber = world.crewRoomInfo[key]?.prNumber
                    let state = world.isClosed(key) ? "CLOSED" : (prNumber != nil ? "OPEN" : cb.state)
                    pr = PullRequest(number: prNumber ?? 0, title: "", state: state, reviewDecision: "", isDraft: false, url: "")
                    packaged = prNumber != nil || world.isClosed(key)
                } else {
                    let local = world.localState(room)
                    let dirtyFiles = room.worktree.map { github.dirtyFiles(worktree: $0) } ?? 0
                    if (local.commits == 0 && dirtyFiles == 0) || haulingRooms.contains(key) { continue }   // nothing to show, or on its way to storage
                    pr = room.repoRoot.flatMap { github.pull(branch: room.branch!, repoRoot: $0) }
                    count = min(16, Int(pow(Double(local.commits), 0.7).rounded(.up)))
                    ghosts = min(8, Int(pow(Double(dirtyFiles), 0.6).rounded(.up)))
                    packaged = pr != nil
                }
                // No pull request: the room's own tint. With one: the status colour, shaded the same way.
                let base = NSColor(room.color).lighter(0.12)
                let status: NSColor?
                switch (pr?.state, pr?.reviewDecision, pr?.isDraft) {
                case (nil, _, _): status = nil
                case ("MERGED", _, _): status = NSColor(rgb: (0.6, 0.4, 0.9))
                case ("CLOSED", _, _): status = NSColor(rgb: (0.92, 0.22, 0.22))   // closed, not merged: red, then it fades with the office
                case (_, "APPROVED", _): status = NSColor(rgb: (0.45, 0.95, 0.5))
                case (_, "CHANGES_REQUESTED", _): status = NSColor(rgb: (0.95, 0.3, 0.3))
                case (_, _, true): status = NSColor(rgb: (0.6, 0.62, 0.68))
                default: status = NSColor(rgb: (0.4, 0.82, 0.45))
                }
                var color = status.map { $0.mixed(with: base, 0.15) } ?? base
                let failing = world.checksFailing(room)
                if world.isDusty(room) { color = color.mixed(with: NSColor(rgb: (0.55, 0.55, 0.6)), 0.55) }
                let floorShadow = NSColor(room.color).darker(0.16)
                if packaged {
                    // One package for the whole pull request, sized by the work in it, strapped in the status colour.
                    let cell = farCells(station, room).first!
                    let size = 0.38   // one crate size everywhere: the cubes say how much work is in it
                    let pkg = Props.package(color: NSColor(room.color).lighter(0.1), band: status ?? NSColor(rgb: (0.55, 0.55, 0.6)), size: size)
                    pkg.position = v3(station.offset.x + Double(cell.x), 0, station.offset.y + Double(cell.y))
                    pkg.name = "box:" + key
                    pkg.opacity = undelivered.contains(key) ? 0 : 1
                    if failing {
                        let shell = SCNNode(geometry: SCNBox(width: size * 1.2, height: size, length: size * 1.2, chamferRadius: 0))
                        shell.geometry!.firstMaterial = flat(NSColor(rgb: (0.95, 0.2, 0.2)))
                        shell.opacity = 0.2
                        shell.runAction(.repeatForever(.sequence([.fadeOpacity(to: 0.55, duration: 0.7), .fadeOpacity(to: 0.15, duration: 0.9)])))
                        pkg.addChildNode(shell)
                    }
                    markerRoot.addChildNode(pkg)
                    lastBoxCount[key] = 1
                    continue
                }
                // Deterministic clutter: sizes, turns and shades vary per box, and extras stack on top.
                var seed = UInt64(truncatingIfNeeded: key.hashValue) | 1
                func rnd() -> Double { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Double(seed >> 11) / Double(1 << 53) }
                let cells = farCells(station, room)
                var placedBoxes: [(pos: SIMD3<Double>, size: Double)] = []
                for i in 0..<(count + ghosts) {
                    let ghost = i >= count
                    let size = [0.18, 0.26, 0.34][min(2, Int(rnd() * 3))]
                    let shade = CGFloat(rnd() * 0.1 - 0.04)
                    let box = SCNBox(width: size, height: size, length: size, chamferRadius: 0)
                    let tint = color.lighter(shade)
                    // Flat game-style shading: light top, mid and dark sides, no lights involved.
                    let top = flat(tint.lighter(0.14)), mid = flat(tint), dark = flat(tint.darker(0.13))
                    box.materials = [mid, dark, mid, dark, top, top]
                    let n = SCNNode(geometry: box)
                    let shadow = SCNNode(geometry: SCNPlane(width: size * 1.25, height: size * 1.25))
                    shadow.geometry!.firstMaterial = flat(floorShadow)
                    shadow.eulerAngles.x = -.pi / 2
                    shadow.position = v3(size * 0.08, -size / 2 + 0.004, size * 0.08)
                    shadow.name = "box:" + key
                    n.addChildNode(shadow)
                    let pos: SIMD3<Double>
                    if i >= 8, let base = placedBoxes[i - 8] as (pos: SIMD3<Double>, size: Double)? {
                        pos = SIMD3(base.pos.x + (rnd() - 0.5) * 0.06, base.pos.y + base.size / 2 + size / 2, base.pos.z + (rnd() - 0.5) * 0.06)
                    } else {
                        let cell = cells[(i / 3) % cells.count]
                        let room = max(0, 0.86 - size * 1.25)   // keep the box and its shadow inside the tile
                        pos = SIMD3(station.offset.x + Double(cell.x) + (rnd() - 0.5) * room, size / 2, station.offset.y + Double(cell.y) + (rnd() - 0.5) * room)
                    }
                    placedBoxes.append((pos, size))
                    n.position = v3(pos.x, pos.y, pos.z)
                    n.eulerAngles.y = rnd() * 0.9
                    n.name = "box:" + key
                    n.opacity = undelivered.contains(key) ? 0 : (ghost ? 0.38 : boxOpacity)
                    if failing && !ghost {
                        let shell = SCNNode(geometry: SCNBox(width: size * 1.25, height: size * 1.25, length: size * 1.25, chamferRadius: 0))
                        shell.geometry!.firstMaterial = flat(NSColor(rgb: (0.95, 0.2, 0.2)))
                        shell.opacity = 0.2
                        shell.runAction(.repeatForever(.sequence([.fadeOpacity(to: 0.55, duration: 0.7), .fadeOpacity(to: 0.15, duration: 0.9)])))
                        shell.name = "box:" + key
                        n.addChildNode(shell)
                    }
                    markerRoot.addChildNode(n)
                }
                // More commits than last time while the owner is in: it carries the new box in.
                if let last = lastBoxCount[key], count > last, room.branch != nil,
                   let m = minions.values.first(where: { $0.station == station.name && $0.place == .room(room.key) && !$0.onJob && $0.carried == nil }) {
                    let carry = SCNNode(geometry: SCNBox(width: 0.24, height: 0.24, length: 0.24, chamferRadius: 0))
                    carry.geometry!.firstMaterial = lit(color)
                    carry.position = v3(0, m.headHeight + 0.14, 0)
                    m.node.addChildNode(carry)
                    m.carried = carry
                    m.commitDrop = true
                    if let dest = room.cells.filter({ $0 != m.cell }).randomElement() { walk(m, to: dest) }
                }
                lastBoxCount[key] = count + ghosts
            }
            let purple = NSColor(rgb: (0.6, 0.4, 0.9))
            for area in ["storage", "deck"] where station.hasPad {
                for slot in world.yardLayout(station: station, area: area) {
                    if area == "deck", world.truth.isCarried(station: station.name, repo: slot.repo, number: slot.number) { continue }
                    let c = NSColor(fleet.color(forRepo: slot.repo))
                    let pkg = Props.package(color: c.lighter(0.1), band: slot.cleared ? NSColor(rgb: (0.45, 0.95, 0.5)) : purple, size: 0.38, approved: slot.cleared)
                    pkg.position = v3(slot.pos.x, slot.pos.y, slot.pos.z)
                    pkg.eulerAngles.y = slot.yaw
                    pkg.name = "\(area):\(station.name)|\(slot.repo)|\(slot.number)"
                    pkg.enumerateChildNodes { c, _ in c.name = pkg.name }
                    markerRoot.addChildNode(pkg)
                }
            }
        }
        refreshObstacles()
    }

    /// Flame on, a slow climb that carries the rocket out of the frame, then gone.
    func liftOff(_ node: SCNNode) {
        drone.sweep(up: true)
        node.childNode(withName: "flame", recursively: false)?.opacity = 1
        let rise = SCNAction.moveBy(x: 0, y: 40, z: 0, duration: 12)
        rise.timingMode = .easeIn
        let flicker = SCNAction.repeat(.sequence([.scale(to: 1.04, duration: 0.08), .scale(to: 0.98, duration: 0.08)]), count: 8)
        node.runAction(.sequence([flicker, .group([rise, .sequence([.wait(duration: 9), .fadeOut(duration: 3)])]), .removeFromParentNode()]))
    }

    // MARK: rockets

    /// The reconciler says what a repository's rocket should be doing. An empty pad gets a new actor;
    /// one already there only takes a stage it has not reached yet, so a repeated wish changes nothing.
    func handle(rocket station: String, repo: String, label: String, untested: Bool, tall: Bool, cargo: Int, command: Command) {
        guard let st = fleet.stations[station], case .rocket(let stage, _, _) = command.kind else { return }
        let key = station + "|" + repo
        if let r = rocketActors[key] {
            r.label = label
            redraw(r, cargo: cargo, untested: untested)
            guard stage.rank > r.stage.rank else { return }
            take(r, command)
            return
        }
        let slot = rocketActors.count % 4
        let r = Rocket(station: station, repo: repo,
                       node: rocketNode(station: st, repo: repo, cargo: cargo, untested: untested, tall: tall, label: label, slot: slot),
                       command: command)
        r.label = label; r.untested = untested; r.tall = tall; r.cargoShown = cargo
        rocketActors[key] = r
        take(r, command)
    }

    /// The rocket prop itself, on its slot on the pad.
    private func rocketNode(station: Station, repo: String, cargo: Int, untested: Bool, tall: Bool, label: String, slot: Int) -> SCNNode {
        let n = Props.rocket(color: NSColor(fleet.color(forRepo: repo)), tall: tall, cargo: cargo)
        if untested {
            let deco = Props.holdDecoration(around: SIMD3(0, 0, 0), tall: tall)
            deco.name = "hold"
            n.addChildNode(deco)
        }
        let offsets: [SIMD2<Double>] = [SIMD2(0, 0), SIMD2(1.3, 0), SIMD2(-1.3, 0), SIMD2(0, 1.2)]
        let pc = station.padCenter + offsets[slot]
        n.position = v3(station.offset.x + pc.x, 0, station.offset.y + pc.y)
        n.name = label
        n.enumerateChildNodes { c, _ in if c.name != "flame" && c.name != "hold" { c.name = label } }
        rocketRoot.addChildNode(n)
        return n
    }

    /// A production rocket grows with what it will carry. Only one standing by is redrawn: once it is
    /// loading it keeps the size it had, and the steam and the flame stay where they are.
    private func redraw(_ r: Rocket, cargo: Int, untested: Bool) {
        guard r.stage.rank == 0, !r.node.hasActions, let st = fleet.stations[r.station] else { return }
        guard cargo / 3 != r.cargoShown / 3 || untested != r.untested else {
            r.node.name = r.label
            r.node.enumerateChildNodes { c, _ in if c.name != "flame" && c.name != "hold" { c.name = r.label } }
            return
        }
        let slot = Array(rocketActors.keys).sorted().firstIndex(of: r.key) ?? 0
        let position = r.node.position
        r.node.removeFromParentNode()
        r.node = rocketNode(station: st, repo: r.repo, cargo: cargo, untested: untested, tall: r.tall, label: r.label, slot: slot % 4)
        r.node.position = position
        r.cargoShown = cargo
        r.untested = untested
    }

    /// The rocket takes a new command and starts its first phase.
    private func take(_ r: Rocket, _ command: Command) {
        r.command = command
        r.phase = 0
        r.since = clock
        issue(command, by: "rocket", announce: true)
        beginRocketPhase(r)
    }

    private func beginRocketPhase(_ r: Rocket) {
        switch r.phaseKind {
        case .load:
            r.node.childNode(withName: "hold", recursively: false)?.removeFromParentNode()   // cleared: the tape comes down
            loadCrates(r)
        case .climb:
            world.truth.clearPad(station: r.station, repo: r.repo)
            liftOff(r.node)
            r.until = clock + 15
            fleet.save()
        default:
            if r.isSteaming { addSteam(to: r.node) }
        }
    }

    /// One pass over every rocket: loading watches station truth, the climb watches the clock.
    func tickRockets() {
        for r in Array(rocketActors.values) {
            switch r.phaseKind {
            case .load:
                loadCrates(r)
                // Done when nothing of this repository is left on the rows and nothing is on someone's
                // arms. A haul that got stuck may not ground a launch forever.
                guard padClear(r) || clock - r.since > 90 else { continue }
                advanceRocket(r)
            case .climb:
                if clock >= r.until { r.node.removeFromParentNode(); rocketActors[r.key] = nil }
            default: continue
            }
        }
    }

    /// The end of the load phase: on to the climb if the command has one, otherwise the rocket steams.
    private func advanceRocket(_ r: Rocket) {
        if r.phase + 1 < r.command.phases.count {
            r.phase += 1
            r.since = clock
            beginRocketPhase(r)
            return
        }
        take(r, .rocket(.steam, station: r.station, repo: r.repo))
    }

    /// Which row a rocket loads from: the deck when releases go through staging, storage otherwise.
    private var loadSource: String { ConfigStore.shared.current.stagingBranch.isEmpty ? "storage" : "deck" }

    /// Nothing of this repository left standing on its row, and nothing on anyone's arms.
    private func padClear(_ r: Rocket) -> Bool {
        let onFloor = markerRoot.childNodes.contains { ($0.name ?? "").hasPrefix("\(loadSource):\(r.station)|\(r.repo)|") }
        return !onFloor && world.truth.carriedCount(station: r.station, repo: r.repo) == 0
    }

    /// Hands out a carry for every crate of the repository still standing on its row. A crate already
    /// spoken for is off the floor, so this can run every pass without doubling up.
    private func loadCrates(_ r: Rocket) {
        guard let station = fleet.stations[r.station] else { return }
        let source = loadSource
        let repo = r.repo
        let boxes = markerRoot.childNodes.filter { ($0.name ?? "").hasPrefix("\(source):\(r.station)|\(repo)|") }
        guard !boxes.isEmpty else { return }
        let numbers = boxes.map { Int($0.name?.split(separator: "|").last ?? "") ?? 0 }
        for command in world.carryToPad(station: station, repo: repo, from: source, numbers: numbers) {
            guard let crate = command.crate, case .carry(_, let from, _) = command.kind,
                  let b = crateNode(source, crate, at: from) else { continue }
            carry(command, node: b) { [weak self] in
                guard let self else { return }
                if source == "deck" { station.staged[repo] = max(0, (station.staged[repo] ?? 1) - 1) }
                else { station.stored[repo] = max(0, (station.stored[repo] ?? 1) - 1) }
                b.runAction(.sequence([.scale(to: 0.01, duration: 0.3), .removeFromParentNode()]))
                fleet.save()
            }
        }
    }

    /// Pads whose release is gone lose their rocket, and the ones standing by are resized to the pile.
    func refreshRockets() {
        let live = world.padRockets()
        for (key, r) in rocketActors {
            guard let st = fleet.stations[r.station] else { continue }
            if !live.contains(key), !r.isBusy, !r.node.hasActions {
                r.node.removeFromParentNode()
                rocketActors[key] = nil
                continue
            }
            redraw(r, cargo: world.cargoWaiting(station: st, repo: r.repo), untested: r.untested)
        }
        rebuildDueRings()
    }

    /// Cargo waiting with no rocket yet: a faint ring in the repo colour on the pad, a release is due.
    private func rebuildDueRings() {
        if ringRoot.parent == nil { propRoot.addChildNode(ringRoot) }
        ringRoot.childNodes.forEach { $0.removeFromParentNode() }
        for station in fleet.stations.values where station.hasPad {
            let pile = ConfigStore.shared.current.stagingBranch.isEmpty ? station.stored : station.staged
            let waiting = pile.filter { $0.value > 0 }.map(\.key).sorted()
            let withRocket = Set(world.repoRoots.filter { $0.value.station == station.name }.compactMap { (root, info) -> String? in
                (github.openReleases(repoRoot: root)?.contains(where: \.isProduction) == true) ? info.repo : nil
            })
            for (i, repo) in waiting.filter({ !withRocket.contains($0) }).enumerated() {
                let radius = 1.62 + Double(i) * 0.12
                let ring = SCNNode(geometry: faceted(SCNTube(innerRadius: radius, outerRadius: radius + 0.05, height: 0.008)))
                ring.geometry!.firstMaterial = flat(NSColor(fleet.color(forRepo: repo)))
                ring.opacity = 0.3
                ring.runAction(.repeatForever(.sequence([.fadeOpacity(to: 0.6, duration: 1.6), .fadeOpacity(to: 0.25, duration: 1.6)])))
                let pc = station.padCenter
                ring.position = v3(station.offset.x + pc.x, 0.009, station.offset.y + pc.y)
                ring.name = "pad:" + station.name
                ringRoot.addChildNode(ring)
            }
        }
    }

    /// Steam venting from a loaded rocket waiting for ignition.
    func addSteam(to rocket: SCNNode) {
        guard rocket.childNode(withName: "steam", recursively: false) == nil else { return }
        let emitter = SCNNode(); emitter.name = "steam"
        rocket.addChildNode(emitter)
        let puff = SCNAction.run { [weak self] _ in
            guard let self else { return }
            enqueue {
                let p = SCNNode(geometry: SCNBox(width: 2 * (0.08), height: 2 * (0.08), length: 2 * (0.08), chamferRadius: 0))
                p.geometry!.firstMaterial = flat(NSColor(rgb: (0.85, 0.88, 0.95)))
                p.opacity = 0.7
                p.position = v3(Double.random(in: -0.25...0.25), 0.05, Double.random(in: -0.25...0.25))
                emitter.addChildNode(p)
                p.runAction(.sequence([.group([.moveBy(x: CGFloat(Double.random(in: -0.4...0.4)), y: 0.5, z: CGFloat(Double.random(in: -0.4...0.4)), duration: 1.6), .scale(to: 2.2, duration: 1.6), .fadeOut(duration: 1.6)]), .removeFromParentNode()]))
            }
        }
        emitter.runAction(.repeatForever(.sequence([puff, .wait(duration: 0.25)])))
    }

    /// Lights flicker on when a dark office gets activity, and dim when it is left alone.
    func updatePower() {
        for station in fleet.stations.values {
            for room in station.rooms.values where !room.key.hasPrefix("kind:") && world.crewRoomInfo[roomKey(station, room)] == nil {
                let key = roomKey(station, room)
                let powered = Date().timeIntervalSince(room.lastActive) < StationController.powerWindow
                    || minions.values.contains { $0.station == station.name && $0.place == .room(room.key) && $0.busy }
                guard powered != (roomPower[key] ?? powered) else { continue }
                roomPower[key] = powered
                let full = NSColor(room.color)
                let base = room.key.hasPrefix("proj:") ? full.darker(0.32) : full
                let color = powered ? base : base.darker(0.2)
                for t in roomTiles[key] ?? [] {
                    t.geometry?.firstMaterial?.diffuse.contents = color
                    let flicker = SCNAction.sequence([.fadeOpacity(to: 0.35, duration: 0.05), .fadeOpacity(to: 1, duration: 0.08), .fadeOpacity(to: 0.5, duration: 0.05), .fadeOpacity(to: 1, duration: 0.12), .fadeOpacity(to: 0.7, duration: 0.05), .fadeOpacity(to: 1, duration: 0.1)])
                    t.runAction(flicker)
                }
                if powered { logEvent("\(room.name): lights on") }
            }
        }
    }

    /// Lightning from the monolith into each researching minion: a jagged bolt redrawn every frame.
    func updateBeams() {
        var live = Set<String>()
        for m in minions.values where m.place == .core && m.path.isEmpty && m.state == .settled && m.opacity > 0.5 && m.activity != .sleeping {
            guard let station = fleet.stations[m.station] else { continue }
            live.insert(m.id)
            let mp = station.monolithPosition
            let from = SIMD3(station.offset.x + mp.x, 1.9, station.offset.y + mp.y)
            let to = SIMD3(station.offset.x + m.pos.x, m.headHeight * 0.8, station.offset.y + m.pos.y)
            let bolt = beams[m.id] ?? {
                let group = SCNNode()
                for _ in 0..<5 {
                    let n = SCNNode(geometry: SCNBox(width: 0.03, height: 0.03, length: 1, chamferRadius: 0))
                    n.geometry!.firstMaterial = flat(NSColor(rgb: (0.75, 0.88, 1.0)))
                    group.addChildNode(n)
                }
                beamRoot.addChildNode(group)
                beams[m.id] = group
                return group
            }()
            var points = [from]
            for k in 1..<5 {
                let t = Double(k) / 5
                let jitter = 0.14
                points.append(from + (to - from) * t + SIMD3(Double.random(in: -jitter...jitter), Double.random(in: -jitter...jitter), Double.random(in: -jitter...jitter)))
            }
            points.append(to)
            for (i, seg) in bolt.childNodes.enumerated() {
                let a = points[i], b = points[i + 1]
                let d = b - a
                let len = max(0.001, (d.x * d.x + d.y * d.y + d.z * d.z).squareRoot())
                let mid = (a + b) / 2
                seg.position = v3(mid.x, mid.y, mid.z)
                seg.scale = SCNVector3(1, 1, len)
                seg.look(at: v3(b.x, b.y, b.z), up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, 1))
            }
            bolt.opacity = Double.random(in: 0.35...1.0)
        }
        for (id, n) in beams where !live.contains(id) { n.removeFromParentNode(); beams[id] = nil }
    }
}
