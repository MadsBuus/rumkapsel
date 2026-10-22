import AppKit
import SceneKit

extension StationController {
    private func owner(_ station: Station, _ c: Cell) -> String? {
        if let m = owners[station.name] { return m[c] }
        var m: [Cell: String] = [:]
        for (room, _) in drawnRooms(station) { for c in room.cells { m[c] = room.key } }
        for c in station.corridorCells where station.isCorridor(c) { m[c] = "corridor" }
        for c in station.coreCells { m[c] = "corridor" }
        for c in station.hall.deconCells { m[c] = "kind:decon" }
        for c in station.hall.padCells { m[c] = "kind:pad" }
        for c in station.hall.cells { m[c] = "kind:hall" }
        for c in station.hangarCells { m[c] = "kind:hangar" }
        owners[station.name] = m
        return m[c]
    }

    private func joined(_ station: Station, _ a: Cell, _ b: Cell, _ key: String) -> Bool {
        owner(station, b) == key || openEdges.contains("\(station.name):\(a.x),\(a.y)|\(b.x),\(b.y)")
    }

    private func floorKind(_ key: String) -> Floor {
        switch key {
        case "corridor": return .hallway
        case "kind:hangar": return .bay
        case "kind:pad": return .pad
        case "kind:storage", "kind:deck", "kind:decon": return .yard
        case let k where k.hasPrefix("kind:"): return .fixed
        default: return .room
        }
    }

    @discardableResult
    private func shared(_ id: String, width: Double, height: Double, _ material: () -> SCNMaterial) -> SCNGeometry {
        guard Looks.current.sharesTiles else {
            let p = SCNPlane(width: width, height: height)
            p.firstMaterial = material()
            return p
        }
        if Looks.theme != tileCacheLook { tileCache = [:]; tileCacheLook = Looks.theme }
        if let g = tileCache[id] { return g }
        let p = SCNPlane(width: width, height: height)
        p.firstMaterial = material()
        tileCache[id] = p
        return p
    }

    private func swatch(_ c: NSColor) -> String? {
        guard let s = c.usingColorSpace(.sRGB) else { return nil }
        return String(format: "%.4f/%.4f/%.4f/%.4f", s.redComponent, s.greenComponent, s.blueComponent, s.alphaComponent)
    }

    @discardableResult
    private func addGlassDoor(_ station: Station, at p: SIMD2<Double>, facing: SIMD2<Double>) -> (node: SCNNode, lightHeight: Double) {
        let door = SCNNode()
        let drawn = Looks.current.doorFrame(facing: facing)
        door.addChildNode(drawn.node)
        let pane = SCNNode(geometry: SCNBox(width: 0.92, height: 0.7, length: 0.03, chamferRadius: 0))
        pane.geometry!.firstMaterial = Props.glass(alpha: 0.35)
        pane.position = v3(0, 0.35, 0)
        pane.name = "pane"
        door.addChildNode(pane)
        door.position = v3(station.offset.x + p.x, 0, station.offset.y + p.y)
        door.name = "glassdoor:" + station.name
        staticRoot.addChildNode(door)
        return (door, drawn.lightHeight)
    }

