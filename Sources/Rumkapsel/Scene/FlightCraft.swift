import AppKit
import SceneKit

enum FlightCraft {
    static let radius = RocketShape.radius
    static var lifterTop: Double { RocketShape.split }
    static var tipBase: Double { RocketShape.split }
    static var noseTop: Double { RocketShape.height }
    static let cameraBearing = RocketShape.cameraBearing
    static let sides = 12
    static let cornerOffset = Double.pi / Double(sides)
    static func faceMiddle(near bearing: Double) -> Double {
        let step = 2 * Double.pi / Double(sides), first = cornerOffset + step / 2
        return first + ((bearing - first) / step).rounded() * step
    }
    static let plateSize = 0.22
    static var standDepth: Double { RocketShape.standDepth }

    static func build(color: NSColor, repo: String, release: String, hotfix: Bool = false) -> (lifter: SCNNode, tip: SCNNode) {
        let lifter = SCNNode(), tip = SCNNode()
        lifter.name = "lifter"; tip.name = "tip"
        buildLifter(lifter, color: color, repo: repo, release: release)
        buildTip(tip, color: color, repo: repo, hotfix: hotfix)
        let names = RocketShape.names(repo.uppercased(), color: color, scale: 1, apothem: { RocketShape.r($0) * cos(.pi / Double(sides)) },
                                      width: RocketShape.nameWidth, flatShaded: false)
        names.lifter.forEach(lifter.addChildNode)
        names.tip.forEach(tip.addChildNode)
        return (lifter, tip)
    }

    // MARK: the lifter

    private static func bands(_ profile: [(y: Double, r: Double)], material: SCNMaterial, closeBottom: Bool, closeTop: Bool) -> SCNNode {
        let n = SCNNode()
        let span = (low: profile.first!.y, high: profile.last!.y)
        for i in 0..<(profile.count - 1) {
            let lo = profile[i], hi = profile[i + 1]
            n.addChildNode(SCNNode(geometry: hullBand(r0: lo.r, r1: max(0.0005, hi.r), y0: lo.y, y1: hi.y, material: material,
                                                      closed: (closeBottom && i == 0, closeTop && i == profile.count - 2), span: span)))
        }
        return n
    }

    private static func buildLifter(_ n: SCNNode, color: NSColor, repo: String, release: String) {
        let shape = RocketShape.self
        let bodySkin = Materials.hull(seed: 21)
        bodySkin.multiply.contents = Textures.sootRise
        bodySkin.multiply.mappingChannel = 1
        bodySkin.multiply.wrapS = .clamp; bodySkin.multiply.wrapT = .clamp
        n.addChildNode(bands(shape.profile(from: shape.base, to: shape.split, steps: 8), material: bodySkin, closeBottom: true, closeTop: true))
        let tail = shape.r(shape.base)
        for k in 0..<7 {
            let a = Double(k) * .pi / 3
            let at = k == 6 ? SIMD2(0.0, 0.0) : SIMD2(cos(a), sin(a)) * tail * shape.bellRing
            let bell = SCNNode(geometry: round(SCNCone(topRadius: shape.bellTop, bottomRadius: shape.bellBottom, height: shape.bellHeight)))
            bell.geometry!.firstMaterial = Materials.bell
            bell.position = v3(at.x, shape.base - shape.bellHeight / 2, at.y)
            n.addChildNode(bell)
        }
        for a in shape.finBearings { n.addChildNode(fin(at: a, color: color)) }
        let plume = FlightCraft.airPlume()
        plume.name = "lifter plume"
        plume.position = v3(0, shape.base - shape.bellHeight, 0)
        n.addChildNode(plume)
    }

    // MARK: the tip

