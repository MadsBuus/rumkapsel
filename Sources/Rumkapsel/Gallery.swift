import AppKit
import SceneKit
import SpriteKit

/// A showroom: every routine a body plays and every piece the current look draws, each on its own
/// tile, one thing at a time and up close.
///
/// Two rules keep a tile honest.
///
/// **Nothing here writes an animation.** The motion comes from `Routines`, the same table the
/// station's tick reads, and the arcs from the same `CrateMotion` the floor uses. A tile can only
/// show what the app draws, so the picture cannot quietly drift from the station — which is what
/// it used to do: the gallery's own copy had a tablet where the app had a torch, and a lightning
/// bolt the app stopped drawing long ago.
///
/// **Nothing here names a theme.** Every piece comes through `Looks.current`, so the sheet shows
/// whatever theme is on and a theme's own pieces can be judged against the classic ones without
/// two themes ending up in the same picture.
///
/// Getting about:
///
///     --tiles                 every tile's name, one per line
///     --tile <words>          the camera on the first tile whose name has those words, framed
///     --tile <words> --zoom 2 …and closer or wider
///
/// and in the window, `]` and `[` step to the next tile and the one before, `0` pulls back to the
/// whole sheet. The window's title says which tile the camera is on.
final class GalleryController: NSObject, SCNSceneRendererDelegate {
    let view: StationView
    private let scene = SCNScene()
    private let rig = SCNNode()
    private let pitchNode = SCNNode()
    private let cameraNode = SCNNode()
    private var yaw = 0.0, pitch = -Double.pi / 5
    /// Where the camera is aiming and how wide it is, eased toward every frame.
    private var at = SIMD2<Double>(0, 0), scale = 8.0
    private var clock = 0.0, lastTime = 0.0
    private var updaters: [(Double, Double) -> Void] = []   // (clock, dt)
    private let drone = Drone()
    /// The crates under way on the carry tiles, on the gallery's own clock: the station's own tween,
    /// so a lift here rises exactly as a lift there does.
    private var motions: [ObjectIdentifier: CrateMotion] = [:]

    /// One exhibit: what it is called and the box it stands in, so the camera can frame it alone.
    private struct Exhibit {
        let title: String
        let at: SIMD2<Double>
        /// How tall the tallest thing on it is, so framing a rocket does not cut its nose off.
        var height = 1.0
    }
    private var exhibits: [Exhibit] = []
    /// The tile the camera is on, or nil for the whole sheet.
    private var shown: Int?

    init(frame: NSRect) {
        view = StationView(frame: frame, options: [SCNView.Option.preferredRenderingAPI.rawValue: SCNRenderingAPI.metal.rawValue])
        super.init()
        scene.background.contents = Looks.current.background
        view.scene = scene
        view.backgroundColor = Looks.current.background
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

        view.onZoom = { [weak self] f, _ in guard let self else { return }; scale = min(26, max(1, scale / f)); shown = nil }
        view.onRotate = { [weak self] r, _ in self?.yaw -= r }
        view.onTilt = { [weak self] dy in self?.pitch = min(-0.15, max(-Double.pi / 2 + 0.05, (self?.pitch ?? 0) - dy * 0.004)) }
        view.onPan = { [weak self] dx, dy in
            guard let self else { return }
            let y = Double.pi / 4 + yaw
            let upp = 2 * cameraNode.camera!.orthographicScale / Double(max(1, view.bounds.height))
            at -= (SIMD2(cos(y), -sin(y)) * dx - SIMD2(-sin(y), -cos(y)) * dy) * upp
            shown = nil
        }
        view.onKey = { [weak self] key in self?.handle(key: key) ?? false }

        build()

        let args = CommandLine.arguments
        // `--tiles`: the sheet's contents, for picking one without taking a picture of the lot first.
        if args.contains("--tiles") {
            FileHandle.standardOutput.write((exhibits.map(\.title).joined(separator: "\n") + "\n").data(using: .utf8)!)
            exit(0)
        }
        if let i = args.firstIndex(of: "--tile"), args.count > i + 1,
           let k = index(matching: args[i + 1]) {
            show(k)
            if let z = args.firstIndex(of: "--zoom"), args.count > z + 1, let v = Double(args[z + 1]) { scale /= v }
        } else {
            showAll()
        }
        // Where the camera starts is where it should already be: a snapshot must not catch it easing in.
        settle(by: 1)
    }

