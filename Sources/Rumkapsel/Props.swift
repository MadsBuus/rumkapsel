import AppKit
import SceneKit

/// The things that populate a station, so the gallery and the scene draw the same props.
enum Props {
    /// The soft dark patch under a prop, the game's "foot".
    static func foot(color: NSColor, size: Double) -> SCNNode {
        let f = SCNNode(geometry: SCNPlane(width: size, height: size))
        f.geometry!.firstMaterial = flat(color)
        f.eulerAngles.x = -.pi / 2
        f.position = v3(size * 0.06, 0.004, size * 0.06)
        return f
    }

    /// A square pyramid with two lit faces and two shaded, like the game's resource pyramids.
    static func pyramid(color: NSColor, size: Double, floor: NSColor) -> SCNNode {
        let geo = SCNPyramid(width: size, height: size * 0.9, length: size)
        geo.materials = [flat(color.darker(0.2)), flat(color.lighter(0.12)), flat(color.darker(0.08)), flat(color.darker(0.2)), flat(color.darker(0.14))]
        let n = SCNNode()
        let body = SCNNode(geometry: geo)
        body.position = v3(0, 0, 0)
        n.addChildNode(body)
        n.addChildNode(foot(color: floor.darker(0.16), size: size * 1.15))
        return n
    }

    /// A plain crate: one pull request's worth of work, with a dark strap groove and a small status tag on top.
    /// Shapes mean things: a hexagon is a packed office, a cube is a piece of work (commits),
    /// a square strapped crate is a pull request, a pyramid is a session input.
    static func package(color: NSColor, band: NSColor, size: Double) -> SCNNode {
        let n = SCNNode()
        let h = size * 0.8
        let box = SCNBox(width: size, height: h, length: size, chamferRadius: 0)
        box.materials = [flat(color), flat(color.darker(0.13)), flat(color), flat(color.darker(0.13)), flat(color.lighter(0.14)), flat(color)]
        let body = SCNNode(geometry: box)
        body.position = v3(0, h / 2, 0)
        n.addChildNode(body)
        // Strap groove: a slightly proud ring in a deeper shade, flush like a real crate strap.
        let strap = SCNBox(width: size * 1.02, height: h * 0.16, length: size * 1.02, chamferRadius: 0)
        strap.materials = [flat(color.darker(0.3)), flat(color.darker(0.38)), flat(color.darker(0.3)), flat(color.darker(0.38)), flat(color.darker(0.22)), flat(color.darker(0.3))]
        let s = SCNNode(geometry: strap)
        s.position = v3(0, h / 2, 0)
        n.addChildNode(s)
        // Status tag on the lid.
        let tag = SCNNode(geometry: SCNBox(width: size * 0.34, height: 0.012, length: size * 0.24, chamferRadius: 0))
        tag.geometry!.firstMaterial = flat(band)
        tag.position = v3(size * 0.22, h + 0.006, -size * 0.22)
        n.addChildNode(tag)
        n.addChildNode(foot(color: color.darker(0.28), size: size * 1.3))
        return n
    }

    /// A hexagonal crate in the repo colour: the order for a new office.
    static func crate(color: NSColor) -> SCNNode {
        let geo = SCNCylinder(radius: 0.26, height: 0.18)
        geo.radialSegmentCount = 6
        let top = flat(color.lighter(0.16)), side = flat(color.darker(0.06))
        geo.materials = [side, top, top]
        let n = SCNNode()
        let body = SCNNode(geometry: geo)
        body.eulerAngles.y = .pi / 6
        n.addChildNode(body)
        n.addChildNode(foot(color: color.darker(0.3), size: 0.7))
        return n
    }

