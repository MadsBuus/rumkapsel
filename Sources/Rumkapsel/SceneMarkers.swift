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
        // The airlock door posts stand in the walls; the way through is between them.
        for door in staticRoot.childNodes where (door.name ?? "").hasPrefix("airlockdoor:") {
            let stationName = String(door.name!.dropFirst("airlockdoor:".count))
            guard let st = fleet.stations[stationName] else { continue }
            for post in door.childNodes where post.name == "post" {
                let f = Double(Station.fine)
                let p = SIMD2(Double(door.position.x + post.position.x) - st.offset.x, Double(door.position.z + post.position.z) - st.offset.y)
                blocked[stationName, default: []].insert(Cell(x: Int((p.x * f).rounded()), y: Int((p.y * f).rounded())))
            }
        }
        // A hover pallet is a heavy thing standing on the floor: walks go round it, never through it.
        for (name, p) in pallets {
            let f = Double(Station.fine)
            let hx = Props.palletWidth / 2, hy = Props.palletDepth / 2
            for sx in Int(((p.spot.x - hx) * f).rounded())...Int(((p.spot.x + hx) * f).rounded()) {
                for sy in Int(((p.spot.y - hy) * f).rounded())...Int(((p.spot.y + hy) * f).rounded()) {
                    blocked[name, default: []].insert(Cell(x: sx, y: sy))
                }
            }
        }
        for st in fleet.stations.values { st.obstacles = blocked[st.name] ?? [] }
    }

    /// The yard reconciliation: the source's word against what stands on the floor, per repository.
    /// What can be carried is handed to carriers; counts are snapped only for the rest. It runs from
    /// the tick and before every redraw, never from the drawing itself: drawing decides nothing.
    func reconcileYards() {
        for station in fleet.stations.values where station.hasPad {
            let before = (station.stored, station.staged)
            for (root, info) in world.repoRoots where info.station == station.name {
                if let c = github.cargo(repoRoot: root), case .carryToDeck(let commands) = world.reconcile(station: station, repo: info.repo, root: root, cargo: c) {
                    handle(.carryToDeck(station: station.name, repo: info.repo, commands: commands))
                }
            }
            if before.0 != station.stored || before.1 != station.staged { markersDirty = true }
        }
    }

    /// Grey boxes pile up in an office as commits land; the pull request state colours them.
    ///
    /// A redraw adopts what already stands. An office whose boxes would come out the same is left
    /// alone; a numbered yard crate keeps its node and is moved only if its slot changed, downwards as
    /// a settle, otherwise put where the layout says; only what is new is built, and only what is gone
    /// is taken away. So a redraw in the middle of a carry disturbs nothing, and drawing the same
    /// floor twice costs nothing.
    func rebuildMarkers() {
        var keep: Set<ObjectIdentifier> = []
        var signatures: [String: String] = [:]
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
                    if (local.commits == 0 && dirtyFiles == 0) || world.truth.haulOrdered(office: key) { continue }   // nothing to show, or on its way to storage
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
                let cells = farCells(station, room)
                // Everything that shapes this office's boxes. The same signature as last time means the
                // same boxes: they stay as they are, cubes, package, shells and all.
                let signature = (["\(station.offset.x),\(station.offset.y)"] + cells.map { "\($0.x),\($0.y)" } + [
                    "\(count)", "\(ghosts)", pr?.state ?? "", pr?.reviewDecision ?? "", "\(pr?.isDraft ?? false)", pr?.checks ?? "",
                    "\(failing)", "\(packaged)", "\(undelivered.contains(key))", "\(packing.contains(key))", "\(world.isDusty(room))",
                ]).joined(separator: "|")
                let drawn = markerRoot.childNodes.filter { $0.name == "box:" + key }
                signatures[key] = signature
                if markerSignatures[key] == signature, !drawn.isEmpty {
                    drawn.forEach { keep.insert(ObjectIdentifier($0)) }
                    continue
                }
                drawn.forEach { $0.removeFromParentNode() }
                if packaged {
                    // One crate for the pull request. Its plate is a light: blinking while checks run, red when they
                    // fail, green when all is well; a closed one is red all over.
                    let cell = cells.first!
                    let size = 0.38   // one crate size everywhere: the cubes say how much work is in it
                    let closed = pr?.state == "CLOSED"
                    let checks = pr?.checks ?? ""
                    let light: NSColor = closed || failing || checks == "failure" ? NSColor(rgb: (0.95, 0.22, 0.22))
                        : checks == "pending" ? NSColor(rgb: (1.0, 0.72, 0.25)) : (status ?? NSColor(rgb: (0.4, 0.82, 0.45)))
                    let pkg = Props.package(color: closed ? NSColor(rgb: (0.75, 0.2, 0.2)) : NSColor(room.color).lighter(0.1), band: light, size: size,
                                            blink: checks == "pending" && !closed)
                    pkg.position = v3(station.offset.x + Double(cell.x), 0, station.offset.y + Double(cell.y))
                    pkg.name = "box:" + key
                    pkg.opacity = undelivered.contains(key) || packing.contains(key) ? 0 : 1
                    if failing {
                        let shell = SCNNode(geometry: SCNBox(width: size * 1.2, height: size, length: size * 1.2, chamferRadius: 0))
                        shell.geometry!.firstMaterial = flat(NSColor(rgb: (0.95, 0.2, 0.2)))
                        shell.opacity = 0.2
                        shell.runAction(.repeatForever(.sequence([.fadeOpacity(to: 0.55, duration: 0.7), .fadeOpacity(to: 0.15, duration: 0.9)])))
                        pkg.addChildNode(shell)
                    }
                    markerRoot.addChildNode(pkg)
                    keep.insert(ObjectIdentifier(pkg))
                    lastBoxCount[key] = 1
                    continue
                }
                // Deterministic clutter: sizes, turns and shades vary per box, and extras stack on top.
                var seed = UInt64(truncatingIfNeeded: key.hashValue) | 1
                func rnd() -> Double { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Double(seed >> 11) / Double(1 << 53) }
                var placedBoxes: [(pos: SIMD3<Double>, size: Double)] = []
                var newest: SCNNode?
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
                    if !ghost { newest = n }
                    if failing && !ghost {
                        let shell = SCNNode(geometry: SCNBox(width: size * 1.25, height: size * 1.25, length: size * 1.25, chamferRadius: 0))
                        shell.geometry!.firstMaterial = flat(NSColor(rgb: (0.95, 0.2, 0.2)))
                        shell.opacity = 0.2
                        shell.runAction(.repeatForever(.sequence([.fadeOpacity(to: 0.55, duration: 0.7), .fadeOpacity(to: 0.15, duration: 0.9)])))
                        shell.name = "box:" + key
                        n.addChildNode(shell)
                    }
                    markerRoot.addChildNode(n)
                    keep.insert(ObjectIdentifier(n))
                }
                // More commits than last time while the owner is in: the newest cube is not on the floor
                // yet. The worker carries it over on its head and stows it where it goes: a command.
                if let last = lastBoxCount[key], count > last, room.branch != nil, let box = newest,
                   let m = minions.values.first(where: { $0.station == station.name && $0.place == .room(room.key) && !$0.onJob && $0.carried == nil && $0.stowing == nil }) {
                    box.opacity = 0
                    let cube = SCNNode(geometry: SCNBox(width: 0.24, height: 0.24, length: 0.24, chamferRadius: 0))
                    cube.geometry!.firstMaterial = lit(color)
                    cube.position = v3(0, m.headHeight + 0.14, 0)
                    m.node.addChildNode(cube)
                    m.stowing = (cube, box)
                    start(m, .stow(office: room.key), announce: true)
                    let at = Cell(x: Int((Double(box.position.x) - station.offset.x).rounded()), y: Int((Double(box.position.z) - station.offset.y).rounded()))
                    walk(m, to: standCell(station, near: at))
                }
                lastBoxCount[key] = count + ghosts
            }
            // Crates on somebody's arms are left out by `yardLayout` itself: they are drawn once, in
            // the hands, for as long as the carry lasts.
            for area in ["storage", "deck"] where station.hasPad {
                let layout = world.yardLayout(station: station, area: area).filter { !$0.carried }   // held slots are not drawn
                let prefix = "\(area):\(station.name)|"
                var standing: [String: [SCNNode]] = [:]
                for n in markerRoot.childNodes where (n.name ?? "").hasPrefix(prefix) { standing[n.name!, default: []].append(n) }
                let wanted = Set(layout.filter { $0.number > 0 }.map { prefix + "\($0.repo)|\($0.number)" })
                /// True when nothing that still belongs in the rows stands between here and there in this
                /// column: only then is a drop a stack settling, rather than two crates changing places.
                func vacated(_ from: SIMD3<Double>, _ to: SIMD3<Double>) -> Bool {
                    standing.allSatisfy { name, nodes in
                        !wanted.contains(name) || nodes.allSatisfy { n in
                            let p = n.position
                            return !(abs(Double(p.x) - to.x) < 0.001 && abs(Double(p.z) - to.z) < 0.001
                                     && Double(p.y) < from.y - 0.05 && Double(p.y) > to.y - 0.05)
                        }
                    }
                }
                for slot in layout {
                    let name = prefix + "\(slot.repo)|\(slot.number)"
                    let spec = slot.cleared ? "tested" : "untested"
                    // A numbered crate already standing here keeps its node. It moves only if its slot
                    // did: down onto a freed level it settles over a beat; anywhere else it is put where
                    // the layout says, as a fresh node would have been.
                    if slot.number > 0, markerSignatures[name] == spec, let n = standing[name]?.first, !keep.contains(ObjectIdentifier(n)) {
                        keep.insert(ObjectIdentifier(n))
                        signatures[name] = spec
                        let at = SIMD3(Double(n.position.x), Double(n.position.y), Double(n.position.z))
                        let heading = crateMotions[ObjectIdentifier(n)]?.legs.last?.to ?? at
                        if abs(heading.x - slot.pos.x) > 0.001 || abs(heading.y - slot.pos.y) > 0.001 || abs(heading.z - slot.pos.z) > 0.001
                            || abs(Double(n.eulerAngles.y) - slot.yaw) > 0.001 {
                            stopCrate(n)
                            if abs(at.x - slot.pos.x) < 0.001, abs(at.z - slot.pos.z) < 0.001, at.y > slot.pos.y + 0.05, vacated(at, slot.pos) {
                                moveCrate(n, legs: [MotionLeg(to: slot.pos, seconds: Hands.settleSeconds)])
                            } else {
                                n.position = v3(slot.pos.x, slot.pos.y, slot.pos.z)
                                n.eulerAngles.y = slot.yaw
                            }
                        }
                        continue
                    }
                    let c = NSColor(fleet.color(forRepo: slot.repo))
                    // In the yard the light is off, except green with a sticker on a tested crate.
                    let pkg = Props.package(color: c.lighter(0.1), band: slot.cleared ? NSColor(rgb: (0.45, 0.95, 0.5)) : NSColor(rgb: (0.3, 0.32, 0.38)), size: 0.38, approved: slot.cleared)
                    pkg.position = v3(slot.pos.x, slot.pos.y, slot.pos.z)
                    pkg.eulerAngles.y = slot.yaw
                    pkg.name = name
                    pkg.enumerateChildNodes { c, _ in c.name = pkg.name }
                    markerRoot.addChildNode(pkg)
                    keep.insert(ObjectIdentifier(pkg))
                    if slot.number > 0 { signatures[name] = spec }
                }
            }
        }
        // Whatever the floor no longer calls for goes. A crate waiting for its carrier stays: it is
        // spoken for, and the layout has already left its slot alone.
        for n in markerRoot.childNodes where !keep.contains(ObjectIdentifier(n)) && n.name != "haul" { n.removeFromParentNode() }
        markerSignatures = signatures
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
        r.assigned = []   // a new stage orders its own cargo; what is already aboard stays aboard
        r.pending = []
        r.moaned = 0
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
                // A rocket never launches empty. The load is over when every crate this rocket was
                // given a carry for stands on the pad, and nothing of the repository is left on the
                // rows or on anyone's arms. A haul that is taking its time is waited out and said
                // out loud, never launched over. A release with no cargo at all — nothing was ever
                // assigned — goes as soon as the rows are clear, as it always did.
                // Unnumbered crates of a repository share one truth key, so the count aboard can
                // read short of what is really on the pad: the carries themselves are the second,
                // exact witness, and both have to agree before the rocket may go.
                let short = r.assigned.count - world.truth.aboard(station: r.station, repo: r.repo)
                guard padClear(r), r.pending.isEmpty, short <= 0 else {
                    if clock - r.since > 90, clock - r.moaned > 30 {
                        r.moaned = clock
                        logEvent("\(r.repo): the rocket holds, \(max(short, 1)) crate\(max(short, 1) == 1 ? "" : "s") still to come aboard")
                    }
                    continue
                }
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
            r.assigned.insert(crate.key)   // ordered aboard: the launch waits for it
            r.pending.insert(command.id)
            carry(command, node: b) { [weak self, weak r] in
                guard let self else { return }
                r?.pending.remove(command.id)
                // Aboard by hand: the rows may not draw it again until the board says it has shipped.
                world.landed(station: station, repo: repo, number: crate.number, in: .pad)
                // Through the hatch into the hold: up off the floor, in toward the hull, shrinking as it
                // goes, since the rocket is far too small for it. The hatch opens for it and closes after.
                let at = SIMD3(Double(b.position.x), Double(b.position.y), Double(b.position.z))
                let hull = SIMD3(at.x, at.y + 0.22, at.z - 0.45)
                if let hatch = r?.node.childNode(withName: "hatch", recursively: true) {
                    hatch.runAction(.sequence([.scale(to: 0.05, duration: 0.2), .wait(duration: 0.8), .scale(to: 1, duration: 0.2)]))
                }
                moveCrate(b, legs: [MotionLeg(to: SIMD3(at.x, at.y + 0.22, at.z), seconds: 0.3, ease: .easeOut),
                                    MotionLeg(to: hull, seconds: 0.6, ease: .easeIn, scale: 0.02)]) { b.removeFromParentNode() }
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
            guard let station = fleet.stations[m.station], station.cells(of: .core).contains(m.cell) else { continue }   // at the monolith, not out on a chore
            live.insert(m.id)
            let mp = station.monolithPosition
            let from = SIMD3(station.offset.x + mp.x, 1.9, station.offset.y + mp.y)
            let to = SIMD3(station.offset.x + m.pos.x, m.headHeight * 0.8, station.offset.y + m.pos.y)
            // A cone of light from the monolith down onto whoever is asking it, as the game's research went.
            let cone = beams[m.id] ?? {
                let n = SCNNode(geometry: faceted(SCNCone(topRadius: 0.05, bottomRadius: 0.32, height: 1)))
                n.geometry!.firstMaterial = flat(NSColor(rgb: (0.75, 0.88, 1.0)))
                n.geometry!.firstMaterial?.transparency = 0.22
                n.geometry!.firstMaterial?.writesToDepthBuffer = false
                n.geometry!.firstMaterial?.isDoubleSided = true
                beamRoot.addChildNode(n)
                beams[m.id] = n
                return n
            }()
            let d = to - from
            let len = max(0.001, (d.x * d.x + d.y * d.y + d.z * d.z).squareRoot())
            let mid = (from + to) / 2
            cone.position = v3(mid.x, mid.y, mid.z)
            cone.scale = SCNVector3(1, len, 1)
            cone.look(at: v3(to.x, to.y, to.z), up: SCNVector3(0, 0, 1), localFront: SCNVector3(0, -1, 0))
            cone.opacity = 0.8 + 0.2 * sin(clock * 3 + Double(m.bobPhase))
        }
        for (id, n) in beams where !live.contains(id) { n.removeFromParentNode(); beams[id] = nil }
    }
}
