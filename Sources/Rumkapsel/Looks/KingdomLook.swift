// Kenney Kingdom: the station as a harbour village, bright as a handheld town. The hallways are the
// green itself and offices worked plots of tilled soil with a crop and the repo's flag; the yard is
// cobbled and hedged, the monolith a castle keep, the airlock and the decon hatch castle gates, the bay a
// stone quay with a pier at each slot and a lighthouse off its end, and what stands on the pad a siege
// engine flying the repo's flag. Low cliffs along the coast, deep woods and hamlets on the land. Villagers
// for minions, sailing ships for shuttles. The floor plan is Classic's. Built from Kenney's Castle Kit,
// Fantasy Town Kit, Nature Kit, Pirate Kit, Mini Characters and Hexagon Kit (CC0); where a model is missing
// from the bundle, the classic piece stands in.

import AppKit
import SceneKit

struct KingdomLook: Look {
    static let grass = NSColor(rgb: (0.49, 0.74, 0.38))
    static let sand = NSColor(rgb: (0.9, 0.84, 0.68))
    static let cobble = NSColor(rgb: (0.72, 0.68, 0.6))
    static let earth = NSColor(rgb: (0.66, 0.54, 0.38))
    static let stone = NSColor(rgb: (0.6, 0.6, 0.64))
    static let water = NSColor(rgb: (0.42, 0.7, 0.87))
    static let beach = NSColor(rgb: (0.93, 0.87, 0.66))
    static let planks = NSColor(rgb: (0.64, 0.48, 0.32))
    static let soil = NSColor(rgb: (0.55, 0.41, 0.28))
    static let quay = NSColor(rgb: (0.62, 0.6, 0.57))
    static let foam = NSColor(rgb: (0.8, 0.92, 0.96))
    /// The Nature Kit's colours, brought to the Kingdom's: tilled soil, crop leaves, the deep woods and cliff rock.
    static var soilTint: [String: NSColor] { ["dirt": NSColor(rgb: (0.5, 0.36, 0.24)), "dirtDark": NSColor(rgb: (0.38, 0.27, 0.18))] }
    static var cropTint: [String: NSColor] { ["grass": NSColor(rgb: (0.4, 0.62, 0.28))] }
    static var forestTint: [String: NSColor] {
        ["leafsDark": NSColor(rgb: (0.2, 0.43, 0.27)), "woodBarkDark": NSColor(rgb: (0.36, 0.26, 0.18)),
         "woodBark": NSColor(rgb: (0.45, 0.33, 0.22)), "woodInner": NSColor(rgb: (0.72, 0.58, 0.4))]
    }
    static var cliffTint: [String: NSColor] { ["grass": grass, "dirt": NSColor(rgb: (0.56, 0.52, 0.48)), "_defaultMat": NSColor(rgb: (0.5, 0.47, 0.44))] }
    static let villagers = ["a", "b", "c", "d", "e", "f"].flatMap { ["character-male-" + $0, "character-female-" + $0] }

    var background: NSColor { NSColor(rgb: (0.55, 0.76, 0.92)) }
    var dotsHallway: Bool { false }
    /// Fences and hedges part the floors; no dark lines on the green.
    var drawsBorders: Bool { false }

    func backdrop(into root: SCNNode) -> [(SCNNode, SIMD2<Double>)] { [] }

