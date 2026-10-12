import AppKit
import SceneKit

final class ShuttleView {
    let node: SCNNode
    let hull: SCNNode
    var yaw: Double
    var pitch = 0.0, bank = 0.0
    var posedByLook = false
    init(node: SCNNode, hull: SCNNode, yaw: Double) { self.node = node; self.hull = hull; self.yaw = yaw }
}

final class RocketView {
    var node: SCNNode
    var untestedShown: Bool
    var panelsShown: Int
    var bornAt: Double
    var flying: [Int: Double] = [:]
    var paintedNode: SCNNode?
    var weldedShown = 0
    var hot: [Int: Double] = [:]
    var stripping: [Int: Double] = [:]
    init(node: SCNNode, untested: Bool, panels: Int, at clock: Double) {
        self.node = node; untestedShown = untested; panelsShown = panels; bornAt = clock
    }
}

struct Spark {
    let node: SCNNode
    var vel: SIMD3<Double>
    let born: Double
    let life: Double
}

enum Hull {
    static let white = NSColor(rgb: (0.92, 0.92, 0.95))
    static let bare = NSColor(rgb: (0.48, 0.5, 0.55))
    static let hot = NSColor(rgb: (1.0, 0.52, 0.14))
    static let glow = NSColor(rgb: (0.95, 0.38, 0.06))
    static let cooling = 2.5
    static let flight = 0.6
    static let sparkShape: SCNGeometry = {
        let g = SCNBox(width: 0.016, height: 0.016, length: 0.016, chamferRadius: 0)
        let m = flat(NSColor(rgb: (1.0, 0.88, 0.5)))
        m.emission.contents = NSColor(rgb: (1.0, 0.75, 0.3))
        g.firstMaterial = m
        return g
    }()
}

extension StationController {
    // MARK: shuttles

    private func shuttle(color: NSColor) -> SCNNode { Looks.current.shuttle(color: color) }

    func drawShuttles(dt: Double) {
        var live = Set<ObjectIdentifier>()
        for f in simulation.flights {
            guard let station = fleet.stations[f.station], let anchor = hangarAnchors[f.station] else { continue }
            let id = ObjectIdentifier(f)
            live.insert(id)
            let hc = station.hangarCenter
            let v = shuttleViews[id] ?? {
                let holder = SCNNode()
                let hull = shuttle(color: NSColor(fleet.color(forRepo: f.repo)))
                holder.addChildNode(hull)
                anchor.addChildNode(holder)
                let v = ShuttleView(node: holder, hull: hull, yaw: f.heading.map { atan2(-$0.z, $0.x) } ?? 0)
                shuttleViews[id] = v
                return v
            }()
            let leg = ShipLeg(phase: f.phaseKind, progress: f.progress(at: clock), slot: SIMD2(f.down.x, f.down.z), side: f.exit.x >= f.down.x ? 1 : -1)
            if let pose = Looks.current.shipPose(leg) {
                v.node.position = v3(pose.pos.x - hc.x, pose.pos.y, pose.pos.z - hc.y)
                v.node.eulerAngles = SCNVector3(0, pose.yaw, 0)
                v.hull.eulerAngles = SCNVector3(0, 0, 0)
                v.posedByLook = true
                continue
            }
            v.posedByLook = false
            v.node.position = v3(f.pos.x - hc.x, f.pos.y, f.pos.z - hc.y)
            var wantPitch = 0.0
            if let h = f.heading {
                let flat = (h.x * h.x + h.z * h.z).squareRoot()
                let want = atan2(-h.z, h.x)
                var turn = (want - v.yaw).truncatingRemainder(dividingBy: 2 * .pi)
                if turn > .pi { turn -= 2 * .pi } else if turn < -.pi { turn += 2 * .pi }
                let step = max(-2.6 * dt, min(2.6 * dt, turn))
                v.yaw += step
                v.bank += (max(-0.5, min(0.5, -step / max(dt, 1e-3) * 0.22)) - v.bank) * min(1, dt * 5)
                wantPitch = max(-0.85, min(0.85, atan2(h.y, max(flat, 1e-4))))
            } else {
                v.bank += (0 - v.bank) * min(1, dt * 4)
            }
            v.pitch += (wantPitch - v.pitch) * min(1, dt * 4)
            v.node.eulerAngles = SCNVector3(0, CGFloat(v.yaw), 0)
            v.hull.eulerAngles = SCNVector3(CGFloat(v.bank), 0, CGFloat(v.pitch))
        }
        for (id, v) in shuttleViews where !live.contains(id) {
            v.node.removeFromParentNode()
            shuttleViews[id] = nil
        }
    }

