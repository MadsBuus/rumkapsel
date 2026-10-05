// The flight rocket's hull plating, generated: big plates with their corners cut at 45°, deep grooves between
// them, finer engraved lines, greeble patches and bolts, and over all of it the grit of poured concrete, mottled
// and pitted. One height map is drawn and everything is read from it: the colour (grime gathers in what is
// low), the relief the light finds (a normal map), and how rough each spot is. Nothing here is SceneKit's
// business but the images at the end.

import AppKit
import simd

enum Plating {
    /// The maps for one skin, each `size` square.
    struct Maps { let color: NSImage; let normal: NSImage; let roughness: NSImage }

    /// The plating's own paint, which every colour is laid over.
    static let paleTint = SIMD3(0.62, 0.65, 0.68)

    /// Where the baked maps are: in the app's resources, or beside the sources when run from a build.
    static let root: URL? = {
        if let r = Bundle.main.resourceURL?.appendingPathComponent("Plating"), FileManager.default.fileExists(atPath: r.path) { return r }
        let src = sourceRoot
        return FileManager.default.fileExists(atPath: src.path) ? src : nil
    }()
    static let sourceRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Resources/Plating")

    private static var cache: [UInt64: Maps] = [:]
    private static let lock = NSLock()
    private static let kinds = ["color", "normal", "roughness"]

    /// The maps for one layout, as baked into the app by `bake`; made here and now only if they are missing.
    static func maps(seed: UInt64) -> Maps {
        lock.lock(); defer { lock.unlock() }
        if let m = cache[seed] { return m }
        let loaded = kinds.compactMap { k in root.flatMap { NSImage(contentsOf: $0.appendingPathComponent("plating-\(seed)-\(k).png")) } }
        let m = loaded.count == 3 ? Maps(color: loaded[0], normal: loaded[1], roughness: loaded[2]) : make(seed: seed)
        cache[seed] = m
        return m
    }

    /// Makes the maps for a layout from scratch: slow, which is why they are baked.
    static func make(seed: UInt64, size: Int = 1024) -> Maps {
        let height = heightField(seed: seed, size: size)
        // The relief is read off a lightly softened field, so a trace a texel wide does not flicker in the light.
        return Maps(color: colorMap(height, seed: seed, size: size, tint: paleTint),
                    normal: normalMap(soften(height, size: size), size: size, strength: 16),
                    roughness: roughnessMap(height, seed: seed, size: size))
    }

    /// `rumkapsel --bake-plating`: makes every layout the flight rocket uses and writes them beside the sources,
    /// to be committed. Run it again after changing how plating is made.
    static func bake(_ seeds: [UInt64]) -> Never {
        try? FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        for seed in seeds {
            let m = make(seed: seed)
            for (image, kind) in zip([m.color, m.normal, m.roughness], kinds) {
                guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                      let png = rep.representation(using: .png, properties: [:]) else { continue }
                let url = sourceRoot.appendingPathComponent("plating-\(seed)-\(kind).png")
                try? png.write(to: url)
                print("wrote \(url.path)")
            }
        }
        exit(0)
    }

    // MARK: the height field