    // MARK: getting about

    /// The first tile whose name has those words in it, however they are cased.
    private func index(matching words: String) -> Int? {
        let needle = words.lowercased()
        return exhibits.firstIndex { $0.title.lowercased().contains(needle) }
    }

    private func handle(key: String) -> Bool {
        switch key {
        case "]": show(((shown ?? -1) + 1) % exhibits.count); return true
        case "[": show(((shown ?? 0) - 1 + exhibits.count) % exhibits.count); return true
        case "0": showAll(); return true
        default: return false
        }
    }

    /// The camera onto one tile, framed to it, with its name in the title bar.
    private func show(_ k: Int) {
        guard exhibits.indices.contains(k) else { return }
        shown = k
        let e = exhibits[k]
        (at, scale) = framing(corners(of: e))
        title("\(k + 1)/\(exhibits.count)  \(e.title)")
    }

    /// Back out to the whole sheet.
    private func showAll() {
        shown = nil
        (at, scale) = framing(exhibits.flatMap(corners(of:)))
        title("\(exhibits.count) tiles · ] [ to step, 0 for all")
    }

    private func title(_ text: String) {
        view.window?.title = "rumkapsel gallery — " + text
    }

    /// The box a tile takes up: its own square up to whatever stands tallest on it, and the strip
    /// its label runs along underneath.
    private func corners(of e: Exhibit) -> [SIMD3<Double>] {
        let half = GalleryController.tileSize / 2 + 0.1
        var out = [-half, half].flatMap { dx in [-half, half].flatMap { dz in
            [0.0, e.height].map { y in SIMD3(e.at.x + dx, y, e.at.y + dz) }
        } }
        for side in [-1.8, 1.8] {
            let at = e.at + place(right: side, down: GalleryController.labelDrop + 0.3)
            out.append(SIMD3(at.x, 0, at.y))
        }
        return out
    }

    /// Where the rig must stand and how wide the camera must be for these points to fill the view.
    /// The projection is the rig's own — yaw, then pitch, then straight down the camera's axis —
    /// so the frame is exact however the sheet is turned.
    private func framing(_ points: [SIMD3<Double>]) -> (at: SIMD2<Double>, scale: Double) {
        guard !points.isEmpty else { return (SIMD2(0, 0), 8) }
        let ry = Double.pi / 4 + yaw
        func project(_ p: SIMD3<Double>) -> SIMD2<Double> {
            let x = p.x * cos(ry) - p.z * sin(ry)
            let z = p.x * sin(ry) + p.z * cos(ry)
            return SIMD2(x, p.y * cos(pitch) + z * sin(pitch))
        }
        let flat = points.map(project)
        let lo = SIMD2(flat.map(\.x).min()!, flat.map(\.y).min()!)
        let hi = SIMD2(flat.map(\.x).max()!, flat.map(\.y).max()!)
        let mid = (lo + hi) / 2
        // Back out of the projection onto the floor, where the rig stands.
        let qx = mid.x, qz = mid.y / sin(pitch)
        let aim = SIMD2(qx * cos(ry) + qz * sin(ry), -qx * sin(ry) + qz * cos(ry))
        let aspect = Double(max(1, view.bounds.width)) / Double(max(1, view.bounds.height))
        let want = max((hi.y - lo.y) / 2, (hi.x - lo.x) / 2 / aspect) * 1.06   // a little air round the edges
        return (aim, max(0.6, want))
    }

    // MARK: laying the sheet out

    private static let tileSize = 2.6
    private static let columns = 6
    /// The sheet is laid out in the camera's own frame at the angle it starts on, so it reads as
    /// plain rows and columns rather than a diamond, while every prop on it is still seen at the
    /// station's own angle. Turning the camera afterwards skews the sheet, which is the price of
    /// looking at a prop from another side; the framing follows the turn either way.
    private static let sheetYaw = Double.pi / 4, sheetPitch = -Double.pi / 5
    /// Tile to tile, in screen units: a 2.6 square seen at this angle is about 3.7 across and 2.2
    /// down, and a row is dropped further still by whatever stands tallest on it, since a tall prop
    /// rises up the picture into the row above.
    private static let across = 4.3, down = 3.2
    /// How far below a tile its label sits.
    private static let labelDrop = 1.45