    /// A harbour town on its shore. Land lies behind each station's hull, up to the airlock's inner door;
    /// the water starts there, so the airlock is a causeway out over it and the bay a dock, and it runs on
    /// down to the next row of stations like a channel, or out to sea past the last. Floor that reaches past
    /// a shore stands on made ground. A beach along every shore, woods in clusters on the land and hamlets
    /// of cottages between them, all from a fixed seed.
    func ground(under stations: [Station], into root: SCNNode) {
        guard let fp = fleetFootprint(stations) else { return }
        typealias Box = (x0: Double, x1: Double, z0: Double, z1: Double)
        func draw(_ b: Box, _ color: NSColor, _ y: Double) {
            guard b.x1 > b.x0, b.z1 > b.z0 else { return }
            let n = SCNNode(geometry: SCNPlane(width: b.x1 - b.x0, height: b.z1 - b.z0))
            n.geometry!.firstMaterial = flat(color)
            n.eulerAngles.x = -.pi / 2
            n.position = v3((b.x0 + b.x1) / 2, y, (b.z0 + b.z1) / 2)
            root.addChildNode(n)
        }
        let west = fp.lo.x - 70, east = fp.hi.x + 70
        draw((west, east, fp.lo.y - 70, fp.hi.y + 70), Self.grass, -0.06)
        var waters: [Box] = [], lands: [Box] = []
        for st in stations {
            guard let inner = st.airlockInner.first else { continue }   // no bay, no harbour: all land
            let b = st.bounds
            let shore = Double(inner.y) + st.offset.y - 0.5
            let next = stations.map { Double($0.bounds.min.y) + $0.offset.y }.filter { $0 > shore }.min()
            // The water opens east of the bay, so the yard to the west keeps its land and the coast turns there.
            let cove = Double(st.hangarCells.map(\.x).min() ?? inner.x) + st.offset.x - 3
            waters.append((cove, east, shore, next.map { $0 - 2.5 } ?? shore + 70))
            lands.append((Double(b.min.x) + st.offset.x - 2.5, Double(b.max.x) + st.offset.x + 2.5, Double(b.min.y) + st.offset.y - 2.5, shore))
            let outside = Set(st.airlockCells + st.hangarCells)
            for c in st.allCells where !outside.contains(c) && Double(c.y) + st.offset.y > shore - 0.5 {
                let x = Double(c.x) + st.offset.x, z = Double(c.y) + st.offset.y
                lands.append((x - 0.75, x + 0.75, z - 0.75, z + 0.75))
            }
        }
        // Beaches first, so a strip that runs into another stretch of water is drowned by it.
        for w in waters {
            draw((w.x0 - 0.6, w.x1, w.z0 - 0.6, w.z0), Self.beach, -0.055)
            draw((w.x0 - 0.6, w.x1, w.z1, w.z1 + 0.6), Self.beach, -0.055)
            draw((w.x0 - 0.6, w.x0, w.z0 - 0.6, w.z1 + 0.6), Self.beach, -0.055)
        }
        for w in waters { draw(w, Self.water, -0.05) }
        for l in lands { draw(l, Self.grass, -0.04) }
        // Foam where the water meets the land.
        for w in waters {
            draw((w.x0, w.x1, w.z0, w.z0 + 0.22), Self.foam, -0.045)
            draw((w.x0, w.x0 + 0.22, w.z0, w.z1), Self.foam, -0.045)
            if w.z1 < w.z0 + 69 { draw((w.x0, w.x1, w.z1 - 0.22, w.z1), Self.foam, -0.045) }
        }

        func inside(_ p: SIMD2<Double>, _ b: Box, _ margin: Double) -> Bool {
            p.x > b.x0 - margin && p.x < b.x1 + margin && p.y > b.z0 - margin && p.y < b.z1 + margin
        }
        func onLand(_ p: SIMD2<Double>) -> Bool {
            lands.contains { inside(p, $0, -0.2) } || !waters.contains { inside(p, $0, 1.0) }
        }
        let onStation = { (p: SIMD2<Double>, margin: Double) -> Bool in
            fp.each.contains { p.x > $0.lo.x - margin && p.x < $0.hi.x + margin && p.y > $0.lo.y - margin && p.y < $0.hi.y + margin }
        }
        var rng = Scatter(seed: 11)
        func put(_ name: String, _ pack: Kit.Pack, at p: SIMD2<Double>, scale: Double, yaw: Double) {
            guard let n = Kit.node(name, from: pack) else { return }
            n.scale = SCNVector3(scale, scale, scale)
            n.eulerAngles.y = yaw
            n.position = v3(p.x, -0.035, p.y)
            root.addChildNode(n)
        }
        func anywhere() -> SIMD2<Double> { SIMD2(rng.between(fp.lo.x - 26, fp.hi.x + 26), rng.between(fp.lo.y - 20, fp.hi.y + 20)) }
        func nature(_ name: String, at p: SIMD2<Double>, scale: Double, yaw: Double, tint: [String: NSColor], y: Double = -0.035) {
            guard let n = Kit.node(name, from: .nature, tint: tint) else { return }
            n.scale = SCNVector3(scale, scale, scale)
            n.eulerAngles.y = yaw
            n.position = v3(p.x, y, p.y)
            root.addChildNode(n)
        }

        // The coast: low cliffs in runs with sandy gaps between, their faces to the water.
        for w in waters {
            var x = w.x0 + 0.5
            while x < min(w.x1, fp.hi.x + 30) {
                let run = Int(rng.between(3, 9)), gap = rng.between(2, 6)
                for k in 0..<run {
                    let p = SIMD2(x + Double(k), w.z0 - 0.02)
                    guard !onStation(p, 0.8) else { continue }
                    nature("cliff_half_rock", at: p, scale: 1, yaw: 0, tint: Self.cliffTint, y: -0.05)
                    if w.z1 < w.z0 + 69 { nature("cliff_half_rock", at: SIMD2(p.x, w.z1 + 0.02), scale: 1, yaw: .pi, tint: Self.cliffTint, y: -0.05) }
                }
                x += Double(run) + gap
            }
            var z = w.z0 + 0.5
            while z < w.z1 {
                let p = SIMD2(w.x0 - 0.02, z)
                if !onStation(p, 0.8) { nature("cliff_half_rock", at: p, scale: 1, yaw: .pi / 2, tint: Self.cliffTint, y: -0.05) }
                z += 1
            }
        }

        // Deep woods: dark pines and broad trees crowded together, thinning at the edge, stumps and logs about it.
        let forest: [(String, Double, Double)] = [("tree_pineTallA_detailed", 1.3, 1.9), ("tree_pineTallC_detailed", 1.3, 1.9), ("tree_pineRoundA", 1.1, 1.6),
                                                  ("tree_default_dark", 1.1, 1.5), ("tree_oak_dark", 1.2, 1.6), ("tree_fat_darkh", 1.1, 1.5), ("tree_detailed_dark", 1.1, 1.5)]
        var woods: [SIMD2<Double>] = []
        for _ in 0..<160 where woods.count < 14 {
            let c = anywhere()
            guard onLand(c), !onStation(c, 3.5) else { continue }
            woods.append(c)
            let radius = rng.between(4, 7)
            for _ in 0..<Int(rng.between(30, 55)) {
                let a = rng.between(0, 2 * .pi), r = radius * (rng.next() * 0.5 + rng.next() * 0.5)
                let p = c + SIMD2(cos(a), sin(a)) * r
                guard onLand(p), !onStation(p, 1.2) else { continue }
                let tree = rng.pick(forest)
                nature(tree.0, at: p, scale: rng.between(tree.1, tree.2), yaw: rng.between(0, 2 * .pi), tint: Self.forestTint)
            }
            for _ in 0..<3 {
                let a = rng.between(0, 2 * .pi)
                let p = c + SIMD2(cos(a), sin(a)) * (radius + 0.8)
                guard onLand(p), !onStation(p, 1.5) else { continue }
                nature(rng.next() < 0.5 ? "stump_old" : "log_stack", at: p, scale: 1.2, yaw: rng.between(0, 2 * .pi), tint: Self.forestTint)
            }
        }
        // Rough ground: outcrops of tall rock here and there.
        for _ in 0..<14 {
            let c = anywhere()
            guard onLand(c), !onStation(c, 3) else { continue }
            for _ in 0..<Int(rng.between(2, 5)) {
                let p = c + SIMD2(rng.between(-1.2, 1.2), rng.between(-1.2, 1.2))
                guard onLand(p), !onStation(p, 1.5) else { continue }
                nature(rng.next() < 0.6 ? "rock_tallA" : "rock_largeA", at: p, scale: rng.between(0.5, 1.0), yaw: rng.between(0, 2 * .pi), tint: Self.cliffTint)
            }
        }
        // Hamlets: a few cottages together in the open, between the woods and the stations, now and then a mill.
        let homes = ["unit-house", "unit-house", "unit-house", "unit-mansion"]
        var hamlets = 0
        for _ in 0..<120 where hamlets < 7 {
            let c = anywhere()
            guard onLand(c), !onStation(c, 3.5), !woods.contains(where: { simd_distance($0, c) < 6 }) else { continue }
            hamlets += 1
            for k in 0..<Int(rng.between(2, 5)) {
                let p = c + SIMD2(rng.between(-2.2, 2.2), rng.between(-2.2, 2.2))
                guard onLand(p), !onStation(p, 1.6) else { continue }
                let name = k == 0 && rng.next() < 0.35 ? "unit-mill" : rng.pick(homes)
                put(name, .hexagon, at: p, scale: 2.6, yaw: Double(Int(rng.between(0, 4))) * .pi / 2 + rng.between(-0.2, 0.2))
            }
        }
        // Single trees about the open land.
        for _ in 0..<40 {
            let p = anywhere()
            guard onLand(p), !onStation(p, 2) else { continue }
            let tree = rng.pick(forest)
            nature(tree.0, at: p, scale: rng.between(tree.1, tree.2) * 0.8, yaw: rng.between(0, 2 * .pi), tint: Self.forestTint)
        }
    }