    private func addTile(station: Station, cell: Cell, owner key: String, color: NSColor, name: String, into parent: SCNNode? = nil) -> SCNNode {
        let root = parent ?? staticRoot
        let look = Looks.current
        let floor = floorKind(key)
        tilesBuilt += 1
        let tint = look.floorColor(color, floor: floor)
        let drawn = look.drawsPlane(floor)
        let plane: SCNGeometry
        func paint() -> SCNMaterial {
            let m = flat(tint)
            if !drawn { m.transparency = 0; m.writesToDepthBuffer = false }
            else if look.detailsFloors, let kind = Detail.kind(of: floor) { Detail.apply(kind, to: m) }
            return m
        }
        if let id = swatch(tint) {
            plane = shared("floor:\(id):\(drawn):\(floor)", width: 1, height: 1, paint)
        } else {
            let p = SCNPlane(width: 1.0, height: 1.0)
            p.firstMaterial = paint()
            plane = p
        }
        let n = SCNNode(geometry: plane)
        n.eulerAngles.x = -.pi / 2
        n.position = v3(station.offset.x + Double(cell.x), 0, station.offset.y + Double(cell.y))
        n.name = name
        root.addChildNode(n)
        let g = 0.075
        func parted(_ a: Cell, _ b: Cell) -> Bool {
            guard let oa = owner(station, a), let ob = owner(station, b), oa != ob else { return false }
            return !joined(station, a, b, oa)
        }
        let sides: [(Cell, SIMD2<Double>, Bool, Int)] = [
            (Cell(x: cell.x - 1, y: cell.y), SIMD2(-0.5, 0), true, 1), (Cell(x: cell.x + 1, y: cell.y), SIMD2(0.5, 0), true, 3),
            (Cell(x: cell.x, y: cell.y - 1), SIMD2(0, -0.5), false, 0), (Cell(x: cell.x, y: cell.y + 1), SIMD2(0, 0.5), false, 2),
        ]
        var open = Set<Int>(), walled: [Int: Floor] = [:]
        for (nb, off, vertical, edge) in sides {
            guard let other = owner(station, nb) else { open.insert(edge); continue }
            guard other != key, !joined(station, cell, nb, key) else { continue }
            walled[edge] = floorKind(other)
            guard look.drawsBorders else { continue }
            let along = vertical ? Cell(x: 0, y: 1) : Cell(x: 1, y: 0)
            func meets(_ s: Int) -> Bool {
                let a = Cell(x: cell.x + s * along.x, y: cell.y + s * along.y), b = Cell(x: nb.x + s * along.x, y: nb.y + s * along.y)
                return parted(cell, a) || parted(nb, b) || parted(a, b)
            }
            let lo = meets(-1) ? g : 0, hi = meets(1) ? g : 0
            let length = 1 + lo + hi, shift = (hi - lo) / 2
            let strip = shared("border:\(vertical):\(length)", width: vertical ? g * 2 : length,
                               height: vertical ? length : g * 2) { flat(Palette.void) }
            let b = SCNNode(geometry: strip)
            b.eulerAngles.x = -.pi / 2
            b.position = v3(station.offset.x + Double(cell.x) + off.x + (vertical ? 0 : shift), look.floorTop + 0.002,
                            station.offset.y + Double(cell.y) + off.y + (vertical ? shift : 0))
            b.name = name
            b.opacity = n.opacity
            root.addChildNode(b)
        }
        var same: UInt8 = 0
        for (k, (dx, dz)) in Tile.around.enumerated() where owner(station, Cell(x: cell.x + dx, y: cell.y + dz)) == key { same |= 1 << k }
        if let detail = look.tileDetail(Tile(floor: floor, color: color, open: open, walled: walled, same: same)) {
            detail.name = name
            n.addChildNode(detail)
        }
        return n
    }

