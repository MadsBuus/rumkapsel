// A repository's colony on its planet: hab pods panelled in its colour, a glass dome, tanks, a radio mast,
// solar rows, lamps, a rover, people in suits, boulders, and a flag with the release that last landed.
// Built in the colony's own frame, the ground at the origin and up along +Y, and seen only onboard.

import AppKit
import SceneKit

enum Colonies {
    /// `ground` is the planet's radius: each piece is set down on its curve.
    static func build(repo: String, color: NSColor, release: String, ground: Double) -> SCNNode {
        let colony = SCNNode()
        colony.name = "colony"
        var rng = SplitMix(seed: UInt64(Planets.seed(repo)) &* 2654435761)
        let still = SCNNode()   // everything that never moves
        let live = SCNNode()    // lights that blink, people, the flag

        pad(into: still, live: live, color: color)

        // Pods round one side joined by tubes, the dome, the tanks, the mast, solar rows further out.
        let turn = rng.next() * 2 * .pi
        func spot(_ a: Double, _ d: Double) -> SIMD3<Double> { SIMD3(cos(a + turn) * d, 0, sin(a + turn) * d) }
        let podCount = 2 + Int(rng.next() * 2)
        var pods: [SIMD3<Double>] = []
        for i in 0..<podCount {
            let at = spot(0.9 + Double(i) * 0.5, 0.32 + rng.next() * 0.05)
            let pod = habPod(size: 0.85 + rng.next() * 0.35, color: color, seed: rng.next())
            pod.position = v3(at.x, 0, at.z)
            pod.eulerAngles.y = CGFloat(rng.next() * .pi * 2)
            still.addChildNode(pod)
            pods.append(at)
        }
        for i in 1..<pods.count { still.addChildNode(tube(from: pods[i - 1], to: pods[i])) }
        let domeAt = spot(-0.7, 0.36)
        let dome = glassDome(size: 1 + rng.next() * 0.3, seed: rng.next())
        dome.position = v3(domeAt.x, 0, domeAt.z)
        still.addChildNode(dome)
        still.addChildNode(tube(from: pods[0], to: domeAt))
        let farm = tanks(count: 3 + Int(rng.next() * 3), color: color, seed: rng.next())
        let tanksAt = spot(-1.5, 0.4)
        farm.position = v3(tanksAt.x, 0, tanksAt.z)
        still.addChildNode(farm)
        mast(at: spot(3.3, 0.46), into: still, live: live)
        for row in 0..<2 {
            let a = 2.5 + Double(row) * 0.28
            let solar = solarRow(panels: 4 + Int(rng.next() * 3))
            let at = spot(a, 0.56)
            solar.position = v3(at.x, 0, at.z)
            solar.eulerAngles.y = CGFloat(-(a + turn))
            still.addChildNode(solar)
        }
        let roverAt = spot(-2.4, 0.3)
        let r = rover(color: color)
        r.position = v3(roverAt.x, 0, roverAt.z)
        r.eulerAngles.y = CGFloat(rng.next() * .pi * 2)
        still.addChildNode(r)
        for k in 0..<5 { lamp(at: spot(Double(k) * 1.25 + 0.3, 0.26 + Double(k % 2) * 0.04), into: still, live: live) }
        rocks(into: still, rng: &rng, color: color)

        // People out on the regolith: one by the flag, one walking between the pods, one at the rover.
        let flagAt = SIMD3(0.1, 0.0, 0.05)
        for (i, at) in [flagAt + SIMD3(0.025, 0, 0.02), pods[0] + SIMD3(0.05, 0, 0.04), roverAt + SIMD3(0.04, 0, -0.02)].enumerated() {
            let a = astronaut()
            a.position = v3(at.x, 0, at.z)
            a.eulerAngles.y = CGFloat(rng.next() * .pi * 2)
            if i == 1 {
                a.runAction(.repeatForever(.sequence([.moveBy(x: -0.07, y: 0, z: 0.03, duration: 7), .rotateBy(x: 0, y: .pi, z: 0, duration: 0.8),
                                                      .moveBy(x: 0.07, y: 0, z: -0.03, duration: 7), .rotateBy(x: 0, y: .pi, z: 0, duration: 0.8)])))
            }
            live.addChildNode(a)
        }
        let flagNode = flag(repo: repo, release: release, color: color)
        flagNode.position = v3(flagAt.x, 0, flagAt.z)
        live.addChildNode(flagNode)

        // A low light over the colony, the ground and the landed tip.
        let sun = SCNNode()
        sun.light = SCNLight()
        sun.light!.type = .spot
        sun.light!.intensity = 1000
        sun.light!.color = NSColor(rgb: (1, 0.96, 0.9))
        sun.light!.spotInnerAngle = 40
        sun.light!.spotOuterAngle = 80
        sun.light!.castsShadow = true
        sun.light!.shadowMapSize = CGSize(width: 2048, height: 2048)
        sun.light!.shadowRadius = 1.5
        sun.light!.shadowSampleCount = 8
        sun.light!.shadowColor = NSColor.black.withAlphaComponent(0.75)
        sun.light!.zNear = 0.05
        sun.light!.zFar = 4
        sun.light!.categoryBitMask = Pick.colony | Pick.planet | Pick.onboard
        sun.position = v3(0.75, 0.55, 0.45)
        sun.look(at: SCNVector3(0, 0, 0))
        colony.addChildNode(sun)

        for piece in still.childNodes + live.childNodes { settle(piece, on: ground) }
        colony.addChildNode(still)
        colony.addChildNode(live)
        colony.enumerateHierarchy { n, _ in if n.light == nil { n.categoryBitMask = Pick.colony } }
        return colony
    }

