import AppKit
import SceneKit
import SpriteKit

/// A showroom: every prop and animation on its own tile, so the look can be judged up close.
final class GalleryController: NSObject, SCNSceneRendererDelegate {
    let view: StationView
    private let scene = SCNScene()
    private let rig = SCNNode()
    private let pitchNode = SCNNode()
    private let cameraNode = SCNNode()
    private var yaw = 0.0, pitch = -Double.pi / 5, zoom = 1.0, pan = SIMD2<Double>(0, 0)
    private var clock = 0.0, lastTime = 0.0
    private var updaters: [(Double, Double) -> Void] = []   // (clock, dt)
    private let drone = Drone()

    init(frame: NSRect) {
        view = StationView(frame: frame, options: [SCNView.Option.preferredRenderingAPI.rawValue: SCNRenderingAPI.metal.rawValue])
        super.init()
        scene.background.contents = Palette.void
        view.scene = scene
        view.backgroundColor = Palette.void
        view.antialiasingMode = .multisampling4X
        view.isPlaying = true
        view.autoresizingMask = [.width, .height]
        view.delegate = self

        let camera = SCNCamera()
        camera.usesOrthographicProjection = true
        camera.orthographicScale = 6
        camera.zNear = 0.1; camera.zFar = 400
        cameraNode.camera = camera
        cameraNode.position = v3(0, 0, 120)
        pitchNode.eulerAngles.x = pitch
        pitchNode.addChildNode(cameraNode)
        rig.eulerAngles.y = .pi / 4
        rig.addChildNode(pitchNode)
        scene.rootNode.addChildNode(rig)
        let sun = SCNNode(); sun.light = SCNLight(); sun.light!.type = .directional; sun.light!.intensity = 700; sun.eulerAngles = v3(-.pi / 3, .pi / 3, 0)
        let ambient = SCNNode(); ambient.light = SCNLight(); ambient.light!.type = .ambient; ambient.light!.intensity = 550
        scene.rootNode.addChildNode(sun); scene.rootNode.addChildNode(ambient)

        view.onZoom = { [weak self] f, _ in self?.zoom = min(8, max(0.3, (self?.zoom ?? 1) * f)) }
        view.onRotate = { [weak self] r, _ in self?.yaw -= r }
        view.onTilt = { [weak self] dy in self?.pitch = min(-0.15, max(-Double.pi / 2 + 0.05, (self?.pitch ?? 0) - dy * 0.004)) }
        view.onPan = { [weak self] dx, dy in
            guard let self else { return }
            let y = Double.pi / 4 + yaw
            let upp = 2 * cameraNode.camera!.orthographicScale / Double(max(1, view.bounds.height))
            pan -= (SIMD2(cos(y), -sin(y)) * dx - SIMD2(-sin(y), -cos(y)) * dy) * upp
        }
        build()
    }

    // MARK: exhibits

    private func tile(_ index: Int, _ title: String) -> SIMD2<Double> {
        let cols = 5
        let x = Double(index % cols) * 3.2, z = Double(index / cols) * 3.4
        let floor = SCNNode(geometry: SCNPlane(width: 2.6, height: 2.6))
        floor.geometry!.firstMaterial = flat(NSColor(rgb: (0.16, 0.17, 0.23)))
        floor.eulerAngles.x = -.pi / 2
        floor.position = v3(x, 0, z)
        scene.rootNode.addChildNode(floor)
        let label = floorText(title, color: Palette.text, size: 0.28, maxWidth: 2.6, lines: 1)
        label.node.position = v3(x - 1.3 + label.width / 2, 0.01, z + 1.5 + label.height / 2)
        scene.rootNode.addChildNode(label.node)
        return SIMD2(x, z)
    }

    private func roomFloor(at p: SIMD2<Double>, color: NSColor, size: Double = 2.0) {
        let f = SCNNode(geometry: SCNPlane(width: size, height: size))
        f.geometry!.firstMaterial = flat(color)
        f.eulerAngles.x = -.pi / 2
        f.position = v3(p.x, 0.003, p.y)
        scene.rootNode.addChildNode(f)
    }

