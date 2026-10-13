import SceneKit

enum RocketShape {
    static let height = 2.42, radius = 0.2, base = 0.16
    static let finCount = 3, nosePower = 1.9, finSpan = 2.3
    static var length: Double { height - base }
    static func y(_ t: Double) -> Double { base + length * t }
    static var split: Double { y(0.4) }
    static var panelTop: Double { y(0.72) }
    static var hatchHeight: Double { y(0.52) }
    static var rcsHeight: Double { y(0.64) }

    static func r(_ y: Double) -> Double {
        let t = (y - base) / length
        if t <= 0 { return radius * 0.62 }
        if t < 0.22 { return radius * (0.62 + 0.38 * sin(.pi / 2 * t / 0.22)) }
        if t < 0.45 { return radius }
        return radius * max(0, 1 - pow(min(1, (t - 0.45) / 0.55), nosePower))
    }

    static func profile(from y0: Double, to y1: Double, steps: Int) -> [(y: Double, r: Double)] {
        (0...steps).map { i in
            let y = y0 + (y1 - y0) * Double(i) / Double(steps)
            return (y, r(y))
        }
    }

    static var finBearings: [Double] { (0..<finCount).map { .pi / 6 + Double($0) * 2 * .pi / Double(finCount) } }
    static let cameraBearing = Double.pi * 7 / 6
    static var rcsBearings: [Double] { finBearings.map { $0 + .pi / Double(finCount) } }
    static let nameFaces = [Double.pi / 3, .pi, 5 * .pi / 3]
    static var nameWidth: Double { radius * 0.7 }

    static var finRootHigh: Double { y(0.36) }
    static var finRootLow: Double { y(0.02) }
    static var finReach: Double { radius * finSpan }
    static let podLength = 0.34, podRadius = 0.036

    static func finOutline(scale s: Double) -> NSBezierPath {
        let p = NSBezierPath()
        p.move(to: NSPoint(x: r(finRootHigh) * 0.9 * s, y: finRootHigh * s))
        p.line(to: NSPoint(x: finReach * s, y: podLength * 0.8 * s))
        p.line(to: NSPoint(x: finReach * s, y: podLength * 0.15 * s))
        p.line(to: NSPoint(x: r(finRootLow) * 0.9 * s, y: finRootLow * s))
        p.close()
        return p
    }

    static let bellHeight = 0.1, bellRing = 0.55, bellTop = 0.018, bellBottom = 0.045

    static var legBearings: [Double] { finBearings }
    static let legLength = 0.3, legOut = 0.8, legTaper = 0.58, legGap = 0.07
    static var legTop: Double { r(split) * 0.84 }
    static let engineHeight = 0.16, engineTop = 0.07, engineBottom = 0.11

    static var standDepth: Double {
        let bottom = legTop * legTaper
        return [0.0, .pi / 3 - legGap].map { a in legLength * cos(legOut) - (bottom * cos(a) - legTop) * sin(legOut) }.max()!
    }

    static let station = 1.9 / 2.42

    static func legAngle(fold: Double) -> Double { legOut * (1 - min(1, max(0, fold))) }

    static func fold(_ tip: SCNNode, _ fold: Double) {
        let angle = CGFloat(legAngle(fold: fold))
        tip.enumerateHierarchy { n, _ in if isLeg(n) { n.eulerAngles.z = angle } }
    }

    private static func isLeg(_ n: SCNNode) -> Bool { (n.value(forKey: "part") as? String) == "leg" }

    static func showLegs(_ tip: SCNNode, _ shown: Bool) {
        tip.enumerateHierarchy { n, _ in if isLeg(n) { n.isHidden = !shown } }
    }

