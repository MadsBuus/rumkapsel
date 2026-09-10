// The station as it stands: floor tiles, walls, outlines and the names written on the floor.

import AppKit
import SceneKit

extension StationController {
    private func owner(_ station: Station, _ c: Cell) -> String? {
        if station.hangarCells.contains(c) { return "kind:hangar" }
        if station.storageCells.contains(c) { return "kind:storage" }
        if station.deckCells.contains(c) && !ConfigStore.shared.current.stagingBranch.isEmpty { return "kind:deck" }
        if station.padCells.contains(c) { return "kind:pad" }
        if station.coreCells.contains(c) || station.isCorridor(c) { return "corridor" }
        return station.room(at: c)?.key
    }

    private func joined(_ station: Station, _ a: Cell, _ b: Cell, _ key: String) -> Bool {
        owner(station, b) == key || openEdges.contains("\(station.name):\(a.x),\(a.y)|\(b.x),\(b.y)")
    }

    /// Full-size floor tile; borders are drawn separately as strips so corners meet cleanly.
    @discardableResult
    private func addTile(station: Station, cell: Cell, owner key: String, color: NSColor, name: String, into parent: SCNNode? = nil) -> SCNNode {
        let root = parent ?? staticRoot
        let plane = SCNPlane(width: 1.0, height: 1.0)
        plane.firstMaterial = flat(color)
        let n = SCNNode(geometry: plane)
        n.eulerAngles.x = -.pi / 2
        n.position = v3(station.offset.x + Double(cell.x), 0, station.offset.y + Double(cell.y))
        n.name = name
        root.addChildNode(n)
        // Dark border toward any neighbouring floor of another owner, extended past the corners.
        let g = 0.075
        let sides: [(Cell, SIMD2<Double>, Bool)] = [
            (Cell(x: cell.x - 1, y: cell.y), SIMD2(-0.5, 0), true), (Cell(x: cell.x + 1, y: cell.y), SIMD2(0.5, 0), true),
            (Cell(x: cell.x, y: cell.y - 1), SIMD2(0, -0.5), false), (Cell(x: cell.x, y: cell.y + 1), SIMD2(0, 0.5), false),
        ]
        for (nb, off, vertical) in sides {
            guard let other = owner(station, nb), other != key, !joined(station, cell, nb, key) else { continue }
            let strip = SCNPlane(width: vertical ? g * 2 : 1 + g * 2, height: vertical ? 1 + g * 2 : g * 2)
            strip.firstMaterial = flat(Palette.void)
            let b = SCNNode(geometry: strip)
            b.eulerAngles.x = -.pi / 2
            b.position = v3(station.offset.x + Double(cell.x) + off.x, 0.002, station.offset.y + Double(cell.y) + off.y)
            b.name = name
            b.opacity = n.opacity
            root.addChildNode(b)
        }
        return n
    }

    /// Dashed outline around a room's footprint, the game's look for a room under construction.
    private func outline(station: Station, room: Room) -> SCNNode {
        let group = SCNNode()
        let color = NSColor(room.color)
        let dash = 0.3, gap = 0.18, thick = 0.06
        func addEdge(from a: SIMD2<Double>, to b: SIMD2<Double>) {
            let d = b - a
            let len = (d.x * d.x + d.y * d.y).squareRoot()
            let dir = d / len
            var t = 0.08
            while t + dash <= len + 0.001 {
                let mid = a + dir * (t + dash / 2)
                let n = SCNNode(geometry: SCNPlane(width: dash, height: thick))
                n.geometry!.firstMaterial = flat(color)
                n.eulerAngles = SCNVector3(-Double.pi / 2, 0, 0)
                n.eulerAngles.y = dir.x == 0 ? .pi / 2 : 0
                n.position = v3(station.offset.x + mid.x, 0.012, station.offset.y + mid.y)
                group.addChildNode(n)
                t += dash + gap
            }
        }
        let cells = Set(room.cells)
        for c in room.cells {
            let x = Double(c.x), y = Double(c.y)
            if !cells.contains(Cell(x: c.x, y: c.y - 1)) { addEdge(from: SIMD2(x - 0.5, y - 0.5), to: SIMD2(x + 0.5, y - 0.5)) }
            if !cells.contains(Cell(x: c.x, y: c.y + 1)) { addEdge(from: SIMD2(x - 0.5, y + 0.5), to: SIMD2(x + 0.5, y + 0.5)) }
            if !cells.contains(Cell(x: c.x - 1, y: c.y)) { addEdge(from: SIMD2(x - 0.5, y - 0.5), to: SIMD2(x - 0.5, y + 0.5)) }
            if !cells.contains(Cell(x: c.x + 1, y: c.y)) { addEdge(from: SIMD2(x + 0.5, y - 0.5), to: SIMD2(x + 0.5, y + 0.5)) }
        }
        return group
    }

