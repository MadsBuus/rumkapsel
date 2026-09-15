// Kenney Kingdom: the station as a harbour village, bright as a handheld town. The hallways are the
// green itself; offices are open fields with a market stall, the yard is cobbled and hedged, the monolith
// a castle keep, the airlock and the decon hatch castle gates, and what stands on the pad a siege engine
// flying the repo's flag. Villagers for minions, sailing ships for shuttles. The floor plan is Classic's.
// Built from Kenney's Castle Kit, Fantasy Town Kit, Mini Characters and Hexagon Kit (CC0); where a model
// is missing from the bundle, the classic piece stands in.

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
        let trees: [(String, Kit.Pack)] = [("tree-large", .castle), ("tree-small", .castle), ("tree", .town), ("tree-high-round", .town)]

        // Woods: clusters of trees, thick in the middle and thinning out toward their edges.
        var woods: [SIMD2<Double>] = []
        for _ in 0..<80 where woods.count < 12 {
            let c = anywhere()
            guard onLand(c), !onStation(c, 5) else { continue }
            woods.append(c)
            for _ in 0..<Int(rng.between(14, 28)) {
                let a = rng.between(0, 2 * .pi), r = 4.5 * rng.next() * (0.4 + 0.6 * rng.next())
                let p = c + SIMD2(cos(a), sin(a)) * r
                guard onLand(p), !onStation(p, 1.8) else { continue }
                let tree = rng.pick(trees)
                put(tree.0, tree.1, at: p, scale: rng.between(0.75, 1.15), yaw: rng.between(0, 2 * .pi))
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
        // Single trees and rocks about the open land.
        for _ in 0..<60 {
            let p = anywhere()
            guard onLand(p), !onStation(p, 2) else { continue }
            if rng.next() < 0.6 {
                let tree = rng.pick(trees)
                put(tree.0, tree.1, at: p, scale: rng.between(0.7, 1.0), yaw: rng.between(0, 2 * .pi))
            } else if rng.next() < 0.5 {
                put("rocks-small", .castle, at: p, scale: rng.between(0.4, 0.7), yaw: rng.between(0, 2 * .pi))
            } else {
                put("rock-small", .town, at: p, scale: rng.between(0.3, 0.5), yaw: rng.between(0, 2 * .pi))
            }
        }
    }

    /// Hallways are the green; plots keep their repo colour warmed toward sand; the yard is cobbled with a
    /// trace of its own shade, the bay trodden earth, the airlock stone.
    func floorColor(_ color: NSColor, floor: Floor) -> NSColor {
        switch floor {
        case .hallway: return Self.grass
        case .room: return color.mixed(with: Self.sand, 0.35)
        case .yard: return Self.cobble.mixed(with: color, 0.45)
        case .bay: return Self.planks
        case .airlock: return Self.stone
        }
    }

    /// Offices are open fields and the bay a bare dock. A low hedge runs only round the outside of the
    /// yard, where it ends on nothing; between floors there is nothing at all.
    func tileDetail(floor: Floor, open: Set<Int>, walled: [Int: Floor], color: NSColor) -> SCNNode? {
        guard floor == .yard else { return nil }
        let model = "hedge"
        let edges = open
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
        let moor = SIMD2(s.x, s.y + 0.95), off = SIMD2(s.x, s.y + 3.5)
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

    /// Carts at the pad's corners clear of the engines, and a high cart parked in the bay.
    func dress(station: Station) -> [SCNNode] {
        var props: [SCNNode] = []
        for (i, c) in Dressing.padCorners(station).enumerated() {
            guard let cart = Kit.node("cart", from: .town) else { continue }
            cart.scale = SCNVector3(0.8, 0.8, 0.8)
            cart.eulerAngles.y = Double(i) * .pi / 2 + 0.4
            cart.position = v3(Double(c.x), 0, Double(c.y))
            props.append(cart)
        }
        if let c = Dressing.bayParking(station), let cart = Kit.node("cart-high", from: .town) {
            cart.eulerAngles.y = 0.6
            cart.position = v3(Double(c.x), 0, Double(c.y))
            props.append(cart)
        }
        return props
    }

    /// A market stall along an outer fence of the office's farthest cell from the door.
    func dress(office room: Room, in station: Station) -> SCNNode? {
        guard let wall = Dressing.officeWall(room, in: station), let stall = Kit.node("stall", from: .town) else { return nil }
        stall.scale = SCNVector3(0.8, 0.8, 0.8)
        stall.eulerAngles.y = wall.out.x != 0 ? 0 : .pi / 2   // its long side along the fence
        stall.position = v3(Double(wall.cell.x) + wall.out.x * 0.28, 0, Double(wall.cell.y) + wall.out.y * 0.28)
        return stall
    }
}