    func crateOrdered(key: String, station name: String, slot: Int, repo: String) {
        guard let station = fleet.stations[name], let anchor = hangarAnchors[name], slot < station.hangarSlots.count else { return }
        let local = station.hangarSlots[slot] - station.hangarCenter
        let color = station.rooms[String(key.dropFirst(name.count + 1))]?.color ?? fleet.color(forRepo: repo)
        let box = Looks.current.crate(color: NSColor(color)) ?? Props.crate(color: NSColor(color))
        box.position = v3(local.x, 0.09, local.y)
        box.opacity = 0
        box.name = "room:" + key
        anchor.addChildNode(box)
        boxes[key] = box
    }

    func crateDropped(key: String, station name: String, slot: Int) {
        guard let station = fleet.stations[name], let box = boxes[key], slot < station.hangarSlots.count else { return }
        let local = station.hangarSlots[slot] - station.hangarCenter
        box.opacity = 1
        box.position = v3(local.x, 0.42, local.y)
        moveCrate(box, legs: [MotionLeg(to: SIMD3(local.x, 0.09, local.y), seconds: 0.5, ease: .easeIn)])
    }

    // MARK: rockets

    func padPosition(station: Station, slot: Int) -> SCNVector3 {
        let slots = world.padSlots(station: station)
        let pc = slots[slot % slots.count]
        return v3(station.offset.x + pc.x, 0, station.offset.y + pc.y)
    }
    func padSlot(station: Station, key: String) -> Int { world.padSlotOf[key] ?? 0 }

    private func rocketNode(station: Station, _ r: RocketJob, slot: Int) -> SCNNode {
        let color = NSColor(fleet.color(forRepo: r.repo))
        let n = Looks.current.rocket(color: color, tall: r.tall, cargo: r.cargo)
        Props.shape(n, lifter: r.kick == .docked, panels: r.panels)
        if r.untested, let own = Looks.current.hold(tall: r.kick == .docked) { own.name = "hold"; n.addChildNode(own) }
        n.position = padPosition(station: station, slot: slot)
        n.name = r.label
        n.enumerateChildNodes { c, _ in if c.name != "flame" && c.name != "hold" { c.name = r.label } }
        rocketRoot.addChildNode(n)
        n.opacity = 0
        return n
    }

    func drawRockets() {
        for (key, r) in simulation.rockets {
            guard let st = fleet.stations[r.station] else { continue }
            let slot = padSlot(station: st, key: key)
            guard let v = rocketViews[key] else {
                rocketViews[key] = RocketView(node: rocketNode(station: st, r, slot: slot), untested: r.untested, panels: r.panels, at: clock)
                continue
            }
            if v.node.opacity < 1, !v.node.hasActions { v.node.opacity = CGFloat(min(1, (clock - v.bornAt) / 1.2)) }
            weld(r, v)
            paintHull(r, v)
            signal(r, v)
            placeKick(r, v, station: st)
            vent(r, v)
            guard r.stage.rank < 3, !v.node.hasActions else { continue }
            if r.untested != v.untestedShown {
                let position = v.node.position
                v.node.removeFromParentNode()
                v.node = rocketNode(station: st, r, slot: slot)
                v.node.opacity = 1
                v.flying = [:]
                v.node.position = position
                v.untestedShown = r.untested
                v.panelsShown = r.panels
            } else if v.node.name != r.label {
                v.node.name = r.label
                v.node.enumerateChildNodes { c, _ in if c.name != "flame" && c.name != "hold" { c.name = r.label } }
            }
            if world.padSlotOf[key] != nil { v.node.position = padPosition(station: st, slot: slot) }
        }
    }

