// The rocket a production deploy is filmed from. The station's rocket is a toy at the station's scale; this one
// is only seen through the flight's cameras, close up, so it is built to be looked at: a lifter and a tip of one
// diameter with twelve flat sides, plated (`Plating`) and lit as metal, the nose and a band in the repository's
// colour, its name along the lifter, slim fins, thruster pods on the tip's sides, and six black flaps round the
// tip's blue flame that swing out as its feet. Like the planets it is the world beyond the station, so its shapes
// may be round.
//
// Measurements are the craft's own, in its local units, nose along +y. The names the flight steps by are
// "lifter", "tip", "lifter plume", "tip plume", "strain", "flap", "rcs" and "down cam".

import AppKit
import SceneKit

enum FlightCraft {
    /// Both stages are one diameter.
    static let radius = 0.12
    /// The lifter's engines stand from 0 to `engineTop`; its body runs to `lifterTop`, and the interstage
    /// skirt over the tip's engine on up to `skirtTop`.
    static let engineTop = 0.09, lifterTop = 1.12, skirtTop = 1.28
    /// The tip stands on `tipBase`, its hull runs to `tipTop`, and the nose to `noseTop`.
    static let tipBase = 1.36, tipTop = 2.06, noseTop = 2.42
    /// The corner the cameras are on, as a bearing round the hull; the fins are on the three a third of a turn
    /// apart that miss it, the raceway beside it.
    static let cameraBearing = Double.pi * 7 / 6
    static let legBearings = [Double.pi / 6, Double.pi * 5 / 6, Double.pi * 3 / 2]
    /// How many flat sides the hull has. Its corners always include the six of the station's hexagonal rocket,
    /// which the fins and the cameras stand on.
    static let sides = 12
    /// Where the corners start: one of them at a sixth of a half turn, as the hexagon's are.
    static var cornerOffset: Double { (Double.pi / 6).truncatingRemainder(dividingBy: 2 * .pi / Double(sides)) }
    /// The middle of the face nearest a bearing.
    static func faceMiddle(near bearing: Double) -> Double {
        let step = 2 * Double.pi / Double(sides), first = cornerOffset + step / 2
        return first + ((bearing - first) / step).rounded() * step
    }
    /// How much hull one copy of the plating covers, across and up.
    static let plateSize = 0.22
    /// The flaps: how long, leaning in how far round the flame (negative, toward the middle), and out how far
    /// as feet. What the tip stands on is their tips.
    static let flapLength = 0.17, flapClosed = -0.25, flapOut = 0.62
    static var standDepth: Double { flapLength * cos(flapOut) }

    /// The craft in two pieces, the lifter and the tip, each in the craft's own frame.
    static func build(color: NSColor, repo: String, release: String) -> (lifter: SCNNode, tip: SCNNode) {
        let lifter = SCNNode(), tip = SCNNode()
        lifter.name = "lifter"; tip.name = "tip"
        buildLifter(lifter, color: color, repo: repo, release: release)
        buildTip(tip, color: color, repo: repo)
        return (lifter, tip)
    }

    // MARK: the lifter

    private static func buildLifter(_ n: SCNNode, color: NSColor, repo: String, release: String) {
        let r = radius
        // The body's plating, and over it once from top to bottom the soot of the engines, thickest at the foot.
        let bodySkin = Materials.plated(seed: 21)
        bodySkin.multiply.contents = Textures.sootRise
        bodySkin.multiply.mappingChannel = 1
        bodySkin.multiply.wrapS = .clamp; bodySkin.multiply.wrapT = .clamp
        let body = SCNNode(geometry: hullBand(r0: r, r1: r, y0: engineTop, y1: lifterTop, material: bodySkin, closed: (false, true)))
        n.addChildNode(body)
        // The interstage: a darker skirt over the tip's engine.
        // Open at the top, its inside drawn too, so looking in shows its wall and the deck below.
        let skirtSkin = Materials.plated(seed: 41, tint: SIMD3(0.3, 0.31, 0.33))
        skirtSkin.isDoubleSided = true
        let skirt = SCNNode(geometry: hullBand(r0: r * 1.005, r1: r * 1.005, y0: lifterTop + 0.001, y1: skirtTop, material: skirtSkin))
        n.addChildNode(skirt)
        // The engine section: a heat shield plate and seven bells, one in the middle and six round it.
        let plate = SCNNode(geometry: round(SCNCylinder(radius: r * 0.98, height: 0.02)))
        plate.geometry!.firstMaterial = skin(Textures.soot, shine: 0.05)
        plate.position = v3(0, engineTop + 0.01, 0)
        n.addChildNode(plate)
        for k in 0..<7 {
            let a = Double(k) * .pi / 3
            let at = k == 6 ? SIMD2(0.0, 0.0) : SIMD2(cos(a), sin(a)) * r * 0.62
            let bell = SCNNode(geometry: round(SCNCone(topRadius: 0.011, bottomRadius: 0.03, height: engineTop - 0.01)))
            bell.geometry!.firstMaterial = Materials.bell
            bell.position = v3(at.x, (engineTop - 0.01) / 2, at.y)
            n.addChildNode(bell)
        }
        // Three fins at the foot, on the corners the tip's fins are on.
        for a in legBearings { n.addChildNode(fin(at: a, from: engineTop + 0.02, to: engineTop + 0.46, reach: 0.06, color: color)) }
        // The repository's colour in a band under the interstage, and its name down the face beside the cameras.
        n.addChildNode(SCNNode(geometry: hullBand(r0: r * 1.004, r1: r * 1.004, y0: lifterTop - 0.08, y1: lifterTop,
                                                 material: Materials.plated(seed: 21, tint: paint(color)))))
        n.addChildNode(nameplate(repo.uppercased(), face: faceMiddle(near: .pi * 13 / 12), top: lifterTop - 0.14, length: 0.62))
        n.addChildNode(raceway(from: engineTop + 0.05, to: lifterTop - 0.02))
        let plume = FlightCraft.airPlume()
        plume.name = "lifter plume"
        plume.position = v3(0, 0.005, 0)
        n.addChildNode(plume)
    }

    // MARK: the tip