    /// Where a point that far right of and below a spot lands on the floor.
    private func place(right: Double, down: Double) -> SIMD2<Double> {
        let ry = GalleryController.sheetYaw, p = GalleryController.sheetPitch
        let qx = right, qz = -down / sin(p)
        return SIMD2(qx * cos(ry) + qz * sin(ry), -qx * sin(ry) + qz * cos(ry))
    }

    /// A row of spots across a tile, evenly spaced along the picture's horizontal, so a set of five
    /// packages reads as a row rather than running off into the corner.
    private func spread(_ p: SIMD2<Double>, _ count: Int, gap: Double) -> [SIMD2<Double>] {
        (0..<count).map { p + place(right: (Double($0) - Double(count - 1) / 2) * gap, down: 0) }
    }

    // MARK: what goes on the sheet

    /// A tile waiting for a spot: the layout needs every tile's height before it can space the rows,
    /// so the sheet is declared first and drawn after.
    private struct Pending {
        let title: String
        let height: Double
        /// Whether it starts a new band.
        let breaks: Bool
        let draw: (SIMD2<Double>) -> Void
    }
    private var pending: [Pending] = []
    private var breakNext = false

    /// Starts a new band. A section always begins on its own row, so the sheet reads in bands and
    /// `]` walks them in order.
    private func section() { breakNext = true }

    /// One tile: what it is called, how tall it stands, and what to draw once it has a spot.
    private func add(_ title: String, height: Double = 1.0, _ draw: @escaping (SIMD2<Double>) -> Void) {
        pending.append(Pending(title: title, height: height, breaks: breakNext, draw: draw))
        breakNext = false
    }

    /// Gives every declared tile a spot, a floor and a label, and then draws it.
    private func layout() {
        var rows: [[Pending]] = []
        for p in pending {
            if p.breaks || rows.isEmpty || rows[rows.count - 1].count == GalleryController.columns { rows.append([]) }
            rows[rows.count - 1].append(p)
        }
        var y = 0.0
        for row in rows {
            // A tall prop stands up the picture, so the row it is on drops by what it reaches.
            y += GalleryController.down + (row.map(\.height).max() ?? 1) * cos(GalleryController.sheetPitch)
            for (column, p) in row.enumerated() {
                let at = place(right: Double(column) * GalleryController.across, down: y)
                let floor = SCNNode(geometry: SCNPlane(width: GalleryController.tileSize, height: GalleryController.tileSize))
                floor.geometry!.firstMaterial = flat(NSColor(rgb: (0.16, 0.17, 0.23)))
                floor.eulerAngles.x = -.pi / 2
                floor.position = v3(at.x, 0, at.y)
                scene.rootNode.addChildNode(floor)
                // Turned to the camera's horizontal, so the words read across the picture rather
                // than off into the corner of it.
                // Two lines, so a title that says what all five states on a tile are still fits under it.
                let label = floorText(p.title, color: Palette.text, size: 0.23, maxWidth: GalleryController.across - 0.3, lines: 2)
                let under = at + place(right: 0, down: GalleryController.labelDrop)
                label.node.position = v3(under.x, 0.01, under.y)
                label.node.eulerAngles.y = GalleryController.sheetYaw
                scene.rootNode.addChildNode(label.node)
                exhibits.append(Exhibit(title: p.title, at: at, height: p.height))
                p.draw(at)
            }
        }
        pending = []
    }

    /// A patch of coloured floor under a tile's props, where the room's colour is part of what is
    /// being judged.
    private func ground(_ p: SIMD2<Double>, _ color: NSColor, size: Double = 2.0) {
        let f = SCNNode(geometry: SCNPlane(width: size, height: size))
        f.geometry!.firstMaterial = flat(color)
        f.eulerAngles.x = -.pi / 2
        f.position = v3(p.x, 0.003, p.y)
        scene.rootNode.addChildNode(f)
    }

    /// A body standing on a tile, built the one way the station builds one, so it wears the current
    /// look's figure.
    private func body(at p: SIMD2<Double>, sub: Bool = false, crew: Bool = false) -> Minion {
        let m = Minion(id: UUID().uuidString, station: "gallery",
                       home: Home(key: "x", name: "x", repo: "x", issue: nil),
                       cwd: "", toolCount: 0, isSubagent: sub, start: Cell(x: 0, y: 0), crew: crew)
        m.pos = p
        m.node.position = v3(p.x, 0, p.y)
        m.node.opacity = 1
        scene.rootNode.addChildNode(m.node)
        bodies.append(m)
        return m
    }

