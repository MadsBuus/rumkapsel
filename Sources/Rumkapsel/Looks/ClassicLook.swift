// The classic look: flat shading adrift in space, the homage the station started as. These pieces were
// drawn inline in the scene before there were looks, and are moved here as they were.

import AppKit
import SceneKit

struct ClassicLook: Look {
    var background: NSColor { Palette.void }
    var viewYaw: Double { .pi / 4 }
    var floorTop: Double { 0 }
    var dotsHallway: Bool { true }
    var drawsBorders: Bool { true }

    /// Flakes of debris drifting, a far star field and a few nebulae.
    func backdrop(into root: SCNNode) -> [(SCNNode, SIMD2<Double>)] {
        var drifting: [(SCNNode, SIMD2<Double>)] = []
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
            drifting.append((n, SIMD2(Double.random(in: -0.12...0.12), Double.random(in: -0.12...0.12))))
        }
        // A far, still star field: one point-cloud geometry, faint and small.
        var stars: [SCNVector3] = []
        var starColors: [SCNVector4] = []
        for _ in 0..<700 {
            stars.append(v3(Double.random(in: -90...90), -12, Double.random(in: -90...90)))
            let b = Double.random(in: 0.25...0.7)
            starColors.append(SCNVector4(0.8 * b, 0.85 * b, 1.0 * b, 1))
        }
        let starSource = SCNGeometrySource(vertices: stars)
        let colorData = Data(bytes: starColors, count: starColors.count * MemoryLayout<SCNVector4>.stride)
        let colorSource = SCNGeometrySource(data: colorData, semantic: .color, vectorCount: starColors.count, usesFloatComponents: true,
                                            componentsPerVector: 4, bytesPerComponent: MemoryLayout<CGFloat>.size, dataOffset: 0, dataStride: MemoryLayout<SCNVector4>.stride)
        let indices = (0..<stars.count).map { Int32($0) }
        let element = SCNGeometryElement(indices: indices, primitiveType: .point)
        element.pointSize = 1.2
        element.minimumPointScreenSpaceRadius = 0.6
        element.maximumPointScreenSpaceRadius = 1.6
        let starGeometry = SCNGeometry(sources: [starSource, colorSource], elements: [element])
        let starMaterial = SCNMaterial()
        starMaterial.lightingModel = .constant
        starMaterial.diffuse.contents = NSColor.white
        starMaterial.blendMode = .add
        starGeometry.firstMaterial = starMaterial
        root.addChildNode(SCNNode(geometry: starGeometry))

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
            root.addChildNode(cluster)
            drifting.append((cluster, SIMD2(Double.random(in: -0.08...0.08), Double.random(in: -0.08...0.08))))
        }
        return drifting
    }

    func ground(under stations: [Station], into root: SCNNode) {}

    func floorColor(_ color: NSColor, floor: Floor) -> NSColor { color }

    func tileDetail(floor: Floor, open: Set<Int>, walled: [Int: Floor], color: NSColor) -> SCNNode? { nil }

    func tint(tile: SCNNode, _ color: NSColor) {
        tile.geometry?.firstMaterial?.diffuse.contents = color
    }

    /// A lintel across the posts.
    func airlockFrame(width: Double, spans: [Double], tint: NSColor) -> (node: SCNNode, showsPosts: Bool) {
        let lintel = SCNNode(geometry: SCNBox(width: width + 0.08, height: 0.08, length: 0.08, chamferRadius: 0))
        lintel.geometry!.firstMaterial = lit(tint)
        lintel.position = v3(0, 0.74, 0)
        return (lintel, true)
    }

    /// Two posts and a lintel.
    func hatchFrame(facing: SIMD2<Double>) -> (node: SCNNode, lightHeight: Double) {
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
    func monolith() -> SCNNode {
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

    func figure(id: String, crew: Bool, height: Double) -> SCNNode? { nil }

    func pose(figure: SCNNode, height: Double, torso: Double) {}

    /// The shuttle body, wings in a repo colour.
    func shuttle(color: NSColor) -> SCNNode {
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

    func rocket(color: NSColor, tall: Bool, cargo: Int) -> SCNNode {
        Props.rocket(color: color, tall: tall, cargo: cargo)
    }

    func shipPose(_ leg: ShipLeg) -> (pos: SIMD3<Double>, yaw: Double)? { nil }

    func dress(station: Station) -> [SCNNode] { [] }

    func dress(office room: Room, in station: Station) -> SCNNode? { nil }
}