    private func weld(_ r: RocketJob, _ v: RocketView) {
        guard let tip = Props.part(v.node, "tip") else { return }
        func piece(_ name: String) -> SCNNode? { tip.childNodes.first { ($0.value(forKey: "part") as? String) == name } }
        if r.panels > v.panelsShown {
            for i in v.panelsShown..<r.panels { v.flying[i] = clock + Double(i - v.panelsShown) * 0.15 }
        } else if r.panels < v.panelsShown {
            Props.shape(v.node, lifter: r.kick == .docked, panels: r.panels)
            v.flying = [:]
        }
        v.panelsShown = r.panels
        let flight = Hull.flight
        let welder = simulation.drones[r.station]?.first { $0.task == .weld(r.key) }
        let source = welder.map { tip.convertPosition(v3($0.pos.x, $0.pos.y, $0.pos.z), from: nil) }
        for (i, at) in v.flying {
            guard let panel = piece("panel\(i)"), let rest = panel.value(forKey: "rest") as? SCNVector3 ?? {
                let p = panel.position; panel.setValue(p, forKey: "rest"); return p }() else { continue }
            let t = (clock - at) / flight
            panel.isHidden = t < 0
            let from = source.map { SIMD3(Double($0.x), Double($0.y), Double($0.z)) } ?? SIMD3(0, 1.8 - Double(tip.position.y), 0)
            let to = SIMD3(Double(rest.x), Double(rest.y), Double(rest.z))
            let k = min(1, max(0, t)), e = k * k * (3 - 2 * k)
            let p = from + (to - from) * e + SIMD3(0, sin(k * .pi) * 0.15, 0)
            panel.position = v3(p.x, p.y, p.z)
            if t >= 1 { panel.position = rest; v.flying[i] = nil }
        }
        let whole = r.panels >= RocketGeometry.panels && v.flying.isEmpty
        for name in ["nose", "hatch", "port"] {
            for c in tip.childNodes where (c.value(forKey: "part") as? String) == name {
                if whole, c.isHidden { c.isHidden = false; c.setValue(clock, forKey: "on") }
                if let on = c.value(forKey: "on") as? Double {
                    let k = CGFloat(min(1, max(0.01, (clock - on) / 0.35)))
                    c.scale = SCNVector3(k, k, k)
                    if k >= 1 { c.setValue(nil, forKey: "on") }
                }
            }
        }
    }

    private func paintHull(_ r: RocketJob, _ v: RocketView) {
        guard let tip = Props.part(v.node, "tip") else { return }
        let done = Int(r.welded)
        func paint(_ i: Int, _ color: NSColor, glow: NSColor = .black) {
            guard let panel = tip.childNodes.first(where: { ($0.value(forKey: "part") as? String) == "panel\(i)" }) else { return }
            if panel.value(forKey: "paint") == nil {
                panel.geometry?.firstMaterial = (panel.geometry?.firstMaterial?.copy() as? SCNMaterial) ?? lit(Hull.white)
                panel.setValue(true, forKey: "paint")
            }
            panel.geometry?.firstMaterial?.diffuse.contents = color
            panel.geometry?.firstMaterial?.emission.contents = glow
        }
        if v.paintedNode !== v.node {
            v.paintedNode = v.node
            v.hot = [:]; v.stripping = [:]
            for i in 0..<RocketGeometry.panels { paint(i, i < done ? Hull.white : Hull.bare) }
            v.weldedShown = done
        }
        if done > v.weldedShown {
            for i in v.weldedShown..<done {
                let at = v.flying[i].map { $0 + Hull.flight } ?? clock
                v.hot[i] = at
                v.stripping[i] = nil
                if at > clock { paint(i, Hull.bare) }
            }
        } else if done < v.weldedShown {
            for i in done..<v.weldedShown { v.stripping[i] = clock + Double(v.weldedShown - 1 - i) * 0.04; v.hot[i] = nil }
        }
        v.weldedShown = done
        for (i, at) in v.stripping where clock >= at { paint(i, Hull.bare); v.stripping[i] = nil }
        for (i, at) in v.hot where clock >= at {
            let k = min(1, (clock - at) / Hull.cooling)
            paint(i, Hull.hot.blended(withFraction: CGFloat(k), of: Hull.white) ?? Hull.white,
                  glow: Hull.glow.blended(withFraction: CGFloat(k), of: .black) ?? .black)
            if k >= 1 { v.hot[i] = nil }
        }
    }

