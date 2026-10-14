import AppKit
import SceneKit

struct Scatter {
    private var state: UInt64
    init(seed: UInt64) { state = seed &* 0x9E37_79B9_7F4A_7C15 | 1 }
    mutating func next() -> Double {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Double(state >> 11) / Double(1 << 53)
    }
    mutating func between(_ a: Double, _ b: Double) -> Double { a + (b - a) * next() }
    mutating func pick<T>(_ items: [T]) -> T { items[min(items.count - 1, Int(next() * Double(items.count)))] }
}

enum Kit {
    enum Pack: String {
        case space = "space-kit", modular = "modular-space-kit", nature = "nature-kit"
        case castle = "castle-kit", town = "fantasy-town-kit", hexagon = "hexagon-kit"
        case pirate = "pirate-kit", survival = "survival-kit", cubePets = "cube-pets"
    }

    private static var prototypes: [String: SCNNode] = [:]
    private static let lock = NSLock()

    static let root: URL? = {
        if let r = Bundle.main.resourceURL?.appendingPathComponent("Kenney"), FileManager.default.fileExists(atPath: r.path) { return r }
        let src = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/Kenney")
        return FileManager.default.fileExists(atPath: src.path) ? src : nil
    }()

    private static func prototype(_ name: String, _ pack: Pack) -> SCNNode? {
        let key = pack.rawValue + "/" + name
        lock.lock(); defer { lock.unlock() }
        if let p = prototypes[key] { return p }
        guard let root else { return nil }
        let dir = root.appendingPathComponent(pack.rawValue)
        guard let scene = try? SCNScene(url: dir.appendingPathComponent(name + ".obj"), options: [.checkConsistency: false]) else { return nil }
        var found: SCNGeometry?
        scene.rootNode.enumerateChildNodes { c, stop in if let g = c.geometry { found = g; stop.pointee = true } }
        guard let geometry = found else { return nil }
        for m in geometry.materials {
            m.lightingModel = .lambert
            m.specular.contents = NSColor.black
            if let path = m.diffuse.contents as? String {
                let file = URL(fileURLWithPath: path).lastPathComponent
                m.diffuse.contents = NSImage(contentsOf: dir.appendingPathComponent("Textures/" + file)) ?? NSImage(contentsOf: dir.appendingPathComponent("Textures/colormap.png"))
            }
        }
        let proto = SCNNode(geometry: geometry)
        prototypes[key] = proto
        return proto
    }

    static func node(_ name: String, from pack: Pack = .space, tint: [String: NSColor] = [:], multiply: NSColor? = nil) -> SCNNode? {
        guard let proto = prototype(name, pack), let g = proto.geometry?.copy() as? SCNGeometry else { return nil }
        let n = SCNNode(geometry: g)
        if !tint.isEmpty || multiply != nil {
            g.materials = g.materials.map { m in
                if let name = m.name, let c = tint[name] {
                    let t = m.copy() as! SCNMaterial
                    t.diffuse.contents = c
                    return t
                }
                guard let multiply else { return m }
                let t = m.copy() as! SCNMaterial
                t.multiply.contents = multiply
                return t
            }
        }
        return n
    }

    static let plateTop = 0.004

    static func plateShade(_ color: NSColor) -> NSColor { color.mixed(with: .white, 0.15) }
    static func kerbShade(_ color: NSColor) -> NSColor { color.darker(0.15) }

    static func platform(open: Set<Int>, color: NSColor) -> SCNNode? {
        let pieces: [(String, Set<Int>)] = [
            ("platform_center", []), ("platform_side", [0]), ("platform_corner", [0, 1]),
            ("platform_straight", [0, 2]), ("platform_end", [0, 1, 2]), ("platform_small", [0, 1, 2, 3]),
        ]
        for (name, native) in pieces where native.count == open.count {
            for k in 0..<4 where Set(native.map { ($0 + k) % 4 }) == open {
                guard let m = node(name, tint: [accent: kerbShade(color)], multiply: plateShade(color)) else { return nil }
                m.eulerAngles.y = Double(k) * .pi / 2
                let n = SCNNode()
                n.addChildNode(m)
                return n
            }
        }
        return nil
    }

    static func tint(tile: SCNNode, _ color: NSColor) {
        tile.geometry?.firstMaterial?.diffuse.contents = color
        for c in tile.childNodes.flatMap({ [$0] + $0.childNodes }) {
            for m in c.geometry?.materials ?? [] {
                if m.name == accent { m.diffuse.contents = kerbShade(color) } else { m.multiply.contents = plateShade(color) }
            }
        }
    }