    static func rocket(color: NSColor, tall: Bool, cargo: Int = 0) -> SCNNode {
        let n = SCNNode()
        // A production rocket grows with what it will carry: small for a couple of boxes, big for a dozen.
        let grow = tall ? min(1.6, 0.85 + Double(cargo) * 0.06) : 1.0
        let h = (tall ? 1.5 : 0.9) * grow, r = (tall ? 0.17 : 0.12) * (0.7 + 0.3 * grow)
        let white = lit(NSColor(rgb: (0.92, 0.92, 0.95)))
        let dark = lit(NSColor(rgb: (0.2, 0.21, 0.26)))
        // Body, a slightly wider lower stage, and a nose cone in the repo colour.
        let lower = SCNNode(geometry: SCNCylinder(radius: r, height: h * 0.45))
        lower.geometry!.firstMaterial = white
        lower.position = v3(0, 0.12 + h * 0.225, 0)
        n.addChildNode(lower)
        let band = SCNNode(geometry: SCNCylinder(radius: r * 1.02, height: h * 0.08))
        band.geometry!.firstMaterial = lit(color)
        band.position = v3(0, 0.12 + h * 0.45, 0)
        n.addChildNode(band)
        let upper = SCNNode(geometry: SCNCylinder(radius: r * 0.9, height: h * 0.4))
        upper.geometry!.firstMaterial = white
        upper.position = v3(0, 0.12 + h * 0.49 + h * 0.2, 0)
        n.addChildNode(upper)
        let nose = SCNNode(geometry: SCNCone(topRadius: 0, bottomRadius: r * 0.9, height: r * 2.6))
        nose.geometry!.firstMaterial = lit(color)
        nose.position = v3(0, 0.12 + h * 0.89 + r * 1.3, 0)
        n.addChildNode(nose)
        // Portholes on the upper stage.
        for k in 0..<3 {
            let port = SCNNode(geometry: SCNSphere(radius: r * 0.18))
            port.geometry!.firstMaterial = flat(NSColor(rgb: (0.35, 0.55, 0.85)))
            let a = Double(k) * 2 * .pi / 3
            port.position = v3(sin(a) * r * 0.86, 0.12 + h * 0.75, cos(a) * r * 0.86)
            n.addChildNode(port)
        }
        // Four swept fins and an engine nozzle.
        for k in 0..<4 {
            let pivot = SCNNode()
            pivot.eulerAngles.y = Double(k) * .pi / 2 + .pi / 4
            let fin = SCNNode(geometry: SCNBox(width: 0.035, height: r * 2.4, length: r * 1.5, chamferRadius: 0))
            fin.geometry!.firstMaterial = lit(color)
            fin.position = v3(0, 0.12 + r * 1.0, r + r * 0.55)
            fin.eulerAngles.x = 0.35
            pivot.addChildNode(fin)
            n.addChildNode(pivot)
        }
        let nozzle = SCNNode(geometry: SCNCone(topRadius: r * 0.55, bottomRadius: r * 0.8, height: 0.14))
        nozzle.geometry!.firstMaterial = dark
        nozzle.position = v3(0, 0.05, 0)
        n.addChildNode(nozzle)
        // Landing legs so it stands on the pad.
        for k in 0..<3 {
            let pivot = SCNNode()
            pivot.eulerAngles.y = Double(k) * 2 * .pi / 3
            let leg = SCNNode(geometry: SCNBox(width: 0.03, height: 0.22, length: 0.03, chamferRadius: 0))
            leg.geometry!.firstMaterial = dark
            leg.position = v3(0, 0.1, r * 1.1)
            leg.eulerAngles.x = 0.5
            pivot.addChildNode(leg)
            n.addChildNode(pivot)
        }
        let flame = SCNNode(geometry: SCNCone(topRadius: r * 0.6, bottomRadius: 0, height: 0.45))
        flame.geometry!.firstMaterial = flat(Palette.pyramid)
        flame.position = v3(0, -0.2, 0)
        flame.name = "flame"
        flame.opacity = 0
        n.addChildNode(flame)
        return n
    }

    /// A red-and-white tape barrier with a gantry ladder: the release is up but not cleared to fly.
    static func holdDecoration(around center: SIMD3<Double>, tall: Bool) -> SCNNode {
        let n = SCNNode()
        let red = flat(NSColor(rgb: (0.9, 0.2, 0.2))), white = flat(NSColor(rgb: (0.95, 0.95, 0.95)))
        let radius = 0.72, postH = 0.32
        for k in 0..<4 {
            let a = Double(k) * .pi / 2 + .pi / 4
            let post = SCNNode(geometry: SCNBox(width: 0.05, height: postH, length: 0.05, chamferRadius: 0))
            post.geometry!.firstMaterial = lit(NSColor(rgb: (0.3, 0.3, 0.35)))
            post.position = v3(center.x + cos(a) * radius, postH / 2, center.z + sin(a) * radius)
            n.addChildNode(post)
            // Tape between this post and the next, striped in short segments.
            let b = a + .pi / 2
            let p0 = SIMD2(center.x + cos(a) * radius, center.z + sin(a) * radius)
            let p1 = SIMD2(center.x + cos(b) * radius, center.z + sin(b) * radius)
            let segs = 6
            for i in 0..<segs {
                let t0 = Double(i) / Double(segs), t1 = Double(i + 1) / Double(segs)
                let m0 = p0 + (p1 - p0) * t0, m1 = p0 + (p1 - p0) * t1
                let mid = (m0 + m1) / 2
                let d = m1 - m0
                let len = (d.x * d.x + d.y * d.y).squareRoot()
                let seg = SCNNode(geometry: SCNBox(width: len, height: 0.06, length: 0.012, chamferRadius: 0))
                seg.geometry!.firstMaterial = i % 2 == 0 ? red : white
                seg.position = v3(mid.x, postH * 0.8, mid.y)
                seg.eulerAngles.y = -atan2(d.y, d.x)
                n.addChildNode(seg)
            }
        }
        // Gantry: a tower with rungs beside the rocket.
        let h = tall ? 1.7 : 1.1
        let tower = SCNNode()
        for dz in [-0.08, 0.08] {
            let rail = SCNNode(geometry: SCNBox(width: 0.04, height: h, length: 0.04, chamferRadius: 0))
            rail.geometry!.firstMaterial = lit(NSColor(rgb: (0.75, 0.55, 0.2)))
            rail.position = v3(0, h / 2, dz)
            tower.addChildNode(rail)
        }
        var y = 0.15
        while y < h {
            let rung = SCNNode(geometry: SCNBox(width: 0.03, height: 0.03, length: 0.2, chamferRadius: 0))
            rung.geometry!.firstMaterial = lit(NSColor(rgb: (0.75, 0.55, 0.2)))
            rung.position = v3(0, y, 0)
            tower.addChildNode(rung)
            y += 0.18
        }
        tower.position = v3(center.x + 0.32, 0, center.z + 0.02)
        n.addChildNode(tower)
        return n
    }

}