    private func minion(at p: SIMD2<Double>, sub: Bool = false, crew: Bool = false) -> Minion {
        let m = Minion(id: UUID().uuidString, station: "gallery", home: Home(key: "x", name: "x", repo: "x", issue: nil), cwd: "", toolCount: 0, isSubagent: sub, start: Cell(x: 0, y: 0), crew: crew)
        m.pos = p
        m.node.position = v3(p.x, 0, p.y)
        m.node.opacity = 1
        scene.rootNode.addChildNode(m.node)
        return m
    }

    private func pose(_ m: Minion, activity: Activity, t: Double) -> (Double, Double, Double) {
        switch activity {
        case .coding: return (sin(t * 14) * 0.06, 0, 0)
        case .exploring: return (0, 0, sin(t * 1.2) * 0.7)
        case .writing: return (sin(t * 3) * 0.1, 0, 0)
        case .thinking: return (0, sin(t * 2) * 0.12, 0)
        case .planning: return (-0.12 + sin(t * 2) * 0.05, 0, 0)
        case .reading: return (-0.18, 0, 0)
        case .testing: return (0.1, 0, sin(t * 1.6) * 0.6)
        case .running: return (sin(t * 22) * 0.04, cos(t * 19) * 0.04, 0)
        case .shipping: return (0, sin(t * 9) * 0.16, 0)
        case .skill: return (0.15, sin(t * 3) * 0.05, 0)
        case .delegating: return (0, 0, sin(t * 4) * 0.3)
        case .qa: return (0.28 + sin(t * 1.2) * 0.08, 0, sin(t * 0.6) * 0.5)
        default: return (0, sin(t * 5) * 0.07, 0)
        }
    }

