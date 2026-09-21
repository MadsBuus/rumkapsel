import AppKit
import SceneKit

/// The things that populate a station, so the gallery and the scene draw the same props.
enum Props {
    /// The soft dark patch under a prop, the game's "foot": translucent, so it sits right on any floor.
    static func foot(size: Double) -> SCNNode {
        let f = SCNNode(geometry: SCNPlane(width: size, height: size))
        f.geometry!.firstMaterial = flat(NSColor(rgb: (0.05, 0.05, 0.08)))
        f.opacity = 0.28
        f.eulerAngles.x = -.pi / 2
        f.position = v3(size * 0.06, 0.004, size * 0.06)
        return f
    }

    /// A square pyramid with two lit faces and two shaded, like the game's resource pyramids.
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

    /// A plain crate: one pull request's worth of work, with a dark strap groove and a small status tag on top.
    /// Shapes mean things: a hexagon is a packed office, a cube is a piece of work (commits),
    /// a square strapped crate is a pull request, a pyramid is a session input.
    static func package(color: NSColor, band: NSColor, size: Double, approved: Bool = false, blink: Bool = false, mine: Bool = false) -> SCNNode {
        let n = SCNNode()
        let h = size * 0.8
        let box = SCNBox(width: size, height: h, length: size, chamferRadius: 0)
        box.materials = [flat(color), flat(color.darker(0.13)), flat(color), flat(color.darker(0.13)), flat(color.lighter(0.14)), flat(color)]
        let body = SCNNode(geometry: box)
        body.position = v3(0, h / 2, 0)
        n.addChildNode(body)
        // Strap groove: a slightly proud ring in a deeper shade, flush like a real crate strap. Your own
        // work is strapped in white instead: the crate is already its repository's colour, and a second
        // colour there would read as another repository.
        let strapColor = mine ? Palette.mine : color.darker(0.3)
        let strap = SCNBox(width: size * 1.02, height: h * 0.16, length: size * 1.02, chamferRadius: 0)
        strap.materials = mine
            ? [flat(strapColor), flat(strapColor.darker(0.12)), flat(strapColor), flat(strapColor.darker(0.12)), flat(strapColor.lighter(0.1)), flat(strapColor)]
            : [flat(color.darker(0.3)), flat(color.darker(0.38)), flat(color.darker(0.3)), flat(color.darker(0.38)), flat(color.darker(0.22)), flat(color.darker(0.3))]
        let s = SCNNode(geometry: strap)
        s.position = v3(0, h / 2, 0)
        n.addChildNode(s)
        // Status plate on the front face, like a lock, so it reads from the side whatever is stacked above.
        // The geometry is named, not the node: a redraw finds the plate by it and re-lights the crate
        // rather than building a new one, while the node stays nameless so a hover still finds the crate.
        let plate = SCNNode(geometry: SCNBox(width: size * 0.3, height: h * 0.28, length: 0.012, chamferRadius: 0))
        plate.geometry!.name = Props.plateName
        plate.geometry!.firstMaterial = flat(band)
        plate.position = v3(size * 0.2, h * 0.36, size / 2 + 0.006)
        if blink { plate.runAction(Props.blinking()) }
        n.addChildNode(plate)
        if approved { n.addChildNode(tag(size: size)) }
        n.addChildNode(foot(size: size * 1.3))
        return n
    }

    /// The name on a crate's status plate geometry, and on the shell round a failing one.
    static let plateName = "crate-plate"
    static let shellName = "crate-shell"

    /// The blink a plate carries while checks run.
    static func blinking() -> SCNAction {
        .repeatForever(.sequence([.fadeOpacity(to: 0.15, duration: 0.5), .fadeOpacity(to: 1, duration: 0.5)]))
    }

    /// Passed QA: a pale sticker on the lid with a green mark. Placed on a crate of this size, whether
    /// the crate is being built or the tag is slapped on one that already stands, in a carrier's arms.
    static func tag(size: Double) -> SCNNode {
        let h = size * 0.8
        let sticker = SCNNode(geometry: SCNBox(width: size * 0.42, height: 0.012, length: size * 0.42, chamferRadius: 0))
        sticker.geometry!.firstMaterial = flat(NSColor(rgb: (0.93, 0.95, 0.9)))
        sticker.position = v3(-size * 0.1, h + 0.006, size * 0.1)
        sticker.eulerAngles.y = 0.2
        let mark = SCNNode(geometry: SCNBox(width: size * 0.22, height: 0.012, length: size * 0.22, chamferRadius: 0))
        mark.geometry!.firstMaterial = flat(NSColor(rgb: (0.35, 0.85, 0.45)))
        mark.position = v3(0, 0.006, 0)
        mark.eulerAngles.y = .pi / 4
        sticker.addChildNode(mark)
        return sticker
    }