    /// Every body on the sheet, so their props can be beaten each frame. A tile that hands a body a tool
    /// and never beats it shows an empty pair of hands: the prop arrives at nothing and waits to be
    /// brought up.
    private var bodies: [Minion] = []

    /// Puts a routine's beat onto a body, the way the station's tick puts it: the spin on the body,
    /// the tilt and roll on its head, the lean a step along its own facing.
    private func apply(_ r: Routines.Motion, to m: Minion, at p: SIMD2<Double>, facing: Double) {
        if let lit = r.scanner { m.blinkScanner(lit) }
        if let aim = r.aim { m.lightPivot?.eulerAngles = aim }
        if let pitch = r.hammerPitch { m.hammerPivot?.eulerAngles.x = CGFloat(pitch) }
        m.node.eulerAngles = SCNVector3(0, facing + r.spin, 0)
        m.tilt.eulerAngles = SCNVector3(r.tilt, 0, r.roll)
        m.tilt.position.y = CGFloat(r.lift ?? 0)
        m.node.position = v3(p.x + sin(facing) * r.lean, 0, p.y + cos(facing) * r.lean)
    }

    // MARK: the sheet

    private func build() {
        buildWork()
        buildCone()
        buildHands()
        buildPieces()
        layout()
    }

    /// One tile per thing a session can be doing, named as the hover panel names it. Every one of
    /// them plays `Routines`, so what stands here is what stands in an office.
    private func buildWork() {
        section()
        // The monolith's own: a subagent at the core, with the beam coming down on it.
        add(Activity.researching.label, height: 2.6) { [self] p in
            let keep = Looks.current.monolith()
            keep.position = v3(p.x - 0.55, 0, p.y - 0.45)
            scene.rootNode.addChildNode(keep)
            let m = body(at: SIMD2(p.x + 0.55, p.y + 0.45), sub: true)
            let beam = Props.beam()
            scene.rootNode.addChildNode(beam)
            updaters.append { c, _ in
                Props.aim(beam, from: SIMD3(p.x - 0.55, 1.9, p.y - 0.45),
                          to: SIMD3(p.x + 0.55, m.headHeight * 0.8, p.y + 0.45),
                          clock: c, phase: m.bobPhase)
            }
        }
        // The desk routines: the whole switch in `Routines.working`, one activity to a tile.
        for act in [Activity.exploring, .coding("app"), .testing, .running, .shipping, .skill("review"),
                    .planning, .delegating, .writing, .thinking, .reading, .qa] {
            add(act.label) { [self] p in
                let m = body(at: p)
                updaters.append { [weak self] c, dt in
                    guard let self else { return }
                    m.setTool(Routines.tool(for: act))
                    let r = Routines.working(act, t: (c + m.bobPhase) * m.tempo, dt: dt, clock: c)
                    apply(r, to: m, at: p, facing: 0)
                    if case .tick = r.flash {
                        let tick = Props.qaTick()
                        tick.position = v3(p.x, m.headHeight + 0.2, p.y)
                        scene.rootNode.addChildNode(tick)
                    }
                }
            }
        }
        // Waiting on you: the hop of the first minute.
        add(Activity.waiting.label) { [self] p in
            let m = body(at: p)
            updaters.append { c, _ in
                m.node.position = v3(p.x, Routines.hop(clock: c, phase: m.bobPhase), p.y)
            }
        }
        add("walking") { [self] p in
            let m = body(at: p)
            updaters.append { c, _ in
                let s = sin(c * 1.2)
                m.node.position = v3(p.x + s * 0.9, 0, p.y)
                m.node.eulerAngles.y = cos(c * 1.2) >= 0 ? .pi / 2 : -.pi / 2
            }
        }
        buildBed()
        buildSeats()
    }