    private func rim(_ tile: SCNNode, cell: Cell, of room: Room, in station: Station, color: NSColor) {
        let inside = Set(room.cells)
        func outside(_ dx: Int, _ dz: Int) -> Bool { !inside.contains(Cell(x: cell.x + dx, y: cell.y + dz)) }
        func door(_ dx: Int, _ dz: Int) -> Bool { joined(station, cell, Cell(x: cell.x + dx, y: cell.y + dz), room.key) && outside(dx, dz) }
        func void(_ dx: Int, _ dz: Int) -> Bool { owner(station, Cell(x: cell.x + dx, y: cell.y + dz)) == nil }
        let border = 0.075, wide = 0.13
        let over = 0.03
        let at = 0.5 - border - wide / 2, edge = 0.5 - border / 2 + over / 2
        func add(_ w: Double, _ h: Double, _ x: Double, _ z: Double, _ c: NSColor, _ y: Double) {
            let piece = shared("rim:\(w):\(h):\(c.description)", width: w, height: h) { flat(c) }
            let r = SCNNode(geometry: piece)
            r.position = SCNVector3(x, -z, y)
            r.name = tile.name
            tile.addChildNode(r)
        }
        for (dx, dz) in [(-1, 0), (1, 0), (0, -1), (0, 1)] where outside(dx, dz) && !door(dx, dz) {
            let (ax, az) = dx != 0 ? (0, 1) : (1, 0)
            func stops(_ x: Int, _ z: Int) -> Bool { outside(x, z) && !door(x, z) }
            let lo = stops(-ax, -az) ? -0.5 + border : -0.5, hi = stops(ax, az) ? 0.5 - border : 0.5
            let length = hi - lo, mid = (lo + hi) / 2
            if dx != 0 { add(wide, length, Double(dx) * at, mid, color, 0.001) } else { add(length, wide, mid, Double(dz) * at, color, 0.001) }
            guard void(dx, dz) else { continue }
            let before = void(-ax, -az) || !outside(-ax, -az) ? over : 0, after = void(ax, az) || !outside(ax, az) ? over : 0
            let run = 1 + before + after, on = (after - before) / 2
            if dx != 0 { add(border + over, run, Double(dx) * edge, on, Palette.void, 0.0015) }
            else { add(run, border + over, on, Double(dz) * edge, Palette.void, 0.0015) }
        }
        for (dx, dz) in [(-1, -1), (1, -1), (-1, 1), (1, 1)] where outside(dx, dz) && !outside(dx, 0) && !outside(0, dz) {
            let side = border + wide, c = 0.5 - side / 2
            add(side, side, Double(dx) * c, Double(dz) * c, color, 0.001)
            if void(dx, dz) { add(border + over, border + over, Double(dx) * edge, Double(dz) * edge, Palette.void, 0.0015) }
        }
    }

