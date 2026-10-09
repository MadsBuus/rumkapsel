// The station's walls as the walk sees them: painted ship's panelling over a dark kick plate, a steel cap, and
// steel pilasters where a wall turns or ends. One family, a panel of its own for each kind of place: a light slot
// along the hallways, a rail at desk height in the offices, soft grooved panels in the living quarters, grey
// bays between tapered pilasters in the yard.

import AppKit
import SceneKit
import simd

enum Bulkhead {
    /// The skin's maps, one wall section long and the wall's height high.
    struct Skin { let color: NSImage, normal: NSImage, roughness: NSImage, metalness: NSImage, glow: NSImage? }

    static let size = 512
    /// Skins to pick from in each style, so neighbouring sections differ.
    static let count = 4

    static func pick(_ c: Cell, _ dx: Int, _ dy: Int, _ station: String) -> Int {
        var h = UInt64(bitPattern: Int64(c.x &* 73856093 ^ c.y &* 19349663 ^ (dx + 2) &* 83492791 ^ (dy + 2) &* 2654435761))
        for u in station.utf8 { h = h &* 31 &+ UInt64(u) }
        h ^= h >> 29; h = h &* 0xbf58476d1ce4e5b9; h ^= h >> 32
        return Int(h % UInt64(count))
    }

    /// The panel for each kind of place.
    enum Style: String, CaseIterable { case hallway, office, quarters, yard }

    /// Which panel faces into each cell of a station: the yard's in the yard, the airlock and the bay, the quarters'
    /// in the dorm, the lounge, the bath and the gym, an office's in an office. Anywhere else is hallway.
    static func styles(of st: Station) -> [Cell: Style] {
        var out: [Cell: Style] = [:]
        for c in st.storageCells + st.deckCells + st.deconCells + st.padCells + st.airlockCells + st.hangarCells { out[c] = .yard }
        for (key, room) in st.rooms { for c in room.cells { out[c] = key.hasPrefix("kind:") ? .quarters : .office } }
        return out
    }

    /// Loads every skin off the thread that draws, from the files `bake` wrote: the walls are plain paint until
    /// they are in, then built again with them. Once.
    static func prepare() {
        lock.lock(); let started = preparing; preparing = true; lock.unlock()
        guard !started else { return }
        DispatchQueue.global(qos: .utility).async { prepareNow() }
    }

    /// The same, here and now: for a still that must have them. A skin whose files are missing is drawn afresh,
    /// all of those at once across the cores.
    static func prepareNow() {
        let styles = Style.allCases
        var drawn = [Skin?](repeating: nil, count: styles.count * count)
        drawn.withUnsafeMutableBufferPointer { buffer in
            let slots = buffer
            DispatchQueue.concurrentPerform(iterations: slots.count) { i in
                let style = styles[i / count], k = i % count
                slots[i] = load(style, k) ?? make(seed: seed(k), style: style)
            }
        }
        lock.lock()
        for (k, style) in styles.enumerated() { skinSets[style] = (0..<count).map { drawn[k * count + $0]! } }
        generation += 1
        lock.unlock()
    }

    private static func seed(_ k: Int) -> UInt64 { UInt64(101 + k * 37) }
    private static let maps = ["color", "normal", "roughness", "metalness", "glow"]

    /// Where the baked skins are: in the app's resources, or beside the sources when run from a build.
    static let root: URL? = {
        if let r = Bundle.main.resourceURL?.appendingPathComponent("Walls"), FileManager.default.fileExists(atPath: r.path) { return r }
        return FileManager.default.fileExists(atPath: sourceRoot.path) ? sourceRoot : nil
    }()
    static let sourceRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Resources/Walls")
    private static func file(_ style: Style, _ k: Int, _ map: String) -> String { "wall-\(style.rawValue)-\(k)-\(map).png" }

    /// A skin as baked, or nil when any of its maps is missing. Only a skin with lights has a glow map.
    private static func load(_ style: Style, _ k: Int) -> Skin? {
        guard let root else { return nil }
        let images = maps.map { NSImage(contentsOf: root.appendingPathComponent(file(style, k, $0))) }
        guard let color = images[0], let normal = images[1], let roughness = images[2], let metalness = images[3] else { return nil }
        return Skin(color: color, normal: normal, roughness: roughness, metalness: metalness, glow: images[4])
    }

