// Kenney Kingdom: the station as a village on a green, bright as a handheld town. The hallways are the
// green itself; offices are fenced plots with a market stall, the yard is cobbled and hedged, the monolith
// a castle keep, the airlock and the decon hatch castle gates, and what stands on the pad a siege engine
// flying the repo's flag. Villagers for minions, sailing ships for shuttles. The floor plan is Classic's.
// Built from Kenney's Castle Kit, Fantasy Town Kit, Mini Characters and Hexagon Kit (CC0); where a model
// is missing from the bundle, the classic piece stands in.

import AppKit
import SceneKit

struct KingdomLook: Look {
    private let classic = ClassicLook()

    static let grass = NSColor(rgb: (0.49, 0.74, 0.38))
    static let sand = NSColor(rgb: (0.9, 0.84, 0.68))
    static let cobble = NSColor(rgb: (0.72, 0.68, 0.6))
    static let earth = NSColor(rgb: (0.66, 0.54, 0.38))
    static let stone = NSColor(rgb: (0.6, 0.6, 0.64))
    static let villagers = ["a", "b", "c", "d", "e", "f"].flatMap { ["character-male-" + $0, "character-female-" + $0] }

    var background: NSColor { NSColor(rgb: (0.55, 0.76, 0.92)) }
    var viewYaw: Double { .pi / 4 }
    var floorTop: Double { 0 }
    var dotsHallway: Bool { false }
    /// Fences and hedges part the floors; no dark lines on the green.
    var drawsBorders: Bool { false }

    func backdrop(into root: SCNNode) -> [(SCNNode, SIMD2<Double>)] { [] }

    /// A green to every side, the same green the hallways are drawn in so they are one with it, and a
    /// wood round the village from a fixed seed, a clearing kept round every station.
    func ground(under stations: [Station], into root: SCNNode) {
        guard let fp = fleetFootprint(stations) else { return }
        let onStation = { (p: SIMD2<Double>, margin: Double) -> Bool in
            fp.each.contains { p.x > $0.lo.x - margin && p.x < $0.hi.x + margin && p.y > $0.lo.y - margin && p.y < $0.hi.y + margin }
        }
        let mid = (fp.lo + fp.hi) / 2
        let lawn = SCNNode(geometry: SCNPlane(width: 200, height: 200))
        lawn.geometry!.firstMaterial = flat(Self.grass)
        lawn.eulerAngles.x = -.pi / 2
        lawn.position = v3(mid.x, -0.03, mid.y)
        root.addChildNode(lawn)
        var rng = Scatter(seed: 11)
        func plant(_ name: String, _ pack: Kit.Pack, at p: SIMD2<Double>, scale: Double) {
            guard let n = Kit.node(name, from: pack) else { return }
            n.scale = SCNVector3(scale, scale, scale)
            n.eulerAngles.y = rng.between(0, 2 * .pi)
            n.position = v3(p.x, -0.03, p.y)
            root.addChildNode(n)
        }
        let trees: [(String, Kit.Pack)] = [("tree-large", .castle), ("tree-small", .castle), ("tree", .town), ("tree-high-round", .town)]
        for _ in 0..<160 {
            let p = SIMD2(rng.between(fp.lo.x - 24, fp.hi.x + 24), rng.between(fp.lo.y - 24, fp.hi.y + 24))
            guard !onStation(p, 2.5) else { continue }
            let tree = rng.pick(trees)
            plant(tree.0, tree.1, at: p, scale: rng.between(0.7, 1.1))
        }
        for _ in 0..<30 {
            let p = SIMD2(rng.between(fp.lo.x - 20, fp.hi.x + 20), rng.between(fp.lo.y - 20, fp.hi.y + 20))
            guard !onStation(p, 1.5) else { continue }
            if rng.next() < 0.5 { plant("rocks-small", .castle, at: p, scale: rng.between(0.4, 0.7)) } else { plant("rock-small", .town, at: p, scale: rng.between(0.3, 0.5)) }
        }
    }

    /// Hallways are the green; plots keep their repo colour warmed toward sand; the yard is cobbled with a
    /// trace of its own shade, the bay trodden earth, the airlock stone.
    func floorColor(_ color: NSColor, floor: Floor) -> NSColor {
        switch floor {
        case .hallway: return Self.grass
        case .room: return color.mixed(with: Self.sand, 0.35)
        case .yard: return Self.cobble.mixed(with: color, 0.45)
        case .bay: return Self.earth
        case .airlock: return Self.stone
        }
    }

    /// Offices are open fields. A low hedge runs only round the outside of the yard and the bay, where
    /// they end on nothing; between floors there is nothing at all.
    func tileDetail(floor: Floor, open: Set<Int>, walled: [Int: Floor], color: NSColor) -> SCNNode? {
        guard floor == .yard || floor == .bay else { return nil }
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
            guard let gate = Kit.node("gate", from: .castle) else { return classic.airlockFrame(width: width, spans: spans, tint: tint) }
            gate.eulerAngles.y = .pi / 2   // its face across the doorway
            gate.position = v3(x, 0, 0)
            row.addChildNode(gate)
        }
        return (row, false)
    }

    func hatchFrame(facing: SIMD2<Double>) -> (node: SCNNode, lightHeight: Double) {
        guard let gate = Kit.node("gate", from: .castle) else { return classic.hatchFrame(facing: facing) }
        gate.eulerAngles.y = facing.x == 0 ? .pi / 2 : 0
        let n = SCNNode()
        n.addChildNode(gate)
        return (n, 1.0)
    }

    /// A square keep about the monolith's size: a base, a storey and a roofed top.
    func monolith() -> SCNNode {
        guard let base = Kit.node("tower-square-base", from: .castle), let storey = Kit.node("tower-square-mid", from: .castle),
              let top = Kit.node("tower-square-top-roof", from: .castle) else { return classic.monolith() }
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
        guard let m = Kit.node("unit-ship-large", from: .hexagon, multiply: color.mixed(with: .white, 0.55)) else { return classic.shuttle(color: color) }
        m.scale = SCNVector3(1.2, 1.2, 1.2)
        m.position = v3(0, -0.3, 0)
        let n = SCNNode()
        n.addChildNode(m)
        return n
    }

    /// A siege engine sized as the classic rocket is for its cargo: a siege tower for a tall release, a
    /// catapult for a small one, turned narrow side along the pad's slots, flying the repo's flag. The hatch
    /// the crates go in by and the flame the lift-off lights are where the scene reaches for them.
    func rocket(color: NSColor, tall: Bool, cargo: Int) -> SCNNode {
        let grow = tall ? min(1.6, 0.85 + Double(cargo) * 0.06) : 1.0
        let (name, native, height) = tall ? ("siege-tower", 2.68, 1.5 * grow + 0.3) : ("siege-catapult", 1.18, 0.9)
        guard let engine = Kit.node(name, from: .castle) else { return classic.rocket(color: color, tall: tall, cargo: cargo) }
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