    /// The welding arc at a cone: a warm lamp with a billboard spark in it, put where the cone stands
    /// and switched on and off by `Routines.Flash.weld`.
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

    /// QA passed one: a green tick that floats off the head and fades. It carries its own rise, so
    /// whoever spawns it only has to place it and let it go.
    static func qaTick() -> SCNNode {
        let tick = SCNNode(geometry: SCNBox(width: 0.16, height: 0.02, length: 0.16, chamferRadius: 0))
        tick.eulerAngles = SCNVector3(Double.pi / 2, 0, Double.pi / 4)
        tick.geometry!.firstMaterial = flat(NSColor(rgb: (0.35, 0.9, 0.45)))
        tick.runAction(.sequence([.group([.moveBy(x: 0, y: 0.5, z: 0, duration: 0.9),
                                          .sequence([.wait(duration: 0.5), .fadeOut(duration: 0.4)])]),
                                  .removeFromParentNode()]))
        return tick
    }

    /// One commit: a cube in the office's colour with its own shadow under it. Flat game-style
    /// shading, light top, mid and dark sides, no lights involved. The three sizes the rows pick
    /// from are `cubeSizes`; an uncommitted one is the same cube at `ghostOpacity`.
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

    /// The red cage round a cube or a crate whose checks are failing.
    static func failingShell(size: Double) -> SCNNode {
        let shell = SCNNode(geometry: SCNBox(width: size, height: size, length: size, chamferRadius: 0))
        shell.geometry!.firstMaterial = flat(NSColor(rgb: (0.95, 0.2, 0.2)))
        shell.opacity = 0.2
        shell.runAction(.repeatForever(.sequence([.fadeOpacity(to: 0.55, duration: 0.7), .fadeOpacity(to: 0.15, duration: 0.9)])))
        return shell
    }

    /// The monolith's answer: a cone of light down onto whoever is asking it, as the game's research
    /// went. `aim` puts it between the two ends and breathes it.
    static func beam() -> SCNNode {
        let n = SCNNode(geometry: faceted(SCNCone(topRadius: 0.05, bottomRadius: 0.32, height: 1)))
        n.geometry!.firstMaterial = flat(NSColor(rgb: (0.75, 0.88, 1.0)))
        n.geometry!.firstMaterial?.transparency = 0.22
        n.geometry!.firstMaterial?.writesToDepthBuffer = false
        n.geometry!.firstMaterial?.isDoubleSided = true
        return n
    }

    /// Stretches a beam from the monolith's head down onto a body's, and breathes it on the clock.
    static func aim(_ beam: SCNNode, from: SIMD3<Double>, to: SIMD3<Double>, clock: Double, phase: Double) {
        let d = to - from
        let len = max(0.001, (d.x * d.x + d.y * d.y + d.z * d.z).squareRoot())
        let mid = (from + to) / 2
        beam.position = v3(mid.x, mid.y, mid.z)
        beam.scale = SCNVector3(1, len, 1)
        beam.look(at: v3(to.x, to.y, to.z), up: SCNVector3(0, 0, 1), localFront: SCNVector3(0, -1, 0))
        beam.opacity = 0.8 + 0.2 * sin(clock * 3 + phase)
    }

    /// A hexagonal crate in the repo colour: the order for a new office.
    static func crate(color: NSColor) -> SCNNode {
        let geo = faceted(SCNCylinder(radius: 0.26, height: 0.18))
        geo.radialSegmentCount = 6
        let top = flat(color.lighter(0.16)), side = flat(color.darker(0.06))
        geo.materials = [side, top, top]
        let n = SCNNode()
        let body = SCNNode(geometry: geo)   // same turn as the bay's hexagons, so it lands squarely on one
        n.addChildNode(body)
        return n
    }

