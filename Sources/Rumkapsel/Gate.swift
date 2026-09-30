// The gate between the deck and the pad, and the X-ray in it: a belt through half of the arch, a tunnel with
// rubber flaps on the gate line, a monitor, and the operator standing at it. The belt, the scan and the verdict
// are the simulation's (`GateJob`); this draws them. A crate carried through the other half by hand is scanned
// too: onto the pad it shrinks, packed for flight; an untested one going up sets off the alarm.

import AppKit
import SceneKit

/// The gate as the scene draws it, one per station.
final class GateView {
    let arch: SCNNode, belt: SCNNode, tunnel: SCNNode, monitor: SCNNode, operatorNode: SCNNode
    /// The arch's and the tunnel's lights, the operator's eye, the screen and the line that sweeps it.
    var lights: [SCNNode] = []
    let eye: SCNNode?
    let screen: SCNNode?
    let sweep: SCNNode?
    var rollers: [SCNNode] = []
    /// The way through, for the rollers, and where the operator faces at rest and while it scans.
    let inward: SIMD2<Double>
    let restYaw: Double, watchYaw: Double
    var yaw: Double
    /// The verdict showing now, and until when; an alarm blinks.
    var scan: (color: NSColor, until: Double, alarm: Bool)?
    /// Crates on the belt: waiting at its deck end, by crate key, and the one on its way through.
    var waiting: [String: SCNNode] = [:]
    var moving: (key: String, node: SCNNode)?
    /// The picture on the screen, and the crate it is of.
    var showing = ""
    /// The operator's head and arms, and what it is reacting to since when: a crate through, or one
    /// sent back.
    let head: SCNNode?, armL: SCNNode?, armR: SCNNode?
    var reaction: (passed: Bool, since: Double)?
    let standsAt: SCNVector3

    init(arch: SCNNode, belt: SCNNode, tunnel: SCNNode, monitor: SCNNode, operatorNode: SCNNode, inward: SIMD2<Double>,
         restYaw: Double, watchYaw: Double) {
        self.arch = arch; self.belt = belt; self.tunnel = tunnel; self.monitor = monitor; self.operatorNode = operatorNode
        self.inward = inward; self.restYaw = restYaw; self.watchYaw = watchYaw; yaw = restYaw
        eye = operatorNode.childNode(withName: "eye", recursively: true)
        head = operatorNode.childNode(withName: "head", recursively: true)
        armL = operatorNode.childNode(withName: "armL", recursively: true)
        armR = operatorNode.childNode(withName: "armR", recursively: true)
        standsAt = operatorNode.position
        screen = monitor.childNode(withName: "screen", recursively: true)
        sweep = monitor.childNode(withName: "sweep", recursively: true)
        for n in [arch, tunnel] { n.enumerateChildNodes { c, _ in if c.name == "light" { lights.append(c) } } }
        belt.enumerateChildNodes { c, _ in if c.name == "roller" { rollers.append(c) } }
    }
}

extension Props {
    /// A plate lit for a crate through the gate.
    static let passedLight = NSColor(rgb: (0.45, 0.95, 0.5))
    static let scanRed = NSColor(rgb: (1.0, 0.22, 0.2))
    static let scanIdle = NSColor(rgb: (0.35, 0.75, 0.95))
    /// The gate's lights at rest.
    static let gateIdle = NSColor(rgb: (0.95, 0.7, 0.15))

