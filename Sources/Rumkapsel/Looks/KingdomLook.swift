// Kenney Kingdom: the station as a walled castle on the sea, drawn in the layers of THEMES.md.
// The curtain wall follows the station's own outline, so the castle's shape is the floor plan's and it gains a
// stretch whenever an office opens; offices are flagstoned wards under the house's banner and hallways are
// cobbled. The output is a harbour outside the walls, where a release lies at the quay as a great ship and
// casts off for the open water; the input a caravan gate on the road, where a new office arrives by wagon. The
// center is a keep with four turrets. The ground round it is planned in rings: the ditch and its moat against
// the wall, an open sward, then woods well back, with a hamlet along the road. Built from Kenney's kits (CC0).

import AppKit
import SceneKit

struct KingdomLook: Look {
    static let grass = NSColor(rgb: (0.5, 0.72, 0.36))
    static let meadow = NSColor(rgb: (0.44, 0.66, 0.31))
    static let sand = NSColor(rgb: (0.91, 0.84, 0.63))
    static let foam = NSColor(rgb: (0.88, 0.96, 0.97))
    static let shallows = NSColor(rgb: (0.46, 0.78, 0.85))
    static let water = NSColor(rgb: (0.3, 0.62, 0.79))
    static let deep = NSColor(rgb: (0.2, 0.48, 0.7))
    static let dirt = NSColor(rgb: (0.67, 0.54, 0.38))
    static let dirtEdge = NSColor(rgb: (0.56, 0.45, 0.31))
    static let soil = NSColor(rgb: (0.46, 0.33, 0.21))
    static let stone = NSColor(rgb: (0.69, 0.66, 0.61))
    static let cobble = NSColor(rgb: (0.58, 0.55, 0.52))
    static let stoneEdge = NSColor(rgb: (0.47, 0.45, 0.42))
    static let planks = NSColor(rgb: (0.63, 0.49, 0.33))
    static let wood = NSColor(rgb: (0.5, 0.36, 0.23))
    static let straw = NSColor(rgb: (0.84, 0.73, 0.44))
    static let villagers = ["a", "b", "c", "d", "e", "f"].flatMap { ["character-male-" + $0, "character-female-" + $0] }
    static var forestTint: [String: NSColor] {
        ["leafsDark": NSColor(rgb: (0.22, 0.45, 0.28)), "woodBarkDark": NSColor(rgb: (0.36, 0.26, 0.18)),
         "woodBark": NSColor(rgb: (0.45, 0.33, 0.22)), "woodInner": NSColor(rgb: (0.72, 0.58, 0.4))]
    }
    static var groundTint: [String: NSColor] {
        ["grass": meadow, "leafsGreen": NSColor(rgb: (0.36, 0.6, 0.3)), "dirt": NSColor(rgb: (0.58, 0.54, 0.5)),
         "dirtDark": NSColor(rgb: (0.46, 0.43, 0.4)), "_defaultMat": NSColor(rgb: (0.52, 0.49, 0.46))]
    }
    static var cropTint: [String: NSColor] { ["grass": NSColor(rgb: (0.4, 0.63, 0.27))] }

    // MARK: the world

    var background: NSColor { Self.deep }
    func backdrop(into root: SCNNode) -> [(SCNNode, SIMD2<Double>)] { [] }

    func ground(under stations: [Station], into root: SCNNode) {
        Realm.survey(stations)
        for station in stations { root.addChildNode(Site(station).world()) }
    }

    // MARK: the input

    func input(_ station: Station) -> SetPiece? {
        guard station.hasHangar, !station.hangarCells.isEmpty else { return nil }
        let site = Site(station)
        var piece = SetPiece()
        let bay = Set(station.hangarCells), lock = Set(station.airlockCells)
        for n in [site.blob(bay, grow: 0.16, Self.stoneEdge, y: -0.02), site.blob(bay, grow: 0.05, Self.stone, y: 0.001)] { if let n { piece.add(n, as: .bay) } }
        for n in [site.blob(lock, grow: 0.0, Self.stoneEdge, y: -0.02), site.blob(lock, grow: -0.1, Self.stone, y: 0.001)] { if let n { piece.add(n, as: .airlock) } }
        let xs = station.hangarCells.map(\.x), zs = station.hangarCells.map(\.y)
        let west = Double(xs.min()!), east = Double(xs.max()!), front = Double(zs.min()!), back = Double(zs.max()!)
        // A jetty out from the quay beside every landing slot, where its ship moors.
        for slot in station.hangarSlots {
            let jetty = SCNNode()
            let deck = SCNNode(geometry: SCNBox(width: 0.34, height: 0.05, length: 1.7, chamferRadius: 0))
            deck.geometry!.firstMaterial = lit(Self.planks)
            jetty.addChildNode(deck)
            for (dx, dz) in [(-0.14, -0.7), (0.14, -0.7), (-0.14, 0.1), (0.14, 0.1), (-0.14, 0.8), (0.14, 0.8)] {
                let post = SCNNode(geometry: SCNBox(width: 0.06, height: 0.34, length: 0.06, chamferRadius: 0))
                post.geometry!.firstMaterial = lit(Self.wood)
                post.position = v3(dx, -0.14, dz)
                jetty.addChildNode(post)
            }
            jetty.position = v3(site.offset.x + slot.x + 0.3, 0.0, site.offset.y + back + 1.3)
            piece.add(jetty, as: .bay)
        }
        // Lanterns at the quay's landward corners, goods beside them, and a lighthouse on rocks off the cove's west side.
        for (x, z) in [(west - 0.3, front - 0.3), (east + 0.3, front - 0.3)] {
            if let lamp = Kit.node("lantern", from: .town) {
                lamp.scale = SCNVector3(0.34, 0.34, 0.34)
                lamp.position = v3(site.offset.x + x, 0, site.offset.y + z)
                piece.add(lamp, as: .bay)
            }
        }
        for (i, (name, scale, x, z)) in [("barrel", 0.26, west + 0.05, front + 0.05), ("crate", 0.28, west + 0.1, front + 0.4),
                                          ("chest", 0.24, east - 0.05, front + 0.05)].enumerated() {
            guard let n = Kit.node(name, from: .pirate) else { continue }
            n.scale = SCNVector3(scale, scale, scale)
            n.eulerAngles.y = Double(i) * 0.9
            n.position = v3(site.offset.x + x, 0, site.offset.y + z)
            piece.add(n, as: .bay)
        }
        if let rocks = Kit.node("rocks-sand-a", from: .pirate), let tower = Kit.node("tower-complete-small", from: .pirate) {
            let at = site.bayCenter + SIMD2(-4.4, 2.2)
            rocks.scale = SCNVector3(0.32, 0.2, 0.32)
            rocks.position = v3(site.offset.x + at.x, -0.3, site.offset.y + at.y)
            tower.scale = SCNVector3(0.2, 0.2, 0.2)
            tower.position = v3(site.offset.x + at.x, 0.28, site.offset.y + at.y)
            piece.add(rocks, as: .bay)
            piece.add(tower, as: .bay)
        }
        return piece
    }

    func airlockFrame(width: Double, spans: [Double], tint: NSColor) -> (node: SCNNode, showsPosts: Bool) {
        let row = SCNNode()
        for x in spans {
            guard let gate = Kit.node("gate", from: .castle) else { return Classic.airlockFrame(width: width, spans: spans, tint: tint) }
            gate.eulerAngles.y = .pi / 2   // its face across the doorway
            gate.position = v3(x, 0, 0)
            row.addChildNode(gate)
        }
        return (row, false)
    }

    /// A caravan wagon: a covered cart in the house's colours, drawn by an ox, nose along +x as the scene
    /// expects, so it rolls in the way it is pointed.
    func shuttle(color: NSColor) -> SCNNode {
        let cart = SCNNode()
        let bed = SCNNode(geometry: SCNBox(width: 1.0, height: 0.22, length: 0.52, chamferRadius: 0.04))
        bed.geometry!.firstMaterial = lit(Self.wood)
        bed.position = v3(0, 0.3, 0)
        cart.addChildNode(bed)
        let tilt = SCNNode(geometry: SCNBox(width: 0.82, height: 0.36, length: 0.46, chamferRadius: 0.16))
        tilt.geometry!.firstMaterial = lit(NSColor(rgb: (0.92, 0.89, 0.8)))
        tilt.position = v3(-0.04, 0.56, 0)
        cart.addChildNode(tilt)
        let band = SCNNode(geometry: SCNBox(width: 0.2, height: 0.34, length: 0.48, chamferRadius: 0.14))
        band.geometry!.firstMaterial = lit(color)
        band.position = v3(-0.04, 0.56, 0)
        cart.addChildNode(band)
        for side in [-1.0, 1.0] {
            for x in [-0.3, 0.3] {
                let wheel = SCNNode(geometry: faceted(SCNCylinder(radius: 0.16, height: 0.06), 8))
                wheel.geometry!.firstMaterial = lit(Self.wood.darker(0.2))
                wheel.eulerAngles.x = .pi / 2
                wheel.position = v3(x, 0.16, side * 0.28)
                cart.addChildNode(wheel)
            }
        }
        let shaft = SCNNode(geometry: SCNBox(width: 0.5, height: 0.04, length: 0.04, chamferRadius: 0))
        shaft.geometry!.firstMaterial = lit(Self.wood)
        shaft.position = v3(0.72, 0.26, 0)
        cart.addChildNode(shaft)
        if let ox = Kit.node("animal-cow", from: .cubePets) {
            ox.scale = SCNVector3(0.5, 0.5, 0.5)
            ox.eulerAngles.y = .pi / 2
            ox.position = v3(1.1, 0, 0)
            cart.addChildNode(ox)
        } else {
            let beast = SCNNode(geometry: SCNBox(width: 0.5, height: 0.34, length: 0.32, chamferRadius: 0.06))
            beast.geometry!.firstMaterial = lit(NSColor(rgb: (0.5, 0.4, 0.32)))
            beast.position = v3(1.1, 0.3, 0)
            cart.addChildNode(beast)
        }
        return cart
    }

    func shipPose(_ leg: ShipLeg) -> (pos: SIMD3<Double>, yaw: Double)? {
        let s = leg.slot, t = leg.progress
        // A caravan comes down the road from the south, draws up on its stand, and rolls back out the same way.
        let stand = SIMD2(s.x, s.y), wait = SIMD2(s.x, s.y + 3.6), far = SIMD2(s.x + 1.2, s.y + 17)
        let smooth = t * t * (3 - 2 * t)
        func heading(_ a: SIMD2<Double>, _ b: SIMD2<Double>) -> Double { atan2(-(b.y - a.y), b.x - a.x) }
        let (p, yaw): (SIMD2<Double>, Double) = {
            switch leg.phase {
            case .approach: return (far + (wait - far) * (1 - (1 - t) * (1 - t)), heading(far, wait))
            case .descend: return (wait + (stand - wait) * smooth, heading(wait, stand))
            case .unload: return (stand, heading(wait, stand))
            case .rise: return (stand + (wait - stand) * smooth, heading(stand, wait))
            default: return (wait + (far - wait) * (t * t), heading(wait, far))
            }
        }()
        return (SIMD3(p.x, 0, p.y), yaw)
    }

