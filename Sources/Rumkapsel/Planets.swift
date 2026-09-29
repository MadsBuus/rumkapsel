// A repository's production, as a planet on the horizon: a real surface, in its colour.

import AppKit
import SceneKit

enum Planets {
    /// The surfaces in Resources/Planets, from Solar System Scope (CC BY 4.0).
    static let surfaces = ["mercury", "moon", "mars", "ceres", "eris", "haumea", "makemake", "jupiter", "saturn", "uranus", "neptune", "venus_atmosphere", "earth_daymap"]

    static let root: URL? = {
        if let r = Bundle.main.resourceURL?.appendingPathComponent("Planets"), FileManager.default.fileExists(atPath: r.path) { return r }
        let src = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/Planets")
        return FileManager.default.fileExists(atPath: src.path) ? src : nil
    }()

    /// The same name makes the same world on every run.
    static func seed(_ name: String) -> UInt32 {
        var h: UInt32 = 2166136261
        for b in name.utf8 { h = (h ^ UInt32(b)) &* 16777619 }
        return h
    }

    static func surfaceName(for name: String) -> String { surfaces[Int(seed(name) % UInt32(surfaces.count))] }

    private static var tinted: [String: CGImage] = [:]
    private static let lock = NSLock()

    /// A lit globe with a rim of atmosphere; the saturn surface keeps its ring. The scene turns the globe.
    static func make(name: String, color: NSColor, radius: Double) -> SCNNode {
        let node = SCNNode()
        let surface = surfaceName(for: name)
        let globe = SCNNode(geometry: SCNSphere(radius: radius))
        (globe.geometry as! SCNSphere).segmentCount = 72
        let m = SCNMaterial()
        m.lightingModel = .lambert
        m.diffuse.contents = color
        // Tinted off the render thread; the plain colour stands in until then.
        DispatchQueue.global(qos: .utility).async { if let img = image(surface, color: color) { m.diffuse.contents = img } }
        globe.geometry!.firstMaterial = m
        globe.name = "globe"
        node.addChildNode(globe)
        node.addChildNode(atmosphere(radius: radius, color: color))
        if surface == "saturn", let ring = ring(inner: radius * 1.25, outer: radius * 2.3, color: color) {
            ring.eulerAngles = SCNVector3(0.42, 0, 0.18)
            node.addChildNode(ring)
        }
        return node
    }

    private static func atmosphere(radius: Double, color: NSColor) -> SCNNode {
        let air = SCNNode(geometry: SCNSphere(radius: radius * 1.06))
        (air.geometry as! SCNSphere).segmentCount = 48
        let a = SCNMaterial()
        a.lightingModel = .constant
        a.blendMode = .add
        a.writesToDepthBuffer = false
        a.diffuse.contents = NSColor.black
        a.shaderModifiers = [.fragment: """
            #pragma arguments
            float3 glow;
            #pragma body
            float rim = 1.0 - saturate(dot(normalize(_surface.normal), normalize(_surface.view)));
            float g = pow(rim, 2.6);
            _output.color = float4(glow * g, g);
            """]
        let c = color.lighter(0.35).usingColorSpace(.deviceRGB) ?? color
        a.setValue(SCNVector3(c.redComponent, c.greenComponent, c.blueComponent), forKey: "glow")
        air.geometry!.firstMaterial = a
        air.name = "air"
        return air
    }

    /// A flat ring, its texture running from the inner edge to the outer.
    private static func ring(inner: Double, outer: Double, color: NSColor) -> SCNNode? {
        guard let img = image("ring", ext: "png", color: color, keepAlpha: true) else { return nil }
        let n = 96
        var verts: [SCNVector3] = [], uvs: [CGPoint] = [], idx: [Int32] = []
        for i in 0...n {
            let a = Double(i) / Double(n) * 2 * .pi
            verts.append(SCNVector3(cos(a) * inner, 0, sin(a) * inner)); uvs.append(CGPoint(x: 0, y: 0.5))
            verts.append(SCNVector3(cos(a) * outer, 0, sin(a) * outer)); uvs.append(CGPoint(x: 1, y: 0.5))
        }
        for i in 0..<n {
            let b = Int32(i * 2)
            idx += [b, b + 1, b + 2, b + 1, b + 3, b + 2]
        }
        let g = SCNGeometry(sources: [SCNGeometrySource(vertices: verts), SCNGeometrySource(textureCoordinates: uvs)],
                            elements: [SCNGeometryElement(indices: idx, primitiveType: .triangles)])
        let m = SCNMaterial()
        m.lightingModel = .lambert
        m.diffuse.contents = img
        m.isDoubleSided = true
        m.writesToDepthBuffer = false
        g.firstMaterial = m
        let node = SCNNode(geometry: g)
        node.name = "ring"
        return node
    }

    /// A surface in the repository's colour: its own dark and light stretched to the colour's darkest and lightest.
    static func image(_ surface: String, ext: String = "jpg", color: NSColor, keepAlpha: Bool = false) -> CGImage? {
        let key = "\(surface)|\(color)"
        lock.lock(); defer { lock.unlock() }
        if let t = tinted[key] { return t }
        guard let url = root?.appendingPathComponent("\(surface).\(ext)"),
              let src = CGImageSourceCreateWithURL(url as CFURL, nil), let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        let w = cg.width, h = cg.height
        var px = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        var hist = [Int](repeating: 0, count: 256)
        var lum = [UInt8](repeating: 0, count: w * h)
        for i in 0..<(w * h) {
            let l = (Int(px[i * 4]) * 54 + Int(px[i * 4 + 1]) * 183 + Int(px[i * 4 + 2]) * 19) >> 8
            lum[i] = UInt8(l); hist[l] += 1
        }
        // The 2nd and 98th percentiles.
        func percentile(_ p: Double) -> Int {
            let target = Int(Double(w * h) * p); var run = 0
            for (i, c) in hist.enumerated() { run += c; if run >= target { return i } }
            return 255
        }
        let lo = Double(percentile(0.02)), hi = max(lo + 1, Double(percentile(0.98)))
        func rgb(_ c: NSColor) -> SIMD3<Double> {
            let d = c.usingColorSpace(.deviceRGB) ?? c
            return SIMD3(Double(d.redComponent), Double(d.greenComponent), Double(d.blueComponent))
        }
        let dark = rgb(color.darker(0.82)), mid = rgb(color.darker(0.15)), light = rgb(color.lighter(0.3))
        for i in 0..<(w * h) {
            let t = max(0, min(1, (Double(lum[i]) - lo) / (hi - lo)))
            let c = t < 0.5 ? dark + (mid - dark) * (t * 2) : mid + (light - mid) * ((t - 0.5) * 2)
            let a = keepAlpha ? Double(px[i * 4 + 3]) / 255 : 1
            px[i * 4] = UInt8(max(0, min(255, c.x * 255 * a)))
            px[i * 4 + 1] = UInt8(max(0, min(255, c.y * 255 * a)))
            px[i * 4 + 2] = UInt8(max(0, min(255, c.z * 255 * a)))
            if !keepAlpha { px[i * 4 + 3] = 255 }
        }
        guard let out = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage() else { return nil }
        tinted[key] = out
        return out
    }
}