    /// `rumkapsel --bake-walls`: draws every skin and writes it beside the sources, to be committed. Run it again
    /// after changing how a wall is drawn.
    static func bake() -> Never {
        try? FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        for style in Style.allCases {
            for k in 0..<count {
                let s = make(seed: seed(k), style: style)
                for (image, map) in zip([s.color, s.normal, s.roughness, s.metalness, s.glow], maps) {
                    guard let image, let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                          let png = rep.representation(using: .png, properties: [:]) else { continue }
                    let url = sourceRoot.appendingPathComponent(file(style, k, map))
                    try? png.write(to: url)
                    print("wrote \(url.path)")
                }
            }
        }
        exit(0)
    }

    private static let lock = NSLock()
    private static var preparing = false
    private static var skinSets: [Style: [Skin]] = [:]
    private static var made: [String: SCNMaterial] = [:]
    /// Bumped when the skins are done, so whoever built walls without them builds them again.
    private(set) static var generation = 0

    /// The face of a wall section: its skin once drawn, plain paint of its colour until then.
    static func material(_ variant: Int, style: Style) -> SCNMaterial {
        lock.lock(); let set = skinSets[style]; lock.unlock()
        guard let set else {
            prepare()
            let key = "\(style.rawValue)#plain"
            if let m = made[key] { return m }
            let m = SCNMaterial()
            m.lightingModel = .physicallyBased
            m.diffuse.contents = NSColor(rgb: style == .yard ? (0.62, 0.63, 0.64) : (0.74, 0.74, 0.74))
            m.roughness.contents = NSColor(white: 0.5, alpha: 1)
            made[key] = m
            return m
        }
        let key = "\(style.rawValue)#\(variant)"
        if let m = made[key] { return m }
        let s = set[variant % count]
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = s.color
        m.normal.contents = s.normal
        m.roughness.contents = s.roughness
        m.metalness.contents = s.metalness
        if let glow = s.glow { m.emission.contents = glow }
        for p in [m.diffuse, m.normal, m.roughness, m.metalness, m.emission] { p.mipFilter = .linear }
        made[key] = m
        return m
    }

    /// Steel: the cap, the ends and the pilasters, in the rocket's own plating.
    static let steel: SCNMaterial = {
        let maps = Plating.maps(seed: 21)
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = maps.color
        m.normal.contents = maps.normal
        m.roughness.contents = maps.roughness
        m.metalness.contents = NSColor(white: 0.15, alpha: 1)
        m.multiply.contents = NSColor(white: 0.85, alpha: 1)
        for p in [m.diffuse, m.normal, m.roughness] { p.wrapS = .repeat; p.wrapT = .repeat; p.mipFilter = .linear }
        m.diffuse.contentsTransform = SCNMatrix4MakeScale(3, 3, 1)
        m.normal.contentsTransform = SCNMatrix4MakeScale(3, 3, 1)
        m.roughness.contentsTransform = SCNMatrix4MakeScale(3, 3, 1)
        return m
    }()

    /// The cap along a wall's top, `length` long: a broad steel rail with a narrower one on it, so its edge
    /// steps in like a chamfer.
    static func cap(length: Double, thickness t: Double, across: Bool) -> SCNNode {
        let n = SCNNode()
        for (w, h, y) in [(t + 0.026, 0.026, Walker.wallHeight - 0.013), (t + 0.008, 0.014, Walker.wallHeight + 0.007)] {
            let b = SCNBox(width: across ? w : length, height: h, length: across ? length : w, chamferRadius: 0)
            b.firstMaterial = steel
            let node = SCNNode(geometry: b)
            node.position = v3(0, y, 0)
            n.addChildNode(node)
        }
        return n
    }

