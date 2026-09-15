// Kenney Space Center: the same floor plan on the ground, laid out as the Cape is, built from Kenney's
// Space Kit, Modular Space Kit and Nature Kit (CC0). Where a model is missing from the bundle, the
// classic piece stands in, so a broken install draws a station rather than holes.

import AppKit
import SceneKit

struct KenneyLook: Look {
    private let classic = ClassicLook()

    var background: NSColor { Kit.sky }
    /// Turned about so the yard and its pad face right, toward the sea.
    var viewYaw: Double { .pi / 4 + .pi }
    var floorTop: Double { Kit.plateTop }
    /// The kit's plates have marks of their own.
    var dotsHallway: Bool { false }

    /// On the ground there is nothing to drift.
    func backdrop(into root: SCNNode) -> [(SCNNode, SIMD2<Double>)] { [] }

    /// A lawn to every side and the sea past the yard, so the pad stands nearest the water; palms along
    /// the shore and scrub on the grass, from a fixed seed so it stands where it stood last time.
    func ground(under stations: [Station], into root: SCNNode) {
        // The fleet's footprint in world units: each station's bounds, with its offset, and the whole.
        var lo = SIMD2<Double>(.infinity, .infinity), hi = SIMD2<Double>(-.infinity, -.infinity)
        var footprints: [(lo: SIMD2<Double>, hi: SIMD2<Double>)] = []
        for st in stations {
            let b = st.bounds
            let a = SIMD2(Double(b.min.x) + st.offset.x - 0.5, Double(b.min.y) + st.offset.y - 0.5)
            let z = SIMD2(Double(b.max.x) + st.offset.x + 0.5, Double(b.max.y) + st.offset.y + 0.5)
            footprints.append((a, z))
            lo = pointwiseMin(lo, a); hi = pointwiseMax(hi, z)
        }
        guard lo.x.isFinite else { return }
        let onStation = { (p: SIMD2<Double>, margin: Double) -> Bool in
            footprints.contains { p.x > $0.lo.x - margin && p.x < $0.hi.x + margin && p.y > $0.lo.y - margin && p.y < $0.hi.y + margin }
        }
        // The pad stands at the fleet's west end on its causeway, so the sea begins a few tiles past it.
        let shore = (lo.x - 4).rounded()
        let mid = (lo + hi) / 2
        let reach = 140.0
        let lawn = SCNNode(geometry: SCNPlane(width: reach, height: reach * 2))
        lawn.geometry!.firstMaterial = lit(Kit.grass)
        lawn.eulerAngles.x = -.pi / 2
        lawn.position = v3(shore + reach / 2, -0.03, mid.y)
        root.addChildNode(lawn)
        let sea = SCNNode(geometry: SCNPlane(width: reach, height: reach * 2))
        sea.geometry!.firstMaterial = lit(Kit.water)
        sea.eulerAngles.x = -.pi / 2
        sea.position = v3(shore - reach / 2, -0.08, mid.y)
        root.addChildNode(sea)
        // The shore: the kit's bank tiles in a row, their grass side turned toward the station.
        let span = Int(reach / 2)
        let midZ = mid.y.rounded()
        for k in -span...span {
            guard let bank = Kit.node("ground_riverSide", from: .nature, tint: Kit.shoreTint) else { break }
            bank.eulerAngles.y = .pi / 2
            bank.position = v3(shore + 0.5, -0.03, midZ + Double(k))
            root.addChildNode(bank)
        }
        var rng = Scatter(seed: 7)
        func plant(_ name: String, at p: SIMD2<Double>, scale: Double) {
            guard let n = Kit.node(name, from: .nature, tint: Kit.scrubTint) else { return }
            n.scale = SCNVector3(scale, scale, scale)
            n.eulerAngles.y = rng.between(0, 2 * .pi)
            n.position = v3(p.x, -0.03, p.y)
            root.addChildNode(n)
        }
        // Palms along the shore, a few steps up the bank, and never on the station.
        let palms = ["tree_palm", "tree_palmTall", "tree_palmBend", "tree_palmDetailedShort"]
        for _ in 0..<26 {
            let p = SIMD2(shore + rng.between(1.2, 4.5), midZ + rng.between(-Double(span) + 2, Double(span) - 2))
            guard !onStation(p, 1.5) else { continue }
            plant(rng.pick(palms), at: p, scale: rng.between(0.75, 1.1))
        }
        // Scrub on the lawn round the fleet: tufts of grass most of all, then bushes, rocks and flowers.
        let scrub = ["grass", "grass", "grass_large", "grass_large", "plant_bush", "plant_bushLarge", "rock_smallA", "rock_smallB", "flower_yellowA", "flower_redA"]
        for _ in 0..<140 {
            let p = SIMD2(rng.between(max(shore + 1.5, lo.x - 22), hi.x + 22), rng.between(lo.y - 22, hi.y + 22))
            guard !onStation(p, 1.2) else { continue }
            plant(rng.pick(scrub), at: p, scale: rng.between(0.7, 1.1))
        }
        for _ in 0..<6 {
            let p = SIMD2(rng.between(max(shore + 3, lo.x - 22), hi.x + 22), rng.between(lo.y - 22, hi.y + 22))
            guard !onStation(p, 2) else { continue }
            plant("rock_largeA", at: p, scale: rng.between(0.8, 1.2))
        }
    }