    // MARK: the output

    func output(_ station: Station, deckInUse: Bool) -> SetPiece? {
        guard station.hasPad else { return nil }
        let site = Site(station)
        var piece = SetPiece()
        let all = Set(station.deconCells + station.storageCells + station.deckCells)
        if let rim = site.blob(all, grow: 0.2, Self.dirtEdge, y: -0.02, wobble: 0.24) { piece.add(rim, as: .pad) }
        let areas: [(Area, [Cell], NSColor)] = [
            (.decon, station.deconCells, NSColor(rgb: (0.62, 0.6, 0.57))),
            (.storage, station.storageCells, NSColor(rgb: (0.58, 0.44, 0.29))),
            (deckInUse ? .deck : .storage, station.deckCells, NSColor(rgb: (0.66, 0.55, 0.38))),
        ]
        for (area, cells, color) in areas where !cells.isEmpty {
            if let n = site.blob(Set(cells), grow: 0.04, color, y: 0.001, wobble: 0) { piece.add(n, as: area) }
        }
        // The harbour: the basin cut into the yard where the pad was, and a timber wharf standing out over it
        // for the whole of it but the outer lane, which is the water a ship lies in.
        let pad = Set(station.padCells)
        if !pad.isEmpty {
            let west = station.padCells.map(\.x).min()!
            let rows = Set(station.padCells.map(\.y))
            // The whole quay is walked on, so the water lies beyond it rather than under it: the basin comes
            // up to the west edge, where the wall stands open, and the boards run to the water's edge.
            // The outer two lanes of the quay are the basin a ship lies in; nobody is sent to stand there,
            // since a berth is always a tile and a half in from the water.
            let berth = pad.filter { $0.x < west + 2 }, deck = pad.filter { $0.x >= west + 2 }
            if let stone = site.blob(deck, grow: 0.42, Self.stoneEdge, y: -0.006, wobble: 0.05) { piece.add(stone, as: .pad) }
            if let boards = site.blob(deck, grow: 0.3, Self.planks, y: 0.001, wobble: 0) { piece.add(boards, as: .pad) }
            // Piles under the quay's lip, standing in the water.
            for c in deck.filter({ $0.x == west + 2 }) {
                for dz in [-0.3, 0.3] {
                    let pile = SCNNode(geometry: SCNBox(width: 0.09, height: 0.42, length: 0.09, chamferRadius: 0))
                    pile.geometry!.firstMaterial = lit(Self.wood.darker(0.2))
                    pile.position = v3(site.offset.x + Double(c.x) - 0.5, 0.06, site.offset.y + Double(c.y) + dz)
                    piece.add(pile, as: .pad)
                }
            }
            for y in rows {
                let seam = SCNNode(geometry: SCNBox(width: 4.2, height: 0.004, length: 0.05, chamferRadius: 0))
                seam.geometry!.firstMaterial = flat(Self.wood)
                seam.position = v3(site.offset.x + Double(west) + 3.6, 0.004, site.offset.y + Double(y) + 0.5)
                piece.add(seam, as: .pad)
            }
            // A crane at the quay head, and goods waiting to go aboard.
            if let mid = rows.sorted().dropFirst(rows.count / 2).first {
                let crane = SCNNode()
                let mast = SCNNode(geometry: SCNBox(width: 0.12, height: 1.15, length: 0.12, chamferRadius: 0))
                mast.geometry!.firstMaterial = lit(Self.wood)
                mast.position = v3(0, 0.58, 0)
                crane.addChildNode(mast)
                let jib = SCNNode(geometry: SCNBox(width: 0.95, height: 0.08, length: 0.08, chamferRadius: 0))
                jib.geometry!.firstMaterial = lit(Self.wood)
                jib.position = v3(-0.4, 1.12, 0)
                crane.addChildNode(jib)
                let rope = SCNNode(geometry: SCNBox(width: 0.02, height: 0.42, length: 0.02, chamferRadius: 0))
                rope.geometry!.firstMaterial = lit(Self.wood.darker(0.3))
                rope.position = v3(-0.82, 0.9, 0)
                crane.addChildNode(rope)
                crane.position = v3(site.offset.x + Double(west) + 2.4, 0, site.offset.y + Double(mid))
                piece.add(crane, as: .pad)
                // Goods along the quay, sized to the men who carry them, not to the kit.
                let goods: [(String, Double, SIMD2<Double>)] = [
                    ("barrel", 0.32, SIMD2(1.1, 0.8)), ("barrel", 0.3, SIMD2(1.45, 1.05)), ("crate", 0.3, SIMD2(1.2, -0.9)),
                    ("chest", 0.26, SIMD2(2.4, 1.2)), ("crate", 0.28, SIMD2(3.4, -1.1)), ("barrel", 0.3, SIMD2(4.1, 0.9)),
                    ("crate", 0.26, SIMD2(4.5, -0.6)), ("barrel", 0.28, SIMD2(2.9, -1.6)),
                ]
                for (k, (name, scale, at)) in goods.enumerated() {
                    guard let n = Kit.node(name, from: .pirate) else { continue }
                    n.scale = SCNVector3(scale, scale, scale)
                    n.eulerAngles.y = Double(k) * 0.8
                    n.position = v3(site.offset.x + Double(west) + 2.2 + at.x, 0.01, site.offset.y + Double(mid) + at.y)
                    piece.add(n, as: .pad)
                }
            }
            // Bollards along the wharf's outer edge, and a crate or two waiting to go aboard.
            for c in deck.filter({ $0.x == west + 2 }) {
                let bollard = SCNNode(geometry: SCNBox(width: 0.11, height: 0.2, length: 0.11, chamferRadius: 0.02))
                bollard.geometry!.firstMaterial = lit(Self.wood)
                bollard.position = v3(site.offset.x + Double(c.x) - 0.38, 0.1, site.offset.y + Double(c.y))
                piece.add(bollard, as: .pad)
            }
        }
        // Boards across the granary and earth ruts across the market, so neither reads as a poured slab.
        for (cells, colour, step) in [(station.storageCells, Self.wood.darker(0.06), 1.0), (station.deckCells, Self.dirtEdge, 1.0)] {
            guard !cells.isEmpty else { continue }
            let x0 = cells.map(\.x).min()!, x1 = cells.map(\.x).max()!
            for y in Set(cells.map(\.y)) {
                let run = SCNNode(geometry: SCNBox(width: Double(x1 - x0) + 0.9, height: 0.004, length: 0.05, chamferRadius: 0))
                run.geometry!.firstMaterial = flat(colour)
                run.opacity = 0.55
                run.position = v3(site.offset.x + Double(x0 + x1) / 2, 0.004, site.offset.y + Double(y) + 0.5 * step)
                piece.add(run, as: cells.first.map { station.storageCells.contains($0) ? .storage : .deck } ?? .storage)
            }
        }
        // A palisade round the yard where it meets open ground, left open at the caravan yard's gate onto the
        // road, at the decon hatch, and wherever floor runs on.
        let floor = Set(station.allCells)
        let hatch = station.deconHatch.0
        let fence = SCNNode()
        for c in all {
            for (dx, dz) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let nb = Cell(x: c.x + dx, y: c.y + dz)
                guard !all.contains(nb), !floor.contains(nb), !(dx == -1 && station.padCells.contains(c)) else { continue }
                let edge = SIMD2(Double(c.x) + Double(dx) * 0.6, Double(c.y) + Double(dz) * 0.6)
                guard simd_distance(edge, hatch) > 0.7 else { continue }
                let rail = SCNNode(geometry: SCNBox(width: dx != 0 ? 0.04 : 1.0, height: 0.04, length: dz != 0 ? 0.04 : 1.0, chamferRadius: 0))
                rail.geometry!.firstMaterial = lit(Self.wood)
                rail.position = v3(site.offset.x + edge.x, 0.24, site.offset.y + edge.y)
                fence.addChildNode(rail)
                for k in 0..<3 {
                    let along = -0.33 + Double(k) * 0.33
                    let height = 0.3 + Noise.hash(c.x &* 7 &+ k, c.y &* 5 &+ dx &+ dz &* 3, seed: 41) * 0.1
                    let post = SCNNode(geometry: SCNBox(width: 0.06, height: height, length: 0.06, chamferRadius: 0.01))
                    post.geometry!.firstMaterial = lit(Self.wood)
                    post.position = v3(site.offset.x + edge.x + (dx == 0 ? along : 0), height / 2, site.offset.y + edge.y + (dz == 0 ? along : 0))
                    fence.addChildNode(post)
                }
            }
        }
        piece.add(fence.flattenedClone(), as: .pad)
        // Hay and barrels by the caravan yard's gate onto the road, and a lantern at the road's start.
        if let start = site.road.first {
            let props: [(String, Kit.Pack, Double, SIMD2<Double>)] = [("box-large", .survival, 1.0, SIMD2(0.3, -1.6)), ("barrel", .survival, 0.9, SIMD2(0.6, 1.8)),
                                                                     ("barrel", .survival, 0.8, SIMD2(0.2, 2.1)), ("lantern", .town, 0.34, SIMD2(-0.2, -1.2))]
            for (name, pack, scale, at) in props {
                guard let n = Kit.node(name, from: pack) else { continue }
                n.scale = SCNVector3(scale, scale, scale)
                n.position = v3(site.offset.x + start.x + at.x, 0, site.offset.y + start.y + at.y)
                piece.add(n, as: .pad)
            }
        }
        return piece
    }

    func hatchFrame(facing: SIMD2<Double>) -> (node: SCNNode, lightHeight: Double) {
        guard let gate = Kit.node("gate", from: .castle) else { return Classic.hatchFrame(facing: facing) }
        gate.eulerAngles.y = facing.x == 0 ? .pi / 2 : 0
        let n = SCNNode()
        n.addChildNode(gate)
        return (n, 1.0)
    }

    /// A release as a great ship lying alongside the quay: a deep clinkered hull with a raised bulwark, a
    /// stern castle, a single square sail in the house's colours and a pennant at the masthead. The hull is
    /// carried out past the boards and set down into the water, with its wash round it, so it reads as
    /// floating rather than standing on the quay; the gangway and the hatch stay on the boards, where a
    /// minion walks up to it.
    func rocket(color: NSColor, tall: Bool, cargo: Int) -> SCNNode {
        let ship = SCNNode()
        let moored = SCNNode()
        let length = tall ? 2.6 : 2.0, beam = tall ? 0.8 : 0.66, depth = 0.42
        func plank(_ w: Double, _ h: Double, _ l: Double, _ c: NSColor, _ at: SIMD3<Double>, chamfer: Double = 0.03) -> SCNNode {
            let n = SCNNode(geometry: SCNBox(width: w, height: h, length: l, chamferRadius: chamfer))
            n.geometry!.firstMaterial = lit(c)
            n.position = v3(at.x, at.y, at.z)
            return n
        }
        // The wash the hull sits in, so its foot is water rather than a cut-off box on the boards.
        let wash = plank(length + 0.5, 0.02, beam + 0.42, Self.foam, SIMD3(0, 0.012, 0), chamfer: 0.2)
        wash.opacity = 0.75
        moored.addChildNode(wash)
        moored.addChildNode(plank(length, depth, beam, Self.wood, SIMD3(0, depth / 2 - 0.08, 0)))
        let bow = plank(beam * 0.78, depth, beam * 0.78, Self.wood, SIMD3(-length / 2, depth / 2 - 0.08, 0))
        bow.eulerAngles.y = .pi / 4
        moored.addChildNode(bow)
        // The bulwark: the strake a hull shows above the water, in the house's colour.
        moored.addChildNode(plank(length + 0.05, 0.12, beam + 0.05, color.darker(0.12), SIMD3(0, depth - 0.02, 0)))
        moored.addChildNode(plank(length - 0.14, 0.04, beam - 0.16, Self.planks, SIMD3(0, depth + 0.02, 0), chamfer: 0))
        moored.addChildNode(plank(0.5, 0.34, beam - 0.1, Self.wood.lighter(0.1), SIMD3(length / 2 - 0.26, depth + 0.16, 0)))
        let mastH = tall ? 1.5 : 1.2
        moored.addChildNode(plank(0.08, mastH, 0.08, Self.wood.darker(0.15), SIMD3(-0.18, depth + mastH / 2, 0), chamfer: 0))
        moored.addChildNode(plank(0.05, 0.05, beam + 0.36, Self.wood.darker(0.15), SIMD3(-0.18, depth + mastH - 0.12, 0), chamfer: 0))
        moored.addChildNode(plank(0.04, mastH * 0.5, beam + 0.3, NSColor(rgb: (0.94, 0.92, 0.86)), SIMD3(-0.18, depth + mastH - 0.12 - mastH * 0.26, 0), chamfer: 0))
        moored.addChildNode(plank(0.045, mastH * 0.17, beam + 0.3, color, SIMD3(-0.18, depth + mastH - 0.12 - mastH * 0.26, 0), chamfer: 0))
        moored.addChildNode(plank(0.02, 0.09, 0.3, color, SIMD3(-0.18, depth + mastH + 0.02, 0.16), chamfer: 0))
        if cargo > 0 {
            for k in 0..<min(3, cargo) {
                guard let box = Kit.node("crate", from: .pirate) else { break }
                box.scale = SCNVector3(0.5, 0.5, 0.5)
                box.position = v3(0.12 + Double(k) * 0.3, depth + 0.06, 0)
                moored.addChildNode(box)
            }
        }
        // Out past the boards, and set down so the waterline is at the quay's foot.
        moored.position = v3(-2.1, -0.06, 0)
        ship.addChildNode(moored)
        // The gangway from the boards down to the stern, and the hatch the crates go in by.
        let gang = plank(1.5, 0.05, 0.3, Self.planks, SIMD3(-1.0, 0.16, 0), chamfer: 0)
        gang.eulerAngles.z = 0.09
        ship.addChildNode(gang)
        let hatch = SCNNode()
        hatch.name = "hatch"
        hatch.position = v3(-0.5, 0.3, 0)
        ship.addChildNode(hatch)
        let wake = plank(0.8, 0.02, beam + 0.3, Self.foam, SIMD3(-1.95 + length / 2 + 0.4, 0.03, 0), chamfer: 0.2)
        wake.name = "flame"
        wake.opacity = 0
        ship.addChildNode(wake)
        return ship
    }

    /// The ship casts off, gathers way and stands out to sea, fading as it goes. Its bow already points that
    /// way, so it leaves forwards.
    func launch(_ rocket: SCNNode) -> SCNAction {
        rocket.childNode(withName: "flame", recursively: true)?.runAction(.fadeIn(duration: 1.2))
        let cast = SCNAction.moveBy(x: -1.2, y: 0, z: 0, duration: 3.5)
        cast.timingMode = .easeIn
        let away = SCNAction.moveBy(x: -26, y: 0, z: 0, duration: 16)
        return .sequence([cast, .group([away, .sequence([.wait(duration: 9), .fadeOut(duration: 5)])])])
    }

    // MARK: the center

    /// The keep: a square donjon on a stone motte, four corner turrets standing above its battlements, a
    /// great door at its foot and the king's banner at the top. It is the first thing the eye finds, so it is
    /// built rather than borrowed.
    func monolith() -> SCNNode {
        let n = SCNNode()
        let block = 1.35, tall = 1.75
        let motte = SCNNode(geometry: faceted(SCNCylinder(radius: 1.35, height: 0.16), 8))
        motte.geometry!.firstMaterial = lit(Self.stoneEdge)
        motte.position = v3(0, 0.08, 0)
        n.addChildNode(motte)
        let apron = SCNNode(geometry: faceted(SCNCylinder(radius: 1.2, height: 0.2), 8))
        apron.geometry!.firstMaterial = lit(Self.stone)
        apron.position = v3(0, 0.14, 0)
        n.addChildNode(apron)
        let shaft = SCNNode(geometry: SCNBox(width: block, height: tall, length: block, chamferRadius: 0.02))
        shaft.geometry!.firstMaterial = lit(Self.wallStone)
        shaft.position = v3(0, 0.22 + tall / 2, 0)
        n.addChildNode(shaft)
        // A string course, then the battlements the wall-walk runs behind.
        let course = SCNNode(geometry: SCNBox(width: block + 0.12, height: 0.08, length: block + 0.12, chamferRadius: 0))
        course.geometry!.firstMaterial = lit(Self.wallShade)
        course.position = v3(0, 0.22 + tall, 0)
        n.addChildNode(course)
        for side in 0..<4 {
            let a = Double(side) * .pi / 2
            for k in -1...1 {
                let merlon = SCNNode(geometry: SCNBox(width: 0.2, height: 0.17, length: 0.16, chamferRadius: 0))
                merlon.geometry!.firstMaterial = lit(Self.wallCap)
                merlon.eulerAngles.y = a
                merlon.position = v3(cos(a) * (block / 2 + 0.02) - sin(a) * Double(k) * 0.42,
                                     0.22 + tall + 0.12,
                                     -sin(a) * (block / 2 + 0.02) - cos(a) * Double(k) * 0.42)
                n.addChildNode(merlon)
            }
        }
        // Four turrets, each carried a little past the keep's own top.
        for (sx, sz) in [(-1.0, -1.0), (1.0, -1.0), (-1.0, 1.0), (1.0, 1.0)] {
            let turret = SCNNode()
            let h = tall + 0.62
            let drum = SCNNode(geometry: faceted(SCNCylinder(radius: 0.26, height: h), 8))
            drum.geometry!.firstMaterial = lit(Self.wallStone)
            drum.position = v3(0, h / 2, 0)
            turret.addChildNode(drum)
            let cap = SCNNode(geometry: faceted(SCNCylinder(radius: 0.31, height: 0.09), 8))
            cap.geometry!.firstMaterial = lit(Self.wallCap)
            cap.position = v3(0, h + 0.045, 0)
            turret.addChildNode(cap)
            for k in 0..<6 {
                let a = Double(k) / 6 * 2 * .pi
                let merlon = SCNNode(geometry: SCNBox(width: 0.11, height: 0.13, length: 0.11, chamferRadius: 0))
                merlon.geometry!.firstMaterial = lit(Self.wallCap)
                merlon.eulerAngles.y = a
                merlon.position = v3(cos(a) * 0.26, h + 0.13, sin(a) * 0.26)
                turret.addChildNode(merlon)
            }
            turret.position = v3(sx * block / 2, 0.22, sz * block / 2)
            n.addChildNode(turret)
        }
        // Tall windows on every face, and the great door at the foot.
        for side in 0..<4 {
            let a = Double(side) * .pi / 2
            for k in [-0.3, 0.3] {
                for y in [0.95, 1.5] {
                    let light = SCNNode(geometry: SCNBox(width: 0.13, height: 0.3, length: 0.05, chamferRadius: 0))
                    light.geometry!.firstMaterial = lit(NSColor(rgb: (0.2, 0.22, 0.28)))
                    light.eulerAngles.y = a
                    light.position = v3(cos(a) * (block / 2 + 0.01) - sin(a) * k, y, -sin(a) * (block / 2 + 0.01) - cos(a) * k)
                    n.addChildNode(light)
                }
            }
        }
        let door = SCNNode(geometry: SCNBox(width: 0.34, height: 0.46, length: 0.06, chamferRadius: 0.1))
        door.geometry!.firstMaterial = lit(Self.wood.darker(0.15))
        door.position = v3(0, 0.45, block / 2 + 0.01)
        n.addChildNode(door)
        let pole = SCNNode(geometry: SCNBox(width: 0.04, height: 0.52, length: 0.04, chamferRadius: 0))
        pole.geometry!.firstMaterial = lit(Self.wood)
        pole.position = v3(0, 0.22 + tall + 0.3, 0)
        n.addChildNode(pole)
        if let banner = Kit.node("flag-banner-long", from: .castle) {
            banner.scale = SCNVector3(0.3, 0.3, 0.3)
            banner.position = v3(0.1, 0.22 + tall + 0.12, 0)
            n.addChildNode(banner)
        }
        return n
    }

    // MARK: the walls

    static let wallStone = NSColor(rgb: (0.72, 0.70, 0.66))
    static let wallShade = NSColor(rgb: (0.57, 0.55, 0.52))
    static let wallCap = NSColor(rgb: (0.80, 0.78, 0.74))
    /// A wall stands about a villager's height: enough to read as a castle from above, low enough that the
    /// floor, its signs and whoever is walking behind it are all still visible.
    static let wallHeight = 0.5
    static let towerHeight = 1.05

    /// The curtain wall, run along the station's own outline, so the castle's shape is the floor plan's and it
    /// grows a new stretch whenever an office opens. Towers stand only at corners well apart from one another,
    /// and the wall opens at the gate and at the road out of the caravan yard.
    func dress(station: Station) -> [SCNNode] {
        // The quay lies outside the walls, as a harbour does, reached by a water gate; the bay is outside too.
        let inside = Set(station.allCells).subtracting(station.hangarCells).subtracting(station.padCells)
        guard !inside.isEmpty else { return [] }
        let key = "\(station.name)|\(inside.count)|\(inside.map { $0.x &* 31 &+ $0.y }.reduce(0, &+))"
        if let built = Self.walls[key] { return [built.clone()] }
        var open = Set<String>()
        for c in station.airlockCells {
            for d in [(0, -1), (0, 1), (1, 0), (-1, 0)] where !inside.contains(Cell(x: c.x + d.0, y: c.y + d.1)) {
                open.insert("\(c.x),\(c.y)|\(d.0),\(d.1)")
            }
        }
        // The water gate: the wall stands open where the quay meets it.
        for c in station.padCells {
            for d in [(1, 0), (0, 1), (0, -1)] where inside.contains(Cell(x: c.x + d.0, y: c.y + d.1)) {
                open.insert("\(c.x + d.0),\(c.y + d.1)|\(-d.0),\(-d.1)")
            }
        }
        let built = curtain(over: inside, gaps: open)
        Self.walls = Self.walls.filter { !$0.key.hasPrefix(station.name + "|") }
        Self.walls[key] = built
        return [built.clone()]
    }

    /// The curtain wall over a set of cells: a stretch of rampart on every edge that faces open ground, with
    /// towers at corners well apart. A straight run is one stone, not one a tile, so a long wall is cheap and
    /// has no seams down it.
    func curtain(over inside: Set<Cell>, gaps: Set<String> = [], merged: Bool = true) -> SCNNode {
        let wall = SCNNode()
        // Every boundary edge, gathered by which way it faces and which line it lies on, so the ones in a row
        // can be drawn as one stretch.
        var runs: [String: [Int]] = [:]
        var corners: [Cell] = []
        for c in inside {
            var out: [(Int, Int)] = []
            for d in [(0, -1), (1, 0), (0, 1), (-1, 0)] where !inside.contains(Cell(x: c.x + d.0, y: c.y + d.1)) { out.append(d) }
            if out.count >= 2 { corners.append(c) }
            for d in out where !gaps.contains("\(c.x),\(c.y)|\(d.0),\(d.1)") {
                let line = d.0 == 0 ? "z|\(d.1)|\(c.y)" : "x|\(d.0)|\(c.x)"
                runs[line, default: []].append(d.0 == 0 ? c.x : c.y)
            }
        }
        for (line, along) in runs {
            let part = line.split(separator: "|")
            let northSouth = part[0] == "z"
            let side = Double(part[1])!, fixed = Double(part[2])!
            for (from, to) in Self.stretches(along.sorted()) {
                let mid = Double(from + to) / 2, length = Double(to - from) + 1
                let at = northSouth ? SIMD2(mid, fixed + side * 0.56) : SIMD2(fixed + side * 0.56, mid)
                wall.addChildNode(Self.rampart(at: at, length: length, along: northSouth))
            }
        }
        var placed: [Cell] = []
        for c in corners.sorted(by: { ($0.x, $0.y) < ($1.x, $1.y) }) {
            guard !placed.contains(where: { abs($0.x - c.x) < 5 && abs($0.y - c.y) < 5 }) else { continue }
            placed.append(c)
            var out = SIMD2<Double>(0, 0)
            for d in [(0, -1), (1, 0), (0, 1), (-1, 0)] where !inside.contains(Cell(x: c.x + d.0, y: c.y + d.1)) {
                out += SIMD2(Double(d.0), Double(d.1))
            }
            wall.addChildNode(Self.tower(at: SIMD2(Double(c.x), Double(c.y)) + out * 0.5))
        }
        return merged ? Self.merge(wall) : wall
    }

    /// Runs of consecutive numbers, as first and last of each.
    private static func stretches(_ sorted: [Int]) -> [(Int, Int)] {
        var out: [(Int, Int)] = []
        var from = sorted.first ?? 0, prev = from
        for v in sorted.dropFirst() {
            if v != prev + 1 { out.append((from, prev)); from = v }
            prev = v
        }
        if !sorted.isEmpty { out.append((from, prev)) }
        return out
    }

    /// Everything under a node as one node per material. `flattenedClone` loses where the pieces stand when
    /// they were never in a scene, so the stones are baked into their own geometry here instead.
    private static func merge(_ node: SCNNode) -> SCNNode {
        let holder = SCNNode()
        var byColor: [String: [SCNNode]] = [:]
        for n in node.childNodes(passingTest: { c, _ in c.geometry != nil }) {
            let c = (n.geometry?.firstMaterial?.diffuse.contents as? NSColor) ?? .white
            byColor["\(c)", default: []].append(n)
        }
        for (_, group) in byColor {
            guard let first = group.first?.geometry?.firstMaterial else { continue }
            let box = SCNNode()
            for n in group {
                let copy = SCNNode(geometry: n.geometry)
                copy.transform = n.worldTransform
                box.addChildNode(copy)
            }
            let flat = box.flattenedClone()
            flat.geometry?.materials = [first]
            holder.addChildNode(flat)
        }
        return holder
    }

    private static var walls: [String: SCNNode] = [:]

    /// A stretch of curtain wall: a stone band on a shadowed foot, with merlons along its top.
    private static func rampart(at p: SIMD2<Double>, length: Double, along northSouth: Bool) -> SCNNode {
        let n = SCNNode()
        let thick = 0.2
        let w = northSouth ? length : thick, l = northSouth ? thick : length
        let face = SCNNode(geometry: SCNBox(width: w, height: wallHeight, length: l, chamferRadius: 0))
        face.geometry!.firstMaterial = lit(wallStone)
        face.position = v3(0, wallHeight / 2, 0)
        n.addChildNode(face)
        let foot = SCNNode(geometry: SCNBox(width: w + 0.08, height: 0.1, length: l + 0.08, chamferRadius: 0))
        foot.geometry!.firstMaterial = lit(wallShade)
        foot.position = v3(0, 0.05, 0)
        n.addChildNode(foot)
        let step = 0.42
        let count = max(1, Int((length / step).rounded()) - 1)
        for k in 0..<count {
            let t = (Double(k) - Double(count - 1) / 2) * step
            let merlon = SCNNode(geometry: SCNBox(width: northSouth ? 0.24 : thick, height: 0.15,
                                                  length: northSouth ? thick : 0.24, chamferRadius: 0))
            merlon.geometry!.firstMaterial = lit(wallCap)
            merlon.position = v3(northSouth ? t : 0, wallHeight + 0.075, northSouth ? 0 : t)
            n.addChildNode(merlon)
        }
        n.position = v3(p.x, 0, p.y)
        return n
    }

    /// A drum tower: a faceted stone shaft with a battlemented head, taller at a gate.
    private static func tower(at p: SIMD2<Double>, gate: Bool = false) -> SCNNode {
        let n = SCNNode()
        let h = gate ? towerHeight + 0.22 : towerHeight, r = gate ? 0.34 : 0.3
        let shaft = SCNNode(geometry: faceted(SCNCylinder(radius: r, height: h), 8))
        shaft.geometry!.firstMaterial = lit(wallStone)
        shaft.position = v3(0, h / 2, 0)
        n.addChildNode(shaft)
        let skirt = SCNNode(geometry: faceted(SCNCylinder(radius: r + 0.06, height: 0.14), 8))
        skirt.geometry!.firstMaterial = lit(wallShade)
        skirt.position = v3(0, 0.07, 0)
        n.addChildNode(skirt)
        let head = SCNNode(geometry: faceted(SCNCylinder(radius: r + 0.05, height: 0.1), 8))
        head.geometry!.firstMaterial = lit(wallCap)
        head.position = v3(0, h + 0.05, 0)
        n.addChildNode(head)
        for k in 0..<6 {
            let a = Double(k) / 6 * 2 * .pi
            let merlon = SCNNode(geometry: SCNBox(width: 0.13, height: 0.15, length: 0.13, chamferRadius: 0))
            merlon.geometry!.firstMaterial = lit(wallCap)
            merlon.eulerAngles.y = a
            merlon.position = v3(cos(a) * r, h + 0.14, sin(a) * r)
            n.addChildNode(merlon)
        }
        n.position = v3(p.x, 0, p.y)
        return n
    }

    // MARK: the idle areas

    /// A tavern fire: the fire where the table stood, logs to sit on where the couches were, barrels in the corners.
    func furnishLounge(_ lounge: Room, in station: Station) -> Furnishing {
        var f = Furnishing()
        let o = station.offset
        let xs = lounge.cells.map(\.x), zs = lounge.cells.map(\.y)
        let cx = Double(xs.reduce(0, +)) / Double(xs.count), cz = Double(zs.reduce(0, +)) / Double(zs.count)
        if let fire = Kit.node("campfire-pit", from: .survival) {
            fire.scale = SCNVector3(1.8, 1.8, 1.8)
            fire.position = v3(o.x + cx, 0, o.y + cz)
            f.props.append(fire)
        }
        for c in station.couches {
            let along = c.x < Double(xs.min()!) - 0.1 || c.x > Double(xs.max()!) + 0.1
            guard let log = Kit.node("log", from: .nature, tint: Self.forestTint) else { continue }
            log.scale = SCNVector3(0.9, 0.9, 0.9)
            log.eulerAngles.y = along ? 0 : .pi / 2
            log.position = v3(o.x + c.x, 0, o.y + c.y)
            f.props.append(log)
        }
        for (x, z) in [(Double(xs.min()!) - 0.28, Double(zs.min()!) - 0.28), (Double(xs.max()!) + 0.1, Double(zs.min()!) - 0.3)] {
            guard let barrel = Kit.node("barrel", from: .survival) else { continue }
            barrel.scale = SCNVector3(0.95, 0.95, 0.95)
            barrel.position = v3(o.x + x, 0, o.y + z)
            f.props.append(barrel)
        }
        return f
    }

    /// A washing corner: a bucket turned over to sit on where the bowl was, a wooden tub under the spout,
    /// the pipes in timber, and a linen cloth on the rail.
    func furnishBath(_ bath: Room, in station: Station) -> Furnishing {
        var f = Classic.bath(bath, in: station)
        rustic(f.props)
        f.towel?.geometry?.firstMaterial?.diffuse.contents = NSColor(rgb: (0.93, 0.9, 0.8))
        if f.props.count > 4 {
            if let bucket = Kit.node("bucket", from: .survival) {
                bucket.scale = SCNVector3(1.1, 1.1, 1.1)
                bucket.position = v3(Double(f.props[0].position.x), 0, Double(f.props[0].position.z))
                f.props[0] = bucket
            }
            let drain = f.props[4]
            let tub = SCNNode(geometry: faceted(SCNCylinder(radius: 0.26, height: 0.14), 8))
            tub.geometry!.firstMaterial = lit(Self.planks)
            tub.position = v3(Double(drain.position.x), 0.07, Double(drain.position.z))
            let water = SCNNode(geometry: faceted(SCNCylinder(radius: 0.21, height: 0.01), 8))
            water.geometry!.firstMaterial = flat(Self.shallows)
            water.position = v3(0, 0.07, 0)
            tub.addChildNode(water)
            f.props[4] = tub
        }
        return f
    }

    /// A training yard: a hay bale where the treadmill was, a log to lift on timber uprights, a straw sack on a
    /// post, all in timber and straw.
    func furnishGym(_ gym: Room, in station: Station) -> Furnishing {
        var f = Classic.gym(gym, in: station)
        rustic(f.fixtures)
        if let tread = f.fixtures.first {
            let bale = SCNNode(geometry: SCNBox(width: 0.42, height: 0.26, length: 0.6, chamferRadius: 0.03))
            bale.geometry!.firstMaterial = lit(Self.straw)
            bale.position = v3(Double(tread.position.x), 0.13, Double(tread.position.z))
            for z in [-0.18, 0.18] {
                let band = SCNNode(geometry: SCNBox(width: 0.44, height: 0.27, length: 0.03, chamferRadius: 0))
                band.geometry!.firstMaterial = lit(Self.wood)
                band.position = v3(0, 0, z)
                bale.addChildNode(band)
            }
            f.fixtures[0] = bale
        }
        if let bar = f.bar {
            bar.childNodes.forEach { $0.removeFromParentNode() }
            let log = SCNNode(geometry: faceted(SCNCylinder(radius: 0.05, height: 0.86), 6))
            log.geometry!.firstMaterial = lit(Self.wood)
            log.eulerAngles.z = .pi / 2
            bar.geometry = nil
            bar.addChildNode(log)
        }
        return f
    }

    /// Straw bedrolls on the floor; above, a timber bunk with a bedroll on it.
    func bed(level: Int) -> SCNNode {
        guard let roll = Kit.node("bedroll", from: .survival) else { return Classic.bed(level: level, floorTop: floorTop) }
        roll.scale = SCNVector3(0.85, 0.85, 0.85)
        roll.geometry?.materials.forEach { $0.multiply.contents = NSColor(rgb: (0.95, 0.85, 0.62)) }
        if level == 0 {
            let n = SCNNode()
            roll.position = v3(0, 0.06, 0)
            n.addChildNode(roll)
            return n
        }
        let bunk = Classic.bed(level: level, floorTop: floorTop)
        rustic([bunk])
        roll.position = v3(0, 0.06, 0)
        bunk.addChildNode(roll)
        return bunk
    }

    // MARK: work in the village

    /// No welding at a field: working a message is digging, hoeing, reaping and looking it over by lantern.
    var workSparks: Bool { false }

    /// Village tools for the station's: a hoe to swing for the hammer, a spade for the goggles, a sickle-like axe
    /// for the scanner, a hanging lantern for the torch, a scroll for the tablet, a ledger for the clipboard and a
    /// wooden staff for the wand.
    func tool(_ tool: Minion.Tool, height h: Double, depth d: Double) -> SCNNode? {
        let n = SCNNode()
        /// A kit tool lying along the body's facing: its handle's foot at the grip, its head outward.
        func held(_ name: String, _ scale: Double) -> SCNNode? {
            guard let m = Kit.node(name, from: .survival) else { return nil }
            m.scale = SCNVector3(scale, scale, scale)
            m.eulerAngles.x = .pi / 2
            return m
        }
        switch tool {
        case .hammer:
            guard let hoe = held("tool-hoe", 1.5) else { return nil }
            let pivot = SCNNode()
            pivot.name = "swing"
            pivot.position = v3(0.07, h * 0.42, d / 2 + 0.04)
            pivot.eulerAngles.x = Minion.hammerRest
            pivot.addChildNode(hoe)
            n.addChildNode(pivot)
        case .goggles:
            guard let spade = held("tool-shovel", 1.3) else { return nil }
            let grip = SCNNode()
            grip.position = v3(0.08, h * 0.34, d / 2 + 0.04)
            grip.eulerAngles.x = 0.7   // blade down into the soil ahead
            grip.addChildNode(spade)
            n.addChildNode(grip)
        case .scanner:
            guard let axe = held("tool-axe", 1.3) else { return nil }
            let grip = SCNNode()
            grip.position = v3(0.08, h * 0.3, d / 2 + 0.06)
            grip.eulerAngles.x = 0.25
            grip.addChildNode(axe)
            n.addChildNode(grip)
        case .flashlight:
            guard let lantern = Kit.node("lantern", from: .town) else { return nil }
            let pivot = SCNNode()
            pivot.name = "aim"
            pivot.position = v3(0.07, h * 0.36, d / 2 + 0.05)
            lantern.scale = SCNVector3(0.1, 0.1, 0.1)
            lantern.position = v3(0, -0.16, 0.06)
            pivot.addChildNode(lantern)
            let light = SCNNode()
            light.light = SCNLight()
            light.light!.type = .omni
            light.light!.color = NSColor(rgb: (1.0, 0.82, 0.5))
            light.light!.intensity = 380
            light.light!.attenuationEndDistance = 1.4
            light.position = v3(0, -0.08, 0.06)
            pivot.addChildNode(light)
            n.addChildNode(pivot)
        case .tablet:
            let scroll = SCNNode(geometry: SCNBox(width: 0.17, height: 0.006, length: 0.12, chamferRadius: 0))
            scroll.geometry!.firstMaterial = flat(NSColor(rgb: (0.95, 0.9, 0.76)))
            scroll.position = v3(0, h * 0.28, d / 2 + 0.09)
            scroll.eulerAngles.x = 0.35
            for z in [-0.065, 0.065] {
                let rod = SCNNode(geometry: faceted(SCNCylinder(radius: 0.014, height: 0.21), 6))
                rod.geometry!.firstMaterial = lit(Self.wood)
                rod.eulerAngles.z = .pi / 2
                rod.position = v3(0, 0.008, z)
                scroll.addChildNode(rod)
            }
            let ink = SCNNode(geometry: SCNBox(width: 0.11, height: 0.002, length: 0.05, chamferRadius: 0))
            ink.geometry!.firstMaterial = flat(NSColor(rgb: (0.45, 0.36, 0.28)))
            ink.position = v3(0, 0.005, 0)
            scroll.addChildNode(ink)
            n.addChildNode(scroll)
        case .clipboard:
            let book = SCNNode(geometry: SCNBox(width: 0.13, height: 0.17, length: 0.035, chamferRadius: 0.005))
            book.geometry!.firstMaterial = lit(NSColor(rgb: (0.45, 0.24, 0.18)))
            book.position = v3(0.16, h * 0.24, d / 2 + 0.02)
            book.eulerAngles = SCNVector3(0.25, -0.5, 0.15)
            let pages = SCNNode(geometry: SCNBox(width: 0.115, height: 0.15, length: 0.037, chamferRadius: 0))
            pages.geometry!.firstMaterial = flat(NSColor(rgb: (0.94, 0.9, 0.8)))
            pages.position = v3(0.01, 0, 0)
            book.addChildNode(pages)
            n.addChildNode(book)
        case .telekinesis:
            let pivot = SCNNode()
            pivot.position = v3(0.07, h * 0.36, d / 2 + 0.04)
            pivot.eulerAngles.x = -0.5
            let staff = SCNNode(geometry: faceted(SCNCylinder(radius: 0.018, height: 0.34), 6))
            staff.geometry!.firstMaterial = lit(Self.wood)
            staff.eulerAngles.x = .pi / 2
            staff.position = v3(0, 0, 0.1)
            pivot.addChildNode(staff)
            let tip = SCNNode(geometry: faceted(SCNCone(topRadius: 0, bottomRadius: 0.035, height: 0.08), 5))
            tip.geometry!.firstMaterial = flat(NSColor(rgb: (1.0, 0.86, 0.45)))
            tip.eulerAngles.x = .pi / 2
            tip.position = v3(0, 0, 0.3)
            tip.opacity = 0.45
            tip.name = "wandTip"
            pivot.addChildNode(tip)
            let light = SCNNode()
            light.light = SCNLight()
            light.light!.type = .omni
            light.light!.color = NSColor(rgb: (1.0, 0.86, 0.45))
            light.light!.intensity = 0
            light.light!.attenuationEndDistance = 2.0
            light.position = v3(0, 0, 0.31)
            light.name = "wandLight"
            pivot.addChildNode(light)
            n.addChildNode(pivot)
        case .hands:
            return nil
        }
        return n
    }

    /// A message as a sheaf of wheat tied with a ribbon in the office's colour.
    func message(color: NSColor, floor: NSColor) -> SCNNode? {
        guard let wheat = Kit.node("crops_wheatStageB", from: .nature, tint: Self.cropTint) else { return nil }
        let n = SCNNode()
        wheat.scale = SCNVector3(0.75, 0.75, 0.75)
        n.addChildNode(wheat)
        let ribbon = SCNNode(geometry: faceted(SCNCylinder(radius: 0.09, height: 0.05), 8))
        ribbon.geometry!.firstMaterial = flat(color)
        ribbon.position = v3(0, 0.14, 0)
        n.addChildNode(ribbon)
        return n
    }

    /// Recolour classic furniture: its greys become timber, its colours straw.
    private func rustic(_ nodes: [SCNNode]) {
        for root in nodes {
            for n in [root] + root.childNodes(passingTest: { _, _ in true }) {
                for m in n.geometry?.materials ?? [] {
                    guard let c = (m.diffuse.contents as? NSColor)?.usingColorSpace(.deviceRGB) else { continue }
                    m.diffuse.contents = c.saturationComponent > 0.22 ? Self.straw.mixed(with: Self.wood, 0.25 * (1 - c.brightnessComponent))
                                                                      : Self.wood.mixed(with: Self.straw, 0.5 * c.brightnessComponent)
                }
            }
        }
    }

    // MARK: the growth zone

    var dotsHallway: Bool { false }
    var drawsBorders: Bool { false }
    func drawsPlane(_ floor: Floor) -> Bool { !(floor == .hallway || floor == .room || floor == .fixed) }

    func tileDetail(_ tile: Tile) -> SCNNode? {
        switch tile.floor {
        case .hallway: return patch(tile, inset: 0.18, round: 0.2, Self.cobble, flags: true)
        case .room: return patch(tile, inset: 0.07, round: 0.16, Self.ward(tile.color), flags: true)
        case .fixed: return patch(tile, inset: 0.06, round: 0.16, Self.ward(tile.color).darker(0.08), flags: true)
        default: return nil
        }
    }

    func tint(tile: SCNNode, _ color: NSColor) {
        tile.geometry?.firstMaterial?.diffuse.contents = color
        tile.childNode(withName: "patch", recursively: true)?.geometry?.firstMaterial?.diffuse.contents = Self.ward(color)
    }

    /// A soft-edged patch over the tile that runs on into its owner's neighbours, with flagstones scored on it.
    private func patch(_ tile: Tile, inset: Double, round: Double, _ color: NSColor, flags: Bool) -> SCNNode? {
        guard let shape = Shapes.patch(same: tile.same, inset: inset, round: round)?.copy() as? SCNGeometry,
              let ground = Shapes.node(shape, color, y: 0.002) else { return nil }
        ground.name = "patch"
        let holder = SCNNode()
        holder.eulerAngles.x = .pi / 2   // upright again under a plane tilted flat
        holder.addChildNode(ground)
        if flags, let stones = flagstones(tile) { holder.addChildNode(stones) }
        return holder
    }

    private static var paving: [String: SCNNode] = [:]

    /// A ward's paving: the repo's colour worked into stone rather than laid on it, so a courtyard still reads
    /// as whose it is from across the map while looking like a paved yard up close.
    static func ward(_ color: NSColor) -> NSColor {
        stone.mixed(with: color, 0.42).darker(0.02)
    }

    /// Flagstones scored into a tile: a few darker joints, their pattern following the cell so neighbouring
    /// tiles do not repeat. Built once per pattern and shared.
    private func flagstones(_ tile: Tile) -> SCNNode? {
        let pattern = Int(tile.same % 4)
        if let built = Self.paving["\(pattern)"] { return built.clone() }
        let n = SCNNode()
        let joint = flat(NSColor(rgb: (0.32, 0.31, 0.30)))
        func score(_ x: Double, _ z: Double, _ w: Double, _ l: Double) {
            let s = SCNNode(geometry: SCNBox(width: w, height: 0.003, length: l, chamferRadius: 0))
            s.geometry!.firstMaterial = joint
            s.opacity = 0.3
            s.position = v3(x, 0.005, z)
            n.addChildNode(s)
        }
        score(0, -0.16 + Double(pattern) * 0.04, 0.9, 0.028)
        score(0, 0.24 - Double(pattern) * 0.05, 0.9, 0.028)
        score(-0.2 + Double(pattern) * 0.07, -0.34, 0.028, 0.34)
        score(0.26 - Double(pattern) * 0.06, 0.06, 0.028, 0.46)
        let built = n.flattenedClone()
        Self.paving["\(pattern)"] = built
        return built.clone()
    }

    /// Nothing is lettered on a castle's ground: a ward is known by the banner at its wall.
    var writesOnFloor: Bool { false }

    /// The house's banner at the ward's outer wall: a pole, a long cloth in the repo's colour and the
    /// office's name on it, so whose courtyard it is and what is being done there both read from across the
    /// map without writing on the flagstones.
    func dress(office room: Room, in station: Station) -> SCNNode? {
        guard let wall = Dressing.officeWall(room, in: station) else { return nil }
        let n = SCNNode()
        let pole = SCNNode(geometry: SCNBox(width: 0.05, height: 1.3, length: 0.05, chamferRadius: 0))
        pole.geometry!.firstMaterial = lit(Self.wood)
        pole.position = v3(0, 0.65, 0)
        n.addChildNode(pole)
        let cloth = SCNNode(geometry: SCNBox(width: 0.4, height: 0.62, length: 0.02, chamferRadius: 0))
        cloth.geometry!.firstMaterial = lit(NSColor(room.color))
        cloth.position = v3(0.21, 0.9, 0)
        n.addChildNode(cloth)
        let fringe = SCNNode(geometry: SCNBox(width: 0.4, height: 0.08, length: 0.025, chamferRadius: 0))
        fringe.geometry!.firstMaterial = lit(NSColor(room.color).darker(0.25))
        fringe.position = v3(0.21, 0.56, 0)
        n.addChildNode(fringe)
        // The name, sewn across the cloth rather than cut into the floor.
        let text = room.name
        let c = (NSColor(room.color).usingColorSpace(.deviceRGB) ?? .gray)
        let ink = c.brightnessComponent > 0.62 ? NSColor(rgb: (0.16, 0.14, 0.12)) : NSColor(rgb: (0.96, 0.94, 0.88))
        let sign = floorSign(text.count > 14 ? String(text.prefix(13)) + "…" : text, color: ink, size: 0.1)
        sign.node.eulerAngles.x = .pi / 2
        sign.node.eulerAngles.y = .pi / 2
        sign.node.position = v3(0.21, 0.9, 0.02)
        n.addChildNode(sign.node)
        n.eulerAngles.y = atan2(wall.out.x, wall.out.y)
        n.position = v3(Double(wall.cell.x) + wall.out.x * 0.34, 0, Double(wall.cell.y) + wall.out.y * 0.34)
        return n
    }

    /// The pallet is ordered at a writing lectern with a ledger open on it, not a lit panel.
    func console(color: NSColor) -> SCNNode? {
        let n = SCNNode()
        let post = SCNNode(geometry: SCNBox(width: 0.08, height: 0.5, length: 0.08, chamferRadius: 0))
        post.geometry!.firstMaterial = lit(Self.wood)
        post.position = v3(0, -0.25, 0)
        n.addChildNode(post)
        let desk = SCNNode(geometry: SCNBox(width: 0.34, height: 0.05, length: 0.26, chamferRadius: 0.01))
        desk.geometry!.firstMaterial = lit(Self.wood.lighter(0.1))
        desk.eulerAngles.x = -0.5
        n.addChildNode(desk)
        let book = SCNNode(geometry: SCNBox(width: 0.24, height: 0.035, length: 0.18, chamferRadius: 0))
        book.geometry!.firstMaterial = lit(NSColor(rgb: (0.93, 0.9, 0.82)))
        book.eulerAngles.x = -0.5
        book.position = v3(0, 0.05, 0.02)
        book.name = "panel"
        n.addChildNode(book)
        let quill = SCNNode(geometry: SCNBox(width: 0.02, height: 0.22, length: 0.02, chamferRadius: 0))
        quill.geometry!.firstMaterial = lit(NSColor(rgb: (0.95, 0.95, 0.92)))
        quill.eulerAngles.z = 0.4
        quill.position = v3(0.14, 0.11, 0.02)
        n.addChildNode(quill)
        return n
    }

    /// A crate of work as a bound chest: boards, iron straps and a lid painted in the house's colour. No
    /// lamps on it — a castle has none to put there.
    func crate(color: NSColor) -> SCNNode? {
        let n = SCNNode()
        let body = SCNNode(geometry: SCNBox(width: 0.46, height: 0.2, length: 0.34, chamferRadius: 0.02))
        body.geometry!.firstMaterial = lit(Self.wood)
        body.position = v3(0, 0.1, 0)
        n.addChildNode(body)
        let lid = SCNNode(geometry: SCNBox(width: 0.47, height: 0.08, length: 0.35, chamferRadius: 0.03))
        lid.geometry!.firstMaterial = lit(color.mixed(with: Self.wood, 0.3))
        lid.position = v3(0, 0.23, 0)
        n.addChildNode(lid)
        for x in [-0.14, 0.14] {
            let strap = SCNNode(geometry: SCNBox(width: 0.04, height: 0.3, length: 0.36, chamferRadius: 0))
            strap.geometry!.firstMaterial = lit(NSColor(rgb: (0.38, 0.36, 0.34)))
            strap.position = v3(x, 0.14, 0)
            n.addChildNode(strap)
        }
        let lock = SCNNode(geometry: SCNBox(width: 0.07, height: 0.07, length: 0.04, chamferRadius: 0.01))
        lock.geometry!.firstMaterial = lit(NSColor(rgb: (0.72, 0.62, 0.3)))
        lock.position = v3(0, 0.19, 0.18)
        n.addChildNode(lock)
        return n
    }

    /// The handcart the goods ride on: a plank bed on two wheels with a pair of shafts, in the house's
    /// colour. Its bed stands where the classic pallet's does, so the crates set into it still land right.
    func pallet(color: NSColor) -> SCNNode? {
        let n = SCNNode()
        let bed = SCNNode(geometry: SCNBox(width: Props.palletWidth, height: 0.05, length: Props.palletDepth, chamferRadius: 0.01))
        bed.geometry!.firstMaterial = lit(Self.planks)
        n.addChildNode(bed)
        let frame = SCNNode(geometry: SCNBox(width: Props.palletWidth - 0.12, height: 0.06, length: Props.palletDepth - 0.12, chamferRadius: 0))
        frame.geometry!.firstMaterial = lit(Self.wood)
        frame.position = v3(0, -0.05, 0)
        n.addChildNode(frame)
        for side in [-1.0, 1.0] {
            let rail = SCNNode(geometry: SCNBox(width: Props.palletWidth, height: 0.05, length: 0.05, chamferRadius: 0))
            rail.geometry!.firstMaterial = lit(color.mixed(with: Self.wood, 0.45))
            rail.position = v3(0, 0.04, side * (Props.palletDepth / 2 - 0.02))
            n.addChildNode(rail)
            let wheel = SCNNode(geometry: faceted(SCNCylinder(radius: 0.17, height: 0.05), 8))
            wheel.geometry!.firstMaterial = lit(Self.wood.darker(0.2))
            wheel.eulerAngles.x = .pi / 2
            wheel.position = v3(0, -0.1, side * (Props.palletDepth / 2 - 0.04))
            n.addChildNode(wheel)
        }
        for side in [-1.0, 1.0] {
            let shaft = SCNNode(geometry: SCNBox(width: 0.34, height: 0.035, length: 0.035, chamferRadius: 0))
            shaft.geometry!.firstMaterial = lit(Self.wood)
            shaft.position = v3(Props.palletWidth / 2 + 0.15, -0.02, side * 0.12)
            n.addChildNode(shaft)
        }
        return n
    }

    /// A release not yet cleared is roped off with pennants, not taped.
    func hold(tall: Bool) -> SCNNode? {
        let n = SCNNode()
        let radius = 0.78
        for k in 0..<4 {
            let a = Double(k) / 4 * 2 * .pi + .pi / 4
            let post = SCNNode(geometry: SCNBox(width: 0.06, height: 0.42, length: 0.06, chamferRadius: 0))
            post.geometry!.firstMaterial = lit(Self.wood)
            post.position = v3(cos(a) * radius, 0.21, sin(a) * radius)
            n.addChildNode(post)
            let b = Double(k + 1) / 4 * 2 * .pi + .pi / 4
            let from = SIMD2(cos(a) * radius, sin(a) * radius), to = SIMD2(cos(b) * radius, sin(b) * radius)
            let mid = (from + to) / 2, span = simd_distance(from, to)
            let rope = SCNNode(geometry: SCNBox(width: span, height: 0.02, length: 0.02, chamferRadius: 0))
            rope.geometry!.firstMaterial = lit(NSColor(rgb: (0.78, 0.72, 0.55)))
            rope.eulerAngles.y = atan2(-(to.y - from.y), to.x - from.x)
            rope.position = v3(mid.x, 0.36, mid.y)
            n.addChildNode(rope)
            for t in [0.0] {
                let flag = SCNNode(geometry: SCNBox(width: 0.16, height: 0.2, length: 0.012, chamferRadius: 0))
                flag.geometry!.firstMaterial = lit(NSColor(rgb: (0.76, 0.62, 0.26)))
                flag.eulerAngles.y = rope.eulerAngles.y
                let at = mid + (to - from) * t
                flag.position = v3(at.x, 0.25, at.y)
                n.addChildNode(flag)
            }
        }
        return n
    }

    // MARK: people
    // MARK: people

    /// Earthy dyes a tunic could be made in, so a crowd reads as a village and not as a paint chart.
    static let tunics: [NSColor] = [
        NSColor(rgb: (0.55, 0.28, 0.24)), NSColor(rgb: (0.35, 0.42, 0.55)), NSColor(rgb: (0.45, 0.47, 0.32)),
        NSColor(rgb: (0.62, 0.5, 0.28)), NSColor(rgb: (0.4, 0.34, 0.42)), NSColor(rgb: (0.3, 0.45, 0.4)),
        NSColor(rgb: (0.6, 0.42, 0.26)), NSColor(rgb: (0.46, 0.3, 0.34)),
    ]
    static let skins: [NSColor] = [
        NSColor(rgb: (0.87, 0.72, 0.57)), NSColor(rgb: (0.75, 0.57, 0.42)), NSColor(rgb: (0.55, 0.39, 0.29)),
        NSColor(rgb: (0.93, 0.8, 0.68)), NSColor(rgb: (0.42, 0.3, 0.24)),
    ]

    /// A figure of the castle, built rather than borrowed: a hooded villager in a dyed tunic, or a guard in
    /// mail with a helm for the crew. The kit's own people wear suits and carry satchels, which no castle
    /// ever did. Picked by the minion's id, so a session is the same person every time it is seen.
    func figure(id: String, crew: Bool, height: Double) -> SCNNode? {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for b in id.utf8 { h = (h ^ UInt64(b)) &* 0x100_0000_01b3 }
        let tunic = crew ? NSColor(rgb: (0.55, 0.56, 0.6)) : Self.tunics[Int(h % UInt64(Self.tunics.count))]
        let skin = Self.skins[Int((h >> 8) % UInt64(Self.skins.count))]
        let hooded = !crew && (h >> 16) % 3 != 0
        let n = SCNNode()
        func part(_ w: Double, _ hh: Double, _ l: Double, _ c: NSColor, _ y: Double, _ x: Double = 0, _ z: Double = 0, chamfer: Double = 0.01) {
            let b = SCNNode(geometry: SCNBox(width: w, height: hh, length: l, chamferRadius: chamfer))
            b.geometry!.firstMaterial = lit(c)
            b.position = v3(x, y, z)
            n.addChildNode(b)
        }
        let hose = NSColor(rgb: (0.32, 0.28, 0.24))
        for side in [-1.0, 1.0] { part(0.075, 0.2, 0.09, hose, 0.1, side * 0.055) }
        for side in [-1.0, 1.0] { part(0.09, 0.05, 0.13, Self.wood.darker(0.25), 0.025, side * 0.055, 0.01) }
        // The tunic, belted, with a skirt a little wider than the chest.
        part(0.26, 0.22, 0.17, tunic, 0.3)
        part(0.23, 0.2, 0.15, tunic.lighter(0.06), 0.5)
        part(0.245, 0.04, 0.16, Self.wood.darker(0.1), 0.4)
        for side in [-1.0, 1.0] { part(0.055, 0.19, 0.08, tunic.darker(0.06), 0.5, side * 0.14) }
        for side in [-1.0, 1.0] { part(0.055, 0.05, 0.075, skin, 0.38, side * 0.14) }
        part(0.19, 0.17, 0.17, skin, 0.68)
        if crew {
            // A guard: a mail coif, a helm with a nasal, and a surcoat band.
            part(0.21, 0.1, 0.19, NSColor(rgb: (0.6, 0.61, 0.64)), 0.62)
            part(0.21, 0.09, 0.2, NSColor(rgb: (0.72, 0.73, 0.76)), 0.79)
            part(0.2, 0.05, 0.21, NSColor(rgb: (0.66, 0.67, 0.7)), 0.73)
            part(0.04, 0.1, 0.03, NSColor(rgb: (0.66, 0.67, 0.7)), 0.73, 0, 0.1)
        } else if hooded {
            part(0.22, 0.13, 0.2, tunic.darker(0.12), 0.78)
            part(0.2, 0.12, 0.09, tunic.darker(0.12), 0.7, 0, -0.07)
        } else {
            let hair = [NSColor(rgb: (0.26, 0.18, 0.12)), NSColor(rgb: (0.5, 0.36, 0.18)), NSColor(rgb: (0.72, 0.62, 0.42)),
                        NSColor(rgb: (0.2, 0.18, 0.18))][Int((h >> 24) % 4)]
            part(0.2, 0.07, 0.18, hair, 0.79)
            part(0.2, 0.12, 0.06, hair, 0.72, 0, -0.07)
        }
        // Eyes, so it reads as a person at a glance rather than a peg.
        for side in [-1.0, 1.0] { part(0.03, 0.035, 0.02, NSColor(rgb: (0.16, 0.13, 0.12)), 0.7, side * 0.045, 0.088, chamfer: 0) }
        pose(figure: n, height: height, torso: height)
        return n
    }

    /// Scaled to the box's height by its own; on a seat it shortens, feet at the box's new foot.
    func pose(figure: SCNNode, height: Double, torso: Double) {
        let s = height / max(0.1, Double(figure.boundingBox.max.y))
        figure.scale = SCNVector3(s, s * torso / height, s)
        figure.position = v3(0, -torso / 2, -0.02)
    }
}