    /// Hallways are the green; plots are tilled soil with a trace of the repo's colour; the yard is cobbled
    /// with a trace of its own shade, the bay a stone quay, the airlock stone.
    func floorColor(_ color: NSColor, floor: Floor) -> NSColor {
        switch floor {
        case .hallway: return Self.grass
        case .room: return Self.soil.mixed(with: color, 0.3)
        case .fixed: return color.mixed(with: Self.sand, 0.35)
        case .yard: return Self.cobble.mixed(with: color, 0.45)
        case .bay: return Self.quay
        case .airlock: return Self.stone
        }
    }

    /// Offices are worked plots. A low hedge runs only round the outside of the yard, where it ends on
    /// nothing; between floors there is nothing at all.
    func tileDetail(_ tile: Tile) -> SCNNode? {
        if tile.floor == .room { return plot(tile.color) }
        guard tile.floor == .yard else { return nil }
        let model = "hedge"
        let edges = tile.open
        guard !edges.isEmpty else { return nil }
        let n = SCNNode()
        for e in edges.sorted() {
            guard let piece = Kit.node(model, from: .town) else { return nil }
            // The piece stands on the tile's x+ edge, and a quarter turn moves it one edge on.
            piece.eulerAngles.y = Double((e + 1) % 4) * .pi / 2
            n.addChildNode(piece)
        }
        n.eulerAngles.x = .pi / 2   // upright again under a plane tilted flat
        return n
    }

