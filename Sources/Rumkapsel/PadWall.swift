// The hall's pad wall as the scene draws it: the field across it, which holds the air in and which a release is
// pulled out through (`VortexView.swift`); and out on the pad the drones and their rack. The drones' flights are
// the simulation's (`Drones.swift`); this draws them, on the station clock.

import AppKit
import SceneKit

final class DroneView {
    let node: SCNNode
    let clawL: SCNNode?, clawR: SCNNode?, strobe: SCNNode?, torch: SCNNode?, eye: SCNNode?
    /// The thrusters' nozzles, for the puffs.
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

/// A puff of cold gas from a thruster or a vent: it spreads, drifts and is gone, on the station clock.
struct Puff {
    let node: SCNNode
    let vel: SIMD3<Double>
    let born: Double, life: Double, grow: Double
}

extension Props {
    /// A crate's plate lit when it passed QA.
    static let passedLight = NSColor(rgb: (0.45, 0.95, 0.5))
    static let scanRed = NSColor(rgb: (1.0, 0.22, 0.2))
    /// The drones' eyes at rest.
    static let scanIdle = NSColor(rgb: (0.35, 0.75, 0.95))
    /// The amber of a light that says something is under way.
    static let gateIdle = NSColor(rgb: (0.95, 0.7, 0.15))
    static let hazard = NSColor(rgb: (0.95, 0.7, 0.15))

    /// Light that adds to what is behind it: a field's sheet, a torch's glow.
    static func glowing(_ color: NSColor, alpha: CGFloat) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = color.withAlphaComponent(alpha)
        m.blendMode = .add
        m.writesToDepthBuffer = false
        m.isDoubleSided = true
        return m
    }

    /// Glass: a faint blue you see through, with a sheen.
    static func glass(alpha: CGFloat = 0.22) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .blinn
        m.diffuse.contents = NSColor(rgb: (0.55, 0.78, 0.95)).withAlphaComponent(alpha)
        m.specular.contents = NSColor(white: 0.5, alpha: 1)
        m.shininess = 0.9
        m.transparencyMode = .dualLayer
        m.writesToDepthBuffer = false
        m.isDoubleSided = true
        return m
    }

    private static func block(_ w: Double, _ h: Double, _ l: Double, _ m: SCNMaterial, at p: SCNVector3, in parent: SCNNode, name: String? = nil) -> SCNNode {
        let b = SCNNode(geometry: SCNBox(width: w, height: h, length: l, chamferRadius: 0))
        b.geometry!.firstMaterial = m
        b.position = p
        b.name = name
        parent.addChildNode(b)
        return b
    }

    /// The drones' rack: a low plinth along x with a cradle per berth, a light at each that the scene lights green
    /// while its drone is home ("berth0", "berth1", ...).
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

    /// A drone, nose to +z, its middle at the origin: a flat body with a hazard band, four thruster pods out on
    /// struts with their nozzles ("nozzle") under them, a sensor strip for an eye ("eye"), red and green running
    /// lights, a white strobe on top ("strobe"), two claws under it that close on a crate ("clawL", "clawR"), and a
    /// torch at the nose for welding ("torch"). No round parts: every face is flat.
    static func padDrone() -> SCNNode {
        let n = SCNNode()
        let shell = lit(NSColor(rgb: (0.86, 0.87, 0.9))), dark = lit(NSColor(rgb: (0.2, 0.21, 0.25)))
        let steel = lit(NSColor(rgb: (0.55, 0.57, 0.62)))
        _ = block(0.17, 0.045, 0.13, shell, at: v3(0, 0, 0), in: n)
        _ = block(0.174, 0.015, 0.134, flat(hazard), at: v3(0, -0.012, 0), in: n)
        _ = block(0.09, 0.03, 0.07, dark, at: v3(0, 0.035, -0.01), in: n)
        let eye = block(0.1, 0.016, 0.01, flat(scanIdle), at: v3(0, 0.004, 0.068), in: n, name: "eye")
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

    /// A puff of gas: a small pale block that the scene spreads and fades.
    static func puff() -> SCNNode {
        let p = SCNNode(geometry: SCNBox(width: 0.018, height: 0.018, length: 0.018, chamferRadius: 0))
        p.geometry!.firstMaterial = Props.glowing(NSColor(white: 0.95, alpha: 1), alpha: 0.32)
        p.castsShadow = false
        p.eulerAngles = SCNVector3(Double.random(in: 0...1), Double.random(in: 0...1), 0)
        return p
    }
}