    /// Small panels at slightly different heights, thin recessed traces between and across them turning at right
    /// angles, and rivets: a circuit-board of plating. Every mark wraps at the edges, so copies meet without a seam.
    static func heightField(seed: UInt64, size n: Int) -> [Float] {
        var h = [Float](repeating: 0.5, count: n * n)
        var r = Textures.Seeded(s: seed &* 2654435761 | 1)
        func at(_ x: Int, _ y: Int) -> Int { ((y % n + n) % n) * n + (x % n + n) % n }
        // Panels: the square split again and again into rectangles, each a step up or down from the next.
        var panels: [(x: Int, y: Int, w: Int, h: Int)] = [(0, 0, n, n)]
        for _ in 0..<8 {
            panels = panels.flatMap { p -> [(x: Int, y: Int, w: Int, h: Int)] in
                guard max(p.w, p.h) > n / 20, r.next() < 0.85 else { return [p] }
                let alongX = p.w > p.h ? r.next() < 0.75 : r.next() < 0.25
                let t = 0.25 + r.next() * 0.5
                if alongX { let a = max(1, Int(Double(p.w) * t)); return [(p.x, p.y, a, p.h), (p.x + a, p.y, p.w - a, p.h)] }
                let a = max(1, Int(Double(p.h) * t)); return [(p.x, p.y, p.w, a), (p.x, p.y + a, p.w, p.h - a)]
            }
        }
        for p in panels {
            let level = Float(0.5 + (r.next() - 0.5) * 0.24)
            for y in p.y..<(p.y + p.h) { for x in p.x..<(p.x + p.w) { h[at(x, y)] = level } }
        }
        // A thin seam round most panels, sunk a little.
        for p in panels where r.next() < 0.7 {
            for x in p.x..<(p.x + p.w) { h[at(x, p.y)] -= 0.16; h[at(x, p.y + 1)] -= 0.08; h[at(x, p.y + p.h - 1)] -= 0.06 }
            for y in p.y..<(p.y + p.h) { h[at(p.x, y)] -= 0.16; h[at(p.x + 1, y)] -= 0.08; h[at(p.x + p.w - 1, y)] -= 0.06 }
        }
        // Traces: recessed lines a texel or two wide, running straight and turning at right angles.
        for _ in 0..<(n / 5) {
            var x = Int(r.next() * Double(n)), y = Int(r.next() * Double(n))
            let wide = r.next() < 0.3
            var dir = Int(r.next() * 4)
            for _ in 0..<(2 + Int(r.next() * 5)) {
                let len = Int(Double(n) * (0.01 + r.next() * 0.07))
                for _ in 0..<len {
                    h[at(x, y)] -= 0.12
                    if wide { h[at(x + (dir % 2 == 0 ? 0 : 1), y + (dir % 2 == 0 ? 1 : 0))] -= 0.05 }
                    switch dir { case 0: x += 1; case 1: y += 1; case 2: x -= 1; default: y -= 1 }
                }
                dir = (dir + (r.next() < 0.5 ? 1 : 3)) % 4
            }
        }
        // Rivets: small raised dots, at panel corners and scattered.
        func rivet(_ cx: Int, _ cy: Int) {
            for yy in -2...2 { for xx in -2...2 {
                let d = Double(xx * xx + yy * yy).squareRoot()
                if d <= 1.8 { h[at(cx + xx, cy + yy)] += Float(0.06 * (1 - d / 2.2)) }
            } }
        }
        for p in panels where p.w > n / 30 && p.h > n / 30 && r.next() < 0.6 {
            rivet(p.x + 5, p.y + 5); rivet(p.x + p.w - 6, p.y + 5); rivet(p.x + 5, p.y + p.h - 6); rivet(p.x + p.w - 6, p.y + p.h - 6)
        }
        for _ in 0..<(n / 3) { rivet(Int(r.next() * Double(n)), Int(r.next() * Double(n))) }
        return h
    }

    // MARK: maps from the height field

    /// Smooth noise, a few octaves of it, for mottling.
    static func noise(_ x: Double, _ y: Double, seed: UInt64) -> Double {
        func hash(_ i: Int, _ j: Int) -> Double {
            var v = UInt64(bitPattern: Int64(i &* 73856093 ^ j &* 19349663)) ^ seed
            v = (v ^ (v >> 33)) &* 0xff51afd7ed558ccd; v = (v ^ (v >> 33)) &* 0xc4ceb9fe1a85ec53; v ^= v >> 33
            return Double(v >> 11) / Double(1 << 53)
        }
        var total = 0.0, amp = 0.5, f = 1.0
        for _ in 0..<5 {
            let xf = x * f, yf = y * f, i = Int(floor(xf)), j = Int(floor(yf))
            let tx = xf - floor(xf), ty = yf - floor(yf)
            let sx = tx * tx * (3 - 2 * tx), sy = ty * ty * (3 - 2 * ty)
            let a = hash(i, j), b = hash(i + 1, j), c = hash(i, j + 1), d = hash(i + 1, j + 1)
            total += amp * (a + (b - a) * sx + (c - a) * sy + (a - b - c + d) * sx * sy)
            amp *= 0.5; f *= 2.03
        }
        return total
    }

    /// How sunk a texel is among its neighbours: grime and shade gather there.
    static func occlusion(_ h: [Float], size n: Int, radius: Int) -> [Float] {
        // A box blur of the height, twice, then how far below its surroundings each texel sits.
        func blur(_ src: [Float]) -> [Float] {
            var tmp = [Float](repeating: 0, count: n * n), out = tmp
            for y in 0..<n { var acc: Float = 0
                for x in -radius...radius { acc += src[y * n + (x + n) % n] }
                for x in 0..<n { tmp[y * n + x] = acc / Float(2 * radius + 1); acc += src[y * n + (x + radius + 1) % n] - src[y * n + (x - radius + n) % n] } }
            for x in 0..<n { var acc: Float = 0
                for y in -radius...radius { acc += tmp[((y + n) % n) * n + x] }
                for y in 0..<n { out[y * n + x] = acc / Float(2 * radius + 1); acc += tmp[((y + radius + 1) % n) * n + x] - tmp[((y - radius + n) % n) * n + x] } }
            return out
        }
        let b = blur(blur(h))
        return zip(h, b).map { max(0, $1 - $0) }
    }