    /// One of the kit's platforms, kerbed on the open edges, the dark line between owners kept as it is.
    func tileDetail(open: Set<Int>, color: NSColor) -> SCNNode? {
        guard let plate = Kit.platform(open: open, color: color) else { return nil }
        // Under a plane tilted flat: the plate set a hair above the plane, under the text on the floor.
        plate.eulerAngles.x = .pi / 2
        plate.position = SCNVector3(0, 0, Kit.plateTop - 0.05)
        return plate
    }

    func tint(tile: SCNNode, _ color: NSColor) { Kit.tint(tile: tile, color) }

    /// A row of the kit's arches across the chamber, the pane still dropping behind them.
    func airlockFrame(width: Double, spans: [Double], tint: NSColor) -> (node: SCNNode, showsPosts: Bool) {
        let row = SCNNode()
        for x in spans {
            guard let gate = Kit.gate(yaw: 0) else { return classic.airlockFrame(width: width, spans: spans, tint: tint) }
            gate.position = v3(x, 0, 0)
            row.addChildNode(gate)
        }
        return (row, false)
    }

    func hatchFrame(facing: SIMD2<Double>) -> (node: SCNNode, lightHeight: Double) {
        guard let gate = Kit.gate(yaw: facing.x == 0 ? 0 : .pi / 2) else { return classic.hatchFrame(facing: facing) }
        return (gate, 0.9)
    }

    /// The kit's comms tower, its dish turning slowly over the plaza.
    func monolith() -> SCNNode { Kit.tower() ?? classic.monolith() }

    /// Astronauts; the crew wear the other suit.
    func figure(crew: Bool, height: Double) -> SCNNode? { Kit.astronaut(crew: crew, height: height) }

    /// The astronaut has legs of its own: on a seat it shortens, feet at the box's new foot.
    func pose(figure: SCNNode, height: Double, torso: Double) {
        let s = height / Kit.astronautHeight
        figure.scale = SCNVector3(s, s * torso / height, s)
        figure.position = v3(0, -torso / 2, -0.03)
    }

    func shuttle(color: NSColor) -> SCNNode { Kit.craft(color: color) ?? classic.shuttle(color: color) }

    func rocket(color: NSColor, tall: Bool, cargo: Int) -> SCNNode {
        Kit.rocketProp(color: color, tall: tall, cargo: cargo) ?? classic.rocket(color: color, tall: tall, cargo: cargo)
    }

    /// Fuel by the pad, on the two corners farthest from every rocket slot; a rover parked in the bay,
    /// on the cell farthest from the slots the ships drop crates on and from the airlock.
    func dress(station: Station) -> [SCNNode] {
        var props: [SCNNode] = []
        if station.hasPad {
            let pc = station.padCenter
            let slots = [SIMD2(0.0, 0.0), SIMD2(1.3, 0.0), SIMD2(-1.3, 0.0), SIMD2(0.0, 1.2)].map { pc + $0 }
            func clearance(_ c: Cell) -> Double { slots.map { simd_distance(SIMD2(Double(c.x), Double(c.y)), $0) }.min() ?? 0 }
            let corners = station.padCells.filter { clearance($0) > 1.1 && simd_distance(SIMD2(Double($0.x), Double($0.y)), pc) < 2.5 }.sorted { (clearance($0), $0.y, $0.x) > (clearance($1), $1.y, $1.x) }.prefix(2)
            for (i, c) in corners.enumerated() {
                guard let barrel = Kit.prop("machine_barrel", scale: 0.8, yaw: Double(i) * .pi / 2 + 0.4, color: NSColor(rgb: (0.75, 0.62, 0.25))) else { continue }
                barrel.position = v3(Double(c.x), 0, Double(c.y))
                props.append(barrel)
            }
        }
        if station.hasHangar, !station.hangarCells.isEmpty {
            let keepOff = station.hangarSlots + station.airlockCells.map { SIMD2(Double($0.x), Double($0.y)) }
            func clearance(_ c: Cell) -> Double { keepOff.map { simd_distance(SIMD2(Double(c.x), Double(c.y)), $0) }.min() ?? 0 }
            if let c = station.hangarCells.max(by: { (clearance($0), $0.y, $0.x) < (clearance($1), $1.y, $1.x) }), clearance(c) > 0.9,
               let rover = Kit.prop("rover", scale: 1.5, yaw: 0.6, color: NSColor(Colors.hangar).lighter(0.25)) {
                rover.position = v3(Double(c.x), 0, Double(c.y))
                props.append(rover)
            }
        }
        return props
    }

