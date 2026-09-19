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
        // The loading hatch: a small dark plate at the foot on the deck side, where crates go in.
        let hatch = SCNNode(geometry: SCNBox(width: r * 1.1, height: 0.2, length: 0.02, chamferRadius: 0))
        hatch.geometry!.firstMaterial = dark
        hatch.position = v3(0, 0.22, r + 0.005)
        hatch.name = "hatch"
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
        // Four swept fins and an engine nozzle.
        for k in 0..<4 {
            let pivot = SCNNode()
            pivot.eulerAngles.y = Double(k) * .pi / 2 + .pi / 4
            let fin = SCNNode(geometry: SCNBox(width: 0.035, height: r * 2.4, length: r * 1.5, chamferRadius: 0))
            fin.geometry!.firstMaterial = lit(color)
            fin.position = v3(0, 0.12 + r * 1.0, r + r * 0.55)
            fin.eulerAngles.x = 0.35
            pivot.addChildNode(fin)
            n.addChildNode(pivot)
        }
        let nozzle = SCNNode(geometry: faceted(SCNCone(topRadius: r * 0.55, bottomRadius: r * 0.8, height: 0.14)))
        nozzle.geometry!.firstMaterial = dark
        nozzle.position = v3(0, 0.05, 0)
        n.addChildNode(nozzle)
        // Landing legs so it stands on the pad.
        for k in 0..<3 {
            let pivot = SCNNode()
            pivot.eulerAngles.y = Double(k) * 2 * .pi / 3
            let leg = SCNNode(geometry: SCNBox(width: 0.03, height: 0.22, length: 0.03, chamferRadius: 0))
            leg.geometry!.firstMaterial = dark
            leg.position = v3(0, 0.1, r * 1.1)
            leg.eulerAngles.x = 0.5
            pivot.addChildNode(leg)
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

    /// The service tower beside a rocket that is up but not cleared to fly: it stays attached until the
    /// rocket is cleared, and a rocket ready to go stands alone, as on a real pad.
    static func holdDecoration(around center: SIMD3<Double>, tall: Bool) -> SCNNode {
        let n = SCNNode()
        // The service tower: a steel lattice beside the rocket, as a real pad has, with cross-bracing
        // between the legs, a work platform every so often, and a swing arm out to the rocket at the top.
        // Grey steel, a red beacon on top; nothing wooden stands on a launch pad.
        let h = tall ? 1.7 : 1.1
        let steel = lit(NSColor(rgb: (0.55, 0.57, 0.62))), dark = lit(NSColor(rgb: (0.38, 0.4, 0.45)))
        let tower = SCNNode()
        let w = 0.18, leg = 0.025
        for (dx, dz) in [(-w / 2, -w / 2), (w / 2, -w / 2), (-w / 2, w / 2), (w / 2, w / 2)] {
            let l = SCNNode(geometry: SCNBox(width: leg, height: h, length: leg, chamferRadius: 0))
            l.geometry!.firstMaterial = steel
            l.position = v3(dx, h / 2, dz)
            tower.addChildNode(l)
        }
        let bay = 0.22
        var y = bay
        var level = 0
        while y < h - 0.02 {
            // Horizontal braces round the four sides, and a diagonal across each, alternating direction.
            for side in 0..<4 {
                let along = side % 2 == 0
                let brace = SCNNode(geometry: SCNBox(width: along ? w : leg * 0.8, height: leg * 0.8, length: along ? leg * 0.8 : w, chamferRadius: 0))
                brace.geometry!.firstMaterial = steel
                let off = (side < 2 ? -1.0 : 1.0) * w / 2
                brace.position = along ? v3(0, y, off) : v3(off, y, 0)
                tower.addChildNode(brace)
                let diagLen = (w * w + bay * bay).squareRoot()
                let diag = SCNNode(geometry: SCNBox(width: diagLen, height: leg * 0.6, length: leg * 0.6, chamferRadius: 0))
                diag.geometry!.firstMaterial = dark
                diag.position = along ? v3(0, y - bay / 2, off) : v3(off, y - bay / 2, 0)
                let tilt = atan2(bay, w) * ((level + side) % 2 == 0 ? 1 : -1)
                diag.eulerAngles = along ? SCNVector3(0, 0, tilt) : SCNVector3(0, .pi / 2, tilt)
                tower.addChildNode(diag)
            }
            // A work platform every other bay: a grating that sticks out towards the rocket.
            if level % 2 == 1 {
                let deck = SCNNode(geometry: SCNBox(width: w + 0.16, height: 0.02, length: w + 0.04, chamferRadius: 0))
                deck.geometry!.firstMaterial = dark
                deck.position = v3(-0.08, y + 0.01, 0)
                tower.addChildNode(deck)
                let rail = SCNNode(geometry: SCNBox(width: w + 0.16, height: 0.012, length: 0.012, chamferRadius: 0))
                rail.geometry!.firstMaterial = steel
                rail.position = v3(-0.08, y + 0.09, (w + 0.04) / 2)
                tower.addChildNode(rail)
            }
            y += bay; level += 1
        }
        // The swing arm at the top, out to the rocket's side, with the umbilical's box on its end.
        let armLen = 0.3
        let arm = SCNNode(geometry: SCNBox(width: armLen, height: 0.04, length: 0.06, chamferRadius: 0))
        arm.geometry!.firstMaterial = steel
        arm.position = v3(-w / 2 - armLen / 2 + 0.02, h - 0.12, 0)
        tower.addChildNode(arm)
        let umbilical = SCNNode(geometry: SCNBox(width: 0.06, height: 0.08, length: 0.08, chamferRadius: 0))
        umbilical.geometry!.firstMaterial = dark
        umbilical.position = v3(-w / 2 - armLen + 0.04, h - 0.14, 0)
        tower.addChildNode(umbilical)
        // A beacon on top.
        let beacon = SCNNode(geometry: SCNBox(width: 0.04, height: 0.05, length: 0.04, chamferRadius: 0))
        beacon.geometry!.firstMaterial = flat(NSColor(rgb: (0.95, 0.25, 0.2)))
        beacon.position = v3(0, h + 0.025, 0)
        tower.addChildNode(beacon)
        tower.position = v3(center.x + 0.44, 0, center.z + 0.02)
        n.addChildNode(tower)
        return n
    }

}
