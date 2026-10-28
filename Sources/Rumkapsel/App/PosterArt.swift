import AppKit
import SceneKit
import Metal
import CoreImage

enum PosterArt {
    static let size = CGSize(width: 1200, height: 1600)
    static let sky = NSColor(rgb: (0.015, 0.02, 0.035))
    static let ink = NSColor(white: 0.97, alpha: 1), dim = NSColor(white: 1, alpha: 0.55), quiet = NSColor(white: 0.2, alpha: 1)
    static let amber = Props.waitingAmber, green = Props.passedGreen
    static let working = NSColor(rgb: (0.35, 0.78, 0.85)), waiting = Palette.pyramid, sleeping = NSColor(Colors.quarters).lighter(0.25)
    static var repo: NSColor { NSColor(Colors.repos[0]) }

    static func draw(_ poster: Poster) -> NSImage {
        switch poster {
        case .yard: return yard()
        case .shapes: return shapes()
        case .crew: return crew()
        case .rocket: return rocket()
        case .decon: return decon()
        case .mission: return mission()
        case .lounge: return lounge()
        case .galley: return galley()
        case .bath: return bath()
        case .bay: return bay()
        case .gym: return gym()
        }
    }

    static func bake(into dir: URL) -> Never {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for poster in Poster.allCases {
            let image = draw(poster)
            guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                  let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.86]) else { exit(1) }
            try? jpeg.write(to: dir.appendingPathComponent(Poster.file(poster)))
            print("baked \(poster.rawValue)")
        }
        exit(0)
    }

    // MARK: the stage

    static func snapshot(_ scene: SCNScene, from eye: SCNNode, size: CGSize) -> NSImage {
        let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
        renderer.scene = scene
        renderer.pointOfView = eye
        return renderer.snapshot(atTime: 1, with: size, antialiasingMode: .multisampling4X)
    }

    static func light(_ scene: SCNScene, _ type: SCNLight.LightType, _ color: NSColor, _ intensity: CGFloat,
                      from: SCNVector3 = SCNVector3(0, 1, 0), at: SCNVector3 = SCNVector3(0, 0, 0)) -> SCNLight {
        let n = SCNNode(), l = SCNLight()
        l.type = type; l.color = color; l.intensity = intensity
        n.light = l
        n.position = from
        n.look(at: at, up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
        scene.rootNode.addChildNode(n)
        return l
    }

    static func sideScene(floor: Bool) -> SCNScene {
        let scene = SCNScene()
        scene.background.contents = sky
        if floor {
            let plane = SCNNode(geometry: SCNPlane(width: 30, height: 12))
            plane.geometry!.firstMaterial = lit(NSColor(rgb: (0.24, 0.26, 0.32)))
            plane.eulerAngles.x = -.pi / 2
            plane.position.z = 4.8
            scene.rootNode.addChildNode(plane)
        }
        scene.rootNode.addChildNode(FlightCraft.stars())
        _ = light(scene, .ambient, NSColor(rgb: (0.45, 0.55, 0.8)), 220)
        let key = light(scene, .directional, NSColor(rgb: (1.0, 0.84, 0.66)), 1900, from: SCNVector3(-6, 4.5, 2.2), at: SCNVector3(0, 0.3, 0))
        key.castsShadow = true; key.shadowRadius = 5; key.shadowSampleCount = 16; key.shadowMapSize = CGSize(width: 4096, height: 4096)
        key.shadowColor = NSColor(white: 0, alpha: 0.65); key.orthographicScale = 8; key.automaticallyAdjustsShadowProjection = false
        key.zNear = 0.1; key.zFar = 30
        let rim = light(scene, .spot, NSColor(rgb: (0.55, 0.8, 1.0)), 4200, from: SCNVector3(2.5, 3.5, -5), at: SCNVector3(-0.4, 0.4, 0))
        rim.spotInnerAngle = 28; rim.spotOuterAngle = 70
        return scene
    }

    static func sideEye(_ scene: SCNScene, scale: CGFloat = 2.15, centre: SIMD2<Double> = SIMD2(0.02, 1.05)) -> SCNNode {
        let eye = SCNNode(), cam = SCNCamera()
        FlightCraft.film(cam)
        cam.usesOrthographicProjection = true
        cam.orthographicScale = scale
        cam.vignettingIntensity = 0
        cam.exposureOffset = -0.35
        cam.bloomThreshold = 1.6
        cam.bloomIntensity = 0.6
        cam.zFar = 1000
        eye.camera = cam
        eye.eulerAngles.x = -0.1
        eye.position = SCNVector3(centre.x, centre.y + 20 * tan(0.1), 20)
        scene.rootNode.addChildNode(eye)
        return eye
    }

    static func glowLight(_ scene: SCNScene, _ color: NSColor, at: SCNVector3, intensity: CGFloat = 320, reach: CGFloat = 1.1) {
        let l = light(scene, .omni, color, intensity, from: at)
        l.attenuationEndDistance = reach
    }

    static func object(_ node: SCNNode, yaw: Double = -0.6, pitch: Double = -0.42, pixels: CGFloat = 600, margin: Double = 1.25) -> NSImage {
        let scene = SCNScene()
        scene.background.contents = NSColor.clear
        let turn = SCNNode()
        turn.eulerAngles.y = CGFloat(yaw)
        turn.addChildNode(node)
        scene.rootNode.addChildNode(turn)
        _ = light(scene, .ambient, NSColor(rgb: (0.45, 0.55, 0.8)), 360)
        _ = light(scene, .directional, NSColor(rgb: (1.0, 0.88, 0.74)), 1800, from: SCNVector3(-1.5, 2.6, 2.0))
        _ = light(scene, .directional, NSColor(rgb: (0.55, 0.8, 1.0)), 2200, from: SCNVector3(1.8, 1.2, -1.6))
        let (c, r) = turn.boundingSphere
        let eye = SCNNode(), cam = SCNCamera()
        cam.usesOrthographicProjection = true
        cam.orthographicScale = Double(r) * margin
        cam.zFar = 100
        eye.camera = cam
        eye.eulerAngles.x = CGFloat(pitch)
        eye.position = SCNVector3(c.x, c.y + 10 * sin(-pitch), c.z + 10 * cos(pitch))
        scene.rootNode.addChildNode(eye)
        return snapshot(scene, from: eye, size: CGSize(width: pixels, height: pixels))
    }

    // MARK: the mascot

    enum Mood { case proud, working, waiting, dozing }

    static func mascot(_ mood: Mood = .proud, grounded: Bool = false, extra: ((SCNNode) -> Void)? = nil) -> NSImage {
        let scene = SCNScene()
        scene.background.contents = NSColor.clear
        let hero = Minion(id: "poster", station: "poster", home: Home(key: "x", name: "x", repo: "x", issue: nil),
                          cwd: "", toolCount: 0, isSubagent: false, start: Cell(x: 0, y: 0))
        hero.node.opacity = 1
        hero.wearSuit(badge: repo)
        face(hero, mood)
        if !grounded { hero.node.enumerateHierarchy { n, _ in if n.geometry is SCNPlane { n.isHidden = true } } }
        hero.node.eulerAngles = mood == .dozing ? v3(-0.3, -0.45, 0.08) : v3(-0.15, -0.45, 0)
        scene.rootNode.addChildNode(hero.node)
        extra?(scene.rootNode)
        _ = light(scene, .ambient, NSColor(rgb: (0.45, 0.55, 0.8)), 320)
        _ = light(scene, .directional, NSColor(rgb: (1.0, 0.88, 0.74)), 2300, from: SCNVector3(-0.6, 2.6, 2.4), at: SCNVector3(0, 0.25, 0))
        _ = light(scene, .directional, NSColor(rgb: (0.55, 0.8, 1.0)), 3200, from: SCNVector3(1.8, 1.2, -1.4), at: SCNVector3(0, 0.25, 0))
        let eye = SCNNode(), cam = SCNCamera()
        cam.fieldOfView = 78
        cam.zNear = 0.01
        eye.camera = cam
        eye.position = SCNVector3(0.2, 0.07, 0.46)
        eye.look(at: SCNVector3(0, 0.32, 0), up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, -1))
        scene.rootNode.addChildNode(eye)
        let size = CGSize(width: 900, height: 1100)
        let shot = snapshot(scene, from: eye, size: size)
        guard let cg = shot.cgImage(forProposedRect: nil, context: nil, hints: nil), let bump = CIFilter(name: "CIBumpDistortion") else { return shot }
        bump.setValue(CIImage(cgImage: cg), forKey: kCIInputImageKey)
        bump.setValue(CIVector(x: CGFloat(cg.width) / 2, y: CGFloat(cg.height) * 0.55), forKey: kCIInputCenterKey)
        bump.setValue(CGFloat(cg.width) * 0.75, forKey: kCIInputRadiusKey)
        bump.setValue(0.35, forKey: kCIInputScaleKey)
        guard let bulged = bump.outputImage?.cropped(to: CGRect(x: 0, y: 0, width: cg.width, height: cg.height)) else { return shot }
        let out = NSImage(size: size)
        out.addRepresentation(NSCIImageRep(ciImage: bulged))
        return out
    }

    private static func face(_ hero: Minion, _ mood: Mood) {
        var found: SCNNode?
        hero.node.enumerateHierarchy { n, stop in if (n.geometry as? SCNBox)?.width == 0.22 { found = n; stop.pointee = true } }
        guard let body = found else { return }
        body.childNode(withName: "patch", recursively: false)?.isHidden = true
        let line = CGMutablePath()
        switch mood {
        case .dozing: line.move(to: CGPoint(x: -0.018, y: 0)); line.addLine(to: CGPoint(x: 0.018, y: 0))
        case .waiting: line.addArc(center: .zero, radius: 0.016, startAngle: .pi * 1.2, endAngle: .pi * 1.8, clockwise: false)
        default: line.addArc(center: .zero, radius: 0.03, startAngle: .pi * 200 / 180, endAngle: .pi * 340 / 180, clockwise: false)
        }
        let path = NSBezierPath(cgPath: line.copy(strokingWithWidth: 0.008, lineCap: .round, lineJoin: .round, miterLimit: 1))
        path.flatness = 0.0003
        let shape = SCNShape(path: path, extrusionDepth: 0)
        shape.firstMaterial = flat(NSColor(rgb: (0.12, 0.14, 0.2)))
        let n = SCNNode(geometry: shape)
        n.position = v3(0, mood == .dozing ? 0.112 : 0.122, 0.0565)
        body.addChildNode(n)
    }

    // MARK: ink

    struct Ink {
        let H: CGFloat

        func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: x, y: H - y) }
        func font(_ s: CGFloat, _ w: NSFont.Weight = .black) -> NSFont { .systemFont(ofSize: s, weight: w, width: .condensed) }

        @discardableResult
        func say(_ s: String, _ f: NSFont, _ color: NSColor, x: CGFloat, top: CGFloat, align: NSTextAlignment = .left, kern: CGFloat = 0) -> CGSize {
            let a = NSAttributedString(string: s, attributes: [.font: f, .foregroundColor: color, .kern: kern])
            let w = a.size()
            let x0 = align == .center ? x - w.width / 2 : align == .right ? x - w.width : x
            a.draw(at: NSPoint(x: x0, y: H - top - w.height))
            return w
        }

        func glow(_ color: NSColor, radius: CGFloat = 18, _ draw: () -> Void) {
            NSGraphicsContext.saveGraphicsState()
            let sh = NSShadow(); sh.shadowColor = color.withAlphaComponent(0.8); sh.shadowBlurRadius = radius; sh.shadowOffset = .zero; sh.set()
            draw()
            NSGraphicsContext.restoreGraphicsState()
        }

        func arrow(_ a: NSPoint, _ c1: NSPoint, _ c2: NSPoint, _ b: NSPoint, color: NSColor, width: CGFloat = 12, dashed: Bool = false) {
            let dx = b.x - c2.x, dy = b.y - c2.y, len = max(0.001, (dx * dx + dy * dy).squareRoot()), ux = dx / len, uy = dy / len
            let head = width * 3.2
            let end = NSPoint(x: b.x - ux * head * 0.6, y: b.y - uy * head * 0.6)
            let path = NSBezierPath()
            path.move(to: p(a.x, a.y)); path.curve(to: p(end.x, end.y), controlPoint1: p(c1.x, c1.y), controlPoint2: p(c2.x, c2.y))
            path.lineWidth = width; path.lineCapStyle = .round
            if dashed { path.setLineDash([width * 1.6, width * 1.4], count: 2, phase: 0) }
            let tip = NSBezierPath()
            tip.move(to: p(b.x + ux * head * 0.4, b.y + uy * head * 0.4))
            tip.line(to: p(b.x - ux * head * 0.6 - uy * head * 0.62, b.y - uy * head * 0.6 + ux * head * 0.62))
            tip.line(to: p(b.x - ux * head * 0.6 + uy * head * 0.62, b.y - uy * head * 0.6 - ux * head * 0.62))
            tip.close()
            glow(color) { color.setStroke(); path.stroke(); color.setFill(); tip.fill() }
        }

        func hop(_ a: NSPoint, _ b: NSPoint, lift: CGFloat, color: NSColor) {
            let top = min(a.y, b.y) - lift
            arrow(a, NSPoint(x: a.x + (b.x - a.x) * 0.15, y: top), NSPoint(x: a.x + (b.x - a.x) * 0.85, y: top), b, color: color)
        }

        func straight(_ a: NSPoint, _ b: NSPoint, color: NSColor, width: CGFloat = 12, dashed: Bool = false) {
            arrow(a, NSPoint(x: a.x + (b.x - a.x) / 3, y: a.y + (b.y - a.y) / 3), NSPoint(x: a.x + (b.x - a.x) * 2 / 3, y: a.y + (b.y - a.y) * 2 / 3), b,
                  color: color, width: width, dashed: dashed)
        }

        func bracket(from a: CGFloat, to b: CGFloat, top: CGFloat, color: NSColor, word: String, size: CGFloat = 64) {
            let path = NSBezierPath()
            path.move(to: p(a, top)); path.line(to: p(a, top + 32)); path.line(to: p(b, top + 32)); path.line(to: p(b, top))
            path.move(to: p((a + b) / 2, top + 32)); path.line(to: p((a + b) / 2, top + 60))
            path.lineWidth = 10; path.lineCapStyle = .round; path.lineJoinStyle = .round
            color.setStroke(); path.stroke()
            say(word, font(size), color, x: (a + b) / 2, top: top + 70, align: .center, kern: 6)
        }

        func callout(from anchor: NSPoint, to elbow: NSPoint, end: NSPoint, color: NSColor) {
            let path = NSBezierPath()
            path.move(to: p(anchor.x, anchor.y)); path.line(to: p(elbow.x, elbow.y)); path.line(to: p(end.x, end.y))
            path.lineWidth = 5; path.lineCapStyle = .round; path.lineJoinStyle = .round
            let dot = NSBezierPath(ovalIn: NSRect(x: anchor.x - 11, y: H - anchor.y - 11, width: 22, height: 22))
            glow(color, radius: 12) { color.setStroke(); path.stroke(); color.setFill(); dot.fill() }
        }

        func heart(at c: NSPoint, size k: CGFloat, tilt: CGFloat = -9) {
            func shape(_ k: CGFloat) -> NSBezierPath {
                let h = NSBezierPath()
                h.move(to: NSPoint(x: 0, y: -0.5 * k))
                h.curve(to: NSPoint(x: -0.5 * k, y: 0.1 * k), controlPoint1: NSPoint(x: -0.15 * k, y: -0.3 * k), controlPoint2: NSPoint(x: -0.5 * k, y: -0.15 * k))
                h.curve(to: NSPoint(x: 0, y: 0.3 * k), controlPoint1: NSPoint(x: -0.5 * k, y: 0.45 * k), controlPoint2: NSPoint(x: -0.1 * k, y: 0.5 * k))
                h.curve(to: NSPoint(x: 0.5 * k, y: 0.1 * k), controlPoint1: NSPoint(x: 0.1 * k, y: 0.5 * k), controlPoint2: NSPoint(x: 0.5 * k, y: 0.45 * k))
                h.curve(to: NSPoint(x: 0, y: -0.5 * k), controlPoint1: NSPoint(x: 0.5 * k, y: -0.15 * k), controlPoint2: NSPoint(x: 0.15 * k, y: -0.3 * k))
                h.close()
                let t = NSAffineTransform()
                t.translateX(by: c.x, yBy: H - c.y)
                t.rotate(byDegrees: tilt)
                h.transform(using: t as AffineTransform)
                return h
            }
            NSGraphicsContext.saveGraphicsState()
            let drop = NSShadow(); drop.shadowColor = NSColor(white: 0, alpha: 0.35); drop.shadowBlurRadius = 6; drop.shadowOffset = NSSize(width: 2, height: -3); drop.set()
            NSColor.white.setFill(); shape(k).fill()
            NSGraphicsContext.restoreGraphicsState()
            repo.setFill(); shape(k * 0.79).fill()
        }

        func image(_ img: NSImage, x: CGFloat, top: CGFloat, width: CGFloat, alpha: CGFloat = 1) {
            let h = width * img.size.height / img.size.width
            img.draw(in: NSRect(x: x, y: H - top - h, width: width, height: h), from: .zero, operation: .sourceOver, fraction: alpha)
        }

        func mascot(_ img: NSImage, x: CGFloat, top: CGFloat, width: CGFloat, sticker: Bool = true) {
            image(img, x: x, top: top, width: width)
            if sticker { heart(at: NSPoint(x: x + width * 0.559, y: top + width * 0.72), size: width * 0.187) }
        }

        func ribbon(_ slogan: String) {
            let band = NSRect(x: 0, y: 0, width: PosterArt.size.width, height: 96)
            NSColor(rgb: (0.78, 0.2, 0.17)).setFill(); band.fill()
            NSColor(rgb: (0.98, 0.84, 0.4)).setFill()
            NSRect(x: 0, y: 92, width: PosterArt.size.width, height: 4).fill()
            NSRect(x: 0, y: 0, width: PosterArt.size.width, height: 4).fill()
            let face = NSFontManager.shared.convert(font(46), toHaveTrait: .italicFontMask)
            say(slogan, face, .white, x: 56, top: H - 82, kern: 2)
            let c = NSPoint(x: 1112, y: 48)
            let ring = NSBezierPath(ovalIn: NSRect(x: c.x - 38, y: c.y - 38, width: 76, height: 76))
            ring.lineWidth = 3; NSColor(rgb: (0.98, 0.84, 0.4)).setStroke(); ring.stroke()
            let inner = NSBezierPath(ovalIn: NSRect(x: c.x - 31, y: c.y - 31, width: 62, height: 62))
            inner.lineWidth = 1.5; inner.stroke()
            for (k, w) in ["STATION", "MORALE", "OFFICE"].enumerated() {
                say(w, font(13, .heavy), NSColor(rgb: (0.98, 0.84, 0.4)), x: c.x, top: H - c.y - 25 + CGFloat(k) * 15, align: .center, kern: 1)
            }
        }

        func card(x: CGFloat, top: CGFloat, width: CGFloat, height: CGFloat, tint: NSColor) {
            let r = NSRect(x: x, y: H - top - height, width: width, height: height)
            let path = NSBezierPath(roundedRect: r, xRadius: 34, yRadius: 34)
            NSGradient(starting: tint.withAlphaComponent(0.28), ending: tint.withAlphaComponent(0.06))?.draw(in: path, angle: -90)
            path.lineWidth = 4
            glow(tint, radius: 14) { tint.withAlphaComponent(0.9).setStroke(); path.stroke() }
        }
    }

    static func paint(_ base: NSImage?, _ body: (Ink) -> Void) -> NSImage {
        let out = NSImage(size: size)
        out.lockFocus()
        if let base { base.draw(in: NSRect(origin: .zero, size: size)) } else { sky.setFill(); NSRect(origin: .zero, size: size).fill() }
        body(Ink(H: size.height))
        out.unlockFocus()
        return out
    }

    // MARK: the yard: pack, test, ship

    static func yard() -> NSImage {
        let scene = sideScene(floor: true)
        let bands: [NSColor] = [NSColor(rgb: (0.3, 0.32, 0.38)), amber, green]
        for (k, band) in bands.enumerated() {
            let c = Props.package(color: repo, band: band, size: 0.38)
            c.position = v3(-1.2 + Double(k) * 0.85, 0, 0)
            c.scale = SCNVector3(1.4, 1.4, 1.4)
            scene.rootNode.addChildNode(c)
            if k > 0 { glowLight(scene, band, at: v3(-1.2 + Double(k) * 0.85, 0.25, 0.55)) }
        }
        let ship = Looks.current.rocket(color: repo, tall: true, cargo: 0)
        Props.nameRocket(ship, repo: "web", color: repo)
        ship.position = v3(1.2, 1.6, -0.25)
        ship.scale = SCNVector3(0.72, 0.72, 0.72)
        ship.childNode(withName: "flame", recursively: true)?.opacity = 1
        ship.enumerateHierarchy { n, _ in n.castsShadow = false }
        scene.rootNode.addChildNode(ship)
        glowLight(scene, NSColor(rgb: (1.0, 0.6, 0.3)), at: v3(1.2, 1.35, 0.3), intensity: 900, reach: 1.6)
        let base = snapshot(scene, from: sideEye(scene), size: size)
        let hero = mascot(grounded: true)
        return paint(base) { k in
            let crate: [CGFloat] = [145, 462, 778]
            k.mascot(hero, x: 805, top: 1014, width: 460)
            k.say("PACK,", k.font(170), ink, x: 64, top: 70, kern: 3)
            k.say("TEST,", k.font(170), amber, x: 64, top: 250, kern: 3)
            k.say("SHIP.", k.font(170), green, x: 64, top: 430, kern: 3)
            k.hop(NSPoint(x: crate[0] + 30, y: 990), NSPoint(x: crate[1] - 30, y: 990), lift: 200, color: ink)
            k.hop(NSPoint(x: crate[1] + 30, y: 990), NSPoint(x: crate[2] - 30, y: 990), lift: 150, color: amber)
            k.arrow(NSPoint(x: crate[2] + 30, y: 990), NSPoint(x: 960, y: 990), NSPoint(x: 1038, y: 900), NSPoint(x: 1038, y: 742), color: green)
            k.say("TO STAGING", k.font(30, .heavy), ink, x: (crate[0] + crate[1]) / 2, top: 788, align: .center, kern: 4)
            k.say("TESTED", k.font(30, .heavy), amber, x: (crate[1] + crate[2]) / 2, top: 826, align: .center, kern: 4)
            k.say("LAUNCH", k.font(30, .heavy), green, x: 1118, top: 840, align: .center, kern: 4)
            k.bracket(from: 350, to: 890, top: 1305, color: quiet, word: "SHIPS")
            for (word, color, x) in [("WAITING", NSColor(white: 0.8, alpha: 1), crate[0]), ("TESTING", amber, crate[1]), ("CLEARED", green, crate[2])] {
                k.say(word, k.font(40, .heavy), color, x: x, top: 1232, align: .center, kern: 5)
            }
            k.ribbon("Untested? It flies anyway! Isn't space grand?")
        }
    }

    // MARK: shapes: a legend

    static func shapes() -> NSImage {
        let cube = SCNNode()
        let solid = Props.cube(color: repo, size: 0.3, shadow: sky)
        solid.position = v3(-0.2, 0.15, 0)
        let ghost = Props.cube(color: repo, size: 0.3, shadow: sky)
        ghost.position = v3(0.22, 0.15, 0.05)
        ghost.opacity = Props.ghostOpacity
        cube.addChildNode(solid); cube.addChildNode(ghost)
        let crate = Props.package(color: repo, band: green, size: 0.38)
        let cone = Props.pyramid(color: repo.lighter(0.22), size: 0.32, floor: sky)
        let rows: [(NSImage, String, String, NSColor)] = [
            (object(cube, yaw: -0.35), "COMMIT", "The ghost is not committed yet", ink),
            (object(crate), "PULL REQUEST", "Its light shows the checks", green),
            (object(cone), "YOUR MESSAGE", "What its minion is working on", repo.lighter(0.22)),
        ]
        let hero = mascot()
        return paint(nil) { k in
            stars(k)
            k.say("WHAT'S", k.font(170), ink, x: 64, top: 70, kern: 3)
            k.say("WHAT.", k.font(170), repo, x: 64, top: 250, kern: 3)
            k.mascot(hero, x: 760, top: 40, width: 400)
            for (i, row) in rows.enumerated() {
                let top = 540 + CGFloat(i) * 310
                k.glow(row.3.withAlphaComponent(0.6), radius: 40) {
                    row.3.withAlphaComponent(0.12).setFill()
                    NSBezierPath(ovalIn: NSRect(x: 90, y: k.H - top - 270, width: 280, height: 70)).fill()
                }
                k.image(row.0, x: 60, top: top - 10, width: 340)
                k.say(row.1, k.font(100), row.3, x: 450, top: top + 70, kern: 2)
                k.say(row.2, k.font(38, .medium), dim, x: 454, top: top + 190)
            }
            k.ribbon("Every commit counts!")
        }
    }

    // MARK: the crew: three cards

    static func crew() -> NSImage {
        let atWork = mascot(.working)
        let cone = object(Props.pyramid(color: repo.lighter(0.22), size: 0.32, floor: sky), pixels: 400)
        let waitingFor = mascot(.waiting)
        let dozing = mascot(.dozing)
        let cards: [(NSImage, String, String, String, NSColor, Bool)] = [
            (atWork, "AT WORK", "", "Its cone is the job", working, true),
            (waitingFor, "WAITING", "FOR YOU", "No cone: your turn", waiting, false),
            (dozing, "ASLEEP", "", "After quiet minutes", sleeping, false),
        ]
        return paint(nil) { k in
            stars(k)
            k.say("NO CONE?", k.font(150), ink, x: 64, top: 50, kern: 3)
            k.say("YOUR TURN.", k.font(150), waiting, x: 64, top: 210, kern: 3)
            for (i, c) in cards.enumerated() {
                let x = 50 + CGFloat(i) * 375
                k.card(x: x, top: 420, width: 350, height: 1000, tint: c.4)
                k.mascot(c.0, x: x - 40, top: 470, width: 430, sticker: c.5)
                k.say(c.1, k.font(76), c.4, x: x + 175, top: 1150, align: .center, kern: 3)
                if !c.2.isEmpty { k.say(c.2, k.font(76), c.4, x: x + 175, top: 1230, align: .center, kern: 3) }
                k.say(c.3, k.font(34, .medium), dim, x: x + 175, top: c.2.isEmpty ? 1250 : 1330, align: .center)
            }
            k.image(cone, x: 60, top: 880, width: 150)
            k.straight(NSPoint(x: 570, y: 1030), NSPoint(x: 470, y: 1030), color: waiting.withAlphaComponent(0.85), width: 7)
            k.straight(NSPoint(x: 630, y: 1030), NSPoint(x: 730, y: 1030), color: waiting.withAlphaComponent(0.85), width: 7)
            for (j, z) in ["z", "z", "Z"].enumerated() {
                k.say(z, k.font(46 + CGFloat(j) * 20), sleeping, x: 1010 + CGFloat(j) * 40, top: 610 - CGFloat(j) * 66)
            }
            k.ribbon("A pacing minion misses you!")
        }
    }

    // MARK: the rocket: a callout diagram

    static func rocket() -> NSImage {
        let scene = sideScene(floor: false)
        let ship = Looks.current.rocket(color: repo, tall: true, cargo: 0)
        Props.nameRocket(ship, repo: "web", color: repo)
        let lamp = SCNNode(geometry: SCNSphere(radius: 0.035))
        lamp.geometry!.firstMaterial = flat(Props.amberLamp)
        lamp.geometry!.firstMaterial!.emission.contents = Props.amberLamp
        lamp.position = v3(0, Double(ship.boundingBox.max.y) + 0.025, 0)
        lamp.scale = SCNVector3(1.6, 1.6, 1.6)
        ship.addChildNode(lamp)
        ship.position = v3(0.55, 0, -0.25)
        ship.scale = SCNVector3(1.45, 1.45, 1.45)
        scene.rootNode.addChildNode(ship)
        glowLight(scene, Props.amberLamp, at: v3(0.55, 3.0, 0.5), intensity: 500, reach: 1.0)
        glowLight(scene, NSColor(rgb: (1.0, 0.95, 0.9)), at: v3(0.55, 0.2, 1.2), intensity: 700, reach: 2.2)
        let base = snapshot(scene, from: sideEye(scene, scale: 2.15, centre: SIMD2(0.02, 1.45)), size: size)
        let hero = mascot()
        return paint(base) { k in
            k.say("MERGE WHEN", k.font(130), ink, x: 64, top: 60, kern: 3)
            k.say("IT VENTS.", k.font(130), repo, x: 64, top: 200, kern: 3)
            for (x, y, r) in [(905.0, 1255.0, 46.0), (870, 1205, 34), (845, 1160, 24), (1095, 1250, 44), (1130, 1198, 32), (1150, 1150, 22)] as [(CGFloat, CGFloat, CGFloat)] {
                k.glow(.white, radius: 22) {
                    NSColor(white: 1, alpha: 0.85).setFill()
                    NSBezierPath(ovalIn: NSRect(x: x - r, y: k.H - y - r, width: r * 2, height: r * 2)).fill()
                }
            }
            k.callout(from: NSPoint(x: 1150, y: 1150), to: NSPoint(x: 1150, y: 1395), end: NSPoint(x: 960, y: 1395), color: ink)
            k.say("VENTING: GO", k.font(48), ink, x: 940, top: 1370, align: .right, kern: 3)
            k.callout(from: NSPoint(x: 790, y: 300), to: NSPoint(x: 560, y: 520), end: NSPoint(x: 390, y: 520), color: Props.amberLamp)
            k.say("NOSE LAMP", k.font(56), Props.amberLamp, x: 64, top: 488, kern: 3)
            k.say("Amber while staging builds", k.font(34, .medium), dim, x: 66, top: 560)
            k.callout(from: NSPoint(x: 780, y: 700), to: NSPoint(x: 560, y: 790), end: NSPoint(x: 390, y: 790), color: ink)
            k.say("TIP", k.font(56), ink, x: 64, top: 758, kern: 3)
            k.say("The staging release", k.font(34, .medium), dim, x: 66, top: 830)
            k.callout(from: NSPoint(x: 790, y: 1150), to: NSPoint(x: 560, y: 1060), end: NSPoint(x: 390, y: 1060), color: repo)
            k.say("KICK STAGE", k.font(56), repo, x: 64, top: 1028, kern: 3)
            k.say("The production release", k.font(34, .medium), dim, x: 66, top: 1100)
            k.mascot(hero, x: 50, top: 1100, width: 300)
            k.ribbon("A venting rocket is a happy rocket!")
        }
    }

    // MARK: decon: a fork

    static func decon() -> NSImage {
        func object(_ tint: NSColor = repo) -> SCNNode {
            Props.package(color: Palette.alien.darker(0.3).mixed(with: tint.darker(0.3), 0.35), band: Palette.alienLight.darker(0.3), size: 0.3)
        }
        let pile = SCNNode()
        for (k, at) in [SIMD3(-0.17, 0.0, 0.0), SIMD3(0.17, 0.0, 0.02), SIMD3(0.0, 0.3, 0.01)].enumerated() {
            let o = object(Colors.repos.count > k ? NSColor(Colors.repos[k]) : repo)
            o.position = v3(at.x, at.y, at.z)
            pile.addChildNode(o)
        }
        let stack = PosterArt.object(pile, yaw: -0.5, pixels: 700)
        let merged = PosterArt.object(object(), yaw: -0.5, pixels: 400)
        let ejected = PosterArt.object(object(), yaw: 0.9, pitch: -0.9, pixels: 400)
        let hero = mascot()
        return paint(nil) { k in
            stars(k)
            k.say("UNKNOWN", k.font(170), ink, x: 64, top: 70, kern: 3)
            k.say("OBJECTS.", k.font(170), Palette.alienLight, x: 64, top: 250, kern: 3)
            k.say("A full decon is bot updates waiting for you", k.font(44, .medium), dim, x: 68, top: 460)
            k.glow(Palette.alienLight, radius: 30) {
                Palette.alienLight.withAlphaComponent(0.08).setFill()
                let room = NSBezierPath(roundedRect: NSRect(x: 330, y: k.H - 1060, width: 540, height: 470), xRadius: 30, yRadius: 30)
                room.fill()
                Palette.alienLight.withAlphaComponent(0.7).setStroke(); room.lineWidth = 4; room.stroke()
            }
            k.say("DECON", k.font(40, .heavy), Palette.alienLight.withAlphaComponent(0.8), x: 600, top: 610, align: .center, kern: 8)
            k.image(stack, x: 360, top: 600, width: 480)
            k.straight(NSPoint(x: 470, y: 1080), NSPoint(x: 340, y: 1180), color: green)
            k.straight(NSPoint(x: 730, y: 1080), NSPoint(x: 860, y: 1180), color: quiet.lighter(0.5))
            k.image(merged, x: 170, top: 1150, width: 220)
            k.say("MERGED", k.font(56), green, x: 280, top: 1345, align: .center, kern: 3)
            k.say("Into storage, tested", k.font(32, .medium), dim, x: 280, top: 1414, align: .center)
            k.image(ejected, x: 820, top: 1130, width: 200, alpha: 0.55)
            k.say("CLOSED", k.font(56), NSColor(white: 0.75, alpha: 1), x: 920, top: 1345, align: .center, kern: 3)
            k.say("Ejected, forgotten", k.font(32, .medium), dim, x: 920, top: 1414, align: .center)
            k.ribbon("An empty decon is a happy decon!")
            k.mascot(hero, x: 880, top: 520, width: 300)
        }
    }

    // MARK: mission control: one dial

    static func mission() -> NSImage {
        let hero = mascot()
        let states: [(String, NSColor)] = [("CALM", NSColor(white: 0.85, alpha: 1)), ("FLYING", working), ("READY", green),
                                           ("TESTING", amber), ("HOLDING", NSColor(rgb: (1.0, 0.5, 0.2))), ("FAILING", Props.failRed)]
        return paint(nil) { k in
            stars(k)
            k.say("EYES ON", k.font(150), ink, x: 64, top: 50, kern: 3)
            k.say("THE NEEDLES.", k.font(150), working, x: 64, top: 210, kern: 3)
            let c = NSPoint(x: 600, y: k.H - 860), r: CGFloat = 400
            let face = NSBezierPath(ovalIn: NSRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
            k.glow(working, radius: 40) { NSColor(rgb: (0.93, 0.9, 0.82)).setFill(); face.fill() }
            face.lineWidth = 26; NSColor(rgb: (0.55, 0.58, 0.62)).setStroke(); face.stroke()
            let arc0: CGFloat = 200, arc1: CGFloat = -20
            for (i, st) in states.enumerated() {
                let a0 = arc0 + (arc1 - arc0) * CGFloat(i) / 6, a1 = arc0 + (arc1 - arc0) * CGFloat(i + 1) / 6
                let band = NSBezierPath()
                band.appendArc(withCenter: c, radius: r - 70, startAngle: a0, endAngle: a1, clockwise: true)
                band.lineWidth = 50; st.1.setStroke(); band.stroke()
                let mid = (a0 + a1) / 2 * .pi / 180
                let at = NSPoint(x: c.x + cos(mid) * (r - 165), y: c.y + sin(mid) * (r - 165))
                k.say(st.0, k.font(40, .heavy), NSColor(rgb: (0.12, 0.13, 0.16)), x: at.x, top: k.H - at.y - 24, align: .center, kern: 2)
            }
            for t in 0...30 {
                let a = (arc0 + (arc1 - arc0) * CGFloat(t) / 30) * .pi / 180
                let tick = NSBezierPath()
                tick.move(to: NSPoint(x: c.x + cos(a) * (r - 30), y: c.y + sin(a) * (r - 30)))
                tick.line(to: NSPoint(x: c.x + cos(a) * (r - (t % 5 == 0 ? 52 : 42)), y: c.y + sin(a) * (r - (t % 5 == 0 ? 52 : 42))))
                tick.lineWidth = t % 5 == 0 ? 5 : 2.5; NSColor(rgb: (0.12, 0.13, 0.16)).setStroke(); tick.stroke()
            }
            let needle = (arc0 - 14) * .pi / 180
            let n = NSBezierPath()
            n.move(to: NSPoint(x: c.x + cos(needle) * (r - 60), y: c.y + sin(needle) * (r - 60)))
            n.line(to: NSPoint(x: c.x + cos(needle + .pi / 2) * 14, y: c.y + sin(needle + .pi / 2) * 14))
            n.line(to: NSPoint(x: c.x - cos(needle) * 60, y: c.y - sin(needle) * 60))
            n.line(to: NSPoint(x: c.x + cos(needle - .pi / 2) * 14, y: c.y + sin(needle - .pi / 2) * 14))
            n.close()
            NSColor(rgb: (0.78, 0.2, 0.17)).setFill(); n.fill()
            NSColor(rgb: (0.2, 0.21, 0.24)).setFill(); NSBezierPath(ovalIn: NSRect(x: c.x - 30, y: c.y - 30, width: 60, height: 60)).fill()
            k.say("MOST URGENT", k.font(34, .heavy), NSColor(rgb: (0.12, 0.13, 0.16)), x: c.x, top: k.H - c.y + 70, align: .center, kern: 3)
            k.say("THING TRUE OF IT", k.font(34, .heavy), NSColor(rgb: (0.12, 0.13, 0.16)), x: c.x, top: k.H - c.y + 110, align: .center, kern: 3)
            k.say("One gauge per repository, most urgent first", k.font(40, .medium), dim, x: 600, top: 1300, align: .center)
            let screen = NSRect(x: 70, y: k.H - 1470, width: 300, height: 120)
            NSColor(rgb: (0.04, 0.05, 0.06)).setFill(); NSBezierPath(roundedRect: screen, xRadius: 14, yRadius: 14).fill()
            k.glow(Props.failRed, radius: 12) { k.say("NO SIGNAL", k.font(40, .heavy), Props.failRed, x: 220, top: 1378, align: .center, kern: 4) }
            k.say("Alarm screen: feed it", k.font(28, .medium), dim, x: 220, top: 1425, align: .center)
            k.mascot(hero, x: 880, top: 1090, width: 300)
            k.ribbon("All needles point to calm! (Mostly.)")
        }
    }

    // MARK: the lounge: the real bubble

    static func lounge() -> NSImage {
        let hero = mascot()
        let choices: [(String, String)] = [("dumbbell.fill", "GYM"), ("bed.double.fill", "NAP"), ("book.fill", "BOOK"), ("shower.fill", "SHOWER"),
                                           ("toilet.fill", "TOILET"), ("cup.and.saucer.fill", "COFFEE"), ("fork.knife", "BITE")]
        return paint(nil) { k in
            stars(k)
            k.say("LEISURE IS", k.font(150), ink, x: 64, top: 50, kern: 3)
            k.say("MANDATORY!", k.font(150), repo, x: 64, top: 210, kern: 3)
            k.mascot(hero, x: 70, top: 560, width: 470)
            let bubble = NSRect(x: 560, y: k.H - 1150, width: 580, height: 560)
            let path = NSBezierPath(roundedRect: bubble, xRadius: 40, yRadius: 40)
            path.move(to: NSPoint(x: 600, y: k.H - 1150 + 120)); path.line(to: NSPoint(x: 470, y: k.H - 1150 + 40)); path.line(to: NSPoint(x: 600, y: k.H - 1150 + 60))
            k.glow(.white, radius: 24) { NSColor(white: 0.97, alpha: 1).setFill(); path.fill() }
            k.say("What next?", k.font(44, .heavy), NSColor(rgb: (0.12, 0.13, 0.16)), x: 850, top: 625, align: .center)
            let config = NSImage.SymbolConfiguration(pointSize: 70, weight: .semibold)
            for (i, ch) in choices.enumerated() {
                let col = CGFloat(i % 3), row = CGFloat(i / 3)
                let cx = 660 + col * 190, top = 720 + row * 140
                let on = ch.1 == "COFFEE"
                if on {
                    k.glow(repo, radius: 20) { repo.setFill(); NSBezierPath(roundedRect: NSRect(x: cx - 80, y: k.H - top - 128, width: 160, height: 132), xRadius: 24, yRadius: 24).fill() }
                }
                if let icon = NSImage(systemSymbolName: ch.0, accessibilityDescription: nil)?.withSymbolConfiguration(config) {
                    let tinted = NSImage(size: icon.size, flipped: false) { r in
                        icon.draw(in: r); (on ? NSColor.white : NSColor(rgb: (0.2, 0.22, 0.27))).set(); r.fill(using: .sourceAtop); return true
                    }
                    let w = icon.size.width, h = icon.size.height
                    tinted.draw(in: NSRect(x: cx - w / 2, y: k.H - top - 10 - h, width: w, height: h))
                }
                k.say(ch.1, k.font(24, .heavy), on ? .white : NSColor(rgb: (0.35, 0.37, 0.42)), x: cx, top: top + 92, align: .center, kern: 2)
            }
            if let arrow = NSImage(systemSymbolName: "cursorarrow", accessibilityDescription: nil)?.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 90, weight: .regular)) {
                k.glow(.black, radius: 8) { arrow.draw(in: NSRect(x: 1010, y: k.H - 1095 - arrow.size.height, width: arrow.size.width, height: arrow.size.height)) }
            }
            k.say("Hover a resting minion, pick its next thing", k.font(48, .heavy), ink, x: 600, top: 1300, align: .center, kern: 1)
            k.say("Busy ones tell you what they are busy with", k.font(34, .medium), dim, x: 600, top: 1380, align: .center)
            k.ribbon("Rest hard. Work harder.")
        }
    }

    // MARK: the galley: a commercial

    static func galley() -> NSImage {
        let noodles = SCNNode()
        let dish = Kitchen.bowl()
        noodles.addChildNode(dish.bowl)
        if dish.food.parent == nil { noodles.addChildNode(dish.food) }
        let meal = object(noodles, yaw: -0.4, pitch: -0.55, pixels: 600, margin: 1.3)
        let mug = Kitchen.mug()
        let cup = object(mug, yaw: -0.5, pitch: -0.25, pixels: 600, margin: 1.4)
        return paint(nil) { k in
            stars(k)
            k.glow(amber, radius: 60) {
                amber.withAlphaComponent(0.1).setFill()
                NSBezierPath(ovalIn: NSRect(x: 100, y: k.H - 1180, width: 1000, height: 700)).fill()
            }
            k.say("PRINTED", k.font(170), ink, x: 64, top: 50, kern: 3)
            k.say("FRESH!", k.font(170), amber, x: 64, top: 230, kern: 3)
            k.image(cup, x: 60, top: 520, width: 520)
            k.image(meal, x: 600, top: 600, width: 520)
            for (i, x) in [230.0, 290, 350].enumerated() as EnumeratedSequence<[CGFloat]> {
                let curl = NSBezierPath()
                curl.move(to: k.p(x, 700))
                curl.curve(to: k.p(x + 10, 520 - CGFloat(i) * 20), controlPoint1: k.p(x - 50, 640), controlPoint2: k.p(x + 60, 580))
                curl.lineWidth = 12; curl.lineCapStyle = .round
                k.glow(.white, radius: 16) { NSColor(white: 1, alpha: 0.75).setStroke(); curl.stroke() }
            }
            let c = NSPoint(x: 1010, y: k.H - 420)
            let burst = NSBezierPath()
            for j in 0..<32 {
                let a = CGFloat(j) / 32 * 2 * .pi, rr: CGFloat = j % 2 == 0 ? 150 : 118
                let pt = NSPoint(x: c.x + cos(a) * rr, y: c.y + sin(a) * rr)
                if j == 0 { burst.move(to: pt) } else { burst.line(to: pt) }
            }
            burst.close()
            k.glow(Props.failRed, radius: 20) { NSColor(rgb: (0.92, 0.22, 0.18)).setFill(); burst.fill() }
            k.say("NEW!", k.font(64), .white, x: c.x, top: k.H - c.y - 70, align: .center, kern: 2)
            k.say("0% REAL BEANS", k.font(24, .heavy), .white, x: c.x, top: k.H - c.y + 6, align: .center, kern: 1)
            let menu = NSRect(x: 120, y: k.H - 1460, width: 960, height: 290)
            NSColor(rgb: (0.07, 0.08, 0.1)).setFill(); NSBezierPath(roundedRect: menu, xRadius: 20, yRadius: 20).fill()
            let rim = NSBezierPath(roundedRect: menu, xRadius: 20, yRadius: 20); rim.lineWidth = 4
            k.glow(amber, radius: 12) { amber.setStroke(); rim.stroke() }
            for (i, row) in [("COFFEE", "ALL DAY"), ("NOODLES", "11–14 · 18–20"), ("LIGHTS OUT", "22–07")].enumerated() {
                let top = 1200 + CGFloat(i) * 84
                k.say(row.0, k.font(54, .heavy), ink, x: 170, top: top, kern: 3)
                k.say(row.1, k.font(54, .heavy), amber, x: 1030, top: top, align: .right, kern: 3)
            }
            k.ribbon("Now with 0% real beans!")
        }
    }

    // MARK: the bath: a timeline

    static func bath() -> NSImage {
        let hero = mascot { root in
            let turn = SCNNode()
            turn.eulerAngles.y = -0.45
            let shower = Classic.shower(Bulkhead.steel)
            shower.position = v3(0, 0.16, -Hands.arm - 0.04)
            turn.addChildNode(shower)
            let rain = Props.glowing(NSColor(rgb: (0.55, 0.85, 1.0)), alpha: 0.75)
            var g = Textures.Seeded(s: 5)
            for _ in 0..<26 {
                let drop = SCNNode(geometry: SCNBox(width: 0.004, height: 0.06 + g.next() * 0.06, length: 0.004, chamferRadius: 0))
                drop.geometry!.firstMaterial = rain
                drop.position = v3((g.next() - 0.5) * 0.18, 0.56 + g.next() * 0.22, (g.next() - 0.5) * 0.14 - 0.03)
                turn.addChildNode(drop)
            }
            root.addChildNode(turn)
        }
        let water = NSColor(rgb: (0.45, 0.78, 1.0))
        return paint(nil) { k in
            stars(k)
            k.say("SQUEAKY CLEAN,", k.font(130), ink, x: 64, top: 50, kern: 3)
            k.say("SUPER KEEN!", k.font(130), water, x: 64, top: 190, kern: 3)
            k.mascot(hero, x: 260, top: 330, width: 680)
            var g = Textures.Seeded(s: 11)
            for _ in 0..<16 {
                let x = 80 + CGFloat(g.next()) * 1040, y = 380 + CGFloat(g.next()) * 640, r = CGFloat(10 + g.next() * 28)
                let b = NSBezierPath(ovalIn: NSRect(x: x - r, y: k.H - y - r, width: r * 2, height: r * 2))
                b.lineWidth = 3; NSColor(white: 1, alpha: 0.6).setStroke(); b.stroke()
                NSColor(white: 1, alpha: 0.85).setFill()
                NSBezierPath(ovalIn: NSRect(x: x - r * 0.45, y: k.H - y + r * 0.2, width: r * 0.35, height: r * 0.35)).fill()
            }
            let y: CGFloat = 1190
            func bar(_ x0: CGFloat, _ x1: CGFloat, _ color: NSColor) {
                let r = NSRect(x: x0, y: k.H - y - 50, width: x1 - x0, height: 50)
                k.glow(color, radius: 16) { color.setFill(); NSBezierPath(roundedRect: r, xRadius: 25, yRadius: 25).fill() }
            }
            bar(70, 760, working)
            bar(785, 960, water)
            bar(985, 1130, NSColor(white: 0.85, alpha: 1))
            k.say("20+ MIN OF WORK", k.font(40, .heavy), NSColor(rgb: (0.06, 0.1, 0.12)), x: 415, top: y + 2, align: .center, kern: 2)
            k.say("2–3", k.font(40, .heavy), NSColor(rgb: (0.06, 0.1, 0.12)), x: 872, top: y + 2, align: .center)
            k.say("TOWEL", k.font(30, .heavy), NSColor(rgb: (0.06, 0.1, 0.12)), x: 1057, top: y + 8, align: .center)
            k.say("A minion in the shower just worked hard", k.font(46, .heavy), ink, x: 600, top: 1290, align: .center, kern: 1)
            k.say("Never while busy: work calls, it leaves at once", k.font(34, .medium), dim, x: 600, top: 1360, align: .center)
            k.ribbon("Hygiene is productivity!")
        }
    }

    // MARK: the bay: arrivals

    static func bay() -> NSImage {
        let ship = SCNNode()
        let hull = Classic.shuttle(color: repo)
        ship.addChildNode(hull)
        let office = Props.crate(color: repo)
        office.position = v3(0, -0.42, 0)
        ship.addChildNode(office)
        let craft = object(ship, yaw: -0.5, pitch: -0.3, pixels: 700, margin: 1.15)
        let hero = mascot()
        return paint(nil) { k in
            stars(k)
            k.say("NEW WORK", k.font(150), ink, x: 64, top: 50, kern: 3)
            k.say("LANDS HERE.", k.font(150), repo, x: 64, top: 210, kern: 3)
            k.image(craft, x: 90, top: 380, width: 620)
            let berth = NSRect(x: 160, y: k.H - 1040, width: 500, height: 96)
            k.glow(repo, radius: 30) {
                repo.withAlphaComponent(0.25).setFill(); NSBezierPath(ovalIn: berth).fill()
                let rim = NSBezierPath(ovalIn: berth); rim.lineWidth = 8; repo.setStroke(); rim.stroke()
            }
            k.straight(NSPoint(x: 410, y: 860), NSPoint(x: 410, y: 960), color: ink, width: 10, dashed: true)
            k.mascot(hero, x: 740, top: 560, width: 400)
            let board = NSRect(x: 70, y: k.H - 1440, width: 1060, height: 340)
            NSColor(rgb: (0.06, 0.07, 0.09)).setFill(); NSBezierPath(roundedRect: board, xRadius: 22, yRadius: 22).fill()
            let edge = NSBezierPath(roundedRect: board, xRadius: 22, yRadius: 22); edge.lineWidth = 4
            k.glow(.white, radius: 10) { NSColor(white: 0.8, alpha: 1).setStroke(); edge.stroke() }
            k.say("ARRIVALS & DEPARTURES", k.font(34, .heavy), dim, x: 600, top: 1122, align: .center, kern: 6)
            func flap(_ text: String, x: CGFloat, top: CGFloat, color: NSColor) {
                let f = NSFont.monospacedSystemFont(ofSize: 46, weight: .heavy)
                var cx = x
                for ch in text {
                    let tile = NSRect(x: cx, y: k.H - top - 66, width: 40, height: 66)
                    NSColor(rgb: (0.13, 0.14, 0.17)).setFill(); NSBezierPath(roundedRect: tile, xRadius: 5, yRadius: 5).fill()
                    NSColor(white: 0, alpha: 0.6).setFill(); NSRect(x: tile.minX, y: tile.midY - 1, width: tile.width, height: 2).fill()
                    if ch != " " { k.say(String(ch), f, color, x: tile.midX, top: top + 4, align: .center) }
                    cx += 43
                }
            }
            for (i, row) in [("IN ", "NEW SESSION", green), ("IN ", "TEAMMATE'S WORK", green), ("OUT", "SESSION OVER", amber)].enumerated() {
                let top = 1180 + CGFloat(i) * 82
                flap(row.0, x: 110, top: top, color: row.2)
                flap(row.1, x: 290, top: top, color: ink)
            }
            k.ribbon("Every arrival is a party! Mind the field!")
        }
    }

    // MARK: the gym: a circuit

    static func gym() -> NSImage {
        let set = Classic.bench()
        let benchNode = SCNNode()
        set.seat.position = v3(0, Seat.height / 2, 0)
        benchNode.addChildNode(set.seat)
        for up in set.uprights { up.node.position = v3(up.at.x, Classic.rackHeight, up.at.y); benchNode.addChildNode(up.node) }
        set.bar.position = v3(set.chest.x, Classic.barHeight, set.chest.y)
        benchNode.addChildNode(set.bar)
        let tread = Classic.treadmill()
        let (post, sack) = Classic.punchBag()
        let bagNode = SCNNode()
        post.position = v3(0, 0.55, -0.42)
        sack.position = v3(0, 1.08, 0)
        bagNode.addChildNode(post); bagNode.addChildNode(sack)
        let stations: [(NSImage, String, NSColor)] = [
            (object(tread, yaw: -0.7, pixels: 500, margin: 1.2), "TREADMILL", working),
            (object(benchNode, yaw: -0.7, pixels: 500, margin: 1.2), "BENCH", amber),
            (object(bagNode, yaw: -0.7, pixels: 500, margin: 1.15), "BAG", Props.failRed),
            (mascot { root in
                let mat = Classic.mat()
                mat.position = v3(0, -0.012, 0)
                mat.eulerAngles.y = -0.45
                root.addChildNode(mat)
            }, "MAT", green),
        ]
        let punch = NSColor(rgb: (1.0, 0.42, 0.3))
        return paint(nil) { k in
            stars(k)
            k.say("NO PAIN,", k.font(170), ink, x: 64, top: 50, kern: 3)
            k.say("NO MAIN!", k.font(170), punch, x: 64, top: 230, kern: 3)
            for (i, st) in stations.enumerated() {
                let x: CGFloat = i % 2 == 0 ? 80 : 640, top: CGFloat = i < 2 ? 500 : 900
                k.card(x: x, top: top, width: 480, height: 360, tint: st.2)
                if st.1 == "MAT" { k.mascot(st.0, x: x + 120, top: top + 4, width: 240) } else { k.image(st.0, x: x + 100, top: top + 10, width: 280) }
                k.say(st.1, k.font(46, .heavy), st.2, x: x + 240, top: top + 290, align: .center, kern: 4)
            }
            k.say("In the gym? Resting, and free for work", k.font(48, .heavy), ink, x: 600, top: 1300, align: .center, kern: 1)
            k.say("Give it an order: it drops the bar at once", k.font(36, .medium), dim, x: 600, top: 1380, align: .center)
            k.ribbon("Strong minions ship strong code!")
        }
    }

    private static func stars(_ k: Ink) {
        var g = Textures.Seeded(s: 7)
        for _ in 0..<140 {
            let x = CGFloat(g.next()) * size.width, y = CGFloat(g.next()) * size.height, r = CGFloat(0.8 + g.next() * 2.2)
            NSColor(white: 1, alpha: CGFloat(0.25 + g.next() * 0.6)).setFill()
            NSBezierPath(ovalIn: NSRect(x: x, y: y, width: r, height: r)).fill()
        }
    }
}