    /// A night's sleep, end to end. The poses and the heights are the station's; the timing is the
    /// gallery's, since on a station this plays out over hours.
    private func buildBed() {
        add(Activity.sleeping.label) { [self] p in
            ground(p, NSColor(Colors.quarters))
            let bunk = Looks.current.bed(level: 0)
            bunk.position = v3(p.x, 0, p.y)
            scene.rootNode.addChildNode(bunk)
            let m = body(at: p)

            // Going to bed and getting up are the same moves in opposite orders. It comes to the side
            // of the bunk, turns its back on it, sits on the edge, and swings round into line as it
            // stretches out; getting up it swings back out of line onto the edge, stands, and walks
            // off as it faces. It stops at the bunk's edge, which is 0.17 out from the middle of a bed
            // 0.34 across: that is where its feet go, and sitting puts the rest of it back onto the
            // mattress behind them.
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
    }

    /// The one sitting pose, on the two seats that use it. The station's own seats, at its own
    /// heights: a couch sized to suit the picture would hide the very misfit this tile is here to
    /// show.
    private func buildSeats() {
        add("sit: couch / bowl") { [self] p in
            ground(p, NSColor(rgb: (0.40, 0.36, 0.30)))
            func sitter(at spot: SIMD2<Double>, _ color: NSColor, seat: Double, width: Double, back: Double) -> Minion {
                let pad = SCNNode(geometry: SCNBox(width: width, height: seat, length: 0.4, chamferRadius: 0.02))
                pad.geometry!.firstMaterial = lit(color)
                pad.position = v3(spot.x, seat / 2, spot.y)
                scene.rootNode.addChildNode(pad)
                let rest = SCNNode(geometry: SCNBox(width: width, height: back, length: 0.08, chamferRadius: 0.02))
                rest.geometry!.firstMaterial = lit(color)
                rest.position = v3(spot.x, seat + back / 2, spot.y - 0.24)
                scene.rootNode.addChildNode(rest)
                // A sitter is put down a shin's reach behind its spot, so it stands that far in front
                // of the seat — the same as a body walking up to a couch on a station.
                return body(at: SIMD2(spot.x, spot.y + Body.seatReach))
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
    }

    /// The four turns at a cone, one to a tile, instead of waiting for the rota to come round. The
    /// cone is the look's own message piece, which is what a body actually stands over.
    private func buildCone() {
        section()
        let room = NSColor(Colors.repos[0])
        for (slot, name) in ["welding", "hammering", "push and pull", "torch"].enumerated() {
            add("cone: " + name) { [self] p in
                ground(p, room)
                let tint = room.lighter(0.22)
                let cone = Looks.current.message(color: tint, floor: room) ?? Props.pyramid(color: tint, size: 0.32, floor: room)
                cone.position = v3(p.x + 0.2, 0, p.y)
                scene.rootNode.addChildNode(cone)
                let m = body(at: SIMD2(p.x - 0.2, p.y))
                m.setTool(Routines.coneTools[slot])
                var lamp: SCNNode?
                var struck = false
                updaters.append { [weak self] c, _ in
                    guard let self else { return }
                    let r = Routines.cone(slot: slot, t: (c + m.bobPhase) * m.tempo, struck: &struck)
                    apply(r, to: m, at: SIMD2(p.x - 0.2, p.y), facing: .pi / 2)
                    switch r.flash {
                    case .weld(let on, let intensity):
                        if Looks.current.workSparks, lamp == nil {
                            let l = Props.weldLamp()
                            l.position = v3(p.x + 0.2, 0.25, p.y)
                            scene.rootNode.addChildNode(l)
                            lamp = l
                        }
                        lamp?.light?.intensity = intensity
                        lamp?.opacity = on ? 1 : 0
                    case .strike:
                        self.drone.thud()
                        cone.runAction(.sequence([.scale(to: 0.85, duration: 0.05), .scale(to: 1, duration: 0.25)]))
                    default: break
                    }
                }
            }
        }
    }

    /// Taking a crate up and putting it down again, at each of the four heights the hands work at.
    /// The bend comes from `Routines.hold` and the arc from the station's own tween, so a crate that
    /// clips through a head here clips through one there.
    private func buildHands() {
        section()
        let colour = NSColor(Colors.repos[1])
        for (level, name) in ["floor", "waist", "overhead", "a hop"].enumerated() {
            add("lift: " + name, height: 1.8) { [self] p in
                // The shelf the crate comes off and goes back onto, at the height that level works at.
                let shelfTop = [0.0, 0.42, 0.84, 1.16][level]
                if shelfTop > 0 {
                    let post = SCNNode(geometry: SCNBox(width: 0.5, height: shelfTop, length: 0.5, chamferRadius: 0))
                    post.geometry!.firstMaterial = lit(NSColor(rgb: (0.3, 0.32, 0.4)))
                    post.position = v3(p.x + 0.55, shelfTop / 2, p.y)
                    scene.rootNode.addChildNode(post)
                }
                let stand = SIMD2(p.x - 0.3, p.y)
                let m = body(at: stand)
                m.smoothFacing = .pi / 2
                m.handsAt = level
                let crate = Looks.current.crate(color: colour) ?? Props.crate(color: colour)
                let shelf = SIMD3(p.x + 0.55, shelfTop, p.y)
                crate.position = v3(shelf.x, shelf.y, shelf.z)
                scene.rootNode.addChildNode(crate)

                // One round: reach for it, carry it a beat, put it back, stand off a beat.
                let up = Hands.liftFirst + Hands.liftSecond, down = Hands.setDownFirst + Hands.setDownSecond
                let carries = up + 1.2, puts = carries + down, loop = puts + 1.4
                var phase = -1
                updaters.append { [weak self] c, _ in
                    guard let self else { return }
                    let t = c.truncatingRemainder(dividingBy: loop)
                    let now = t < up ? 0 : t < carries ? 1 : t < puts ? 2 : 3
                    if now != phase {
                        phase = now
                        switch now {
                        case 0:
                            // Onto the arms, by the station's own two legs.
                            crate.removeFromParentNode()
                            m.node.addChildNode(crate)
                            crate.position = m.node.convertPosition(v3(shelf.x, shelf.y, shelf.z), from: nil)
                            move(crate, Routines.liftLegs(from: Double(crate.position.y), handsAt: level, headHeight: m.headHeight))
                        case 2:
                            let target = m.node.convertPosition(v3(shelf.x, shelf.y, shelf.z), from: nil)
                            move(crate, Routines.setDownLegs(to: SIMD3(Double(target.x), Double(target.y), Double(target.z)),
                                                             level: level, headHeight: m.headHeight))
                        case 3:
                            let world = crate.worldPosition
                            crate.removeFromParentNode()
                            crate.position = world
                            scene.rootNode.addChildNode(crate)
                        default: break
                        }
                    }
                    // Bent over it while the hands are on it, upright while it rides on the arms.
                    let working = now == 0 || now == 2
                    let hop = level >= 3 && working ? abs(sin(t * 2.4)) : 0
                    let held = Routines.hold(working ? Routines.posture(handsAt: level) : .none, tilt: 0, roll: 0, hop: hop)
                    m.node.position = v3(stand.x, 0, stand.y)
                    m.node.eulerAngles = SCNVector3(0, Double.pi / 2, 0)
                    m.tilt.eulerAngles = SCNVector3(held.tilt, 0, held.roll)
                    m.tilt.position.y = CGFloat(held.rise)
                }
            }
        }
    }

    /// The pieces the current look draws, each in the state the station can put it in. Nothing here
    /// names a theme: switch the theme and the sheet switches with it.
    private func buildPieces() {
        section()
        let pink = NSColor(Colors.repos[0]), teal = NSColor(Colors.repos[1]), amber = NSColor(Colors.repos[2])

        // Three bodies: a session of yours, a subagent, a teammate's crew.
        add("figures: yours / subagent / crew") { [self] p in
            for (k, who) in [(false, false), (true, false), (false, true)].enumerated() {
                let m = body(at: spread(p, 3, gap: 0.6)[k], sub: who.0, crew: who.1)
                m.node.eulerAngles.y = 0.3
            }
        }
        // Commits: the three sizes the rows pick from, and an uncommitted one.
        add("cubes: three sizes / uncommitted") { [self] p in
            ground(p, amber)
            let sizes = Props.cubeSizes + [0.26]
            for (k, spot) in spread(p, sizes.count, gap: 0.5).enumerated() {
                let n = Props.cube(color: amber.lighter(0.12), size: sizes[k], shadow: amber.darker(0.16))
                n.position = v3(spot.x, sizes[k] / 2, spot.y)
                n.eulerAngles.y = Double(k) * 0.3
                if k == 3 { n.opacity = Props.ghostOpacity }
                scene.rootNode.addChildNode(n)
            }
        }
        // A package in every light the rows can put on it.
        add("packages: open / pending / failing / closed / tested") { [self] p in
            ground(p, pink)
            let green = NSColor(rgb: (0.4, 0.82, 0.45)), pending = NSColor(rgb: (1.0, 0.72, 0.25))
            let red = NSColor(rgb: (0.95, 0.22, 0.22)), cleared = NSColor(rgb: (0.45, 0.95, 0.5))
            let states: [(band: NSColor, shell: NSColor, blink: Bool, failing: Bool, tested: Bool)] = [
                (green, pink, false, false, false),
                (pending, pink, true, false, false),
                (red, pink, false, true, false),
                (red, NSColor(rgb: (0.75, 0.2, 0.2)), false, false, false),
                (cleared, pink, false, false, true),
            ]
            for (k, spot) in spread(p, states.count, gap: 0.46).enumerated() {
                let s = states[k]
                let pkg = Props.package(color: s.shell, band: s.band, size: 0.38, approved: s.tested, blink: s.blink)
                if s.failing { pkg.addChildNode(Props.failingShell(size: 0.38 * 1.2)) }
                pkg.position = v3(spot.x, 0, spot.y)
                scene.rootNode.addChildNode(pkg)
            }
        }
        // And the two a package can be whoever opened it: yours, strapped in white, and a bot's.
        add("packages: yours / a bot's") { [self] p in
            ground(p, pink)
            let spots = spread(p, 2, gap: 0.7)
            let mine = Props.package(color: pink, band: NSColor(rgb: (0.4, 0.82, 0.45)), size: 0.38, mine: true)
            mine.position = v3(spots[0].x, 0, spots[0].y)
            scene.rootNode.addChildNode(mine)
            // Of unknown origin: grey wherever it stands, with a tint of the repository it came for.
            let alien = Props.package(color: Palette.alien.darker(0.3).mixed(with: pink.darker(0.3), 0.35),
                                      band: Palette.alienLight.darker(0.3), size: 0.3)
            alien.position = v3(spots[1].x, 0, spots[1].y)
            scene.rootNode.addChildNode(alien)
        }
        // The message cone: the one being worked, and the ones queued behind it.
        add("cones: live / queued") { [self] p in
            ground(p, teal)
            for (k, spot) in spread(p, 3, gap: 0.55).enumerated() {
                let tint = teal.lighter(0.22)
                let cn = Looks.current.message(color: tint, floor: teal) ?? Props.pyramid(color: tint, size: 0.32, floor: teal)
                cn.opacity = k == 0 ? 1 : 0.35
                cn.position = v3(spot.x, 0, spot.y)
                scene.rootNode.addChildNode(cn)
            }
        }
        // What an office and a yard are made of.
        add("crate / console / pallet", height: 1.4) { [self] p in
            let spots = spread(p, 3, gap: 0.85)
            let cart = Looks.current.pallet(color: amber) ?? Props.pallet(color: amber)
            cart.scale = SCNVector3(0.8, 0.8, 0.8)
            cart.position = v3(spots[0].x, 0.22, spots[0].y)
            scene.rootNode.addChildNode(cart)
            let desk = Looks.current.console(color: teal) ?? Props.console(color: teal)
            desk.scale = SCNVector3(1.1, 1.1, 1.1)
            desk.position = v3(spots[1].x, 0.55, spots[1].y)
            scene.rootNode.addChildNode(desk)
            for (k, c) in [pink, teal, amber].enumerated() {
                let box = Looks.current.crate(color: c) ?? Props.crate(color: c)
                box.scale = SCNVector3(0.85, 0.85, 0.85)
                box.position = v3(spots[2].x + Double(k) * 0.05, 0.004 + Double(k) * 0.26, spots[2].y - Double(k) * 0.05)
                scene.rootNode.addChildNode(box)
            }
        }
        // The way work leaves: a rocket for staging, and one for production held on the pad.
        add("rockets: staging / production held", height: 2.4) { [self] p in
            ground(p, NSColor(rgb: (0.24, 0.26, 0.32)))
            let spots = spread(p, 2, gap: 1.1)
            let small = Looks.current.rocket(color: amber, tall: false, cargo: 0)
            small.position = v3(spots[0].x, 0, spots[0].y)
            scene.rootNode.addChildNode(small)
            let tall = Looks.current.rocket(color: teal, tall: true, cargo: 8)
            tall.position = v3(spots[1].x, 0, spots[1].y)
            if let own = Looks.current.hold(tall: true) { tall.addChildNode(own) } else { Props.attachTower(to: tall, tall: true, held: true) }
            scene.rootNode.addChildNode(tall)
        }
        // The way work arrives: the shuttle, coming down with a crate and going back up.
        add("shuttle: down / drop / up", height: 2.4) { [self] p in
            ground(p, NSColor(Colors.hangar))
            let ring = SCNNode(geometry: faceted(SCNTube(innerRadius: 0.3, outerRadius: 0.34, height: 0.01)))
            ring.geometry!.firstMaterial = flat(NSColor(Colors.hangar).lighter(0.18))
            ring.position = v3(p.x, 0.006, p.y)
            scene.rootNode.addChildNode(ring)
            let crate = Looks.current.crate(color: teal) ?? Props.crate(color: teal)
            crate.position = v3(p.x, 0.09, p.y); crate.opacity = 0
            scene.rootNode.addChildNode(crate)
            let ship = Looks.current.shuttle(color: teal)
            scene.rootNode.addChildNode(ship)
            func loop() {
                ship.position = v3(p.x, 3.5, p.y); crate.opacity = 0
                let down = SCNAction.move(to: v3(p.x, 0.55, p.y), duration: 3); down.timingMode = .easeInEaseOut
                let up = SCNAction.move(to: v3(p.x, 3.5, p.y), duration: 2); up.timingMode = .easeIn
                ship.runAction(.sequence([down, .wait(duration: 0.8),
                                          .run { _ in
                                              crate.opacity = 1
                                              crate.position = v3(p.x, 0.42, p.y)
                                              crate.runAction(.move(to: v3(p.x, 0.09, p.y), duration: 0.5))
                                          },
                                          .wait(duration: 1.2), up, .wait(duration: 1.5), .run { _ in loop() }]))
            }
            loop()
        }
        // The centre of a station, and the bunk in its quarters.
        add("monolith / bed", height: 2.6) { [self] p in
            let spots = spread(p, 2, gap: 1.2)
            let keep = Looks.current.monolith()
            keep.position = v3(spots[0].x, 0, spots[0].y)
            scene.rootNode.addChildNode(keep)
            let bunk = Looks.current.bed(level: 0)
            bunk.position = v3(spots[1].x, 0, spots[1].y)
            scene.rootNode.addChildNode(bunk)
        }
        // What the hands hold, all of it at once.
        add("tools in hand") { [self] p in
            let tools: [Minion.Tool] = [.goggles, .hammer, .scanner, .flashlight, .tablet]
            for (k, spot) in spread(p, tools.count, gap: 0.48).enumerated() {
                let m = body(at: spot)
                m.setTool(tools[k])
                m.node.eulerAngles.y = 0.5
            }
        }
    }

    // MARK: the clock

    /// A crate on its way, on the gallery's clock. The same tween the station uses, so the arcs
    /// cannot differ.
    private func move(_ node: SCNNode, _ legs: [MotionLeg]) {
        motions[ObjectIdentifier(node)] = CrateMotion(node: node, legs: legs, start: clock, yawTo: nil, onDone: nil)
    }

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        let dt = lastTime == 0 ? 0 : min(0.1, time - lastTime)
        lastTime = time
        clock += dt
        for u in updaters { u(clock, dt) }
        for m in bodies { m.stepFades(dt) }
        for (id, motion) in motions where motion.apply(at: clock) { motions[id] = nil }
        settle(by: 1 - exp(-dt * 10))
    }

    /// Eases the camera toward where it is meant to be; `k` of 1 puts it there at once.
    private func settle(by k: Double) {
        rig.eulerAngles.y += (Double.pi / 4 + yaw - Double(rig.eulerAngles.y)) * k
        pitchNode.eulerAngles.x += (pitch - Double(pitchNode.eulerAngles.x)) * k
        cameraNode.camera!.orthographicScale += (scale - cameraNode.camera!.orthographicScale) * k
        rig.position.x += (at.x - Double(rig.position.x)) * k
        rig.position.z += (at.y - Double(rig.position.z)) * k
    }

    func snapshot(to path: String) {
        let image = view.snapshot()
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: URL(fileURLWithPath: path))
    }
}
