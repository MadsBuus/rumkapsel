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

        view.onZoom = { [weak self] f in self?.zoom = min(8, max(0.3, (self?.zoom ?? 1) * f)) }
        view.onRotate = { [weak self] r in self?.yaw -= r }
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
        case .testing: return (0, 0, t * 3)
        case .running: return (sin(t * 22) * 0.04, cos(t * 19) * 0.04, 0)
        case .shipping: return (0, sin(t * 9) * 0.16, 0)
        case .skill: return (0, 0, t * 2)
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
        // 2. sleeping and rising
        do {
            let p = tile(i, "sleep / rise"); i += 1
            roomFloor(at: p, color: NSColor(Colors.quarters))
            let bed = SCNNode(geometry: SCNPlane(width: 0.34, height: 0.72)); bed.geometry!.firstMaterial = flat(NSColor(Colors.bed)); bed.eulerAngles.x = -.pi / 2; bed.position = v3(p.x, 0.006, p.y)
            scene.rootNode.addChildNode(bed)
            let m = minion(at: p); m.setSleeping(true)
            var phase = 0
            updaters.append { c, _ in
                let k = Int(c / 3) % 2
                if k != phase { phase = k; m.setSleeping(k == 0) }
            }
        }
        // 3. working routines
        for act in [Activity.coding("x"), .exploring, .thinking, .writing, .testing, .shipping, .qa, .waiting] {
            let p = tile(i, act == .waiting ? "waiting (jump)" : act.label); i += 1
            let m = minion(at: p)
            switch act {
            case .coding, .testing: m.setTool(.wrench)
            case .exploring, .writing, .qa: m.setTool(.clipboard)
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
            m.setTool([Minion.Tool.goggles, .hammer, .wrench, nil][k])
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
            let p = tile(i, "package: open / merged / failing"); i += 1
            roomFloor(at: p, color: pink)
            let bands = [NSColor(rgb: (0.4, 0.82, 0.45)), NSColor(rgb: (0.6, 0.4, 0.9)), NSColor(rgb: (0.4, 0.82, 0.45))]
            for (k, band) in bands.enumerated() {
                let pkg = Props.package(color: pink.lighter(0.1), band: band, size: 0.5)
                pkg.position = v3(p.x - 0.8 + Double(k) * 0.8, 0, p.y)
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
            let ring = SCNNode(geometry: SCNTube(innerRadius: 0.3, outerRadius: 0.34, height: 0.01)); ring.geometry!.firstMaterial = flat(NSColor(Colors.hangar).lighter(0.18)); ring.position = v3(p.x, 0.006, p.y); scene.rootNode.addChildNode(ring)
            let crate = Props.crate(color: teal); crate.position = v3(p.x, 0.09, p.y); crate.opacity = 0; scene.rootNode.addChildNode(crate)
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
            tall.addChildNode(Props.holdDecoration(around: SIMD3(0, 0, 0), tall: true)); scene.rootNode.addChildNode(tall)
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
        // 11. lounge and crew
        do {
            let p = tile(i, "lounge + crew minion"); i += 1
            roomFloor(at: p, color: NSColor(rgb: (0.40, 0.36, 0.30)))
            let table = SCNNode(geometry: SCNCylinder(radius: 0.3, height: 0.28)); table.geometry!.firstMaterial = lit(NSColor(rgb: (0.55, 0.42, 0.3))); table.position = v3(p.x, 0.14, p.y); scene.rootNode.addChildNode(table)
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
        rig.position = v3(6.4, 0, 5.0)
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