    /// The hover pallet: a flat two-tier slab that floats a hand's breadth off the floor, with a
    /// glowing rim and a cushion of light under it. Its slots are `PalletGeometry`'s, so the plate is
    /// marked out wherever a crate can stand.
    static let palletWidth = PalletGeometry.width, palletDepth = PalletGeometry.depth, palletLift = PalletGeometry.lift

    static func pallet(color: NSColor) -> SCNNode {
        let n = SCNNode()
        let deckColor = NSColor(rgb: (0.34, 0.37, 0.46))
        let top = SCNNode(geometry: SCNBox(width: palletWidth, height: 0.05, length: palletDepth, chamferRadius: 0))
        top.geometry!.materials = [flat(deckColor), flat(deckColor.darker(0.1)), flat(deckColor), flat(deckColor.darker(0.1)),
                                   flat(deckColor.lighter(0.1)), flat(deckColor.darker(0.14))]
        n.addChildNode(top)
        // A narrower plate under it, so the silhouette is cut rather than a plain brick.
        let under = SCNNode(geometry: SCNBox(width: palletWidth - 0.16, height: 0.05, length: palletDepth - 0.16, chamferRadius: 0))
        under.geometry!.firstMaterial = lit(deckColor.darker(0.18))
        under.position = v3(0, -0.05, 0)
        n.addChildNode(under)
        // The rim strip: the only thing that says it is under power.
        for side in [-1.0, 1.0] {
            let strip = SCNNode(geometry: SCNBox(width: palletWidth - 0.1, height: 0.014, length: 0.03, chamferRadius: 0))
            strip.geometry!.firstMaterial = flat(color.lighter(0.2))
            strip.position = v3(0, 0.02, side * (palletDepth / 2 - 0.02))
            n.addChildNode(strip)
        }
        // A shallow field sunk into the plate per crate slot, so the deck is not a blank sheet.
        for row in 0..<PalletGeometry.rows {
            for column in 0..<PalletGeometry.columns {
                let field = SCNNode(geometry: SCNBox(width: 0.36, height: 0.014, length: 0.36, chamferRadius: 0))
                field.geometry!.firstMaterial = flat(deckColor.darker(0.26))
                let at = palletOffset(row: row, column: column, level: 0)
                field.position = v3(at.x, 0.029, at.z)   // proud of the plate's own face, or the two fight
                n.addChildNode(field)
            }
        }
        // Rivets along the rim: tiny cubes, evenly spaced, standing proud of the plate.
        func rivet(_ x: Double, _ z: Double) {
            let r = SCNNode(geometry: SCNBox(width: 0.036, height: 0.036, length: 0.036, chamferRadius: 0))
            r.geometry!.firstMaterial = lit(deckColor.lighter(0.28))
            r.position = v3(x, 0.042, z)
            n.addChildNode(r)
        }
        for i in 0..<8 {
            let x = -palletWidth / 2 + 0.09 + Double(i) * (palletWidth - 0.18) / 7
            rivet(x, -palletDepth / 2 + 0.05)
            if x < palletWidth / 2 - 0.2 { rivet(x, palletDepth / 2 - 0.05) }   // room for the light on that corner
        }
        for i in 0..<4 {
            let z = -palletDepth / 2 + 0.09 + Double(i) * (palletDepth - 0.18) / 3
            rivet(-palletWidth / 2 + 0.05, z)
            if z < palletDepth / 2 - 0.2 { rivet(palletWidth / 2 - 0.05, z) }
        }
        // The warning light on the near corner. The tick blinks it, so it blinks headless too.
        let beacon = SCNNode(geometry: SCNBox(width: 0.09, height: 0.09, length: 0.09, chamferRadius: 0))
        let lamp = flat(palletAmber)
        lamp.emission.contents = palletAmber
        beacon.geometry!.firstMaterial = lamp
        beacon.position = v3(palletWidth / 2 - 0.08, 0.07, palletDepth / 2 - 0.08)
        beacon.name = "beacon"
        n.addChildNode(beacon)
        // The cushion of light it rides on.
        let glow = SCNNode(geometry: SCNPlane(width: palletWidth - 0.1, height: palletDepth - 0.1))
        glow.geometry!.firstMaterial = flat(color)
        glow.opacity = 0.22
        glow.eulerAngles.x = -.pi / 2
        glow.position = v3(0, -palletLift + 0.01, 0)
        n.addChildNode(glow)
        return n
    }

