import AppKit
import SceneKit

final class DroneView {
    let node: SCNNode
    let clawL: SCNNode?, clawR: SCNNode?, strobe: SCNNode?, torch: SCNNode?, eye: SCNNode?
    var pods: [SCNNode] = []
    var lamp: SCNNode?
    var grip = 0.0
    init(node: SCNNode) {
        self.node = node
        clawL = node.childNode(withName: "clawL", recursively: true)
        clawR = node.childNode(withName: "clawR", recursively: true)
        strobe = node.childNode(withName: "strobe", recursively: true)
        torch = node.childNode(withName: "torch", recursively: true)
        eye = node.childNode(withName: "eye", recursively: true)
        node.enumerateChildNodes { c, _ in if c.name == "nozzle" { pods.append(c) } }
    }
}

struct Puff {
    let node: SCNNode
    let vel: SIMD3<Double>
    let born: Double, life: Double, grow: Double
}

extension Props {
    private static func block(_ w: Double, _ h: Double, _ l: Double, _ m: SCNMaterial, at p: SCNVector3, in parent: SCNNode, name: String? = nil) -> SCNNode {
        let b = SCNNode(geometry: SCNBox(width: w, height: h, length: l, chamferRadius: 0))
        b.geometry!.firstMaterial = m
        b.position = p
        b.name = name
        parent.addChildNode(b)
        return b
    }

    static func droneRack(count: Int, pitch: Double) -> SCNNode {
        let n = SCNNode()
        let dark = lit(NSColor(rgb: (0.2, 0.21, 0.25))), steel = lit(NSColor(rgb: (0.55, 0.57, 0.62)))
        let length = Double(count) * pitch + 0.06
        _ = block(length, 0.1, 0.3, dark, at: v3(0, 0.05, 0), in: n)
        _ = block(length + 0.004, 0.025, 0.304, flat(hazard), at: v3(0, 0.085, 0), in: n)
        for k in 0..<count {
            let x = (Double(k) - Double(count - 1) / 2) * pitch
            for dz in [-0.07, 0.07] { _ = block(0.18, 0.04, 0.025, steel, at: v3(x, 0.12, dz), in: n) }
            let light = block(0.05, 0.02, 0.05, flat(NSColor(rgb: (0.3, 0.9, 0.45))), at: v3(x, 0.105, 0.13), in: n, name: "berth\(k)")
            light.castsShadow = false
        }
        return n
    }

    static func padDrone() -> SCNNode {
        let n = SCNNode()
        let shell = lit(NSColor(rgb: (0.86, 0.87, 0.9))), dark = lit(NSColor(rgb: (0.2, 0.21, 0.25)))
        let steel = lit(NSColor(rgb: (0.55, 0.57, 0.62)))
        _ = block(0.17, 0.045, 0.13, shell, at: v3(0, 0, 0), in: n)
        _ = block(0.174, 0.015, 0.134, flat(hazard), at: v3(0, -0.012, 0), in: n)
        _ = block(0.09, 0.03, 0.07, dark, at: v3(0, 0.035, -0.01), in: n)
        let eye = block(0.1, 0.016, 0.01, flat(droneEye), at: v3(0, 0.004, 0.068), in: n, name: "eye")
        eye.castsShadow = false
        for (x, z) in [(-1.0, -1.0), (1.0, -1.0), (-1.0, 1.0), (1.0, 1.0)] {
            let strut = block(0.07, 0.014, 0.014, steel, at: v3(x * 0.1, 0.005, z * 0.06), in: n)
            strut.eulerAngles.y = CGFloat(x * z * 0.6)
            _ = block(0.055, 0.04, 0.055, dark, at: v3(x * 0.14, 0.008, z * 0.09), in: n)
            let nozzle = block(0.034, 0.018, 0.034, lit(NSColor(rgb: (0.1, 0.1, 0.12))), at: v3(x * 0.14, -0.02, z * 0.09), in: n, name: "nozzle")
            nozzle.castsShadow = false
        }
        let red = block(0.012, 0.012, 0.03, flat(NSColor(rgb: (1.0, 0.2, 0.2))), at: v3(-0.172, 0.01, 0.09), in: n)
        let green = block(0.012, 0.012, 0.03, flat(NSColor(rgb: (0.25, 1.0, 0.4))), at: v3(0.172, 0.01, 0.09), in: n)
        red.castsShadow = false; green.castsShadow = false
        let strobe = block(0.018, 0.012, 0.018, flat(.white), at: v3(0, 0.056, -0.01), in: n, name: "strobe")
        strobe.castsShadow = false
        for (name, x) in [("clawL", -1.0), ("clawR", 1.0)] {
            let pivot = SCNNode()
            pivot.name = name
            pivot.position = v3(x * 0.05, -0.025, 0)
            _ = block(0.012, 0.06, 0.07, steel, at: v3(0, -0.03, 0), in: pivot)
            _ = block(0.03, 0.01, 0.07, steel, at: v3(-x * 0.012, -0.058, 0), in: pivot)
            n.addChildNode(pivot)
        }
        let torch = SCNNode()
        torch.name = "torch"
        torch.position = v3(0, -0.005, 0.07)
        _ = block(0.014, 0.014, 0.07, steel, at: v3(0, 0, 0.035), in: torch)
        let tip = block(0.02, 0.02, 0.02, Props.glowing(NSColor(rgb: (1.0, 0.85, 0.55)), alpha: 0.9), at: v3(0, 0, 0.075), in: torch, name: "tip")
        tip.castsShadow = false
        torch.isHidden = true
        n.addChildNode(torch)
        return n
    }

