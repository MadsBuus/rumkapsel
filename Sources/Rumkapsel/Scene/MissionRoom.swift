import AppKit
import SceneKit

enum MissionRoom {
    struct Palette {
        var console = NSColor(rgb: (0.52, 0.58, 0.6)), dark = NSColor(rgb: (0.14, 0.15, 0.16)), glow = NSColor(rgb: (0.45, 0.95, 0.6))
        static let ops = Palette()
    }

    static func console(_ size: SIMD2<Double>, _ p: Palette) -> SCNNode {
        let n = SCNNode()
        let w = size.x, d = size.y
        n.addChildNode(box(w, 0.2, d, lit(p.console), at: v3(0, 0.1, 0), chamfer: 0.01))
        let slope = box(w, 0.012, d * 0.6, lit(p.console.blended(withFraction: 0.2, of: .white)!), at: v3(0, 0.215, d * 0.2))
        slope.eulerAngles.x = 0.35
        n.addChildNode(slope)
        n.addChildNode(box(w, 0.16, d * 0.46, lit(p.console), at: v3(0, 0.3, -d * 0.27), chamfer: 0.01))
        n.addChildNode(box(w - 0.04, 0.012, 0.04, lit(p.dark), at: v3(0, 0.386, -d * 0.27)))
        for k in -1...1 {
            let x = Double(k) * w * 0.31
            n.addChildNode(box(w * 0.2, 0.12, 0.006, flat(NSColor(rgb: (0.05, 0.08, 0.06))), at: v3(x, 0.31, -0.008)))
            n.addChildNode(screen(w * 0.16, 0.09, Screens.table(p.glow), at: v3(x, 0.31, -0.012), bezel: 0.004))
        }
        let colors = [NSColor(rgb: (0.92, 0.35, 0.3)), NSColor(rgb: (0.95, 0.82, 0.35)), NSColor(rgb: (0.92, 0.93, 0.9)), NSColor(rgb: (0.4, 0.8, 0.55))]
        for r in 0..<2 {
            for c in 0..<11 {
                let key = box(0.028, 0.008, 0.02, flat(colors[(r * 3 + c * 7) % colors.count]),
                              at: v3(-w * 0.41 + Double(c) * w * 0.081, 0.226 + Double(r) * 0.012, d * 0.12 + Double(r) * 0.035))
                key.eulerAngles.x = 0.35
                n.addChildNode(key)
            }
        }
        return n
    }

    static func hologram() -> SCNNode {
        let n = SCNNode()
        let cyan = NSColor(rgb: (0.4, 0.9, 1.0))
        let station = SCNNode(geometry: faceted(SCNCylinder(radius: 0.06, height: 0.03), 6))
        station.geometry!.firstMaterial = holo(cyan, 0.9)
        station.position = v3(0, 0.1, 0)
        n.addChildNode(station)
        for (r, a, size) in [(0.22, 0.4, 0.035), (0.33, 2.2, 0.05), (0.4, 4.1, 0.03), (0.28, 5.3, 0.025)] {
            let orbit = SCNNode(geometry: SCNTorus(ringRadius: r, pipeRadius: 0.002))
            orbit.geometry!.firstMaterial = holo(cyan, 0.45)
            orbit.position = v3(0, 0.1, 0)
            n.addChildNode(orbit)
            let planet = SCNNode(geometry: SCNSphere(radius: size))
            planet.geometry!.firstMaterial = holo(cyan, 0.7)
            planet.position = v3(sin(a) * r, 0.1, cos(a) * r)
            n.addChildNode(planet)
        }
        return n
    }

    static func holo(_ color: NSColor, _ alpha: Double) -> SCNMaterial {
        let m = SCNMaterial()
        m.diffuse.contents = color
        m.emission.contents = color
        m.lightingModel = .constant
        m.transparency = CGFloat(alpha)
        m.blendMode = .add
        m.writesToDepthBuffer = false
        m.isDoubleSided = true
        return m
    }

    static func screen(_ w: Double, _ h: Double, _ image: NSImage, at: SCNVector3, bezel: Double = 0.02) -> SCNNode {
        let frame = box(w + bezel * 2, h + bezel * 2, 0.02, lit(NSColor(rgb: (0.1, 0.11, 0.13))), at: at)
        let face = SCNNode(geometry: SCNPlane(width: w, height: h))
        let m = SCNMaterial()
        m.diffuse.contents = image
        m.emission.contents = image
        m.lightingModel = .constant
        face.geometry!.firstMaterial = m
        face.position = v3(0, 0, 0.011)
        frame.addChildNode(face)
        return frame
    }