/// One station's village as the Kingdom lays it out, in the station's own cells: where its floor is, where the
/// coast runs and curls into the cove round the bay, and where the road leaves.
private struct Site {
    let station: Station
    let offset: SIMD2<Double>
    /// Every floor cell but the airlock's, the bay's and the quay's: the ground the castle stands on. The
    /// quay is left out so the water can come right up to it rather than being pushed off by dry land.
    let floor: Set<Cell>
    let bayCenter: SIMD2<Double>
    /// The line the coast wanders about, in x: just past the quay's outer edge, so the sea lies beyond the
    /// harbour and a release sails out of it. Everything landward of it is the castle's ground.
    let shoreline: Double
    /// The middle of the quay, which the harbour basin is scooped out around.
    let quay: SIMD2<Double>
    /// The road from the caravan yard's west edge out of the world.
    let road: [SIMD2<Double>]
    let lo: SIMD2<Double>, hi: SIMD2<Double>
    /// Cells within reach of the floor and of the road: anywhere else is simply far from both.
    private let nearFloor: Set<Cell>, nearRoad: Set<Cell>

    init(_ st: Station) {
        station = st
        offset = st.offset
        floor = Set(st.allCells).subtracting(st.airlockCells).subtracting(st.hangarCells).subtracting(st.padCells)
        bayCenter = st.hasHangar ? st.hangarCenter : SIMD2(0, Double(st.bounds.max.y) + 12)
        quay = st.hasPad ? st.padCenter : SIMD2(Double(st.bounds.min.x) - 4, 0)
        shoreline = (st.hasPad ? Double(st.padCells.map(\.x).min()!) : Double(st.bounds.min.x)) + 1.55
        let b = st.bounds
        lo = SIMD2(Double(b.min.x) - 26, Double(b.min.y) - 22)
        hi = SIMD2(Double(b.max.x) + 26, Double(b.max.y) + 20)
        var road: [SIMD2<Double>] = []
        if st.hasHangar, let far = st.hangarCells.map(\.y).max() {
            var p = SIMD2(bayCenter.x, Double(far) + 0.5)
            var k = 0
            while p.y < hi.y + 2 {
                road.append(p)
                p += SIMD2((Noise.value(SIMD2(Double(k) * 0.3, 7)) - 0.5) * 0.9, 0.8)
                k += 1
            }
        }
        self.road = road
        var near = Set<Cell>()
        for c in floor { for dz in -3...3 { for dx in -3...3 { near.insert(Cell(x: c.x + dx, y: c.y + dz)) } } }
        nearFloor = near
        near = []
        for p in road { for dz in -2...2 { for dx in -2...2 { near.insert(Cell(x: Int(p.x.rounded()) + dx, y: Int(p.y.rounded()) + dz)) } } }
        nearRoad = near
    }