    /// A tile of a worked plot: a double row of tilled soil with two plants on it, the same crop across an
    /// office, picked by the office's hue so it holds while the office's lights come and go.
    private func plot(_ color: NSColor) -> SCNNode? {
        guard let soil = Kit.node("crops_dirtDoubleRow", from: .nature, tint: Self.soilTint) else { return nil }
        let n = SCNNode()
        n.addChildNode(soil)
        let crops: [(String, Double)] = [("crops_wheatStageB", 0.75), ("crop_carrot", 0.6), ("crops_cornStageB", 0.45),
                                         ("crop_turnip", 0.6), ("crop_pumpkin", 0.8), ("crops_wheatStageA", 0.8)]
        let hue = (color.usingColorSpace(.deviceRGB) ?? color).hueComponent
        let crop = crops[Int((hue * 12).rounded()) % crops.count]
        for (x, z) in [(-0.25, -0.2), (0.25, 0.22)] {
            guard let plant = Kit.node(crop.0, from: .nature, tint: Self.cropTint) else { continue }
            plant.scale = SCNVector3(crop.1, crop.1, crop.1)
            plant.position = v3(x, 0.03, z)
            n.addChildNode(plant)
        }
        n.eulerAngles.x = .pi / 2   // upright again under a plane tilted flat
        return n
    }

    func tint(tile: SCNNode, _ color: NSColor) {
        tile.geometry?.firstMaterial?.diffuse.contents = floorColor(color, floor: .room)
    }

    /// A castle gate over each tile of the doorway, the pane still dropping behind it like a portcullis.
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