    private func signal(_ r: RocketJob, _ v: RocketView) {
        guard let ring = padRings[r.key] else { return }
        let color = NSColor(fleet.color(forRepo: r.repo))
        if r.welding {
            let flash = pow(max(0, cos((clock / 0.9).truncatingRemainder(dividingBy: 1) * 2 * .pi)), 4)
            ring.geometry?.firstMaterial?.diffuse.contents = Props.amberLampOff.blended(withFraction: CGFloat(0.3 + 0.7 * flash), of: Props.amberLamp)
            ring.opacity = 0.95
        } else if r.untested {
            let k = 0.5 + 0.5 * sin(clock * 2.2)
            ring.geometry?.firstMaterial?.diffuse.contents = Props.scanRed.blended(withFraction: CGFloat(0.3 * (1 - k)), of: .black)
            ring.opacity = CGFloat(0.55 + 0.4 * k)
        } else {
            ring.geometry?.firstMaterial?.diffuse.contents = color
            ring.opacity = 0.75
        }
    }

    private func vent(_ r: RocketJob, _ v: RocketView) {
        guard r.isVenting, Double.random(in: 0...1) < 0.3 else { return }
        let p = v.node.presentation.worldPosition
        let side = Bool.random() ? 1.0 : -1.0
        let out = SIMD3(0, 0, side)
        let at = SIMD3(Double(p.x), Double(p.y) + RocketGeometry.hullBase - 0.06, Double(p.z)) + out * (RocketGeometry.radius + 0.02)
        let burst = Double.random(in: 0...1) < 0.06 ? 4 : 1
        for _ in 0..<burst {
            let spread = SIMD3(Double.random(in: -0.15...0.15), Double.random(in: -0.05...0.2), 0)
            emitPuff(at: at, vel: (out + spread) * Double.random(in: 0.5...0.9), life: 0.7, grow: 3)
        }
    }

    func throwSparks(at seam: SCNVector3, from rocket: SCNNode, count: Int) {
        let out = SIMD2(Double(seam.x - rocket.position.x), Double(seam.z - rocket.position.z))
        let len = max(1e-3, (out.x * out.x + out.y * out.y).squareRoot()), dir = out / len
        for _ in 0..<count where sparks.count < 80 {
            let node = SCNNode(geometry: Hull.sparkShape)
            node.position = seam
            rocketRoot.addChildNode(node)
            let speed = Double.random(in: 0.25...0.8), across = Double.random(in: -0.35...0.35)
            let vel = SIMD3(dir.x * speed - dir.y * across, Double.random(in: -0.1...0.7), dir.y * speed + dir.x * across)
            sparks.append(Spark(node: node, vel: vel, born: clock, life: Double.random(in: 0.5...1.1)))
        }
    }

