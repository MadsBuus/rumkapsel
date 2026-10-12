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

    static let cubeSizes = [0.18, 0.26, 0.34]
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
        let h = RocketGeometry.height, r = RocketGeometry.radius, cradleTop = RocketGeometry.cradleTop
        let white = lit(NSColor(rgb: (0.92, 0.92, 0.95)))
        let dark = lit(NSColor(rgb: (0.2, 0.21, 0.26)))
        Detail.apply(.hull, to: white)
        let paint = lit(color)
        Detail.apply(.hull, to: paint)
        func plated(_ m: SCNMaterial, _ w: Double, _ h: Double, at: (Double, Double) = (0, 0)) -> SCNMaterial {
            let c = m.copy() as! SCNMaterial
            let unit = RocketGeometry.platingSpan
            c.multiply.contentsTransform = SCNMatrix4Mult(SCNMatrix4MakeScale(CGFloat(w / unit), CGFloat(h / unit), 1),
                                                          SCNMatrix4MakeTranslation(CGFloat(at.0 / unit), CGFloat(at.1 / unit), 0))
            return c
        }
        let tip = SCNNode(), lifter = SCNNode(), cradle = SCNNode()
        tip.name = "tip"; lifter.name = "lifter"; cradle.name = "cradle"
        let base = RocketGeometry.hullBase
        tip.setValue(base, forKey: "base")
        n.addChildNode(lifter); n.addChildNode(tip); n.addChildNode(cradle)

        let hullR = RocketGeometry.hullRadius, hullH = RocketGeometry.hullHeight, apothem = RocketGeometry.apothem
        let rings = RocketGeometry.panels / 6, ringH = hullH / Double(rings)
        let core = SCNNode(geometry: faceted(SCNCylinder(radius: apothem * 0.9, height: hullH)))
        core.geometry!.firstMaterial = dark
        core.position = v3(0, base + hullH / 2, 0)
        core.name = "frame"
        tip.addChildNode(core)
        for k in 0..<6 {
            let a = Double(k) * .pi / 3 + .pi / 3
            let rib = SCNNode(geometry: SCNBox(width: 0.014, height: hullH, length: 0.014, chamferRadius: 0))
            rib.geometry!.firstMaterial = dark
            rib.position = v3(sin(a) * hullR * 0.97, base + hullH / 2, cos(a) * hullR * 0.97)
            rib.name = "frame"
            tip.addChildNode(rib)
        }
        for ring in 0..<rings {
            for k in 0..<6 {
                let f = RocketGeometry.facing(side: k)
                let panel = SCNNode(geometry: SCNBox(width: hullR - 0.006, height: ringH - 0.006, length: 0.014, chamferRadius: 0))
                panel.geometry!.firstMaterial = plated(white, hullR, ringH, at: (Double(k) * hullR, Double(ring) * ringH))
                panel.position = v3(f.x * apothem, base + ringH * (Double(ring) + 0.5), f.y * apothem)
                panel.eulerAngles.y = CGFloat(atan2(f.x, f.y))
                panel.name = "panel\(ring * 6 + k)"
                tip.addChildNode(panel)
            }
        }
        let nose = SCNNode(geometry: faceted(SCNCone(topRadius: 0, bottomRadius: hullR, height: r * 2.6)))
        nose.geometry!.firstMaterial = plated(paint, 2 * .pi * hullR, r * 2.6)
        nose.position = v3(0, base + hullH + r * 1.3, 0)
        nose.name = "nose"
        tip.addChildNode(nose)
        let hatch = SCNNode()
        hatch.name = "hatch"
        let frameW = r * 0.9, frameH = 0.2
        let frame = SCNNode(geometry: SCNBox(width: frameW, height: frameH, length: 0.03, chamferRadius: 0))
        frame.geometry!.firstMaterial = dark
        frame.position = v3(0, 0, -0.012)
        hatch.addChildNode(frame)
        let door = SCNNode(geometry: SCNBox(width: frameW - 0.02, height: frameH - 0.02, length: 0.02, chamferRadius: 0))
        door.geometry!.firstMaterial = plated(white, frameW, frameH)
        door.name = "door"
        door.position = v3(0, 0, 0.004)
        hatch.addChildNode(door)
        let latch = SCNNode(geometry: SCNBox(width: frameW * 0.45, height: 0.016, length: 0.014, chamferRadius: 0))
        latch.geometry!.firstMaterial = lit(NSColor(rgb: (0.75, 0.78, 0.82)))
        latch.position = v3(frameW * 0.08, 0, 0.02)
        hatch.addChildNode(latch)
        for dy in [-0.055, 0.055] {
            let hinge = SCNNode(geometry: SCNBox(width: 0.02, height: 0.03, length: 0.02, chamferRadius: 0))
            hinge.geometry!.firstMaterial = lit(NSColor(rgb: (0.75, 0.78, 0.82)))
            hinge.position = v3(-frameW / 2 + 0.005, dy, 0.012)
            hatch.addChildNode(hinge)
        }
        let at = RocketGeometry.hatchInTip
        hatch.position = v3(at.x, at.y, at.z)
        hatch.eulerAngles.y = .pi / 2
        tip.addChildNode(hatch)
        for k in 0..<3 {
            let a = .pi / 2 + Double(2 * k + 1) * .pi / 3
            let port = SCNNode(geometry: SCNBox(width: r * 0.36, height: r * 0.36, length: 0.02, chamferRadius: 0))
            port.geometry!.firstMaterial = flat(NSColor(rgb: (0.35, 0.55, 0.85)))
            port.position = v3(sin(a) * (apothem + 0.008), 0.12 + h * 0.75, cos(a) * (apothem + 0.008))
            port.eulerAngles.y = CGFloat(a)
            port.name = "port"
            tip.addChildNode(port)
        }

        let lower = SCNNode(geometry: faceted(SCNCylinder(radius: r, height: h * 0.45)))
        lower.geometry!.firstMaterial = plated(white, 2 * .pi * r, h * 0.45)
        lower.position = v3(0, 0.12 + h * 0.225, 0)
        lifter.addChildNode(lower)
        let band = SCNNode(geometry: faceted(SCNCylinder(radius: r * 1.02, height: h * 0.08)))
        band.geometry!.firstMaterial = plated(paint, 2 * .pi * r, h * 0.08)
        band.position = v3(0, 0.12 + h * 0.45, 0)
        lifter.addChildNode(band)
        for k in 0..<4 {
            let pivot = SCNNode()
            pivot.eulerAngles.y = Double(k) * .pi / 2 + .pi / 4
            let finH = r * 2.6, finL = r * 1.3, lean = 0.42
            let fin = SCNNode(geometry: SCNBox(width: 0.035, height: finH, length: finL, chamferRadius: 0))
            fin.geometry!.firstMaterial = plated(paint, r * 1.3, r * 2.6)
            fin.position = v3(0, 0.12 + finH * 0.45, r * 0.3 + finL * 0.5 + finH * 0.5 * sin(lean) * 0.5)
            fin.eulerAngles.x = -lean
            pivot.addChildNode(fin)
            lifter.addChildNode(pivot)
        }
        let throat = SCNNode(geometry: faceted(SCNCylinder(radius: r * 0.35, height: 0.04)))
        throat.geometry!.firstMaterial = dark
        throat.position = v3(0, 0.11, 0)
        lifter.addChildNode(throat)
        let bell = SCNNode(geometry: faceted(SCNCone(topRadius: r * 0.35, bottomRadius: r * 0.75, height: 0.09)))
        bell.geometry!.firstMaterial = lit(NSColor(rgb: (0.3, 0.31, 0.36)))
        bell.position = v3(0, 0.055, 0)
        lifter.addChildNode(bell)
        for k in 0..<3 {
            let pivot = SCNNode()
            pivot.eulerAngles.y = Double(k) * 2 * .pi / 3 + .pi / 3
            let leg = SCNNode(geometry: SCNBox(width: 0.03, height: 0.24, length: 0.03, chamferRadius: 0))
            leg.geometry!.firstMaterial = dark
            leg.position = v3(0, 0.11, r * 1.15)
            leg.eulerAngles.x = -0.55
            pivot.addChildNode(leg)
            let foot = SCNNode(geometry: SCNBox(width: 0.06, height: 0.02, length: 0.06, chamferRadius: 0))
            foot.geometry!.firstMaterial = dark
            foot.position = v3(0, 0.01, r * 1.15 + 0.12 * sin(0.55))
            pivot.addChildNode(foot)
            lifter.addChildNode(pivot)
        }

        let collar = SCNNode(geometry: faceted(SCNCylinder(radius: hullR * 1.12, height: 0.05)))
        collar.geometry!.firstMaterial = dark
        collar.position = v3(0, cradleTop - 0.025, 0)
        cradle.addChildNode(collar)
        for k in 0..<3 {
            let a = Double(k) * 2 * .pi / 3 + .pi / 3
            let leg = SCNNode(geometry: SCNBox(width: 0.035, height: cradleTop, length: 0.035, chamferRadius: 0))
            leg.geometry!.firstMaterial = lit(NSColor(rgb: (0.38, 0.4, 0.45)))
            leg.position = v3(sin(a) * hullR * 1.2, cradleTop / 2, cos(a) * hullR * 1.2)
            cradle.addChildNode(leg)
        }

        let flame = SCNNode(geometry: faceted(SCNCone(topRadius: r * 0.6, bottomRadius: 0, height: 0.45)))
        flame.geometry!.firstMaterial = flat(Palette.pyramid)
        flame.position = v3(0, -0.2, 0)
        flame.name = "flame"
        flame.opacity = 0
        n.addChildNode(flame)
        n.enumerateChildNodes { c, _ in if let name = c.name { c.setValue(name, forKey: "part") } }
        shape(n, lifter: tall, panels: RocketGeometry.panels)
        return n
    }

    static func part(_ rocket: SCNNode, _ name: String) -> SCNNode? {
        rocket.childNodes.first { ($0.value(forKey: "part") as? String) == name }
    }

    static func shape(_ rocket: SCNNode, lifter: Bool, panels: Int) {
        guard let tip = part(rocket, "tip") else { return }
        let base = (tip.value(forKey: "base") as? Double) ?? 0
        part(rocket, "lifter")?.isHidden = !lifter
        part(rocket, "cradle")?.isHidden = lifter
        tip.position.y = CGFloat(lifter ? 0 : RocketGeometry.cradleTop - base)
        let whole = panels >= RocketGeometry.panels
        for c in tip.childNodes {
            let name = (c.value(forKey: "part") as? String) ?? ""
            if name.hasPrefix("panel"), let i = Int(name.dropFirst(5)) { c.isHidden = i >= panels }
            else if name == "nose" || name == "hatch" || name == "port" { c.isHidden = !whole }
        }
    }
}

extension Props {
}