    static func box(_ w: Double, _ h: Double, _ d: Double, _ m: SCNMaterial, at: SCNVector3, chamfer: Double = 0) -> SCNNode {
        let n = SCNNode(geometry: SCNBox(width: w, height: h, length: d, chamferRadius: chamfer))
        n.geometry!.firstMaterial = m
        n.position = at
        return n
    }
}

enum Screens {
    private static func draw(_ w: Int, _ h: Int, _ body: (CGContext, CGFloat, CGFloat) -> Void) -> NSImage {
        let image = NSImage(size: NSSize(width: w, height: h))
        image.lockFocus()
        if let c = NSGraphicsContext.current?.cgContext { body(c, CGFloat(w), CGFloat(h)) }
        image.unlockFocus()
        return image
    }

    static func table(_ glow: NSColor) -> NSImage {
        draw(256, 160) { c, w, h in
            c.setFillColor(NSColor(rgb: (0.02, 0.05, 0.06)).cgColor); c.fill(CGRect(x: 0, y: 0, width: w, height: h))
            c.setFillColor(glow.withAlphaComponent(0.85).cgColor)
            for row in 0..<9 {
                for col in 0..<4 {
                    let len = CGFloat(18 + (row * 7 + col * 13) % 34)
                    c.fill(CGRect(x: 10 + CGFloat(col) * 62, y: h - 18 - CGFloat(row) * 16, width: len, height: 7))
                }
            }
        }
    }

    static func annunciator(_ repos: [(name: String, color: NSColor)]) -> NSImage {
        draw(1024, 300) { c, w, h in
            c.setFillColor(NSColor(rgb: (0.06, 0.06, 0.07)).cgColor); c.fill(CGRect(x: 0, y: 0, width: w, height: h))
            let rows = max(5, repos.count), rowH = h / CGFloat(rows)
            for r in 0..<rows {
                let y = h - rowH * CGFloat(r + 1)
                if r < repos.count {
                    let repo = repos[r]
                    c.setFillColor(repo.color.cgColor); c.fill(CGRect(x: 8, y: y + 6, width: 210, height: rowH - 12))
                    NSAttributedString(string: repo.name, attributes: [.font: NSFont.monospacedSystemFont(ofSize: 22, weight: .heavy), .foregroundColor: NSColor.black])
                        .draw(at: NSPoint(x: 16, y: y + (rowH - 26) / 2))
                }
                for k in 0..<6 {
                    c.setFillColor(NSColor(rgb: (0.16, 0.17, 0.19)).cgColor)
                    c.fill(CGRect(x: 240 + CGFloat(k) * 128, y: y + 8, width: 116, height: rowH - 16))
                }
            }
        }
    }

    static func flapBoard(_ title: String) -> NSImage {
        draw(768, 230) { c, w, h in
            c.setFillColor(NSColor(rgb: (0.05, 0.05, 0.06)).cgColor); c.fill(CGRect(x: 0, y: 0, width: w, height: h))
            NSAttributedString(string: title, attributes: [.font: NSFont.systemFont(ofSize: 28, weight: .bold), .foregroundColor: NSColor(rgb: (1, 0.85, 0.35))])
                .draw(at: NSPoint(x: 14, y: h - 40))
            for row in 0..<3 {
                let y = h - 84 - CGFloat(row) * 48
                for k in 0..<22 {
                    c.setFillColor(NSColor(rgb: (0.13, 0.13, 0.15)).cgColor)
                    c.fill(CGRect(x: 34 + CGFloat(k) * 33, y: y, width: 30, height: 34))
                }
            }
        }
    }

    static func nixieClock(_ text: String?) -> NSImage {
        draw(256, 256) { c, w, h in
            c.setFillColor(NSColor(rgb: (0.04, 0.03, 0.02)).cgColor); c.fillEllipse(in: CGRect(x: 0, y: 0, width: w, height: h))
            let s = NSAttributedString(string: text ?? "--:--", attributes: [.font: NSFont.monospacedSystemFont(ofSize: 44, weight: .bold), .foregroundColor: NSColor(rgb: (1, 0.55, 0.2))])
            let size = s.size()
            s.draw(at: NSPoint(x: (w - size.width) / 2, y: (h - size.height) / 2))
        }
    }
}