    func tickSparks(dt: Double) {
        for (i, var s) in sparks.enumerated().reversed() {
            let age = (clock - s.born) / s.life
            guard age < 1 else { s.node.removeFromParentNode(); sparks.remove(at: i); continue }
            s.vel.y -= 2.4 * dt
            var p = SIMD3(Double(s.node.position.x), Double(s.node.position.y), Double(s.node.position.z)) + s.vel * dt
            if p.y < 0.01 { p.y = 0.01; s.vel.y = abs(s.vel.y) * 0.3; s.vel.x *= 0.5; s.vel.z *= 0.5 }
            s.node.position = v3(p.x, p.y, p.z)
            s.node.opacity = CGFloat(age < 0.6 ? 1 : (1 - age) / 0.4)
            sparks[i] = s
        }
    }

    func seamPoint(_ r: RocketJob) -> SCNVector3? {
        guard let tip = rocketViews[r.key].flatMap({ Props.part($0.node, "tip") }),
              let seam = tip.childNodes.first(where: { ($0.value(forKey: "part") as? String) == "panel\(r.seam)" }) else { return nil }
        return seam.convertPosition(SCNVector3Zero, to: propRoot)
    }

    private func placeKick(_ r: RocketJob, _ v: RocketView, station: Station) {
        guard let tip = Props.part(v.node, "tip"), let stage = Props.part(v.node, "lifter") else { return }
        stage.isHidden = r.kick == .none
        if let foot = r.kickAt {
            let p = v.node.convertPosition(v3(foot.x, foot.y, foot.z), from: v.node.parent)
            stage.position = p
            let out = simd_distance(foot, simulation.kickDepot(station))
            stage.opacity = CGFloat(min(1, out / 1.5))
        } else {
            stage.position = SCNVector3Zero
            stage.opacity = 1
        }
        tip.position.y = CGFloat(RocketGeometry.tipDrop(lift: r.lift))
        Props.part(v.node, "cradle")?.isHidden = r.kick == .docked
    }

    func play(rocket cue: Cue) {
        switch cue {
        case .rocketLoading(let key):
            rocketViews[key]?.node.childNode(withName: "hold", recursively: false)?.removeFromParentNode()
        case .liftOff(let key):
            if let node = rocketViews[key]?.node {
                node.childNode(withName: "hold", recursively: false)?.removeFromParentNode()
                liftOff(node, repo: String(key.split(separator: "|", maxSplits: 1).last ?? ""))
            }
        case .steam:
            break
        case .rocketGone(let key):
            rocketViews.removeValue(forKey: key)?.node.removeFromParentNode()
        default: break
        }
    }

    func liftOff(_ node: SCNNode, repo: String) {
        let flying = (mission.map { $0.repo == repo && $0.ended == nil } ?? false) || queuedMissions.contains { $0.repo == repo && $0.ended == nil }
        if flying {
            node.runAction(.sequence([.fadeOut(duration: 0.6), .removeFromParentNode()]))
            return
        }
        drone.sweep(up: true)
        node.opacity = 1
        node.childNode(withName: "flame", recursively: false)?.opacity = 0
        undocking.append((node, clock))
        node.runAction(.sequence([Looks.current.launch(node), .removeFromParentNode()]))
    }

    func tickUndocking() {
        undocking.removeAll { clock - $0.since > 6 || $0.node.parent == nil }
        for u in undocking where Double.random(in: 0...1) < 0.35 {
            let side = Double.random(in: 0..<(2 * .pi))
            let out = SIMD3(sin(side), Double.random(in: -0.6 ... -0.1), cos(side))
            let p = u.node.presentation.worldPosition
            let at = SIMD3(Double(p.x), Double(p.y), Double(p.z)) + SIMD3(out.x * 0.2, 0.9 + Double.random(in: 0...0.5), out.z * 0.2)
            emitPuff(at: at, vel: out * 0.8, life: 0.5, grow: 2.4)
        }
    }

    func refreshRockets() {
        simulation.refreshRockets()
        rebuildPadHexes()
    }
}
