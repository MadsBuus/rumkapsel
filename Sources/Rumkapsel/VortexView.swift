// A release leaving the hall, as the scene draws it: the field across the pad wall, and while a release goes
// out, the vortex from the drones' ring to the rocket's hatch with the crates spiralling along it. Where every
// crate is comes from `Vortex.place`, on the station clock; this only draws it and ripples the field where a
// crate goes through.

import AppKit
import SceneKit

/// The nodes for one release going out: the swirl of light along the vortex, and the crates, by crate key.
final class VortexView {
    let node = SCNNode()
    var motes: [SCNNode] = []
    var crates: [String: SCNNode] = [:]
    /// Each crate's side of the field last frame, so a crossing ripples it once.
    var outside: [String: Bool] = [:]
}

extension Props {
    /// One mote of the vortex's swirl: a small glowing chip.
    static func vortexMote() -> SCNNode {
        let n = SCNNode(geometry: SCNBox(width: 0.045, height: 0.045, length: 0.045, chamferRadius: 0))
        n.geometry!.firstMaterial = Props.glowing(fieldBlue, alpha: 0.9)
        n.castsShadow = false
        return n
    }
}

extension StationController {
    /// The field across the hall's pad wall: the same sheet the ships fly through at the bay, holding the air in.
    func buildPadField(_ station: Station) -> SCNNode? {
        padFields[station.name] = nil
        guard let field = station.padField else { return nil }
        let width = field.to.x - field.from.x
        let built = Props.hangarField(width: width)
        let x = station.offset.x + (field.from.x + field.to.x) / 2, z = station.offset.y + field.from.y
        built.node.position = v3(x, 0, z)
        built.node.name = "station:" + station.name
        staticRoot.addChildNode(built.node)
        padFields[station.name] = HangarField(node: built.node, sheet: built.sheet, z: z, x0: x - width / 2, x1: x + width / 2)
        return built.node
    }

    /// One frame of every release going out, and of the pad fields: the swirl turns, each crate is where its
    /// path puts it, and a crate going through the field ripples it.
    func drawVortices() {
        for (name, field) in padFields {
            let drift = CGFloat(clock * 0.12).truncatingRemainder(dividingBy: 1)
            field.sheet.geometry?.firstMaterial?.diffuse.contentsTransform = SCNMatrix4MakeTranslation(0, drift, 0)
            let pulling = simulation.vortices.values.contains { $0.station == name && $0.closedAt == nil }
            let glow = max(0, 1 - (clock - field.struck) / 1.2)
            field.sheet.opacity = CGFloat(0.3 + (pulling ? 0.12 : 0) + 0.4 * glow + 0.05 * sin(clock * 1.7))
            for (i, r) in field.ripples.enumerated().reversed() {
                let age = (clock - r.born) / 1.1
                guard age < 1 else { r.node.removeFromParentNode(); field.ripples.remove(at: i); continue }
                let s = CGFloat(0.2 + 1.2 * age)
                r.node.scale = SCNVector3(s, s, 1)
                r.node.opacity = CGFloat((1 - age) * (1 - age))
            }
        }
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

    /// The swirl: motes streaming from the ring to the hatch on a narrowing spiral, as strong as the vortex is.
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

    /// The crates of the release: on their tiles until their turn, then where their path puts them, rippling the
    /// field as they go through it, and gone into the hold at the end.
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
        let n = looseCrate(crate)
        propRoot.addChildNode(n)
        view.crates[crate.key] = n
        return n
    }
}
