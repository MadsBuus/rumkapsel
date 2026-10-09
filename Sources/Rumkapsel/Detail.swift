// Fine detail laid over the station's flat colours: deck plates and their seams on the floors, a crate's case,
// the rocket's plating. Each is a grey image multiplied over a surface's colour, nearly white
// on average, so from a distance the colour is what it always was and the detail is there when you are close.
// Baked into Resources/Detail by `--bake-detail`.

import AppKit
import SceneKit
import simd

enum Detail {
    /// The kinds of surface with a detail of their own.
    enum Kind: String, CaseIterable { case hallway, office, quarters, yard, bay, airlock, hull, pod, hardcase, lid }

    static let size = 512
    /// What a detail averages to, so a surface keeps its colour from afar.
    static let mean = 0.96

    /// The crate looks, one picked for each task by its number, so a row of crates is a mix and a crate keeps its own.
    static let crates: [Kind] = [.pod, .hardcase, .lid, .hull]
    static func crate(for number: Int?) -> Kind {
        guard let number else { return .pod }
        var h = UInt64(truncatingIfNeeded: number) &* 0x9e3779b97f4a7c15
        h ^= h >> 31
        return crates[Int(h % UInt64(crates.count))]
    }

    static func kind(of floor: Floor) -> Kind {
        switch floor {
        case .hallway: return .hallway
        case .room: return .office
        case .fixed: return .quarters
        case .yard: return .yard
        case .bay: return .bay
        case .airlock: return .airlock
        }
    }

    /// Where the baked details are: in the app's resources, or beside the sources when run from a build.
    static let root: URL? = {
        if let r = Bundle.main.resourceURL?.appendingPathComponent("Detail"), FileManager.default.fileExists(atPath: r.path) { return r }
        return FileManager.default.fileExists(atPath: sourceRoot.path) ? sourceRoot : nil
    }()
    static let sourceRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Resources/Detail")

    private static let lock = NSLock()
    private static var loaded: [Kind: NSImage?] = [:]

    /// A kind's detail as baked, or nil when it is missing: the surface is then its plain colour.
    static func image(_ kind: Kind) -> NSImage? {
        lock.lock(); defer { lock.unlock() }
        if let made = loaded[kind] { return made }
        let image = root.flatMap { NSImage(contentsOf: $0.appendingPathComponent("detail-\(kind.rawValue).png")) }
        loaded[kind] = image
        return image
    }

    /// Lays a kind's detail over a material's colour, `repeats` times across each face.
    static func apply(_ kind: Kind, to m: SCNMaterial, repeats: (Double, Double) = (1, 1)) {
        guard let image = image(kind) else { return }
        m.multiply.contents = image
        m.multiply.mipFilter = .linear
        m.multiply.maxAnisotropy = 8
        m.multiply.wrapS = .repeat; m.multiply.wrapT = .repeat
        if repeats != (1, 1) { m.multiply.contentsTransform = SCNMatrix4MakeScale(CGFloat(repeats.0), CGFloat(repeats.1), 1) }
    }

    /// `rumkapsel --bake-detail`: draws every detail and writes it beside the sources, to be committed. Run it
    /// again after changing how a detail is drawn.
    static func bake() -> Never {
        try? FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        for kind in Kind.allCases {
            let grey = make(kind)
            guard let tiff = picture(grey).tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else { continue }
            let url = sourceRoot.appendingPathComponent("detail-\(kind.rawValue).png")
            try? png.write(to: url)
            print("wrote \(url.path)")
        }
        exit(0)
    }

    // MARK: drawing

