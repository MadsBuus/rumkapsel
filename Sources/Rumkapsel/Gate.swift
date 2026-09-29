// The gate between the deck and the pad: a scanner in the doorway and the security unit on its post
// beside it. Every crate carried through is scanned. Onto the pad it shrinks, packed for flight, and
// its plate goes green; back out it grows again. The scan is red for a crate whose clearance was taken
// back, and an alarm for one going up untested.

import AppKit
import SceneKit

/// The gate as the scene draws it, one per station.
final class GateView {
    let arch: SCNNode
    /// The bar of light under the lintel that the scan sweeps with.
    let beam: SCNNode?
    let unit: SCNNode
    /// The unit's one light: its eye and its scanner.
    let eye: SCNNode?
    /// Where the unit rests, and the way it faces when nobody comes: out over the deck.
    let post: SIMD3<Double>
    let restYaw: Double
    let bobPhase = Double.random(in: 0..<6.28)
    var yaw: Double
    /// The scan showing now, and until when; an alarm blinks.
    var scan: (color: NSColor, until: Double, alarm: Bool)?
    /// Crates waiting for the unit, by the gate or on their stack, by crate key; and the one in the air.
    var waiting: [String: SCNNode] = [:]
    var flying: SCNNode?

    init(arch: SCNNode, unit: SCNNode, post: SIMD3<Double>, restYaw: Double) {
        self.arch = arch; self.unit = unit; self.post = post; self.restYaw = restYaw; yaw = restYaw
        beam = arch.childNode(withName: "scan", recursively: true)
        eye = unit.childNode(withName: "eye", recursively: true)
    }
}

extension Props {
    /// A plate lit for a crate through the gate.
    static let passedLight = NSColor(rgb: (0.45, 0.95, 0.5))
    static let scanRed = NSColor(rgb: (1.0, 0.22, 0.2))
    static let scanIdle = NSColor(rgb: (0.35, 0.75, 0.95))

    /// The scanner arch: two posts and a lintel `width` apart along x, with the scan bar under the lintel,
    /// standing on the origin.
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
            stripe.geometry!.firstMaterial = flat(NSColor(rgb: (0.95, 0.7, 0.15)))
            stripe.position = v3(side * (width / 2 + 0.05), 0.12, 0)
            n.addChildNode(stripe)
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

    /// The security unit: a flat-sided body that hovers, one light across its face (+z), stubby side
    /// plates, standing on the origin at its hover height.
    static func securityUnit() -> SCNNode {
        let n = SCNNode()
        let shell = lit(NSColor(rgb: (0.34, 0.37, 0.45))), trim = flat(NSColor(rgb: (0.95, 0.7, 0.15)))
        let body = SCNNode(geometry: SCNBox(width: 0.2, height: 0.2, length: 0.16, chamferRadius: 0))
        body.geometry!.firstMaterial = shell
        body.position = v3(0, 0.1, 0)
        n.addChildNode(body)
        let cap = SCNNode(geometry: SCNBox(width: 0.16, height: 0.04, length: 0.12, chamferRadius: 0))
        cap.geometry!.firstMaterial = lit(NSColor(rgb: (0.24, 0.26, 0.32)))
        cap.position = v3(0, 0.22, 0)
        n.addChildNode(cap)
        let band = SCNNode(geometry: SCNBox(width: 0.204, height: 0.03, length: 0.164, chamferRadius: 0))
        band.geometry!.firstMaterial = trim
        band.position = v3(0, 0.035, 0)
        n.addChildNode(band)
        let eye = SCNNode(geometry: SCNBox(width: 0.13, height: 0.035, length: 0.012, chamferRadius: 0))
        eye.geometry!.firstMaterial = flat(scanIdle)
        eye.name = "eye"
        eye.position = v3(0, 0.14, 0.083)
        n.addChildNode(eye)
        for side in [-1.0, 1.0] {
            let plate = SCNNode(geometry: SCNBox(width: 0.03, height: 0.1, length: 0.1, chamferRadius: 0))
            plate.geometry!.firstMaterial = shell
            plate.position = v3(side * 0.12, 0.1, 0)
            n.addChildNode(plate)
        }
        return n
    }
}

extension StationController {
    /// How high the unit hovers, and how near a carrier comes before it turns to look.
    private static let unitHover = 0.28, unitWatch = 2.6