    private static func buildTip(_ n: SCNNode, color: NSColor, repo: String) {
        let r = radius
        let plates = Materials.plated(seed: 31)
        // The nose in the repository's colour, as the station's rocket has it.
        let nosePaint = Materials.plated(seed: 31, tint: paint(color))
        n.addChildNode(SCNNode(geometry: hullBand(r0: r, r1: r, y0: tipBase, y1: tipTop, material: plates, closed: (true, false))))
        // The nose: six faces curving in to a point, in bands whose width follows an ogive.
        let steps = 6, noseH = noseTop - tipTop
        func radiusAt(_ t: Double) -> Double { r * (1 - t * t) }   // t from the shoulder (0) to the point (1)
        for i in 0..<steps {
            let t0 = Double(i) / Double(steps), t1 = Double(i + 1) / Double(steps)
            n.addChildNode(SCNNode(geometry: hullBand(r0: radiusAt(t0), r1: max(0.0005, radiusAt(t1)), y0: tipTop + noseH * t0, y1: tipTop + noseH * t1, material: nosePaint)))
        }
        // Six black flaps round the foot, closed in round the blue flame like a nozzle; for the landing they swing
        // out and down into six feet.
        for k in 0..<6 { n.addChildNode(flap(at: cameraBearing + Double(k) * .pi / 3 + .pi / 6)) }
        // A dark ring at the hull's foot, the heat shield's edge.
        n.addChildNode(SCNNode(geometry: hullBand(r0: r * 1.012, r1: r * 1.012, y0: tipBase, y1: tipBase + 0.03,
                                                 material: Materials.plated(seed: 31, tint: SIMD3(0.12, 0.12, 0.13)))))
        // Three slim fins down its lower corners.
        for a in legBearings { n.addChildNode(fin(at: a, from: tipBase + 0.03, to: tipBase + 0.36, reach: 0.045, color: color)) }
        // Thruster pods on its sides at the shoulder, between the fins: they fire the course corrections.
        for a in legBearings.map({ $0 + .pi / 3 }) where abs(remainder(a - cameraBearing, 2 * .pi)) > 0.1 {
            n.addChildNode(thrusterPod(at: a, height: tipTop - 0.08))
        }
        n.addChildNode(raceway(from: tipBase + 0.05, to: tipTop - 0.04))
        // A blade antenna on the nose's shoulder.
        let blade = SCNNode(geometry: SCNBox(width: 0.004, height: 0.07, length: 0.04, chamferRadius: 0.001))
        blade.geometry!.firstMaterial = Materials.metal
        let mast = legBearings[0] + .pi / 3
        blade.position = v3(cos(mast) * r * 0.86, tipTop + 0.07, sin(mast) * r * 0.86)
        blade.eulerAngles.y = CGFloat(-mast)
        n.addChildNode(blade)
        // The beacon at the point, blinking in the repository's colour.
        let beacon = SCNNode(geometry: SCNSphere(radius: 0.012))
        beacon.geometry!.firstMaterial = Materials.glow(color.lighter(0.5))
        beacon.position = v3(0, noseTop + 0.004, 0)
        beacon.runAction(.repeatForever(.sequence([.fadeOpacity(to: 1, duration: 0.1), .wait(duration: 0.35),
                                                   .fadeOpacity(to: 0.15, duration: 0.25), .wait(duration: 0.5)])))
        n.addChildNode(beacon)
        // The strain of braking down through the air: a hot glow pressed against its foot and streaks torn off it.
        let strain = SCNNode()
        strain.name = "strain"
        strain.opacity = 0
        let bow = SCNNode(geometry: SCNSphere(radius: 0.24))
        bow.geometry!.firstMaterial = Materials.fire(Textures.plasma, alpha: 0.75)
        bow.scale = SCNVector3(1, 0.45, 1)
        bow.position = v3(0, tipBase - 0.16, 0)
        strain.addChildNode(bow)
        let streaks = SCNNode()
        streaks.position = v3(0, tipBase - 0.12, 0)
        streaks.addParticleSystem(Particles.streaks())
        strain.addChildNode(streaks)
        n.addChildNode(strain)
        let plume = FlightCraft.vacuumPlume()
        plume.name = "tip plume"
        plume.position = v3(0, tipBase - 0.01, 0)
        plume.isHidden = true
        n.addChildNode(plume)
        n.setValue(tipBase, forKey: "split")
    }