    /// The corner light's colour, on and off.
    static let palletAmber = NSColor(rgb: (1.0, 0.56, 0.12))
    static let palletAmberOff = NSColor(rgb: (0.42, 0.24, 0.08))

    /// The dark patch the pallet throws on the floor. It does not bob with the slab: it tightens and
    /// darkens as the pallet sinks, as if the light stood close overhead.
    static func palletShadow() -> SCNNode {
        let s = SCNNode(geometry: SCNPlane(width: palletWidth, height: palletDepth))
        let m = flat(NSColor(rgb: (0.05, 0.05, 0.08)))
        m.transparency = 0.34   // the darkness lives in the material, so the node's opacity is free to fade
        s.geometry!.firstMaterial = m
        s.eulerAngles.x = -.pi / 2
        return s
    }

    /// Where crate `index` stands on a pallet: four across, two rows back, stacked past eight.
    static func palletSlot(_ index: Int) -> (row: Int, column: Int, level: Int) { PalletGeometry.slot(index) }

    /// That slot's place on the pallet's own top plate.
    static func palletOffset(row: Int, column: Int, level: Int) -> SIMD3<Double> { PalletGeometry.offset(row: row, column: column, level: level) }

    /// A small wall panel: the storage console, where a pallet is ordered.
    static func console(color: NSColor) -> SCNNode {
        let n = SCNNode()
        let shell = SCNNode(geometry: SCNBox(width: 0.34, height: 0.26, length: 0.09, chamferRadius: 0))
        shell.geometry!.firstMaterial = lit(NSColor(rgb: (0.26, 0.28, 0.34)))
        n.addChildNode(shell)
        let panel = SCNNode(geometry: SCNBox(width: 0.24, height: 0.16, length: 0.02, chamferRadius: 0))
        panel.geometry!.firstMaterial = flat(color)
        panel.position = v3(0, 0.02, 0.055)
        panel.name = "panel"
        n.addChildNode(panel)
        for k in 0..<3 {
            let key = SCNNode(geometry: SCNBox(width: 0.05, height: 0.03, length: 0.02, chamferRadius: 0))
            key.geometry!.firstMaterial = flat(NSColor(rgb: (0.5, 0.53, 0.6)))
            key.position = v3(-0.07 + Double(k) * 0.07, -0.09, 0.05)
            n.addChildNode(key)
        }
        return n
    }