    private static func buildTip(_ n: SCNNode, color: NSColor, repo: String, hotfix: Bool) {
        let shape = RocketShape.self
        let plates = Materials.hull(seed: 31)
        n.addChildNode(bands(shape.profile(from: shape.split, to: shape.panelTop, steps: 5), material: plates, closeBottom: true, closeTop: false))
        let nose = hotfix ? Materials.plated(seed: 31, tint: paint(RocketShape.hotfixRed)) : plates
        n.addChildNode(bands(shape.profile(from: shape.panelTop, to: shape.height, steps: 6), material: nose, closeBottom: false, closeTop: false))
        n.addChildNode(bands(shape.profile(from: shape.bandLow, to: shape.bandHigh, steps: 2).map { ($0.y, $0.r * 1.006) },
                             material: Materials.plated(seed: 41, tint: paint(color)), closeBottom: false, closeTop: false))
        for a in shape.legBearings { n.addChildNode(RocketShape.leg(at: a, scale: 1, segments: 4, material: Materials.plated(seed: 41, tint: paint(RocketShape.legColor)))) }
        let engine = SCNNode(geometry: round(SCNCone(topRadius: shape.engineTop, bottomRadius: shape.engineBottom, height: shape.engineHeight)))
        engine.geometry!.firstMaterial = Materials.bell
        engine.position = v3(0, shape.split - shape.engineHeight / 2, 0)
        n.addChildNode(engine)
        for a in shape.rcsBearings {
            n.addChildNode(RocketShape.thruster(at: a, scale: 1, surface: { RocketShape.r($0) * cos(.pi / Double(sides)) }, hull: plates, nozzle: Materials.dark))
        }
        n.addChildNode(raceway(from: shape.split + 0.05, to: shape.panelTop - 0.04))
        n.addChildNode(RocketShape.hatch(scale: 1, surface: { RocketShape.r($0) * cos(.pi / Double(sides)) }, flatShaded: false))
        let beacon = SCNNode(geometry: SCNSphere(radius: 0.012))
        beacon.geometry!.firstMaterial = Materials.glow(color.lighter(0.5))
        beacon.position = v3(0, noseTop + 0.004, 0)
        beacon.runAction(.repeatForever(.sequence([.fadeOpacity(to: 1, duration: 0.1), .wait(duration: 0.35),
                                                   .fadeOpacity(to: 0.15, duration: 0.25), .wait(duration: 0.5)])))
        n.addChildNode(beacon)
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
        plume.position = v3(0, tipBase - RocketShape.engineHeight, 0)
        plume.isHidden = true
        n.addChildNode(plume)
        n.setValue(tipBase, forKey: "split")
    }