    private func addSetPiece(_ piece: SetPiece, _ station: Station) {
        for (area, nodes) in piece.parts {
            for n in nodes { n.name = area.rawValue + ":" + station.name; staticRoot.addChildNode(n) }
        }
    }

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
        owners = [:]
        staticRoot.childNodes.forEach { $0.removeFromParentNode() }
        roomTiles = [:]
        officeParts = [:]
        openEdges = []
        for station in fleet.stations.values {
            for (room, office) in drawnRooms(station) {
                guard let d = office.map({ $0.door }) ?? station.doorCell(of: room.key),
                      let o = office.map({ $0.outside }) ?? station.doorOutside(of: room.key) else { continue }
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
            let gone = (knownHall[station.name] ?? []).filter { !station.isCorridor($0) }
            knownHall[station.name] = station.dugCells
            for (i, c) in gone.reversed().enumerated() {
                let tile = SCNNode()
                propRoot.addChildNode(tile)
                _ = addTile(station: station, cell: c, owner: "corridor", color: Palette.corridor, name: "", into: tile)
                tile.runAction(.sequence([.wait(duration: min(2.4, 0.2 * Double(i))), .fadeOut(duration: 0.5), .removeFromParentNode()]))
            }
            for c in station.corridorCells + station.coreCells {
                let t = addTile(station: station, cell: c, owner: "corridor", color: Palette.corridor, name: "station:" + station.name)
                let order = station.digOrder(of: c)
                if order > oldDug {
                    t.opacity = 0
                    t.runAction(.sequence([.wait(duration: min(2.4, 0.2 * Double(order - oldDug))), .fadeIn(duration: 0.5)]))
                }
            }
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
            let input = Looks.current.input(station)
            if let input { addSetPiece(input, station) } else {
                for c in station.hangarCells {
                    addTile(station: station, cell: c, owner: "kind:hangar", color: NSColor(rgb: Props.hullPlate), name: "hangar:" + station.name)
                }
            }
            let output = Looks.current.output(station, deckInUse: world.deckInUse(station: station.name))
            if let output { addSetPiece(output, station) }
            for door in station.glassDoors {
                let (node, lightHeight) = addGlassDoor(station, at: door.at, facing: door.facing)
                guard door.hatch else { continue }
                let light = SCNNode(geometry: SCNBox(width: 0.2, height: 0.06, length: 0.06, chamferRadius: 0))
                light.geometry!.firstMaterial = flat(Palette.alienLight.darker(0.35))
                light.position = v3(0, lightHeight, door.facing.y * 0.05)
                node.addChildNode(light)
                hatchLights[station.name] = light
            }
            if station.hasHangar, input == nil { buildHangar(station) }
            if output == nil, station.hasPad, Theme.forPlan.kickRises {
                staticRoot.addChildNode(padSlab(station))
            } else {
                for c in station.hall.padCells where output == nil {
                    addTile(station: station, cell: c, owner: "kind:pad", color: Palette.padFloor, name: "pad:" + station.name)
                }
            }
            if station.hasPad, output == nil, let east = station.hall.padCells.map(\.x).max(),
               let y0 = station.hall.padCells.map(\.y).min(), let y1 = station.hall.padCells.map(\.y).max(),
               let hull = Looks.current.hullWall(width: Double(y1 - y0 + 1), depth: Station.hullDepth, doorway: 0, doorTop: 0) {
                hull.eulerAngles.y = -.pi / 2
                hull.position = v3(station.offset.x + Double(east) + 0.56, 0, station.offset.y + Double(y0 + y1) / 2)
                hull.name = "hull:" + station.name
                staticRoot.addChildNode(hull)
            }
            if output == nil {
                let lab = world.deckInUse(station: station.name)
                let storage = Set(station.hall.storageCells), deck = Set(station.hall.deckCells)
                for c in station.hall.cells {
                    let color = storage.contains(c) || (!lab && deck.contains(c)) ? Palette.storageFloor : deck.contains(c) ? Palette.labFloor : Palette.walkFloor
                    addTile(station: station, cell: c, owner: "kind:hall", color: color, name: (deck.contains(c) && lab ? "deck:" : "storage:") + station.name)
                }
            }
            if station.hasPad {
                for c in station.hall.deconCells where output == nil {
                    addTile(station: station, cell: c, owner: "kind:decon", color: Palette.deconFloor, name: "decon:" + station.name)
                }
            }
            buildPadWall(station)
            for prop in Looks.current.dress(station: station) {
                prop.position.x += station.offset.x; prop.position.z += station.offset.y
                prop.name = "station:" + station.name
                staticRoot.addChildNode(prop)
            }
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
            kitchens[station.name] = nil
            if let galley = station.galley, let room = station.rooms["kind:galley"] {
                let f = Looks.current.furnishGalley(galley, in: station)
                for n in f.props { n.name = "room:" + roomKey(station, room); staticRoot.addChildNode(n) }
                for n in f.fixtures { n.name = "gym:" + roomKey(station, room); staticRoot.addChildNode(n) }
                kitchens[station.name] = f.kitchen
            }
            chairs[station.name] = nil
            missionScreens[station.name] = nil
            if let room = station.rooms["kind:mission"], !station.fixtures(in: room.key).isEmpty {
                let f = Looks.current.furnishMission(room, in: station)
                for n in f.props + f.fixtures { n.name = "room:" + roomKey(station, room); staticRoot.addChildNode(n) }
                chairs[station.name] = f.chairs
                if let faces = f.faces {
                    let cameras = feedCameras(station)
                    for c in cameras { c.camera.name = "room:" + roomKey(station, room); staticRoot.addChildNode(c.camera) }
                    missionScreens[station.name] = MissionScreens(annunciator: faces.annunciator, clock: faces.clock,
                                                                  feeds: zip(cameras, faces.feeds).map { .init(name: $0.0.name, camera: $0.0.camera, material: $0.1) },
                                                                  wall: faces.wall)
                }
            }
            if station.hasHangar {
                let hc = station.hangarCenter
                let anchor = hangarAnchors[station.name] ?? { let n = SCNNode(); propRoot.addChildNode(n); hangarAnchors[station.name] = n; return n }()
                anchor.position = v3(station.offset.x + hc.x, 0, station.offset.y + hc.y)
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

            for (room, office) in drawnRooms(station) {
                let key = roomKey(station, room)
                let look = office?.look ?? ShownOffice.Look()
                var tiles: [SCNNode] = []
                var parts: [(node: SCNNode, base: Double?)] = []
                let progress: Double = room.key.hasPrefix("proj:") ? 0 : 1
                let light = officeLight(station, room, dark: look.dark)
                roomLight[key] = light
                roomPower[key] = light != .dark
                let failing = look.failing
                let dusty = look.dusty
                let subfloor = NSColor(rgb: (0.15, 0.16, 0.21))
                let base = officeBase(room, remote: look.remote)
                let full = look.remote ? NSColor(room.color).dimmed(0.82) : NSColor(room.color)
                let provisional = look.provisional
                let unchecked = look.unchecked
                let door = office.map { $0.door } ?? station.doorCell(of: room.key)
                let ordered = room.cells.sorted { (a, b) in
                    let da = abs(a.x - (door?.x ?? a.x)) + abs(a.y - (door?.y ?? a.y))
                    let db = abs(b.x - (door?.x ?? b.x)) + abs(b.y - (door?.y ?? b.y))
                    return da != db ? da < db : (a.y, a.x) < (b.y, b.x)
                }
                let tiled = Int((Double(ordered.count) * progress).rounded())
                let rimmed = Looks.current.rimsOffices && office != nil && !unchecked && !provisional
                let shown = office.map { $0.label(at: clock) } ?? 1
                for (i, c) in ordered.enumerated() {
                    let color = i < tiled || progress == 0 ? officeTone(base, light) : subfloor
                    let t = addTile(station: station, cell: c, owner: room.key, color: color, name: "room:" + key)
                    if rimmed, i < tiled || progress == 0 { rim(t, cell: c, of: room, in: station, color: base) }
                    if let office { t.opacity = CGFloat(tileBase(look) * office.tile(c, at: clock)) }
                    tiles.append(t)
                    if failing || dusty {
                        let overlay = SCNNode(geometry: SCNPlane(width: 1, height: 1))
                        overlay.geometry!.firstMaterial = flat(failing ? NSColor(rgb: (0.95, 0.2, 0.2)) : NSColor(rgb: (0.62, 0.62, 0.68)))
                        overlay.eulerAngles.x = -.pi / 2
                        overlay.position = v3(t.position.x, Looks.current.floorTop + 0.0005, t.position.z)
                        overlay.name = "room:" + key
                        if failing {
                            overlay.opacity = 0.15
                            overlay.runAction(.repeatForever(.sequence([.fadeOpacity(to: 0.5, duration: 0.7), .fadeOpacity(to: 0.12, duration: 0.9)])))
                            parts.append((overlay, nil))
                        } else {
                            overlay.opacity = CGFloat(0.28 * shown)
                            parts.append((overlay, 0.28))
                        }
                        overlay.isHidden = shown < 1 && failing
                        staticRoot.addChildNode(overlay)
                    }
                }
                roomTiles[key] = tiles
                if let office, office.up, let prop = Looks.current.dress(office: room, in: station, sign: sign(for: room, who: look.who)) {
                    prop.position.x += station.offset.x; prop.position.z += station.offset.y
                    prop.name = "room:" + roomKey(station, room)
                    prop.opacity = CGFloat((provisional ? 0.38 : 1) * shown)
                    parts.append((prop, provisional ? 0.38 : 1))
                    staticRoot.addChildNode(prop)
                }
                if provisional || look.live, office?.up == true {
                    let cellSet = Set(room.cells)
                    for c in room.cells {
                        for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] where !cellSet.contains(Cell(x: c.x + dx, y: c.y + dy)) {
                            let edge = SCNNode(geometry: SCNBox(width: dx == 0 ? 1.0 : 0.04, height: 0.01, length: dy == 0 ? 1.0 : 0.04, chamferRadius: 0))
                            edge.geometry!.firstMaterial = flat(full.lighter(0.25))
                            edge.position = v3(station.offset.x + Double(c.x) + Double(dx) * 0.48, 0.006, station.offset.y + Double(c.y) + Double(dy) * 0.48)
                            edge.name = "room:" + key
                            edge.opacity = CGFloat(shown)
                            parts.append((edge, 1))
                            staticRoot.addChildNode(edge)
                        }
                    }
                }
                if office != nil { officeParts[key] = parts }
            }
        }
        groundRoot.childNodes.forEach { $0.removeFromParentNode() }
        if headless {
        } else {
            Looks.current.ground(under: Array(fleet.stations.values), into: groundRoot)
        }
        rebuildLabels()
        rebuildBerths()
        rebuildPadHexes()
        timed("markers") { rebuildMarkers() }

        lastRebuildAt = CACurrentMediaTime()
        let held = userTookView && focused == nil ? (center: targetFocus + userPan, scale: fitScale(half: targetHalf) / userZoom) : nil
        (targetFocus, targetHalf) = frame(for: shownStations)
        if let f = focused { focusNow(on: f) }
        if let held { userPan = held.center - targetFocus; userZoom = min(6, max(0.4, fitScale(half: targetHalf) / held.scale)) }
        fleet.save()
    }

