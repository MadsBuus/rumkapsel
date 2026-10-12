// The gate between the deck and the pad as the scene draws it: the cargo lock in one half, a chamber with a
// glass roof so the crate in it shows from above, a door on each side that rises out of the way, mist that drains
// as the air goes, a sheet of light that sweeps a crate bound out, and the X-ray of it on a screen over the deck
// door; the window in the other half, where the idle watch a rocket; and on the pad the drones and their rack.
// The lock's trips and the drones' flights are the simulation's (`CargoLock.swift`, `Drones.swift`); this draws
// them, on the station clock.

import AppKit
import SceneKit

/// The lock as the scene draws it, one per station.
final class LockView {
    let node: SCNNode
    let innerDoor: SCNNode?, outerDoor: SCNNode?
    /// The lights along the roof's edges, the mist inside, the scan's sheet, the screen and its sweep line, the vent.
    var lamps: [SCNNode] = []
    let mist: SCNNode?, scan: SCNNode?, screen: SCNNode?, sweep: SCNNode?, vent: SCNNode?
    /// Crates on the trays: on the inner bound out, on the outer bound in, by crate key; and the one in the chamber.
    var waiting: [String: SCNNode] = [:]
    var returning: [String: SCNNode] = [:]
    var moving: (key: String, node: SCNNode)?
    /// The picture on the screen, and the crate it is of.
    var showing = ""
    /// How much air is in the chamber as drawn, 0 to 1.
    var air = 1.0
    /// The window and the rack, built with the lock.
    let window: SCNNode?, rack: SCNNode?
    /// The way through, deck to pad.
    let inward: SIMD2<Double>
    /// Until when both doors stand open for a pod going through to its rocket.
    var passUntil = 0.0

    init(node: SCNNode, window: SCNNode?, rack: SCNNode?, inward: SIMD2<Double>) {
        self.node = node; self.window = window; self.rack = rack; self.inward = inward
        innerDoor = node.childNode(withName: "innerDoor", recursively: true)
        outerDoor = node.childNode(withName: "outerDoor", recursively: true)
        mist = node.childNode(withName: "mist", recursively: true)
        scan = node.childNode(withName: "scan", recursively: true)
        screen = node.childNode(withName: "screen", recursively: true)
        sweep = node.childNode(withName: "sweep", recursively: true)
        vent = node.childNode(withName: "vent", recursively: true)
        node.enumerateChildNodes { c, _ in if c.name == "lamp" { lamps.append(c) } }
    }
}