    func rebuildStatic() {
        fleet.arrange()
        staticRoot.childNodes.forEach { $0.removeFromParentNode() }
        roomTiles = [:]
        openEdges = []
        for station in fleet.stations.values {
            for room in station.rooms.values {
                guard let d = station.doorCell(of: room.key), let o = station.doorOutside(of: room.key) else { continue }
                openEdges.insert("\(station.name):\(d.x),\(d.y)|\(o.x),\(o.y)")
                openEdges.insert("\(station.name):\(o.x),\(o.y)|\(d.x),\(d.y)")
            }
            for (a, b) in station.yardDoorways + (station.airlockHatch.map { [($0.inside, $0.bay)] } ?? []) {
                openEdges.insert("\(station.name):\(a.x),\(a.y)|\(b.x),\(b.y)")
                openEdges.insert("\(station.name):\(b.x),\(b.y)|\(a.x),\(a.y)")
            }
        }

        for station in fleet.stations.values {
            let anchor = stationAnchors[station.name] ?? { let n = SCNNode(); propRoot.addChildNode(n); stationAnchors[station.name] = n; return n }()
            anchor.position = v3(station.offset.x, 0, station.offset.y)
            let oldSpine = knownSpine[station.name] ?? station.spineHalfLength
            knownSpine[station.name] = station.spineHalfLength
            for c in station.corridorCells + station.coreCells {
                let t = addTile(station: station, cell: c, owner: "corridor", color: Palette.corridor, name: "station:" + station.name)
                // New corridor beyond the old length is built tile by tile, outward.
                let reach = max(abs(c.x), abs(c.y))
                if reach > oldSpine, station.isCorridor(c) {   // the core sits past the spine's end; it is never new
                    t.opacity = 0
                    t.runAction(.sequence([.wait(duration: 0.3 * Double(reach - oldSpine)), .fadeIn(duration: 0.5)]))
                }
            }
            for c in station.hangarCells {
                addTile(station: station, cell: c, owner: "kind:hangar", color: NSColor(Colors.hangar), name: "hangar:" + station.name)
            }
            for c in station.padCells {
                addTile(station: station, cell: c, owner: "kind:pad", color: NSColor(rgb: (0.24, 0.26, 0.32)), name: "pad:" + station.name)
            }
            for c in station.storageCells {
                addTile(station: station, cell: c, owner: "kind:storage", color: NSColor(rgb: (0.20, 0.22, 0.30)), name: "storage:" + station.name)
            }
            if !ConfigStore.shared.current.stagingBranch.isEmpty {
                for c in station.deckCells {
                    addTile(station: station, cell: c, owner: "kind:deck", color: NSColor(rgb: (0.22, 0.27, 0.30)), name: "deck:" + station.name)
                }
            }
            if station.hasPad {
                let pc = station.padCenter
                let ring = SCNNode(geometry: faceted(SCNTube(innerRadius: 1.45, outerRadius: 1.55, height: 0.01)))
                ring.geometry!.firstMaterial = flat(NSColor(rgb: (0.45, 0.48, 0.58)))
                ring.position = v3(station.offset.x + pc.x, 0.006, station.offset.y + pc.y)
                staticRoot.addChildNode(ring)
            }
            if let lounge = station.rooms["kind:lounge"] {
                let cx = Double(lounge.cells.map(\.x).reduce(0, +)) / Double(lounge.cells.count)
                let cy = Double(lounge.cells.map(\.y).reduce(0, +)) / Double(lounge.cells.count)
                // A low coffee table: a thin top on two side panels, with a magazine left on it.
                let table = SCNNode(geometry: SCNBox(width: 0.9, height: 0.03, length: 0.4, chamferRadius: 0))
                table.geometry!.firstMaterial = lit(NSColor(rgb: (0.55, 0.42, 0.3)))
                table.position = v3(station.offset.x + cx, 0.2, station.offset.y + cy)
                for lx in [-0.4, 0.4] {
                    let panel = SCNNode(geometry: SCNBox(width: 0.03, height: 0.19, length: 0.34, chamferRadius: 0))
                    panel.geometry!.firstMaterial = lit(NSColor(rgb: (0.42, 0.32, 0.24)))
                    panel.position = v3(lx, -0.1, 0)
                    table.addChildNode(panel)
                }
                let magazine = SCNNode(geometry: SCNBox(width: 0.16, height: 0.01, length: 0.22, chamferRadius: 0))
                magazine.geometry!.firstMaterial = flat(NSColor(rgb: (0.85, 0.85, 0.8)))
                magazine.position = v3(0.15, 0.02, 0.02)
                magazine.eulerAngles.y = 0.3
                table.addChildNode(magazine)
                table.name = "room:" + roomKey(station, lounge)
                staticRoot.addChildNode(table)
                let lxs = lounge.cells.map(\.x)
                for c in station.couches {
                    let along = c.x < Double(lxs.min()!) - 0.1 || c.x > Double(lxs.max()!) + 0.1   // side walls run along z, the far wall along x
                    let couch = SCNNode(geometry: SCNBox(width: along ? 0.3 : 0.8, height: 0.18, length: along ? 0.8 : 0.3, chamferRadius: 0.02))
                    couch.geometry!.firstMaterial = lit(NSColor(rgb: (0.62, 0.45, 0.4)))
                    couch.position = v3(station.offset.x + c.x, 0.09, station.offset.y + c.y)
                    couch.name = "room:" + roomKey(station, lounge)
                    let back = SCNNode(geometry: SCNBox(width: along ? 0.08 : 0.8, height: 0.22, length: along ? 0.8 : 0.08, chamferRadius: 0.02))
                    back.geometry!.firstMaterial = couch.geometry!.firstMaterial
                    back.position = v3(along ? (c.x < cx ? -0.11 : 0.11) : 0, 0.16, along ? 0 : 0.11)
                    couch.addChildNode(back)
                    staticRoot.addChildNode(couch)
                }
                // A potted plant in one corner and a low shelf in another: somewhere to look at.
                let xs = lounge.cells.map(\.x), ys = lounge.cells.map(\.y)
                // A square pot with a few flat leaves fanned out on a thin stem.
                let pot = SCNNode(geometry: SCNBox(width: 0.2, height: 0.16, length: 0.2, chamferRadius: 0))
                pot.geometry!.firstMaterial = lit(NSColor(rgb: (0.75, 0.5, 0.35)))
                pot.position = v3(station.offset.x + Double(xs.min()!) - 0.28, 0.08, station.offset.y + Double(ys.min()!) - 0.28)
                let stem = SCNNode(geometry: SCNBox(width: 0.03, height: 0.3, length: 0.03, chamferRadius: 0))
                stem.geometry!.firstMaterial = lit(NSColor(rgb: (0.25, 0.45, 0.28)))
                stem.position = v3(0, 0.22, 0)
                pot.addChildNode(stem)
                for (i, (w, yaw, tiltZ)) in [(0.22, 0.0, 0.6), (0.2, 2.1, 0.5), (0.24, 4.2, 0.7), (0.16, 1.0, -0.2)].enumerated() {
                    let leaf = SCNNode(geometry: SCNBox(width: w, height: 0.02, length: 0.09, chamferRadius: 0))
                    leaf.geometry!.firstMaterial = lit(NSColor(rgb: (0.3 + Double(i) * 0.03, 0.62, 0.38)))
                    leaf.pivot = SCNMatrix4MakeTranslation(-w / 2, 0, 0)
                    leaf.position = v3(0, 0.3 + Double(i) * 0.03, 0)
                    leaf.eulerAngles = SCNVector3(0, yaw, tiltZ)
                    pot.addChildNode(leaf)
                }
                pot.name = "room:" + roomKey(station, lounge)
                staticRoot.addChildNode(pot)
                let shelf = SCNNode(geometry: SCNBox(width: 0.7, height: 0.32, length: 0.2, chamferRadius: 0.01))
                shelf.geometry!.firstMaterial = lit(NSColor(rgb: (0.5, 0.4, 0.32)))
                shelf.position = v3(station.offset.x + Double(xs.max()!), 0.16, station.offset.y + Double(ys.min()!) - 0.32)
                for i in 0..<4 {
                    let book = SCNNode(geometry: SCNBox(width: 0.08, height: 0.2, length: 0.14, chamferRadius: 0))
                    book.geometry!.firstMaterial = lit(NSColor(Colors.repos[i % Colors.repos.count]))
                    book.position = v3(-0.22 + Double(i) * 0.13, 0.26, 0)
                    shelf.addChildNode(book)
                }
                shelf.name = "room:" + roomKey(station, lounge)
                staticRoot.addChildNode(shelf)
            }
            if let airlock = station.rooms["kind:airlock"] {
                // A round hatch standing at the far end, ringed in a warning stripe.
                let cells = airlock.cells
                let door = station.doorCell(of: airlock.key) ?? cells[0]
                let far = station.airlockHatch?.inside ?? cells.max { (abs($0.x - door.x) + abs($0.y - door.y)) < (abs($1.x - door.x) + abs($1.y - door.y)) } ?? cells[0]
                let out = station.airlockHatch?.bay ?? Cell(x: far.x + (far.x - door.x), y: far.y + (far.y - door.y))
                let hatch = SCNNode(geometry: faceted(SCNTube(innerRadius: 0.22, outerRadius: 0.32, height: 0.08)))
                hatch.geometry!.firstMaterial = lit(NSColor(rgb: (0.75, 0.62, 0.25)))
                let dx = out.x - far.x, dy = out.y - far.y
                hatch.eulerAngles = dx != 0 ? SCNVector3(0, 0, Double.pi / 2) : SCNVector3(Double.pi / 2, 0, 0)
                hatch.position = v3(station.offset.x + Double(far.x) + Double(dx) * 0.42, 0.42, station.offset.y + Double(far.y) + Double(dy) * 0.42)
                let pane = SCNNode(geometry: faceted(SCNCylinder(radius: 0.22, height: 0.04)))
                pane.geometry!.firstMaterial = flat(NSColor(rgb: (0.12, 0.14, 0.2)))
                hatch.addChildNode(pane)
                hatch.name = "room:" + roomKey(station, airlock)
                staticRoot.addChildNode(hatch)
            }
            if let bath = station.rooms["kind:bath"] {
                // A toilet in one corner and a shower post in the other.
                let cells = bath.cells.sorted { ($0.y, $0.x) < ($1.y, $1.x) }
                let tc = cells.first!, sc = cells.last!
                let bowl = SCNNode(geometry: faceted(SCNCylinder(radius: 0.13, height: 0.2), 4))
                bowl.geometry!.firstMaterial = lit(NSColor(rgb: (0.92, 0.93, 0.95)))
                bowl.position = v3(station.offset.x + Double(tc.x) - 0.22, 0.1, station.offset.y + Double(tc.y) - 0.22)
                let tank = SCNNode(geometry: SCNBox(width: 0.24, height: 0.3, length: 0.1, chamferRadius: 0.01))
                tank.geometry!.firstMaterial = bowl.geometry!.firstMaterial
                tank.position = v3(0, 0.15, -0.14)
                bowl.addChildNode(tank)
                bowl.name = "room:" + roomKey(station, bath)
                staticRoot.addChildNode(bowl)
                // The shower: a nozzle on a short arm off the corner wall, and a drain in the floor below it.
                // It takes the corner across from the toilet; the far corner is the sign's.
                let sc2 = cells.count > 1 ? cells[1] : sc
                let arm = SCNNode(geometry: SCNBox(width: 0.04, height: 0.04, length: 0.2, chamferRadius: 0))
                arm.geometry!.firstMaterial = lit(NSColor(rgb: (0.7, 0.72, 0.78)))
                arm.position = v3(station.offset.x + Double(sc2.x) + 0.3, 0.62, station.offset.y + Double(sc2.y) - 0.35)
                let nozzle = SCNNode(geometry: SCNBox(width: 0.1, height: 0.04, length: 0.1, chamferRadius: 0))
                nozzle.geometry!.firstMaterial = arm.geometry!.firstMaterial
                nozzle.position = v3(0, -0.03, 0.1)
                arm.addChildNode(nozzle)
                arm.name = "room:" + roomKey(station, bath)
                staticRoot.addChildNode(arm)
                let drain = SCNNode(geometry: SCNBox(width: 0.14, height: 0.006, length: 0.14, chamferRadius: 0))
                drain.geometry!.firstMaterial = flat(NSColor(rgb: (0.28, 0.36, 0.4)))
                drain.position = v3(station.offset.x + Double(sc2.x) + 0.3, 0.01, station.offset.y + Double(sc2.y) - 0.25)
                drain.name = "room:" + roomKey(station, bath)
                staticRoot.addChildNode(drain)
            }
            if station.hasHangar {
                let hc = station.hangarCenter
                let anchor = hangarAnchors[station.name] ?? { let n = SCNNode(); propRoot.addChildNode(n); hangarAnchors[station.name] = n; return n }()
                anchor.position = v3(station.offset.x + hc.x, 0, station.offset.y + hc.y)
                for slot in station.hangarSlots {
                    let mark = SCNNode(geometry: faceted(SCNTube(innerRadius: 0.3, outerRadius: 0.34, height: 0.01)))
                    mark.geometry!.firstMaterial = flat(NSColor(Colors.hangar).lighter(0.18))
                    mark.position = v3(station.offset.x + slot.x, 0.006, station.offset.y + slot.y)
                    staticRoot.addChildNode(mark)
                }
            }
            for c in station.corridorCells where (c.x + c.y * 3) % 4 == 0 {
                let d = SCNNode(geometry: SCNPlane(width: 0.12, height: 0.12))
                d.geometry!.firstMaterial = flat(Palette.void)
                d.eulerAngles.x = -.pi / 2
                d.position = v3(station.offset.x + Double(c.x), 0.004, station.offset.y + Double(c.y))
                staticRoot.addChildNode(d)
            }
            let core = SCNNode(geometry: SCNBox(width: 0.7, height: 2.3, length: 0.7, chamferRadius: 0))
            core.geometry!.firstMaterial = lit(Palette.core)
            let mp = station.monolithPosition
            core.position = v3(station.offset.x + mp.x, 1.15, station.offset.y + mp.y)
            core.name = "station:" + station.name
            staticRoot.addChildNode(core)
            let glow = SCNNode(geometry: SCNBox(width: 0.72, height: 0.04, length: 0.72, chamferRadius: 0))
            glow.geometry!.firstMaterial = flat(NSColor(rgb: (0.55, 0.75, 1.0)))
            glow.position = v3(station.offset.x + mp.x, 1.75, station.offset.y + mp.y)
            staticRoot.addChildNode(glow)
            for bed in station.beds {
                if bed.level == 0 {
                    let b = SCNNode(geometry: SCNPlane(width: 0.34, height: 0.72))
                    b.geometry!.firstMaterial = flat(NSColor(Colors.bed))
                    b.eulerAngles.x = -.pi / 2
                    b.position = v3(station.offset.x + bed.pos.x, 0.005, station.offset.y + bed.pos.y)
                    b.name = "room:\(station.name)|kind:quarters"
                    staticRoot.addChildNode(b)
                } else {
                    // The upper bunk: a slab on four thin posts.
                    let slab = SCNNode(geometry: SCNBox(width: 0.36, height: 0.03, length: 0.74, chamferRadius: 0))
                    slab.geometry!.firstMaterial = lit(NSColor(Colors.bed).lighter(0.08))
                    slab.position = v3(station.offset.x + bed.pos.x, 0.34, station.offset.y + bed.pos.y)
                    slab.name = "room:\(station.name)|kind:quarters"
                    for dx in [-0.16, 0.16] { for dz in [-0.35, 0.35] {
                        let post = SCNNode(geometry: SCNBox(width: 0.025, height: 0.34, length: 0.025, chamferRadius: 0))
                        post.geometry!.firstMaterial = lit(NSColor(rgb: (0.3, 0.22, 0.3)))
                        post.position = v3(dx, -0.17, dz)
                        slab.addChildNode(post)
                    } }
                    staticRoot.addChildNode(slab)
                }
            }

            for room in station.rooms.values {
                let key = roomKey(station, room)
                var tiles: [SCNNode] = []
                // Construction progress: no branch = empty grey floor; a local branch starts the tiling,
                // commits add more, and pushing finishes it.
                // Dark while it's just a conversation; lit as soon as a branch exists; power cut when left alone.
                let progress: Double = room.key.hasPrefix("proj:") ? 0 : 1
                let powered = room.key.hasPrefix("kind:") || world.crewRoomInfo[key] != nil || Date().timeIntervalSince(room.lastActive) < StationController.powerWindow
                roomPower[key] = powered
                let failing = world.checksFailing(room)
                let dusty = world.isDusty(room)
                let grey = NSColor(rgb: (0.27, 0.28, 0.33))          // an empty room's floor
                let subfloor = NSColor(rgb: (0.15, 0.16, 0.21))      // where tiles have not been laid yet
                let full = world.isRemoteOnly(station, room) ? NSColor(room.color).darker(0.14) : NSColor(room.color)
                let provisional = world.isProvisional(station, room)
                let ordered = room.cells.sorted { (a, b) in
                    let da = abs(a.x - (station.doorCell(of: room.key)?.x ?? a.x)) + abs(a.y - (station.doorCell(of: room.key)?.y ?? a.y))
                    let db = abs(b.x - (station.doorCell(of: room.key)?.x ?? b.x)) + abs(b.y - (station.doorCell(of: room.key)?.y ?? b.y))
                    return da != db ? da < db : (a.y, a.x) < (b.y, b.x)
                }
                let tiled = Int((Double(ordered.count) * progress).rounded())
                let pending = undelivered.contains(key)
                for (i, c) in ordered.enumerated() {
                    if pending {
                        addTile(station: station, cell: c, owner: room.key, color: grey, name: "room:" + key)
                    }
                    var color = progress == 0 ? full.darker(0.32) : (i < tiled ? full : subfloor)
                    if !powered { color = color.darker(0.2) }
                    let t = addTile(station: station, cell: c, owner: room.key, color: color, name: "room:" + key)
                    if pending { t.opacity = 0; t.position.y = 0.003 }
                    else if provisional { t.opacity = 0.38 }
                    tiles.append(t)
                    if failing || dusty {
                        let overlay = SCNNode(geometry: SCNPlane(width: 1, height: 1))
                        overlay.geometry!.firstMaterial = flat(failing ? NSColor(rgb: (0.95, 0.2, 0.2)) : NSColor(rgb: (0.62, 0.62, 0.68)))
                        overlay.eulerAngles.x = -.pi / 2
                        overlay.position = v3(t.position.x, 0.004, t.position.z)
                        overlay.name = "room:" + key
                        if failing {
                            overlay.opacity = 0.15
                            overlay.runAction(.repeatForever(.sequence([.fadeOpacity(to: 0.5, duration: 0.7), .fadeOpacity(to: 0.12, duration: 0.9)])))
                        } else {
                            overlay.opacity = 0.28
                        }
                        staticRoot.addChildNode(overlay)
                    }
                }
                roomTiles[key] = tiles
                if provisional, !pending {
                    // A thin frame round each tile's outer edges: reserved, not built.
                    let cellSet = Set(room.cells)
                    for c in room.cells {
                        for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] where !cellSet.contains(Cell(x: c.x + dx, y: c.y + dy)) {
                            let edge = SCNNode(geometry: SCNBox(width: dx == 0 ? 1.0 : 0.04, height: 0.01, length: dy == 0 ? 1.0 : 0.04, chamferRadius: 0))
                            edge.geometry!.firstMaterial = flat(full.lighter(0.25))
                            edge.position = v3(station.offset.x + Double(c.x) + Double(dx) * 0.48, 0.006, station.offset.y + Double(c.y) + Double(dy) * 0.48)
                            edge.name = "room:" + key
                            staticRoot.addChildNode(edge)
                        }
                    }
                }
                outlines.removeValue(forKey: key)?.removeFromParentNode()
            }
        }
        for (key, o) in outlines where !undelivered.contains(key) { o.removeFromParentNode(); outlines[key] = nil }
        rebuildLabels()
        rebuildMarkers()
        for key in fadeIn {
            for t in roomTiles[key] ?? [] { let o = t.opacity; t.opacity = 0; t.runAction(.fadeOpacity(to: o, duration: 2.5)) }
            if let l = roomLabels[key] { let o = l.opacity; l.opacity = 0; l.runAction(.fadeOpacity(to: o, duration: 2.5)) }
        }
        fadeIn = []