    /// A pilaster where a wall turns or ends: a steel shaft, broader at its foot and its head. Now and then it
    /// carries two small indicators.
    static func pilaster(seed: Int) -> SCNNode {
        let n = SCNNode()
        let h = Walker.wallHeight + 0.03
        for (w, hh, y) in [(0.13, 0.05, 0.025), (0.1, h, h / 2), (0.125, 0.04, h - 0.02)] {
            let b = SCNBox(width: w, height: hh, length: w, chamferRadius: 0)
            b.firstMaterial = steel
            let node = SCNNode(geometry: b)
            node.position = v3(0, y, 0)
            n.addChildNode(node)
        }
        if seed % 5 == 0 {
            for (k, c) in [NSColor(rgb: (1, 0.25, 0.18)), NSColor(rgb: (0.95, 0.95, 0.9))].enumerated() {
                let lamp = flat(c); lamp.emission.contents = c
                for side in 0..<4 {
                    let dot = SCNNode(geometry: SCNBox(width: 0.008, height: 0.008, length: 0.004, chamferRadius: 0))
                    dot.geometry!.firstMaterial = lamp
                    let a = Double(side) * .pi / 2
                    dot.eulerAngles.y = CGFloat(a)
                    dot.position = v3(sin(a) * 0.051 + cos(a) * (Double(k) - 0.5) * 0.014, h * 0.62, cos(a) * 0.051 - sin(a) * (Double(k) - 0.5) * 0.014)
                    n.addChildNode(dot)
                }
            }
        }
        return n
    }

    // MARK: the skin

    /// What a texel is: painted panel, a seam between panels, bare steel, the dark of a slot or the kick plate, or a light.
    private enum Kind: UInt8 { case paint, seam, steel, dark, lamp }