/// A drone as the scene draws it.
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
    /// A plate lit for a crate through the lock.
    static let passedLight = NSColor(rgb: (0.45, 0.95, 0.5))
    static let scanRed = NSColor(rgb: (1.0, 0.22, 0.2))
    static let scanIdle = NSColor(rgb: (0.35, 0.75, 0.95))
    /// The lock's lights at rest.
    static let gateIdle = NSColor(rgb: (0.95, 0.7, 0.15))
    static let hazard = NSColor(rgb: (0.95, 0.7, 0.15))

    /// Light that adds to what is behind it: a scan's sheet, a torch's glow.
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

    /// The cargo lock, in its own frame: x along the gate's line, z out onto the pad, standing on the origin in
    /// the chamber's middle. Two walls with a hazard band, a glass roof on a frame, a door at each end that the
    /// scene raises ("innerDoor" on the deck at -z, "outerDoor" on the pad at +z), lights along both roof edges
    /// ("lamp"), the chamber's "mist" and the scan's "sheet", a screen tilted up over the deck door ("screen",
    /// "sweep"), a "vent" on the pad side, and a roller tray before each door.
    static func cargoLock() -> SCNNode {
        let n = SCNNode()
        let w = CargoLock.halfWidth, d = CargoLock.halfDepth, h = CargoLock.height
        let shell = lit(NSColor(rgb: (0.8, 0.82, 0.86))), dark = lit(NSColor(rgb: (0.2, 0.21, 0.25)))
        let steel = lit(NSColor(rgb: (0.55, 0.57, 0.62))), stripe = flat(hazard)
        _ = block(2 * w + 0.1, 0.03, 2 * d, dark, at: v3(0, 0.015, 0), in: n)
        for side in [-1.0, 1.0] {
            _ = block(0.07, h, 2 * d + 0.06, shell, at: v3(side * (w + 0.035), h / 2, 0), in: n)
            _ = block(0.074, 0.05, 2 * d + 0.064, stripe, at: v3(side * (w + 0.035), 0.09, 0), in: n)
            // The door frames: a post either side of each door, standing proud of the walls.
            for end in [-1.0, 1.0] { _ = block(0.09, h + 0.04, 0.07, steel, at: v3(side * (w + 0.035), (h + 0.04) / 2, end * (d + 0.035)), in: n) }
        }
        // The roof: a frame round the glass.
        for end in [-1.0, 1.0] {
            _ = block(2 * w + 0.16, 0.06, 0.07, steel, at: v3(0, h + 0.01, end * (d + 0.035)), in: n)
            let lamp = block(2 * w - 0.1, 0.025, 0.035, flat(gateIdle), at: v3(0, h + 0.05, end * (d + 0.035)), in: n, name: "lamp")
            lamp.castsShadow = false
        }
        let glass = block(2 * w, 0.012, 2 * d, glass(alpha: 0.1), at: v3(0, h - 0.005, 0), in: n)
        glass.castsShadow = false
        for x in [-w / 3, w / 3] { _ = block(0.02, 0.02, 2 * d, steel, at: v3(x, h, 0), in: n) }
        // The doors, as tall as the opening, a chevron of hazard across each; raised by the scene.
        for (name, end) in [("innerDoor", -1.0), ("outerDoor", 1.0)] {
            let door = SCNNode()
            door.name = name
            door.position = v3(0, 0, end * (d + 0.035))
            _ = block(2 * w, h - 0.03, 0.04, dark, at: v3(0, (h - 0.03) / 2 + 0.03, 0), in: door)
            for k in 0..<4 {
                let chev = block(0.09, 0.03, 0.044, stripe, at: v3(-w + 0.12 + Double(k) * (2 * w - 0.24) / 3, h * 0.55, 0), in: door)
                chev.eulerAngles.z = k % 2 == 0 ? 0.5 : -0.5
            }
            _ = block(2 * w * 0.6, 0.05, 0.046, flat(NSColor(rgb: (0.1, 0.1, 0.12))), at: v3(0, h * 0.3, 0), in: door)
            n.addChildNode(door)
        }
        // The air in the chamber, which goes and comes as it cycles; and the scan's sheet of light.
        let mist = block(2 * w - 0.02, h - 0.06, 2 * d - 0.04, Props.glowing(NSColor(white: 0.85, alpha: 1), alpha: 0.09), at: v3(0, h / 2, 0), in: n, name: "mist")
        mist.castsShadow = false
        let sheet = SCNNode(geometry: SCNPlane(width: 2 * w - 0.02, height: h - 0.08))
        sheet.geometry!.firstMaterial = Props.glowing(scanIdle, alpha: 0.55)
        sheet.name = "scan"
        sheet.opacity = 0
        sheet.castsShadow = false
        sheet.position = v3(0, h / 2, 0)
        n.addChildNode(sheet)
        // The screen over the deck door, tilted up so it reads from above: the X-ray of a crate bound out.
        let mount = SCNNode()
        mount.position = v3(0, h + 0.06, -(d + 0.09))
        mount.eulerAngles.x = 1.0
        _ = block(0.46, 0.3, 0.03, dark, at: v3(0, 0, 0), in: mount)
        let screen = SCNNode(geometry: SCNPlane(width: 0.42, height: 0.26))
        let sm = SCNMaterial()
        sm.lightingModel = .constant
        sm.diffuse.contents = NSColor(rgb: (0.03, 0.07, 0.14))
        screen.geometry!.firstMaterial = sm
        screen.name = "screen"
        screen.position = v3(0, 0, -0.017)
        screen.eulerAngles.y = .pi
        mount.addChildNode(screen)
        let sweep = SCNNode(geometry: SCNPlane(width: 0.42, height: 0.01))
        sweep.geometry!.firstMaterial = flat(scanIdle)
        sweep.name = "sweep"
        sweep.opacity = 0
        sweep.position = v3(0, 0, -0.019)
        sweep.eulerAngles.y = .pi
        mount.addChildNode(sweep)
        n.addChildNode(mount)
        // The vent on the pad side, where the chamber's air goes out to space.
        let vent = block(0.14, 0.06, 0.03, dark, at: v3(w - 0.12, h * 0.8, d + 0.085), in: n, name: "vent")
        for k in 0..<3 { _ = block(0.12, 0.006, 0.034, steel, at: v3(0, -0.018 + Double(k) * 0.018, 0), in: vent) }
        // A roller tray before each door, at the trays' height.
        for end in [-1.0, 1.0] {
            let tray = SCNNode()
            tray.position = v3(0, 0, end * 0.78)
            _ = block(0.44, CargoLock.top - 0.03, 0.4, dark, at: v3(0, (CargoLock.top - 0.03) / 2, 0), in: tray)
            for k in 0..<5 { _ = block(0.42, 0.012, 0.03, steel, at: v3(0, CargoLock.top - 0.012, -0.16 + Double(k) * 0.08), in: tray) }
            _ = block(0.45, 0.03, 0.02, stripe, at: v3(0, CargoLock.top - 0.01, end * 0.2), in: tray)
            n.addChildNode(tray)
        }
        return n
    }

    /// The window across the rest of the gate, `width` along its x, standing on the origin: posts and a sill and
    /// a lintel round a pane of glass with a sheen across it.
    static func gateWindow(width: Double) -> SCNNode {
        let n = SCNNode()
        let h = CargoLock.height
        let steel = lit(NSColor(rgb: (0.55, 0.57, 0.62))), shell = lit(NSColor(rgb: (0.8, 0.82, 0.86)))
        _ = block(width, 0.16, 0.1, shell, at: v3(0, 0.08, 0), in: n)
        _ = block(width, 0.05, 0.1, steel, at: v3(0, h + 0.02, 0), in: n)
        let posts = max(2, Int((width / 0.5).rounded()) + 1)
        for k in 0..<posts {
            let x = -width / 2 + Double(k) * width / Double(posts - 1)
            _ = block(0.05, h, 0.09, steel, at: v3(x, h / 2, 0), in: n)
        }
        let pane = block(width - 0.04, h - 0.18, 0.012, glass(alpha: 0.18), at: v3(0, 0.16 + (h - 0.18) / 2, 0), in: n)
        pane.castsShadow = false
        // A streak of reflection across the glass.
        let sheen = SCNNode(geometry: SCNPlane(width: 0.07, height: h * 0.7))
        sheen.geometry!.firstMaterial = Props.glowing(.white, alpha: 0.14)
        sheen.eulerAngles.z = 0.6
        sheen.position = v3(-width * 0.18, 0.16 + (h - 0.18) / 2, 0.008)
        sheen.castsShadow = false
        n.addChildNode(sheen)
        return n
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
    /// The gate for a station, built with the static floor: the lock in its half, the window across the rest, and
    /// the drones' rack out on the pad. Nothing where the station has no pad beside its deck.
    func buildGate(_ station: Station) {
        if let old = locks.removeValue(forKey: station.name) { tearDown(old) }
        guard let g = station.gate, let lock = station.lock else { return }
        let along = CGFloat(atan2(g.inward.x, g.inward.y))
        let node = Props.cargoLock()
        node.position = v3(lock.chamber.x, 0, lock.chamber.z)
        node.eulerAngles.y = along
        node.name = "station:" + station.name
        propRoot.addChildNode(node)
        // The window across the cells the lock leaves, on the gate's line.
        var window: SCNNode?
        if !station.windowDoorway.isEmpty {
            let across = SIMD2(-g.inward.y, g.inward.x)
            let mids = station.windowDoorway.map { SIMD2(Double($0.deck.x + $0.pad.x) / 2, Double($0.deck.y + $0.pad.y) / 2) }
            let centre = mids.reduce(.zero, +) / Double(mids.count)
            let spans = mids.map { simd_dot($0 - centre, across) }
            // From the lock's wall to the far edge of the opening.
            let lockMid = SIMD2(lock.chamber.x - station.offset.x, lock.chamber.z - station.offset.y)
            let towardLock = simd_dot(lockMid - centre, across) > 0 ? 1.0 : -1.0
            let near = simd_dot(lockMid - centre, across) - towardLock * (CargoLock.halfWidth + 0.07)
            let far = towardLock > 0 ? spans.min()! - 0.5 : spans.max()! + 0.5
            let width = abs(near - far)
            let mid = centre + across * ((near + far) / 2)
            let w = Props.gateWindow(width: width)
            w.position = v3(station.offset.x + mid.x, 0, station.offset.y + mid.y)
            w.eulerAngles.y = along
            w.name = "station:" + station.name
            staticRoot.addChildNode(w)
            window = w
        }
        var rackNode: SCNNode?
        if let r = simulation.rack(station) {
            let n = Props.droneRack(count: DroneFlight.count, pitch: DroneFlight.berthPitch)
            n.position = v3(station.offset.x + r.at.x, 0, station.offset.y + r.at.y)
            n.eulerAngles.y = CGFloat(atan2(-r.along.y, r.along.x))
            n.name = "station:" + station.name
            staticRoot.addChildNode(n)
            rackNode = n
        }
        locks[station.name] = LockView(node: node, window: window, rack: rackNode, inward: g.inward)
    }

    /// Everything a gate put on the floor, off it again, with the crates it drew on its trays. A crate a carry
    /// holds is the carry's, and stays.
    private func tearDown(_ lv: LockView) {
        lv.node.removeFromParentNode()
        lv.window?.removeFromParentNode()
        lv.rack?.removeFromParentNode()
        let mine = Array(lv.waiting.values) + Array(lv.returning.values) + [lv.moving?.node].compactMap { $0 }
        for node in mine where !cargoNodes.values.contains(where: { $0 === node }) { node.removeFromParentNode() }
    }

    /// One frame of every gate: the lock and what is in it, the drones and what they hold, the puffs of gas. A crate
    /// on a minion's arms is indoors, full size; it grows back to that over a beat if it came in small.
    func tickGates(dt: Double) {
        for (name, lv) in locks {
            guard let station = fleet.stations[name] else { continue }
            for m in minions.values where m.station == name {
                guard let node = m.carried, case .crate? = m.load else { continue }
                let now = Double(node.scale.x)
                if abs(1 - now) > 0.001 {
                    let k = CGFloat(now + (1 - now) * min(1, dt * 7))
                    node.scale = SCNVector3(k, k, k)
                }
            }
            drawLock(simulation.locks[name], lv: lv, station: station, dt: dt)
        }
        drawDrones(dt: dt)
        tickPuffs(dt: dt)
    }

    // MARK: the lock

    /// The doors, the lights, the air, the scan, the screen and the crates, from the lock's job as it stands.
    private func drawLock(_ job: LockJob?, lv: LockView, station: Station, dt: Double) {
        guard let lock = station.lock else { return }
        let phase = job?.phase ?? .rest
        var doors = lock.doors(of: phase, at: clock)
        if clock < lv.passUntil {
            let k = min(1, min(clock - (lv.passUntil - RocketJob.podSeconds), lv.passUntil - clock) / 0.5)
            doors = (max(doors.inner, k), max(doors.outer, k))
        }
        let rise = CargoLock.height * 0.92
        lv.innerDoor?.position.y = CGFloat(rise * doors.inner)
        lv.outerDoor?.position.y = CGFloat(rise * doors.outer)
        // The air: kept full at rest, drained while a crate bound out cycles, let in for one coming in.
        var air = 1.0
        var scanning: (crate: CrateRef, since: Double)?
        switch phase {
        case .rest: air = 1
        case .intake(let t, let since): air = t.inbound ? max(0, 1 - (clock - since) / 0.3) : 1
        case .cycling(let t, let since):
            let k = min(1, (clock - since) / (CargoLock.cycleSeconds * 0.8))
            air = t.inbound ? k : 1 - k
            if !t.inbound { scanning = (t.crate, since) }
        case .outgoing(let t, _, let passed): air = (passed != t.inbound) ? 0 : 1
        }
        // The air going out of the vent to space, as a crate bound out is cycled: a jet that dies away.
        if air < lv.air - 0.004, let vent = lv.vent, Double.random(in: 0...1) < (lv.air - air) * 40 {
            let at = vent.convertPosition(SCNVector3Zero, to: propRoot)
            let out = SIMD3(lv.inward.x, 0.15, lv.inward.y) * Double.random(in: 0.4...0.8)
            emitPuff(at: SIMD3(Double(at.x), Double(at.y), Double(at.z)), vel: out, life: 0.9, grow: 3.5)
        }
        lv.air = air
        lv.mist?.opacity = CGFloat(0.15 + 0.85 * air)
        // Lights: amber at rest, blinking while a crate goes in, cyan pulsing while it cycles, the verdict after.
        var light = Props.gateIdle
        switch phase {
        case .intake: light = clock.truncatingRemainder(dividingBy: 0.5) < 0.25 ? Props.gateIdle : Props.gateIdle.darker(0.5)
        case .cycling: light = clock.truncatingRemainder(dividingBy: 0.4) < 0.2 ? Props.scanIdle : Props.scanIdle.darker(0.5)
        default: break
        }
        if let s = job?.scan, clock <= s.until { light = s.passed ? Props.passedLight : Props.scanRed }
        for l in lv.lamps { l.geometry?.firstMaterial?.diffuse.contents = light }
        // The scan's sheet sweeps the chamber end to end and back while a crate bound out cycles.
        if let s = scanning {
            let t = ((clock - s.since) / 1.4).truncatingRemainder(dividingBy: 2)
            let k = t < 1 ? t : 2 - t
            lv.scan?.opacity = 1
            lv.scan?.position.z = CGFloat(-CargoLock.halfDepth + 0.05 + k * (2 * CargoLock.halfDepth - 0.1))
        } else {
            lv.scan?.opacity = 0
        }
        // The screen: the crate's X-ray while it is scanned, a line sweeping down it; crossed out when refused.
        if let s = scanning {
            let c = s.crate
            if lv.showing != c.key {
                lv.showing = c.key
                let commits = world.works.find(repo: c.repo, crate: c.number)?.pulls.count ?? 0
                lv.screen?.geometry?.firstMaterial?.diffuse.contents = XRay.image(repo: c.repo, number: c.number, commits: max(2, commits * 2 + c.number % 4))
            }
            let t = ((clock - s.since) / 1.1).truncatingRemainder(dividingBy: 1)
            lv.sweep?.opacity = 0.9
            lv.sweep?.position.y = CGFloat(0.12 - t * 0.24)
        } else if case .outgoing(let t, _, false) = phase, !t.inbound {
            lv.sweep?.opacity = 0
            if lv.showing != t.crate.key + " back" {
                lv.showing = t.crate.key + " back"
                let c = t.crate
                let commits = world.works.find(repo: c.repo, crate: c.number)?.pulls.count ?? 0
                lv.screen?.geometry?.firstMaterial?.diffuse.contents = XRay.image(repo: c.repo, number: c.number,
                                                                                   commits: max(2, commits * 2 + c.number % 4), sentBack: true)
            }
        } else {
            lv.sweep?.opacity = 0
            if job?.scan.map({ clock > $0.until }) ?? true, !lv.showing.isEmpty {
                lv.showing = ""
                lv.screen?.geometry?.firstMaterial?.diffuse.contents = NSColor(rgb: (0.03, 0.07, 0.14))
            }
        }
        // Crates on the trays, stacked, and the one in the chamber.
        func keep(_ list: [CrateRef], in shown: inout [String: SCNNode], at tray: SIMD3<Double>, scale: Double) {
            let keys = Set(list.map(\.key))
            for (key, node) in shown where !keys.contains(key) && lv.moving?.key != key {
                if !cargoNodes.values.contains(where: { $0 === node }) && drone(holdingNode: node) == nil { node.removeFromParentNode() }
                shown[key] = nil
            }
            for (i, c) in list.enumerated() {
                let node = shown[c.key] ?? {
                    let n = ridingNode(c) ?? lockCrate(c)
                    stopCrate(n)
                    if n.parent !== propRoot { n.removeFromParentNode(); propRoot.addChildNode(n) }
                    shown[c.key] = n
                    return n
                }()
                if !crateMoving(node) {
                    let k = CGFloat(scale)
                    node.scale = SCNVector3(k, k, k)
                    node.position = v3(tray.x, CargoLock.top + Double(i) * 0.34 * scale, tray.z)
                }
            }
        }
        keep(job?.waiting ?? [], in: &lv.waiting, at: lock.inner, scale: 1)
        keep(job?.returning ?? [], in: &lv.returning, at: lock.outer, scale: Station.testedScale)
        if let t = job?.trip, let place = lock.place(of: phase, at: clock) {
            if lv.moving?.key != t.crate.key {
                let node = lv.waiting.removeValue(forKey: t.crate.key) ?? lv.returning.removeValue(forKey: t.crate.key) ?? ridingNode(t.crate) ?? lockCrate(t.crate)
                stopCrate(node)
                if node.parent !== propRoot { node.removeFromParentNode(); propRoot.addChildNode(node) }
                lv.moving = (t.crate.key, node)
            }
            let node = lv.moving!.node
            node.position = v3(place.pos.x, place.pos.y, place.pos.z)
            node.eulerAngles = SCNVector3(0, CGFloat(atan2(lock.inward.x, lock.inward.y)), 0)
            let k = CGFloat(place.scale)
            node.scale = SCNVector3(k, k, k)
            if let plate = node.childNodes.first(where: { $0.geometry?.name == Props.plateName }), let s = job?.scan, clock <= s.until {
                plate.geometry?.firstMaterial?.diffuse.contents = s.passed ? Props.passedLight : Props.scanRed
            }
        }
    }

    /// The node of the carry waiting on this crate in the lock: the lock carries that one.
    private func ridingNode(_ crate: CrateRef) -> SCNNode? {
        simulation.cargo.first { $0.value.command.crate == crate && ($0.value.inLock || $0.value.byDrone) }.flatMap { cargoNodes[$0.key] }
    }

    /// A crate as the rows draw it, for the lock to carry: its repository's colour, your straps, the light off.
    func lockCrate(_ crate: CrateRef) -> SCNNode {
        let row = fleet.stations[crate.station]?.ledger[crate.repo, crate.number]
        let alien = row?.alien == true
        let color = alien ? Palette.alien.darker(0.3) : NSColor(fleet.color(forRepo: crate.repo))
        let words = crateWords(repo: crate.repo, number: crate.number)
        return Props.package(color: color, band: NSColor(rgb: (0.3, 0.32, 0.38)), size: 0.38,
                             mine: !alien && world.isMine(repo: crate.repo, number: crate.number), number: crate.number,
                             title: words.title, who: words.who)
    }

    /// The lock has cycled: heard once.
    func lockCycled(station: String, inbound: Bool, passed: Bool) {
        drone.ping(seed: inbound ? 5 : passed ? 7 : 3)
    }

    /// Out of the lock onto a tray. The carry waiting for it takes it from here, the same crate it put in; one
    /// that came on the pallet gets a carry of its own, a drone's outside and a hand's indoors.
    func lockHandoff(station name: String, crate: CrateRef, from spot: Spot, collect: Int?) {
        guard let lv = locks[name], let station = fleet.stations[name] else { return }
        let node = lv.moving?.key == crate.key ? lv.moving!.node : (crateNode(crate) ?? lockCrate(crate))
        lv.moving = nil
        if node.parent == nil { propRoot.addChildNode(node) }
        node.position = v3(spot.pos.x, spot.pos.y, spot.pos.z)
        if let collect { cargoNodes[collect] = node; return }
        let command = world.carryFromLock(station: station, crate: crate, from: spot)
        carry(command, node: node, pastLock: station.isOutside(spot)) { [weak self] in
            guard let self else { return }
            node.removeFromParentNode()
            rebuildMarkers()
            refreshRockets()
        }
    }

    // MARK: the drones

    /// The drone whose grip holds this node, if one does.
    private func drone(holdingNode node: SCNNode) -> PadDrone? {
        for list in simulation.drones.values {
            for d in list where d.holding != nil { if let id = d.carry, cargoNodes[id] === node { return d } }
        }
        return nil
    }

    /// Every drone where the simulation has it: bobbing a little in the air, tilting into its thrust, its claws
    /// shut on what it holds and the crate under them, its strobe blinking, the torch lit at a seam, and a puff
    /// from the nozzles opposite each push. The rack's lights say who is home.
    private func drawDrones(dt: Double) {
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
                // The claws: shut while it holds, or while they close on a crate or let it go.
                let shut: Double = {
                    switch d.task {
                    case .grab: return 1 - max(0, (d.until - clock) / DroneFlight.gripSeconds)
                    case .release: return max(0, (d.until - clock) / DroneFlight.gripSeconds)
                    default: return d.holding != nil ? 1 : 0
                    }
                }()
                v.grip += (shut - v.grip) * min(1, dt * 10)
                v.clawL?.eulerAngles.z = CGFloat(-0.5 + 0.5 * v.grip)
                v.clawR?.eulerAngles.z = CGFloat(0.5 - 0.5 * v.grip)
                v.strobe?.isHidden = resting || clock.truncatingRemainder(dividingBy: 1.2) > 0.08
                v.eye?.geometry?.firstMaterial?.diffuse.contents = d.torch ? NSColor(rgb: (1.0, 0.75, 0.3)) : Props.scanIdle
                // The crate in its grip hangs under it, packed small.
                if let crate = d.holding, let id = d.carry, let node = cargoNodes[id] ?? crateNode(crate) {
                    cargoNodes[id] = node
                    stopCrate(node)
                    if node.parent !== propRoot { node.removeFromParentNode(); propRoot.addChildNode(node) }
                    let k = Station.testedScale
                    node.scale = SCNVector3(k, k, k)
                    node.position = v3(d.pos.x, d.pos.y + bob - DroneFlight.hang - 0.38 * 0.8 * k, d.pos.z)
                    node.eulerAngles = SCNVector3(0, CGFloat(d.yaw), 0)
                }
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
            if let rack = locks[name]?.rack {
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

    private func tickPuffs(dt: Double) {
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

/// What the X-ray shows of a crate: its outline, the commits inside as cubes, and now and then something
/// that has no business being in there. The same crate always shows the same picture.
enum XRay {
    private static var cache: [String: NSImage] = [:]
    static let finds = ["rubber duck", "football", "banana", "sock", "keys"]

    /// Which find, if any, a crate carries: about one in three.
    static func find(repo: String, number: Int) -> String? {
        let h = stableHash("xray \(repo)#\(number)")
        return h % 3 == 0 ? finds[Int((h / 3) % UInt64(finds.count))] : nil
    }

    static func image(repo: String, number: Int, commits: Int, sentBack: Bool = false) -> NSImage {
        let key = "\(repo)#\(number)" + (sentBack ? " back" : "")
        if let i = cache[key] { return i }
        var seed = stableHash("cubes \(key)") | 1
        func rnd() -> Double { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Double(seed >> 11) / Double(1 << 53) }
        let bone = NSColor(rgb: (0.55, 0.95, 1.0)), soft = NSColor(rgb: (1.0, 0.62, 0.25))
        let found = find(repo: repo, number: number)
        let img = NSImage(size: NSSize(width: 560, height: 380), flipped: false) { r in
            NSColor(rgb: (0.03, 0.07, 0.14)).setFill(); r.fill()
            // Faint lines across, the way a scanner's picture has them.
            NSColor(rgb: (0.08, 0.14, 0.24)).setFill()
            for y in stride(from: 0.0, to: r.height, by: 6) { NSRect(x: 0, y: y, width: r.width, height: 1).fill() }
            // The crate, its strap, and the commits in it.
            let crate = NSRect(x: 150, y: 70, width: 260, height: 240)
            bone.withAlphaComponent(0.8).setStroke()
            let box = NSBezierPath(rect: crate); box.lineWidth = 5; box.stroke()
            let strap = NSBezierPath(rect: NSRect(x: crate.minX, y: crate.midY - 14, width: crate.width, height: 28)); strap.lineWidth = 2; strap.stroke()
            bone.withAlphaComponent(0.55).setFill()
            for _ in 0..<max(1, min(9, commits)) {
                let s = 34.0
                NSRect(x: crate.minX + 18 + rnd() * (crate.width - 36 - s), y: crate.minY + 18 + rnd() * (crate.height - 36 - s), width: s, height: s).fill()
            }
            // Whatever else is in there, in the orange of something soft.
            soft.withAlphaComponent(0.85).setFill(); soft.setStroke()
            let c = NSPoint(x: crate.midX + 30, y: crate.midY + 40)
            switch found {
            case "rubber duck":
                NSBezierPath(ovalIn: NSRect(x: c.x - 55, y: c.y - 35, width: 100, height: 60)).fill()
                NSBezierPath(ovalIn: NSRect(x: c.x + 15, y: c.y + 10, width: 50, height: 50)).fill()
                let beak = NSBezierPath(); beak.move(to: NSPoint(x: c.x + 62, y: c.y + 38)); beak.line(to: NSPoint(x: c.x + 88, y: c.y + 30))
                beak.line(to: NSPoint(x: c.x + 62, y: c.y + 24)); beak.close(); beak.fill()
            case "football":
                NSBezierPath(ovalIn: NSRect(x: c.x - 50, y: c.y - 50, width: 100, height: 100)).fill()
                NSColor(rgb: (0.03, 0.07, 0.14)).setFill()
                for (dx, dy) in [(0.0, 0.0), (-28.0, 20.0), (28.0, 20.0), (-20.0, -28.0), (20.0, -28.0)] {
                    NSBezierPath(ovalIn: NSRect(x: c.x + dx - 11, y: c.y + dy - 11, width: 22, height: 22)).fill()
                }
            case "banana":
                let b = NSBezierPath(); b.lineWidth = 26; b.lineCapStyle = .round
                b.appendArc(withCenter: NSPoint(x: c.x, y: c.y + 70), radius: 90, startAngle: 210, endAngle: 330)
                b.stroke()
            case "sock":
                let s = NSBezierPath(); s.lineWidth = 34; s.lineCapStyle = .round; s.lineJoinStyle = .round
                s.move(to: NSPoint(x: c.x - 30, y: c.y + 60)); s.line(to: NSPoint(x: c.x - 30, y: c.y - 30)); s.line(to: NSPoint(x: c.x + 40, y: c.y - 30))
                s.stroke()
            case "keys":
                let ring = NSBezierPath(ovalIn: NSRect(x: c.x - 60, y: c.y, width: 44, height: 44)); ring.lineWidth = 6; ring.stroke()
                for (k, angle) in [0.0, 0.5].enumerated() {
                    let key = NSBezierPath(); key.lineWidth = 10
                    let from = NSPoint(x: c.x - 20, y: c.y + 22), to = NSPoint(x: from.x + 90 * cos(angle - 0.2), y: from.y - 90 * sin(angle + Double(k) * 0.1))
                    key.move(to: from); key.line(to: to); key.stroke()
                }
            default: break
            }
            let label = NSAttributedString(string: "#\(number)" + (found.map { "   ·   \($0)?" } ?? ""),
                                           attributes: [.font: NSFont.monospacedSystemFont(ofSize: 22, weight: .medium), .foregroundColor: bone])
            label.draw(at: NSPoint(x: 18, y: 14))
            // Sent back: a red cross over the whole picture, and a red frame round it.
            if sentBack {
                let red = NSColor(rgb: (1.0, 0.25, 0.22))
                red.withAlphaComponent(0.18).setFill(); r.fill()
                red.setStroke()
                let frame = NSBezierPath(rect: r.insetBy(dx: 6, dy: 6)); frame.lineWidth = 12; frame.stroke()
                let x = NSBezierPath(); x.lineWidth = 26; x.lineCapStyle = .round
                x.move(to: NSPoint(x: crate.minX - 20, y: crate.minY - 10)); x.line(to: NSPoint(x: crate.maxX + 20, y: crate.maxY + 10))
                x.move(to: NSPoint(x: crate.minX - 20, y: crate.maxY + 10)); x.line(to: NSPoint(x: crate.maxX + 20, y: crate.minY - 10))
                x.stroke()
            }
            return true
        }
        cache[key] = img
        return img
    }
}