    /// A computer desk against an outer wall of the office's farthest cell from the door, its screen
    /// turned into the room, so whoever stands on that cell stands at it.
    func dress(office room: Room, in station: Station) -> SCNNode? {
        let cells = Set(room.cells)
        guard let door = station.doorCell(of: room.key), let outside = station.doorOutside(of: room.key),
              let far = room.cells.max(by: { a, b in
                  (abs(a.x - door.x) + abs(a.y - door.y), -a.y, -a.x) < (abs(b.x - door.x) + abs(b.y - door.y), -b.y, -b.x)
              }) else { return nil }
        let sides = [Cell(x: far.x, y: far.y - 1), Cell(x: far.x, y: far.y + 1), Cell(x: far.x - 1, y: far.y), Cell(x: far.x + 1, y: far.y)]
        // An outer wall: a side with no room beyond it, the open ground before anything, never the doorway.
        let walls = sides.filter { !cells.contains($0) && !($0 == outside && far == door) }
        guard let wall = walls.first(where: { station.room(at: $0) == nil && !station.isCorridor($0) }) ?? walls.first else { return nil }
        let d = SIMD2(Double(wall.x - far.x), Double(wall.y - far.y))
        guard let desk = Kit.prop("desk_computer", scale: 0.8, yaw: atan2(-d.x, -d.y), color: NSColor(room.color)) else { return nil }
        desk.position = v3(Double(far.x) + d.x * 0.36, Kit.plateTop, Double(far.y) + d.y * 0.36)
        return desk
    }
}

/// A small generator of its own, so the scrub stands where it stood on the last rebuild.
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

/// Kenney's models (CC0, www.kenney.nl), each loaded once from the bundle and cloned out with materials
/// of its own, so a tint touches one copy. Only `KenneyLook` reaches for these.
enum Kit {
    enum Pack: String { case space = "space-kit", modular = "modular-space-kit", nature = "nature-kit" }

    private static var prototypes: [String: SCNNode] = [:]
    private static let lock = NSLock()

    /// Where the models are: in the app bundle, or beside the sources when run straight from .build.
    static let root: URL? = {
        if let r = Bundle.main.resourceURL?.appendingPathComponent("Kenney"), FileManager.default.fileExists(atPath: r.path) { return r }
        let src = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
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
        // Each OBJ is one mesh; its geometry is taken as is, since a flattened clone would lose the
        // material names the tints go by. Kenney's materials come in as physically based and the OBJ's
        // texture path as a string; the station is lit by one sun and an ambient, so lambert, and the
        // one texture is read by hand.
        var found: SCNGeometry?
        scene.rootNode.enumerateChildNodes { c, stop in if let g = c.geometry { found = g; stop.pointee = true } }
        guard let geometry = found else { return nil }
        for m in geometry.materials {
            m.lightingModel = .lambert
            m.specular.contents = NSColor.black
            if m.diffuse.contents is String { m.diffuse.contents = NSImage(contentsOf: dir.appendingPathComponent("Textures/colormap.png")) }
        }
        let proto = SCNNode(geometry: geometry)
        prototypes[key] = proto
        return proto
    }

    /// A fresh copy of a model: the geometry shared, the materials in `tint` replaced by the colour named,
    /// and with `multiply` every other material its own too, shaded through that colour.
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

    /// Where the top of a platform's plate sits over the floor plane; flat marks on the floor go above it.
    static let plateTop = 0.004

    /// The shade a floor's plate is seen through, and its kerb: the tile's colour, so the floor plan reads
    /// from afar as the flat one does, the kit's panel lines a little lighter and the kerb a little darker.
    static func plateShade(_ color: NSColor) -> NSColor { color.mixed(with: .white, 0.15) }
    static func kerbShade(_ color: NSColor) -> NSColor { color.darker(0.15) }