    // MARK: the pieces

    /// Sets a piece down on a ball of this radius whose top is the colony's origin: dropped to the surface
    /// and tilted to stand square on it.
    private static func settle(_ piece: SCNNode, on r: Double) {
        let p = SIMD3(Double(piece.position.x), Double(piece.position.y), Double(piece.position.z))
        let d = (p.x * p.x + p.z * p.z).squareRoot()
        guard d > 0.001, d < r else { return }
        let up = simd_normalize(SIMD3(p.x, (r * r - d * d).squareRoot(), p.z))
        piece.position = v3(p.x, p.y + (r * r - d * d).squareRoot() - r, p.z)
        let tilt = simd_quatd(from: SIMD3(0, 1, 0), to: up)
        let own = simd_quatd(ix: Double(piece.orientation.x), iy: Double(piece.orientation.y), iz: Double(piece.orientation.z), r: Double(piece.orientation.w))
        let q = tilt * own
        piece.orientation = SCNQuaternion(q.imag.x, q.imag.y, q.imag.z, q.real)
    }

    private static func blinn(_ c: NSColor, shine: CGFloat = 0.25) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .blinn
        m.diffuse.contents = c
        m.specular.contents = NSColor(white: shine, alpha: 1)
        m.shininess = 0.35
        return m
    }
    private static let panel = blinn(NSColor(rgb: (0.26, 0.27, 0.3)))
    private static let hull = blinn(NSColor(rgb: (0.82, 0.83, 0.86)), shine: 0.4)
    private static let steel = blinn(NSColor(rgb: (0.55, 0.57, 0.6)), shine: 0.5)
    private static let dark = blinn(NSColor(rgb: (0.12, 0.12, 0.14)))
    private static let glow = flat(NSColor(rgb: (1, 0.82, 0.48)))

    /// The landing pad: a slab with a ring and a cross in the repository's colour, lights round its rim.
    private static func pad(into still: SCNNode, live: SCNNode, color: NSColor) {
        let slab = SCNNode(geometry: faceted(SCNCylinder(radius: 0.08, height: 0.006), 6))
        slab.geometry!.firstMaterial = blinn(NSColor(rgb: (0.36, 0.37, 0.4)))
        slab.position = v3(0, 0.003, 0)
        still.addChildNode(slab)
        let ring = SCNNode(geometry: faceted(SCNTube(innerRadius: 0.058, outerRadius: 0.064, height: 0.0068), 6))
        ring.geometry!.firstMaterial = lit(color)
        ring.position = v3(0, 0.0034, 0)
        still.addChildNode(ring)
        for a in [0.0, Double.pi / 2] {
            let bar = SCNNode(geometry: SCNBox(width: 0.07, height: 0.0068, length: 0.008, chamferRadius: 0))
            bar.geometry!.firstMaterial = lit(NSColor(white: 0.85, alpha: 1))
            bar.position = v3(0, 0.0034, 0); bar.eulerAngles.y = CGFloat(a + .pi / 4)
            still.addChildNode(bar)
        }
        for k in 0..<6 {
            let a = Double(k) * .pi / 3
            let light = SCNNode(geometry: SCNBox(width: 0.006, height: 0.004, length: 0.006, chamferRadius: 0))
            light.geometry!.firstMaterial = flat(NSColor(rgb: (0.6, 0.9, 1)))
            light.position = v3(cos(a) * 0.076, 0.008, sin(a) * 0.076)
            light.runAction(.repeatForever(.sequence([.wait(duration: Double(k) * 0.15), .fadeOpacity(to: 0.2, duration: 0.3),
                                                      .fadeOpacity(to: 1, duration: 0.3), .wait(duration: 1.2 - Double(k) * 0.15)])))
            live.addChildNode(light)
        }
    }

    /// A hab pod: a faceted shell of panels, some of them insulation in the repository's colour and a band
    /// of lit windows, its seams dark, on skids, with a door and steps.
    private static func habPod(size s: Double, color: NSColor, seed: Double) -> SCNNode {
        let pod = SCNNode()
        var rng = SplitMix(seed: UInt64(seed * 1e9))
        let r = 0.055 * s
        let (verts, faces) = Mesh.icosphere(1)
        let squash = SIMD3(1.0, 0.74, 1.0) * r
        var tris: [(SIMD3<Double>, SIMD3<Double>, SIMD3<Double>)] = [], kinds: [Int] = []
        for f in faces {
            let a = verts[f.0], b = verts[f.1], c = verts[f.2]
            let centre = (a + b + c) / 3
            guard centre.y > -0.3 else { continue }
            let kind = centre.y > 0.6 ? 0 : abs(centre.y) < 0.28 && rng.next() < 0.3 ? 2 : rng.next() < 0.42 ? 1 : 0
            tris.append((a * squash, b * squash, c * squash)); kinds.append(kind)
        }
        let shell = SCNNode(geometry: Mesh.faceted(tris, kinds, [panel, blinn(color.darker(0.15)), glow]))
        shell.position = v3(0, r * 0.62, 0)
        let seams = SCNNode(geometry: Mesh.edges(tris.map { ($0.0 * 1.004, $0.1 * 1.004, $0.2 * 1.004) }, flat(NSColor(white: 0.05, alpha: 1))))
        seams.position = shell.position
        pod.addChildNode(shell); pod.addChildNode(seams)
        for side in [-1.0, 1.0] {
            let skid = SCNNode(geometry: SCNBox(width: r * 2, height: 0.006, length: 0.008, chamferRadius: 0))
            skid.geometry!.firstMaterial = dark
            skid.position = v3(0, 0.003, side * r * 0.55)
            pod.addChildNode(skid)
        }
        let door = SCNNode(geometry: SCNBox(width: 0.018, height: 0.026, length: 0.01, chamferRadius: 0))
        door.geometry!.firstMaterial = hull
        door.position = v3(0, 0.02, r * 0.98)
        pod.addChildNode(door)
        for k in 0..<3 {
            let step = SCNNode(geometry: SCNBox(width: 0.02, height: 0.003, length: 0.008, chamferRadius: 0))
            step.geometry!.firstMaterial = steel
            step.position = v3(0, 0.004 + Double(k) * 0.005, r * 0.98 + 0.014 - Double(k) * 0.006)
            pod.addChildNode(step)
        }
        return pod
    }

    /// A geodesic dome of glass on a white ring, its frame showing, green growing inside.
    private static func glassDome(size s: Double, seed: Double) -> SCNNode {
        let dome = SCNNode()
        let r = 0.07 * s
        let (verts, faces) = Mesh.icosphere(2)
        var tris: [(SIMD3<Double>, SIMD3<Double>, SIMD3<Double>)] = []
        for f in faces {
            let a = verts[f.0] * r, b = verts[f.1] * r, c = verts[f.2] * r
            if (a.y + b.y + c.y) / 3 > 0.02 * r { tris.append((a, b, c)) }
        }
        let glass = SCNMaterial()
        glass.lightingModel = .blinn
        glass.diffuse.contents = NSColor(rgb: (0.55, 0.75, 0.85))
        glass.specular.contents = NSColor.white
        glass.shininess = 0.8
        glass.transparency = 0.35
        glass.isDoubleSided = true
        glass.writesToDepthBuffer = false
        let shell = SCNNode(geometry: Mesh.faceted(tris, Array(repeating: 0, count: tris.count), [glass]))
        shell.renderingOrder = 10
        let frame = SCNNode(geometry: Mesh.edges(tris, flat(NSColor(white: 0.82, alpha: 1))))
        let ring = SCNNode(geometry: faceted(SCNCylinder(radius: r * 1.03, height: 0.01), 16))
        ring.geometry!.firstMaterial = hull
        ring.position = v3(0, 0.005, 0)
        let floor = SCNNode(geometry: faceted(SCNCylinder(radius: r * 0.95, height: 0.004), 16))
        floor.geometry!.firstMaterial = flat(NSColor(rgb: (0.28, 0.45, 0.25)))
        floor.position = v3(0, 0.011, 0)
        dome.addChildNode(ring); dome.addChildNode(floor); dome.addChildNode(shell); dome.addChildNode(frame)
        var rng = SplitMix(seed: UInt64(seed * 1e9))
        for _ in 0..<7 {
            let a = rng.next() * 2 * .pi, d = rng.next() * r * 0.65, h = 0.015 + rng.next() * 0.025
            let tree = SCNNode(geometry: faceted(SCNCone(topRadius: 0, bottomRadius: 0.008 + rng.next() * 0.006, height: h), 6))
            tree.geometry!.firstMaterial = lit(NSColor(rgb: (0.25, 0.55 + rng.next() * 0.2, 0.3)))
            tree.position = v3(cos(a) * d, 0.013 + h / 2, sin(a) * d)
            dome.addChildNode(tree)
        }
        return dome
    }

    /// A walkway tube between two modules, ribbed.
    private static func tube(from a: SIMD3<Double>, to b: SIMD3<Double>) -> SCNNode {
        let length = simd_distance(a, b)
        let t = SCNNode()
        t.position = v3((a.x + b.x) / 2, 0.022, (a.z + b.z) / 2)
        t.look(at: v3(b.x, 0.022, b.z), up: SCNVector3(0, 1, 0), localFront: SCNVector3(0, 1, 0))
        let body = SCNNode(geometry: faceted(SCNCylinder(radius: 0.011, height: length), 10))
        body.geometry!.firstMaterial = hull
        t.addChildNode(body)
        let ribs = max(2, Int(length / 0.035))
        for k in 0...ribs {
            let rib = SCNNode(geometry: faceted(SCNCylinder(radius: 0.0125, height: 0.003), 10))
            rib.geometry!.firstMaterial = steel
            rib.position = v3(0, -length / 2 + length * Double(k) / Double(ribs), 0)
            t.addChildNode(rib)
        }
        return t
    }

    /// A cluster of capsule tanks with dark bands, one in the repository's colour, on a base.
    private static func tanks(count: Int, color: NSColor, seed: Double) -> SCNNode {
        let farm = SCNNode()
        var rng = SplitMix(seed: UInt64(seed * 1e9))
        for k in 0..<count {
            let a = Double(k) / Double(count) * 2 * .pi, d = 0.028
            let h = 0.05 + rng.next() * 0.03, r = 0.012 + rng.next() * 0.005
            let tank = SCNNode(geometry: SCNCapsule(capRadius: r, height: h))
            (tank.geometry as! SCNCapsule).radialSegmentCount = 14
            tank.geometry!.firstMaterial = k == 0 ? blinn(color, shine: 0.5) : hull
            tank.position = v3(cos(a) * d, h / 2 + 0.004, sin(a) * d)
            farm.addChildNode(tank)
            for y in [0.3, 0.7] {
                let band = SCNNode(geometry: faceted(SCNCylinder(radius: r * 1.04, height: 0.003), 14))
                band.geometry!.firstMaterial = dark
                band.position = v3(cos(a) * d, h * y + 0.004, sin(a) * d)
                farm.addChildNode(band)
            }
        }
        let base = SCNNode(geometry: faceted(SCNCylinder(radius: 0.05, height: 0.004), 8))
        base.geometry!.firstMaterial = steel
        base.position = v3(0, 0.002, 0)
        farm.addChildNode(base)
        return farm
    }

    /// A lattice mast with a dish at the top, and red lights blinking up its height.
    private static func mast(at p: SIMD3<Double>, into still: SCNNode, live: SCNNode) {
        let m = SCNNode()
        m.position = v3(p.x, 0, p.z)
        let h = 0.2, w = 0.01
        for (x, z) in [(-w, -w), (w, -w), (-w, w), (w, w)] {
            let post = SCNNode(geometry: SCNBox(width: 0.0025, height: h, length: 0.0025, chamferRadius: 0))
            post.geometry!.firstMaterial = steel
            post.position = v3(x, h / 2, z)
            m.addChildNode(post)
        }
        var y = 0.02
        while y < h {
            for a in [0.0, Double.pi / 2] {
                let brace = SCNNode(geometry: SCNBox(width: w * 2.4, height: 0.0018, length: 0.0018, chamferRadius: 0))
                brace.geometry!.firstMaterial = steel
                brace.position = v3(0, y, 0); brace.eulerAngles.y = CGFloat(a); brace.eulerAngles.z = 0.5
                m.addChildNode(brace)
            }
            y += 0.03
        }
        let dish = SCNNode(geometry: SCNCone(topRadius: 0.035, bottomRadius: 0.006, height: 0.014))
        (dish.geometry as! SCNCone).radialSegmentCount = 18
        dish.geometry!.firstMaterial = blinn(NSColor(rgb: (0.82, 0.83, 0.86)), shine: 0.4)
        dish.geometry!.firstMaterial!.isDoubleSided = true
        dish.position = v3(0, h + 0.012, 0.006); dish.eulerAngles.x = -0.6
        m.addChildNode(dish)
        let feed = SCNNode(geometry: SCNBox(width: 0.003, height: 0.03, length: 0.003, chamferRadius: 0))
        feed.geometry!.firstMaterial = dark
        feed.position = v3(0, h + 0.024, 0.02); feed.eulerAngles.x = -0.6
        m.addChildNode(feed)
        still.addChildNode(m)
        for (i, ly) in [h * 0.5, h + 0.004].enumerated() {
            let light = SCNNode(geometry: SCNBox(width: 0.005, height: 0.005, length: 0.005, chamferRadius: 0))
            light.geometry!.firstMaterial = flat(NSColor(rgb: (1, 0.2, 0.15)))
            light.position = v3(p.x, ly, p.z)
            light.runAction(.repeatForever(.sequence([.wait(duration: Double(i) * 0.5), .fadeOpacity(to: 1, duration: 0.1), .wait(duration: 0.4),
                                                      .fadeOpacity(to: 0.08, duration: 0.3), .wait(duration: 1.2 - Double(i) * 0.5)])))
            live.addChildNode(light)
        }
    }

    /// A row of solar panels on low frames, tilted to the light, their cells gridded.
    private static func solarRow(panels: Int) -> SCNNode {
        let row = SCNNode()
        let cells = SCNMaterial()
        cells.lightingModel = .blinn
        cells.diffuse.contents = cellImage
        cells.specular.contents = NSColor(white: 0.6, alpha: 1)
        cells.shininess = 0.7
        for k in 0..<panels {
            let x = (Double(k) - Double(panels - 1) / 2) * 0.052
            let panel = SCNNode(geometry: SCNBox(width: 0.048, height: 0.002, length: 0.032, chamferRadius: 0))
            panel.geometry!.materials = [steel, steel, steel, steel, cells, steel]
            panel.position = v3(x, 0.022, 0); panel.eulerAngles.x = 0.55
            row.addChildNode(panel)
            let leg = SCNNode(geometry: SCNBox(width: 0.003, height: 0.022, length: 0.003, chamferRadius: 0))
            leg.geometry!.firstMaterial = steel
            leg.position = v3(x, 0.011, 0)
            row.addChildNode(leg)
        }
        return row
    }

    private static let cellImage: NSImage = NSImage(size: NSSize(width: 96, height: 64), flipped: false) { r in
        NSColor(rgb: (0.07, 0.12, 0.3)).setFill(); r.fill()
        NSColor(rgb: (0.35, 0.45, 0.65)).setFill()
        for x in stride(from: 0, through: 96, by: 12) { NSRect(x: CGFloat(x), y: 0, width: 1, height: 64).fill() }
        for y in stride(from: 0, through: 64, by: 16) { NSRect(x: 0, y: CGFloat(y), width: 96, height: 1).fill() }
        return true
    }

    /// A six-wheeled rover: a low body, a cab in the repository's colour with a lit window, an antenna.
    private static func rover(color: NSColor) -> SCNNode {
        let r = SCNNode()
        let body = SCNNode(geometry: SCNBox(width: 0.05, height: 0.012, length: 0.028, chamferRadius: 0.002))
        body.geometry!.firstMaterial = hull
        body.position = v3(0, 0.017, 0)
        let cab = SCNNode(geometry: SCNBox(width: 0.02, height: 0.014, length: 0.024, chamferRadius: 0.002))
        cab.geometry!.firstMaterial = blinn(color.darker(0.1))
        cab.position = v3(0.013, 0.029, 0)
        let window = SCNNode(geometry: SCNBox(width: 0.002, height: 0.007, length: 0.018, chamferRadius: 0))
        window.geometry!.firstMaterial = glow
        window.position = v3(0.0235, 0.031, 0)
        r.addChildNode(body); r.addChildNode(cab); r.addChildNode(window)
        for x in [-0.018, 0.0, 0.018] {
            for z in [-0.016, 0.016] {
                let wheel = SCNNode(geometry: faceted(SCNCylinder(radius: 0.0075, height: 0.006), 10))
                wheel.geometry!.firstMaterial = dark
                wheel.position = v3(x, 0.0075, z); wheel.eulerAngles.x = .pi / 2
                r.addChildNode(wheel)
            }
        }
        let antenna = SCNNode(geometry: SCNBox(width: 0.0015, height: 0.03, length: 0.0015, chamferRadius: 0))
        antenna.geometry!.firstMaterial = steel
        antenna.position = v3(-0.018, 0.038, 0.008)
        r.addChildNode(antenna)
        return r
    }

    /// A lamp post: a pole, a head, and its light.
    private static func lamp(at p: SIMD3<Double>, into still: SCNNode, live: SCNNode) {
        let pole = SCNNode(geometry: SCNBox(width: 0.0025, height: 0.05, length: 0.0025, chamferRadius: 0))
        pole.geometry!.firstMaterial = steel
        pole.position = v3(p.x, 0.025, p.z)
        let head = SCNNode(geometry: SCNBox(width: 0.008, height: 0.005, length: 0.006, chamferRadius: 0))
        head.geometry!.firstMaterial = dark
        head.position = v3(p.x, 0.051, p.z)
        still.addChildNode(pole); still.addChildNode(head)
        let bulb = SCNNode(geometry: SCNBox(width: 0.006, height: 0.002, length: 0.004, chamferRadius: 0))
        bulb.geometry!.firstMaterial = flat(NSColor(rgb: (1, 0.95, 0.85)))
        bulb.position = v3(p.x, 0.048, p.z)
        live.addChildNode(bulb)
    }

    /// Boulders over the regolith, clear of the pad: low-poly and jagged, grey drawn towards the planet's colour.
    private static func rocks(into still: SCNNode, rng: inout SplitMix, color: NSColor) {
        let stone = blinn(NSColor(rgb: (0.46, 0.45, 0.44)).mixed(with: color, 0.25), shine: 0.05)
        for _ in 0..<40 {
            let a = rng.next() * 2 * .pi, d = 0.12 + pow(rng.next(), 0.7) * 0.55
            let size = 0.004 + pow(rng.next(), 3) * (d < 0.25 ? 0.01 : 0.03)
            let rock = SCNNode(geometry: Mesh.rock(seed: rng.next(), material: stone))
            rock.scale = SCNVector3(size, size * (0.5 + rng.next() * 0.4), size * (0.8 + rng.next() * 0.4))
            rock.position = v3(cos(a) * d, size * 0.2, sin(a) * d)
            rock.eulerAngles.y = CGFloat(rng.next() * .pi * 2)
            still.addChildNode(rock)
        }
    }

    /// Someone in a suit: white, a backpack, a gold visor.
    private static func astronaut() -> SCNNode {
        let a = SCNNode()
        let suit = blinn(NSColor(rgb: (0.93, 0.93, 0.95)), shine: 0.3)
        for side in [-1.0, 1.0] {
            let leg = SCNNode(geometry: SCNBox(width: 0.005, height: 0.013, length: 0.005, chamferRadius: 0.001))
            leg.geometry!.firstMaterial = suit
            leg.position = v3(side * 0.0032, 0.0065, 0)
            a.addChildNode(leg)
            let arm = SCNNode(geometry: SCNBox(width: 0.004, height: 0.011, length: 0.004, chamferRadius: 0.001))
            arm.geometry!.firstMaterial = suit
            arm.position = v3(side * 0.0085, 0.019, 0); arm.eulerAngles.z = CGFloat(side * 0.15)
            a.addChildNode(arm)
        }
        let torso = SCNNode(geometry: SCNBox(width: 0.012, height: 0.013, length: 0.008, chamferRadius: 0.002))
        torso.geometry!.firstMaterial = suit
        torso.position = v3(0, 0.02, 0)
        let pack = SCNNode(geometry: SCNBox(width: 0.01, height: 0.012, length: 0.005, chamferRadius: 0.001))
        pack.geometry!.firstMaterial = hull
        pack.position = v3(0, 0.021, -0.0065)
        let helmet = SCNNode(geometry: SCNSphere(radius: 0.0055))
        (helmet.geometry as! SCNSphere).segmentCount = 12
        helmet.geometry!.firstMaterial = suit
        helmet.position = v3(0, 0.0315, 0)
        let visor = SCNNode(geometry: SCNBox(width: 0.0075, height: 0.0045, length: 0.002, chamferRadius: 0.001))
        visor.geometry!.firstMaterial = blinn(NSColor(rgb: (0.85, 0.62, 0.2)), shine: 0.9)
        visor.position = v3(0, 0.0318, 0.005)
        for n in [torso, pack, helmet, visor] { a.addChildNode(n) }
        return a
    }

    /// The flag beside the pad, flying the release that last landed, a face on each side.
    private static func flag(repo: String, release: String, color: NSColor) -> SCNNode {
        let flag = SCNNode()
        flag.name = "flag"
        let pole = SCNNode(geometry: SCNBox(width: 0.0025, height: 0.12, length: 0.0025, chamferRadius: 0))
        pole.geometry!.firstMaterial = hull
        pole.position = v3(0, 0.06, 0)
        flag.addChildNode(pole)
        let cloth = SCNNode()
        cloth.name = "cloth"
        for back in [false, true] {
            let face = SCNNode(geometry: SCNPlane(width: 0.07, height: 0.04))
            let m = SCNMaterial()
            m.lightingModel = .lambert
            m.diffuse.contents = flagImage(repo: repo, release: release, color: color)
            face.geometry!.firstMaterial = m
            if back { face.eulerAngles.y = .pi }
            cloth.addChildNode(face)
        }
        cloth.position = v3(0.036, 0.1, 0)
        cloth.runAction(.repeatForever(.sequence([.rotateTo(x: 0, y: 0.12, z: 0, duration: 1.4), .rotateTo(x: 0, y: -0.08, z: 0, duration: 1.1)])))
        flag.addChildNode(cloth)
        return flag
    }

    /// The flag's cloth: the repository's colour, its name, and the release.
    static func flagImage(repo: String, release: String, color: NSColor) -> NSImage {
        NSImage(size: NSSize(width: 360, height: 200), flipped: false) { r in
            color.setFill(); r.fill()
            color.darker(0.35).setFill()
            NSRect(x: 0, y: 0, width: r.width, height: 28).fill()
            let name = NSAttributedString(string: repo, attributes: [.font: NSFont.systemFont(ofSize: 34, weight: .bold), .foregroundColor: NSColor.white])
            let rel = NSAttributedString(string: release, attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 46, weight: .heavy),
                                                                       .foregroundColor: NSColor.white])
            name.draw(at: NSPoint(x: (r.width - name.size().width) / 2, y: 120))
            rel.draw(at: NSPoint(x: (r.width - rel.size().width) / 2, y: 50))
            return true
        }
    }

    /// Hoists a new release on a colony's flag.
    static func hoist(_ colony: SCNNode?, repo: String, release: String, color: NSColor) {
        let image = flagImage(repo: repo, release: release, color: color)
        colony?.childNode(withName: "cloth", recursively: true)?.childNodes.forEach { $0.geometry?.firstMaterial?.diffuse.contents = image }
    }
}