    /// A repository's colour as paint on the plating: a little deeper than the colour itself, so the plating's
    /// light and grime read on it.
    static func paint(_ color: NSColor) -> SIMD3<Double> {
        let c = color.usingColorSpace(.deviceRGB) ?? color
        return SIMD3(Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent)) * 0.82
    }

    /// The repository's name stencilled along a face of the hull.
    static func nameplate(_ name: String, face: Double, top: Double, length: Double) -> SCNNode {
        let width = min(radius * 0.62, 2 * radius * sin(.pi / Double(sides)) * 0.82)
        let image = Textures.draw(1600, Int(1600 * width / length)) { _, w, h in
            let big: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: h * 0.62, weight: .black),
                                                      .foregroundColor: NSColor(white: 0.08, alpha: 0.88), .kern: h * 0.08]
            NSAttributedString(string: name, attributes: big).draw(at: NSPoint(x: w * 0.02, y: h * 0.04))
        }
        let plane = SCNPlane(width: length, height: width)
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = image
        m.roughness.contents = NSColor(white: 0.7, alpha: 1)
        m.metalness.contents = NSColor(white: 0.1, alpha: 1)
        m.transparencyMode = .aOne
        plane.firstMaterial = m
        let letters = SCNNode(geometry: plane)
        letters.eulerAngles.z = .pi / 2   // the text runs up the hull, the right way up from the camera on its corner
        let mount = SCNNode()
        let out = SIMD2(cos(face), sin(face)) * (radius * cos(.pi / Double(sides)) + 0.0012)
        mount.position = v3(out.x, top - length / 2, out.y)
        mount.eulerAngles.y = CGFloat(atan2(cos(face), sin(face)))
        mount.addChildNode(letters)
        return mount
    }

    /// How far out the hull's surface is at a bearing: the corners are `radius` out, the middles of the faces less.
    static func surface(at bearing: Double, radius r: Double = radius) -> Double {
        r * cos(.pi / Double(sides)) / cos(bearing - faceMiddle(near: bearing))
    }

    /// A band of the hull between two heights: its flat faces with hard edges, `r0` out to the corners at `y0`
    /// and `r1` at `y1`. Its texture is laid in the hull's own units, so plates are one size wherever they are.
    static func hullBand(r0: Double, r1: Double, y0: Double, y1: Double, material: SCNMaterial, closed: (bottom: Bool, top: Bool) = (false, false)) -> SCNGeometry {
        let tile = plateSize
        var verts: [SCNVector3] = [], normals: [SCNVector3] = [], uvs: [CGPoint] = [], whole: [CGPoint] = [], tangents: [SCNVector4] = [], idx: [Int32] = []
        func corner(_ k: Int, _ r: Double, _ y: Double) -> SIMD3<Double> {
            let a = cornerOffset + Double(k) * 2 * .pi / Double(sides)
            return SIMD3(cos(a) * r, y, sin(a) * r)
        }
        let side = 2 * sin(.pi / Double(sides))   // a face's width, for a corner radius of one
        let width0 = r0 * side, width1 = r1 * side
        for k in 0..<sides {
            let a0 = corner(k, r0, y0), b0 = corner(k + 1, r0, y0), a1 = corner(k, r1, y1), b1 = corner(k + 1, r1, y1)
            let along = simd_normalize(b0 - a0)
            var n = simd_normalize(simd_cross(a1 - a0, along))
            if simd_dot(n, SIMD3(a0.x + b0.x, 0, a0.z + b0.z)) < 0 { n = -n }
            let base = Int32(verts.count)
            let u0 = Double(k) * max(width0, width1) / tile
            let mid = (u0 + max(width0, width1) / tile / 2)
            for (p, w, y) in [(a0, width0, y0), (b0, width0, y0), (b1, width1, y1), (a1, width1, y1)] {
                verts.append(SCNVector3(p.x, p.y, p.z)); normals.append(SCNVector3(n.x, n.y, n.z))
                let side = (p == a0 || p == a1) ? -0.5 : 0.5
                uvs.append(CGPoint(x: mid + side * w / tile, y: -y / tile))
                whole.append(CGPoint(x: side + 0.5, y: (y1 - y) / max(1e-6, y1 - y0)))   // the band once over: 0 at its top
                tangents.append(SCNVector4(along.x, along.y, along.z, 1))
            }
            // Wound outward, two triangles a face.
            idx += [base, base + 2, base + 1, base, base + 3, base + 2]
        }
        // The ends asked for are closed, a fan of triangles across each. Only an end nothing else meets: two
        // ends in the same place flicker against each other.
        var capIdx: [Int32] = []
        for (y, r, down, wanted) in [(y0, r0, true, closed.bottom), (y1, r1, false, closed.top)] where wanted && r > 0.002 {
            let centre = Int32(verts.count)
            verts.append(SCNVector3(0, y, 0)); normals.append(SCNVector3(0, down ? -1 : 1, 0))
            uvs.append(CGPoint(x: 0, y: 0)); whole.append(CGPoint(x: 0.5, y: down ? 1 : 0)); tangents.append(SCNVector4(1, 0, 0, 1))
            for k in 0...sides {
                let p = corner(k, r, y)
                verts.append(SCNVector3(p.x, p.y, p.z)); normals.append(SCNVector3(0, down ? -1 : 1, 0))
                uvs.append(CGPoint(x: p.x / tile, y: p.z / tile)); whole.append(CGPoint(x: 0.5, y: down ? 1 : 0)); tangents.append(SCNVector4(1, 0, 0, 1))
            }
            for k in 0..<Int32(sides) { capIdx += [centre, centre + 1 + k, centre + 2 + k] }
        }
        let tan = tangents.withUnsafeBufferPointer { Data(buffer: $0) }
        let tangentSource = SCNGeometrySource(data: tan, semantic: .tangent, vectorCount: tangents.count, usesFloatComponents: true,
                                              componentsPerVector: 4, bytesPerComponent: MemoryLayout<CGFloat>.size, dataOffset: 0,
                                              dataStride: MemoryLayout<SCNVector4>.stride)
        let g = SCNGeometry(sources: [SCNGeometrySource(vertices: verts), SCNGeometrySource(normals: normals),
                                      SCNGeometrySource(textureCoordinates: uvs), tangentSource, SCNGeometrySource(textureCoordinates: whole)],
                            elements: [SCNGeometryElement(indices: idx, primitiveType: .triangles),
                                       SCNGeometryElement(indices: capIdx, primitiveType: .triangles)])
        let ends = material.copy() as! SCNMaterial
        ends.isDoubleSided = true
        g.materials = [material, ends]
        return g
    }

    /// A fin on a corner of the hull: a slender angular blade, flush with the hull at its top, reaching out
    /// toward its foot to a short straight outer edge picked out in the repository's colour, and cut back in
    /// under it.
    private static func fin(at a: Double, from y0: Double, to y1: Double, reach: Double, color: NSColor) -> SCNNode {
        let pivot = SCNNode()
        pivot.eulerAngles.y = CGFloat(-a)
        let profile = NSBezierPath()
        let h = y1 - y0
        profile.move(to: NSPoint(x: 0, y: h))
        profile.line(to: NSPoint(x: reach * 0.35, y: h * 0.7))
        profile.line(to: NSPoint(x: reach, y: h * 0.32))
        profile.line(to: NSPoint(x: reach, y: h * 0.12))
        profile.line(to: NSPoint(x: reach * 0.45, y: 0))
        profile.line(to: NSPoint(x: 0, y: 0))
        profile.close()
        let shape = SCNShape(path: profile, extrusionDepth: 0.006)
        shape.chamferRadius = 0.0012
        let skin = Materials.plated(seed: 41, tint: SIMD3(0.36, 0.38, 0.41))
        // A shape's texture is laid over its whole outline: shrink the plating back to the hull's plate size.
        let fit = SCNMatrix4MakeScale(CGFloat(reach / plateSize), CGFloat(h / plateSize), 1)
        for p in [skin.diffuse, skin.roughness] { p.contentsTransform = fit }
        // A shape has no surface directions for a relief map to follow: it would only sparkle.
        skin.normal.contents = nil
        shape.firstMaterial = skin
        let plate = SCNNode(geometry: shape)
        plate.position = v3(radius * 0.97, y0, 0)
        pivot.addChildNode(plate)
        let edge = SCNNode(geometry: SCNBox(width: 0.004, height: h * 0.2, length: 0.0075, chamferRadius: 0.001))
        let paintMaterial = SCNMaterial()
        paintMaterial.lightingModel = .physicallyBased
        let c = paint(color)
        paintMaterial.diffuse.contents = NSColor(red: CGFloat(c.x), green: CGFloat(c.y), blue: CGFloat(c.z), alpha: 1)
        paintMaterial.roughness.contents = NSColor(white: 0.5, alpha: 1)
        edge.geometry!.firstMaterial = paintMaterial
        edge.position = v3(radius * 0.97 + reach + 0.0015, y0 + h * 0.22, 0)
        pivot.addChildNode(edge)
        return pivot
    }

    /// One of the six flaps: a black plate hinged at the hull's foot, narrowing to its tip. Closed, it leans in
    /// round the flame; out, it is a foot. The hinge turns it in the plane of its bearing.
    private static func flap(at a: Double) -> SCNNode {
        let pivot = SCNNode()
        pivot.eulerAngles.y = CGFloat(-a)
        let hinge = SCNNode()
        hinge.name = "flap"
        hinge.position = v3(surface(at: a) * 0.96, tipBase + 0.004, 0)
        hinge.eulerAngles.z = CGFloat(flapClosed)
        let outline = NSBezierPath()
        let w0 = 2 * radius * sin(.pi / 6) * 0.9, w1 = w0 * 0.42   // as wide as a sixth of the hull at the hinge
        outline.move(to: NSPoint(x: -w0 / 2, y: 0))
        outline.line(to: NSPoint(x: w0 / 2, y: 0))
        outline.line(to: NSPoint(x: w1 / 2, y: -flapLength))
        outline.line(to: NSPoint(x: -w1 / 2, y: -flapLength))
        outline.close()
        let plate = SCNShape(path: outline, extrusionDepth: 0.008)
        plate.chamferRadius = 0.002
        let black = SCNMaterial()
        black.lightingModel = .physicallyBased
        black.diffuse.contents = NSColor(white: 0.035, alpha: 1)
        black.roughness.contents = NSColor(white: 0.45, alpha: 1)
        black.metalness.contents = NSColor(white: 0.5, alpha: 1)
        plate.firstMaterial = black
        let leaf = SCNNode(geometry: plate)
        leaf.eulerAngles.y = .pi / 2   // the plate's face looking out from the hull
        hinge.addChildNode(leaf)
        pivot.addChildNode(hinge)
        return pivot
    }

    /// How hard the air is pressing on it, 0 to 1: the glow round its foot and the streaks off it.
    static func strain(_ tip: SCNNode, heat: Double) {
        guard let strain = tip.childNode(withName: "strain", recursively: false) else { return }
        let k = max(0, min(1, heat))
        strain.opacity = CGFloat(k)
        strain.enumerateHierarchy { n, _ in n.particleSystems?.first?.birthRate = CGFloat(260 * k) }
    }

    /// How far the flaps are out, 0 closed round the flame to 1 standing on them as feet.
    static func feet(_ tip: SCNNode, out: Double) {
        let k = max(0, min(1, out))
        let angle = flapClosed + (flapOut - flapClosed) * k
        tip.enumerateHierarchy { n, _ in if n.name == "flap" { n.eulerAngles.z = CGFloat(angle) } }
    }

    /// A pod of four small nozzles on the side at the shoulder. It is named for the flight to fire it: puffs
    /// leave it along its local +x, out from the hull.
    private static func thrusterPod(at a: Double, height: Double) -> SCNNode {
        let pivot = SCNNode()
        pivot.name = "rcs"
        pivot.setValue(SIMD3(radius + 0.04, height, 0), forKey: "nozzle")
        pivot.eulerAngles.y = CGFloat(-a)
        let pod = SCNNode(geometry: SCNBox(width: 0.03, height: 0.05, length: 0.04, chamferRadius: 0.006))
        pod.geometry!.firstMaterial = skin(Textures.soot, shine: 0.2)
        pod.position = v3(radius + 0.01, height, 0)
        pivot.addChildNode(pod)
        for (dy, dz) in [(0.014, 0.0), (-0.014, 0.0), (0.0, 0.014), (0.0, -0.014)] {
            let nozzle = SCNNode(geometry: round(SCNCone(topRadius: 0.003, bottomRadius: 0.006, height: 0.012)))
            nozzle.geometry!.firstMaterial = Materials.bell
            nozzle.position = v3(radius + 0.03, height + dy, dz)
            nozzle.eulerAngles.z = -.pi / 2
            pivot.addChildNode(nozzle)
        }
        return pivot
    }

    /// The cable raceway down the side beside the cameras: a long covered channel with clamps.
    private static func raceway(from: Double, to: Double) -> SCNNode {
        let a = cameraBearing + 0.42
        let pivot = SCNNode()
        pivot.eulerAngles.y = CGFloat(-a)
        let channel = SCNNode(geometry: SCNBox(width: 0.016, height: to - from, length: 0.026, chamferRadius: 0.004))
        channel.geometry!.firstMaterial = skin(Textures.steel, shine: 0.3)
        channel.position = v3(surface(at: a) + 0.008, (from + to) / 2, 0)
        pivot.addChildNode(channel)
        var y = from + 0.04
        while y < to - 0.02 {
            let clamp = SCNNode(geometry: SCNBox(width: 0.02, height: 0.008, length: 0.03, chamferRadius: 0.002))
            clamp.geometry!.firstMaterial = Materials.dark
            clamp.position = v3(surface(at: a) + 0.01, y, 0)
            pivot.addChildNode(clamp)
            y += 0.09
        }
        return pivot
    }

    // MARK: cameras

    /// The camera bolted to the rocket, for the liftoff: on the lifter, looking down past it at the pad.
    static func mountCameras(lifter: SCNNode, tip: SCNNode) {
        let r = radius
        lifter.addChildNode(camera("down cam", reach: r * 1.32, height: lifterTop - 0.06, looking: SIMD3(0, -1, 0), lean: 0.1))
    }

    /// One of the craft's cameras, on the camera corner: `reach` out from the middle, at `height`, looking
    /// along `looking`, leaned out (or in, below zero) by `lean`. It looks along its -z with its y away from
    /// the hull, so the hull is always the bottom of its picture. A small housing is drawn behind it.
    static func camera(_ name: String, reach: Double, height: Double, looking: SIMD3<Float>, lean: Float) -> SCNNode {
        let out = SIMD3<Float>(Float(cos(cameraBearing)), 0, Float(sin(cameraBearing)))
        let cam = SCNNode()
        cam.name = name
        cam.simdPosition = out * Float(reach) + SIMD3(0, Float(height), 0)
        let ahead = simd_normalize(looking + out * lean)
        let right = simd_normalize(simd_cross(ahead, out)), up = simd_cross(right, ahead)
        cam.simdOrientation = simd_quatf(simd_float3x3(columns: (right, up, -ahead)))
        return cam
    }

    // MARK: the sky

    /// Stars all round, for the flight's cameras: points on a great sphere, a few of them bright and a few
    /// tinted. As points they stay sharp at any zoom, so the long lens sees a handful of pin-pricks, not blurs.
    static func stars() -> SCNNode {
        var r = Textures.Seeded(s: 977)
        var points: [SCNVector3] = [], colors: [SIMD4<Float>] = []
        for _ in 0..<4500 {
            // Evenly over the sphere: a height and an angle round, each uniform.
            let z = r.next() * 2 - 1, a = r.next() * 2 * .pi, ring = (1 - z * z).squareRoot()
            points.append(SCNVector3(ring * cos(a) * 400, z * 400, ring * sin(a) * 400))
            let b = Float(pow(r.next(), 3) * 0.85 + 0.15)   // most faint, a few bright
            let tint = r.next()
            let c: SIMD3<Float> = tint < 0.1 ? SIMD3(0.75, 0.82, 1) : tint < 0.16 ? SIMD3(1, 0.88, 0.72) : SIMD3(1, 1, 1)
            colors.append(SIMD4(c * b, 1))
        }
        let colorData = colors.withUnsafeBufferPointer { Data(buffer: $0) }
        let colorSource = SCNGeometrySource(data: colorData, semantic: .color, vectorCount: colors.count, usesFloatComponents: true,
                                            componentsPerVector: 4, bytesPerComponent: MemoryLayout<Float>.size, dataOffset: 0,
                                            dataStride: MemoryLayout<SIMD4<Float>>.stride)
        let element = SCNGeometryElement(indices: (0..<Int32(points.count)).map { $0 }, primitiveType: .point)
        element.pointSize = 2
        element.minimumPointScreenSpaceRadius = 0.6
        element.maximumPointScreenSpaceRadius = 1.6
        let g = SCNGeometry(sources: [SCNGeometrySource(vertices: points), colorSource], elements: [element])
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = NSColor.white
        m.writesToDepthBuffer = false
        g.firstMaterial = m
        let n = SCNNode(geometry: g)
        n.name = "flight stars"
        n.categoryBitMask = Pick.onboard
        n.renderingOrder = -10
        return n
    }

    // MARK: the camera's character

    /// What the space round the craft gives its metal to reflect: dark, with the glow of the sun's side and a
    /// faint band of light where the planets are.
    static let environment = Textures.draw(512, 256) { ctx, w, h in
        NSGradient(colors: [NSColor(rgb: (0.02, 0.025, 0.04)), NSColor(rgb: (0.1, 0.11, 0.14)), NSColor(rgb: (0.03, 0.03, 0.045))],
                   atLocations: [0, 0.55, 1], colorSpace: .deviceRGB)!.draw(in: NSRect(x: 0, y: 0, width: w, height: h), angle: 90)
        let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [NSColor(rgb: (1, 0.96, 0.88)).cgColor, NSColor(white: 0, alpha: 0).cgColor] as CFArray, locations: [0, 1])!
        ctx.drawRadialGradient(g, startCenter: CGPoint(x: w * 0.3, y: h * 0.42), startRadius: 0, endCenter: CGPoint(x: w * 0.3, y: h * 0.42), endRadius: w * 0.16, options: [])
    }

    /// An onboard camera's look: a bright exposure that blooms, the edges falling off, a little grain and
    /// colour fringing.
    static func film(_ c: SCNCamera) {
        c.wantsHDR = true
        c.wantsExposureAdaptation = false
        c.exposureOffset = 0.2
        c.minimumExposure = -2; c.maximumExposure = 2
        c.bloomIntensity = 0.9
        c.bloomThreshold = 1.15
        c.bloomBlurRadius = 10
        c.vignettingIntensity = 0.6
        c.vignettingPower = 0.8
        c.colorFringeStrength = 0.5
        c.colorFringeIntensity = 0.5
        c.grainIntensity = 0.06
        c.grainScale = 1.2
        c.grainIsColored = false
    }

    // MARK: plumes

    /// The lifter's plume in the air: a thin white-hot core with shock diamonds down it, white exhaust streaming
    /// off the nozzles, a glare round the engines, and smoke left behind in the air. Its top is at the node; it points
    /// down -y. `air(_:thin:)` widens and thins it as the air does.
    static func airPlume() -> SCNNode {
        let n = SCNNode()
        let core = SCNNode(geometry: round(SCNCone(topRadius: 0.03, bottomRadius: 0.012, height: 0.7)))
        core.geometry!.firstMaterial = Materials.fire(Textures.diamonds, alpha: 1)
        core.position = v3(0, -0.35, 0)
        core.name = "core"
        n.addChildNode(core)
        let fire = SCNNode()
        fire.name = "fire"
        fire.addParticleSystem(Particles.fire())
        n.addChildNode(fire)
        let glare = SCNNode(geometry: SCNPlane(width: 0.28, height: 0.28))
        glare.geometry!.firstMaterial = Materials.fire(Textures.glare, alpha: 0.55)
        glare.constraints = [SCNBillboardConstraint()]
        glare.position = v3(0, -0.06, 0)
        glare.name = "glare"
        n.addChildNode(glare)
        let smoke = SCNNode()
        smoke.name = "smoke"
        smoke.position = v3(0, -0.7, 0)
        smoke.addParticleSystem(Particles.smoke())
        n.addChildNode(smoke)
        return n
    }

    /// How far into thin air the climb is, 0 on the pad to 1 in space: the fire spreads a little and thins out,
    /// the core and the glare fade, and the smoke stops. It never swells past the rocket.
    static func air(_ plume: SCNNode, thin: Double) {
        let k = max(0, min(1, thin))
        if let fire = plume.childNode(withName: "fire", recursively: false)?.particleSystems?.first {
            fire.spreadingAngle = CGFloat(4 + 10 * k)
            fire.birthRate = CGFloat(900 * (1 - 0.7 * k))
        }
        plume.childNode(withName: "core", recursively: false)?.opacity = CGFloat(1 - 0.6 * k)
        plume.childNode(withName: "glare", recursively: false)?.opacity = CGFloat(1 - 0.7 * k)
        plume.childNode(withName: "smoke", recursively: false)?.particleSystems?.first?.birthRate = CGFloat(220 * (1 - k) * (1 - k))
    }

    /// The tip's flame in vacuum: a small translucent blue cone standing just off the nozzle, soft at its edges,
    /// and a blue glow at the throat.
    static func vacuumPlume() -> SCNNode {
        let n = SCNNode()
        let cone = SCNNode(geometry: round(SCNCone(topRadius: 0.05, bottomRadius: 0.018, height: 0.26)))
        cone.geometry!.firstMaterial = Materials.fire(Textures.blueFlame, alpha: 0.85)
        cone.position = v3(0, -0.03 - 0.13, 0)
        n.addChildNode(cone)
        let inner = SCNNode(geometry: round(SCNCone(topRadius: 0.028, bottomRadius: 0.008, height: 0.16)))
        inner.geometry!.firstMaterial = Materials.fire(Textures.blueFlame, alpha: 0.9)
        inner.position = v3(0, -0.03 - 0.08, 0)
        n.addChildNode(inner)
        let glow = SCNNode(geometry: SCNPlane(width: 0.22, height: 0.22))
        glow.geometry!.firstMaterial = Materials.fire(Textures.blueGlare, alpha: 0.6)
        glow.constraints = [SCNBillboardConstraint()]
        glow.position = v3(0, -0.04, 0)
        n.addChildNode(glow)
        n.runAction(.repeatForever(.sequence([.fadeOpacity(to: 0.9, duration: 0.5), .fadeOpacity(to: 1, duration: 0.6)])))
        return n
    }

    // MARK: building blocks

    /// A turned shape smooth enough to read as round up close.
    private static func round<G: SCNGeometry>(_ g: G) -> G {
        if let c = g as? SCNCylinder { c.radialSegmentCount = 48 }
        if let c = g as? SCNCone { c.radialSegmentCount = 48 }
        if let t = g as? SCNTube { t.radialSegmentCount = 48 }
        if let s = g as? SCNSphere { s.segmentCount = 16 }
        return g
    }

    /// A lit skin: a texture, or a plain colour, with a sheen.
    static func skin(_ image: NSImage?, color: NSColor = .white, shine: Double) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .blinn
        m.diffuse.contents = image ?? color
        m.specular.contents = NSColor(white: CGFloat(shine), alpha: 1)
        m.shininess = 0.35
        m.locksAmbientWithDiffuse = true
        return m
    }

    enum Materials {
        /// The hull's plating, lit as a painted metal: colour, relief and roughness from `Plating`.
        /// The plating families the craft is made of: the lifter's, the tip's, and the fittings'. `Plating.warm`
        /// makes them ahead of the first flight.
        static let families: [UInt64] = [21, 31, 41]
        /// Plating of one family, painted: the paint is laid over the pale plating, so one set of maps serves
        /// every colour.
        static func plated(seed: UInt64, tint: SIMD3<Double>? = nil) -> SCNMaterial {
            let maps = Plating.maps(seed: seed)
            let m = SCNMaterial()
            if let tint {
                let base = Plating.paleTint
                m.multiply.contents = NSColor(red: CGFloat(min(1, tint.x / base.x)), green: CGFloat(min(1, tint.y / base.y)),
                                              blue: CGFloat(min(1, tint.z / base.z)), alpha: 1)
            }
            m.lightingModel = .physicallyBased
            m.diffuse.contents = maps.color
            m.normal.contents = maps.normal
            m.roughness.contents = maps.roughness
            m.metalness.contents = NSColor(white: 0.35, alpha: 1)
            for p in [m.diffuse, m.normal, m.roughness] { p.wrapS = .repeat; p.wrapT = .repeat; p.mipFilter = .linear; p.maxAnisotropy = 8 }
            return m
        }
        static let metal = skin(nil, color: NSColor(rgb: (0.62, 0.64, 0.68)), shine: 0.7)
        static let dark = skin(nil, color: NSColor(rgb: (0.16, 0.16, 0.18)), shine: 0.25)
        static let bell = skin(Textures.bell, shine: 0.45)
        /// Exhaust: added light, seen from inside and out, never hiding what is behind it.
        static func fire(_ image: NSImage, alpha: Double) -> SCNMaterial {
            let m = SCNMaterial()
            m.lightingModel = .constant
            m.diffuse.contents = image
            m.transparency = CGFloat(alpha)
            m.blendMode = .add
            m.isDoubleSided = true
            m.writesToDepthBuffer = false
            return m
        }
        static func glow(_ color: NSColor) -> SCNMaterial {
            let m = SCNMaterial()
            m.lightingModel = .constant
            m.diffuse.contents = color
            return m
        }
    }

    enum Particles {
        /// Streaks of hot air torn off the foot while it brakes through the air: left behind where they were made.
        static func streaks() -> SCNParticleSystem {
            let ps = SCNParticleSystem()
            ps.particleImage = Textures.glare
            ps.birthRate = 0
            ps.loops = true
            ps.emitterShape = SCNCylinder(radius: radius * 1.3, height: 0.01)
            ps.birthLocation = .surface
            ps.emittingDirection = SCNVector3(0, 1, 0)
            ps.spreadingAngle = 12
            ps.particleVelocity = 0.35
            ps.particleVelocityVariation = 0.15
            ps.particleLifeSpan = 0.5
            ps.particleLifeSpanVariation = 0.2
            ps.particleSize = 0.012
            ps.stretchFactor = 0.08
            ps.blendMode = .additive
            ps.isLocal = false
            ps.isAffectedByGravity = false
            let color = CAKeyframeAnimation()
            color.values = [NSColor(rgb: (1, 0.92, 0.8)), NSColor(rgb: (1, 0.55, 0.35)), NSColor(rgb: (0.4, 0.1, 0.12))]
            color.keyTimes = [0, 0.4, 1]
            ps.propertyControllers = [.color: SCNParticlePropertyController(animation: color)]
            return ps
        }

        /// The fire off the nozzles: hot and white at the mouth, orange, then dark red as it goes, carried with
        /// the rocket.
        static func fire() -> SCNParticleSystem {
            let ps = SCNParticleSystem()
            ps.particleImage = Textures.glare
            ps.birthRate = 900
            ps.loops = true
            ps.emitterShape = SCNCylinder(radius: radius * 0.6, height: 0.005)
            ps.birthLocation = .volume
            ps.emittingDirection = SCNVector3(0, -1, 0)
            ps.spreadingAngle = 4
            ps.particleVelocity = 2.4
            ps.particleVelocityVariation = 0.6
            ps.particleLifeSpan = 0.32
            ps.particleLifeSpanVariation = 0.08
            ps.particleSize = 0.035
            ps.particleSizeVariation = 0.012
            ps.blendMode = .additive
            ps.isLocal = true
            ps.isAffectedByGravity = false
            let color = CAKeyframeAnimation()
            // White-hot at the lip, then dense cream-white exhaust thinning out: no fire colours.
            color.values = [NSColor(rgb: (1, 0.98, 0.94)), NSColor(rgb: (0.96, 0.92, 0.86)), NSColor(rgb: (0.78, 0.75, 0.72)), NSColor(rgb: (0.2, 0.2, 0.2))]
            color.keyTimes = [0, 0.25, 0.65, 1]
            ps.propertyControllers = [.color: SCNParticlePropertyController(animation: color)]
            let grow = CAKeyframeAnimation(); grow.values = [0.7, 1.8, 3.2]; grow.keyTimes = [0, 0.4, 1]
            ps.propertyControllers?[.size] = SCNParticlePropertyController(animation: grow)
            return ps
        }

        /// Smoke left in the air behind the climb: it stays where it was made while the rocket goes on.
        static func smoke() -> SCNParticleSystem {
            let ps = SCNParticleSystem()
            ps.particleImage = Textures.puff
            ps.birthRate = 220
            ps.loops = true
            ps.emitterShape = SCNSphere(radius: 0.06)
            ps.emittingDirection = SCNVector3(0, -1, 0)
            ps.spreadingAngle = 18
            ps.particleVelocity = 0.5
            ps.particleVelocityVariation = 0.3
            ps.particleLifeSpan = 5
            ps.particleLifeSpanVariation = 1.5
            ps.particleSize = 0.12
            ps.particleSizeVariation = 0.06
            ps.dampingFactor = 1.2
            ps.particleAngleVariation = 180
            ps.particleAngularVelocityVariation = 20
            ps.particleColor = NSColor(rgb: (0.78, 0.74, 0.7)).withAlphaComponent(0.55)
            ps.particleColorVariation = SCNVector4(0, 0.05, 0.12, 0.15)
            ps.blendMode = .alpha
            ps.isLocal = false
            ps.isAffectedByGravity = false
            let fade = CAKeyframeAnimation(); fade.values = [0, 0.7, 0.45, 0]; fade.keyTimes = [0, 0.08, 0.5, 1]
            ps.propertyControllers = [.opacity: SCNParticlePropertyController(animation: fade)]
            let grow = CAKeyframeAnimation(); grow.values = [0.6, 2.5, 5]; grow.keyTimes = [0, 0.35, 1]
            ps.propertyControllers?[.size] = SCNParticlePropertyController(animation: grow)
            return ps
        }
    }
}

