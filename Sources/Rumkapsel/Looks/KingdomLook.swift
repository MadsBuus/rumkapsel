// Kenney Kingdom: every station a harbour village in a world of its own, drawn in the layers of THEMES.md.
// The world is a coast that curls into a cove round the bay, shallows and foam, meadow, deep woods and a few
// cottages, all keyed to where they stand, so a village that grows only clears the ground round it. The input
// is a stone quay in the cove with a jetty for every landing slot and a causeway out to it; the output a yard
// of customs, granary, market and caravan yard, with a road leading west out of the world, down which releases
// leave as ox carts. The center is a stone keep; the idle areas a tavern fire, a well corner, a training yard
// and straw beds; the growth zone dirt paths and tilled fields with soft edges. Built from Kenney's kits (CC0).

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

    /// A sailing ship, its hull tinted toward the repo colour.
    func shuttle(color: NSColor) -> SCNNode {
        guard let m = Kit.node("unit-ship-large", from: .hexagon, multiply: color.mixed(with: .white, 0.55)) else { return Classic.shuttle(color: color) }
        m.scale = SCNVector3(1.2, 1.2, 1.2)
        m.position = v3(0, -0.15, 0)
        let n = SCNNode()
        n.addChildNode(m)
        return n
    }

    /// Ships sail in from the open sea to the south-east, turn in beside their slot's jetty, and sail back out.
    /// While the slot is taken they wait offshore.
    func shipPose(_ leg: ShipLeg) -> (pos: SIMD3<Double>, yaw: Double)? {
        let s = leg.slot, t = leg.progress
        let moor = SIMD2(s.x + 0.72, s.y + 1.3), off = SIMD2(s.x + 0.72, s.y + 4.2), far = SIMD2(s.x + 9, s.y + 15)
        let smooth = t * t * (3 - 2 * t)
        func heading(_ a: SIMD2<Double>, _ b: SIMD2<Double>) -> Double { atan2(-(b.y - a.y), b.x - a.x) }
        let moored = heading(SIMD2(0, 0), SIMD2(0, -1))   // bow in toward the quay
        let (p, yaw): (SIMD2<Double>, Double) = {
            switch leg.phase {
            case .approach: return (far + (off - far) * (1 - (1 - t) * (1 - t)), heading(far, off))
            case .descend: return (off + (moor - off) * smooth, heading(far, off) + (moored - heading(far, off)) * smooth)
            case .unload: return (moor, moored)
            case .rise: return (moor + (off - moor) * smooth, moored)
            default: return (off + (far - off) * (t * t), heading(off, far))
            }
        }()
        return (SIMD3(p.x, 0, p.y), yaw)
    }

    // MARK: the output

    func output(_ station: Station, deckInUse: Bool) -> SetPiece? {
        guard station.hasPad else { return nil }
        let site = Site(station)
        var piece = SetPiece()
        let all = Set(station.deconCells + station.storageCells + station.deckCells + station.padCells)
        if let rim = site.blob(all, grow: 0.2, Self.dirtEdge, y: -0.02, wobble: 0.24) { piece.add(rim, as: .pad) }
        let areas: [(Area, [Cell], NSColor)] = [
            (.decon, station.deconCells, NSColor(rgb: (0.58, 0.56, 0.53))),
            (.storage, station.storageCells, Self.planks),
            (deckInUse ? .deck : .storage, station.deckCells, NSColor(rgb: (0.73, 0.69, 0.61))),
            (.pad, station.padCells, NSColor(rgb: (0.71, 0.59, 0.43))),
        ]
        for (area, cells, color) in areas where !cells.isEmpty {
            if let n = site.blob(Set(cells), grow: 0.04, color, y: 0.001, wobble: 0) { piece.add(n, as: area) }
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

    /// A release as an ox cart: a high cart and its ox for a tall release, a handcart for a small one, flying
    /// the repo's flag, with the hatch the crates go in by at its tail.
    func rocket(color: NSColor, tall: Bool, cargo: Int) -> SCNNode {
        guard let cart = Kit.node(tall ? "cart-high" : "cart", from: .town) else { return Classic.rocket(color: color, tall: tall, cargo: cargo) }
        let s = tall ? 0.68 + min(0.2, Double(cargo) * 0.02) : 0.62
        cart.scale = SCNVector3(s, s, s)
        let n = SCNNode()
        n.addChildNode(cart)
        if tall, let ox = Kit.node("animal-cow", from: .cubePets) {
            ox.scale = SCNVector3(0.34, 0.34, 0.34)
            ox.position = v3(0, 0, 0.95 * s + 0.3)
            n.addChildNode(ox)
        }
        if let flag = Kit.node("flag", from: .pirate, multiply: color) {
            flag.scale = SCNVector3(0.2, 0.2, 0.2)
            flag.position = v3(0.22, 0.4, -0.3)
            n.addChildNode(flag)
        }
        let hatch = SCNNode(geometry: SCNBox(width: 0.2, height: 0.16, length: 0.02, chamferRadius: 0))
        hatch.geometry!.firstMaterial = lit(Self.wood)
        hatch.position = v3(0, 0.25, -0.5 * s - 0.02)
        hatch.name = "hatch"
        n.addChildNode(hatch)
        let flame = SCNNode()   // nothing burns on a cart
        flame.name = "flame"
        n.addChildNode(flame)
        return n
    }

    /// The cart turns to the road and rolls away west out of the world, fading as it goes.
    func launch(_ rocket: SCNNode) -> SCNAction {
        let turn = SCNAction.rotateTo(x: 0, y: -.pi / 2, z: 0, duration: 1.2, usesShortestUnitArc: true)
        let roll = SCNAction.moveBy(x: -24, y: 0, z: 0, duration: 11)
        roll.timingMode = .easeIn
        return .sequence([turn, .group([roll, .sequence([.wait(duration: 8), .fadeOut(duration: 3)])])])
    }

    // MARK: the center

    /// A stone keep with windows and a high roof, on a round stone square.
    func monolith() -> SCNNode {
        guard let base = Kit.node("tower-square-base", from: .castle), let storey = Kit.node("tower-square-mid-windows", from: .castle),
              let top = Kit.node("tower-square-top-roof-high", from: .castle) else { return Classic.monolith() }
        let n = SCNNode()
        let square = SCNNode(geometry: faceted(SCNCylinder(radius: 1.25, height: 0.02), 8))
        square.geometry!.firstMaterial = flat(Self.stone)
        square.position = v3(0, 0.006, 0)
        n.addChildNode(square)
        let s = 0.74
        for (i, part) in [base, storey, top].enumerated() {
            part.scale = SCNVector3(s, s, s)
            part.position = v3(0, Double(i) * 1.01 * s, 0)
            n.addChildNode(part)
        }
        if let banner = Kit.node("flag-banner-long", from: .castle) {
            banner.scale = SCNVector3(0.32, 0.32, 0.32)
            banner.position = v3(0.36, 0.55, 0)
            n.addChildNode(banner)
        }
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

    /// A well corner: a barrel to sit on where the bowl was, the rest in wood, the towel a linen cloth.
    func furnishBath(_ bath: Room, in station: Station) -> Furnishing {
        var f = Classic.bath(bath, in: station)
        rustic(f.props)
        f.towel?.geometry?.firstMaterial?.diffuse.contents = NSColor(rgb: (0.93, 0.9, 0.8))
        if let bowl = f.props.first, let barrel = Kit.node("barrel", from: .survival) {
            barrel.scale = SCNVector3(0.62, 0.62, 0.62)
            barrel.position = v3(Double(bowl.position.x), 0, Double(bowl.position.z))
            f.props[0] = barrel
        }
        return f
    }

    /// A training yard: the gym's pieces in timber and straw.
    func furnishGym(_ gym: Room, in station: Station) -> Furnishing {
        let f = Classic.gym(gym, in: station)
        rustic(f.fixtures)
        return f
    }

    /// Straw bedrolls on the floor, timber bunks above.
    func bed(level: Int) -> SCNNode {
        let b = Classic.bed(level: level, floorTop: floorTop)
        rustic([b])
        return b
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
        case .hallway: return patch(tile, inset: 0.25, round: 0.24, Self.dirt, crops: false)
        case .room: return patch(tile, inset: 0.07, round: 0.3, Self.soil.mixed(with: tile.color, 0.2), crops: true)
        case .fixed: return patch(tile, inset: 0.05, round: 0.22, tile.color.mixed(with: Self.dirt, 0.62), crops: false)
        default: return nil
        }
    }

    func tint(tile: SCNNode, _ color: NSColor) {
        tile.geometry?.firstMaterial?.diffuse.contents = color
        tile.childNode(withName: "patch", recursively: true)?.geometry?.firstMaterial?.diffuse.contents = Self.soil.mixed(with: color, 0.2)
    }

    /// A soft-edged patch over the tile that runs on into its owner's neighbours, and a field's crop rows on it.
    private func patch(_ tile: Tile, inset: Double, round: Double, _ color: NSColor, crops: Bool) -> SCNNode? {
        guard let shape = Shapes.patch(same: tile.same, inset: inset, round: round)?.copy() as? SCNGeometry,
              let ground = Shapes.node(shape, color, y: 0.002) else { return nil }
        ground.name = "patch"
        let holder = SCNNode()
        holder.eulerAngles.x = .pi / 2   // upright again under a plane tilted flat
        holder.addChildNode(ground)
        if crops, let rows = cropRows(tile.color) { holder.addChildNode(rows) }
        return holder
    }

    private static var rows: [String: SCNNode] = [:]

    /// Two rows of small plants in darker furrows, the same crop across an office, picked by its hue so it holds
    /// while the office's lights come and go; built once a crop and shared.
    private func cropRows(_ color: NSColor) -> SCNNode? {
        let crops: [(String, Double)] = [("crops_wheatStageB", 0.4), ("crop_carrot", 0.36), ("crops_cornStageB", 0.28),
                                         ("crop_turnip", 0.36), ("crop_pumpkin", 0.55), ("crops_wheatStageA", 0.5)]
        let hue = (color.usingColorSpace(.deviceRGB) ?? color).hueComponent
        let crop = crops[Int((hue * 12).rounded()) % crops.count]
        if let built = Self.rows[crop.0] { return built.clone() }
        let n = SCNNode()
        for z in [-0.2, 0.2] {
            let furrow = SCNNode(geometry: SCNBox(width: 0.8, height: 0.004, length: 0.1, chamferRadius: 0))
            furrow.geometry!.firstMaterial = flat(Self.soil.darker(0.25))
            furrow.position = v3(0, 0.004, z)
            n.addChildNode(furrow)
            for x in [-0.22, 0.22] {
                guard let plant = Kit.node(crop.0, from: .nature, tint: Self.cropTint) else { continue }
                plant.scale = SCNVector3(crop.1, crop.1, crop.1)
                plant.position = v3(x, 0.004, z)
                n.addChildNode(plant)
            }
        }
        let built = n.flattenedClone()
        Self.rows[crop.0] = built
        return built.clone()
    }

    /// A small flag in the repo's colour at the field's far edge, so whose field it is reads from afar.
    func dress(office room: Room, in station: Station) -> SCNNode? {
        guard let wall = Dressing.officeWall(room, in: station), let flag = Kit.node("flag", from: .pirate, multiply: NSColor(room.color)) else { return nil }
        flag.scale = SCNVector3(0.18, 0.18, 0.18)
        flag.position = v3(Double(wall.cell.x) + wall.out.x * 0.36, 0, Double(wall.cell.y) + wall.out.y * 0.36)
        return flag
    }

    // MARK: people

    /// A villager, picked by the minion's id so a session is the same villager every time it is seen.
    func figure(id: String, crew: Bool, height: Double) -> SCNNode? {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for b in id.utf8 { h = (h ^ UInt64(b)) &* 0x100_0000_01b3 }
        guard let n = Kit.node(Self.villagers[Int(h % UInt64(Self.villagers.count))], from: .mini) else { return nil }
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
    /// Every floor cell but the airlock's and the bay's: the ground the village stands on.
    let floor: Set<Cell>
    let bayCenter: SIMD2<Double>
    /// The line the coast wanders about: just past the airlock's inner door.
    let shoreline: Double
    /// The road from the caravan yard's west edge out of the world.
    let road: [SIMD2<Double>]
    let lo: SIMD2<Double>, hi: SIMD2<Double>
    /// Cells within reach of the floor and of the road: anywhere else is simply far from both.
    private let nearFloor: Set<Cell>, nearRoad: Set<Cell>

    init(_ st: Station) {
        station = st
        offset = st.offset
        floor = Set(st.allCells).subtracting(st.airlockCells).subtracting(st.hangarCells)
        bayCenter = st.hasHangar ? st.hangarCenter : SIMD2(0, Double(st.bounds.max.y) + 12)
        shoreline = st.airlockInner.first.map { Double($0.y) - 0.5 } ?? Double(st.bounds.max.y) + 6
        let b = st.bounds
        lo = SIMD2(Double(b.min.x) - 26, Double(b.min.y) - 22)
        hi = SIMD2(Double(b.max.x) + 26, Double(b.max.y) + 20)
        var road: [SIMD2<Double>] = []
        if st.hasPad, let west = st.padCells.map(\.x).min() {
            var p = SIMD2(Double(west) - 0.5, st.padCenter.y)
            var k = 0
            while p.x > lo.x - 2 {
                road.append(p)
                p += SIMD2(-0.8, (Noise.value(SIMD2(Double(k) * 0.3, 7)) - 0.5) * 0.8)
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
        let coast = shoreline + (Noise.fbm(SIMD2(p.x, 0.5), scale: 7, seed: 3) - 0.5) * 3.2 - p.y
        let d = p - bayCenter, len = max(0.001, simd_length(d))
        let cove = len - (5 + (Noise.value(d / len * 1.5 + SIMD2(20, 20)) - 0.5) * 1.8)
        return max(min(coast, cove), 1.3 - toFloor(p))
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

    private static var worlds: [String: SCNNode] = [:]

    /// The world round the station: sea, shallows, foam, beach, meadow, road, woods, rocks and cottages. Built
    /// once for a floor and kept, so a redraw that did not move the floor does not rebuild it.
    func world() -> SCNNode {
        let key = "\(station.name)|\(floor.count)|\(floor.map { $0.x &* 31 &+ $0.y }.reduce(0, &+))|\(offset.x),\(offset.y)"
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
        layer(ground, 0.8, KingdomLook.grass, -0.075)
        layer(ground.map { p, v in min(v - 1.2, (Noise.fbm(p, scale: 9, seed: 5) - 0.56) * 8) }, 0, KingdomLook.meadow, -0.072)
        let road = ground.map { p, v in min(v - 0.4, -toRoad(p)) }
        layer(road, -0.64, KingdomLook.dirtEdge, -0.07)
        layer(road, -0.48, KingdomLook.dirt, -0.068)

        let props = SCNNode()
        func put(_ name: String, _ pack: Kit.Pack, _ p: SIMD2<Double>, scale: Double, yaw: Double, tint: [String: NSColor] = [:]) {
            guard let n = Kit.node(name, from: pack, tint: tint) else { return }
            n.scale = SCNVector3(scale, scale, scale)
            n.eulerAngles.y = yaw
            n.position = v3(p.x, -0.07, p.y)
            props.addChildNode(n)
        }
        let forest = ["tree_pineTallA_detailed", "tree_pineTallC_detailed", "tree_pineRoundA", "tree_default_dark", "tree_oak_dark", "tree_fat_darkh", "tree_detailed_dark"]
        let tufts = ["grass_large", "grass", "plant_bush", "flower_yellowA", "flower_redA"]
        for z in Int(lo.y)...Int(hi.y) {
            for x in Int(lo.x)...Int(hi.x) {
                let h1 = Noise.hash(x, z, seed: 21), h2 = Noise.hash(x, z, seed: 22), h3 = Noise.hash(x, z, seed: 23)
                let p = SIMD2(Double(x) + h1 * 0.8 - 0.4, Double(z) + h2 * 0.8 - 0.4)
                let density = Noise.fbm(p, scale: 8, seed: 11)
                let ground = land(p)
                let clear = toFloor(p), road = toRoad(p)
                // Deep woods where the forest noise is high, kept back from the village and the road.
                if density > 0.53, ground > 1.4, clear > 2.8 + h3 * 1.2, road > 1.5 {
                    put(forest[Int(h3 * Double(forest.count)) % forest.count], .nature, p, scale: (0.95 + (density - 0.53) * 2.4) * (0.85 + h1 * 0.3),
                        yaw: h2 * 2 * .pi, tint: KingdomLook.forestTint)
                    continue
                }
                // Rocks along the beach, tufts and flowers on the open meadow.
                if ground > 0.05, ground < 0.7, h3 > 0.86, simd_distance(p, bayCenter) > 6.5 {
                    put(h1 < 0.5 ? "rock_largeA" : "rock_tallA", .nature, p, scale: 0.35 + h2 * 0.3, yaw: h1 * 6.28, tint: KingdomLook.groundTint)
                } else if ground > 1, clear > 1.2, road > 0.8, h3 > 0.9 {
                    put(tufts[Int(h1 * Double(tufts.count)) % tufts.count], .nature, p, scale: 0.8 + h2 * 0.5, yaw: h1 * 6.28, tint: KingdomLook.groundTint)
                }
            }
        }
        // A few cottages in the open, beyond the village and short of the woods.
        for z in stride(from: Int(lo.y), through: Int(hi.y), by: 6) {
            for x in stride(from: Int(lo.x), through: Int(hi.x), by: 6) {
                guard Noise.hash(x, z, seed: 31) > 0.55 else { continue }
                let p = SIMD2(Double(x) + Noise.hash(x, z, seed: 32) * 4, Double(z) + Noise.hash(x, z, seed: 33) * 4)
                let b = station.bounds
                let nearVillage = p.x > Double(b.min.x) - 8 && p.x < Double(b.max.x) + 8 && p.y > Double(b.min.y) - 8 && p.y < Double(b.max.y) + 8
                guard nearVillage, land(p) > 2, toFloor(p) > 2.4, Noise.fbm(p, scale: 8, seed: 11) < 0.48, toRoad(p) > 1.3 else { continue }
                put(Noise.hash(x, z, seed: 34) < 0.7 ? "unit-house" : "unit-mansion", .hexagon, p, scale: 2.3, yaw: Double(Int(Noise.hash(x, z, seed: 35) * 4)) * .pi / 2)
            }
        }
        w.addChildNode(props.flattenedClone())
        w.position = v3(offset.x, 0, offset.y)
        Site.worlds = Site.worlds.filter { !$0.key.hasPrefix(station.name + "|") }
        Site.worlds[key] = w
        return w
    }
}
