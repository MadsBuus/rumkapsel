// The classic look: flat shading adrift in space, the homage the station started as. Its pieces are what
// every look gets unless it draws its own (see `extension Look`), kept here as `Classic` so a look whose
// own model is missing can still fall back on the classic piece.

import AppKit
import SceneKit

struct ClassicLook: Look {}

enum Classic {
    /// Flakes of debris drifting, a far star field and a few nebulae.
    static func backdrop(into root: SCNNode) -> [(SCNNode, SIMD2<Double>)] {
        var drifting: [(SCNNode, SIMD2<Double>)] = []
        // Debris is one stream, not a swarm: every flake runs the same heading, and only how fast it
        // runs it differs, so the field reads as something the station is passing through.
        let heading = Double.random(in: 0..<6.28)
        let course = SIMD2(cos(heading), sin(heading))
        for _ in 0..<110 {
            let size = Double.random(in: 0.05...0.13)
            let n = SCNNode(geometry: SCNPlane(width: size, height: size))
            n.geometry!.firstMaterial = flat(Palette.debris)
            n.opacity = Double.random(in: 0.25...0.7)
            n.eulerAngles.x = -.pi / 2
            n.eulerAngles.z = Double.random(in: 0..<6.28)
            let p = SIMD2(Double.random(in: -40...40), Double.random(in: -40...40))
            n.position = v3(p.x, -0.6, p.y)
            root.addChildNode(n)
            drifting.append((n, course * Double.random(in: 0.18...0.42)))
        }
        starField(into: root)

        for _ in 0..<4 {
            let cluster = SCNNode()
            let count = Int.random(in: 12...20)
            for _ in 0..<count {
                let size = Double.random(in: 0.25...0.4)
                let n = SCNNode(geometry: SCNPlane(width: size, height: size))
                let shade = Double.random(in: 0...1)
                n.geometry!.firstMaterial = flat(NSColor(rgb: (0.55 + 0.25 * shade, 0.22 + 0.15 * shade, 0.40 + 0.15 * shade)))
                n.eulerAngles.x = -.pi / 2
                let a = Double.random(in: 0..<6.28), r = Double.random(in: 0...1.3)
                n.position = v3(cos(a) * r, Double.random(in: -0.15...0.15), sin(a) * r)
                cluster.addChildNode(n)
            }
            let p = SIMD2(Double.random(in: -30...30), Double.random(in: -30...30))
            cluster.position = v3(p.x, -0.4, p.y)
            // A nebula is further off than a flake, so it wheels slowly and drifts at half the pace.
            cluster.runAction(.repeatForever(.rotateBy(x: 0, y: CGFloat(6.28 * (Bool.random() ? 1 : -1)), z: 0, duration: Double.random(in: 90...160))))
            root.addChildNode(cluster)
            drifting.append((cluster, SIMD2(Double.random(in: -0.16...0.16), Double.random(in: -0.16...0.16))))
        }
        return drifting
    }

    /// The far, still star field, in three layers: a haze of faint dust, a scatter of ordinary stars and a
    /// handful of bright ones. A point cloud carries one size for all its points, so each layer is its own
    /// geometry — that difference in size is most of what separates a star field from grey noise. A third of
    /// the dust is drawn towards one diagonal lane, the galaxy the station is looking along.
    private static func starField(into root: SCNNode) {
        let lane = Double.random(in: 0..<6.28)
        let along = SIMD2(cos(lane), sin(lane)), across = SIMD2(-sin(lane), cos(lane))
        func place(inLane: Bool) -> SCNVector3 {
            guard inLane else { return v3(Double.random(in: -90...90), -12, Double.random(in: -90...90)) }
            // Two uniforms summed pile up in the middle, so the lane has a dense spine and soft edges.
            let off = (Double.random(in: -1...1) + Double.random(in: -1...1)) * 14
            let p = along * Double.random(in: -90...90) + across * off
            return v3(p.x, -12, p.y)
        }
        // A star's colour follows its heat: mostly blue-white, a few embers. Squaring the pick keeps the
        // warm ones rare, the way they are in a real sky.
        func tint(_ brightness: Double) -> SCNVector4 {
            let warm = pow(Double.random(in: 0...1), 2)
            let r = (0.72 + 0.28 * warm) * brightness
            let g = (0.82 + 0.02 * warm) * brightness
            let b = (1.00 - 0.35 * warm) * brightness
            return SCNVector4(r, g, b, 1)
        }
        for (count, size, range, laned) in [(1500, 1.0, 0.10...0.30, true), (400, 1.9, 0.34...0.60, false), (60, 3.4, 0.70...1.00, false)] {
            var points: [SCNVector3] = [], colors: [SCNVector4] = []
            for _ in 0..<count {
                points.append(place(inLane: laned && Double.random(in: 0...1) < 0.34))
                colors.append(tint(Double.random(in: range)))
            }
            let vertices = SCNGeometrySource(vertices: points)
            let data = Data(bytes: colors, count: colors.count * MemoryLayout<SCNVector4>.stride)
            let colorSource = SCNGeometrySource(data: data, semantic: .color, vectorCount: colors.count, usesFloatComponents: true,
                                                componentsPerVector: 4, bytesPerComponent: MemoryLayout<CGFloat>.size, dataOffset: 0, dataStride: MemoryLayout<SCNVector4>.stride)
            let element = SCNGeometryElement(indices: (0..<points.count).map { Int32($0) }, primitiveType: .point)
            element.pointSize = CGFloat(size)
            element.minimumPointScreenSpaceRadius = CGFloat(size * 0.5)
            element.maximumPointScreenSpaceRadius = CGFloat(size * 1.4)
            let geometry = SCNGeometry(sources: [vertices, colorSource], elements: [element])
            let material = SCNMaterial()
            material.lightingModel = .constant
            material.diffuse.contents = NSColor.white
            material.blendMode = .add
            geometry.firstMaterial = material
            root.addChildNode(SCNNode(geometry: geometry))
        }
    }