    static func rocket(color: NSColor, tall: Bool, cargo: Int = 0) -> SCNNode {
        let n = SCNNode()
        // A production rocket grows with what it will carry: small for a couple of boxes, big for a dozen.
        let grow = tall ? min(1.6, 0.85 + Double(cargo) * 0.06) : 1.0
        let h = (tall ? 1.5 : 0.9) * grow, r = (tall ? 0.17 : 0.12) * (0.7 + 0.3 * grow)
        let white = lit(NSColor(rgb: (0.92, 0.92, 0.95)))
        let dark = lit(NSColor(rgb: (0.2, 0.21, 0.26)))
        // The loading hatch: a door in the hull, white with a dark seam round it, a latch bar and two hinge
        // knuckles; open, the door is the black of the hold. The seam sits inside the hull so nothing floats.
        let hatch = SCNNode()
        hatch.name = "hatch"
        let frameW = r * 0.9, frameH = 0.2
        let frame = SCNNode(geometry: SCNBox(width: frameW, height: frameH, length: 0.03, chamferRadius: 0))
        frame.geometry!.firstMaterial = dark
        frame.position = v3(0, 0, -0.012)
        hatch.addChildNode(frame)
        let panel = SCNNode(geometry: SCNBox(width: frameW - 0.02, height: frameH - 0.02, length: 0.02, chamferRadius: 0))
        panel.geometry!.firstMaterial = white
        panel.name = "door"
        panel.position = v3(0, 0, 0.004)
        hatch.addChildNode(panel)
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
        // High on the payload section, on the tower's side, where cargo comes in. The hull has six flat sides
        // and this is the middle of one, at the apothem.
        hatch.position = v3(r * 0.866 + 0.003, 0.12 + h * 0.6, 0)
        hatch.eulerAngles.y = .pi / 2
        n.addChildNode(hatch)
        // Body, a slightly wider lower stage, and a nose cone in the repo colour.
        let lower = SCNNode(geometry: faceted(SCNCylinder(radius: r, height: h * 0.45)))
        lower.geometry!.firstMaterial = white
        lower.position = v3(0, 0.12 + h * 0.225, 0)
        n.addChildNode(lower)
        let band = SCNNode(geometry: faceted(SCNCylinder(radius: r * 1.02, height: h * 0.08)))
        band.geometry!.firstMaterial = lit(color)
        band.position = v3(0, 0.12 + h * 0.45, 0)
        n.addChildNode(band)
        let upper = SCNNode(geometry: faceted(SCNCylinder(radius: r * 0.9, height: h * 0.4)))
        upper.geometry!.firstMaterial = white
        upper.position = v3(0, 0.12 + h * 0.49 + h * 0.2, 0)
        n.addChildNode(upper)
        let nose = SCNNode(geometry: faceted(SCNCone(topRadius: 0, bottomRadius: r * 0.9, height: r * 2.6)))
        nose.geometry!.firstMaterial = lit(color)
        nose.position = v3(0, 0.12 + h * 0.89 + r * 1.3, 0)
        n.addChildNode(nose)
        // Portholes on the upper stage.
        for k in 0..<3 {
            let port = SCNNode(geometry: SCNBox(width: r * 0.36, height: r * 0.36, length: 0.02, chamferRadius: 0))   // a flat pane, not a cube
            port.geometry!.firstMaterial = flat(NSColor(rgb: (0.35, 0.55, 0.85)))
            let a = Double(k) * 2 * .pi / 3
            port.position = v3(sin(a) * r * 0.86, 0.12 + h * 0.75, cos(a) * r * 0.86)
            port.eulerAngles.y = a
            n.addChildNode(port)
        }
        // Four tail fins: each a plate leaning in, its top edge buried in the lower stage, its bottom outer
        // corner out by the pad.
        for k in 0..<4 {
            let pivot = SCNNode()
            pivot.eulerAngles.y = Double(k) * .pi / 2 + .pi / 4
            let finH = r * 2.6, finL = r * 1.3, lean = 0.42
            let fin = SCNNode(geometry: SCNBox(width: 0.035, height: finH, length: finL, chamferRadius: 0))
            fin.geometry!.firstMaterial = lit(color)
            // Placed so that leaning by `lean` puts the top inner corner inside the hull.
            fin.position = v3(0, 0.12 + finH * 0.45, r * 0.3 + finL * 0.5 + finH * 0.5 * sin(lean) * 0.5)
            fin.eulerAngles.x = -lean
            pivot.addChildNode(fin)
            n.addChildNode(pivot)
        }
        // The engine: a throat under the hull opening into a bell, its mouth just off the pad.
        let throat = SCNNode(geometry: faceted(SCNCylinder(radius: r * 0.35, height: 0.04)))
        throat.geometry!.firstMaterial = dark
        throat.position = v3(0, 0.11, 0)
        n.addChildNode(throat)
        let bell = SCNNode(geometry: faceted(SCNCone(topRadius: r * 0.35, bottomRadius: r * 0.75, height: 0.09)))
        bell.geometry!.firstMaterial = lit(NSColor(rgb: (0.3, 0.31, 0.36)))
        bell.position = v3(0, 0.055, 0)
        n.addChildNode(bell)
        // Landing legs, splayed out at the foot: the knee on the hull above the fin roots, the pad out on the ground.
        for k in 0..<3 {
            let pivot = SCNNode()
            pivot.eulerAngles.y = Double(k) * 2 * .pi / 3 + .pi / 3   // none in front of the hatch
            let leg = SCNNode(geometry: SCNBox(width: 0.03, height: 0.24, length: 0.03, chamferRadius: 0))
            leg.geometry!.firstMaterial = dark
            leg.position = v3(0, 0.11, r * 1.15)
            leg.eulerAngles.x = -0.55
            pivot.addChildNode(leg)
            let foot = SCNNode(geometry: SCNBox(width: 0.06, height: 0.02, length: 0.06, chamferRadius: 0))
            foot.geometry!.firstMaterial = dark
            foot.position = v3(0, 0.01, r * 1.15 + 0.12 * sin(0.55))
            pivot.addChildNode(foot)
            n.addChildNode(pivot)
        }
        let flame = SCNNode(geometry: faceted(SCNCone(topRadius: r * 0.6, bottomRadius: 0, height: 0.45)))
        flame.geometry!.firstMaterial = flat(Palette.pyramid)
        flame.position = v3(0, -0.2, 0)
        flame.name = "flame"
        flame.opacity = 0
        n.addChildNode(flame)
        return n
    }