    static func securityGate(width: Double) -> SCNNode {
        let n = SCNNode()
        let steel = lit(NSColor(rgb: (0.55, 0.57, 0.62))), dark = lit(NSColor(rgb: (0.3, 0.32, 0.38)))
        let h = 0.95
        for side in [-1.0, 1.0] {
            let post = SCNNode(geometry: SCNBox(width: 0.1, height: h, length: 0.14, chamferRadius: 0))
            post.geometry!.firstMaterial = steel
            post.position = v3(side * (width / 2 + 0.05), h / 2, 0)
            n.addChildNode(post)
            let stripe = SCNNode(geometry: SCNBox(width: 0.104, height: 0.05, length: 0.144, chamferRadius: 0))
            stripe.geometry!.firstMaterial = flat(gateIdle)
            stripe.name = "light"
            stripe.position = v3(side * (width / 2 + 0.05), 0.12, 0)
            n.addChildNode(stripe)
            // A strip down the inside of each post, facing the opening: the scanner's light.
            let strip = SCNNode(geometry: SCNBox(width: 0.02, height: h - 0.3, length: 0.06, chamferRadius: 0))
            strip.geometry!.firstMaterial = flat(gateIdle)
            strip.name = "light"
            strip.position = v3(side * (width / 2 - 0.001), (h - 0.3) / 2 + 0.2, 0)
            n.addChildNode(strip)
        }
        let lintel = SCNNode(geometry: SCNBox(width: width + 0.2, height: 0.1, length: 0.16, chamferRadius: 0))
        lintel.geometry!.firstMaterial = dark
        lintel.position = v3(0, h + 0.05, 0)
        n.addChildNode(lintel)
        let beam = SCNNode(geometry: SCNBox(width: width, height: 0.025, length: 0.08, chamferRadius: 0))
        beam.geometry!.firstMaterial = flat(scanIdle.darker(0.4))
        beam.name = "scan"
        beam.position = v3(0, h - 0.02, 0)
        n.addChildNode(beam)
        let sill = SCNNode(geometry: SCNBox(width: width + 0.2, height: 0.012, length: 0.1, chamferRadius: 0))
        sill.geometry!.firstMaterial = dark
        sill.position = v3(0, 0.006, 0)
        n.addChildNode(sill)
        return n
    }


    /// The operator: a boxy robot on a squat base, a visor for an eye and two arms reaching for the monitor.
    /// Its front is +z.
    static func securityUnit() -> SCNNode {
        let n = SCNNode()
        let shell = lit(NSColor(rgb: (0.62, 0.65, 0.72))), dark = lit(NSColor(rgb: (0.24, 0.26, 0.32)))
        let trim = flat(NSColor(rgb: (0.95, 0.7, 0.15)))
        func box(_ w: Double, _ h: Double, _ l: Double, _ at: SCNVector3, _ m: SCNMaterial) -> SCNNode {
            let b = SCNNode(geometry: SCNBox(width: w, height: h, length: l, chamferRadius: 0))
            b.geometry!.firstMaterial = m
            b.position = at
            n.addChildNode(b)
            return b
        }
        _ = box(0.26, 0.08, 0.22, v3(0, 0.04, 0), dark)
        _ = box(0.264, 0.025, 0.224, v3(0, 0.07, 0), trim)
        _ = box(0.08, 0.08, 0.08, v3(0, 0.12, 0), dark)
        _ = box(0.28, 0.24, 0.2, v3(0, 0.28, 0), shell)
        _ = box(0.12, 0.08, 0.01, v3(0, 0.3, 0.101), dark)
        // The head turns on its neck; the arms swing at the shoulder. Named for the scene to move.
        let head = SCNNode()
        head.name = "head"
        head.position = v3(0, 0.42, 0)
        n.addChildNode(head)
        func part(_ w: Double, _ h: Double, _ l: Double, _ at: SCNVector3, _ m: SCNMaterial, on parent: SCNNode) -> SCNNode {
            let b = SCNNode(geometry: SCNBox(width: w, height: h, length: l, chamferRadius: 0))
            b.geometry!.firstMaterial = m
            b.position = at
            parent.addChildNode(b)
            return b
        }
        _ = part(0.24, 0.17, 0.2, v3(0, 0.08, 0), shell, on: head)
        _ = part(0.244, 0.02, 0.204, v3(0, 0.175, 0), trim, on: head)
        let eye = part(0.19, 0.05, 0.012, v3(0, 0.09, 0.101), flat(scanIdle), on: head)
        eye.name = "eye"
        _ = part(0.015, 0.08, 0.015, v3(0.08, 0.22, -0.04), dark, on: head)
        for side in [-1.0, 1.0] {
            _ = box(0.05, 0.05, 0.05, v3(side * 0.165, 0.36, 0), dark)
            let shoulder = SCNNode()
            shoulder.name = side < 0 ? "armL" : "armR"
            shoulder.position = v3(side * 0.165, 0.36, 0)
            n.addChildNode(shoulder)
            let arm = part(0.04, 0.04, 0.2, v3(0, -0.035, 0.095), shell, on: shoulder)
            arm.eulerAngles.x = 0.35
            _ = part(0.055, 0.03, 0.05, v3(0, -0.07, 0.19), dark, on: shoulder)
        }
        return n
    }