    /// How many tiles out from the nearest castle in the fleet a point is: what the ground round it is
    /// planned by. `toFloor` measures finely but only three tiles out, and only this station's own floor.
    func out(_ p: SIMD2<Double>) -> Double { Realm.out(p + offset) }

    /// How far outside the nearest floor cell's square a point is, negative inside; 99 when none is within three cells.
    func toFloor(_ p: SIMD2<Double>) -> Double {
        nearFloor.contains(Cell(x: Int(p.x.rounded()), y: Int(p.y.rounded()))) ? Site.toCells(p, floor) : 99
    }

    static func toCells(_ p: SIMD2<Double>, _ cells: Set<Cell>) -> Double {
        let cx = Int(p.x.rounded()), cz = Int(p.y.rounded())
        var best = 99.0
        for dz in -3...3 {
            for dx in -3...3 {
                let c = Cell(x: cx + dx, y: cz + dz)
                guard cells.contains(c) else { continue }
                let q = simd_abs(p - SIMD2(Double(c.x), Double(c.y))) - SIMD2(0.5, 0.5)
                best = min(best, simd_length(simd_max(q, SIMD2(0, 0))) + min(max(q.x, q.y), 0))
            }
        }
        return best
    }

    /// How far inside a set of cells a point is, taken as one shape: positive inside, negative outside, so the
    /// seams between two of its cells are inside too.
    static func inside(_ p: SIMD2<Double>, _ cells: Set<Cell>) -> Double {
        let here = Cell(x: Int(p.x.rounded()), y: Int(p.y.rounded()))
        guard cells.contains(here) else { return -toCells(p, cells) }
        var best = 2.0
        for dz in -2...2 {
            for dx in -2...2 {
                let c = Cell(x: here.x + dx, y: here.y + dz)
                guard !cells.contains(c) else { continue }
                let q = simd_abs(p - SIMD2(Double(c.x), Double(c.y))) - SIMD2(0.5, 0.5)
                best = min(best, simd_length(simd_max(q, SIMD2(0, 0))) + min(max(q.x, q.y), 0))
            }
        }
        return best
    }

