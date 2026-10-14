import AppKit
import SceneKit

enum Props {
    static func foot(size: Double) -> SCNNode {
        let f = SCNNode(geometry: SCNPlane(width: size, height: size))
        f.geometry!.firstMaterial = flat(NSColor(rgb: (0.05, 0.05, 0.08)))
        f.opacity = 0.28
        f.eulerAngles.x = -.pi / 2
        f.position = v3(size * 0.06, 0.004, size * 0.06)
        return f
    }

    static func pyramid(color: NSColor, size: Double, floor: NSColor) -> SCNNode {
        let geo = SCNPyramid(width: size, height: size * 0.9, length: size)
        geo.materials = [flat(color.darker(0.2)), flat(color.lighter(0.12)), flat(color.darker(0.08)), flat(color.darker(0.2)), flat(color.darker(0.14))]
        let n = SCNNode()
        let body = SCNNode(geometry: geo)
        body.position = v3(0, 0, 0)
        n.addChildNode(body)
        n.addChildNode(foot(size: size * 1.15))
        return n
    }

    static func package(color: NSColor, band: NSColor, size: Double, blink: Bool = false, mine: Bool = false, number: Int? = nil,
                        title: String? = nil, who: String? = nil) -> SCNNode {
        let n = SCNNode()
        let h = size * 0.8
        let box = SCNBox(width: size, height: h, length: size, chamferRadius: 0)
        box.materials = [flat(color), flat(color.darker(0.13)), flat(color), flat(color.darker(0.13)), flat(color.lighter(0.14)), flat(color)]
        for m in box.materials { Detail.apply(Detail.crate(for: number), to: m) }
        let body = SCNNode(geometry: box)
        body.position = v3(0, h / 2, 0)
        n.addChildNode(body)
        let strapColor = mine ? Palette.mine : color.darker(0.3)
        let strap = SCNBox(width: size * 1.02, height: h * 0.16, length: size * 1.02, chamferRadius: 0)
        strap.materials = mine
            ? [flat(strapColor), flat(strapColor.darker(0.12)), flat(strapColor), flat(strapColor.darker(0.12)), flat(strapColor.lighter(0.1)), flat(strapColor)]
            : [flat(color.darker(0.3)), flat(color.darker(0.38)), flat(color.darker(0.3)), flat(color.darker(0.38)), flat(color.darker(0.22)), flat(color.darker(0.3))]
        let s = SCNNode(geometry: strap)
        s.position = v3(0, h / 2, 0)
        n.addChildNode(s)
        let plate = SCNNode(geometry: SCNBox(width: size * 0.3, height: h * 0.28, length: 0.012, chamferRadius: 0))
        plate.geometry!.name = Props.plateName
        plate.geometry!.firstMaterial = flat(band)
        plate.position = v3(size * 0.2, h * 0.36, size / 2 + 0.006)
        if blink { plate.runAction(Props.blinking()) }
        n.addChildNode(plate)
        if let number { n.addChildNode(crateNumber(number, size: size, height: h)) }
        if let title, !title.isEmpty { n.addChildNode(crateTag(title: title, who: who, size: size, height: h)) }
        n.addChildNode(foot(size: size * 1.3))
        return n
    }

    static func crateNumber(_ number: Int, size: Double, height h: Double) -> SCNNode {
        let plane = SCNPlane(width: size * 0.36, height: h * 0.16)
        plane.firstMaterial = numberStencil(number)
        plane.levelsOfDetail = [SCNLevelOfDetail(geometry: nil, worldSpaceDistance: 3.5)]
        let n = SCNNode(geometry: plane)
        n.position = v3(-size * 0.16, h * 0.36, size / 2 + 0.002)
        return n
    }

    static func crateTag(title: String, who: String?, size: Double, height h: Double) -> SCNNode {
        let plane = SCNPlane(width: size * 0.62, height: h * 0.26)
        plane.firstMaterial = tagFace(title: title, who: who)
        plane.levelsOfDetail = [SCNLevelOfDetail(geometry: nil, worldSpaceDistance: 3.5)]
        let n = SCNNode(geometry: plane)
        n.position = v3(0, h * 0.76, size / 2 + 0.002)
        return n
    }