    static let grass = NSColor(rgb: (0.47, 0.67, 0.36))
    static let leaves = NSColor(rgb: (0.33, 0.58, 0.31))
    static let water = NSColor(rgb: (0.55, 0.82, 0.92))
    static var greens: [String: NSColor] { ["grass": grass, "leafsGreen": leaves] }
    static var shoreTint: [String: NSColor] { greens.merging(["dirt": NSColor(rgb: (0.86, 0.8, 0.62)), "dirtDark": NSColor(rgb: (0.74, 0.68, 0.5))]) { a, _ in a } }
    static var scrubTint: [String: NSColor] { greens.merging(["dirt": NSColor(rgb: (0.6, 0.6, 0.58)), "dirtDark": NSColor(rgb: (0.46, 0.46, 0.45))]) { a, _ in a } }
    static let sky = NSColor(rgb: (0.47, 0.66, 0.84))

    static let accent = "metalRed"

    static let astronautHeight = 0.79

    // MARK: the pieces the station is built from

    static func astronaut(crew: Bool, height: Double) -> SCNNode? {
        guard let n = node(crew ? "astronautB" : "astronautA") else { return nil }
        let s = height / astronautHeight
        n.scale = SCNVector3(s, s, s)
        return n
    }

    static func gate(yaw: Double) -> SCNNode? {
        guard let m = node("gate", from: .modular) else { return nil }
        m.scale = SCNVector3(0.18, 0.18, 0.18)
        let n = SCNNode()
        n.addChildNode(m)
        n.eulerAngles.y = yaw
        return n
    }

    static func prop(_ name: String, scale: Double = 1, yaw: Double = 0, color: NSColor? = nil) -> SCNNode? {
        guard let m = node(name, tint: color.map { [accent: $0] } ?? [:]) else { return nil }
        m.scale = SCNVector3(scale, scale, scale)
        m.eulerAngles.y = yaw
        return m
    }

    static func tower() -> SCNNode? {
        guard let base = node("structure"), let dish = node("satelliteDish_large") else { return nil }
        let n = SCNNode()
        base.scale = SCNVector3(0.7, 1.5, 0.7)
        n.addChildNode(base)
        dish.scale = SCNVector3(0.9, 0.9, 0.9)
        dish.position = v3(0, 1.5, 0)
        dish.runAction(.repeatForever(.rotateBy(x: 0, y: 2 * .pi, z: 0, duration: 48)))
        n.addChildNode(dish)
        return n
    }

    static func rocket(color: NSColor, height: Double) -> (node: SCNNode, radius: Double)? {
        let stages: [(String, Double)] = [("rocket_finsA", 0.7), ("rocket_fuelA", 0.5), ("rocket_sidesA", 1.0), ("rocket_topA", 0.8)]
        let tint = [accent: color]
        var parts: [SCNNode] = []
        for (name, _) in stages { guard let p = node(name, tint: tint) else { return nil }; parts.append(p) }
        let s = height / stages.reduce(0) { $0 + $1.1 }
        let n = SCNNode()
        var y = 0.0
        for (i, p) in parts.enumerated() {
            p.position = v3(0, y, 0)
            n.addChildNode(p)
            y += stages[i].1
        }
        n.scale = SCNVector3(s, s, s)
        return (n, 0.6 * s)
    }

    static func rocketProp(color: NSColor, tall: Bool, cargo: Int) -> SCNNode? {
        let grow = tall ? min(1.6, 0.85 + Double(cargo) * 0.06) : 1.0
        let h = (tall ? 1.5 : 0.9) * grow, r = (tall ? 0.17 : 0.12) * (0.7 + 0.3 * grow)
        guard let stack = rocket(color: color, height: 0.12 + h + r * 2.6) else { return nil }
        let n = SCNNode()
        n.addChildNode(stack.node)
        let hatch = SCNNode(geometry: SCNBox(width: stack.radius * 1.1, height: 0.2, length: 0.02, chamferRadius: 0))
        hatch.geometry!.firstMaterial = lit(NSColor(rgb: (0.2, 0.21, 0.26)))
        hatch.position = v3(0, 0.22, stack.radius + 0.005)
        hatch.name = "hatch"
        n.addChildNode(hatch)
        let flame = SCNNode(geometry: faceted(SCNCone(topRadius: stack.radius * 0.6, bottomRadius: 0, height: 0.45)))
        flame.geometry!.firstMaterial = flat(Palette.pyramid)
        flame.position = v3(0, -0.2, 0)
        flame.name = "flame"
        flame.opacity = 0
        n.addChildNode(flame)
        return n
    }

    static func craft(color: NSColor) -> SCNNode? {
        guard let m = node("craft_speederA", tint: [accent: color]) else { return nil }
        m.scale = SCNVector3(0.42, 0.42, 0.42)
        m.eulerAngles.y = .pi / 2
        m.position = v3(0, -0.17, 0)
        let n = SCNNode()
        n.addChildNode(m)
        return n
    }
}
