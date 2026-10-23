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

    static let hexTurn = Double.pi / 6

    static func bridge(radius r: Double) -> SCNNode {
        let deck = SCNNode(geometry: faceted(SCNCylinder(radius: r, height: 0.035)))
        deck.geometry!.firstMaterial = lit(Palette.ops.console)
        deck.position = v3(0, -0.0175, 0)
        let edge = SCNNode(geometry: faceted(SCNTube(innerRadius: r - 0.025, outerRadius: r + 0.004, height: 0.008)))
        edge.geometry!.firstMaterial = flat(NSColor(rgb: (0.45, 0.95, 1.0)))
        edge.position = v3(0, 0.002, 0)
        let glow = SCNNode(geometry: faceted(SCNCylinder(radius: r * 0.7, height: 0.004)))
        glow.geometry!.firstMaterial = holo(NSColor(rgb: (0.4, 0.9, 1.0)), 0.55)
        glow.position = v3(0, -0.038, 0)
        let n = SCNNode()
        for c in [deck, edge, glow] { n.addChildNode(c) }
        return n
    }

    static func hologram() -> SCNNode {
        let n = SCNNode()
        let sun = SCNNode(geometry: SCNSphere(radius: 0.045))
        sun.geometry!.firstMaterial = holo(NSColor(rgb: (1.0, 0.92, 0.7)), 1)
        let halo = SCNNode(geometry: SCNSphere(radius: 0.075))
        halo.geometry!.firstMaterial = holo(NSColor(rgb: (1.0, 0.8, 0.45)), 0.25)
        sun.addChildNode(halo)
        sun.position = v3(0, HoloView.centre, 0)
        n.addChildNode(sun)
        n.addChildNode(grain())
        return n
    }

    static func grain(count: Int = 300, radius: Double = 0.5, height: Double = 0.36) -> SCNNode {
        var rng = SystemRandomNumberGenerator()
        var verts: [SCNVector3] = [], keys: [CGPoint] = []
        let apothem = radius * cos(.pi / 6)
        while verts.count < count {
            let x = Double.random(in: -radius...radius, using: &rng), z = Double.random(in: -radius...radius, using: &rng)
            let inside = (0..<3).allSatisfy { k in
                let a = Double(k) * .pi / 3
                return abs(x * sin(a) + z * cos(a)) <= apothem
            }
            guard inside else { continue }
            verts.append(SCNVector3(x, 0, z))
            keys.append(CGPoint(x: Double.random(in: 0..<1, using: &rng), y: 1 / Double.random(in: 12...24, using: &rng)))
        }
        let element = SCNGeometryElement(indices: (0..<Int32(count)).map { $0 }, primitiveType: .point)
        element.pointSize = 0.004
        element.minimumPointScreenSpaceRadius = 0.5
        element.maximumPointScreenSpaceRadius = 16
        let g = SCNGeometry(sources: [SCNGeometrySource(vertices: verts), SCNGeometrySource(textureCoordinates: keys)], elements: [element])
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = NSColor(rgb: (0.55, 0.95, 1.0))
        m.blendMode = .add
        m.writesToDepthBuffer = false
        m.shaderModifiers = [
            .geometry: """
                #pragma varyings
                float fade;
                #pragma body
                float2 k = _geometry.texcoords[0];
                float t = fract(scn_frame.time * k.y + k.x);
                float a = scn_frame.time * 0.025 + t * 0.4;
                float3 p = _geometry.position.xyz;
                _geometry.position.xyz = float3(p.x * cos(a) - p.z * sin(a), t * \(height), p.x * sin(a) + p.z * cos(a));
                out.fade = sin(t * 3.14159) * (0.6 + 0.4 * sin(scn_frame.time * (0.3 + k.x * 0.6) + k.x * 40.0));
                """,
            .fragment: """
                #pragma body
                _output.color = float4(_output.color.rgb * in.fade * 0.6, in.fade * 0.7);
                """]
        g.firstMaterial = m
        let n = SCNNode(geometry: g)
        n.name = "grain"
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

    static func annunciator(_ rows: [MissionBoards.Row], blinking: Bool = false) -> NSImage {
        draw(1024, 300) { c, w, h in
            if !blinking { c.setFillColor(NSColor(rgb: (0.06, 0.06, 0.07)).cgColor); c.fill(CGRect(x: 0, y: 0, width: w, height: h)) }
            let head: CGFloat = 34
            for (k, name) in MissionBoards.lamps.enumerated() where !blinking {
                let s = NSAttributedString(string: name, attributes: [.font: NSFont.systemFont(ofSize: 20, weight: .semibold), .foregroundColor: NSColor(rgb: (0.7, 0.72, 0.75))])
                s.draw(at: NSPoint(x: 240 + CGFloat(k) * 128 + (116 - s.size().width) / 2, y: h - head + 6))
            }
            let count = max(5, rows.count), rowH = (h - head) / CGFloat(count)
            for r in 0..<count {
                let y = h - head - rowH * CGFloat(r + 1)
                if r < rows.count, !blinking {
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
                    let blinks = r < rows.count && (rows[r].blink.indices.contains(k) ? rows[r].blink[k] : 0) > 0
                    if blinking != blinks && blinking { continue }
                    let lamp = r < rows.count && !(blinks && !blinking) ? rows[r].lamps[k] : .dark
                    c.setFillColor(lampColor(lamp).cgColor)
                    c.fill(CGRect(x: 240 + CGFloat(k) * 128, y: y + 4, width: 116, height: rowH - 8))
                }
            }
        }
    }

    static func crt(_ frame: NSImage, caption: String) -> NSImage {
        draw(480, 300) { c, w, h in
            frame.draw(in: NSRect(x: 0, y: 0, width: w, height: h), from: .zero, operation: .copy, fraction: 1)
            c.setFillColor(NSColor(rgb: (0.35, 0.85, 0.95)).withAlphaComponent(0.07).cgColor)
            c.setBlendMode(.color); c.fill(CGRect(x: 0, y: 0, width: w, height: h)); c.setBlendMode(.normal)
            c.setFillColor(NSColor.black.withAlphaComponent(0.12).cgColor)
            for y in stride(from: CGFloat(0), to: h, by: 3) { c.fill(CGRect(x: 0, y: y, width: w, height: 1)) }
            let glow = CGGradient(colorsSpace: nil, colors: [NSColor.clear.cgColor, NSColor.black.withAlphaComponent(0.3).cgColor] as CFArray, locations: [0.7, 1])!
            c.drawRadialGradient(glow, startCenter: CGPoint(x: w / 2, y: h / 2), startRadius: 0, endCenter: CGPoint(x: w / 2, y: h / 2), endRadius: w * 0.62, options: [])
            NSAttributedString(string: caption, attributes: [.font: NSFont.monospacedSystemFont(ofSize: 21, weight: .bold), .foregroundColor: NSColor(rgb: (0.85, 1, 0.95))])
                .draw(at: NSPoint(x: 16, y: h - 36))
        }
    }

    static func errors(_ rows: [MissionBoards.ErrorRow]) -> NSImage {
        draw(480, 300) { c, w, h in
            c.setFillColor(NSColor(rgb: (0.03, 0.05, 0.06)).cgColor); c.fill(CGRect(x: 0, y: 0, width: w, height: h))
            NSAttributedString(string: "Errors", attributes: [.font: NSFont.monospacedSystemFont(ofSize: 20, weight: .bold), .foregroundColor: NSColor(rgb: (0.5, 0.62, 0.62))])
                .draw(at: NSPoint(x: 18, y: h - 38))
            let rowH = min(110, (h - 56) / CGFloat(max(1, rows.count)))
            for (k, row) in rows.enumerated() {
                let y = h - 56 - rowH * CGFloat(k + 1)
                c.setFillColor(NSColor(row.color).cgColor); c.fill(CGRect(x: 18, y: y + 8, width: 10, height: rowH - 16))
                let peak = CGFloat(max(1, row.hourly.max() ?? 1))
                let ink = lampColor(row.level == .spiking ? .red : row.level == .rising ? .amber : .green)
                for (i, v) in row.hourly.enumerated() {
                    let bh = max(2, CGFloat(v) / peak * (rowH - 18))
                    let recent = i >= row.hourly.count - 2
                    c.setFillColor((recent ? ink : NSColor(rgb: (0.35, 0.45, 0.45))).cgColor)
                    c.fill(CGRect(x: 40 + CGFloat(i) * 8, y: y + 9, width: 5, height: bh))
                }
                let word = NSAttributedString(string: row.level.words, attributes: [.font: NSFont.monospacedSystemFont(ofSize: min(40, rowH * 0.38), weight: .heavy), .foregroundColor: ink])
                word.draw(at: NSPoint(x: w - 18 - word.size().width, y: y + rowH * 0.42))
                let rate = NSAttributedString(string: "\(row.lastHour)/h", attributes: [.font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular), .foregroundColor: NSColor(rgb: (0.55, 0.62, 0.62))])
                rate.draw(at: NSPoint(x: w - 18 - rate.size().width, y: y + 8))
            }
            c.setFillColor(NSColor.black.withAlphaComponent(0.3).cgColor)
            for y in stride(from: CGFloat(0), to: h, by: 3) { c.fill(CGRect(x: 0, y: y, width: w, height: 1)) }
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