    static func legGeometry(scale s: Double, segments: Int) -> SCNGeometry {
        let half = .pi / 3 - legGap, top = legTop * s, l = legLength * s
        var verts: [SCNVector3] = [], normals: [SCNVector3] = [], idx: [Int32] = []
        func at(_ a: Double, _ d: Double) -> SIMD3<Double> {
            let rho = top * (1 - (1 - legTaper) * d / l)
            return SIMD3(rho * cos(a) - top, -d, rho * sin(a))
        }
        for k in 0..<segments {
            let a0 = -half + 2 * half * Double(k) / Double(segments), a1 = -half + 2 * half * Double(k + 1) / Double(segments)
            let q = [at(a0, 0), at(a1, 0), at(a1, l), at(a0, l)]
            var n = simd_normalize(simd_cross(q[1] - q[0], q[3] - q[0]))
            let mid = (a0 + a1) / 2
            if simd_dot(n, SIMD3(cos(mid), 0, sin(mid))) < 0 { n = -n }
            let i = Int32(verts.count)
            for p in q { verts.append(SCNVector3(p.x, p.y, p.z)); normals.append(SCNVector3(n.x, n.y, n.z)) }
            idx += [i, i + 1, i + 2, i, i + 2, i + 3]
        }
        return SCNGeometry(sources: [SCNGeometrySource(vertices: verts), SCNGeometrySource(normals: normals)],
                           elements: [SCNGeometryElement(indices: idx, primitiveType: .triangles)])
    }

    static func leg(at a: Double, scale s: Double, segments: Int, material: SCNMaterial) -> SCNNode {
        let pivot = SCNNode()
        pivot.eulerAngles.y = CGFloat(-a)
        let hinge = SCNNode(geometry: legGeometry(scale: s, segments: segments))
        hinge.name = "leg"
        hinge.setValue("leg", forKey: "part")
        hinge.geometry!.firstMaterial = material
        material.isDoubleSided = true
        hinge.position = SCNVector3(legTop * s, split * s + 0.002, 0)
        pivot.addChildNode(hinge)
        return pivot
    }

    static var nameLow: Double { y(0.1) }
    static var nameHigh: Double { y(0.7) }

    static func names(_ name: String, color: NSColor, scale s: Double, apothem: @escaping (Double) -> Double,
                      width: Double, flatShaded: Bool, faces: [Double] = nameFaces) -> (lifter: [SCNNode], tip: [SCNNode]) {
        let low = nameLow * s, high = nameHigh * s, seam = split * s, length = high - low
        let lifterShare = (seam - low) / length
        let image = Textures.draw(2400, max(1, Int(2400 * width / length))) { _, w, h in
            func letters(_ size: CGFloat) -> NSAttributedString {
                NSAttributedString(string: name, attributes: [.font: NSFont.systemFont(ofSize: size, weight: .black),
                                                              .foregroundColor: color, .kern: size * 0.12])
            }
            var size = h * 0.86
            let room = letters(size).size().width <= w * CGFloat(lifterShare) * 0.94 ? w * CGFloat(lifterShare) : w
            while letters(size).size().width > room * 0.96, size > 4 { size *= 0.94 }
            let text = letters(size)
            text.draw(at: NSPoint(x: (room - text.size().width) / 2, y: (h - text.size().height) / 2))
        }
        func piece(face: Double, from y0: Double, to y1: Double) -> SCNNode {
            let a0 = apothem(y0), a1 = apothem(y1), lean = atan((a0 - a1) / (y1 - y0))
            let plane = SCNPlane(width: (y1 - y0) / cos(lean) + 0.002, height: width)
            let m = SCNMaterial()
            m.lightingModel = flatShaded ? .lambert : .physicallyBased
            m.diffuse.contents = image
            m.diffuse.wrapS = .clamp
            let f0 = (y0 - low) / length, f1 = (y1 - low) / length
            m.diffuse.contentsTransform = SCNMatrix4Mult(SCNMatrix4MakeScale(CGFloat(f1 - f0), 1, 1), SCNMatrix4MakeTranslation(CGFloat(f0), 0, 0))
            m.transparencyMode = .aOne
            plane.firstMaterial = m
            let letters = SCNNode(geometry: plane)
            letters.eulerAngles.z = .pi / 2
            let tilt = SCNNode()
            tilt.eulerAngles.x = CGFloat(-lean)
            tilt.addChildNode(letters)
            let mount = SCNNode()
            let mid = (y0 + y1) / 2, at = SIMD2(cos(face), sin(face)) * (apothem(mid) + 0.002)
            mount.position = SCNVector3(at.x, mid, at.y)
            mount.eulerAngles.y = CGFloat(atan2(cos(face), sin(face)))
            mount.addChildNode(tilt)
            return mount
        }
        func band(face: Double, from y0: Double, to y1: Double, pieces: Int) -> SCNNode {
            let group = SCNNode()
            group.name = "name"
            group.setValue("name", forKey: "part")
            for k in 0..<pieces {
                let a = y0 + (y1 - y0) * Double(k) / Double(pieces), b = y0 + (y1 - y0) * Double(k + 1) / Double(pieces)
                group.addChildNode(piece(face: face, from: a, to: b))
            }
            return group
        }
        return (faces.map { band(face: $0, from: low, to: seam - 0.004, pieces: 6) }, faces.map { band(face: $0, from: seam + 0.004, to: high, pieces: 6) })
    }