    /// The belt, `length` long along its z, its top at `Belt.top`: a dark frame on legs and pale rollers
    /// across it, named for the scene to turn.
    static func xrayBelt(length: Double) -> SCNNode {
        let n = SCNNode()
        let frame = SCNNode(geometry: SCNBox(width: 0.5, height: 0.05, length: length, chamferRadius: 0))
        frame.geometry!.firstMaterial = lit(NSColor(rgb: (0.22, 0.23, 0.27)))
        frame.position = v3(0, Belt.top - 0.03, 0)
        n.addChildNode(frame)
        for side in [-1.0, 1.0] {
            let rail = SCNNode(geometry: SCNBox(width: 0.03, height: 0.06, length: length, chamferRadius: 0))
            rail.geometry!.firstMaterial = lit(NSColor(rgb: (0.55, 0.57, 0.62)))
            rail.position = v3(side * 0.26, Belt.top - 0.01, 0)
            n.addChildNode(rail)
            for z in stride(from: -length / 2 + 0.1, through: length / 2 - 0.1, by: length / 3) {
                let leg = SCNNode(geometry: SCNBox(width: 0.03, height: Belt.top - 0.05, length: 0.03, chamferRadius: 0))
                leg.geometry!.firstMaterial = lit(NSColor(rgb: (0.38, 0.4, 0.45)))
                leg.position = v3(side * 0.22, (Belt.top - 0.05) / 2, z)
                n.addChildNode(leg)
            }
        }
        var z = -length / 2
        while z < length / 2 {
            let roller = SCNNode(geometry: SCNBox(width: 0.46, height: 0.012, length: 0.03, chamferRadius: 0))
            roller.geometry!.firstMaterial = lit(NSColor(rgb: (0.62, 0.64, 0.7)))
            roller.name = "roller"
            roller.position = v3(0, Belt.top - 0.004, z)
            n.addChildNode(roller)
            z += 0.12
        }
        return n
    }

    /// The X-ray tunnel over the belt, along its z: a pale housing open at both ends, rubber flaps hanging in
    /// each opening, a hazard band, and a light along its top.
    static func xrayTunnel() -> SCNNode {
        let n = SCNNode()
        let shell = lit(NSColor(rgb: (0.8, 0.82, 0.86))), dark = lit(NSColor(rgb: (0.16, 0.17, 0.2)))
        let length = 0.72, height = 0.62, wall = 0.07, inner = 0.52
        let top = SCNNode(geometry: SCNBox(width: inner + 2 * wall, height: 0.14, length: length, chamferRadius: 0))
        top.geometry!.firstMaterial = shell
        top.position = v3(0, height - 0.07, 0)
        n.addChildNode(top)
        for side in [-1.0, 1.0] {
            let w = SCNNode(geometry: SCNBox(width: wall, height: height - 0.14, length: length, chamferRadius: 0))
            w.geometry!.firstMaterial = shell
            w.position = v3(side * (inner / 2 + wall / 2), (height - 0.14) / 2, 0)
            n.addChildNode(w)
            let band = SCNNode(geometry: SCNBox(width: wall + 0.004, height: 0.05, length: length + 0.004, chamferRadius: 0))
            band.geometry!.firstMaterial = flat(NSColor(rgb: (0.95, 0.7, 0.15)))
            band.position = v3(side * (inner / 2 + wall / 2), 0.08, 0)
            n.addChildNode(band)
        }
        // Rubber flaps: dark strips hanging in each opening, a gap between them.
        for end in [-1.0, 1.0] {
            for k in 0..<5 {
                let flap = SCNNode(geometry: SCNBox(width: inner / 5 - 0.012, height: height - 0.14 - Belt.top - 0.2, length: 0.008, chamferRadius: 0))
                flap.geometry!.firstMaterial = dark
                flap.position = v3(-inner / 2 + inner / 5 * (Double(k) + 0.5), height - 0.14 - (height - 0.14 - Belt.top - 0.2) / 2, end * (length / 2 - 0.01))
                n.addChildNode(flap)
            }
        }
        let light = SCNNode(geometry: SCNBox(width: 0.08, height: 0.03, length: length * 0.8, chamferRadius: 0))
        light.geometry!.firstMaterial = flat(gateIdle)
        light.name = "light"
        light.position = v3(0, height + 0.015, 0)
        n.addChildNode(light)
        return n
    }