extension StationController {
    /// The hall's pad wall for a station, built with the static floor: the field across it, and the drones' rack
    /// out on the pad. Nothing where the station has no pad.
    func buildPadWall(_ station: Station) {
        droneRacks[station.name]?.removeFromParentNode()
        droneRacks[station.name] = nil
        _ = buildPadField(station)
        if let r = simulation.rack(station) {
            let n = Props.droneRack(count: DroneFlight.count, pitch: DroneFlight.berthPitch)
            n.position = v3(station.offset.x + r.at.x, 0, station.offset.y + r.at.y)
            n.eulerAngles.y = CGFloat(atan2(-r.along.y, r.along.x))
            n.name = "station:" + station.name
            staticRoot.addChildNode(n)
            droneRacks[station.name] = n
        }
    }

    /// A crate drawn on its own, off the rows: the same as the rows draw it.
    func looseCrate(_ crate: CrateRef) -> SCNNode {
        let row = fleet.stations[crate.station]?.ledger[crate.repo, crate.number]
        let alien = row?.alien == true
        let color = alien ? Palette.alien.darker(0.3) : NSColor(fleet.color(forRepo: crate.repo))
        let words = crateWords(repo: crate.repo, number: crate.number)
        return Props.package(color: color, band: NSColor(rgb: (0.3, 0.32, 0.38)), size: 0.38,
                             mine: !alien && world.isMine(repo: crate.repo, number: crate.number), number: crate.number,
                             title: words.title, who: words.who)
    }

    // MARK: the drones

    /// Every drone where the simulation has it: bobbing a little in the air, tilting into its thrust, its claws
    /// shut on what it holds and the crate under them, its strobe blinking, the torch lit at a seam, and a puff
    /// from the nozzles opposite each push. The rack's lights say who is home.
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
                // Leaning into the push, the way a hovering thing does, and back level when it holds still.
                let push = SIMD2(d.push.x, d.push.z)
                let local = SIMD2(push.x * cos(d.yaw) - push.y * sin(d.yaw), push.x * sin(d.yaw) + push.y * cos(d.yaw))
                let pitch = max(-0.35, min(0.35, local.y * 0.09)), roll = max(-0.35, min(0.35, -local.x * 0.09))
                v.node.eulerAngles = SCNVector3(CGFloat(pitch), CGFloat(d.yaw), CGFloat(roll))
                v.clawL?.eulerAngles.z = -0.5
                v.clawR?.eulerAngles.z = 0.5
                v.strobe?.isHidden = resting || clock.truncatingRemainder(dividingBy: 1.2) > 0.08
                v.eye?.geometry?.firstMaterial?.diffuse.contents = d.torch ? NSColor(rgb: (1.0, 0.75, 0.3)) : Props.scanIdle
                // The torch at a seam: its tip lit, the lamp on the panel, sparks off the hull.
                v.torch?.isHidden = !d.torch
                if d.torch, case .weld(let key) = d.task, let r = simulation.rockets[key], let seam = seamPoint(r) {
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
                // Cold gas from the nozzles away from the push, more the harder it pushes.
                let strength = simd_length(d.push)
                if strength > 0.6, Double.random(in: 0...1) < min(0.5, strength * 0.08) {
                    let away = -d.push / strength
                    for nozzle in v.pods.shuffled().prefix(1) {
                        let at = nozzle.convertPosition(SCNVector3Zero, to: propRoot)
                        emitPuff(at: SIMD3(Double(at.x), Double(at.y), Double(at.z)), vel: away * 0.6 + SIMD3(0, -0.1, 0), life: 0.35, grow: 1.8)
                    }
                }
            }
            // The rack's lights: green over a drone at home, amber over one out at work.
            if let rack = droneRacks[name] {
                for d in list {
                    rack.childNode(withName: "berth\(d.berth)", recursively: false)?.geometry?.firstMaterial?.diffuse.contents =
                        d.task == .rest ? NSColor(rgb: (0.3, 0.9, 0.45)) : (clock.truncatingRemainder(dividingBy: 1) < 0.5 ? Props.gateIdle : Props.gateIdle.darker(0.5))
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