/// Meshes the colony is cut from: a geodesic sphere, faceted shells with a material per face, their seams
/// as lines, and jagged rocks.
enum Mesh {
    static func icosphere(_ subdivisions: Int) -> (verts: [SIMD3<Double>], faces: [(Int, Int, Int)]) {
        let t = (1 + 5.0.squareRoot()) / 2
        let corners: [(Double, Double, Double)] = [(-1, t, 0), (1, t, 0), (-1, -t, 0), (1, -t, 0), (0, -1, t), (0, 1, t), (0, -1, -t), (0, 1, -t),
                                                   (t, 0, -1), (t, 0, 1), (-t, 0, -1), (-t, 0, 1)]
        var verts = corners.map { simd_normalize(SIMD3($0.0, $0.1, $0.2)) }
        var faces: [(Int, Int, Int)] = [(0, 11, 5), (0, 5, 1), (0, 1, 7), (0, 7, 10), (0, 10, 11), (1, 5, 9), (5, 11, 4), (11, 10, 2), (10, 7, 6),
                                        (7, 1, 8), (3, 9, 4), (3, 4, 2), (3, 2, 6), (3, 6, 8), (3, 8, 9), (4, 9, 5), (2, 4, 11), (6, 2, 10),
                                        (8, 6, 7), (9, 8, 1)]
        for _ in 0..<subdivisions {
            var cache: [Int: Int] = [:]
            func mid(_ a: Int, _ b: Int) -> Int {
                let key = min(a, b) << 16 | max(a, b)
                if let m = cache[key] { return m }
                verts.append(simd_normalize((verts[a] + verts[b]) / 2))
                cache[key] = verts.count - 1
                return verts.count - 1
            }
            var next: [(Int, Int, Int)] = []
            for f in faces {
                let a = mid(f.0, f.1), b = mid(f.1, f.2), c = mid(f.2, f.0)
                next += [(f.0, a, c), (f.1, b, a), (f.2, c, b), (a, b, c)]
            }
            faces = next
        }
        return (verts, faces)
    }