    private func sign(for room: Room, who: String?) -> OfficeSign {
        let digits = room.name.drop { !$0.isNumber }.prefix { $0.isNumber }
        return OfficeSign(number: Int(digits), who: who, name: StationController.displayName(room))
    }

    private static func displayName(_ room: Room) -> String {
        switch room.key {
        case "kind:quarters": return Words.current.dorm
        case "kind:lounge": return Words.current.lounge
        case "kind:bath": return Words.current.bath
        case "kind:galley": return Words.current.galley
        default: return room.name
        }
    }

    private func rebuildLabels() {
        labelRoot.childNodes.forEach { $0.removeFromParentNode() }
        roomLabels = [:]
        ownerSigns = [:]
        floorLabels = []
        for st in fleet.stations.values { st.written = [:] }
        func reserve(_ station: Station, _ key: String, _ center: SIMD2<Double>, _ half: SIMD2<Double>) {
            let lo = center - half, hi = center + half
            for x in Int((lo.x + 0.5).rounded(.down))...Int((hi.x + 0.5).rounded(.down)) {
                for y in Int((lo.y + 0.5).rounded(.down))...Int((hi.y + 0.5).rounded(.down)) { station.written[key, default: []].insert(Cell(x: x, y: y)) }
            }
        }
        func add(_ node: SCNNode, yaw: Double, center: SIMD2<Double>) {
            node.eulerAngles.y = yaw
            let y = node.position.y > 0 ? Double(node.position.y) : 0.01
            node.position = v3(center.x, y, center.y)
            node.enumerateHierarchy { n, _ in n.renderingOrder = 10 }
            labelRoot.addChildNode(node)
            floorLabels.append((node, yaw))
        }
        func corner(of cells: [Cell], width: Double, height: Double, station: Station, clearOf names: Set<String>) -> SIMD2<Double> {
            let o = SIMD2(station.offset.x, station.offset.y)
            let props: [(lo: SIMD2<Double>, hi: SIMD2<Double>)] = staticRoot.childNodes.filter { names.contains($0.name ?? "") }.map { n in
                let (lo, hi) = n.boundingBox
                let pts = [lo.x, hi.x].flatMap { x in [lo.z, hi.z].map { z in staticRoot.convertPosition(SCNVector3(x, 0, z), from: n) } }
                return (SIMD2(Double(pts.map(\.x).min()!), Double(pts.map(\.z).min()!)), SIMD2(Double(pts.map(\.x).max()!), Double(pts.map(\.z).max()!)))
            }
            let x0 = Double(cells.map(\.x).min()!), x1 = Double(cells.map(\.x).max()!)
            let y0 = Double(cells.map(\.y).min()!), y1 = Double(cells.map(\.y).max()!)
            let half = SIMD2(width / 2, height / 2)
            let front = y1 + 0.42 - half.y, back = y0 - 0.42 + half.y, right = x1 + 0.42 - half.x, left = x0 - 0.42 + half.x
            let midX = (x0 + x1) / 2, midY = (y0 + y1) / 2
            let options = [SIMD2(right, front), SIMD2(left, front), SIMD2(right, back), SIMD2(left, back),
                           SIMD2(midX, front), SIMD2(right, midY), SIMD2(left, midY), SIMD2(midX, back)].map { $0 + o }
            func covered(_ c: SIMD2<Double>) -> Double {
                props.reduce(0) { sum, p in
                    let w = min(c.x + half.x, p.hi.x) - max(c.x - half.x, p.lo.x), h = min(c.y + half.y, p.hi.y) - max(c.y - half.y, p.lo.y)
                    return sum + max(0, w) * max(0, h)
                }
            }
            return options.enumerated().min { a, b in
                let ca = covered(a.element), cb = covered(b.element)
                return ca != cb ? ca < cb : a.offset < b.offset
            }!.element
        }
        guard Looks.current.writesOnFloor else { return }
        for station in fleet.stations.values {
            let ox = station.offset.x, oz = station.offset.y
            if station.hasPad {
                var zones: [(String, [Cell])] = [(Words.current.zoneWaiting, station.hall.storageCells)]
                if world.deckInUse(station: station.name) {
                    zones += [(Words.current.zoneTesting, station.hall.stagedCells), (Words.current.zoneCleared, station.hall.clearedCells)]
                }
                if let walkway = station.hall.walkwayCells.first?.x {
                    for (word, cells) in zones where !cells.isEmpty {
                        let label = floorSign(word, color: NSColor(rgb: (0.62, 0.66, 0.76)), size: 0.22)
                        label.node.position.y = 0.012
                        let middle = Double(cells.map(\.y).reduce(0, +)) / Double(cells.count)
                        add(label.node, yaw: .pi / 2, center: SIMD2(Double(walkway), middle) + SIMD2(ox, oz))
                    }
                }
                let deconLabel = floorSign(Words.current.decon, color: NSColor(rgb: (0.36, 0.52, 0.48)), size: 0.22)
                deconLabel.node.position.y = 0.012
                let qc = station.hall.deconCells
                let qcorner = SIMD2(Double(qc.map(\.x).max()!) + 0.42 - deconLabel.width / 2, Double(qc.map(\.y).max()!) + 0.42 - deconLabel.height / 2)
                add(deconLabel.node, yaw: 0, center: qcorner + SIMD2(ox, oz))
                let padLabel = floorSign(Words.current.pad, color: NSColor(rgb: (0.45, 0.48, 0.58)), size: 0.34)
                padLabel.node.position.y = 0.012
                let pc = station.hall.padCells
                let corner = SIMD2(Double(pc.map(\.x).max()!) + 0.42 - padLabel.width / 2, Double(pc.map(\.y).max()!) + 0.42 - padLabel.height / 2)
                add(padLabel.node, yaw: 0, center: corner + SIMD2(ox, oz))
            }
            if station.hasHangar {
                let hangarLabel = floorSign(Words.current.bay, color: NSColor(Colors.hangar).lighter(0.18), size: 0.36)
                hangarLabel.node.position.y = 0.012
                add(hangarLabel.node, yaw: 0, center: corner(of: station.hangarCells, width: hangarLabel.width, height: hangarLabel.height,
                                                             station: station, clearOf: ["bay:" + station.name]))
            }
            let occupied: (Cell) -> Bool = { c in
                station.coreCells.contains(c) || station.hangarCells.contains(c) || station.hall.padCells.contains(c)
                    || station.hall.cells.contains(c) || station.isCorridor(c) || station.room(at: c) != nil
            }
            var placed: [(min: SIMD2<Double>, max: SIMD2<Double>)] = []
            func collides(_ lo: SIMD2<Double>, _ hi: SIMD2<Double>) -> Bool {
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
            for (room, office) in drawnRooms(station) {
                let text = StationController.displayName(room)
                if Station.opensInto[room.key] != nil { continue }
                if room.key.hasPrefix("kind:") {
                    let accent = room.key == "kind:quarters" ? NSColor(Colors.bed) : NSColor(room.color).lighter(0.2)
                    let label = floorSign(text, color: accent, size: 0.36)
                    label.node.position.y = 0.012
                    let key = roomKey(station, room)
                    add(label.node, yaw: 0, center: corner(of: room.cells, width: label.width, height: label.height,
                                                           station: station, clearOf: ["room:" + key, "gym:" + key]))
                    label.node.name = "room:" + roomKey(station, room)
                    roomLabels[roomKey(station, room)] = label.node
                    continue
                }
                let size = max(0.3, min(0.46, 6.4 / Double(max(14, text.count))))
                let minX = room.cells.map(\.x).min()!, maxX = room.cells.map(\.x).max()!
                let minY = room.cells.map(\.y).min()!, maxY = room.cells.map(\.y).max()!
                let width = Double(maxX - minX + 1), depth = Double(maxY - minY + 1)
                let charW = 0.5 * size
                let key = roomKey(station, room)
                var node: SCNNode?

                var stamped: Set<Cell> = []
                if let who = office?.look.who {
                    let maxYRow = room.cells.map(\.y).max()!
                    let cx = room.cells.filter { $0.y == maxYRow }.map(\.x).max()!
                    var run = 0
                    while room.cells.contains(Cell(x: cx - run, y: maxYRow)) { run += 1 }
                    let free = Double(run) - 0.16
                    let words = [who, who.split(separator: " ").first.map(String.init) ?? who]
                    let fits = words.map { w in (w, min(0.3, 0.3 * free / floorSign(w, color: .clear, size: 0.3).width)) }
                    let (word, fit) = fits.first { $0.1 >= 0.17 } ?? fits.last!
                    let sign = floorSign(word, color: StationController.inkOnTile, size: fit)
                    sign.node.position.y = 0.012
                    let corner = SIMD2(Double(cx) + 0.42 - sign.width / 2, Double(maxYRow) + 0.42 - sign.height / 2)
                    add(sign.node, yaw: 0, center: corner + SIMD2(ox, oz))
                    reserve(station, room.key, corner, SIMD2(sign.width / 2, sign.height / 2))
                    sign.node.name = "room:" + key
                    sign.node.opacity = CGFloat(office?.label(at: clock) ?? 1)
                    ownerSigns[key] = sign.node
                    let from = Int((Double(cx) + 0.42 - sign.width + 0.5).rounded(.down))
                    stamped = Set((from...cx).map { Cell(x: $0, y: maxYRow) })
                }

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
                if node == nil, let r = Station.largestRect(in: Set(room.cells).subtracting(stamped)) {
                    let rw = Double(r.hi.x - r.lo.x + 1), rd = Double(r.hi.y - r.lo.y + 1)
                    let horizontal = rw >= rd
                    let along = (horizontal ? rw : rd) - 0.3
                    let across = (horizontal ? rd : rw) - 0.3
                    var size = size * 0.85
                    var lines = max(1, min(3, Int((Double(text.count) * 0.5 * size / along).rounded(.up))))
                    let fitWidth = 3 * along / (Double(text.count) * 0.5)
                    let fitDepth = across / (Double(lines) * 1.15)
                    size = max(0.16, min(size, fitWidth, fitDepth))
                    lines = max(1, min(3, Int((Double(text.count) * 0.5 * size / along).rounded(.up))))
                    let label = floorText(text, color: StationController.inkOnTile, size: size, maxWidth: along, lines: lines, bold: true)
                    let anchor = Cell(x: r.lo.x, y: r.hi.y)
                    let center = horizontal
                        ? SIMD2(ox + Double(anchor.x) - 0.35 + label.width / 2, oz + Double(anchor.y) + 0.35 - label.height / 2)
                        : SIMD2(ox + Double(anchor.x) - 0.35 + label.height / 2, oz + Double(anchor.y) + 0.35 - label.width / 2)
                    label.node.position.y = 0.02
                    add(label.node, yaw: horizontal ? 0 : .pi / 2, center: center)
                    let half = horizontal ? SIMD2(label.width / 2, label.height / 2) : SIMD2(label.height / 2, label.width / 2)
                    reserve(station, room.key, center - SIMD2(ox, oz), half)
                    node = label.node
                }
                guard let node else { continue }
                node.name = "room:" + key
                node.opacity = CGFloat(labelBase(office?.look ?? ShownOffice.Look()) * (office?.label(at: clock) ?? 1))
                roomLabels[key] = node
            }
        }
    }
}