        (targetFocus, targetHalf) = frame(for: Array(fleet.stations.values))
        if let f = focused { focusNow(on: f) }
        fleet.save()
    }

    private static func displayName(_ room: Room) -> String {
        switch room.key {
        case "kind:quarters": return "dorm"
        case "kind:lounge": return "lounge"
        case "kind:bath": return "bath"
        case "kind:airlock": return "airlock"
        default: return room.name
        }
    }

    /// Lays each room's name flat beside it on the side with free floor, or cut into the tile when boxed in.
    private func rebuildLabels() {
        labelRoot.childNodes.forEach { $0.removeFromParentNode() }
        roomLabels = [:]
        floorLabels = []
        labelCells = [:]
        func reserve(_ key: String, _ center: SIMD2<Double>, _ half: SIMD2<Double>) {
            let lo = center - half, hi = center + half
            for x in Int((lo.x + 0.5).rounded(.down))...Int((hi.x + 0.5).rounded(.down)) {
                for y in Int((lo.y + 0.5).rounded(.down))...Int((hi.y + 0.5).rounded(.down)) { labelCells[key, default: []].insert(Cell(x: x, y: y)) }
            }
        }
        func add(_ node: SCNNode, yaw: Double, center: SIMD2<Double>) {
            node.eulerAngles.y = yaw
            let y = node.position.y > 0 ? Double(node.position.y) : 0.01
            node.position = v3(center.x, y, center.y)
            node.renderingOrder = 10
            labelRoot.addChildNode(node)
            floorLabels.append((node, yaw))
        }
        for station in fleet.stations.values {
            let ox = station.offset.x, oz = station.offset.y
            let name = floorText(station.name, color: Palette.text, size: 1.0, maxWidth: 10, lines: 1)
            let b = station.bounds
            add(name.node, yaw: 0, center: SIMD2(ox + Double(b.min.x) - 0.5 + name.width / 2, oz + Double(b.max.y) + 1.2 + name.height / 2))

            if station.hasPad {
                if !ConfigStore.shared.current.stagingBranch.isEmpty {
                    let deckLabel = floorSign("staging", color: NSColor(rgb: (0.42, 0.52, 0.58)), size: 0.24)
                    deckLabel.node.position.y = 0.012
                    let dc = station.deckCells
                    let dcorner = SIMD2(Double(dc.map(\.x).max()!) + 0.42 - deckLabel.width / 2, Double(dc.map(\.y).max()!) + 0.42 - deckLabel.height / 2)
                    add(deckLabel.node, yaw: 0, center: dcorner + SIMD2(ox, oz))
                }
                let storeLabel = floorSign("storage", color: NSColor(rgb: (0.40, 0.44, 0.56)), size: 0.24)
                storeLabel.node.position.y = 0.012
                let sc = station.storageCells
                let scorner = SIMD2(Double(sc.map(\.x).max()!) + 0.42 - storeLabel.width / 2, Double(sc.map(\.y).max()!) + 0.42 - storeLabel.height / 2)
                add(storeLabel.node, yaw: 0, center: scorner + SIMD2(ox, oz))
                let padLabel = floorSign("launch", color: NSColor(rgb: (0.45, 0.48, 0.58)), size: 0.34)
                padLabel.node.position.y = 0.012
                let pc = station.padCells
                let corner = SIMD2(Double(pc.map(\.x).max()!) + 0.42 - padLabel.width / 2, Double(pc.map(\.y).max()!) + 0.42 - padLabel.height / 2)
                add(padLabel.node, yaw: 0, center: corner + SIMD2(ox, oz))
            }
            if station.hasHangar {
                let hangarLabel = floorSign("bay", color: NSColor(Colors.hangar).lighter(0.18), size: 0.36)
                hangarLabel.node.position.y = 0.012
                let hc = station.hangarCells
                let corner = SIMD2(Double(hc.map(\.x).max()!) + 0.42 - hangarLabel.width / 2, Double(hc.map(\.y).max()!) + 0.42 - hangarLabel.height / 2)
                add(hangarLabel.node, yaw: 0, center: corner + SIMD2(ox, oz))
            }
            let occupied: (Cell) -> Bool = { c in
                station.coreCells.contains(c) || station.hangarCells.contains(c) || station.padCells.contains(c) || station.storageCells.contains(c)
                    || station.deckCells.contains(c) || station.isCorridor(c) || station.room(at: c) != nil
            }
            var placed: [(min: SIMD2<Double>, max: SIMD2<Double>)] = []
            func collides(_ lo: SIMD2<Double>, _ hi: SIMD2<Double>) -> Bool {
                // Tiles are centred on integer coordinates: any tile the text touches counts.
                let x0 = Int((lo.x + 0.25).rounded(.down)), x1 = max(x0, Int((hi.x - 0.25).rounded(.down)))
                let y0 = Int((lo.y + 0.25).rounded(.down)), y1 = max(y0, Int((hi.y - 0.25).rounded(.down)))
                for x in x0...x1 {
                    for y in y0...y1 where occupied(Cell(x: x, y: y)) {
                        return true
                    }
                }
                return placed.contains { !(hi.x <= $0.min.x || lo.x >= $0.max.x || hi.y <= $0.min.y || lo.y >= $0.max.y) }
            }
            enum Side { case south, north, east, west }
            for room in station.rooms.values.sorted(by: { $0.key < $1.key }) {
                let text = StationController.displayName(room)
                if room.key.hasPrefix("kind:") {
                    // Fixed rooms: a short word cut into the middle of the floor.
                    let accent = room.key == "kind:quarters" ? NSColor(Colors.bed) : NSColor(room.color).lighter(0.2)
                    let label = floorSign(text, color: accent, size: 0.36)
                    label.node.position.y = 0.012
                    // Tucked into the far corner of the floor, clear of beds and rings.
                    let maxY = room.cells.map(\.y).max()!
                    let maxX = room.cells.filter { $0.y == maxY }.map(\.x).max()!
                    let corner = SIMD2(Double(maxX) + 0.42 - label.width / 2, Double(maxY) + 0.42 - label.height / 2)
                    add(label.node, yaw: 0, center: corner + SIMD2(ox, oz))
                    label.node.name = "room:" + roomKey(station, room)
                    roomLabels[roomKey(station, room)] = label.node
                    continue
                }
                // 3. Long names get smaller type.
                let size = max(0.3, min(0.46, 6.4 / Double(max(14, text.count))))
                let minX = room.cells.map(\.x).min()!, maxX = room.cells.map(\.x).max()!
                let minY = room.cells.map(\.y).min()!, maxY = room.cells.map(\.y).max()!
                let width = Double(maxX - minX + 1), depth = Double(maxY - minY + 1)
                let charW = 0.5 * size
                let key = roomKey(station, room)
                var node: SCNNode?

                for side in [Side.south, .north, .east, .west] {
                    let along = (side == .south || side == .north) ? width + 1.5 : depth + 1.5
                    let lines = max(1, min(2, Int((Double(text.count) * charW / along).rounded(.up))))
                    let label = floorText(text, color: NSColor(room.color).lighter(0.12), size: size, maxWidth: along, lines: lines)
                    let (w, h) = (label.width, label.height)
                    let center: SIMD2<Double>
                    let yaw: Double
                    let half: SIMD2<Double>
                    switch side {
                    case .south: yaw = 0; center = SIMD2(Double(minX) - 0.45 + w / 2, Double(maxY) + 0.62 + h / 2); half = SIMD2(w / 2, h / 2)
                    case .north: yaw = 0; center = SIMD2(Double(minX) - 0.45 + w / 2, Double(minY) - 0.62 - h / 2); half = SIMD2(w / 2, h / 2)
                    case .east: yaw = .pi / 2; center = SIMD2(Double(maxX) + 0.62 + h / 2, Double(maxY) + 0.45 - w / 2); half = SIMD2(h / 2, w / 2)
                    case .west: yaw = .pi / 2; center = SIMD2(Double(minX) - 0.62 - h / 2, Double(maxY) + 0.45 - w / 2); half = SIMD2(h / 2, w / 2)
                    }
                    let lo = center - half, hi = center + half
                    if collides(lo, hi) { continue }
                    placed.append((lo, hi))
                    add(label.node, yaw: yaw, center: center + SIMD2(ox, oz))
                    node = label.node
                    break
                }
                if node == nil {
                    // Boxed in: cut the name into the tile itself, shrunk until it fits the floor.
                    let horizontal = width >= depth
                    let along = (horizontal ? width : depth) - 0.3
                    let across = (horizontal ? depth : width) - 0.3
                    var size = size * 0.85
                    var lines = max(1, min(3, Int((Double(text.count) * 0.5 * size / along).rounded(.up))))
                    let fitWidth = 3 * along / (Double(text.count) * 0.5)          // three lines at most
                    let fitDepth = across / (Double(lines) * 1.15)                 // stacked lines must fit too
                    size = max(0.16, min(size, fitWidth, fitDepth))
                    lines = max(1, min(3, Int((Double(text.count) * 0.5 * size / along).rounded(.up))))
                    let label = floorText(text, color: StationController.inkOnTile, size: size, maxWidth: along, lines: lines, bold: true)
                    let maxYRow = room.cells.map(\.y).max()!
                    let anchor = room.cells.filter { $0.y == maxYRow }.min { $0.x < $1.x }!
                    let center = horizontal
                        ? SIMD2(ox + Double(anchor.x) - 0.35 + label.width / 2, oz + Double(anchor.y) + 0.35 - label.height / 2)
                        : SIMD2(ox + Double(anchor.x) - 0.35 + label.height / 2, oz + Double(anchor.y) + 0.35 - label.width / 2)
                    label.node.position.y = 0.02
                    add(label.node, yaw: horizontal ? 0 : .pi / 2, center: center)
                    let half = horizontal ? SIMD2(label.width / 2, label.height / 2) : SIMD2(label.height / 2, label.width / 2)
                    reserve(key, center - SIMD2(ox, oz), half)
                    node = label.node
                }
                if let who = world.occupant(of: key) {
                    let sign = floorSign(who, color: StationController.inkOnTile, size: 0.3)
                    sign.node.position.y = 0.012
                    let maxYRow = room.cells.map(\.y).max()!
                    let cx = room.cells.filter { $0.y == maxYRow }.map(\.x).max()!
                    let corner = SIMD2(Double(cx) + 0.42 - sign.width / 2, Double(maxYRow) + 0.42 - sign.height / 2)
                    add(sign.node, yaw: 0, center: corner + SIMD2(ox, oz))
                    reserve(key, corner, SIMD2(sign.width / 2, sign.height / 2))
                    sign.node.name = "room:" + key
                }
                guard let node else { continue }
                node.name = "room:" + key
                if undelivered.contains(key) { node.opacity = 0 } else if world.isProvisional(station, room) { node.opacity = 0.55 }
                roomLabels[key] = node
            }
        }
    }

    /// An office's floor from the far corners in: boxes go there first, so the doorway stays clear.
    func farCells(_ station: Station, _ room: Room) -> [Cell] {
        let door = station.doorCell(of: room.key) ?? room.cells.first!
        let written = labelCells[roomKey(station, room)] ?? []
        return room.cells.sorted { a, b in
            let wa = written.contains(a), wb = written.contains(b)
            if wa != wb { return !wa }   // cells under writing come last
            let da = abs(a.x - door.x) + abs(a.y - door.y), db = abs(b.x - door.x) + abs(b.y - door.y)
            return da != db ? da > db : (a.y, a.x) < (b.y, b.x)
        }
    }
}