    private static var tags: [String: SCNMaterial] = [:]
    private static func tagFace(title: String, who: String?) -> SCNMaterial {
        let key = title + "|" + (who ?? "")
        if let m = tags[key] { return m }
        let image = Textures.draw(448, 160) { ctx, w, h in
            let card = NSBezierPath(roundedRect: NSRect(x: 2, y: 2, width: w - 4, height: h - 4), xRadius: 10, yRadius: 10)
            NSColor(rgb: (0.1, 0.11, 0.13), alpha: 0.88).setFill(); card.fill()
            NSColor(white: 1, alpha: 0.12).setStroke(); card.lineWidth = 2; card.stroke()
            let titleFont = NSFont.systemFont(ofSize: h * 0.2, weight: .semibold)
            let style = NSMutableParagraphStyle(); style.lineBreakMode = .byTruncatingTail
            var lines = [""]
            for word in title.split(separator: " ").map(String.init) {
                if lines[lines.count - 1].isEmpty { lines[lines.count - 1] = word }
                else if lines[lines.count - 1].count + 1 + word.count <= 28 { lines[lines.count - 1] += " " + word }
                else if lines.count < 2 { lines.append(word) }
                else { lines[1] = Work.shorten(lines[1] + " " + word, to: 26) + "…"; break }
            }
            for (k, line) in lines.enumerated() {
                NSAttributedString(string: line, attributes: [.font: titleFont, .foregroundColor: NSColor(white: 0.94, alpha: 1), .paragraphStyle: style])
                    .draw(in: NSRect(x: w * 0.06, y: h * (0.12 + Double(k) * 0.24), width: w * 0.88, height: h * 0.3))
            }
            if let who {
                NSAttributedString(string: who, attributes: [.font: NSFont.systemFont(ofSize: h * 0.16, weight: .regular),
                                                             .foregroundColor: NSColor(white: 0.7, alpha: 1)])
                    .draw(in: NSRect(x: w * 0.06, y: h * 0.66, width: w * 0.88, height: h * 0.22))
            }
        }
        let m = flat(.white)
        m.diffuse.contents = image
        m.transparencyMode = .aOne
        m.writesToDepthBuffer = false
        tags[key] = m
        return m
    }