    /// The gate for a station, built with the static floor: the arch in the doorway onto the pad and the
    /// unit on its post. Nothing where the station has no deck beside its pad.
    func buildGate(_ station: Station) {
        gates[station.name]?.unit.removeFromParentNode()
        gates[station.name] = nil
        guard world.deckInUse(station: station.name), let g = station.gate, let post = station.securityPost else { return }
        let arch = Looks.current.gate(width: g.width) ?? Props.securityGate(width: g.width)
        // The arch spans along its x: turned so that x runs along the gate's line.
        arch.eulerAngles.y = CGFloat(atan2(g.inward.x, g.inward.y))
        arch.position = v3(station.offset.x + g.center.x, 0, station.offset.y + g.center.y)
        arch.name = "station:" + station.name
        staticRoot.addChildNode(arch)
        let unit = Looks.current.securityUnit() ?? Props.securityUnit()
        unit.name = "gate:" + station.name
        propRoot.addChildNode(unit)
        let rest = atan2(-g.inward.x, -g.inward.y)
        let at = SIMD3(station.offset.x + Double(post.x), StationController.unitHover, station.offset.y + Double(post.y))
        gates[station.name] = GateView(arch: arch, unit: unit, post: at, restYaw: rest)
    }

    /// One frame of every gate: crates shrink or grow as they cross, a crossing is scanned, and the unit
    /// hovers, turns to whoever comes near, and shows the scan.
    func tickGates(dt: Double) {
        for (name, gv) in gates {
            guard let station = fleet.stations[name], let g = station.gate else { continue }
            let pad = Set(station.padCells)
            var nearest: (d: Double, at: SIMD2<Double>)?
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
                let d = simd_distance(m.pos, g.center)
                if d < StationController.unitWatch, d < (nearest?.d ?? .infinity) { nearest = (d, m.pos) }
            }
            if let job = simulation.gates[name] { drawJob(job, gv: gv, station: station, idle: nearest?.at, dt: dt) }
            else { drawUnit(gv, station: station, watching: nearest?.at, dt: dt) }
        }
    }

    /// The unit at work, where the simulation has it; the crates waiting for it; the one in the air.
    private func drawJob(_ job: GateJob, gv: GateView, station: Station, idle watching: SIMD2<Double>?, dt: Double) {
        if case .rest = job.phase, job.waiting.isEmpty, job.ejecting.isEmpty,
           simd_distance(job.unit, gv.post) < 0.05 {
            drawUnit(gv, station: station, watching: watching, dt: dt)
        } else {
            let bob = sin(clock * 7.3 + gv.bobPhase) * 0.015
            gv.unit.position = v3(job.unit.x, job.unit.y + bob, job.unit.z)
            let turn = atan2(sin(job.yaw - gv.yaw), cos(job.yaw - gv.yaw))
            gv.yaw += turn * min(1, dt * 10)
            gv.unit.eulerAngles.y = CGFloat(gv.yaw)
            var light = Props.scanIdle
            if case .inspecting = job.phase { light = clock.truncatingRemainder(dividingBy: 0.25) < 0.125 ? .white : Props.scanIdle }
            if let s = gv.scan, clock <= s.until { light = s.color }
            gv.eye?.geometry?.firstMaterial?.diffuse.contents = light
            gv.beam?.geometry?.firstMaterial?.diffuse.contents = light == Props.scanIdle ? Props.scanIdle.darker(0.4) : light
        }
        // What waits: by the gate crate-sized, on its stack small.
        var want: [String: (SIMD3<Double>, Double, CrateRef)] = [:]
        for w in job.waiting where w.crate != job.busyWith || { if case .inspecting = job.phase { return true }; return false }() {
            want[w.crate.key] = (w.at, 1, w.crate)
        }
        for w in job.ejecting { want[w.crate.key] = (w.at, Station.testedScale, w.crate) }
        for (key, node) in gv.waiting where want[key] == nil { node.removeFromParentNode(); gv.waiting[key] = nil }
        for (key, w) in want where gv.waiting[key] == nil {
            let node = gateCrate(w.2, small: w.1 < 1)
            node.position = v3(w.0.x, w.0.y, w.0.z)
            propRoot.addChildNode(node)
            gv.waiting[key] = node
        }
        if case .carrying(let f) = job.phase, let node = gv.flying {
            let p = f.position(at: clock)
            node.position = v3(p.pos.x, p.pos.y, p.pos.z)
            let k = CGFloat(p.scale)
            node.scale = SCNVector3(k, k, k)
        }
    }

    /// A crate as the rows draw it, for the gate to hold: its repository's colour, your straps, the light off.
    private func gateCrate(_ crate: CrateRef, small: Bool) -> SCNNode {
        let row = fleet.stations[crate.station]?.ledger[crate.repo, crate.number]
        let alien = row?.alien == true
        let color = alien ? Palette.alien.darker(0.3) : NSColor(fleet.color(forRepo: crate.repo))
        let band = small ? Props.passedLight : NSColor(rgb: (0.3, 0.32, 0.38))
        let node = Props.package(color: color, band: band, size: 0.38, mine: !alien && world.isMine(repo: crate.repo, number: crate.number))
        if small { let k = CGFloat(Station.testedScale); node.scale = SCNVector3(k, k, k) }
        return node
    }

    /// The unit's verdict, shown on its eye and the arch.
    func gateScanned(station: String, passed: Bool) {
        guard let gv = gates[station] else { return }
        gv.scan = (passed ? Props.passedLight : Props.scanRed, clock + 1.2, false)
        drone.ping(seed: passed ? 7 : 3)
    }

    /// A crate leaves the ground by the gate, or its stack, for the unit's float through.
    func gateLift(station: String, crate: CrateRef) {
        guard let gv = gates[station] else { return }
        let node = gv.waiting.removeValue(forKey: crate.key) ?? crateNode(crate) ?? gateCrate(crate, small: false)
        let at = node.worldPosition
        node.removeFromParentNode()
        node.position = at
        propRoot.addChildNode(node)
        if let plate = node.childNodes.first(where: { $0.geometry?.name == Props.plateName }),
           let s = gv.scan { plate.geometry?.firstMaterial?.diffuse.contents = s.color }
        gv.flying = node
        rebuildMarkers()
    }

    /// Down on its stack, or out on the untested row: the rows draw it from here.
    func gateLanded(station: String, crate: CrateRef) {
        guard let gv = gates[station] else { return }
        gv.flying?.removeFromParentNode()
        gv.flying = nil
        drone.thud()
        rebuildMarkers()
        refreshRockets()
    }

    /// A crate crossed the gate. Onto the pad it passes green, or sets off the alarm when it is going up
    /// untested; out again it is scanned red, its clearance taken back.
    private func scanned(_ crate: CrateRef, station: Station, onto pad: Bool, gv: GateView, node: SCNNode) {
        let row = station.ledger[crate.repo, crate.number]
        let passes = row?.cleared == true || row?.alien == true || !world.workflow(repo: crate.repo).has(.cleared)
        let color: NSColor = pad && passes ? Props.passedLight : Props.scanRed
        let alarm = pad && !passes
        gv.scan = (color, clock + (alarm ? 2.4 : 0.9), alarm)
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

    /// The unit: a slow hover on its post, turned to the nearest carrier near the gate, its eye the scan's
    /// colour while one shows, blinking for an alarm, and the arch's bar lit with it.
    private func drawUnit(_ gv: GateView, station: Station, watching: SIMD2<Double>?, dt: Double) {
        let bob = sin(clock * (2 * .pi / 2.1) + gv.bobPhase) * 0.025
        gv.unit.position = v3(gv.post.x, gv.post.y + bob, gv.post.z)
        var want = gv.restYaw
        if let at = watching {
            let d = SIMD2(station.offset.x + at.x - gv.post.x, station.offset.y + at.y - gv.post.z)
            if simd_length(d) > 0.05 { want = atan2(d.x, d.y) }
        }
        let turn = atan2(sin(want - gv.yaw), cos(want - gv.yaw))
        gv.yaw += turn * min(1, dt * 5)
        gv.unit.eulerAngles.y = CGFloat(gv.yaw)
        var light = Props.scanIdle, beam = Props.scanIdle.darker(0.4)
        if let s = gv.scan {
            if clock > s.until { gv.scan = nil }
            else {
                let on = !s.alarm || clock.truncatingRemainder(dividingBy: 0.4) < 0.2
                light = on ? s.color : s.color.darker(0.6)
                beam = light
            }
        }
        gv.eye?.geometry?.firstMaterial?.diffuse.contents = light
        gv.beam?.geometry?.firstMaterial?.diffuse.contents = beam
    }
}