    /// The service tower stood beside a rocket, its conveyor at the hatch: on the pad from the moment the
    /// rocket stands to the moment it goes. The beacon is lit red while the rocket is held.
    static func attachTower(to rocket: SCNNode, tall: Bool, held: Bool) {
        let hatchY = rocket.childNode(withName: "hatch", recursively: true).map { Double($0.position.y) }
        let deco = holdDecoration(around: SIMD3(0, 0, 0), tall: tall, armAt: hatchY, held: held)
        deco.name = "hold"
        rocket.addChildNode(deco)
    }

    static func holdDecoration(around center: SIMD3<Double>, tall: Bool, armAt: Double? = nil, held: Bool = true) -> SCNNode {
        let n = SCNNode()
        // The service tower: a steel column beside the rocket, a lift rail up its face on the rocket's side,
        // a cap and a beacon on top.
        let h = max(tall ? 1.7 : 1.1, (armAt ?? 0) + 0.25)
        let armY = armAt ?? h - 0.12
        let steel = lit(NSColor(rgb: (0.55, 0.57, 0.62))), dark = lit(NSColor(rgb: (0.38, 0.4, 0.45)))
        let tower = SCNNode()
        let w = 0.16
        let column = SCNNode(geometry: SCNBox(width: w, height: h, length: w, chamferRadius: 0))
        column.geometry!.firstMaterial = steel
        column.position = v3(0, h / 2, 0)
        tower.addChildNode(column)
        let rail = SCNNode(geometry: SCNBox(width: 0.02, height: h - 0.1, length: 0.06, chamferRadius: 0))
        rail.geometry!.firstMaterial = dark
        rail.position = v3(-w / 2 - 0.005, (h - 0.1) / 2, 0)
        tower.addChildNode(rail)
        let cap = SCNNode(geometry: SCNBox(width: w + 0.04, height: 0.04, length: w + 0.04, chamferRadius: 0))
        cap.geometry!.firstMaterial = dark
        cap.position = v3(0, h + 0.02, 0)
        tower.addChildNode(cap)
        // The conveyor from the tower to the hatch: a belt with rollers and a rail each side, hinged at the
        // tower's face so it swings back along the tower once the rocket is loaded.
        let armLen = 0.3
        let hinge = SCNNode()
        hinge.name = "arm"
        hinge.position = v3(-w / 2 + 0.02, armY - 0.1, 0)
        let belt = SCNNode(geometry: SCNBox(width: armLen, height: 0.03, length: 0.1, chamferRadius: 0))
        belt.geometry!.firstMaterial = lit(NSColor(rgb: (0.22, 0.23, 0.27)))
        belt.position = v3(-armLen / 2, 0, 0)
        hinge.addChildNode(belt)
        for k in 0..<5 {
            let roller = SCNNode(geometry: SCNBox(width: 0.012, height: 0.006, length: 0.09, chamferRadius: 0))
            roller.geometry!.firstMaterial = steel
            roller.position = v3(-armLen * (0.1 + 0.2 * Double(k)), 0.018, 0)
            hinge.addChildNode(roller)
        }
        for dz in [-0.055, 0.055] {
            let side = SCNNode(geometry: SCNBox(width: armLen, height: 0.04, length: 0.012, chamferRadius: 0))
            side.geometry!.firstMaterial = steel
            side.position = v3(-armLen / 2, 0.01, dz)
            hinge.addChildNode(side)
        }
        tower.addChildNode(hinge)
        // A beacon on top: lit red while the rocket is held, dark once it is cleared.
        let beacon = SCNNode(geometry: SCNBox(width: 0.04, height: 0.05, length: 0.04, chamferRadius: 0))
        beacon.geometry!.firstMaterial = held ? flat(NSColor(rgb: (0.95, 0.25, 0.2))) : dark
        beacon.name = "beacon"
        beacon.position = v3(0, h + 0.065, 0)
        tower.addChildNode(beacon)
        tower.position = v3(center.x + 0.44, 0, center.z + 0.02)
        tower.name = "tower"
        n.addChildNode(tower)
        return n
    }

}
