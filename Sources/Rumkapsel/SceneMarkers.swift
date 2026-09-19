// Everything that comes and goes on top of the floor: crates, cones, rockets, steam, power and beams.

import AppKit
import SceneKit

extension StationController {
    /// Tells each station what is standing on its floor, so walks thread between the props.
    func refreshObstacles() {
        var blocked: [String: Set<Cell>] = [:]
        func mark(_ station: String, _ node: SCNNode, offset: SIMD2<Double>, into: inout [String: Set<Cell>]) {
            let (lo, hi) = node.boundingBox
            let p = SIMD2(Double(node.position.x) - offset.x, Double(node.position.z) - offset.y)
            let r = Double(max(hi.x - lo.x, hi.z - lo.z)) / 2 * 0.8
            let f = Double(Station.fine)
            for sx in Int(((p.x - r) * f).rounded())...Int(((p.x + r) * f).rounded()) {
                for sy in Int(((p.y - r) * f).rounded())...Int(((p.y + r) * f).rounded()) { into[station, default: []].insert(Cell(x: sx, y: sy)) }
            }
        }
        func mark(_ station: String, _ node: SCNNode, offset: SIMD2<Double>) { mark(station, node, offset: offset, into: &blocked) }
        for n in markerRoot.childNodes {
            guard let name = n.name, let colon = name.firstIndex(of: ":"), let bar = name.firstIndex(of: "|"), colon < bar else { continue }
            let stationName = String(name[name.index(after: colon)..<bar])
            guard let st = fleet.stations[stationName] else { continue }
            mark(stationName, n, offset: st.offset)
        }
        for m in minions.values {
            for p in m.pyramids + m.queuedCones { mark(m.station, p, offset: .zero) }
        }
        // A rocket on its pad is walked round, never through: its hull is an obstacle, the hull alone,
        // not the fins, the hold's ring or the steam, so its foot stays reachable for loading.
        let rocketKeys = simulation.rockets.keys.sorted()
        for (key, r) in simulation.rockets {
            guard let st = fleet.stations[r.station] else { continue }
            let at = padPosition(station: st, slot: (rocketKeys.firstIndex(of: key) ?? 0) % 4)
            let p = SIMD2(Double(at.x) - st.offset.x, Double(at.z) - st.offset.y)
            let hull = 0.3, f = Double(Station.fine)
            for sx in Int(((p.x - hull) * f).rounded())...Int(((p.x + hull) * f).rounded()) {
                for sy in Int(((p.y - hull) * f).rounded())...Int(((p.y + hull) * f).rounded()) { blocked[r.station, default: []].insert(Cell(x: sx, y: sy)) }
            }
        }
        // Furniture and fixtures: anything standing on a room's floor that is not a tile. Built once per
        // static redraw and read from there: nothing on the static root moves between redraws.
        if furnitureObstaclesAt != staticRoot.childNodes.count {
            furnitureObstaclesAt = staticRoot.childNodes.count
            var furniture: [String: Set<Cell>] = [:]
            for n in staticRoot.childNodes where n.geometry != nil && !(n.geometry is SCNPlane) && (n.name ?? "").hasPrefix("room:") {
                let key = String(n.name!.dropFirst(5))
                guard let bar = key.firstIndex(of: "|"), let st = fleet.stations[String(key[..<bar])] else { continue }
                mark(st.name, n, offset: st.offset, into: &furniture)
            }
            furnitureObstacles = furniture
        }
        for (station, cells) in furnitureObstacles { blocked[station, default: []].formUnion(cells) }
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
        // A hover pallet is not here: it slides while it is pushed, and this set is only as fresh as the
        // last redraw of the markers. The simulation blocks its footprint where it stands now, in `crowd`.
        for st in fleet.stations.values { st.obstacles = blocked[st.name] ?? [] }
    }

    /// Where an office's crate stands: a tile of its own, clear of the floor writing and of any cone in
    /// the office, as far from the door as the office allows. Chosen once and kept, so a later redraw
    /// never moves a crate somebody has already looked at; it is asked for again only if the office no
    /// longer has that tile.
    func packageCell(_ station: Station, _ room: Room) -> Cell {
        let key = roomKey(station, room)
        if let held = packageCells[key], room.cells.contains(held) { return held }
        let cells = farCells(station, room)
        var coned: Set<Cell> = []
        for m in minions.values where m.station == station.name {
            for n in m.pyramids + m.queuedCones {
                let x = Double(n.worldPosition.x) - station.offset.x
                let z = Double(n.worldPosition.z) - station.offset.y
                coned.insert(Cell(x: Int(x.rounded()), y: Int(z.rounded())))
            }
        }
        let cell = cells.first { !coned.contains($0) } ?? cells.first!
        packageCells[key] = cell
        return cell
    }