    func toRoad(_ p: SIMD2<Double>) -> Double {
        guard road.count > 1, nearRoad.contains(Cell(x: Int(p.x.rounded()), y: Int(p.y.rounded()))) else { return 99 }
        var best = 99.0
        for i in 1..<road.count {
            let a = road[i - 1], ab = road[i] - a
            let t = min(1, max(0, simd_dot(p - a, ab) / simd_length_squared(ab)))
            best = min(best, simd_distance(p, a + ab * t))
        }
        return best
    }

    /// How far onto land a point is: positive on land, negative at sea. The coast wanders about the shoreline
    /// and curls round the cove; the village's own floor always stands on land.
    func land(_ p: SIMD2<Double>) -> Double {
        let coast = p.x - (shoreline + (Noise.fbm(SIMD2(0.5, p.y), scale: 9, seed: 3) - 0.5) * 4.4)
        // The basin: open water scooped in front of the quay so a ship has somewhere to lie and to sail out by.
        let d = p - SIMD2(shoreline - 4, quay.y), len = max(0.001, simd_length(d))
        let basin = len - (10 + (Noise.value(d / len * 1.5 + SIMD2(20, 20)) - 0.5) * 3)
        return max(min(coast, basin), 1.2 - toFloor(p))
    }

    /// A soft-edged shape over some of the station's cells, `grow` past their squares and wobbling a little, in the world.
    func blob(_ cells: Set<Cell>, grow: Double, _ color: NSColor, y: Double, wobble: Double = 0.16) -> SCNNode? {
        guard let x0 = cells.map(\.x).min(), let x1 = cells.map(\.x).max(), let z0 = cells.map(\.y).min(), let z1 = cells.map(\.y).max() else { return nil }
        let geometry = Shapes.fill(from: SIMD2(Double(x0) - 1, Double(z0) - 1), to: SIMD2(Double(x1) + 1, Double(z1) + 1), step: 0.1) { p in
            grow + (Noise.value(p * 1.6 + SIMD2(40, 40)) - 0.5) * wobble + Site.inside(p, cells)
        }
        let n = Shapes.node(geometry, color, y: y)
        n?.position.x = offset.x
        n?.position.z = offset.y
        return n
    }