    func hatchFrame(facing: SIMD2<Double>) -> (node: SCNNode, lightHeight: Double) {
        guard let gate = Kit.node("gate", from: .castle) else { return Classic.hatchFrame(facing: facing) }
        gate.eulerAngles.y = facing.x == 0 ? .pi / 2 : 0
        let n = SCNNode()
        n.addChildNode(gate)
        return (n, 1.0)
    }

    /// A square keep about the monolith's size: a base, a storey and a roofed top.
    func monolith() -> SCNNode {
        guard let base = Kit.node("tower-square-base", from: .castle), let storey = Kit.node("tower-square-mid", from: .castle),
              let top = Kit.node("tower-square-top-roof", from: .castle) else { return Classic.monolith() }
        let n = SCNNode()
        let s = 0.8
        for (i, part) in [base, storey, top].enumerated() {
            part.scale = SCNVector3(s, s, s)
            part.position = v3(0, Double(i) * 1.01 * s, 0)
            n.addChildNode(part)
        }
        return n
    }

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

    /// A sailing ship, its hull tinted toward the repo colour.
    func shuttle(color: NSColor) -> SCNNode {
        guard let m = Kit.node("unit-ship-large", from: .hexagon, multiply: color.mixed(with: .white, 0.55)) else { return Classic.shuttle(color: color) }
        m.scale = SCNVector3(1.2, 1.2, 1.2)
        m.position = v3(0, -0.15, 0)
        let n = SCNNode()
        n.addChildNode(m)
        return n
    }

    /// Ships sail in from the sea to the east, turn in and moor off the dock's outer row, where the cargo
    /// comes ashore, and sail back out the way they came. While the slot is taken they wait off the dock.
    func shipPose(_ leg: ShipLeg) -> (pos: SIMD3<Double>, yaw: Double)? {
        let s = leg.slot, side = 1.0, t = leg.progress
        let moor = SIMD2(s.x + 0.72, s.y + 1.15), off = SIMD2(s.x + 0.72, s.y + 3.5)   // beside the slot's pier
        let farIn = SIMD2(s.x + side * 18, s.y + 6), farOut = SIMD2(s.x + side * 18, s.y + 8)
        let smooth = t * t * (3 - 2 * t)
        func heading(_ a: SIMD2<Double>, _ b: SIMD2<Double>) -> Double { atan2(-(b.y - a.y), b.x - a.x) }
        let alongQuay = heading(SIMD2(0, 0), SIMD2(side, 0))   // bow the way it will leave
        let (p, yaw): (SIMD2<Double>, Double) = {
            switch leg.phase {
            case .approach: return (farIn + (off - farIn) * (1 - (1 - t) * (1 - t)), heading(farIn, off))
            case .descend:
                let inbound = heading(farIn, off)
                return (off + (moor - off) * smooth, inbound + (alongQuay - inbound) * smooth)
            case .unload: return (moor, alongQuay)
            case .rise: return (moor + (off - moor) * smooth, alongQuay)
            default: return (off + (farOut - off) * (t * t), heading(off, farOut))
            }
        }()
        return (SIMD3(p.x, 0, p.y), yaw)
    }

    /// A siege engine sized as the classic rocket is for its cargo: a siege tower for a tall release, a
    /// catapult for a small one, turned narrow side along the pad's slots, flying the repo's flag. The hatch
    /// the crates go in by and the flame the lift-off lights are where the scene reaches for them.
    func rocket(color: NSColor, tall: Bool, cargo: Int) -> SCNNode {
        let grow = tall ? min(1.6, 0.85 + Double(cargo) * 0.06) : 1.0
        let (name, native, height) = tall ? ("siege-tower", 2.68, 1.5 * grow + 0.3) : ("siege-catapult", 1.18, 0.9)
        guard let engine = Kit.node(name, from: .castle) else { return Classic.rocket(color: color, tall: tall, cargo: cargo) }
        let s = height / native
        engine.scale = SCNVector3(s, s, s)
        engine.eulerAngles.y = .pi / 2
        let n = SCNNode()
        n.addChildNode(engine)
        if let flag = Kit.node("flag", from: .castle, multiply: color) {
            flag.scale = SCNVector3(0.6, 0.6, 0.6)
            flag.position = v3(0, height * 0.98, 0)
            n.addChildNode(flag)
        }
        let radius = (tall ? 0.98 : 1.0) * s
        let hatch = SCNNode(geometry: SCNBox(width: 0.22, height: 0.2, length: 0.02, chamferRadius: 0))
        hatch.geometry!.firstMaterial = lit(NSColor(rgb: (0.3, 0.22, 0.16)))
        hatch.position = v3(0, 0.22, radius + 0.005)
        hatch.name = "hatch"
        n.addChildNode(hatch)
        let flame = SCNNode(geometry: faceted(SCNCone(topRadius: 0.2, bottomRadius: 0, height: 0.45)))
        flame.geometry!.firstMaterial = flat(Palette.pyramid)
        flame.position = v3(0, -0.2, 0)
        flame.name = "flame"
        flame.opacity = 0
        n.addChildNode(flame)
        return n
    }