    /// A floor tile from the kit's platforms: a plate with a kerb on each edge in `open`. The edges are
    /// numbered round the tile, z- then x- then z+ then x+, so a quarter turn moves every kerb one on.
    static func platform(open: Set<Int>, color: NSColor) -> SCNNode? {
        let pieces: [(String, Set<Int>)] = [
            ("platform_center", []), ("platform_side", [0]), ("platform_corner", [0, 1]),
            ("platform_straight", [0, 2]), ("platform_end", [0, 1, 2]), ("platform_small", [0, 1, 2, 3]),
        ]
        for (name, native) in pieces where native.count == open.count {
            for k in 0..<4 where Set(native.map { ($0 + k) % 4 }) == open {
                guard let m = node(name, tint: [accent: kerbShade(color)], multiply: plateShade(color)) else { return nil }
                // The turn on a node of its own, so the tilt the tile gets under its plane composes after it.
                m.eulerAngles.y = Double(k) * .pi / 2
                let n = SCNNode()
                n.addChildNode(m)
                return n
            }
        }
        return nil
    }

    /// Recolour a floor tile: the plane's own colour, and the kit's plate on it when there is one.
    static func tint(tile: SCNNode, _ color: NSColor) {
        tile.geometry?.firstMaterial?.diffuse.contents = color
        for c in tile.childNodes.flatMap({ [$0] + $0.childNodes }) {
            for m in c.geometry?.materials ?? [] {
                if m.name == accent { m.diffuse.contents = kerbShade(color) } else { m.multiply.contents = plateShade(color) }
            }
        }
    }

    /// The lawn and the sea. The Nature Kit's own grass is a bright turquoise; the lawn is a calmer green,
    /// and every green on its pieces (`greens`) is retinted to match, the leaves a shade deeper.
    static let grass = NSColor(rgb: (0.47, 0.67, 0.36))
    static let leaves = NSColor(rgb: (0.33, 0.58, 0.31))
    static let water = NSColor(rgb: (0.55, 0.82, 0.92))
    static var greens: [String: NSColor] { ["grass": grass, "leafsGreen": leaves] }
    /// The kit's earth is an orange that reads as a prop from afar: sand on the shore, stone on the rocks.
    static var shoreTint: [String: NSColor] { greens.merging(["dirt": NSColor(rgb: (0.86, 0.8, 0.62)), "dirtDark": NSColor(rgb: (0.74, 0.68, 0.5))]) { a, _ in a } }
    static var scrubTint: [String: NSColor] { greens.merging(["dirt": NSColor(rgb: (0.6, 0.6, 0.58)), "dirtDark": NSColor(rgb: (0.46, 0.46, 0.45))]) { a, _ in a } }
    /// The sky past the edge of the ground.
    static let sky = NSColor(rgb: (0.47, 0.66, 0.84))

    /// The Space Kit's accent, the orange on every model, is where a repo's colour goes.
    static let accent = "metalRed"

    /// The astronaut model's own height, before it is scaled to a minion's.
    static let astronautHeight = 0.79

    // MARK: the pieces the station is built from

    /// An astronaut, feet at the origin, scaled to the classic figure's height. The crew wear the other suit.
    static func astronaut(crew: Bool, height: Double) -> SCNNode? {
        guard let n = node(crew ? "astronautB" : "astronautA") else { return nil }
        let s = height / astronautHeight
        n.scale = SCNVector3(s, s, s)
        return n
    }

    /// The Modular Space Kit's gate: an open arch about a tile wide and a door frame tall, its way through along z.
    static func gate(yaw: Double) -> SCNNode? {
        guard let m = node("gate", from: .modular) else { return nil }
        m.scale = SCNVector3(0.18, 0.18, 0.18)
        let n = SCNNode()
        n.addChildNode(m)
        n.eulerAngles.y = yaw
        return n
    }

    /// A piece of set dressing: the model at `scale`, turned by `yaw`, its accent in `color` when given.
    static func prop(_ name: String, scale: Double = 1, yaw: Double = 0, color: NSColor? = nil) -> SCNNode? {
        guard let m = node(name, tint: color.map { [accent: $0] } ?? [:]) else { return nil }
        m.scale = SCNVector3(scale, scale, scale)
        m.eulerAngles.y = yaw
        return m
    }

    /// The monolith as a comms tower: a structure block with the big dish turning on top of it.
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

    /// The rocket as a stack of the kit's stages, scaled to stand `height` tall, the accent in the repo colour.
    /// `radius` is how far out its hull is at the foot, for the hatch.
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
        return (n, 0.6 * s)   // the fins at the foot reach out past the hull
    }

    /// The rocket as the pad draws it, sized as the classic one is for its cargo, with the loading hatch
    /// and the flame the scene reaches for by name.
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

    /// The speeder, nose along +x as the classic shuttle flies, its hull's middle at the origin.
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
