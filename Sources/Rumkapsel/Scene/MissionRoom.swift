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

    static func lampColor(_ l: MissionBoards.Lamp) -> NSColor {
        switch l {
        case .dark: return NSColor(rgb: (0.16, 0.17, 0.19))
        case .green: return NSColor(rgb: (0.3, 0.85, 0.45))
        case .amber: return NSColor(rgb: (1, 0.72, 0.2))
        case .red: return NSColor(rgb: (1, 0.25, 0.22))
        }
    }

    static func annunciator(_ rows: [MissionBoards.Row]) -> NSImage {
        draw(1024, 300) { c, w, h in
            c.setFillColor(NSColor(rgb: (0.06, 0.06, 0.07)).cgColor); c.fill(CGRect(x: 0, y: 0, width: w, height: h))
            let head: CGFloat = 34
            for (k, name) in MissionBoards.lamps.enumerated() {
                let s = NSAttributedString(string: name, attributes: [.font: NSFont.systemFont(ofSize: 20, weight: .semibold), .foregroundColor: NSColor(rgb: (0.7, 0.72, 0.75))])
                s.draw(at: NSPoint(x: 240 + CGFloat(k) * 128 + (116 - s.size().width) / 2, y: h - head + 6))
            }
            let count = max(5, rows.count), rowH = (h - head) / CGFloat(count)
            for r in 0..<count {
                let y = h - head - rowH * CGFloat(r + 1)
                if r < rows.count {
                    let row = rows[r]
                    c.setFillColor(NSColor(row.color).cgColor); c.fill(CGRect(x: 8, y: y + 4, width: 210, height: rowH - 8))
                    var size: CGFloat = min(24, rowH - 12)
                    var name = NSAttributedString(string: row.repo, attributes: [.font: NSFont.systemFont(ofSize: size, weight: .heavy), .foregroundColor: NSColor.black])
                    while name.size().width > 196 && size > 10 {
                        size -= 1
                        name = NSAttributedString(string: row.repo, attributes: [.font: NSFont.systemFont(ofSize: size, weight: .heavy), .foregroundColor: NSColor.black])
                    }
                    name.draw(at: NSPoint(x: 16, y: y + (rowH - name.size().height) / 2))
                }
                for k in 0..<MissionBoards.lamps.count {
                    let lamp = r < rows.count ? rows[r].lamps[k] : .dark
                    c.setFillColor(lampColor(lamp).cgColor)
                    c.fill(CGRect(x: 240 + CGFloat(k) * 128, y: y + 4, width: 116, height: rowH - 8))
                }
            }
        }
    }

    static func crt(_ frame: NSImage, caption: String) -> NSImage {
        draw(320, 200) { c, w, h in
            frame.draw(in: NSRect(x: 0, y: 0, width: w, height: h), from: .zero, operation: .copy, fraction: 1)
            c.setFillColor(NSColor(rgb: (0.35, 0.85, 0.95)).withAlphaComponent(0.22).cgColor)
            c.setBlendMode(.color); c.fill(CGRect(x: 0, y: 0, width: w, height: h)); c.setBlendMode(.normal)
            c.setFillColor(NSColor.black.withAlphaComponent(0.28).cgColor)
            for y in stride(from: CGFloat(0), to: h, by: 3) { c.fill(CGRect(x: 0, y: y, width: w, height: 1)) }
            let glow = CGGradient(colorsSpace: nil, colors: [NSColor.clear.cgColor, NSColor.black.withAlphaComponent(0.55).cgColor] as CFArray, locations: [0.55, 1])!
            c.drawRadialGradient(glow, startCenter: CGPoint(x: w / 2, y: h / 2), startRadius: 0, endCenter: CGPoint(x: w / 2, y: h / 2), endRadius: w * 0.62, options: [])
            NSAttributedString(string: caption, attributes: [.font: NSFont.monospacedSystemFont(ofSize: 15, weight: .bold), .foregroundColor: NSColor(rgb: (0.85, 1, 0.95))])
                .draw(at: NSPoint(x: 12, y: h - 26))
        }
    }

    static func noSignal(_ caption: String) -> NSImage {
        draw(480, 300) { c, w, h in
            c.setFillColor(NSColor(rgb: (0.03, 0.05, 0.06)).cgColor); c.fill(CGRect(x: 0, y: 0, width: w, height: h))
            c.setFillColor(NSColor.black.withAlphaComponent(0.4).cgColor)
            for y in stride(from: CGFloat(0), to: h, by: 3) { c.fill(CGRect(x: 0, y: y, width: w, height: 1)) }
            NSAttributedString(string: caption, attributes: [.font: NSFont.monospacedSystemFont(ofSize: 20, weight: .bold), .foregroundColor: NSColor(rgb: (0.5, 0.62, 0.62))])
                .draw(at: NSPoint(x: 18, y: h - 38))
            let s = NSAttributedString(string: "No signal", attributes: [.font: NSFont.monospacedSystemFont(ofSize: 34, weight: .bold), .foregroundColor: NSColor(rgb: (0.4, 0.5, 0.5))])
            s.draw(at: NSPoint(x: (w - s.size().width) / 2, y: (h - s.size().height) / 2 - 10))
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