    static func puff() -> SCNNode {
        let p = SCNNode(geometry: SCNBox(width: 0.018, height: 0.018, length: 0.018, chamferRadius: 0))
        p.geometry!.firstMaterial = Props.glowing(NSColor(white: 0.95, alpha: 1), alpha: 0.32)
        p.castsShadow = false
        p.eulerAngles = SCNVector3(Double.random(in: 0...1), Double.random(in: 0...1), 0)
        return p
    }
}

extension StationController {
    // MARK: the drones

    func drawDrones(dt: Double) {
        var seen = Set<String>()
        for (name, list) in simulation.drones {
            guard let station = fleet.stations[name] else { continue }
            for d in list {
                seen.insert(d.id)
                let v = droneViews[d.id] ?? {
                    let n = Looks.current.padDrone() ?? Props.padDrone()
                    n.name = "drone:" + name
                    propRoot.addChildNode(n)
                    let v = DroneView(node: n)
                    droneViews[d.id] = v
                    return v
                }()
                let resting = d.task == .rest
                let phase = Double(d.berth) * 1.7
                let bob = resting ? 0 : sin(clock * 3.1 + phase) * 0.012
                v.node.position = v3(d.pos.x, d.pos.y + bob, d.pos.z)
                let push = SIMD2(d.push.x, d.push.z)
                let local = SIMD2(push.x * cos(d.yaw) - push.y * sin(d.yaw), push.x * sin(d.yaw) + push.y * cos(d.yaw))
                let pitch = max(-0.35, min(0.35, local.y * 0.09)), roll = max(-0.35, min(0.35, -local.x * 0.09))
                v.node.eulerAngles = SCNVector3(CGFloat(pitch), CGFloat(d.yaw), CGFloat(roll))
                v.clawL?.eulerAngles.z = -0.5
                v.clawR?.eulerAngles.z = 0.5
                v.strobe?.isHidden = resting || clock.truncatingRemainder(dividingBy: 1.2) > 0.08
                v.eye?.geometry?.firstMaterial?.diffuse.contents = d.torch ? NSColor(rgb: (1.0, 0.75, 0.3)) : Props.droneEye
                v.torch?.isHidden = !d.torch
                if d.torch, case .weld(let key) = d.task, let seam = seamPoint(key, panel: d.seam) {
                    let lamp = v.lamp ?? {
                        let l = Props.weldLamp()
                        propRoot.addChildNode(l)
                        v.lamp = l
                        return l
                    }()
                    let on = Double.random(in: 0...1) < 0.7
                    lamp.position = seam
                    lamp.light?.intensity = on ? CGFloat(Double.random(in: 300...1200)) : 0
                    lamp.opacity = on ? 1 : 0
                    if on, Looks.current.workSparks, let rocket = rocketViews[key]?.node { throwSparks(at: seam, from: rocket, count: Int.random(in: 0...2)) }
                } else if let l = v.lamp {
                    l.removeFromParentNode()
                    v.lamp = nil
                }
                let strength = simd_length(d.push)
                if strength > 0.6, Double.random(in: 0...1) < min(0.5, strength * 0.08) {
                    let away = -d.push / strength
                    for nozzle in v.pods.shuffled().prefix(1) {
                        let at = nozzle.convertPosition(SCNVector3Zero, to: propRoot)
                        emitPuff(at: SIMD3(Double(at.x), Double(at.y), Double(at.z)), vel: away * 0.6 + SIMD3(0, -0.1, 0), life: 0.35, grow: 1.8)
                    }
                }
            }
            if let rack = droneRacks[name] {
                for d in list {
                    rack.childNode(withName: "berth\(d.berth)", recursively: false)?.geometry?.firstMaterial?.diffuse.contents =
                        d.task == .rest ? NSColor(rgb: (0.3, 0.9, 0.45)) : (clock.truncatingRemainder(dividingBy: 1) < 0.5 ? Props.waitingAmber : Props.waitingAmber.darker(0.5))
                }
            }
            _ = station
        }
        for (id, v) in droneViews where !seen.contains(id) {
            v.node.removeFromParentNode()
            v.lamp?.removeFromParentNode()
            droneViews[id] = nil
        }
    }

    // MARK: puffs

    func emitPuff(at p: SIMD3<Double>, vel: SIMD3<Double>, life: Double, grow: Double) {
        guard puffs.count < 120 else { return }
        let n = Props.puff()
        n.position = v3(p.x, p.y, p.z)
        propRoot.addChildNode(n)
        puffs.append(Puff(node: n, vel: vel, born: clock, life: life, grow: grow))
    }

    func tickPuffs(dt: Double) {
        for (i, p) in puffs.enumerated().reversed() {
            let age = (clock - p.born) / p.life
            guard age < 1 else { p.node.removeFromParentNode(); puffs.remove(at: i); continue }
            let k = 1 - age * 0.6
            p.node.position = SCNVector3(p.node.position.x + CGFloat(p.vel.x * dt * k), p.node.position.y + CGFloat(p.vel.y * dt * k),
                                         p.node.position.z + CGFloat(p.vel.z * dt * k))
            let s = CGFloat(1 + p.grow * age)
            p.node.scale = SCNVector3(s, s, s)
            p.node.opacity = CGFloat((1 - age) * (1 - age))
        }
    }
}