    static func colorMap(_ h: [Float], seed: UInt64, size n: Int, tint: SIMD3<Double>) -> NSImage {
        let ao = occlusion(h, size: n, radius: 2)
        var r = Textures.Seeded(s: seed ^ 0x9e3779b97f4a7c15)
        // Pores: dark specks of every size, more of the small ones.
        var pores = [Float](repeating: 0, count: n * n)
        for _ in 0..<(n * n / 160) {
            let x = Int(r.next() * Double(n)), y = Int(r.next() * Double(n))
            // In clusters: where the mottling is dark, pores gather; where it is pale, most are passed over.
            guard noise(Double(x) * 9 / Double(n), Double(y) * 9 / Double(n), seed: seed ^ 23) > 0.42 + r.next() * 0.25 else { continue }
            let rad = r.next() < 0.92 ? 0.6 + r.next() * 1.2 : 1.8 + r.next() * 3.2
            let ir = Int(ceil(rad))
            for yy in (y - ir)...(y + ir) { for xx in (x - ir)...(x + ir) {
                let d = Double((xx - x) * (xx - x) + (yy - y) * (yy - y)).squareRoot()
                guard d <= rad else { continue }
                let i = ((yy + n) % n) * n + (xx + n) % n
                pores[i] = max(pores[i], Float(0.75 * (1 - d / (rad + 0.6))))
            } }
        }
        var px = [UInt8](repeating: 255, count: n * n * 4)
        let scale = 7.0 / Double(n)
        for y in 0..<n {
            for x in 0..<n {
                let i = y * n + x
                let mottle = noise(Double(x) * scale, Double(y) * scale, seed: seed) - 0.5
                let fine = noise(Double(x) * scale * 6, Double(y) * scale * 6, seed: seed ^ 7) - 0.5
                let hv = Double(h[i])
                var c = tint * (1 + 0.16 * mottle + 0.07 * fine)
                // Each plate a shade of its own, by where it is; grooves dark, grime in what is sunk.
                c *= 0.82 + 0.36 * (hv - 0.5)
                c *= 1 - min(0.5, Double(ao[i]) * 4)
                c *= 1 - Double(pores[i])
                px[i * 4] = UInt8(max(0, min(255, c.x * 255))); px[i * 4 + 1] = UInt8(max(0, min(255, c.y * 255)))
                px[i * 4 + 2] = UInt8(max(0, min(255, c.z * 255)))
            }
        }
        return image(px, size: n)
    }

    /// The field with each texel averaged with its eight neighbours.
    static func soften(_ h: [Float], size n: Int) -> [Float] {
        var out = h
        for y in 0..<n { for x in 0..<n {
            var acc: Float = 0
            for dy in -1...1 { for dx in -1...1 { acc += h[((y + dy + n) % n) * n + (x + dx + n) % n] } }
            out[y * n + x] = acc / 9
        } }
        return out
    }

    /// The slope of the height field as a tangent-space normal map: x across, y up the image.
    static func normalMap(_ h: [Float], size n: Int, strength: Float) -> NSImage {
        var px = [UInt8](repeating: 255, count: n * n * 4)
        for y in 0..<n {
            for x in 0..<n {
                func at(_ xx: Int, _ yy: Int) -> Float { h[((yy + n) % n) * n + (xx + n) % n] }
                let dx = (at(x + 1, y) - at(x - 1, y)) * strength
                let dy = (at(x, y + 1) - at(x, y - 1)) * strength
                let v = simd_normalize(SIMD3<Float>(-dx, dy, 1))
                let i = (y * n + x) * 4
                px[i] = UInt8((v.x * 0.5 + 0.5) * 255); px[i + 1] = UInt8((v.y * 0.5 + 0.5) * 255); px[i + 2] = UInt8((v.z * 0.5 + 0.5) * 255)
            }
        }
        return image(px, size: n)
    }

    /// Plates fairly smooth, grooves and grime rough.
    static func roughnessMap(_ h: [Float], seed: UInt64, size n: Int) -> NSImage {
        var px = [UInt8](repeating: 255, count: n * n * 4)
        let scale = 11.0 / Double(n)
        for y in 0..<n {
            for x in 0..<n {
                let i = y * n + x
                let v = 0.6 + 0.25 * (noise(Double(x) * scale, Double(y) * scale, seed: seed ^ 3) - 0.5) + 1.2 * Double(max(0, 0.5 - h[i]))
                let b = UInt8(max(0, min(255, v * 255)))
                px[i * 4] = b; px[i * 4 + 1] = b; px[i * 4 + 2] = b
            }
        }
        return image(px, size: n)
    }

    private static func image(_ px: [UInt8], size n: Int) -> NSImage {
        var data = px
        let cs = CGColorSpaceCreateDeviceRGB()
        let ctx = data.withUnsafeMutableBytes { buf in
            CGContext(data: buf.baseAddress, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4, space: cs,
                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        }
        guard let cg = ctx?.makeImage() else { return NSImage() }
        return NSImage(cgImage: cg, size: NSSize(width: n, height: n))
    }
}