    private static var stencils: [Int: SCNMaterial] = [:]
    private static func numberStencil(_ number: Int) -> SCNMaterial {
        if let m = stencils[number] { return m }
        let image = Textures.draw(256, 64) { _, w, h in
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedSystemFont(ofSize: h * 0.7, weight: .bold),
                                                        .foregroundColor: NSColor(white: 0.96, alpha: 0.82), .kern: h * 0.04]
            let text = NSAttributedString(string: "#\(number)", attributes: attrs)
            let size = text.size()
            text.draw(at: NSPoint(x: (w - size.width) / 2, y: (h - size.height) / 2))
        }
        let m = flat(.white)
        m.diffuse.contents = image
        m.transparencyMode = .aOne
        m.writesToDepthBuffer = false
        stencils[number] = m
        return m
    }

    static let plateName = "crate-plate"
    static let shellName = "crate-shell"

    static func blinking() -> SCNAction {
        .repeatForever(.sequence([.fadeOpacity(to: 0.15, duration: 0.5), .fadeOpacity(to: 1, duration: 0.5)]))
    }

    static func weldLamp() -> SCNNode {
        let l = SCNNode()
        l.light = SCNLight()
        l.light!.type = .omni
        l.light!.color = NSColor(rgb: (1.0, 0.85, 0.55))
        l.light!.attenuationEndDistance = 2.5
        let spark = SCNNode(geometry: SCNPlane(width: 0.08, height: 0.08))
        spark.geometry!.firstMaterial = flat(NSColor(rgb: (1.0, 0.95, 0.8)))
        spark.constraints = [SCNBillboardConstraint()]
        l.addChildNode(spark)
        return l
    }

    static func qaTick() -> SCNNode {
        let tick = SCNNode(geometry: SCNBox(width: 0.16, height: 0.02, length: 0.16, chamferRadius: 0))
        tick.eulerAngles = SCNVector3(Double.pi / 2, 0, Double.pi / 4)
        tick.geometry!.firstMaterial = flat(NSColor(rgb: (0.35, 0.9, 0.45)))
        tick.runAction(.sequence([.group([.moveBy(x: 0, y: 0.5, z: 0, duration: 0.9),
                                          .sequence([.wait(duration: 0.5), .fadeOut(duration: 0.4)])]),
                                  .removeFromParentNode()]))
        return tick
    }

    static let ghostOpacity = 0.38

    static func cube(color: NSColor, size: Double, shadow floorShadow: NSColor) -> SCNNode {
        let box = SCNBox(width: size, height: size, length: size, chamferRadius: 0)
        let top = flat(color.lighter(0.14)), mid = flat(color), dark = flat(color.darker(0.13))
        box.materials = [mid, dark, mid, dark, top, top]
        let n = SCNNode(geometry: box)
        let under = SCNNode(geometry: SCNPlane(width: size * 1.25, height: size * 1.25))
        under.geometry!.firstMaterial = flat(floorShadow)
        under.eulerAngles.x = -.pi / 2
        under.position = v3(size * 0.08, -size / 2 + 0.004, size * 0.08)
        n.addChildNode(under)
        return n
    }

    static func failingShell(size: Double) -> SCNNode {
        let shell = SCNNode(geometry: SCNBox(width: size, height: size, length: size, chamferRadius: 0))
        shell.geometry!.firstMaterial = flat(NSColor(rgb: (0.95, 0.2, 0.2)))
        shell.opacity = 0.2
        shell.runAction(.repeatForever(.sequence([.fadeOpacity(to: 0.55, duration: 0.7), .fadeOpacity(to: 0.15, duration: 0.9)])))
        return shell
    }

    static func beam() -> SCNNode {
        let n = SCNNode(geometry: faceted(SCNCone(topRadius: 0.05, bottomRadius: 0.32, height: 1)))
        n.geometry!.firstMaterial = flat(NSColor(rgb: (0.75, 0.88, 1.0)))
        n.geometry!.firstMaterial?.transparency = 0.22
        n.geometry!.firstMaterial?.writesToDepthBuffer = false
        n.geometry!.firstMaterial?.isDoubleSided = true
        return n
    }

    static func aim(_ beam: SCNNode, from: SIMD3<Double>, to: SIMD3<Double>, clock: Double, phase: Double) {
        let d = to - from
        let len = max(0.001, (d.x * d.x + d.y * d.y + d.z * d.z).squareRoot())
        let mid = (from + to) / 2
        beam.position = v3(mid.x, mid.y, mid.z)
        beam.scale = SCNVector3(1, len, 1)
        beam.look(at: v3(to.x, to.y, to.z), up: SCNVector3(0, 0, 1), localFront: SCNVector3(0, -1, 0))
        beam.opacity = 0.8 + 0.2 * sin(clock * 3 + phase)
    }

    static func crate(color: NSColor) -> SCNNode {
        let geo = faceted(SCNCylinder(radius: 0.26, height: 0.18))
        geo.radialSegmentCount = 6
        let top = flat(color.lighter(0.16)), side = flat(color.darker(0.06))
        geo.materials = [side, top, top]
        let n = SCNNode()
        let body = SCNNode(geometry: geo)
        n.addChildNode(body)
        return n
    }

    static let berthIdle = NSColor(rgb: (0.05, 0.06, 0.09))

    static func berth() -> (node: SCNNode, rim: SCNNode) {
        let node = SCNNode()
        let height = Looks.current.berthHexHeight
        let rim = SCNNode(geometry: faceted(SCNTube(innerRadius: Station.bayRadius - 0.06, outerRadius: Station.bayRadius, height: 0.008)))
        rim.geometry!.firstMaterial = flat(berthIdle)
        rim.opacity = 0.25
        rim.position = v3(0, height, 0)
        node.addChildNode(rim)
        return (node, rim)
    }

    static let hullPlate = (0.28, 0.33, 0.43)

    static let hullLamp = NSColor(rgb: (1.0, 0.56, 0.12))
    static let hullLampOff = NSColor(rgb: (0.26, 0.30, 0.40))

    static let amberLamp = NSColor(rgb: (1.0, 0.56, 0.12))
    static let amberLampOff = NSColor(rgb: (0.42, 0.24, 0.08))

    static func rocket(color: NSColor, tall: Bool, cargo: Int = 0) -> SCNNode {
        let n = SCNNode()
        let s = RocketGeometry.scale
        let white = lit(NSColor(rgb: (0.92, 0.92, 0.95)))
        let dark = lit(NSColor(rgb: (0.2, 0.21, 0.26)))
        Detail.apply(.hull, to: white)
        let paint = lit(color)
        Detail.apply(.hull, to: paint)
        let tip = SCNNode(), lifter = SCNNode()
        tip.name = "tip"; lifter.name = "lifter"
        let base = RocketGeometry.hullBase
        tip.setValue(base, forKey: "base")
        n.addChildNode(lifter); n.addChildNode(tip)

        func scaled(_ p: [(y: Double, r: Double)]) -> [(y: Double, r: Double)] { p.map { ($0.y * s, $0.r * s * RocketGeometry.fuller) } }
        lifter.addChildNode(SCNNode(geometry: lathe(scaled(RocketShape.profile(from: RocketShape.base, to: RocketShape.split, steps: 6)),
                                                    material: white, capBottom: true, capTop: true)))
        let core = SCNNode(geometry: lathe(scaled(RocketShape.profile(from: RocketShape.split, to: RocketShape.panelTop, steps: 5)).map { ($0.y, $0.r * 0.9) },
                                           material: dark, capBottom: true, capTop: false))
        core.name = "frame"
        tip.addChildNode(core)
        let rings = RocketGeometry.panels / 6
        let ringH = (RocketShape.panelTop - RocketShape.split) / Double(rings)
        for ring in 0..<rings {
            let y0 = RocketShape.split + ringH * Double(ring), y1 = y0 + ringH
            for k in 0..<6 {
                let panel = facet(y0: y0 * s, r0: RocketGeometry.hullRadius(at: y0 * s), y1: y1 * s, r1: RocketGeometry.hullRadius(at: y1 * s),
                                  side: k, inset: 0.004, material: white)
                panel.name = "panel\(ring * 6 + k)"
                tip.addChildNode(panel)
            }
        }
        let nose = SCNNode(geometry: lathe(scaled(RocketShape.profile(from: RocketShape.panelTop, to: RocketShape.height, steps: 4)),
                                           material: white, capBottom: true, capTop: false))
        nose.name = "nose"
        tip.addChildNode(nose)

        tip.addChildNode(RocketShape.hatch(scale: s, surface: { RocketGeometry.apothem(at: $0) }, flatShaded: true))

        for k in 0..<7 {
            let a = Double(k) * .pi / 3
            let at = k == 6 ? SIMD2(0.0, 0.0) : SIMD2(cos(a), sin(a)) * RocketShape.r(RocketShape.base) * RocketShape.bellRing * s
            let h = RocketShape.bellHeight * s
            let bell = SCNNode(geometry: faceted(SCNCone(topRadius: RocketShape.bellTop * s, bottomRadius: RocketShape.bellBottom * s, height: h)))
            bell.geometry!.firstMaterial = dark
            bell.position = v3(at.x, RocketShape.base * s - h / 2, at.y)
            lifter.addChildNode(bell)
        }
        for a in RocketShape.finBearings {
            let pivot = SCNNode()
            pivot.eulerAngles.y = CGFloat(-a)
            let fin = SCNNode(geometry: SCNShape(path: RocketShape.finOutline(scale: s), extrusionDepth: 0.012))
            fin.geometry!.firstMaterial = paint
            pivot.addChildNode(fin)
            let podR = RocketShape.podRadius * s, podL = RocketShape.podLength * s
            let body = SCNNode(geometry: faceted(SCNCylinder(radius: podR, height: podL - 2 * podR)))
            let cap = SCNNode(geometry: faceted(SCNCone(topRadius: 0, bottomRadius: podR, height: podR * 1.6)))
            let foot = SCNNode(geometry: faceted(SCNCone(topRadius: podR, bottomRadius: podR * 0.7, height: podR)))
            for (part, y) in [(body, podL / 2), (cap, podL - podR + podR * 0.8), (foot, podR / 2)] {
                part.geometry!.firstMaterial = paint
                part.position = v3(RocketShape.finReach * s, y, 0)
                pivot.addChildNode(part)
            }
            lifter.addChildNode(pivot)
        }
        for a in RocketShape.rcsBearings {
            tip.addChildNode(RocketShape.thruster(at: a, scale: s, surface: { RocketGeometry.hullRadius(at: $0) }, hull: white, nozzle: dark))
        }
        for a in RocketShape.legBearings { tip.addChildNode(RocketShape.leg(at: a, scale: s, segments: 2, material: paint.copy() as! SCNMaterial)) }
        let engineH = RocketShape.engineHeight * s
        let engine = SCNNode(geometry: faceted(SCNCone(topRadius: RocketShape.engineTop * s, bottomRadius: RocketShape.engineBottom * s, height: engineH)))
        engine.geometry!.firstMaterial = dark
        engine.position = v3(0, base - engineH / 2, 0)
        tip.addChildNode(engine)

        let flame = SCNNode(geometry: faceted(SCNCone(topRadius: RocketGeometry.radius * 0.6, bottomRadius: 0, height: 0.45)))
        flame.geometry!.firstMaterial = flat(Palette.pyramid)
        flame.position = v3(0, -0.2, 0)
        flame.name = "flame"
        flame.opacity = 0
        n.addChildNode(flame)
        n.enumerateChildNodes { c, _ in if let name = c.name { c.setValue(name, forKey: "part") } }
        shape(n, lifter: tall, panels: RocketGeometry.panels)
        return n
    }

    static func paintNose(_ rocket: SCNNode, _ color: NSColor) {
        guard let tip = part(rocket, "tip") else { return }
        for c in tip.childNodes where (c.value(forKey: "part") as? String) == "nose" { c.geometry?.firstMaterial = lit(color) }
    }

    static func nameRocket(_ rocket: SCNNode, repo: String, color: NSColor) {
        guard let lifter = part(rocket, "lifter"), let tip = part(rocket, "tip"), !repo.isEmpty else { return }
        let names = RocketShape.names(repo.uppercased(), color: color, scale: RocketGeometry.scale,
                                      apothem: { RocketGeometry.apothem(at: $0) }, width: RocketShape.nameWidth * RocketGeometry.scale, flatShaded: true)
        names.lifter.forEach(lifter.addChildNode)
        names.tip.forEach(tip.addChildNode)
        shape(rocket, lifter: !lifter.isHidden, panels: RocketGeometry.panels)
    }

    private static func corner(_ j: Int, r: Double, y: Double) -> SIMD3<Double> {
        let a = .pi / 6 + Double(j) * .pi / 3
        return SIMD3(cos(a) * r, y, sin(a) * r)
    }

    static func lathe(_ profile: [(y: Double, r: Double)], material: SCNMaterial, capBottom: Bool, capTop: Bool) -> SCNGeometry {
        var verts: [SCNVector3] = [], normals: [SCNVector3] = [], idx: [Int32] = []
        func quad(_ a: SIMD3<Double>, _ b: SIMD3<Double>, _ c: SIMD3<Double>, _ d: SIMD3<Double>, out: SIMD3<Double>) {
            var nrm = simd_normalize(simd_cross(b - a, d - a))
            if simd_dot(nrm, out) < 0 { nrm = -nrm }
            let i = Int32(verts.count)
            for p in [a, b, c, d] { verts.append(SCNVector3(p.x, p.y, p.z)); normals.append(SCNVector3(nrm.x, nrm.y, nrm.z)) }
            idx += [i, i + 1, i + 2, i, i + 2, i + 3, i, i + 2, i + 1, i, i + 3, i + 2]
        }
        for i in 0..<(profile.count - 1) {
            let lo = profile[i], hi = profile[i + 1]
            for j in 0..<6 {
                let a = corner(j, r: lo.r, y: lo.y), b = corner(j + 1, r: lo.r, y: lo.y)
                let c = corner(j + 1, r: hi.r, y: hi.y), d = corner(j, r: hi.r, y: hi.y)
                quad(a, b, c, d, out: (a + b) / 2 - SIMD3(0, lo.y, 0))
            }
        }
        for (end, wanted, down) in [(profile.first!, capBottom, true), (profile.last!, capTop, false)] where wanted && end.r > 0.001 {
            let centre = Int32(verts.count)
            let up = SCNVector3(0, down ? -1 : 1, 0)
            verts.append(SCNVector3(0, end.y, 0)); normals.append(up)
            for j in 0...6 { let p = corner(j, r: end.r, y: end.y); verts.append(SCNVector3(p.x, p.y, p.z)); normals.append(up) }
            for j in 0..<Int32(6) { idx += [centre, centre + 1 + j, centre + 2 + j, centre, centre + 2 + j, centre + 1 + j] }
        }
        let g = SCNGeometry(sources: [SCNGeometrySource(vertices: verts), SCNGeometrySource(normals: normals)],
                            elements: [SCNGeometryElement(indices: idx, primitiveType: .triangles)])
        g.firstMaterial = material
        return g
    }

    private static func facet(y0: Double, r0: Double, y1: Double, r1: Double, side k: Int, inset: Double, material: SCNMaterial) -> SCNNode {
        let j = (6 - k) % 6
        let corners = [corner(j - 1 + 6, r: r0, y: y0), corner(j + 6, r: r0, y: y0), corner(j + 6, r: r1, y: y1), corner(j - 1 + 6, r: r1, y: y1)]
        let centre = corners.reduce(SIMD3<Double>(repeating: 0), +) / 4
        let pulled = corners.map { centre + ($0 - centre) * (1 - inset / max(0.01, r0)) }
        let node = SCNNode(geometry: lathePiece(pulled.map { $0 - centre }, out: SIMD3(centre.x, 0, centre.z)))
        node.geometry!.firstMaterial = material
        node.position = SCNVector3(centre.x, centre.y, centre.z)
        return node
    }

    private static func lathePiece(_ q: [SIMD3<Double>], out: SIMD3<Double>) -> SCNGeometry {
        var nrm = simd_normalize(simd_cross(q[1] - q[0], q[3] - q[0]))
        if simd_dot(nrm, out) < 0 { nrm = -nrm }
        let verts = q.map { SCNVector3($0.x, $0.y, $0.z) }
        let normals = Array(repeating: SCNVector3(nrm.x, nrm.y, nrm.z), count: 4)
        let idx: [Int32] = [0, 1, 2, 0, 2, 3, 0, 2, 1, 0, 3, 2]
        return SCNGeometry(sources: [SCNGeometrySource(vertices: verts), SCNGeometrySource(normals: normals)],
                           elements: [SCNGeometryElement(indices: idx, primitiveType: .triangles)])
    }

    static func part(_ rocket: SCNNode, _ name: String) -> SCNNode? {
        rocket.childNodes.first { ($0.value(forKey: "part") as? String) == name }
    }

    static func shape(_ rocket: SCNNode, lifter: Bool, panels: Int) {
        guard let tip = part(rocket, "tip") else { return }
        let base = (tip.value(forKey: "base") as? Double) ?? 0
        part(rocket, "lifter")?.isHidden = !lifter
        if lifter { part(rocket, "lifter")?.position = SCNVector3Zero }
        RocketShape.fold(tip, lifter ? 1 : 0)
        RocketShape.showLegs(tip, !lifter)
        tip.position.y = CGFloat(lifter ? 0 : RocketGeometry.standHeight - base)
        let whole = panels >= RocketGeometry.panels
        for c in tip.childNodes {
            let name = (c.value(forKey: "part") as? String) ?? ""
            if name.hasPrefix("panel"), let i = Int(name.dropFirst(5)) { c.isHidden = i >= panels }
            else if name == "nose" || name == "hatch" || name == "name" || name == "rcs" { c.isHidden = !whole }
        }
    }
}

extension Props {
}

extension Props {
    static let passedGreen = NSColor(rgb: (0.45, 0.95, 0.5))
    static let failRed = NSColor(rgb: (1.0, 0.22, 0.2))
    static let droneEye = NSColor(rgb: (0.35, 0.75, 0.95))
    static let waitingAmber = NSColor(rgb: (0.95, 0.7, 0.15))
    static let hazard = NSColor(rgb: (0.95, 0.7, 0.15))

    static func glowing(_ color: NSColor, alpha: CGFloat) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = color.withAlphaComponent(alpha)
        m.blendMode = .add
        m.writesToDepthBuffer = false
        m.isDoubleSided = true
        return m
    }

    static func glass(alpha: CGFloat = 0.22) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .blinn
        m.diffuse.contents = NSColor(rgb: (0.55, 0.78, 0.95)).withAlphaComponent(alpha)
        m.specular.contents = NSColor(white: 0.5, alpha: 1)
        m.shininess = 0.9
        m.transparencyMode = .dualLayer
        m.writesToDepthBuffer = false
        m.isDoubleSided = true
        return m
    }
}