/// The craft's skins and its fire, drawn once in code.
enum Textures {
    /// A bitmap drawn with AppKit, top-left at the origin, the way a cylinder's texture runs: across is round
    /// the hull, down is down it.
    static func draw(_ w: Int, _ h: Int, _ body: (CGContext, CGFloat, CGFloat) -> Void) -> NSImage {
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return NSImage() }
        ctx.translateBy(x: 0, y: CGFloat(h)); ctx.scaleBy(x: 1, y: -1)
        let ns = NSGraphicsContext(cgContext: ctx, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ns
        body(ctx, CGFloat(w), CGFloat(h))
        NSGraphicsContext.restoreGraphicsState()
        guard let img = ctx.makeImage() else { return NSImage() }
        return NSImage(cgImage: img, size: NSSize(width: w, height: h))
    }

    /// A repeatable scatter, so a skin looks the same every flight.
    struct Seeded { var s: UInt64; mutating func next() -> Double { s = s &* 6364136223846793005 &+ 1442695040888963407; return Double(s >> 11) / Double(1 << 53) } }

    /// Brushed steel: a pale grey, streaked down its length.
    static func brushed(_ ctx: CGContext, _ w: CGFloat, _ h: CGFloat, base: Double, seed: UInt64) {
        var r = Seeded(s: seed)
        ctx.setFillColor(NSColor(white: base, alpha: 1).cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        for _ in 0..<Int(w * 1.2) {
            let x = r.next() * w, a = r.next() * 0.06
            ctx.setFillColor(NSColor(white: r.next() < 0.5 ? 0 : 1, alpha: a).cgColor)
            ctx.fill(CGRect(x: x, y: 0, width: 1 + r.next() * 2, height: h))
        }
    }

    static let steel = draw(128, 512) { ctx, w, h in brushed(ctx, w, h, base: 0.7, seed: 9) }
    static let soot = draw(256, 128) { ctx, w, h in
        brushed(ctx, w, h, base: 0.12, seed: 13)
    }
    /// An engine bell: dark metal, blued and burnt toward the mouth.
    static let bell = draw(256, 256) { ctx, w, h in
        NSGradient(colors: [NSColor(rgb: (0.32, 0.32, 0.35)), NSColor(rgb: (0.24, 0.2, 0.22)), NSColor(rgb: (0.1, 0.09, 0.1))])!
            .draw(in: NSRect(x: 0, y: 0, width: w, height: h), angle: 90)
        for i in 0..<12 { ctx.setFillColor(NSColor(white: 0, alpha: 0.18).cgColor); ctx.fill(CGRect(x: w * CGFloat(i) / 12, y: 0, width: 1.5, height: h)) }
    }
    /// The exhaust's core: white-hot, with a row of bright shock diamonds fading down its length.
    static let diamonds = draw(64, 512) { ctx, w, h in
        NSGradient(colors: [NSColor.white, NSColor(rgb: (1, 0.97, 0.9)), NSColor(rgb: (0.9, 0.86, 0.8)), NSColor(rgb: (0.3, 0.29, 0.28))])!
            .draw(in: NSRect(x: 0, y: 0, width: w, height: h), angle: 90)
        for i in 0..<6 {
            let y = h * (0.08 + CGFloat(i) * 0.12), k = 1 - CGFloat(i) / 6
            ctx.setFillColor(NSColor(white: 1, alpha: 0.75 * k).cgColor)
            ctx.fill(CGRect(x: 0, y: y, width: w, height: h * 0.035))
            ctx.setFillColor(NSColor(white: 0, alpha: 0.35 * k).cgColor)
            ctx.fill(CGRect(x: 0, y: y + h * 0.05, width: w, height: h * 0.03))
        }
    }
    /// A soft round glare, white at the middle.
    static let glare = draw(64, 64) { ctx, w, h in
        let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [NSColor(white: 1, alpha: 1).cgColor, NSColor(rgb: (1, 0.96, 0.9)).withAlphaComponent(0.35).cgColor, NSColor(white: 0, alpha: 0).cgColor] as CFArray, locations: [0, 0.3, 1])!
        ctx.drawRadialGradient(g, startCenter: CGPoint(x: w / 2, y: h / 2), startRadius: 0, endCenter: CGPoint(x: w / 2, y: h / 2), endRadius: w / 2, options: [])
    }
    /// The soot of the engines up a stage, once over: clean at the top, burnt dark and streaked at the foot.
    static let sootRise = draw(256, 512) { ctx, w, h in
        ctx.setFillColor(NSColor.white.cgColor); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        NSGradient(colors: [NSColor.white, NSColor(white: 0.78, alpha: 1), NSColor(rgb: (0.22, 0.2, 0.19))],
                   atLocations: [0, 0.55, 1], colorSpace: .deviceRGB)!.draw(in: NSRect(x: 0, y: h * 0.45, width: w, height: h * 0.55), angle: 90)
        var r = Seeded(s: 29)
        for _ in 0..<70 {
            let x = r.next() * w, len = h * (0.1 + r.next() * 0.35)
            ctx.setFillColor(NSColor(white: 0.25, alpha: 0.06 + r.next() * 0.1).cgColor)
            ctx.fill(CGRect(x: x, y: h - len, width: 2 + r.next() * 8, height: len))
        }
    }
    /// The vacuum flame: blue, brightest at the top where it leaves the nozzle, fading out down its length
    /// and toward its edges all round.
    static let blueFlame = draw(128, 256) { ctx, w, h in
        NSGradient(colors: [NSColor(rgb: (0.75, 0.88, 1)), NSColor(rgb: (0.3, 0.5, 1)), NSColor(rgb: (0.08, 0.15, 0.45)), NSColor.black],
                   atLocations: [0, 0.25, 0.65, 1], colorSpace: .deviceRGB)!.draw(in: NSRect(x: 0, y: 0, width: w, height: h), angle: 90)
        // Seen from the side a cone shows a band of its round: the band dims toward where it turns away.
        for i in 0..<Int(w) {
            let u = Double(i) / Double(w), k = 0.55 + 0.45 * cos(u * 2 * .pi * 3)
            ctx.setFillColor(NSColor(white: 0, alpha: CGFloat(0.35 * (1 - k))).cgColor)
            ctx.fill(CGRect(x: CGFloat(i), y: 0, width: 1, height: h))
        }
    }
    static let blueGlare = draw(64, 64) { ctx, w, h in
        let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [NSColor(rgb: (0.8, 0.9, 1)).cgColor, NSColor(rgb: (0.3, 0.5, 1)).withAlphaComponent(0.3).cgColor, NSColor(white: 0, alpha: 0).cgColor] as CFArray, locations: [0, 0.3, 1])!
        ctx.drawRadialGradient(g, startCenter: CGPoint(x: w / 2, y: h / 2), startRadius: 0, endCenter: CGPoint(x: w / 2, y: h / 2), endRadius: w / 2, options: [])
    }
    /// The glow of air pressed hot against the foot: white at the middle, pink-orange, gone at the edge.
    static let plasma = draw(128, 128) { ctx, w, h in
        let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [NSColor(rgb: (1, 0.95, 0.88)).cgColor, NSColor(rgb: (1, 0.55, 0.4)).withAlphaComponent(0.6).cgColor, NSColor(white: 0, alpha: 0).cgColor] as CFArray, locations: [0, 0.35, 1])!
        ctx.drawRadialGradient(g, startCenter: CGPoint(x: w / 2, y: h / 2), startRadius: 0, endCenter: CGPoint(x: w / 2, y: h / 2), endRadius: w / 2, options: [])
    }
    /// A puff of smoke: soft, ragged at the edge.
    static let puff = draw(64, 64) { ctx, w, h in
        var r = Seeded(s: 17)
        for _ in 0..<18 {
            let cx = w * (0.3 + r.next() * 0.4), cy = h * (0.3 + r.next() * 0.4), rad = w * (0.12 + r.next() * 0.18)
            let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [NSColor(white: 1, alpha: 0.35).cgColor, NSColor(white: 1, alpha: 0).cgColor] as CFArray, locations: [0, 1])!
            ctx.drawRadialGradient(g, startCenter: CGPoint(x: cx, y: cy), startRadius: 0, endCenter: CGPoint(x: cx, y: cy), endRadius: rad, options: [])
        }
    }
}
