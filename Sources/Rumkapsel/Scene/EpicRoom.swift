import AppKit
import SceneKit

enum EpicRoom {
    static var size: SIMD2<Double> { FixtureKind.planningConsole.size }
    static let board = (width: 0.84, depth: 0.5, tilt: 0.42, height: 0.33)
    static let steel = NSColor(rgb: (0.58, 0.6, 0.6)), chrome = NSColor(rgb: (0.8, 0.82, 0.84)), enamel = NSColor(rgb: (0.24, 0.3, 0.29))

    static func console(color: NSColor) -> SCNNode {
        let n = SCNNode()
        let b = board
        for side in [-1.0, 1.0] {
            let leg = MissionRoom.box(0.05, b.height - 0.02, 0.07, lit(enamel), at: v3(side * (b.width / 2 - 0.08), (b.height - 0.02) / 2, 0.02), chamfer: 0.012)
            n.addChildNode(leg)
            let foot = MissionRoom.box(0.08, 0.03, size.y, lit(enamel.darker(0.2)), at: v3(side * (b.width / 2 - 0.08), 0.015, 0), chamfer: 0.012)
            n.addChildNode(foot)
            let fin = SCNNode(geometry: fin(height: 0.14, length: size.y * 0.8))
            fin.geometry!.firstMaterial = lit(color)
            fin.position = v3(side * (b.width / 2 - 0.08), 0.03, 0)
            n.addChildNode(fin)
        }
        n.addChildNode(MissionRoom.box(b.width - 0.16, 0.04, 0.04, lit(chrome), at: v3(0, 0.1, 0.02), chamfer: 0.01))
        let drawers = MissionRoom.box(b.width * 0.42, 0.14, size.y * 0.6, lit(steel), at: v3(b.width * 0.18, b.height - 0.11, -0.03), chamfer: 0.012)
        n.addChildNode(drawers)
        for k in 0..<2 {
            n.addChildNode(MissionRoom.box(b.width * 0.16, 0.012, 0.01, lit(chrome), at: v3(b.width * 0.18, b.height - 0.08 - Double(k) * 0.06, size.y * 0.27)))
        }

        let top = SCNNode()
        top.position = v3(0, b.height, 0)
        top.eulerAngles.x = CGFloat(b.tilt)
        n.addChildNode(top)
        top.addChildNode(MissionRoom.box(b.width, 0.03, b.depth, lit(steel), at: v3(0, 0, 0), chamfer: 0.008))
        let sheet = SCNNode(geometry: SCNPlane(width: b.width - 0.06, height: b.depth - 0.06))
        let m = SCNMaterial()
        m.diffuse.contents = blueprint
        m.emission.contents = blueprint
        m.emission.intensity = 0.9
        m.lightingModel = .constant
        sheet.geometry!.firstMaterial = m
        sheet.eulerAngles.x = -.pi / 2
        sheet.position = v3(0, 0.016, 0)
        top.addChildNode(sheet)
        for z in [-1.0, 1.0] {
            top.addChildNode(MissionRoom.box(b.width + 0.01, 0.02, 0.018, lit(chrome), at: v3(0, 0.012, z * b.depth / 2), chamfer: 0.006))
        }
        let rule = MissionRoom.box(b.width - 0.02, 0.012, 0.03, lit(chrome), at: v3(0, 0.03, b.depth * 0.12), chamfer: 0.004)
        top.addChildNode(rule)
        let lamps = [NSColor(rgb: (0.95, 0.72, 0.3)), NSColor(rgb: (0.4, 0.85, 0.55)), NSColor(rgb: (0.95, 0.72, 0.3)), color]
        for (k, c) in lamps.enumerated() {
            let lamp = SCNNode(geometry: faceted(SCNCylinder(radius: 0.012, height: 0.012)))
            lamp.geometry!.firstMaterial = flat(c)
            lamp.position = v3(-b.width / 2 + 0.06 + Double(k) * 0.04, 0.02, -b.depth / 2 + 0.03)
            top.addChildNode(lamp)
        }
        n.addChildNode(arm(color: color, height: b.height))
        return n
    }