    /// The monitor on its stand, screen facing +z: a dark panel with the picture on a plane named "screen"
    /// and a thin line named "sweep" that runs down it while a crate is looked at.
    static func xrayMonitor() -> SCNNode {
        let n = SCNNode()
        let steel = lit(NSColor(rgb: (0.38, 0.4, 0.45)))
        let post = SCNNode(geometry: SCNBox(width: 0.05, height: 0.62, length: 0.05, chamferRadius: 0))
        post.geometry!.firstMaterial = steel
        post.position = v3(0, 0.31, 0)
        n.addChildNode(post)
        let foot = SCNNode(geometry: SCNBox(width: 0.22, height: 0.03, length: 0.18, chamferRadius: 0))
        foot.geometry!.firstMaterial = steel
        foot.position = v3(0, 0.015, 0)
        n.addChildNode(foot)
        let case_ = SCNNode(geometry: SCNBox(width: 0.62, height: 0.44, length: 0.05, chamferRadius: 0))
        case_.geometry!.firstMaterial = lit(NSColor(rgb: (0.16, 0.17, 0.2)))
        case_.position = v3(0, 0.82, 0)
        n.addChildNode(case_)
        let screen = SCNNode(geometry: SCNPlane(width: 0.56, height: 0.38))
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = NSColor(rgb: (0.03, 0.07, 0.14))
        screen.geometry!.firstMaterial = m
        screen.name = "screen"
        screen.position = v3(0, 0.82, 0.026)
        n.addChildNode(screen)
        let sweep = SCNNode(geometry: SCNPlane(width: 0.56, height: 0.012))
        sweep.geometry!.firstMaterial = flat(scanIdle)
        sweep.name = "sweep"
        sweep.opacity = 0
        sweep.position = v3(0, 0.82, 0.028)
        n.addChildNode(sweep)
        return n
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

extension StationController {
    /// The gate for a station, built with the static floor: the arch in the doorway onto the pad, the belt
    /// and the tunnel through half of it, the monitor and its operator on the deck side. Nothing where the
    /// station has no deck beside its pad.
    func buildGate(_ station: Station) {
        if let old = gates[station.name] { for n in [old.belt, old.tunnel, old.monitor, old.operatorNode] { n.removeFromParentNode() } }
        gates[station.name] = nil
        guard world.deckInUse(station: station.name), let g = station.gate, let belt = station.belt else { return }
        let arch = Looks.current.gate(width: g.width) ?? Props.securityGate(width: g.width)
        // The arch spans along its x: turned so that x runs along the gate's line.
        arch.eulerAngles.y = CGFloat(atan2(g.inward.x, g.inward.y))
        arch.position = v3(station.offset.x + g.center.x, 0, station.offset.y + g.center.y)
        arch.name = "station:" + station.name
        staticRoot.addChildNode(arch)
        // Belt and tunnel along the way through: their z runs pad-ward.
        let along = CGFloat(atan2(g.inward.x, g.inward.y))
        let length = simd_distance(belt.start, belt.exit) + 0.5
        let beltNode = Props.xrayBelt(length: length)
        let mid = (belt.start + belt.exit) / 2
        beltNode.position = v3(mid.x, 0, mid.z)
        beltNode.eulerAngles.y = along
        beltNode.name = "station:" + station.name
        propRoot.addChildNode(beltNode)
        let tunnel = Props.xrayTunnel()
        tunnel.position = v3(belt.tunnel.x, 0, belt.tunnel.z)
        tunnel.eulerAngles.y = along
        tunnel.name = "station:" + station.name
        propRoot.addChildNode(tunnel)
        // The operator on the deck across from its post, the monitor beside it toward the belt, both facing
        // back over the deck, where the crates come from and where anyone watching is.
        guard let stand = station.operatorSpot, let screen = station.monitorSpot else { return }
        let facingDeck = atan2(-g.inward.x, -g.inward.y)
        let monitor = Props.xrayMonitor()
        let screenAt = screen + station.offset
        monitor.position = v3(screenAt.x, 0, screenAt.y)
        monitor.eulerAngles.y = CGFloat(facingDeck)
        monitor.name = "station:" + station.name
        propRoot.addChildNode(monitor)
        let operatorNode = Looks.current.securityUnit() ?? Props.securityUnit()
        let standAt = stand + station.offset
        operatorNode.position = v3(standAt.x, 0.02, standAt.y)
        operatorNode.name = "gate:" + station.name
        propRoot.addChildNode(operatorNode)
        let watch = atan2(screenAt.x - standAt.x, screenAt.y - standAt.y)
        gates[station.name] = GateView(arch: arch, belt: beltNode, tunnel: tunnel, monitor: monitor, operatorNode: operatorNode,
                                       inward: g.inward, restYaw: facingDeck, watchYaw: watch)
    }

    /// One frame of every gate: hand carries crossing the arch shrink or grow and are scanned; the X-ray's
    /// belt, crates, lights, screen and operator are drawn where the simulation has them.
    func tickGates(dt: Double) {
        for (name, gv) in gates {
            guard let station = fleet.stations[name], let g = station.gate else { continue }
            let pad = Set(station.padCells)
            for m in minions.values where m.station == name {
                guard let node = m.carried, case .crate(let crate)? = m.load else { gateSide[m.id] = nil; continue }
                let onPad = pad.contains(Cell(x: Int(m.pos.x.rounded()), y: Int(m.pos.y.rounded())))
                // On the pad a crate is packed small; off it, crate-sized again. The change takes a moment.
                let want = onPad ? Station.testedScale : 1, now = Double(node.scale.x)
                if abs(want - now) > 0.001 {
                    let k = CGFloat(now + (want - now) * min(1, dt * 7))
                    node.scale = SCNVector3(k, k, k)
                }
                if let was = gateSide[m.id], was != onPad, simd_distance(m.pos, g.center) < g.width / 2 + 1.2 {
                    scanned(crate, station: station, onto: onPad, gv: gv, node: node)
                }
                gateSide[m.id] = onPad
            }
            drawXRay(simulation.gates[name], gv: gv, station: station, dt: dt)
        }
    }

    /// The belt and everything on it, the lights, the screen and the operator, from the job as it stands.
    private func drawXRay(_ job: GateJob?, gv: GateView, station: Station, dt: Double) {
        guard let belt = station.belt else { return }
        let phase = job?.phase ?? .rest
        var scanning: CrateRef?
        if case .scanning(let c, _) = phase { scanning = c }
        // Lights: amber at rest, a quick cyan pulse while looking, the verdict after.
        var light = Props.gateIdle
        if scanning != nil { light = clock.truncatingRemainder(dividingBy: 0.4) < 0.2 ? Props.scanIdle : Props.scanIdle.darker(0.5) }
        if let s = gv.scan, clock <= s.until {
            light = s.alarm ? (clock.truncatingRemainder(dividingBy: 0.4) < 0.2 ? s.color : s.color.darker(0.6)) : s.color
        } else if let s = job?.scan, clock <= s.until {
            light = s.passed ? Props.passedLight : Props.scanRed
        }
        for l in gv.lights { l.geometry?.firstMaterial?.diffuse.contents = light }
        gv.eye?.geometry?.firstMaterial?.diffuse.contents = light == Props.gateIdle ? Props.scanIdle : light
        // The operator looks at the screen while there is something on it, back over the deck otherwise.
        let want = scanning != nil ? gv.watchYaw : gv.restYaw
        gv.yaw += atan2(sin(want - gv.yaw), cos(want - gv.yaw)) * min(1, dt * 6)
        gv.operatorNode.eulerAngles.y = CGFloat(gv.yaw)
        // What the operator does with itself: looks over the deck at rest, types at the monitor while a crate
        // is in the tunnel, raises an arm for one through, and both, shaking, for one sent back.
        let reacting = gv.reaction.flatMap { clock - $0.since < ($0.passed ? 1.6 : 2.6) ? $0 : nil }
        var headYaw = 0.0, left = 0.0, right = 0.0, shake = 0.0
        if let r = reacting {
            let t = clock - r.since
            if r.passed { right = -1.9 * min(1, t / 0.25) * (t > 1.3 ? max(0, (1.6 - t) / 0.3) : 1) }
            else {
                left = -1.55 * min(1, t / 0.2); right = left
                shake = sin(clock * 55) * 0.012
                headYaw = sin(clock * 9) * 0.35
            }
        } else if scanning != nil {
            left = -0.25 + sin(clock * 16) * 0.2
            right = -0.25 - sin(clock * 16) * 0.2
            headYaw = sin(clock * 3) * 0.08
        } else {
            headYaw = sin(clock * 2 * .pi / 5) * 0.5
        }
        gv.head?.eulerAngles.y = CGFloat(headYaw)
        gv.armL?.eulerAngles.x = CGFloat(left)
        gv.armR?.eulerAngles.x = CGFloat(right)
        gv.operatorNode.position = SCNVector3(gv.standsAt.x + CGFloat(shake), gv.standsAt.y, gv.standsAt.z)
        if let r = reacting {
            let on = r.passed || clock.truncatingRemainder(dividingBy: 0.3) < 0.15
            gv.eye?.geometry?.firstMaterial?.diffuse.contents = r.passed ? Props.passedLight : on ? Props.scanRed : Props.scanRed.darker(0.6)
        }
        // The screen: the crate's X-ray while it is in the tunnel, a line sweeping down it; dark otherwise.
        if let c = scanning, case .scanning(_, let since) = phase {
            if gv.showing != c.key {
                gv.showing = c.key
                let commits = world.works.find(repo: c.repo, crate: c.number)?.pulls.count ?? 0
                gv.screen?.geometry?.firstMaterial?.diffuse.contents = XRay.image(repo: c.repo, number: c.number, commits: max(2, commits * 2 + c.number % 4))
            }
            let t = ((clock - since) / 1.1).truncatingRemainder(dividingBy: 1)
            gv.sweep?.opacity = 0.9
            gv.sweep?.position.y = CGFloat(0.82 + 0.18 - t * 0.36)
        } else if case .outgoing(let c, _, false) = phase {
            // Sent back out the way it came: its picture stays up, crossed out.
            gv.sweep?.opacity = 0
            if gv.showing != c.key + " back" {
                gv.showing = c.key + " back"
                let commits = world.works.find(repo: c.repo, crate: c.number)?.pulls.count ?? 0
                gv.screen?.geometry?.firstMaterial?.diffuse.contents = XRay.image(repo: c.repo, number: c.number,
                                                                                   commits: max(2, commits * 2 + c.number % 4), sentBack: true)
            }
        } else {
            gv.sweep?.opacity = 0
            if job?.scan.map({ clock > $0.until }) ?? true, gv.scan.map({ clock > $0.until }) ?? true, !gv.showing.isEmpty {
                gv.showing = ""
                gv.screen?.geometry?.firstMaterial?.diffuse.contents = NSColor(rgb: (0.03, 0.07, 0.14))
            }
        }
        // The rollers turn while the belt runs: in, out, or back.
        var run = 0.0
        switch phase {
        case .intake: run = 1
        case .outgoing(_, _, let passed): run = passed ? 1 : -1
        default: break
        }
        if run != 0 {
            for r in gv.rollers {
                var z = Double(r.position.z) + run * dt * 0.55
                let half = (Double(gv.rollers.count) * 0.12) / 2
                if z > half { z -= half * 2 } else if z < -half { z += half * 2 }
                r.position.z = CGFloat(z)
            }
        }
        // Crates waiting at the belt's deck end, stacked, and the one on its way through.
        let waiting = job?.waiting ?? []
        let keys = Set(waiting.map(\.key))
        for (key, node) in gv.waiting where !keys.contains(key) && gv.moving?.key != key {
            if !cargoNodes.values.contains(where: { $0 === node }) { node.removeFromParentNode() }
            gv.waiting[key] = nil
        }
        for (i, c) in waiting.enumerated() {
            let node = gv.waiting[c.key] ?? {
                let n = ridingNode(c) ?? gateCrate(c)
                if n.parent == nil { propRoot.addChildNode(n) }
                gv.waiting[c.key] = n
                return n
            }()
            if !crateMoving(node) { node.position = v3(belt.start.x, Belt.top + Double(i) * 0.34, belt.start.z) }
        }
        if let c = job?.moving, let place = belt.place(of: phase, at: clock) {
            if gv.moving?.key != c.key {
                let node = gv.waiting.removeValue(forKey: c.key) ?? ridingNode(c) ?? gateCrate(c)
                stopCrate(node)
                if node.parent == nil { propRoot.addChildNode(node) }
                gv.moving = (c.key, node)
            }
            let node = gv.moving!.node
            node.position = v3(place.pos.x, place.pos.y, place.pos.z)
            let k = CGFloat(place.scale)
            node.scale = SCNVector3(k, k, k)
            if let plate = node.childNodes.first(where: { $0.geometry?.name == Props.plateName }), let s = job?.scan, clock <= s.until {
                plate.geometry?.firstMaterial?.diffuse.contents = s.passed ? Props.passedLight : Props.scanRed
            }
        }
    }

    /// The node on the arms of whoever set this crate on the belt: the belt carries that one.
    private func ridingNode(_ crate: CrateRef) -> SCNNode? {
        simulation.cargo.first { $0.value.onBelt && $0.value.command.crate == crate }.flatMap { cargoNodes[$0.key] }
    }

    /// A crate as the rows draw it, for the belt to carry: its repository's colour, your straps, the light off.
    private func gateCrate(_ crate: CrateRef) -> SCNNode {
        let row = fleet.stations[crate.station]?.ledger[crate.repo, crate.number]
        let alien = row?.alien == true
        let color = alien ? Palette.alien.darker(0.3) : NSColor(fleet.color(forRepo: crate.repo))
        return Props.package(color: color, band: NSColor(rgb: (0.3, 0.32, 0.38)), size: 0.38,
                             mine: !alien && world.isMine(repo: crate.repo, number: crate.number))
    }

    /// The X-ray's verdict, heard once.
    func gateScanned(station: String, passed: Bool) {
        drone.ping(seed: passed ? 7 : 3)
        gates[station]?.reaction = (passed, clock)
    }

    /// Off the belt at one of its ends. Whoever set it on the belt takes it from here, the same crate
    /// they put down; one that came on the pallet waits there for the next free hands.
    func gateHandoff(station name: String, crate: CrateRef, from spot: Spot, passed: Bool, riding: Bool) {
        guard let gv = gates[name], let station = fleet.stations[name] else { return }
        let node = gv.moving?.key == crate.key ? gv.moving!.node : (crateNode(crate) ?? gateCrate(crate))
        gv.moving = nil
        if node.parent == nil { propRoot.addChildNode(node) }
        node.position = v3(spot.pos.x, spot.pos.y, spot.pos.z)
        guard !riding else { return }
        let command = world.carryFromGate(station: station, crate: crate, from: spot)
        carry(command, node: node, pastGate: passed) { [weak self] in
            guard let self else { return }
            node.removeFromParentNode()
            rebuildMarkers()
            refreshRockets()
        }
    }

    /// A crate carried through the arch by hand: onto the pad it passes green, or sets off the alarm when
    /// it is going up untested; out again it is scanned red.
    private func scanned(_ crate: CrateRef, station: Station, onto pad: Bool, gv: GateView, node: SCNNode) {
        let row = station.ledger[crate.repo, crate.number]
        let passes = row?.cleared == true || row?.alien == true || !world.workflow(repo: crate.repo).has(.cleared)
        let color: NSColor = pad && passes ? Props.passedLight : Props.scanRed
        // Going up untested sets off the alarm; coming back out, sent back by QA, sets off the same strobe,
        // and the operator puts its picture up crossed out.
        let alarm = !(pad && passes)
        gv.scan = (color, clock + (alarm ? 2.6 : 0.9), alarm)
        gv.reaction = (!alarm, clock)
        if !pad {
            drone.ping(seed: 3)
            let commits = world.works.find(repo: crate.repo, crate: crate.number)?.pulls.count ?? 0
            gv.screen?.geometry?.firstMaterial?.diffuse.contents = XRay.image(repo: crate.repo, number: crate.number,
                                                                               commits: max(2, commits * 2 + crate.number % 4), sentBack: true)
            gv.showing = crate.key + " back"
        }
        if let plate = node.childNodes.first(where: { $0.geometry?.name == Props.plateName }) {
            plate.removeAllActions()
            plate.opacity = 1
            plate.geometry?.firstMaterial?.diffuse.contents = pad ? color : NSColor(rgb: (0.3, 0.32, 0.38))
        }
        if alarm {
            drone.ping(seed: crate.number)
            logEvent("\(crate.repo) #\(crate.number) went through the gate untested")
        }
    }
}