    static func paint(_ color: NSColor) -> SIMD3<Double> {
        let c = color.usingColorSpace(.deviceRGB) ?? color
        return SIMD3(Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent)) * 0.82
    }

    static func surface(at bearing: Double, radius r: Double = radius) -> Double {
        r * cos(.pi / Double(sides)) / cos(bearing - faceMiddle(near: bearing))
    }

    static func hullBand(r0: Double, r1: Double, y0: Double, y1: Double, material: SCNMaterial, closed: (bottom: Bool, top: Bool) = (false, false),
                         span: (low: Double, high: Double)? = nil) -> SCNGeometry {
        let whole0 = span?.low ?? y0, whole1 = span?.high ?? y1
        let tile = plateSize
        var verts: [SCNVector3] = [], normals: [SCNVector3] = [], uvs: [CGPoint] = [], whole: [CGPoint] = [], tangents: [SCNVector4] = [], idx: [Int32] = []
        func corner(_ k: Int, _ r: Double, _ y: Double) -> SIMD3<Double> {
            let a = cornerOffset + Double(k) * 2 * .pi / Double(sides)
            return SIMD3(cos(a) * r, y, sin(a) * r)
        }
        let side = 2 * sin(.pi / Double(sides))
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
                whole.append(CGPoint(x: side + 0.5, y: (whole1 - y) / max(1e-6, whole1 - whole0)))
                tangents.append(SCNVector4(along.x, along.y, along.z, 1))
            }
            idx += [base, base + 2, base + 1, base, base + 3, base + 2]
        }
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

    private static func fin(at a: Double, color: NSColor) -> SCNNode {
        let shape = RocketShape.self
        let pivot = SCNNode()
        pivot.eulerAngles.y = CGFloat(-a)
        let plate = SCNShape(path: shape.finOutline(scale: 1), extrusionDepth: 0.01)
        plate.chamferRadius = 0.0015
        let skin = Materials.plated(seed: 41, tint: paint(color))
        let fit = SCNMatrix4MakeScale(CGFloat(shape.finReach / plateSize), CGFloat(shape.finRootHigh / plateSize), 1)
        for p in [skin.diffuse, skin.roughness] { p.contentsTransform = fit }
        skin.normal.contents = nil
        plate.firstMaterial = skin
        pivot.addChildNode(SCNNode(geometry: plate))
        let pod = SCNNode(geometry: round(SCNCapsule(capRadius: shape.podRadius, height: shape.podLength)))
        pod.geometry!.firstMaterial = Materials.plated(seed: 41, tint: paint(color))
        pod.position = v3(shape.finReach, shape.podLength / 2, 0)
        pivot.addChildNode(pod)
        return pivot
    }

    static func strain(_ tip: SCNNode, heat: Double) {
        guard let strain = tip.childNode(withName: "strain", recursively: false) else { return }
        let k = max(0, min(1, heat))
        strain.opacity = CGFloat(k)
        strain.enumerateHierarchy { n, _ in n.particleSystems?.first?.birthRate = CGFloat(260 * k) }
    }

    static func feet(_ tip: SCNNode, out: Double) { RocketShape.fold(tip, 1 - out) }

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

    static func mountCameras(lifter: SCNNode, tip: SCNNode) {
        let r = radius
        lifter.addChildNode(camera("down cam", reach: r * 1.32, height: lifterTop - 0.06, looking: SIMD3(0, -1, 0), lean: 0.1))
    }

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

    static func stars() -> SCNNode {
        var r = Textures.Seeded(s: 977)
        var points: [SCNVector3] = [], colors: [SIMD4<Float>] = []
        for _ in 0..<4500 {
            let z = r.next() * 2 - 1, a = r.next() * 2 * .pi, ring = (1 - z * z).squareRoot()
            points.append(SCNVector3(ring * cos(a) * 400, z * 400, ring * sin(a) * 400))
            let b = Float(pow(r.next(), 3) * 0.85 + 0.15)
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

    static let environment = Textures.draw(512, 256) { ctx, w, h in
        NSGradient(colors: [NSColor(rgb: (0.02, 0.025, 0.04)), NSColor(rgb: (0.1, 0.11, 0.14)), NSColor(rgb: (0.03, 0.03, 0.045))],
                   atLocations: [0, 0.55, 1], colorSpace: .deviceRGB)!.draw(in: NSRect(x: 0, y: 0, width: w, height: h), angle: 90)
        let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [NSColor(rgb: (1, 0.96, 0.88)).cgColor, NSColor(white: 0, alpha: 0).cgColor] as CFArray, locations: [0, 1])!
        ctx.drawRadialGradient(g, startCenter: CGPoint(x: w * 0.3, y: h * 0.42), startRadius: 0, endCenter: CGPoint(x: w * 0.3, y: h * 0.42), endRadius: w * 0.16, options: [])
    }

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

    private static func round<G: SCNGeometry>(_ g: G) -> G {
        if let c = g as? SCNCylinder { c.radialSegmentCount = 48 }
        if let c = g as? SCNCone { c.radialSegmentCount = 48 }
        if let t = g as? SCNTube { t.radialSegmentCount = 48 }
        if let s = g as? SCNSphere { s.segmentCount = 16 }
        return g
    }

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
        static let families: [UInt64] = [21, 31, 41]
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
        static func hull(seed: UInt64) -> SCNMaterial {
            let m = plated(seed: seed)
            m.metalness.contents = NSColor(white: 0.03, alpha: 1)
            m.diffuse.intensity = 1.75
            return m
        }
        static let metal = skin(nil, color: NSColor(rgb: (0.62, 0.64, 0.68)), shine: 0.7)
        static let dark = skin(nil, color: NSColor(rgb: (0.16, 0.16, 0.18)), shine: 0.25)
        static let bell = skin(Textures.bell, shine: 0.45)
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
            color.values = [NSColor(rgb: (1, 0.98, 0.94)), NSColor(rgb: (0.96, 0.92, 0.86)), NSColor(rgb: (0.78, 0.75, 0.72)), NSColor(rgb: (0.2, 0.2, 0.2))]
            color.keyTimes = [0, 0.25, 0.65, 1]
            ps.propertyControllers = [.color: SCNParticlePropertyController(animation: color)]
            let grow = CAKeyframeAnimation(); grow.values = [0.7, 1.8, 3.2]; grow.keyTimes = [0, 0.4, 1]
            ps.propertyControllers?[.size] = SCNParticlePropertyController(animation: grow)
            return ps
        }

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