    private static func arm(color: NSColor, height: Double) -> SCNNode {
        let n = SCNNode()
        n.position = v3(board.width / 2 - 0.04, height + 0.02, -board.depth / 2 * cos(board.tilt) + 0.02)
        let post = MissionRoom.box(0.02, 0.26, 0.02, lit(chrome), at: v3(0, 0.13, 0))
        n.addChildNode(post)
        let reach = MissionRoom.box(0.018, 0.018, 0.24, lit(chrome), at: v3(-0.06, 0.26, 0.09))
        reach.eulerAngles.y = 0.45
        n.addChildNode(reach)
        let shade = SCNNode(geometry: faceted(SCNCone(topRadius: 0.012, bottomRadius: 0.045, height: 0.05)))
        shade.geometry!.firstMaterial = lit(color)
        shade.position = v3(-0.11, 0.24, 0.19)
        n.addChildNode(shade)
        let bulb = SCNNode(geometry: faceted(SCNCylinder(radius: 0.036, height: 0.004)))
        bulb.geometry!.firstMaterial = flat(NSColor(rgb: (0.95, 0.88, 0.7)))
        bulb.position = v3(-0.11, 0.214, 0.19)
        n.addChildNode(bulb)
        return n
    }

    private static func fin(height: Double, length: Double) -> SCNGeometry {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: -length / 2, y: 0))
        path.line(to: NSPoint(x: length / 2, y: 0))
        path.line(to: NSPoint(x: length * 0.15, y: height))
        path.line(to: NSPoint(x: -length * 0.3, y: height * 0.35))
        path.close()
        let shape = SCNShape(path: path, extrusionDepth: 0.012)
        let holder = SCNNode(geometry: shape)
        holder.eulerAngles.y = .pi / 2
        let flatten = SCNNode()
        flatten.addChildNode(holder)
        return flatten.flattenedClone().geometry ?? shape
    }

    static let blueprint: NSImage = {
        let w = 840, h = 500
        let image = NSImage(size: NSSize(width: w, height: h))
        image.lockFocus()
        NSColor(rgb: (0.08, 0.26, 0.55)).setFill()
        NSRect(x: 0, y: 0, width: w, height: h).fill()
        NSColor(rgb: (0.35, 0.6, 0.95)).withAlphaComponent(0.45).setStroke()
        for x in stride(from: 0, through: w, by: 28) { let p = NSBezierPath(); p.move(to: NSPoint(x: x, y: 0)); p.line(to: NSPoint(x: x, y: h)); p.lineWidth = 1; p.stroke() }
        for y in stride(from: 0, through: h, by: 28) { let p = NSBezierPath(); p.move(to: NSPoint(x: 0, y: y)); p.line(to: NSPoint(x: w, y: y)); p.lineWidth = 1; p.stroke() }
        let ink = NSColor(rgb: (0.9, 0.95, 1.0))
        ink.setStroke()
        func hex(_ c: NSPoint, _ r: Double) {
            let p = NSBezierPath()
            for k in 0...6 {
                let a = Double(k) * .pi / 3 + .pi / 6
                let q = NSPoint(x: c.x + r * cos(a), y: c.y + r * sin(a))
                k == 0 ? p.move(to: q) : p.line(to: q)
            }
            p.lineWidth = 3
            p.stroke()
        }
        let cells = [(0, 0), (1, 0), (0, 1), (-1, 1), (2, -1), (1, 1)]
        let r = 52.0
        for (q, s) in cells {
            let c = NSPoint(x: 330 + r * sqrt(3) * (Double(q) + Double(s) / 2), y: 230 + r * 1.5 * Double(s))
            hex(c, r - 4)
        }
        let done = NSBezierPath()
        for (q, s) in cells.prefix(3) {
            let c = NSPoint(x: 330 + r * sqrt(3) * (Double(q) + Double(s) / 2), y: 230 + r * 1.5 * Double(s))
            done.appendRect(NSRect(x: c.x - 14, y: c.y - 14, width: 28, height: 28))
        }
        ink.setFill()
        done.fill()
        let dim = NSBezierPath()
        dim.move(to: NSPoint(x: 60, y: 60)); dim.line(to: NSPoint(x: 780, y: 60))
        dim.move(to: NSPoint(x: 60, y: 50)); dim.line(to: NSPoint(x: 60, y: 70))
        dim.move(to: NSPoint(x: 780, y: 50)); dim.line(to: NSPoint(x: 780, y: 70))
        dim.move(to: NSPoint(x: 690, y: 110)); dim.line(to: NSPoint(x: 790, y: 110)); dim.line(to: NSPoint(x: 790, y: 440)); dim.line(to: NSPoint(x: 690, y: 440)); dim.close()
        dim.lineWidth = 2
        dim.stroke()
        for k in 0..<5 {
            let line = NSBezierPath()
            line.move(to: NSPoint(x: 705, y: 400 - k * 34)); line.line(to: NSPoint(x: 705 + (k % 2 == 0 ? 70 : 50), y: 400 - k * 34))
            line.lineWidth = 3
            line.stroke()
        }
        image.unlockFocus()
        return image
    }()

    static let poleHigh = 0.8

    static func pennant(color: NSColor) -> SCNNode {
        let n = SCNNode()
        let base = SCNNode(geometry: faceted(SCNCylinder(radius: 0.07, height: 0.025)))
        base.geometry!.firstMaterial = lit(enamel)
        base.position = v3(0, 0.0125, 0)
        n.addChildNode(base)
        let pole = SCNNode(geometry: faceted(SCNCylinder(radius: 0.008, height: poleHigh)))
        pole.geometry!.firstMaterial = lit(chrome)
        pole.position = v3(0, poleHigh / 2, 0)
        n.addChildNode(pole)
        let finial = SCNNode(geometry: faceted(SCNSphere(radius: 0.016)))
        finial.geometry!.firstMaterial = lit(chrome)
        finial.position = v3(0, poleHigh + 0.012, 0)
        n.addChildNode(finial)
        func flag(_ points: [(Double, Double)], _ material: SCNMaterial, depth: Double) -> SCNNode {
            let path = NSBezierPath()
            path.move(to: NSPoint(x: points[0].0, y: points[0].1))
            for p in points.dropFirst() { path.line(to: NSPoint(x: p.0, y: p.1)) }
            path.close()
            let shape = SCNNode(geometry: SCNShape(path: path, extrusionDepth: depth))
            shape.geometry!.firstMaterial = material
            shape.geometry!.firstMaterial!.isDoubleSided = true
            return shape
        }
        let top = poleHigh - 0.02
        n.addChildNode(flag([(0.008, top), (0.3, top - 0.065), (0.008, top - 0.13)], lit(color), depth: 0.004))
        for side in [-1.0, 1.0] {
            let stripe = flag([(0.03, top - 0.05), (0.17, top - 0.062), (0.03, top - 0.08)], lit(NSColor(rgb: (0.95, 0.94, 0.88))), depth: 0.001)
            stripe.position = v3(0, 0, side * 0.0028)
            n.addChildNode(stripe)
        }
        return n
    }

    static func tallyBoard(_ marks: Int, color: NSColor) -> SCNNode {
        let n = SCNNode()
        let b = board, back = -size.y / 2 + 0.035, low = b.height + sin(b.tilt) * b.depth / 2 - 0.02, at = low + 0.2
        for x in [-1.0, 1.0] {
            n.addChildNode(MissionRoom.box(0.016, at - low, 0.016, lit(chrome), at: v3(x * (tallyWide / 2 - 0.04), (low + at) / 2 - tallyHigh / 4, back)))
        }
        let plate = tally(marks, color: color)
        plate.position = v3(0, at, back + 0.01)
        n.addChildNode(plate)
        n.position = v3(-b.width / 2 + tallyWide / 2 + 0.04, 0, 0)
        return n
    }

    static let tallyWide = 0.34, tallyHigh = 0.12

    static func tally(_ marks: Int, color: NSColor) -> SCNNode {
        let n = SCNNode()
        n.addChildNode(MissionRoom.box(tallyWide, tallyHigh, 0.014, lit(enamel), at: v3(0, 0, 0), chamfer: 0.006))
        n.addChildNode(MissionRoom.box(tallyWide - 0.03, tallyHigh - 0.03, 0.004, flat(NSColor(rgb: (0.06, 0.07, 0.08))), at: v3(0, 0, 0.008)))
        for x in [-1.0, 1.0] {
            for y in [-1.0, 1.0] {
                let rivet = SCNNode(geometry: faceted(SCNCylinder(radius: 0.005, height: 0.006)))
                rivet.geometry!.firstMaterial = lit(chrome)
                rivet.eulerAngles.x = .pi / 2
                rivet.position = v3(x * (tallyWide / 2 - 0.008), y * (tallyHigh / 2 - 0.008), 0.009)
                n.addChildNode(rivet)
            }
        }
        let glow = flat(color.blended(withFraction: 0.35, of: .white) ?? color)
        let bar = 0.05, gap = 0.016, group = 4 * gap + 0.022
        for k in 0..<min(marks, 15) {
            let g = Double(k / 5), i = k % 5
            let x0 = -tallyWide / 2 + 0.03 + g * group
            if i < 4 {
                n.addChildNode(MissionRoom.box(0.006, bar, 0.004, glow, at: v3(x0 + Double(i) * gap, 0, 0.012)))
            } else {
                let strike = MissionRoom.box(0.006, 4 * gap + 0.012, 0.004, glow, at: v3(x0 + 1.5 * gap, 0, 0.013))
                strike.eulerAngles.z = -1.1
                n.addChildNode(strike)
            }
        }
        return n
    }
}