    static func hatch(scale s: Double, surface: (Double) -> Double, flatShaded: Bool) -> SCNNode {
        let y = hatchHeight * s, w = radius * 0.75 * s, h = radius * 1.05 * s
        let image = Textures.draw(300, Int(300 * h / w)) { ctx, pw, ph in
            let line = pw * 0.045
            let frame = CGRect(x: line, y: line, width: pw - 2 * line, height: ph - 2 * line)
            ctx.setStrokeColor(NSColor(white: 0.18, alpha: 0.9).cgColor)
            ctx.setLineWidth(line)
            ctx.addPath(CGPath(roundedRect: frame, cornerWidth: pw * 0.18, cornerHeight: pw * 0.18, transform: nil))
            ctx.strokePath()
            ctx.setFillColor(NSColor(white: 0.18, alpha: 0.9).cgColor)
            ctx.fill(CGRect(x: pw * 0.68, y: ph * 0.46, width: pw * 0.14, height: ph * 0.08))
        }
        let plane = SCNPlane(width: w, height: h)
        let m = SCNMaterial()
        m.lightingModel = flatShaded ? .lambert : .physicallyBased
        m.diffuse.contents = image
        m.transparencyMode = .aOne
        plane.firstMaterial = m
        let lean = atan((surface(y - 0.02 * s) - surface(y + 0.02 * s)) / (0.04 * s))
        let door = SCNNode(geometry: plane)
        door.eulerAngles.x = CGFloat(-lean)
        let mount = SCNNode()
        mount.position = SCNVector3(surface(y) + 0.0015, y, 0)
        mount.eulerAngles.y = .pi / 2
        mount.addChildNode(door)
        mount.name = "hatch"
        mount.setValue("hatch", forKey: "part")
        return mount
    }

    static let hotfixRed = NSColor(rgb: (0.86, 0.16, 0.12))

    static func thruster(at a: Double, scale s: Double, surface: (Double) -> Double, hull: SCNMaterial, nozzle: SCNMaterial) -> SCNNode {
        let pivot = SCNNode()
        pivot.name = "rcs"
        pivot.setValue("rcs", forKey: "part")
        pivot.eulerAngles.y = CGFloat(-a)
        let y = rcsHeight * s, out = surface(y), w = radius * 0.55 * s, h = 0.05 * s, d = 0.035 * s
        let box = SCNNode(geometry: SCNBox(width: d, height: h, length: w, chamferRadius: 0))
        box.geometry!.firstMaterial = hull
        let front = out + d * 0.2
        box.position = SCNVector3(front - d / 2, y, 0)
        pivot.addChildNode(box)
        let face = SCNNode(geometry: SCNBox(width: 0.003 * s, height: h * 0.6, length: w * 0.7, chamferRadius: 0))
        face.geometry!.firstMaterial = nozzle
        face.position = SCNVector3(front + 0.0012 * s, y, 0)
        pivot.addChildNode(face)
        pivot.setValue(SIMD3(front, y, 0), forKey: "nozzle")
        pivot.setValue(abs(remainder(a - cameraBearing, 2 * .pi)) < 0.1, forKey: "facesCamera")
        return pivot
    }
}