enum Textures {
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

    struct Seeded { var s: UInt64; mutating func next() -> Double { s = s &* 6364136223846793005 &+ 1442695040888963407; return Double(s >> 11) / Double(1 << 53) } }

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
    static let bell = draw(256, 256) { ctx, w, h in
        NSGradient(colors: [NSColor(rgb: (0.32, 0.32, 0.35)), NSColor(rgb: (0.24, 0.2, 0.22)), NSColor(rgb: (0.1, 0.09, 0.1))])!
            .draw(in: NSRect(x: 0, y: 0, width: w, height: h), angle: 90)
        for i in 0..<12 { ctx.setFillColor(NSColor(white: 0, alpha: 0.18).cgColor); ctx.fill(CGRect(x: w * CGFloat(i) / 12, y: 0, width: 1.5, height: h)) }
    }
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
    static let glare = draw(64, 64) { ctx, w, h in
        let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [NSColor(white: 1, alpha: 1).cgColor, NSColor(rgb: (1, 0.96, 0.9)).withAlphaComponent(0.35).cgColor, NSColor(white: 0, alpha: 0).cgColor] as CFArray, locations: [0, 0.3, 1])!
        ctx.drawRadialGradient(g, startCenter: CGPoint(x: w / 2, y: h / 2), startRadius: 0, endCenter: CGPoint(x: w / 2, y: h / 2), endRadius: w / 2, options: [])
    }
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
    static let blueFlame = draw(128, 256) { ctx, w, h in
        NSGradient(colors: [NSColor(rgb: (0.75, 0.88, 1)), NSColor(rgb: (0.3, 0.5, 1)), NSColor(rgb: (0.08, 0.15, 0.45)), NSColor.black],
                   atLocations: [0, 0.25, 0.65, 1], colorSpace: .deviceRGB)!.draw(in: NSRect(x: 0, y: 0, width: w, height: h), angle: 90)
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
    static let plasma = draw(128, 128) { ctx, w, h in
        let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [NSColor(rgb: (1, 0.95, 0.88)).cgColor, NSColor(rgb: (1, 0.55, 0.4)).withAlphaComponent(0.6).cgColor, NSColor(white: 0, alpha: 0).cgColor] as CFArray, locations: [0, 0.35, 1])!
        ctx.drawRadialGradient(g, startCenter: CGPoint(x: w / 2, y: h / 2), startRadius: 0, endCenter: CGPoint(x: w / 2, y: h / 2), endRadius: w / 2, options: [])
    }
    static let puff = draw(64, 64) { ctx, w, h in
        var r = Seeded(s: 17)
        for _ in 0..<18 {
            let cx = w * (0.3 + r.next() * 0.4), cy = h * (0.3 + r.next() * 0.4), rad = w * (0.12 + r.next() * 0.18)
            let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [NSColor(white: 1, alpha: 0.35).cgColor, NSColor(white: 1, alpha: 0).cgColor] as CFArray, locations: [0, 1])!
            ctx.drawRadialGradient(g, startCenter: CGPoint(x: cx, y: cy), startRadius: 0, endCenter: CGPoint(x: cx, y: cy), endRadius: rad, options: [])
        }
    }
}