    /// The road out, sampled every few steps from where it leaves the ditch: where a hamlet would stand.
    func road2() -> [SIMD2<Double>] {
        stride(from: 6, to: road.count, by: 5).map { road[$0] }
    }

    private static var worlds: [String: SCNNode] = [:]

    /// The world round the station: sea, shallows, foam, beach, meadow, road, woods, rocks and cottages. Built
    /// once for a floor and kept, so a redraw that did not move the floor does not rebuild it.
    func world() -> SCNNode {
        let key = "\(station.name)|\(floor.count)|\(floor.map { $0.x &* 31 &+ $0.y }.reduce(0, &+))|\(offset.x),\(offset.y)|\(Realm.key.hashValue)"
        if let w = Site.worlds[key] { return w }
        let w = SCNNode()
        let sea = SCNNode(geometry: SCNPlane(width: hi.x - lo.x + 240, height: hi.y - lo.y + 240))
        sea.geometry!.firstMaterial = flat(KingdomLook.deep)
        sea.eulerAngles.x = -.pi / 2
        sea.position = v3((lo.x + hi.x) / 2, -0.1, (lo.y + hi.y) / 2)
        w.addChildNode(sea)
        func layer(_ grid: Shapes.Grid, _ level: Double, _ color: NSColor, _ y: Double) {
            if let n = Shapes.node(Shapes.fill(grid, level: level), color, y: y) { w.addChildNode(n) }
        }
        // The land sampled once; the sea's bands, the beach and the grass are cut from it at rising levels.
        let ground = Shapes.sample(from: lo, to: hi, step: 0.4) { land($0) }
        layer(ground, -2.8, KingdomLook.water, -0.095)
        layer(ground, -1.2, KingdomLook.shallows, -0.09)
        layer(ground, -0.3, KingdomLook.foam, -0.085)
        layer(ground, 0, KingdomLook.sand, -0.08)
        layer(ground, 0.45, KingdomLook.grass, -0.075)
        layer(ground.map { p, v in min(v - 1.2, (Noise.fbm(p, scale: 9, seed: 5) - 0.56) * 8) }, 0, KingdomLook.meadow, -0.072)
        let road = ground.map { p, v in min(v - 0.4, -toRoad(p)) }
        layer(road, -0.64, KingdomLook.dirtEdge, -0.07)
        layer(road, -0.48, KingdomLook.dirt, -0.068)
        // The moat: a ring of water in the ditch outside the wall, cut where the causeway and the road cross it.
        let ditch = Shapes.sample(from: lo, to: hi, step: 0.25) { p in
            let d = toFloor(p)
            guard d < 4 else { return -1 }
            let ring = min(d - 1.15, 2.15 - d)
            let crossing = max(1.3 - toRoad(p), 2.2 - Double(abs(p.x - shoreline) < 6 ? 0 : 9))
            return min(ring, -crossing)
        }
        layer(ditch, -0.25, KingdomLook.dirtEdge.darker(0.1), -0.066)
        layer(ditch, 0, KingdomLook.water.darker(0.18), -0.064)

        let props = SCNNode()
        func put(_ name: String, _ pack: Kit.Pack, _ p: SIMD2<Double>, scale: Double, yaw: Double, tint: [String: NSColor] = [:]) {
            guard let n = Kit.node(name, from: pack, tint: tint) else { return }
            n.scale = SCNVector3(scale, scale, scale)
            n.eulerAngles.y = yaw
            n.position = v3(p.x, -0.07, p.y)
            props.addChildNode(n)
        }
        // The land round a castle is planned in rings, not scattered: bare ground and the ditch against the
        // wall, then an open sward nothing is built on, then outliers, and only well back from it the woods.
        let sward = 7.5, edge = 15.0
        let forest = ["tree_pineTallA_detailed", "tree_pineTallC_detailed", "tree_pineRoundA", "tree_default_dark", "tree_oak_dark", "tree_fat_darkh", "tree_detailed_dark"]
        let tufts = ["grass_large", "grass", "plant_bush", "flower_yellowA", "flower_redA"]
        for z in Int(lo.y)...Int(hi.y) {
            for x in Int(lo.x)...Int(hi.x) {
                let h1 = Noise.hash(x, z, seed: 21), h2 = Noise.hash(x, z, seed: 22), h3 = Noise.hash(x, z, seed: 23)
                let p = SIMD2(Double(x) + h1 * 0.8 - 0.4, Double(z) + h2 * 0.8 - 0.4)
                let ground = land(p)
                let clear = out(p), road = toRoad(p)
                guard ground > 0.05, road > 1.3, clear > 3.5 else { continue }
                if clear > sward, ground > 1.4 {
                    // How much wood stands here: none at the sward's edge, all of it once well back.
                    let depth = min(1, (clear - sward) / (edge - sward))
                    let density = Noise.fbm(p, scale: 11, seed: 11) * depth
                    if density > 0.54 {
                        let big = 0.62 + min(0.45, (density - 0.54) * 2.0) + h1 * 0.2
                        put(forest[Int(h3 * Double(forest.count)) % forest.count], .nature, p, scale: big,
                            yaw: h2 * 2 * .pi, tint: KingdomLook.forestTint)
                        continue
                    }
                }
                // A haystack or a woodpile on the open sward, where a castle's stores would stand.
                if clear > 4, clear < 9, ground > 1.6, h3 > 0.955 {
                    put(h1 < 0.5 ? "log" : "rock_tallA", .nature, p, scale: h1 < 0.5 ? 0.8 : 0.4,
                        yaw: h2 * 6.28, tint: KingdomLook.groundTint)
                    continue
                }
                // Rocks along the beach, tufts and flowers on the open sward.
                if ground > 0.05, ground < 0.7, h3 > 0.88, simd_distance(p, bayCenter) > 6.5 {
                    put(h1 < 0.5 ? "rock_largeA" : "rock_tallA", .nature, p, scale: 0.3 + h2 * 0.25, yaw: h1 * 6.28, tint: KingdomLook.groundTint)
                } else if ground > 1, h3 > 0.87 {
                    put(tufts[Int(h1 * Double(tufts.count)) % tufts.count], .nature, p, scale: 0.7 + h2 * 0.4, yaw: h1 * 6.28, tint: KingdomLook.groundTint)
                }
            }
        }
        // A hamlet strung along the road where it leaves the castle, rather than houses dropped about the map.
        for (i, at) in road2().enumerated() {
            guard Noise.hash(i * 7, 3, seed: 31) > 0.42 else { continue }
            let side: Double = Noise.hash(i * 7, 5, seed: 32) < 0.5 ? -1 : 1
            let off = 3.6 + Noise.hash(i * 7, 9, seed: 33) * 2.2
            let p = at + SIMD2(0, side * off)
            guard land(p) > 1.6, out(p) > 5, toRoad(p) > 2.6 else { continue }
            put(Noise.hash(i * 7, 11, seed: 34) < 0.72 ? "unit-house" : "unit-mansion", .hexagon, p, scale: 2.0,
                yaw: side < 0 ? 0 : .pi)
        }
        w.addChildNode(props.flattenedClone())
        w.position = v3(offset.x, 0, offset.y)
        Site.worlds = Site.worlds.filter { !$0.key.hasPrefix(station.name + "|") }
        Site.worlds[key] = w
        return w
    }
}


