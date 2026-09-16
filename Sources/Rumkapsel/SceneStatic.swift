// The station as it stands: floor tiles, walls, outlines and the names written on the floor.

import AppKit
import SceneKit

extension StationController {
    private func owner(_ station: Station, _ c: Cell) -> String? {
        if station.hangarCells.contains(c) { return "kind:hangar" }
        if station.airlockCells.contains(c) { return "kind:airlock" }
        if station.storageCells.contains(c) { return "kind:storage" }
        if station.deckCells.contains(c) && world.deckInUse(station: station.name) { return "kind:deck" }
        if station.padCells.contains(c) { return "kind:pad" }
        if station.deconCells.contains(c) { return "kind:decon" }
        if station.coreCells.contains(c) || station.isCorridor(c) { return "corridor" }
        return station.room(at: c)?.key
    }

    private func joined(_ station: Station, _ a: Cell, _ b: Cell, _ key: String) -> Bool {
        owner(station, b) == key || openEdges.contains("\(station.name):\(a.x),\(a.y)|\(b.x),\(b.y)")
    }

    /// What kind of floor an owner's tile is, for the look.
    private func floorKind(_ key: String) -> Floor {
        switch key {
        case "corridor": return .hallway
        case "kind:hangar": return .bay
        case "kind:airlock": return .airlock
        case "kind:pad", "kind:storage", "kind:deck", "kind:decon": return .yard
        case let k where k.hasPrefix("kind:"): return .fixed
        default: return .room
        }
    }

    /// Full-size floor tile; borders are drawn separately as strips so corners meet cleanly.
    @discardableResult
    private func addTile(station: Station, cell: Cell, owner key: String, color: NSColor, name: String, into parent: SCNNode? = nil) -> SCNNode {
        let root = parent ?? staticRoot
        let look = Looks.current
        let floor = floorKind(key)
        let plane = SCNPlane(width: 1.0, height: 1.0)
        plane.firstMaterial = flat(look.floorColor(color, floor: floor))
        if !look.drawsPlane(floor) { plane.firstMaterial?.transparency = 0; plane.firstMaterial?.writesToDepthBuffer = false }
        let n = SCNNode(geometry: plane)
        n.eulerAngles.x = -.pi / 2
        n.position = v3(station.offset.x + Double(cell.x), 0, station.offset.y + Double(cell.y))
        n.name = name
        root.addChildNode(n)
        // Dark border toward any neighbouring floor of another owner, extended past the corners. Edges
        // with no floor beyond are open, numbered round the tile (z-, x-, z+, x+) for the look's kerbs.
        let g = 0.075
        let sides: [(Cell, SIMD2<Double>, Bool, Int)] = [
            (Cell(x: cell.x - 1, y: cell.y), SIMD2(-0.5, 0), true, 1), (Cell(x: cell.x + 1, y: cell.y), SIMD2(0.5, 0), true, 3),
            (Cell(x: cell.x, y: cell.y - 1), SIMD2(0, -0.5), false, 0), (Cell(x: cell.x, y: cell.y + 1), SIMD2(0, 0.5), false, 2),
        ]
        var open = Set<Int>(), walled: [Int: Floor] = [:]
        for (nb, off, vertical, edge) in sides {
            guard let other = owner(station, nb) else { open.insert(edge); continue }   // the void: a kerb, no border
            guard other != key, !joined(station, cell, nb, key) else { continue }
            walled[edge] = floorKind(other)
            guard look.drawsBorders else { continue }
            let strip = SCNPlane(width: vertical ? g * 2 : 1 + g * 2, height: vertical ? 1 + g * 2 : g * 2)
            strip.firstMaterial = flat(Palette.void)
            let b = SCNNode(geometry: strip)
            b.eulerAngles.x = -.pi / 2
            b.position = v3(station.offset.x + Double(cell.x) + off.x, look.floorTop + 0.002, station.offset.y + Double(cell.y) + off.y)
            b.name = name
            b.opacity = n.opacity
            root.addChildNode(b)
        }
        // Whatever the look hangs under the plane; the plane keeps the name, the colour and the place
        // the scene reads.
        var same: UInt8 = 0
        for (k, (dx, dz)) in Tile.around.enumerated() where owner(station, Cell(x: cell.x + dx, y: cell.y + dz)) == key { same |= 1 << k }
        if let detail = look.tileDetail(Tile(floor: floor, color: color, open: open, walled: walled, same: same)) {
            detail.name = name
            n.addChildNode(detail)
        }
        return n
    }