    /// A wall section's skin in a style: its panels, recesses, slots and indicators by the section's seed,
    /// the rocket's fine plating over the painted faces, and a little wear: soft enough that from a step back it
    /// reads as one plain wall, with the detail there when you are close.
    private static func make(seed: UInt64, style: Style) -> Skin {
        let n = size, H = Walker.wallHeight
        var r = Textures.Seeded(s: seed)
        let micro = Plating.heightField(seed: seed ^ 0x51, size: n)
        var height = [Float](repeating: 0.6, count: n * n), kind = [Kind](repeating: .paint, count: n * n)
        var shade = [Float](repeating: 1, count: n * n), edge = [Float](repeating: 0, count: n * n)
        var light = [Float](repeating: 0, count: n * n)
        var lightColor = SIMD3(0.85, 0.92, 1.0)

        /// Every texel inside a rectangle of the wall (in its own units, y up from the floor), with how far it is
        /// in from the rectangle's nearest side.
        func each(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, _ body: (Int, Double, Double, Double) -> Void) {
            let c0 = max(0, Int(x0 * Double(n))), c1 = min(n - 1, Int(x1 * Double(n)))
            let r0 = max(0, Int((1 - y1 / H) * Double(n))), r1 = min(n - 1, Int((1 - y0 / H) * Double(n)))
            guard c0 <= c1, r0 <= r1 else { return }
            for row in r0...r1 { for col in c0...c1 {
                let x = (Double(col) + 0.5) / Double(n), y = (1 - (Double(row) + 0.5) / Double(n)) * H
                body(row * n + col, x, y, min(min(x - x0, x1 - x), min(y - y0, y1 - y)))
            } }
        }
        /// A panel: a seam round it, a chamfer up from the seam, and its face a shade of its own.
        func panel(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, face: Float = 0.6) {
            let tone = Float(0.96 + r.next() * 0.06)
            each(x0, y0, x1, y1) { i, _, _, e in
                if e < 0.003 { height[i] = 0.3; kind[i] = .seam; return }
                let k = Float(min(1, (e - 0.003) / 0.007))
                height[i] = 0.42 + (face - 0.42) * k
                kind[i] = .paint; shade[i] = tone
                if k < 1 { edge[i] = 1 - k }
            }
        }
        /// A recess in a panel, its sides chamfered; `cut` takes its corners off at forty-five degrees.
        func inset(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, depth: Float = 0.12, cut: Double = 0) {
            each(x0, y0, x1, y1) { i, x, y, e in
                var e = e
                if cut > 0 {
                    let cx = min(x - x0, x1 - x), cy = min(y - y0, y1 - y)
                    e = min(e, (cx + cy - cut) / 1.414)
                }
                guard e > 0 else { return }
                let k = Float(min(1, e / 0.006))
                height[i] -= depth * k
                if k < 1 { edge[i] = max(edge[i], 0.5 * (1 - k)) }
            }
        }
        /// A strip that gives light: recessed, and lit in the emission.
        func slot(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, glow: Float) {
            each(x0, y0, x1, y1) { i, _, _, e in height[i] = 0.35; kind[i] = .lamp; light[i] = glow * Float(min(1, e / 0.004)) }
        }
        each(0, 0, 1, 0.06) { i, _, _, _ in height[i] = 0.45; kind[i] = .dark }   // the kick plate

        var paint: SIMD3<Double>
        switch style {
        case .hallway:
            // Off-white panels with their corners cut, over a lower course, a light slot running between them.
            paint = SIMD3(0.78, 0.78, 0.77)
            for k in 0..<2 { let x0 = Double(k) * 0.5
                panel(x0, 0.06, x0 + 0.5, 0.2); inset(x0 + 0.04, 0.085, x0 + 0.46, 0.175, depth: 0.06, cut: 0.03) }
            slot(0, 0.2, 1, 0.222, glow: 1)
            panel(0, 0.222, 1, 0.66)
            inset(0.05, 0.27, 0.48, 0.61, depth: 0.1, cut: 0.05); inset(0.52, 0.27, 0.95, 0.61, depth: 0.1, cut: 0.05)
            each(0, 0.66, 1, H) { i, _, _, _ in height[i] = 0.3; kind[i] = .dark }
        case .office:
            // The hallway's panels a shade cooler, with a steel rail at desk height instead of the light slot.
            paint = SIMD3(0.75, 0.76, 0.78)
            for k in 0..<3 { let x0 = Double(k) / 3
                panel(x0, 0.06, x0 + 1.0 / 3, 0.3); inset(x0 + 0.035, 0.09, x0 + 1.0 / 3 - 0.035, 0.27, depth: 0.05) }
            each(0, 0.3, 1, 0.318) { i, _, _, _ in height[i] = 0.74; kind[i] = .steel }
            let split = Int(r.next() * 3) + 1
            for k in 0..<split { let x0 = Double(k) / Double(split), x1 = Double(k + 1) / Double(split)
                panel(x0, 0.318, x1, 0.66); inset(x0 + 0.04, 0.35, x1 - 0.04, 0.63, depth: 0.08, cut: 0.03) }
            each(0, 0.66, 1, H) { i, _, _, _ in height[i] = 0.3; kind[i] = .dark }
        case .quarters:
            // Warmer and calmer: finely grooved panels low down, one big soft-cornered panel above.
            paint = SIMD3(0.8, 0.78, 0.75)
            panel(0, 0.06, 1, 0.24)
            each(0, 0.075, 1, 0.225) { i, x, _, _ in
                let u = (x * 16).truncatingRemainder(dividingBy: 1)
                if abs(u - 0.5) > 0.44 { height[i] -= 0.06 }
            }
            panel(0, 0.24, 1, 0.66)
            inset(0.06, 0.29, 0.94, 0.61, depth: 0.06, cut: 0.07)
            each(0, 0.66, 1, H) { i, _, _, _ in height[i] = 0.3; kind[i] = .dark }
        case .yard:
            // Grey bays between tapered pilasters, a rail across them, now and then a tiny pair of indicators.
            paint = SIMD3(0.66, 0.67, 0.68)
            panel(0, 0.06, 1, 0.66)
            for (x, w0, w1) in [(0.0, 0.07, 0.035), (1.0, 0.07, 0.035)] {
                each(x - w0, 0.06, x + w0, 0.66) { i, px, y, _ in
                    let half = w0 + (w1 - w0) * min(1, max(0, (y - 0.12) / 0.4)) * (y < 0.56 ? 1 : max(0, 1 - (y - 0.56) / 0.08))
                    if abs(px - x) < half { height[i] = 0.78 - Float(abs(px - x) / half) * 0.1; kind[i] = .paint; shade[i] = 0.92
                        if abs(abs(px - x) - half) < 0.004 { edge[i] = 0.5 } }
                }
            }
            each(0.06, 0.4, 0.94, 0.43) { i, _, _, _ in height[i] = 0.72; kind[i] = .steel }
            inset(0.12, 0.47, 0.88, 0.62, depth: 0.08)
            inset(0.12, 0.1, 0.88, 0.36, depth: 0.06)
            if r.next() < 0.4 {
                let x = 0.2 + r.next() * 0.6
                for (k, glow) in [(0, Float(1)), (1, Float(0.9))] {
                    each(x + Double(k) * 0.022, 0.53, x + Double(k) * 0.022 + 0.014, 0.56) { i, _, _, _ in kind[i] = .lamp; light[i] = glow; height[i] = 0.62 }
                }
                lightColor = SIMD3(1.0, 0.35, 0.28)
            }
            each(0, 0.66, 1, H) { i, _, _, _ in height[i] = 0.3; kind[i] = .dark }
        }

        // The rocket's fine plating on every painted face.
        for i in 0..<(n * n) where kind[i] == .paint || kind[i] == .steel { height[i] += (micro[i] - 0.5) * 0.06 }

        let ao = Plating.occlusion(height, size: n, radius: 2)
        let soft = Plating.soften(height, size: n)
        var color = [UInt8](repeating: 255, count: n * n * 4), rough = color, metal = color
        var glow: [UInt8]? = light.contains { $0 > 0 } ? [UInt8](repeating: 0, count: n * n * 4) : nil
        let bare = SIMD3(0.45, 0.45, 0.46), seam = paint * 0.42, dark = SIMD3(0.16, 0.16, 0.17)
        for row in 0..<n {
            let y = (1 - (Double(row) + 0.5) / Double(n)) * H
            for col in 0..<n {
                let x = (Double(col) + 0.5) / Double(n)
                let i = row * n + col
                var c: SIMD3<Double>, ro: Double, me: Double
                switch kind[i] {
                case .paint:
                    // Worn through to the steel here and there along the edges.
                    let worn = Double(edge[i]) * (0.2 + 1.2 * max(0, Plating.noise(x * 22, y * 22, seed: seed ^ 41) - 0.4)) > 0.5
                    c = worn ? bare : paint * Double(shade[i]); ro = worn ? 0.35 : 0.5; me = worn ? 0.7 : 0
                case .steel: c = bare * 1.15; ro = 0.32; me = 0.8
                case .seam: c = seam; ro = 0.75; me = 0.2
                case .dark: c = dark; ro = 0.6; me = 0.4
                case .lamp: c = SIMD3(0.9, 0.9, 0.9); ro = 0.2; me = 0
                }
                // Soft wear: faint streaks, a darker foot, dirt in what is sunk.
                let blotch = Plating.noise(x * 6, y * 8, seed: seed ^ 5)
                let streak = Plating.noise(x * 80, y * 1.4, seed: seed ^ 11)
                let foot = max(0, 1 - y / 0.2)
                let dirt = min(0.5, foot * foot * 0.35 + max(0, blotch - 0.6) * 0.45
                               + max(0, streak - 0.7) * 0.4 * (y > 0.24 ? 1 : 0.3) + Double(ao[i]) * 3.5)
                c = c * (1 - dirt * 0.55) + SIMD3(0.06, 0.055, 0.05) * dirt * 0.2
                c *= 1 + 0.03 * (Plating.noise(x * 50, y * 50, seed: seed ^ 17) - 0.5)
                ro = min(1, ro + dirt * 0.3)
                color[i * 4] = byte(c.x); color[i * 4 + 1] = byte(c.y); color[i * 4 + 2] = byte(c.z)
                let rb = byte(ro), mb = byte(me)
                rough[i * 4] = rb; rough[i * 4 + 1] = rb; rough[i * 4 + 2] = rb
                metal[i * 4] = mb; metal[i * 4 + 1] = mb; metal[i * 4 + 2] = mb
                guard glow != nil else { continue }
                let w = lightColor * Double(light[i]) * 1.4
                glow![i * 4] = byte(w.x); glow![i * 4 + 1] = byte(w.y); glow![i * 4 + 2] = byte(w.z)
            }
        }
        return Skin(color: image(color, n), normal: Plating.normalMap(soft, size: n, strength: 6), roughness: image(rough, n),
                    metalness: image(metal, n), glow: glow.map { image($0, n) })
    }

    private static func byte(_ v: Double) -> UInt8 { UInt8(max(0, min(255, v * 255))) }

    private static func image(_ px: [UInt8], _ n: Int) -> NSImage {
        var data = px
        let ctx = data.withUnsafeMutableBytes { buf in
            CGContext(data: buf.baseAddress, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        }
        guard let cg = ctx?.makeImage() else { return NSImage() }
        return NSImage(cgImage: cg, size: NSSize(width: n, height: n))
    }
}