    private func build() {
        let pink = NSColor(Colors.repos[0]), teal = NSColor(Colors.repos[1]), amber = NSColor(Colors.repos[2])
        var i = 0

        // 1. walking
        do {
            let p = tile(i, "walking"); i += 1
            let m = minion(at: p)
            updaters.append { c, _ in
                let s = sin(c * 1.2)
                m.node.position = v3(p.x + s * 0.9, 0, p.y)
                m.node.eulerAngles.y = cos(c * 1.2) >= 0 ? .pi / 2 : -.pi / 2
            }
        }
        // 2. a night's sleep, end to end
        do {
            let p = tile(i, "walk in / turn / sit / lie / rise / walk off"); i += 1
            roomFloor(at: p, color: NSColor(Colors.quarters))
            let bunk = Looks.current.bed(level: 0)
            bunk.position = v3(p.x, 0, p.y)
            scene.rootNode.addChildNode(bunk)
            let m = minion(at: p)

            // Going to bed and getting up are the same moves in opposite orders. It comes to the side of
            // the bunk, turns its back on it, sits on the edge, and swings round into line as it stretches
            // out; getting up it swings back out of line onto the edge, stands, and walks off as it faces.
            // It stops at the bunk's edge, which is 0.17 out from the middle of a bed 0.34 across: that
            // is where its feet go, and sitting puts the rest of it back onto the mattress behind them.
            let side = p.x + 0.17, off = p.x + 1.3
            let onEdge = p.y + 0.1, along = p.y             // where it sits, and where it lies
            let sat = Minion.Pose.seated(height: Minion.bedSeat, at: SIMD2(0, 0))
            let toBed = -Double.pi / 2, offBed = Double.pi / 2, inLine = 0.0
            let walkIn = 1.5, turns = walkIn + 0.5, sitDown = turns + 0.5, lieBack = sitDown + 0.8
            let wakes = lieBack + 2.6, sitsUp = wakes + 0.8, stands = sitsUp + 0.5
            let walksOff = stands + 1.5, loop = walksOff + 0.7
            func ease(_ a: Double, _ b: Double, _ t: Double) -> Double {
                let e = min(1, max(0, t)); return a + (b - a) * (e * e * (3 - 2 * e))
            }
            updaters.append { c, _ in
                let t = c.truncatingRemainder(dividingBy: loop)
                var x = off, z = onEdge, yaw = toBed, pose = Minion.Pose.standing
                switch t {
                case ..<walkIn:   x = ease(off, side, t / walkIn)
                case ..<turns:    x = side; yaw = ease(toBed, offBed, (t - walkIn) / (turns - walkIn))
                case ..<sitDown:  x = side; yaw = offBed; pose = sat
                case ..<lieBack:  // a quarter turn into the bed's line as it stretches out
                                  let k = (t - sitDown) / (lieBack - sitDown)
                                  x = ease(side, p.x, k); z = ease(onEdge, along, k)
                                  yaw = ease(offBed, inLine, k); pose = .flat(height: Minion.bedSeat)
                case ..<wakes:    x = p.x; z = along; yaw = inLine; pose = .flat(height: Minion.bedSeat)
                case ..<sitsUp:   // and back out of it, onto the edge
                                  let k = (t - wakes) / (sitsUp - wakes)
                                  x = ease(p.x, side, k); z = ease(along, onEdge, k)
                                  yaw = ease(inLine, offBed, k); pose = sat
                case ..<stands:   x = side; yaw = offBed
                case ..<walksOff: x = ease(side, off, (t - stands) / (walksOff - stands)); yaw = offBed
                default:          x = off; yaw = offBed
                }
                m.node.position = v3(x, 0, z)
                m.node.eulerAngles.y = CGFloat(yaw)
                m.node.opacity = t > walksOff ? 0 : 1
                m.setPose(pose)
            }
        }
        // 3. working routines
        for act in [Activity.coding("x"), .exploring, .thinking, .writing, .testing, .shipping, .qa, .waiting] {
            let p = tile(i, act == .waiting ? "waiting (jump)" : act.label); i += 1
            let m = minion(at: p)
            switch act {
            case .testing: m.setTool(.scanner)
            case .coding, .exploring, .writing, .qa: m.setTool(.tablet)
            default: break
            }
            updaters.append { [weak self] c, _ in
                guard let self else { return }
                if act == .waiting { m.node.position = v3(p.x, abs(sin(c * 7)) * 0.14, p.y); return }
                let (tilt, roll, spin) = pose(m, activity: act, t: c)
                m.node.eulerAngles = SCNVector3(0, spin, 0)
                m.tilt.eulerAngles = SCNVector3(tilt, 0, roll)
            }
        }
        // 4. at the cone: the four tools
        for (k, name) in ["welding", "hammering", "push / pull", "bent over"].enumerated() {
            let p = tile(i, name); i += 1
            roomFloor(at: p, color: pink)
            let cn = Props.pyramid(color: pink.lighter(0.22), size: 0.32, floor: pink); cn.position = v3(p.x + 0.2, 0, p.y)
            scene.rootNode.addChildNode(cn)
            let m = minion(at: SIMD2(p.x - 0.2, p.y)); m.node.eulerAngles.y = .pi / 2
            m.setTool([Minion.Tool.goggles, .hammer, .scanner, nil][k])
            var light: SCNNode?
            if k == 0 {
                let l = SCNNode(); l.light = SCNLight(); l.light!.type = .omni; l.light!.color = NSColor(rgb: (1.0, 0.85, 0.55)); l.light!.attenuationEndDistance = 2.5
                let spark = SCNNode(geometry: SCNPlane(width: 0.08, height: 0.08)); spark.geometry!.firstMaterial = flat(NSColor(rgb: (1.0, 0.95, 0.8))); spark.constraints = [SCNBillboardConstraint()]
                l.addChildNode(spark); l.position = v3(p.x + 0.2, 0.25, p.y); scene.rootNode.addChildNode(l); light = l
            }
            var up = false
            updaters.append { [weak self] c, _ in
                var tilt = 0.0, lean = 0.0
                switch k {
                case 0: tilt = 0.32; let on = Double.random(in: 0...1) < 0.55; light?.light?.intensity = on ? Double.random(in: 300...1200) : 0; light?.opacity = on ? 1 : 0
                case 1:
                    let swing = sin(c * 7); tilt = max(0, swing) * 0.45
                    if swing > 0.95 && !up { up = true; self?.drone.thud(); cn.runAction(.sequence([.scale(to: 0.85, duration: 0.05), .scale(to: 1, duration: 0.25)])) }
                    if swing < 0 { up = false }
                case 2: lean = sin(c * 2.5) * 0.05; tilt = 0.12 + sin(c * 2.5) * 0.08
                default: tilt = 0.22 + sin(c * 1.5) * 0.05
                }
                m.tilt.eulerAngles = SCNVector3(tilt, 0, 0)
                m.node.position = v3(p.x - 0.2 + lean, 0, p.y)
            }
        }
        // 5. cones
        do {
            let p = tile(i, "cones: live / queued"); i += 1
            roomFloor(at: p, color: teal)
            for (k, a) in [1.0, 0.35].enumerated() {
                let cn = Props.pyramid(color: teal.lighter(0.22), size: 0.32, floor: teal); cn.opacity = a
                cn.position = v3(p.x - 0.4 + Double(k) * 0.8, 0, p.y); scene.rootNode.addChildNode(cn)
            }
        }
        // 6. boxes
        do {
            let p = tile(i, "boxes: 3 sizes / ghost"); i += 1
            roomFloor(at: p, color: amber)
            for (k, size) in [0.18, 0.26, 0.34, 0.26].enumerated() {
                let box = SCNBox(width: size, height: size, length: size, chamferRadius: 0)
                let c = amber.lighter(0.12)
                box.materials = [flat(c), flat(c.darker(0.13)), flat(c), flat(c.darker(0.13)), flat(c.lighter(0.14)), flat(c)]
                let n = SCNNode(geometry: box); n.position = v3(p.x - 0.9 + Double(k) * 0.6, size / 2, p.y); n.eulerAngles.y = Double(k) * 0.3
                if k == 3 { n.opacity = 0.38 }
                let shadow = SCNNode(geometry: SCNPlane(width: size * 1.25, height: size * 1.25)); shadow.geometry!.firstMaterial = flat(amber.darker(0.16)); shadow.eulerAngles.x = -.pi / 2; shadow.position = v3(size * 0.08, -size / 2 + 0.004, size * 0.08)
                n.addChildNode(shadow); scene.rootNode.addChildNode(n)
            }
        }
        // 7. packages
        do {
            let p = tile(i, "package: open / merged / failing / yours / tested"); i += 1
            roomFloor(at: p, color: pink)
            let bands = [NSColor(rgb: (0.4, 0.82, 0.45)), NSColor(rgb: (0.6, 0.4, 0.9)), NSColor(rgb: (0.4, 0.82, 0.45)),
                         NSColor(rgb: (0.4, 0.82, 0.45)), NSColor(rgb: (0.45, 0.95, 0.5))]
            for (k, band) in bands.enumerated() {
                let pkg = Props.package(color: pink.lighter(0.1), band: band, size: 0.42, approved: k == 4, mine: k == 3)
                pkg.position = v3(p.x - 1.16 + Double(k) * 0.58, 0, p.y)
                if k == 2 {
                    let shell = SCNNode(geometry: SCNBox(width: 0.6, height: 0.5, length: 0.6, chamferRadius: 0)); shell.geometry!.firstMaterial = flat(NSColor(rgb: (0.95, 0.2, 0.2))); shell.opacity = 0.2
                    shell.runAction(.repeatForever(.sequence([.fadeOpacity(to: 0.55, duration: 0.7), .fadeOpacity(to: 0.15, duration: 0.9)]))); pkg.addChildNode(shell)
                }
                scene.rootNode.addChildNode(pkg)
            }
        }
        // 8. crate and shuttle
        do {
            let p = tile(i, "shuttle + crate"); i += 1
            roomFloor(at: p, color: NSColor(Colors.hangar))
            let ring = SCNNode(geometry: faceted(SCNTube(innerRadius: 0.3, outerRadius: 0.34, height: 0.01))); ring.geometry!.firstMaterial = flat(NSColor(Colors.hangar).lighter(0.18)); ring.position = v3(p.x, 0.006, p.y); scene.rootNode.addChildNode(ring)
            let crate = Looks.current.crate(color: teal) ?? Props.crate(color: teal); crate.position = v3(p.x, 0.09, p.y); crate.opacity = 0; scene.rootNode.addChildNode(crate)
            let ship = SCNNode()
            let hull = SCNNode(geometry: SCNBox(width: 0.7, height: 0.14, length: 0.4, chamferRadius: 0.03)); hull.geometry!.firstMaterial = lit(NSColor(rgb: (0.85, 0.86, 0.9))); ship.addChildNode(hull)
            let cockpit = SCNNode(geometry: SCNBox(width: 0.2, height: 0.1, length: 0.2, chamferRadius: 0.02)); cockpit.geometry!.firstMaterial = lit(NSColor(rgb: (0.55, 0.75, 1.0))); cockpit.position = v3(0.16, 0.11, 0); ship.addChildNode(cockpit)
            for side in [-1.0, 1.0] { let w = SCNNode(geometry: SCNBox(width: 0.28, height: 0.05, length: 0.34, chamferRadius: 0)); w.geometry!.firstMaterial = lit(teal); w.position = v3(-0.14, 0, side * 0.34); ship.addChildNode(w) }
            scene.rootNode.addChildNode(ship)
            func loop() {
                ship.position = v3(p.x, 3.5, p.y); crate.opacity = 0
                let down = SCNAction.move(to: v3(p.x, 0.55, p.y), duration: 3); down.timingMode = .easeInEaseOut
                let up = SCNAction.move(to: v3(p.x, 3.5, p.y), duration: 2); up.timingMode = .easeIn
                ship.runAction(.sequence([down, .wait(duration: 0.8), .run { _ in crate.opacity = 1; crate.position = v3(p.x, 0.42, p.y); crate.runAction(.move(to: v3(p.x, 0.09, p.y), duration: 0.5)) }, .wait(duration: 1.2), up, .wait(duration: 1.5), .run { _ in loop() }]))
            }
            loop()
        }
        // 9. rockets
        do {
            let p = tile(i, "rockets: staging / production (hold)"); i += 1
            roomFloor(at: p, color: NSColor(rgb: (0.24, 0.26, 0.32)))
            let small = Props.rocket(color: amber, tall: false); small.position = v3(p.x - 0.7, 0, p.y); scene.rootNode.addChildNode(small)
            let tall = Props.rocket(color: teal, tall: true, cargo: 8); tall.position = v3(p.x + 0.5, 0, p.y)
            tall.addChildNode(Looks.current.hold(tall: true) ?? Props.holdDecoration(around: SIMD3(0, 0, 0), tall: true)); scene.rootNode.addChildNode(tall)
        }
        // 10. monolith with lightning
        do {
            let p = tile(i, "monolith + research"); i += 1
            let core = SCNNode(geometry: SCNBox(width: 0.7, height: 2.3, length: 0.7, chamferRadius: 0)); core.geometry!.firstMaterial = lit(Palette.core); core.position = v3(p.x - 0.5, 1.15, p.y - 0.4); scene.rootNode.addChildNode(core)
            let glow = SCNNode(geometry: SCNBox(width: 0.72, height: 0.04, length: 0.72, chamferRadius: 0)); glow.geometry!.firstMaterial = flat(NSColor(rgb: (0.55, 0.75, 1.0))); glow.position = v3(p.x - 0.5, 1.75, p.y - 0.4); scene.rootNode.addChildNode(glow)
            let m = minion(at: SIMD2(p.x + 0.6, p.y + 0.5), sub: true)
            let bolt = SCNNode(); for _ in 0..<5 { let seg = SCNNode(geometry: SCNBox(width: 0.03, height: 0.03, length: 1, chamferRadius: 0)); seg.geometry!.firstMaterial = flat(NSColor(rgb: (0.75, 0.88, 1.0))); bolt.addChildNode(seg) }
            scene.rootNode.addChildNode(bolt)
            updaters.append { _, _ in
                let from = SIMD3(p.x - 0.5, 1.9, p.y - 0.4), to = SIMD3(p.x + 0.6, m.headHeight * 0.8, p.y + 0.5)
                var pts = [from]; for k in 1..<5 { let t = Double(k) / 5; pts.append(from + (to - from) * t + SIMD3(Double.random(in: -0.14...0.14), Double.random(in: -0.14...0.14), Double.random(in: -0.14...0.14))) }; pts.append(to)
                for (k, seg) in bolt.childNodes.enumerated() { let a = pts[k], b = pts[k + 1]; let d = b - a; let len = max(0.001, (d.x*d.x+d.y*d.y+d.z*d.z).squareRoot()); let mid = (a + b) / 2; seg.position = v3(mid.x, mid.y, mid.z); seg.scale = SCNVector3(1, 1, len); seg.look(at: v3(b.x, b.y, b.z), up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 0, 1)) }
                bolt.opacity = Double.random(in: 0.35...1)
            }
        }
        // 11. sitting: the one pose, on the two seats that use it
        do {
            let p = tile(i, "sit: couch / bowl"); i += 1
            roomFloor(at: p, color: NSColor(rgb: (0.40, 0.36, 0.30)))
            // The station's own seats, at its own heights: a couch sized to suit the picture would hide
            // the very misfit this tile is here to show.
            func sitter(at spot: SIMD2<Double>, _ color: NSColor, seat: Double, width: Double, back: Double) -> Minion {
                let pad = SCNNode(geometry: SCNBox(width: width, height: seat, length: 0.4, chamferRadius: 0.02))
                pad.geometry!.firstMaterial = lit(color)
                pad.position = v3(spot.x, seat / 2, spot.y)
                scene.rootNode.addChildNode(pad)
                let rest = SCNNode(geometry: SCNBox(width: width, height: back, length: 0.08, chamferRadius: 0.02))
                rest.geometry!.firstMaterial = lit(color)
                rest.position = v3(spot.x, seat + back / 2, spot.y - 0.24)
                scene.rootNode.addChildNode(rest)
                // A sitter is put down a shin's reach behind its spot, so it stands that far in front of
                // the seat — the same as a body walking up to a couch on a station.
                return minion(at: SIMD2(spot.x, spot.y + Body.seatReach))
            }
            let a = sitter(at: SIMD2(p.x - 0.5, p.y), NSColor(rgb: (0.62, 0.45, 0.4)),
                           seat: Minion.couchSeat, width: 0.8, back: 0.22)
            let b = sitter(at: SIMD2(p.x + 0.5, p.y), .white, seat: Minion.seat, width: 0.3, back: 0.3)
            a.setTool(.tablet)   // reading on the couch: what a sitter most often has in its hands
            a.setPose(.seated(height: Minion.couchSeat, at: SIMD2(0, 0)))
            b.setPose(.seated(height: Minion.seat, at: SIMD2(0, 0)))
            var phase = 0
            updaters.append { c, _ in
                let k = Int(c / 3) % 2
                if k != phase {
                    phase = k
                    a.setPose(k == 0 ? .seated(height: Minion.couchSeat, at: SIMD2(0, 0)) : .standing)
                    b.setPose(k == 0 ? .seated(height: Minion.seat, at: SIMD2(0, 0)) : .standing)
                }
            }
        }
        // 12. lounge and crew
        do {
            let p = tile(i, "lounge + crew minion"); i += 1
            roomFloor(at: p, color: NSColor(rgb: (0.40, 0.36, 0.30)))
            let table = SCNNode(geometry: faceted(SCNCylinder(radius: 0.3, height: 0.28), 4)); table.geometry!.firstMaterial = lit(NSColor(rgb: (0.55, 0.42, 0.3))); table.position = v3(p.x, 0.14, p.y); scene.rootNode.addChildNode(table)
            let a = minion(at: SIMD2(p.x - 0.55, p.y)); a.node.eulerAngles.y = .pi / 2
            let b = minion(at: SIMD2(p.x + 0.55, p.y), crew: true); b.node.eulerAngles.y = -.pi / 2
            updaters.append { c, _ in a.tilt.eulerAngles = SCNVector3(sin(c * 2.2) * 0.06, 0, 0); b.tilt.eulerAngles = SCNVector3(sin(c * 2.2 + 1) * 0.06, 0, 0) }
        }
        // 12. tiles with a door
        do {
            let p = tile(i, "floor + door + border"); i += 1
            let corr = SCNNode(geometry: SCNPlane(width: 1, height: 2)); corr.geometry!.firstMaterial = flat(Palette.corridor); corr.eulerAngles.x = -.pi / 2; corr.position = v3(p.x - 0.7, 0.003, p.y); scene.rootNode.addChildNode(corr)
            let room = SCNNode(geometry: SCNPlane(width: 1.2, height: 2)); room.geometry!.firstMaterial = flat(teal); room.eulerAngles.x = -.pi / 2; room.position = v3(p.x + 0.45, 0.003, p.y); scene.rootNode.addChildNode(room)
            let border = SCNNode(geometry: SCNPlane(width: 0.15, height: 1.0)); border.geometry!.firstMaterial = flat(Palette.void); border.eulerAngles.x = -.pi / 2; border.position = v3(p.x - 0.15, 0.005, p.y - 0.5); scene.rootNode.addChildNode(border)
            let dot = SCNNode(geometry: SCNPlane(width: 0.12, height: 0.12)); dot.geometry!.firstMaterial = flat(Palette.void); dot.eulerAngles.x = -.pi / 2; dot.position = v3(p.x - 0.7, 0.006, p.y + 0.5); scene.rootNode.addChildNode(dot)
        }
        // 13. what a look may draw instead of the scene's own pieces
        do {
            let p = tile(i, "look's own: pallet / console / crate"); i += 1
            let cart = Looks.current.pallet(color: amber) ?? Props.pallet(color: amber)
            cart.scale = SCNVector3(0.8, 0.8, 0.8)
            cart.position = v3(p.x - 0.75, 0.22, p.y + 0.15)
            scene.rootNode.addChildNode(cart)
            let desk = Looks.current.console(color: teal) ?? Props.console(color: teal)
            desk.scale = SCNVector3(1.1, 1.1, 1.1)
            desk.position = v3(p.x + 0.25, 0.55, p.y - 0.55)
            scene.rootNode.addChildNode(desk)
            for (k, c) in [pink, teal, amber].enumerated() {
                let box = Looks.current.crate(color: c) ?? Props.crate(color: c)
                box.scale = SCNVector3(0.85, 0.85, 0.85)
                box.position = v3(p.x + 0.45 + Double(k) * 0.05, 0.004 + Double(k) * 0.26, p.y + 0.45 - Double(k) * 0.05)
                scene.rootNode.addChildNode(box)
            }
        }
        // 14. the castle wall, as it is built and as it is merged: the same run of cells both ways, so a
        // merge that loses the pieces shows up here rather than in the middle of a station.
        do {
            let p = tile(i, "castle wall + great ship"); i += 1
            let cells: Set<Cell> = Set((0...2).flatMap { x in (0...1).map { Cell(x: x, y: $0) } })
            let holder = KingdomLook().curtain(over: cells)
            holder.scale = SCNVector3(0.42, 0.42, 0.42)
            holder.position = v3(p.x - 0.75, 0.004, p.y - 0.3)
            scene.rootNode.addChildNode(holder)
            for (k, tall) in [false, true].enumerated() {
                let ship = KingdomLook().rocket(color: tall ? teal : pink, tall: tall, cargo: tall ? 2 : 0)
                ship.scale = SCNVector3(0.4, 0.4, 0.4)
                ship.position = v3(p.x + 0.55, 0.004, p.y - 0.5 + Double(k) * 0.85)
                scene.rootNode.addChildNode(ship)
            }
        }
        rig.position = v3(6.4, 0, 7.2)
    }

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        let dt = lastTime == 0 ? 0 : min(0.1, time - lastTime)
        lastTime = time
        clock += dt
        for u in updaters { u(clock, dt) }
        let k = 1 - exp(-dt * 10)
        rig.eulerAngles.y += (Double.pi / 4 + yaw - Double(rig.eulerAngles.y)) * k
        pitchNode.eulerAngles.x += (pitch - Double(pitchNode.eulerAngles.x)) * k
        cameraNode.camera!.orthographicScale += (8.0 / zoom - cameraNode.camera!.orthographicScale) * k
        rig.position.x += (6.4 + pan.x - Double(rig.position.x)) * k
        rig.position.z += (5.0 + pan.y - Double(rig.position.z)) * k
    }

    func snapshot(to path: String) {
        let image = view.snapshot()
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: path))
    }
}