    /// A look's set piece into the scene, each part named for its area so the pointer and the clicks find it.
    private func addSetPiece(_ piece: SetPiece, _ station: Station) {
        for (area, nodes) in piece.parts {
            for n in nodes { n.name = area.rawValue + ":" + station.name; staticRoot.addChildNode(n) }
        }
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
            for (a, b) in station.yardDoorways {
                openEdges.insert("\(station.name):\(a.x),\(a.y)|\(b.x),\(b.y)")
                openEdges.insert("\(station.name):\(b.x),\(b.y)|\(a.x),\(a.y)")
            }
        }

        for station in fleet.stations.values {
            let anchor = stationAnchors[station.name] ?? { let n = SCNNode(); propRoot.addChildNode(n); stationAnchors[station.name] = n; return n }()
            anchor.position = v3(station.offset.x, 0, station.offset.y)
            let oldDug = knownSpine[station.name] ?? station.dugCount
            knownSpine[station.name] = station.dugCount
            for c in station.corridorCells + station.coreCells {
                let t = addTile(station: station, cell: c, owner: "corridor", color: Palette.corridor, name: "station:" + station.name)
                // Hallway dug since the last redraw is built tile by tile, in the order it was dug.
                let order = station.digOrder(of: c)
                if order > oldDug {   // the plaza and the fixed arms are order 0; they are never new
                    t.opacity = 0
                    t.runAction(.sequence([.wait(duration: min(2.4, 0.2 * Double(order - oldDug))), .fadeIn(duration: 0.5)]))
                }
            }
            // Nothing to put on the floor yet: the hallway pulses out from the plaza while the station
            // waits to hear which offices it has, in the order the hallway was dug, so the waiting reads
            // as the same outward movement as the building.
            if world.settling {
                for c in station.corridorCells + station.coreCells {
                    let mark = SCNNode(geometry: SCNPlane(width: 0.34, height: 0.34))
                    mark.geometry!.firstMaterial = flat(NSColor(white: 0.75, alpha: 1))
                    mark.geometry!.firstMaterial?.writesToDepthBuffer = false
                    mark.renderingOrder = 3
                    mark.eulerAngles.x = -.pi / 2
                    mark.position = v3(station.offset.x + Double(c.x), 0.004, station.offset.y + Double(c.y))
                    mark.opacity = 0
                    let wait = 0.12 * Double(station.digOrder(of: c) % 12)
                    mark.runAction(.sequence([.wait(duration: wait), .repeatForever(.sequence([
                        .fadeOpacity(to: 0.28, duration: 0.5), .fadeOpacity(to: 0, duration: 0.7), .wait(duration: 0.4)]))]))
                    staticRoot.addChildNode(mark)
                }
            }
            // The input and the output: a look's set pieces, or tiles.
            let input = Looks.current.input(station)
            if let input { addSetPiece(input, station) } else {
                for c in station.hangarCells {
                    addTile(station: station, cell: c, owner: "kind:hangar", color: NSColor(Colors.hangar), name: "hangar:" + station.name)
                }
                for c in station.airlockCells {
                    addTile(station: station, cell: c, owner: "kind:airlock", color: NSColor(rgb: (0.30, 0.34, 0.42)), name: "airlock:" + station.name)
                }
            }
            let output = Looks.current.output(station, deckInUse: world.deckInUse(station: station.name))
            if let output { addSetPiece(output, station) }
            if station.hasHangar, !station.airlockCells.isEmpty {
                // Two rectangular door frames across the chamber's full width: the inner door on the
                // corridor side, the hatch on the bay side. Posts and a lintel, a dark pane between.
                let xs = station.airlockCells.map(\.x), ys = station.airlockCells.map(\.y)
                let cx = station.offset.x + Double(xs.min()! + xs.max()!) / 2
                let width = Double(xs.max()! - xs.min()! + 1) - 0.1   // posts in the walls
                for (edge, tint) in [(Double(ys.min()!) - 0.46, NSColor(rgb: (0.55, 0.6, 0.72))), (Double(ys.max()!) + 0.46, NSColor(rgb: (0.75, 0.62, 0.25)))] {
                    let door = SCNNode()
                    let frame = lit(tint)
                    let spans = (xs.min()!...xs.max()!).map { station.offset.x + Double($0) - cx }
                    let drawn = Looks.current.airlockFrame(width: width, spans: spans, tint: tint)
                    for side in [-1.0, 1.0] {
                        let post = SCNNode(geometry: SCNBox(width: 0.08, height: 0.7, length: 0.08, chamferRadius: 0))
                        post.geometry!.firstMaterial = frame
                        post.position = v3(side * width / 2, 0.35, 0)
                        post.name = "post"
                        post.isHidden = !drawn.showsPosts   // drawn or not, the walks go between them
                        door.addChildNode(post)
                    }
                    door.addChildNode(drawn.node)
                    let pane = SCNNode(geometry: SCNBox(width: width - 0.08, height: 0.7, length: 0.03, chamferRadius: 0))
                    pane.geometry!.firstMaterial = flat(NSColor(rgb: (0.12, 0.14, 0.2)))
                    pane.position = v3(0, 0.35, 0)
                    pane.name = "pane"
                    door.addChildNode(pane)
                    door.position = v3(cx, 0, station.offset.y + edge)
                    door.name = "airlockdoor:" + station.name
                    staticRoot.addChildNode(door)
                }
            }
            for c in station.padCells where output == nil {
                addTile(station: station, cell: c, owner: "kind:pad", color: NSColor(rgb: (0.24, 0.26, 0.32)), name: "pad:" + station.name)
            }
            for c in station.storageCells where output == nil {
                addTile(station: station, cell: c, owner: "kind:storage", color: NSColor(rgb: (0.20, 0.22, 0.30)), name: "storage:" + station.name)
            }
            if output == nil, world.deckInUse(station: station.name) {
                for c in station.deckCells {
                    addTile(station: station, cell: c, owner: "kind:deck", color: NSColor(rgb: (0.22, 0.27, 0.30)), name: "deck:" + station.name)
                }
            }
            if station.hasPad {
                // Decon: a darker floor at the back of storage, and the hatch in the back wall that
                // everything from outside comes through, with its light over it.
                for c in station.deconCells where output == nil {
                    addTile(station: station, cell: c, owner: "kind:decon", color: NSColor(rgb: (0.17, 0.24, 0.24)), name: "decon:" + station.name)
                }
                let (hp, facing) = station.deconHatch
                let hatch = SCNNode()
                let drawn = Looks.current.hatchFrame(facing: facing)
                hatch.addChildNode(drawn.node)
                let pane = SCNNode(geometry: SCNBox(width: 0.92, height: 0.7, length: 0.03, chamferRadius: 0))
                pane.geometry!.firstMaterial = flat(NSColor(rgb: (0.12, 0.14, 0.2)))
                pane.position = v3(0, 0.35, 0)
                hatch.addChildNode(pane)
                let light = SCNNode(geometry: SCNBox(width: 0.2, height: 0.06, length: 0.06, chamferRadius: 0))
                light.geometry!.firstMaterial = flat(Palette.alienLight.darker(0.35))
                light.position = v3(0, drawn.lightHeight, facing.y * 0.05)
                hatch.addChildNode(light)
                hatchLights[station.name] = light
                hatch.position = v3(station.offset.x + hp.x, 0, station.offset.y + hp.y)
                hatch.name = "decon:" + station.name
                staticRoot.addChildNode(hatch)
            }
            if station.hasPad, !station.storageCells.isEmpty {
                // The storage console: a small panel on the wall by the doorway, where a pallet is ordered.
                let (cell, facing) = station.storageConsole
                let console = Props.console(color: NSColor(rgb: (0.4, 0.72, 0.9)))
                console.position = v3(station.offset.x + Double(cell.x) + facing.x * 0.46, 0.5, station.offset.y + Double(cell.y) + facing.y * 0.46)
                console.eulerAngles.y = atan2(-facing.x, -facing.y)   // hung on the wall, face turned into the room
                console.name = "storage:" + station.name
                staticRoot.addChildNode(console)
                consolePanels[station.name] = console.childNode(withName: "panel", recursively: false)
            }
            if station.hasPad, output == nil {
                let pc = station.padCenter
                let ring = SCNNode(geometry: faceted(SCNTube(innerRadius: 1.45, outerRadius: 1.55, height: 0.01)))
                ring.geometry!.firstMaterial = flat(NSColor(rgb: (0.45, 0.48, 0.58)))
                ring.position = v3(station.offset.x + pc.x, 0.006, station.offset.y + pc.y)
                staticRoot.addChildNode(ring)
            }
            for prop in Looks.current.dress(station: station) {
                prop.position.x += station.offset.x; prop.position.z += station.offset.y
                prop.name = "station:" + station.name
                staticRoot.addChildNode(prop)
            }
            // The fixed rooms' furniture, from the look. The solid pieces carry the room's name; the gym's are
            // stood on and stepped round, so they carry the gym's; the towel, the bar and the bag move.
            if let lounge = station.rooms["kind:lounge"] {
                for n in Looks.current.furnishLounge(lounge, in: station).props { n.name = "room:" + roomKey(station, lounge); staticRoot.addChildNode(n) }
            }
            if let bath = station.rooms["kind:bath"] {
                let f = Looks.current.furnishBath(bath, in: station)
                for n in f.props { n.name = "room:" + roomKey(station, bath); staticRoot.addChildNode(n) }
                for n in f.fixtures { n.name = "gym:" + roomKey(station, bath); staticRoot.addChildNode(n) }
                f.towel?.name = "towel:" + station.name
            }
            gymProps[station.name] = nil
            if let gym = station.rooms["kind:gym"] {
                let f = Looks.current.furnishGym(gym, in: station)
                for n in f.props { n.name = "room:" + roomKey(station, gym); staticRoot.addChildNode(n) }
                for n in f.fixtures { n.name = "gym:" + roomKey(station, gym); staticRoot.addChildNode(n) }
                if let bar = f.bar, let bag = f.bag { gymProps[station.name] = (bar, bag) }
            }
            if station.hasHangar {
                let hc = station.hangarCenter
                let anchor = hangarAnchors[station.name] ?? { let n = SCNNode(); propRoot.addChildNode(n); hangarAnchors[station.name] = n; return n }()
                anchor.position = v3(station.offset.x + hc.x, 0, station.offset.y + hc.y)
                for slot in station.hangarSlots where input == nil {
                    let mark = SCNNode(geometry: faceted(SCNTube(innerRadius: 0.3, outerRadius: 0.34, height: 0.01)))
                    mark.geometry!.firstMaterial = flat(NSColor(Colors.hangar).lighter(0.18))
                    mark.position = v3(station.offset.x + slot.x, 0.006, station.offset.y + slot.y)
                    staticRoot.addChildNode(mark)
                }
            }
            for c in station.corridorCells where Looks.current.dotsHallway && (c.x + c.y * 3) % 4 == 0 {
                let d = SCNNode(geometry: SCNPlane(width: 0.12, height: 0.12))
                d.geometry!.firstMaterial = flat(Palette.void)
                d.eulerAngles.x = -.pi / 2
                d.position = v3(station.offset.x + Double(c.x), 0.004, station.offset.y + Double(c.y))
                staticRoot.addChildNode(d)
            }
            let mp = station.monolithPosition
            let monolith = Looks.current.monolith()
            monolith.position = v3(station.offset.x + mp.x, 0, station.offset.y + mp.y)
            monolith.name = "station:" + station.name
            staticRoot.addChildNode(monolith)
            for bed in station.beds {
                let b = Looks.current.bed(level: bed.level)
                b.position.x = station.offset.x + bed.pos.x
                b.position.z = station.offset.y + bed.pos.y
                b.name = "room:\(station.name)|kind:quarters"
                staticRoot.addChildNode(b)
            }

            for room in station.rooms.values {
                let key = roomKey(station, room)
                var tiles: [SCNNode] = []
                // Construction progress: no branch = empty grey floor; a local branch starts the tiling,
                // commits add more, and pushing finishes it.
                // Dark while it's just a conversation; lit as soon as a branch exists; power cut when left alone.
                let progress: Double = room.key.hasPrefix("proj:") ? 0 : 1
                let powered = (room.key.hasPrefix("kind:") || world.crewRoomInfo[key] != nil || Date().timeIntervalSince(room.lastActive) < StationController.powerWindow)
                    && !world.peerDim(key)   // a peer who says the office is idle: dimmed like our own idle ones
                roomPower[key] = powered
                let failing = world.checksFailing(room)
                let dusty = world.isDusty(room)
                let grey = NSColor(rgb: (0.27, 0.28, 0.33))          // an empty room's floor
                let subfloor = NSColor(rgb: (0.15, 0.16, 0.21))      // where tiles have not been laid yet
                let full = world.isRemoteOnly(station, room) ? NSColor(room.color).darker(0.14) : NSColor(room.color)
                let provisional = world.isProvisional(station, room)
                // Drawn from last night's notes and not yet confirmed today: it breathes until it is.
                let unchecked = world.isUnchecked(station, room)
                let ordered = room.cells.sorted { (a, b) in
                    let da = abs(a.x - (station.doorCell(of: room.key)?.x ?? a.x)) + abs(a.y - (station.doorCell(of: room.key)?.y ?? a.y))
                    let db = abs(b.x - (station.doorCell(of: room.key)?.x ?? b.x)) + abs(b.y - (station.doorCell(of: room.key)?.y ?? b.y))
                    return da != db ? da < db : (a.y, a.x) < (b.y, b.x)
                }
                let tiled = Int((Double(ordered.count) * progress).rounded())
                let pending = undelivered.contains(key)
                for (i, c) in ordered.enumerated() {
                    // Nothing on the plot before the office unfolds from its crate: no grey placeholder.
                    var color = progress == 0 ? full.darker(0.32) : (i < tiled ? full : subfloor)
                    if !powered { color = color.darker(0.2) }
                    let t = addTile(station: station, cell: c, owner: room.key, color: color, name: "room:" + key)
                    if pending { t.opacity = 0; t.position.y = 0.003 }
                    else if unchecked { t.opacity = CGFloat(StationController.unlitOffice) }
                    else if provisional { t.opacity = 0.38 }
                    tiles.append(t)
                    if failing || dusty {
                        let overlay = SCNNode(geometry: SCNPlane(width: 1, height: 1))
                        overlay.geometry!.firstMaterial = flat(failing ? NSColor(rgb: (0.95, 0.2, 0.2)) : NSColor(rgb: (0.62, 0.62, 0.68)))
                        overlay.eulerAngles.x = -.pi / 2
                        overlay.position = v3(t.position.x, Looks.current.floorTop + 0.004, t.position.z)
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
                if !pending, !room.key.hasPrefix("kind:"), let prop = Looks.current.dress(office: room, in: station) {
                    prop.position.x += station.offset.x; prop.position.z += station.offset.y
                    prop.name = "station:" + station.name
                    if provisional { prop.opacity = 0.38 }
                    staticRoot.addChildNode(prop)
                }
                // Outlined while not built; a peer's local office someone works in is solid and keeps the frame as a mark.
                if provisional || world.isLocalLive(station, room), !pending {
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
        groundRoot.childNodes.forEach { $0.removeFromParentNode() }
        if headless {
            // A run with no window draws no world round the stations: nothing would see it.
        } else {
            Looks.current.ground(under: Array(fleet.stations.values), into: groundRoot)
        }
        rebuildLabels()
        rebuildMarkers()
        for key in fadeIn {
            for t in roomTiles[key] ?? [] { let o = t.opacity; t.opacity = 0; t.runAction(.fadeOpacity(to: o, duration: 2.5)) }
            if let l = roomLabels[key] { let o = l.opacity; l.opacity = 0; l.runAction(.fadeOpacity(to: o, duration: 2.5)) }
        }
        fadeIn = []

        (targetFocus, targetHalf) = frame(for: shownStations)
        if let f = focused { focusNow(on: f) }
        fleet.save()
    }

    private static func displayName(_ room: Room) -> String {
        switch room.key {
        case "kind:quarters": return Words.current.dorm
        case "kind:lounge": return Words.current.lounge
        case "kind:bath": return Words.current.bath
        case "kind:airlock": return Words.current.airlock
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
                if world.deckInUse(station: station.name) {
                    let deckLabel = floorSign(Words.current.deck, color: NSColor(rgb: (0.42, 0.52, 0.58)), size: 0.24)
                    deckLabel.node.position.y = 0.012
                    let dc = station.deckCells
                    let dcorner = SIMD2(Double(dc.map(\.x).max()!) + 0.42 - deckLabel.width / 2, Double(dc.map(\.y).max()!) + 0.42 - deckLabel.height / 2)
                    add(deckLabel.node, yaw: 0, center: dcorner + SIMD2(ox, oz))
                }
                let storeLabel = floorSign(Words.current.storage, color: NSColor(rgb: (0.40, 0.44, 0.56)), size: 0.24)
                storeLabel.node.position.y = 0.012
                let sc = station.storageCells
                let scorner = SIMD2(Double(sc.map(\.x).max()!) + 0.42 - storeLabel.width / 2, Double(sc.map(\.y).max()!) + 0.42 - storeLabel.height / 2)
                add(storeLabel.node, yaw: 0, center: scorner + SIMD2(ox, oz))
                let deconLabel = floorSign(Words.current.decon, color: NSColor(rgb: (0.36, 0.52, 0.48)), size: 0.22)
                deconLabel.node.position.y = 0.012
                let qc = station.deconCells
                let qcorner = SIMD2(Double(qc.map(\.x).max()!) + 0.42 - deconLabel.width / 2, Double(qc.map(\.y).max()!) + 0.42 - deconLabel.height / 2)
                add(deconLabel.node, yaw: 0, center: qcorner + SIMD2(ox, oz))
                let padLabel = floorSign(Words.current.pad, color: NSColor(rgb: (0.45, 0.48, 0.58)), size: 0.34)
                padLabel.node.position.y = 0.012
                let pc = station.padCells
                let corner = SIMD2(Double(pc.map(\.x).max()!) + 0.42 - padLabel.width / 2, Double(pc.map(\.y).max()!) + 0.42 - padLabel.height / 2)
                add(padLabel.node, yaw: 0, center: corner + SIMD2(ox, oz))
            }
            if station.hasHangar {
                let hangarLabel = floorSign(Words.current.bay, color: NSColor(Colors.hangar).lighter(0.18), size: 0.36)
                hangarLabel.node.position.y = 0.012
                let hc = station.hangarCells
                let corner = SIMD2(Double(hc.map(\.x).max()!) + 0.42 - hangarLabel.width / 2, Double(hc.map(\.y).max()!) + 0.42 - hangarLabel.height / 2)
                add(hangarLabel.node, yaw: 0, center: corner + SIMD2(ox, oz))
                let airlockLabel = floorSign(Words.current.airlock, color: NSColor(rgb: (0.55, 0.6, 0.72)), size: 0.22)
                airlockLabel.node.position.y = 0.012
                if let a = station.airlockInner.first {
                    add(airlockLabel.node, yaw: 0, center: SIMD2(ox + Double(a.x), oz + Double(a.y)))
                }
            }
            let occupied: (Cell) -> Bool = { c in
                station.coreCells.contains(c) || station.hangarCells.contains(c) || station.airlockCells.contains(c) || station.padCells.contains(c) || station.storageCells.contains(c)
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
