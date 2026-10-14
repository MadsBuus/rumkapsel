import AppKit
import SceneKit

final class VortexView {
    let node = SCNNode()
    var motes: [SCNNode] = []
    var crates: [String: SCNNode] = [:]
    var outside: [String: Bool] = [:]
}

extension Props {
    static func vortexMote() -> SCNNode {
        let n = SCNNode(geometry: SCNBox(width: 0.045, height: 0.045, length: 0.045, chamferRadius: 0))
        n.geometry!.firstMaterial = Props.glowing(fieldBlue, alpha: 0.9)
        n.castsShadow = false
        return n
    }
}

extension StationController {
    func drawVortices() {
        for (key, view) in vortexViews where simulation.vortices[key] == nil {
            view.node.removeFromParentNode()
            for n in view.crates.values { n.removeFromParentNode() }
            vortexViews[key] = nil
        }
        for (key, v) in simulation.vortices {
            guard let hatch = simulation.vortexHatch(v) else { continue }
            let view = vortexViews[key] ?? {
                let made = VortexView()
                for _ in 0..<36 { let m = Props.vortexMote(); made.motes.append(m); made.node.addChildNode(m) }
                propRoot.addChildNode(made.node)
                vortexViews[key] = made
                return made
            }()
            drawSwirl(view, v, hatch: hatch)
            drawPulled(view, v, hatch: hatch)
        }
    }

    private func drawSwirl(_ view: VortexView, _ v: Vortex, hatch: SIMD3<Double>) {
        let strength = v.strength(at: clock)
        let axis = hatch - v.ring
        let along = simd_length(axis) > 1e-6 ? simd_normalize(axis) : SIMD3(0, 0, -1)
        let side = simd_normalize(simd_cross(along, SIMD3(0, 1, 0)) + SIMD3(0, 1e-6, 0))
        let lift = simd_cross(side, along)
        for (i, m) in view.motes.enumerated() {
            let s = (Double(i) / Double(view.motes.count) + clock * 0.32).truncatingRemainder(dividingBy: 1)
            let angle = s * 5 * .pi + clock * 2.4 + Double(i % 3) * 2 * .pi / 3
            let r = Vortex.radius * (1 - s) + 0.04
            let p = v.ring + axis * s + side * (cos(angle) * r) + lift * (sin(angle) * r)
            m.position = v3(p.x, p.y, p.z)
            m.opacity = CGFloat(strength * (0.25 + 0.75 * sin(s * .pi)))
            let k = CGFloat(1 - 0.6 * s)
            m.scale = SCNVector3(k, k, k)
        }
    }

    private func drawPulled(_ view: VortexView, _ v: Vortex, hatch: SIMD3<Double>) {
        let field = padFields[v.station]
        var live = Set<String>()
        for c in v.waiting {
            live.insert(c.crate.key)
            let n = pulledNode(view, c.crate)
            n.position = v3(c.from.pos.x, c.from.pos.y, c.from.pos.z)
            n.eulerAngles.y = CGFloat(c.from.yaw)
        }
        for f in v.flying {
            live.insert(f.crate.key)
            let n = pulledNode(view, f.crate)
            guard let at = Vortex.place(from: f.from.pos, ring: v.ring, hatch: hatch, leftAt: f.at, at: clock) else { n.isHidden = true; continue }
            n.isHidden = false
            n.position = v3(at.pos.x, at.pos.y, at.pos.z)
            n.scale = SCNVector3(at.scale, at.scale, at.scale)
            n.eulerAngles.y = CGFloat(f.from.yaw + max(0, clock - f.at - Vortex.liftSeconds) * 3)
            if let field {
                let out = at.pos.z < field.z
                if let was = view.outside[f.crate.key], was != out {
                    let ripple = Props.fieldRipple()
                    ripple.position = v3(at.pos.x - Double(field.node.position.x), at.pos.y, 0.01)
                    field.node.addChildNode(ripple)
                    field.ripples.append((ripple, clock))
                    field.struck = clock
                    drone.ping(seed: 9)
                }
                view.outside[f.crate.key] = out
            }
        }
        for (k, n) in view.crates where !live.contains(k) {
            n.removeFromParentNode()
            view.crates[k] = nil
        }
    }

    private func pulledNode(_ view: VortexView, _ crate: CrateRef) -> SCNNode {
        if let n = view.crates[crate.key] { return n }
        let n = crateNodes[crate.key] ?? looseCrate(crate)
        stopCrate(n)
        n.removeFromParentNode()
        propRoot.addChildNode(n)
        view.crates[crate.key] = n
        return n
    }
}