    /// A standing crate told what its pull request says now: the plate's colour and its blink, and the
    /// shell round a failing one. Everything else about a crate is settled when it is built.
    private func relight(_ pkg: SCNNode, light: NSColor, blink: Bool, failing: Bool, size: Double) {
        if let plate = pkg.childNodes.first(where: { $0.geometry?.name == Props.plateName }) {
            plate.geometry?.firstMaterial = flat(light)
            let blinking = plate.action(forKey: "blink") != nil
            if blink && !blinking { plate.runAction(Props.blinking(), forKey: "blink") }
            if !blink && blinking { plate.removeAction(forKey: "blink"); plate.opacity = 1 }
        }
        let shell = pkg.childNodes.first { $0.geometry?.name == Props.shellName }
        if failing, shell == nil {
            let s = SCNNode(geometry: SCNBox(width: size * 1.2, height: size, length: size * 1.2, chamferRadius: 0))
            s.geometry!.name = Props.shellName
            s.geometry!.firstMaterial = flat(NSColor(rgb: (0.95, 0.2, 0.2)))
            s.opacity = 0.2
            s.runAction(.repeatForever(.sequence([.fadeOpacity(to: 0.55, duration: 0.7), .fadeOpacity(to: 0.15, duration: 0.9)])))
            pkg.addChildNode(s)
        } else if !failing, let s = shell {
            s.removeFromParentNode()
        }
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
        // Stage changes waiting on the floor, a crate not yet down in storage, a pallet still out, are
        // tried again here, on the tick, as the reconciliation always was; a pass is not what they wait for.
        for e in world.stationEvents() { handle(e) }
        for station in fleet.stations.values where station.hasPad {
            // A storage-to-deck carry whose crate the board has since put back in storage is off.
            for (id, job) in cargo {
                guard case .carry(let crate, let from, _) = job.command.kind, crate.station == station.name,
                      let row = station.ledger[crate.repo, crate.number],
                      row.heading == .deck, row.placed == .storage, row.wanted == .storage, row.movedAt == nil else { continue }
                simulation.cancelCarry(id, backTo: from)
            }
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
                let boxOpacity = 1.0
                if room.branch == nil {
                    guard let cb = world.crewBoxes[key] ?? world.peerBoxes[key] else { continue }
                    if world.haulOrdered(office: key) { continue }   // on its way to storage: drawn once, on the arms
                    count = min(16, max(1, cb.count))
                    // A teammate's pull request is a crate with its sticker; pushes before a PR are cubes.
                    // A peer's pull request, as they said it, when GitHub has not told us about it here.
                    let peer = world.crewRoomInfo[key] == nil ? world.peerPull(key) : nil
                    let prNumber = world.crewPull(key) ?? peer?.pull
                    let state = world.isClosed(key) ? "CLOSED" : (peer?.pullState ?? (prNumber != nil ? "OPEN" : cb.state))
                    pr = PullRequest(number: prNumber ?? 0, title: "", state: state, reviewDecision: peer?.review ?? "", isDraft: false, url: "")
                    pr?.checks = peer?.checks ?? ""
                    packaged = prNumber != nil || world.isClosed(key)
                } else {
                    let local = world.localState(room)
                    let dirtyFiles = room.worktree.map { github.dirtyFiles(worktree: $0) } ?? 0
                    if (local.commits == 0 && dirtyFiles == 0) || world.haulOrdered(office: key) { continue }   // nothing to show, or on its way to storage
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
                if packaged {
                    // One crate for the pull request, and it stands for as long as the pull request does.
                    // Commits landing, checks turning, a review coming in only re-light the crate that is
                    // already there: it is never taken away and built again, or it would blink out of the
                    // office every time GitHub answered, and the office would look packed twice over.
                    let cell = packageCell(station, room)
                    let size = 0.38   // one crate size everywhere: the cubes say how much work is in it
                    let closed = pr?.state == "CLOSED"
                    let checks = pr?.checks ?? ""
                    let light: NSColor = closed || failing || checks == "failure" ? NSColor(rgb: (0.95, 0.22, 0.22))
                        : checks == "pending" ? NSColor(rgb: (1.0, 0.72, 0.25)) : (status ?? NSColor(rgb: (0.4, 0.82, 0.45)))
                    let blink = checks == "pending" && !closed
                    // What a standing crate cannot be re-lit into, and what it can.
                    let mine = world.isMine(office: key)   // strapped in white from the moment it is packed, like yours in the rows
                    let built = "\(closed)|\(mine)|\(room.color.r),\(room.color.g),\(room.color.b)"
                    signatures[key] = "package"
                    var pkg = packages[key]
                    if let p = pkg, p.parent == nil || packageBuilt[key] != built { p.removeFromParentNode(); packages[key] = nil; pkg = nil }
                    if pkg == nil {
                        let p = Props.package(color: closed ? NSColor(rgb: (0.75, 0.2, 0.2)) : NSColor(room.color), band: light, size: size, blink: blink, mine: mine)
                        p.name = "box:" + key
                        markerRoot.addChildNode(p)
                        packages[key] = p
                        packageBuilt[key] = built
                        pkg = p
                    }
                    guard let p = pkg else { continue }
                    // The cubes it was packed from go; the crate itself stays.
                    drawn.filter { $0 !== p }.forEach { $0.removeFromParentNode() }
                    let at = v3(station.offset.x + Double(cell.x), 0, station.offset.y + Double(cell.y))
                    if p.position.x != at.x || p.position.z != at.z { p.position = at }
                    relight(p, light: light, blink: blink, failing: failing, size: size)
                    p.opacity = undelivered.contains(key) || packing.contains(key) ? 0 : 1
                    keep.insert(ObjectIdentifier(p))
                    lastBoxCount[key] = 1
                    continue
                }
                signatures[key] = signature
                if markerSignatures[key] == signature, !drawn.isEmpty {
                    drawn.forEach { keep.insert(ObjectIdentifier($0)) }
                    continue
                }
                drawn.forEach { $0.removeFromParentNode() }
                // Deterministic clutter: sizes, turns and shades vary per box, and extras stack on top.
                var seed = stableHash(key) | 1
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
                   let m = minions.values.first(where: { $0.station == station.name && $0.place == .room(room.key) && !$0.onJob && !$0.hasLoad && $0.stowing == nil }) {
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
            for area in ["storage", "deck", "decon"] where station.hasPad {
                let layout = world.yardLayout(station: station, area: area).filter { !$0.carried }   // held slots are not drawn
                let prefix = "\(area):\(station.name)|"
                var standing: [String: [SCNNode]] = [:]
                for n in markerRoot.childNodes where (n.name ?? "").hasPrefix(prefix) { standing[n.name!, default: []].append(n) }
                let wanted = Set(layout.map { prefix + "\($0.repo)|\($0.number)" })
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
                    let spec = (slot.cleared ? "tested" : "untested") + (slot.alien ? " alien" : "") + (slot.mine ? " mine" : "")
                    // A crate already standing here keeps its node. It moves only if its slot did: down
                    // onto a freed level it settles over a beat; anywhere else it is put where the
                    // layout says, as a fresh node would have been.
                    if markerSignatures[name] == spec, let n = standing[name]?.first, !keep.contains(ObjectIdentifier(n)) {
                        keep.insert(ObjectIdentifier(n))
                        signatures[name] = spec
                        let at = SIMD3(Double(n.position.x), Double(n.position.y), Double(n.position.z))
                        let heading = crateMotions[ObjectIdentifier(n)]?.legs.last?.to ?? at
                        if abs(heading.x - slot.pos.x) > 0.001 || abs(heading.y - slot.pos.y) > 0.001 || abs(heading.z - slot.pos.z) > 0.001
                            || abs(Double(n.eulerAngles.y) - slot.yaw) > 0.001 {
                            stopCrate(n)
                            // In decon a whole stack drops together when one is pulled out from under it.
                            if abs(at.x - slot.pos.x) < 0.001, abs(at.z - slot.pos.z) < 0.001, at.y > slot.pos.y + 0.05, area == "decon" || vacated(at, slot.pos) {
                                moveCrate(n, legs: [MotionLeg(to: slot.pos, seconds: Hands.settleSeconds, ease: .easeIn)])
                            } else {
                                n.position = v3(slot.pos.x, slot.pos.y, slot.pos.z)
                                n.eulerAngles.y = slot.yaw
                            }
                        }
                        continue
                    }
                    // Of unknown origin: grey wherever it stands, a bot's, not a repository's work, with a
                    // tint of the repository it came for, so a bump for ios still reads as ios.
                    let c = slot.alien ? Palette.alien.darker(0.3).mixed(with: NSColor(fleet.color(forRepo: slot.repo)).darker(0.3), 0.35) : NSColor(fleet.color(forRepo: slot.repo))
                    // In the yard the light is off, except green with a sticker on a tested crate, and
                    // the unscreened green of decon on what still waits there.
                    let band = area == "decon" ? Palette.alienLight.darker(0.3) : slot.cleared ? NSColor(rgb: (0.45, 0.95, 0.5)) : NSColor(rgb: (0.3, 0.32, 0.38))
                    // In decon it is smaller and darker than a crate of ours, to take less of the eye; cleared
                    // into storage it grows to a crate's size, since a crate is what it is from then on.
                    let pkg = Props.package(color: c, band: band, size: area == "decon" ? 0.3 : 0.38, approved: slot.cleared && !slot.alien, mine: slot.mine)
                    pkg.position = v3(slot.pos.x, slot.pos.y, slot.pos.z)
                    pkg.eulerAngles.y = slot.yaw
                    pkg.name = name
                    pkg.enumerateChildNodes { c, _ in c.name = pkg.name }
                    markerRoot.addChildNode(pkg)
                    // Fresh through the hatch: it starts at hatch height and floats down onto its pile, low gravity.
                    if incoming.remove(name) != nil {
                        pkg.position.y = CGFloat(slot.pos.y + 1.2)
                        moveCrate(pkg, legs: [MotionLeg(to: slot.pos, seconds: Hands.settleSeconds * 1.5, ease: .easeIn)])
                    }
                    keep.insert(ObjectIdentifier(pkg))
                    signatures[name] = spec
                }
            }
        }
        // Whatever the floor no longer calls for goes. A crate waiting for its carrier stays: it is
        // spoken for, and the layout has already left its slot alone.
        for n in markerRoot.childNodes where !keep.contains(ObjectIdentifier(n)) && n.name != "haul" { n.removeFromParentNode() }
        packages = packages.filter { $0.value.parent != nil }
        packageBuilt = packageBuilt.filter { packages[$0.key] != nil }
        markerSignatures = signatures
        refreshObstacles()
    }

    /// Cargo waiting with no rocket yet: a faint ring in the repo colour on the pad, a release is due.
    func rebuildDueRings() {
        if ringRoot.parent == nil { propRoot.addChildNode(ringRoot) }
        ringRoot.childNodes.forEach { $0.removeFromParentNode() }
        for station in fleet.stations.values where station.hasPad {
            let waiting = Set(station.stored.keys).union(station.staged.keys)
                .filter { repo in ((world.stagingIsDeck(station: station.name, repo: repo) ? station.staged : station.stored)[repo] ?? 0) > 0 }.sorted()
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

    /// Something came through decon's hatch: the light over it flashes, and that is all the fuss it gets.
    func hatchBlink(station name: String) {
        guard let light = hatchLights[name] else { return }
        light.removeAllActions()
        let on = SCNAction.run { n in n.geometry?.firstMaterial?.diffuse.contents = Palette.alienLight.lighter(0.3) }
        let off = SCNAction.run { n in n.geometry?.firstMaterial?.diffuse.contents = Palette.alienLight.darker(0.35) }
        light.runAction(.sequence([on, .wait(duration: 0.3), off, .wait(duration: 0.3), on, .wait(duration: 0.3), off, .wait(duration: 0.3), on, .wait(duration: 0.6), off]))
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
                    Looks.current.tint(tile: t, color)
                    let flicker = SCNAction.sequence([.fadeOpacity(to: 0.35, duration: 0.05), .fadeOpacity(to: 1, duration: 0.08), .fadeOpacity(to: 0.5, duration: 0.05), .fadeOpacity(to: 1, duration: 0.12), .fadeOpacity(to: 0.7, duration: 0.05), .fadeOpacity(to: 1, duration: 0.1)])
                    t.runAction(flicker)
                }
                if powered { logEvent("\(room.name): \(Words.current.lightsOn)") }
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