    /// Triangles with flat normals facing out from the middle, each drawn in the material its kind names.
    static func faceted(_ tris: [(SIMD3<Double>, SIMD3<Double>, SIMD3<Double>)], _ kinds: [Int], _ materials: [SCNMaterial]) -> SCNGeometry {
        var verts: [SCNVector3] = [], normals: [SCNVector3] = []
        var elements: [[Int32]] = Array(repeating: [], count: materials.count)
        for (i, t) in tris.enumerated() {
            let raw = simd_cross(t.1 - t.0, t.2 - t.0)
            let outward = simd_dot(raw, t.0 + t.1 + t.2) >= 0
            let n = simd_normalize(outward ? raw : -raw)
            let base = Int32(verts.count)
            for p in outward ? [t.0, t.1, t.2] : [t.0, t.2, t.1] {
                verts.append(SCNVector3(p.x, p.y, p.z)); normals.append(SCNVector3(n.x, n.y, n.z))
            }
            elements[min(kinds[i], materials.count - 1)] += [base, base + 1, base + 2]
        }
        let used = elements.indices.filter { !elements[$0].isEmpty }
        let g = SCNGeometry(sources: [SCNGeometrySource(vertices: verts), SCNGeometrySource(normals: normals)],
                            elements: used.map { SCNGeometryElement(indices: elements[$0], primitiveType: .triangles) })
        g.materials = used.map { materials[$0] }
        return g
    }