    /// Carts at the pad's corners clear of the engines. At the harbour: a plank pier out from the quay at
    /// every landing slot, goods stacked at the quay's corners, and a lighthouse on rocks off its west end.
    func dress(station: Station) -> [SCNNode] {
        var props: [SCNNode] = []
        for (i, c) in Dressing.padCorners(station).enumerated() {
            guard let cart = Kit.node("cart", from: .town) else { continue }
            cart.scale = SCNVector3(0.8, 0.8, 0.8)
            cart.eulerAngles.y = Double(i) * .pi / 2 + 0.4
            cart.position = v3(Double(c.x), 0, Double(c.y))
            props.append(cart)
        }
        guard station.hasHangar, !station.hangarCells.isEmpty else { return props }
        let xs = station.hangarCells.map(\.x), ys = station.hangarCells.map(\.y)
        let west = Double(xs.min()!), east = Double(xs.max()!), front = Double(ys.min()!), back = Double(ys.max()!)
        for s in station.hangarSlots {
            // A dock on posts, its deck about 0.7 up the model: sunk so the deck is level with the quay.
            guard let pier = Kit.node("structure-platform-dock-small", from: .pirate) else { break }
            pier.scale = SCNVector3(0.4, 0.4, 0.4)
            pier.position = v3(s.x, -0.28, back + 1.0)
            props.append(pier)
        }
        let goods: [(String, Double)] = [("barrel", 0.3), ("crate", 0.32), ("chest", 0.28), ("crate-bottles", 0.3), ("barrel", 0.26)]
        let spots = [SIMD2(west - 0.1, front - 0.1), SIMD2(west + 0.25, front - 0.25), SIMD2(east + 0.1, front - 0.1),
                     SIMD2(east - 0.2, front - 0.3), SIMD2(east + 0.15, front + 0.3)]
        for (i, at) in spots.enumerated() {
            let g = goods[i % goods.count]
            guard let n = Kit.node(g.0, from: .pirate) else { continue }
            n.scale = SCNVector3(g.1, g.1, g.1)
            n.eulerAngles.y = Double(i) * 0.7
            n.position = v3(at.x, 0, at.y)
            props.append(n)
        }
        if let rocks = Kit.node("rocks-sand-a", from: .pirate), let tower = Kit.node("tower-complete-small", from: .pirate) {
            let at = SIMD2(west - 1.6, back + 0.6)
            rocks.scale = SCNVector3(0.3, 0.18, 0.3)
            rocks.position = v3(at.x, -0.25, at.y)
            tower.scale = SCNVector3(0.22, 0.22, 0.22)
            tower.position = v3(at.x, 0.3, at.y)
            props.append(rocks)
            props.append(tower)
        }
        return props
    }

    /// A flag in the repo's colour at the plot's far edge, so whose office it is reads from afar.
    func dress(office room: Room, in station: Station) -> SCNNode? {
        guard let wall = Dressing.officeWall(room, in: station), let flag = Kit.node("flag", from: .pirate, multiply: NSColor(room.color)) else { return nil }
        flag.scale = SCNVector3(0.24, 0.24, 0.24)
        flag.position = v3(Double(wall.cell.x) + wall.out.x * 0.4, 0, Double(wall.cell.y) + wall.out.y * 0.4)
        return flag
    }
}