    /// A kind's detail as greys, softened and brought to the mean.
    static func make(_ kind: Kind) -> [Double] {
        let n = size
        var v = [Double](repeating: 1, count: n * n)
        var r = Textures.Seeded(s: kind.rawValue.utf8.reduce(UInt64(0x5eed)) { $0 &* 31 &+ UInt64($1) })
        /// Every texel, with where it is across the image.
        func each(_ body: (Int, Double, Double) -> Void) {
            for row in 0..<n { for col in 0..<n { body(row * n + col, (Double(col) + 0.5) / Double(n), (Double(row) + 0.5) / Double(n)) } }
        }
        /// How far a point is in from the nearest line of a grid of `cells` across.
        func seam(_ x: Double, _ y: Double, cells: Double) -> Double {
            let u = (x * cells).truncatingRemainder(dividingBy: 1), w = (y * cells).truncatingRemainder(dividingBy: 1)
            return min(min(u, 1 - u), min(w, 1 - w)) / cells
        }
        func rivets(cells: Double, inset: Double, radius: Double, depth: Double) {
            each { i, x, y in
                let u = (x * cells).truncatingRemainder(dividingBy: 1), w = (y * cells).truncatingRemainder(dividingBy: 1)
                for (cx, cy) in [(inset, inset), (1 - inset, inset), (inset, 1 - inset), (1 - inset, 1 - inset)] {
                    let d = (((u - cx) * (u - cx) + (w - cy) * (w - cy)).squareRoot()) / cells
                    if d < radius { v[i] *= 1 - depth * (0.5 + 0.5 * (d / radius)) }
                }
            }
        }
        /// Scuffs and mottling: wear that every surface has, a little.
        func wear(_ amount: Double) {
            let seed = r.next() * 1000
            each { i, x, y in
                let mottle = Plating.noise(x * 6 + seed, y * 6, seed: 7) - 0.5
                let fine = Plating.noise(x * 40 + seed, y * 40, seed: 9) - 0.5
                let scuff = max(0, Plating.noise(x * 3 + seed, y * 18, seed: 13) - 0.62)
                v[i] *= 1 + amount * (0.6 * mottle + 0.4 * fine) - amount * 2 * scuff
            }
        }
        switch kind {
        case .hallway:
            // Four deck plates in their seams, a rivet in each corner, a faint tread down the middle.
            each { i, x, y in
                let s = seam(x, y, cells: 2)
                if s < 0.004 { v[i] *= 0.72 } else if s < 0.008 { v[i] *= 1.04 }
                let tread = abs(x - 0.5) < 0.2 && Int(x * 64 + y * 64) % 4 == 0 && Int(x * 64 - y * 64 + 512) % 4 == 0
                if tread { v[i] *= 0.93 }
            }
            rivets(cells: 2, inset: 0.06, radius: 0.007, depth: 0.25)
            wear(0.08)
        case .office:
            // One smooth panel in a fine border.
            each { i, x, y in
                let s = seam(x, y, cells: 1)
                if s < 0.003 { v[i] *= 0.78 } else if abs(s - 0.04) < 0.0025 { v[i] *= 0.9 }
            }
            wear(0.05)
        case .quarters:
            // Small composite tiles, four by four.
            each { i, x, y in
                let s = seam(x, y, cells: 4)
                if s < 0.0025 { v[i] *= 0.84 }
                let k = Int(x * 4) * 7 + Int(y * 4) * 13
                v[i] *= 0.97 + 0.03 * Double(k % 5) / 4
            }
            wear(0.04)
        case .yard:
            // Heavy tread plate: raised diamonds, bolted at its edge, oil and scuffs.
            each { i, x, y in
                let u = (x * 24).truncatingRemainder(dividingBy: 1), w = (y * 24).truncatingRemainder(dividingBy: 1)
                let flip = (Int(x * 24) + Int(y * 24)) % 2 == 0
                let a = flip ? u - w : u + w - 1
                if abs(a) < 0.12, abs(u - 0.5) < 0.42, abs(w - 0.5) < 0.42 { v[i] *= 1.06 }
                let s = seam(x, y, cells: 1)
                if s < 0.004 { v[i] *= 0.7 }
            }
            rivets(cells: 4, inset: 0.08, radius: 0.006, depth: 0.22)
            each { i, x, y in
                let oil = max(0, Plating.noise(x * 2.5, y * 2.5, seed: 31) - 0.6)
                v[i] *= 1 - oil * 1.2
            }
            wear(0.1)
        case .bay:
            // Landing plates, a cross of seams and a ring of bolts.
            each { i, x, y in
                if seam(x, y, cells: 2) < 0.004 { v[i] *= 0.7 }
                let d = ((x - 0.5) * (x - 0.5) + (y - 0.5) * (y - 0.5)).squareRoot()
                if abs(d - 0.38) < 0.004 { v[i] *= 0.82 }
            }
            wear(0.1)
        case .airlock:
            // Ribbed plates across the passage, for grip.
            each { i, _, y in
                let rib = (y * 16).truncatingRemainder(dividingBy: 1)
                v[i] *= rib < 0.12 ? 0.84 : (rib < 0.2 ? 1.05 : 1)
            }
            each { i, x, y in if seam(x, y, cells: 1) < 0.004 { v[i] *= 0.72 } }
            wear(0.08)
        case .pod:
            // A cargo pod: chamfered edges, two ribs across, recessed handle slots, a vent grid.
            each { i, x, y in
                let s = seam(x, y, cells: 1)
                if s < 0.03 { v[i] *= 1.07 } else if s < 0.037 { v[i] *= 0.8 }
                for ry in [0.45, 0.53] where y > ry && y < ry + 0.02 { v[i] *= y < ry + 0.01 ? 1.06 : 0.86 }
                for hx in [0.12, 0.7] where x > hx && x < hx + 0.18 && y > 0.16 && y < 0.24 {
                    v[i] *= (x - hx) < 0.012 || (hx + 0.18 - x) < 0.012 ? 0.8 : 0.66
                }
                let gx = (x - 0.64) / 0.04, gy = (y - 0.68) / 0.05
                if gx > 0, gx < 5, gy > 0, gy < 3 {
                    let fx = gx - floor(gx) - 0.5, fy = gy - floor(gy) - 0.5
                    if fx * fx + fy * fy < 0.07 { v[i] *= 0.62 }
                }
            }
            wear(0.06)
        case .hardcase:
            // A hard case: a fine seam frame, two latch slots along the top, a label plate, a chevron strip.
            each { i, x, y in
                let s = seam(x, y, cells: 1)
                if abs(s - 0.05) < 0.004 { v[i] *= 0.8 }
                for lx in [0.25, 0.65] where x > lx && x < lx + 0.1 && y > 0.08 && y < 0.14 { v[i] *= 0.62 }
                if x > 0.55, x < 0.86, y > 0.3, y < 0.42 { v[i] *= abs(min(x - 0.55, 0.86 - x, y - 0.3, 0.42 - y)) < 0.006 ? 0.86 : 1.08 }
                if y > 0.8, y < 0.88, x > 0.08, x < 0.92 { v[i] *= Int((x + y) * 22) % 2 == 0 ? 0.78 : 1.06 }
            }
            wear(0.06)
        case .lid:
            // A lid over a body: the seam between them, the lid's lip a shade lighter, two grip recesses below it.
            each { i, x, y in
                if y < 0.3 { v[i] *= 1.05 }
                if abs(y - 0.3) < 0.006 { v[i] *= 0.7 }
                for gx in [0.18, 0.64] where x > gx && x < gx + 0.18 && y > 0.36 && y < 0.42 { v[i] *= 0.68 }
                if seam(x, y, cells: 1) < 0.01 { v[i] *= 0.84 }
            }
            wear(0.07)
        case .hull:
            // The rocket's own plating, its colour turned to greys.
            let maps = Plating.maps(seed: 21)
            if let cg = maps.color.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                let w = cg.width, h = cg.height
                var px = [UInt8](repeating: 0, count: w * h * 4)
                let ctx = px.withUnsafeMutableBytes { CGContext(data: $0.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) }
                ctx?.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
                each { i, x, y in
                    let j = (min(h - 1, Int(y * Double(h))) * w + min(w - 1, Int(x * Double(w)))) * 4
                    v[i] = (Double(px[j]) + Double(px[j + 1]) + Double(px[j + 2])) / (3 * 255)
                }
            }
        }
        // Brought to the mean, then softened: half the contrast, so it is detail and not pattern.
        let avg = v.reduce(0, +) / Double(v.count)
        let softness = kind == .hull ? 0.45 : 0.75
        return v.map { min(1.15, 1 - (1 - $0 / avg * mean) * softness) }
    }

    /// A kind's detail drawn here and now, not loaded: for trying a new one before it is baked.
    static func fresh(_ kind: Kind) -> NSImage { picture(make(kind)) }

    private static func picture(_ grey: [Double]) -> NSImage {
        let n = size
        var px = [UInt8](repeating: 255, count: n * n * 4)
        for i in 0..<(n * n) {
            let b = UInt8(max(0, min(255, grey[i] * 255)))
            px[i * 4] = b; px[i * 4 + 1] = b; px[i * 4 + 2] = b
        }
        let ctx = px.withUnsafeMutableBytes { CGContext(data: $0.baseAddress, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
                                                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) }
        guard let cg = ctx?.makeImage() else { return NSImage() }
        return NSImage(cgImage: cg, size: NSSize(width: n, height: n))
    }
}