    /// Every edge of the triangles once, as lines.
    static func edges(_ tris: [(SIMD3<Double>, SIMD3<Double>, SIMD3<Double>)], _ material: SCNMaterial) -> SCNGeometry {
        var verts: [SCNVector3] = [], idx: [Int32] = [], seen = Set<String>()
        func key(_ p: SIMD3<Double>) -> String { String(format: "%.4f,%.4f,%.4f", p.x, p.y, p.z) }
        for t in tris {
            for (a, b) in [(t.0, t.1), (t.1, t.2), (t.2, t.0)] {
                let k = [key(a), key(b)].sorted().joined(separator: "|")
                guard seen.insert(k).inserted else { continue }
                idx += [Int32(verts.count), Int32(verts.count + 1)]
                verts += [SCNVector3(a.x, a.y, a.z), SCNVector3(b.x, b.y, b.z)]
            }
        }
        let g = SCNGeometry(sources: [SCNGeometrySource(vertices: verts)], elements: [SCNGeometryElement(indices: idx, primitiveType: .line)])
        g.firstMaterial = material
        return g
    }

    /// A boulder: a coarse geodesic sphere with its corners pushed in and out, flat underneath.
    static func rock(seed: Double, material: SCNMaterial) -> SCNGeometry {
        var rng = SplitMix(seed: UInt64(seed * 1e9) | 1)
        let (verts, faces) = icosphere(1)
        let bumped = verts.map { $0 * (0.7 + rng.next() * 0.5) }
        let tris = faces.map { (bumped[$0.0], bumped[$0.1], bumped[$0.2]) }.filter { ($0.0.y + $0.1.y + $0.2.y) / 3 > -0.4 }
        return faceted(tris, Array(repeating: 0, count: tris.count), [material])
    }
}

/// A small seeded generator: the same seed, the same colony.
struct SplitMix {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> Double {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        z ^= z >> 31
        return Double(z >> 11) / Double(1 << 53)
    }
}
