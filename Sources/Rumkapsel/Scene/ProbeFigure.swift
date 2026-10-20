import AppKit
import SceneKit

extension Probe {
    static func hover(clock: Double, phase: Double) -> Double { 0.24 + 0.025 * sin(clock * 2.6 + phase) }

    static func build() -> SCNNode {
        let probe = SCNNode()
        func box(_ w: Double, _ h: Double, _ d: Double, _ m: SCNMaterial, _ at: SCNVector3, chamfer: Double = 0) -> SCNNode {
            let n = SCNNode(geometry: SCNBox(width: w, height: h, length: d, chamferRadius: chamfer))
            n.geometry!.firstMaterial = m
            n.position = at
            probe.addChildNode(n)
            return n
        }
        let shell = lit(Palette.minion), dark = lit(NSColor(rgb: (0.22, 0.23, 0.28)))
        box(0.15, 0.11, 0.13, shell, SCNVector3Zero, chamfer: 0.025)
        box(0.1, 0.035, 0.012, dark, v3(0, 0.005, 0.066))
        let eye = box(0.034, 0.022, 0.006, flat(Palette.core), v3(0, 0.005, 0.074))
        eye.name = "eye"
        box(0.155, 0.016, 0.135, lit(NSColor.white), v3(0, 0.04, 0), chamfer: 0.004).name = "stripe"
        for side in [-1.0, 1.0] {
            box(0.03, 0.05, 0.07, dark, v3(side * 0.09, -0.01, -0.01), chamfer: 0.008)
            let glow = box(0.024, 0.006, 0.05, Props.glowing(Palette.core, alpha: 0.7), v3(side * 0.09, -0.04, -0.01))
            glow.name = "jet"
        }
        box(0.008, 0.06, 0.008, dark, v3(0.04, 0.085, -0.03))
        box(0.018, 0.018, 0.018, flat(Palette.core), v3(0.04, 0.118, -0.03)).name = "tip"

        let fan = SCNNode(geometry: fanGeometry())
        fan.geometry!.firstMaterial = Props.glowing(Palette.core, alpha: 0.45)
        fan.position = v3(0, 0.005, 0.075)
        fan.name = "fan"
        fan.isHidden = true
        probe.addChildNode(fan)

        let shard = SCNNode(geometry: SCNPyramid(width: 0.04, height: 0.035, length: 0.04))
        shard.geometry!.firstMaterial = Props.glowing(Palette.core, alpha: 0.95)
        let under = SCNNode(geometry: shard.geometry)
        under.eulerAngles.x = .pi
        shard.addChildNode(under)
        shard.position = v3(0, -0.09, 0.03)
        shard.name = "shard"
        shard.isHidden = true
        probe.addChildNode(shard)
        return probe
    }

    private static func fanGeometry() -> SCNGeometry {
        let v: [SCNVector3] = [v3(0, 0, 0), v3(-0.16, -0.36, 0.34), v3(0.16, -0.36, 0.34)]
        let source = SCNGeometrySource(vertices: v)
        let element = SCNGeometryElement(indices: [Int32(0), 1, 2, 0, 2, 1], primitiveType: .triangles)
        return SCNGeometry(sources: [source], elements: [element])
    }

    static func show(_ body: SCNNode, scanning: Bool, carrying: Bool, clock: Double, phase: Double) {
        if let fan = body.childNode(withName: "fan", recursively: true) {
            fan.isHidden = !scanning
            fan.eulerAngles.y = CGFloat(sin(clock * 1.7 + phase) * 0.55)
            fan.opacity = CGFloat(0.7 + 0.3 * sin(clock * 9 + phase))
        }
        if let shard = body.childNode(withName: "shard", recursively: true) {
            shard.isHidden = !carrying
            shard.eulerAngles.y = CGFloat(clock * 3)
        }
        body.enumerateChildNodes { n, _ in
            if n.name == "jet" { n.opacity = CGFloat(0.55 + 0.45 * sin(clock * 23 + phase * 3)) }
        }
    }
}