/// The whole fleet's ground, surveyed once a redraw: how many tiles from the nearest castle every cell near
/// one is. Castles stand side by side in one landscape, so what grows between two of them has to keep back
/// from both; a site that knew only its own floor planted a wood over its neighbour.
enum Realm {
    private(set) static var ring: [Cell: Int] = [:]
    private(set) static var key = ""

    static func survey(_ stations: [Station]) {
        let k = stations.map { "\($0.name):\($0.allCells.count):\($0.offset.x),\($0.offset.y)" }.sorted().joined(separator: "|")
        guard k != key else { return }
        key = k
        var ring: [Cell: Int] = [:]
        var front: [Cell] = []
        for st in stations {
            let ox = Int(st.offset.x.rounded()), oz = Int(st.offset.y.rounded())
            let bay = Set(st.hangarCells)
            for c in st.allCells where !bay.contains(c) {
                let w = Cell(x: c.x + ox, y: c.y + oz)
                if ring[w] == nil { ring[w] = 0; front.append(w) }
            }
        }
        var step = 0
        while !front.isEmpty, step < 20 {
            step += 1
            var next: [Cell] = []
            for c in front {
                for (dx, dz) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                    let n = Cell(x: c.x + dx, y: c.y + dz)
                    if ring[n] == nil { ring[n] = step; next.append(n) }
                }
            }
            front = next
        }
        Realm.ring = ring
    }

    /// Tiles out from the nearest castle, to twenty; past that, twenty-one.
    static func out(_ world: SIMD2<Double>) -> Double {
        Double(ring[Cell(x: Int(world.x.rounded()), y: Int(world.y.rounded()))] ?? 21)
    }
}