    /// The hull at the outer door: a quarter ellipse in section, so it leaves the floor upright, where the
    /// door is set into it, and is lying flat by the time it reaches its crown over the station. `D` is how
    /// far it may lean and `H` how high it stands; both come off the airlock's own run, so the wall is gone
    /// before the inner door however long a plan makes that chamber.
    ///
    /// One surface with its plating and its fade painted on rather than the slats the rest of the look is
    /// built from: the fade runs two ways at once, up the curve and out to either side, and a slat can only
    /// carry one opacity. It writes no depth and draws last, so nothing behind it is ever hidden — the wall
    /// says where the station ends, it does not cover what the station holds.
    static func hullWall(width: Double, depth: Double, doorway: Double) -> SCNNode? {
        let (D, H) = hullSection(depth: depth)
        let steps = 48
        /// Where the wall's face is at a given height: t back out of `rise`, then the lean at that t.
        func lean(atHeight y: Double) -> Double {
            let a = asin(max(0, min(1, y / H)))
            return -D * (1 - cos(a))
        }
        var vertices: [SCNVector3] = [], uvs: [CGPoint] = [], indices: [Int32] = []
        for j in 0...steps {
            let t = Double(j) / Double(steps), a = t * .pi / 2
            let back = -D * (1 - cos(a)), rise = H * sin(a)   // back toward the station as it climbs
            vertices.append(v3(-width / 2, rise, back)); uvs.append(CGPoint(x: 0, y: t))
            vertices.append(v3(width / 2, rise, back)); uvs.append(CGPoint(x: 1, y: t))
            guard j < steps else { continue }
            let i = Int32(j * 2)
            indices += [i, i + 2, i + 1, i + 1, i + 2, i + 3]
        }
        let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: vertices),
                                             SCNGeometrySource(textureCoordinates: uvs)],
                                   elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
        // The doorway is a hole cut clean out of the plating, not a patch of it made thinner: the wall is
        // solid where it meets the floor, which is exactly where the door stands, so anything short of a
        // hole buries the frame. It is cut a shade *inside* the frame's outer edge, top and sides, so the
        // frame always laps the plating and no seam of space shows between the two. A wall with no door
        // asks for none, and is a blank stretch of hull.
        let hole = doorway > 0 ? (halfU: (doorway + 0.04) / 2 / width, topV: asin(min(1, hatchTop / H)) / (.pi / 2))
                               : (halfU: 0.0, topV: 0.0)
        let skin = hullSkin(panels: max(1, Int(width.rounded())), door: hole)
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = skin.plating
        material.transparent.contents = skin.fade
        material.isDoubleSided = true
        material.writesToDepthBuffer = false
        geometry.firstMaterial = material
        let wall = SCNNode(geometry: geometry)
        wall.renderingOrder = 100
        // A wall this size would swallow every hover and click over the airlock, and it is scenery. Its own
        // category keeps it out of the hit test, which asks for `Pick.normal`. Never zero: the camera reads
        // this same mask to decide what to draw, and a node with no bits set is a node it cannot see.
        wall.categoryBitMask = Pick.scenery
        // Approach lights either side of the doorway, just above its lintel, proud of the plating. The tick
        // blinks them while a ship is on its way in, so they blink headless too. A blank stretch of hull has
        // no door to flank and goes dark.
        for side in [-1.0, 1.0] where doorway > 0 {
            let lamp = SCNNode(geometry: SCNBox(width: 0.1, height: 0.1, length: 0.1, chamferRadius: 0))
            lamp.geometry!.firstMaterial = flat(Props.hullLampOff)
            lamp.name = "beacon"
            lamp.position = v3(side * 0.72, 0.86, lean(atHeight: 0.86) + 0.07)
            wall.addChildNode(lamp)
        }
        return wall
    }

    /// The hull's skin, as two images the wall is painted with. `plating` is the colour: a deck plate at the
    /// floor going cooler and lighter as it climbs, scored across into panels and along into courses, with a
    /// bright rail at the very bottom. `fade` is the alpha: solid for the first stretch, where the door is
    /// set into it, then falling away fast so the curve overhead is a hint and never a lid, and drawn in at
    /// either end over the outermost fifth so the wall ends where the bay does.
    private static func hullSkin(panels: Int, door: (halfU: Double, topV: Double)) -> (plating: NSImage?, fade: NSImage?) {
        let key = "\(panels)|\(Int(door.halfU * 1000))|\(Int(door.topV * 1000))"
        if let made = skins[key] { return made }
        let w = 256, h = 512
        var plate = [UInt8](repeating: 0, count: w * h * 4), fade = [UInt8](repeating: 0, count: w * h * 4)
        let solid = 0.14
        for y in 0..<h {
            let t = Double(y) / Double(h - 1)
            let up = t <= solid ? 1 : pow(max(0, 1 - (t - solid) / (0.9 - solid)), 2.5)
            // Courses run across the wall every eighth of its climb; the seam is a shade under the plate.
            let course = abs((t * 8).truncatingRemainder(dividingBy: 1) - 0.5) > 0.47
            for x in 0..<w {
                let u = Double(x) / Double(w - 1)
                let e = min(min(u, 1 - u) / 0.2, 1)
                let side = e * e * (3 - 2 * e)
                let cut = abs(u - 0.5) < door.halfU && t < door.topV
                let seam = abs((u * Double(panels)).truncatingRemainder(dividingBy: 1) - 0.5) > 0.485
                // The rail runs along the foot of the wall and stops either side of the doorway, and the
                // jamb picks it up again as a bright edge round the cut.
                let rail = t < 0.012 && !cut
                let jamb = !cut && door.halfU > 0 && (abs(abs(u - 0.5) - door.halfU) < 0.006 && t < door.topV
                                                      || abs(t - door.topV) < 0.004 && abs(u - 0.5) < door.halfU)
                var shade = 0.0
                if seam || course { shade = -0.10 }
                if rail || jamb { shade = 0.16 }
                let i = (y * w + x) * 4
                let deck = Props.hullPlate
                let c = (deck.0 + 0.22 * t + shade, deck.1 + 0.25 * t + shade, deck.2 + 0.31 * t + shade)
                plate[i] = byte(c.0); plate[i + 1] = byte(c.1); plate[i + 2] = byte(c.2); plate[i + 3] = 255
                // Premultiplied, so every channel carries the alpha; only the alpha is ever read.
                let a = cut ? 0 : byte(up * side)
                fade[i] = a; fade[i + 1] = a; fade[i + 2] = a; fade[i + 3] = a
            }
        }
        let made = (image(plate, w, h, premultiplied: false), image(fade, w, h, premultiplied: true))
        skins[key] = made
        return made
    }

    /// Where the doorway's head is cut: just under the top of the lintel, so the lintel laps it.
    static let hatchTop = 0.76

    /// The wall's section: how far it may lean and how high it stands, both off the run it is given.
    private static func hullSection(depth: Double) -> (lean: Double, rise: Double) {
        (depth * 0.72, min(3.3, depth * 0.58))
    }

    /// How deep the outer door's frame must be to sit in the hull without a gap. The wall's face slips back
    /// as it climbs, so a frame in one plane meets it at one height and gapes at every other; this is the
    /// slip across the doorway's own height, with a margin either side.
    static func hullDoorReveal(depth: Double) -> Double {
        let (D, H) = hullSection(depth: depth)
        return D * (1 - cos(asin(min(1, hatchTop / H)))) + 0.12
    }
    private static var skins: [String: (plating: NSImage?, fade: NSImage?)] = [:]
    private static func byte(_ v: Double) -> UInt8 { UInt8(max(0, min(255, v * 255))) }
    private static func image(_ pixels: [UInt8], _ w: Int, _ h: Int, premultiplied: Bool) -> NSImage? {
        let alpha = premultiplied ? CGImageAlphaInfo.premultipliedLast : .noneSkipLast
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let cg = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                               space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: alpha.rawValue),
                               provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: w, height: h))
    }

    /// A lintel across the posts.
    static func airlockFrame(width: Double, spans: [Double], tint: NSColor) -> (node: SCNNode, showsPosts: Bool) {
        let lintel = SCNNode(geometry: SCNBox(width: width + 0.08, height: 0.08, length: 0.08, chamferRadius: 0))
        lintel.geometry!.firstMaterial = lit(tint)
        lintel.position = v3(0, 0.74, 0)
        return (lintel, true)
    }

    /// Two posts and a lintel.
    static func hatchFrame(facing: SIMD2<Double>) -> (node: SCNNode, lightHeight: Double) {
        let hatch = SCNNode()
        let frame = lit(NSColor(rgb: (0.55, 0.6, 0.72)))
        for side in [-1.0, 1.0] {
            let post = SCNNode(geometry: SCNBox(width: 0.08, height: 0.7, length: 0.08, chamferRadius: 0))
            post.geometry!.firstMaterial = frame
            post.position = v3(side * 0.5, 0.35, 0)
            hatch.addChildNode(post)
        }
        let lintel = SCNNode(geometry: SCNBox(width: 1.08, height: 0.08, length: 0.08, chamferRadius: 0))
        lintel.geometry!.firstMaterial = frame
        lintel.position = v3(0, 0.74, 0)
        hatch.addChildNode(lintel)
        return (hatch, 0.84)
    }

    /// A dark column with a band of light near its top.
    static func monolith() -> SCNNode {
        let n = SCNNode()
        let core = SCNNode(geometry: SCNBox(width: 0.7, height: 2.3, length: 0.7, chamferRadius: 0))
        core.geometry!.firstMaterial = lit(Palette.core)
        core.position = v3(0, 1.15, 0)
        n.addChildNode(core)
        let glow = SCNNode(geometry: SCNBox(width: 0.72, height: 0.04, length: 0.72, chamferRadius: 0))
        glow.geometry!.firstMaterial = flat(NSColor(rgb: (0.55, 0.75, 1.0)))
        glow.position = v3(0, 1.75, 0)
        n.addChildNode(glow)
        return n
    }

    /// The shuttle body, wings in a repo colour.
    static func shuttle(color: NSColor) -> SCNNode {
        let ship = SCNNode()
        let hull = SCNNode(geometry: SCNBox(width: 0.7, height: 0.14, length: 0.4, chamferRadius: 0.03))
        hull.geometry!.firstMaterial = lit(NSColor(rgb: (0.85, 0.86, 0.9)))
        ship.addChildNode(hull)
        let cockpit = SCNNode(geometry: SCNBox(width: 0.2, height: 0.1, length: 0.2, chamferRadius: 0.02))
        cockpit.geometry!.firstMaterial = lit(NSColor(rgb: (0.55, 0.75, 1.0)))
        cockpit.position = v3(0.16, 0.11, 0)
        ship.addChildNode(cockpit)
        for side in [-1.0, 1.0] {
            let wing = SCNNode(geometry: SCNBox(width: 0.28, height: 0.05, length: 0.34, chamferRadius: 0))
            wing.geometry!.firstMaterial = lit(color)
            wing.position = v3(-0.14, 0, side * 0.34)
            ship.addChildNode(wing)
        }
        for side in [-1.0, 1.0] {
            let skid = SCNNode(geometry: SCNBox(width: 0.5, height: 0.03, length: 0.03, chamferRadius: 0))
            skid.geometry!.firstMaterial = lit(NSColor(rgb: (0.3, 0.3, 0.35)))
            skid.position = v3(0, -0.14, side * 0.16)
            ship.addChildNode(skid)
        }
        return ship
    }

    /// A flicker on the pad, then a slow climb out of the frame, fading as it goes.
    static func launch() -> SCNAction {
        let rise = SCNAction.moveBy(x: 0, y: 40, z: 0, duration: 12)
        rise.timingMode = .easeIn
        let flicker = SCNAction.repeat(.sequence([.scale(to: 1.04, duration: 0.08), .scale(to: 0.98, duration: 0.08)]), count: 8)
        return .sequence([flicker, .group([rise, .sequence([.wait(duration: 9), .fadeOut(duration: 3)])])])
    }

    static func rocket(color: NSColor, tall: Bool, cargo: Int) -> SCNNode {
        Props.rocket(color: color, tall: tall, cargo: cargo)
    }
}
