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
    var heldShown: Bool
    var tallShown: Bool
    var cargoShown: Int
    var panelsShown: Int
    var flying: [Int: Double] = [:]
    var paintedNode: SCNNode?
    var weldedShown = 0
    var hot: [Int: Double] = [:]
    var stripping: [Int: Double] = [:]
    var lifted = false
    init(node: SCNNode, held: Bool, tall: Bool, cargo: Int, panels: Int) {
        self.node = node; heldShown = held; tallShown = tall; cargoShown = cargo; panelsShown = panels
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

    func crateOrdered(_ order: Int, station name: String, slot: Int, room: String, color: RGB) {
        guard let station = fleet.stations[name], let anchor = hangarAnchors[name], slot < station.hangarSlots.count else { return }
        let local = station.hangarSlots[slot] - station.hangarCenter
        let box = Looks.current.crate(color: NSColor(color)) ?? Props.crate(color: NSColor(color))
        box.position = v3(local.x, 0.09, local.y)
        box.opacity = 0
        box.name = "room:\(name)|\(room)"
        anchor.addChildNode(box)
        boxes[order] = box
    }

    func crateDropped(_ order: Int, station name: String, slot: Int) {
        guard let station = fleet.stations[name], let box = boxes[order], slot < station.hangarSlots.count else { return }
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

    private func load(_ st: Station, _ key: String, _ r: ShownRocket) -> Int {
        let id = String(key.dropFirst(st.name.count + 1))
        return st.facts.rockets[id]?.launched == true ? st.facts.aboard(id).count : st.facts.cargo(r.repo).count
    }

    private func rocketNode(station: Station, _ key: String, _ r: ShownRocket) -> SCNNode {
        let color = NSColor(fleet.color(forRepo: r.repo))
        let docked = r.dock >= 1
        let n = Looks.current.rocket(color: color, tall: docked, cargo: load(station, key, r))
        Props.nameRocket(n, repo: r.repo, color: color)
        if case .hotfix = r.kind { Props.paintNose(n, RocketShape.hotfixRed) }
        Props.shape(n, lifter: docked, panels: r.panels)
        if r.held, let own = Looks.current.hold(tall: docked) { own.name = "hold"; n.addChildNode(own) }
        n.position = padPosition(station: station, slot: r.slot)
        name(n, r.label)
        rocketRoot.addChildNode(n)
        n.opacity = 0
        return n
    }

    private func name(_ n: SCNNode, _ label: String) {
        n.name = label
        n.enumerateChildNodes { c, _ in if c.name != "flame" && c.name != "hold" { c.name = label } }
    }

    func drawRockets() {
        var live: Set<String> = []
        for st in fleet.stations.values {
            for (key, r) in simulation.shownRockets(st) {
                live.insert(key)
                let cargo = load(st, key, r)
                guard let v = rocketViews[key] else {
                    rocketViews[key] = RocketView(node: rocketNode(station: st, key, r), held: r.held, tall: r.dock >= 1, cargo: cargo, panels: r.panels)
                    continue
                }
                let reshaped = Looks.current.rocketFollowsLoad && (v.tallShown != (r.dock >= 1) || v.cargoShown != cargo)
                if r.held != v.heldShown || reshaped, r.climbing == nil {
                    let position = v.node.position, opacity = v.node.opacity
                    v.node.removeFromParentNode()
                    v.node = rocketNode(station: st, key, r)
                    v.node.position = position
                    v.node.opacity = opacity
                    v.flying = [:]
                    v.heldShown = r.held
                    v.tallShown = r.dock >= 1
                    v.cargoShown = cargo
                    v.panelsShown = r.panels
                } else if v.node.name != r.label, r.climbing == nil {
                    name(v.node, r.label)
                }
                weld(st, key, r, v)
                paintHull(r, v)
                signal(st, key, r, v)
                placeKick(r, v)
                vent(r, v)
                place(st, key, r, v)
            }
        }
        for (key, v) in rocketViews where !live.contains(key) {
            v.node.removeFromParentNode()
            rocketViews[key] = nil
        }
        let pads = live.map { "\($0):\(simulation.shownRocket($0)?.rocket.slot ?? -1)" }.sorted().joined(separator: ",")
        if pads != padsDrawn { rebuildPadHexes() }
    }

    private func place(_ st: Station, _ key: String, _ r: ShownRocket, _ v: RocketView) {
        let pad = padPosition(station: st, slot: r.slot)
        guard let at = r.climbing else {
            v.node.position = pad
            let leaving = r.leaving.map { 1 - (clock - $0) / ShownRocket.fadeSeconds } ?? 1
            v.node.opacity = CGFloat(max(0, min(1, (clock - r.since) / 1.2, leaving)))
            return
        }
        if !v.lifted, !v.node.isHidden {
            drone.sweep(up: true)
            undocking.append((v.node, at, nil))
        }
        v.lifted = true
        pose(v.node, at: pad, t: clock - at)
    }

    func pose(_ node: SCNNode, at from: SCNVector3, t: Double) {
        let p = Looks.current.launch(at: t)
        node.position = SCNVector3(from.x + CGFloat(p.offset.x), from.y + CGFloat(p.offset.y), from.z + CGFloat(p.offset.z))
        node.opacity = CGFloat(p.opacity)
        node.childNode(withName: "flame", recursively: true)?.opacity = CGFloat(p.flame)
    }

    private func weld(_ st: Station, _ key: String, _ r: ShownRocket, _ v: RocketView) {
        guard let tip = Props.part(v.node, "tip") else { return }
        func piece(_ name: String) -> SCNNode? { tip.childNodes.first { ($0.value(forKey: "part") as? String) == name } }
        if r.panels > v.panelsShown {
            for i in v.panelsShown..<r.panels { v.flying[i] = clock + Double(i - v.panelsShown) * 0.15 }
        } else if r.panels < v.panelsShown {
            Props.shape(v.node, lifter: r.dock >= 1, panels: r.panels)
            v.flying = [:]
        }
        v.panelsShown = r.panels
        let flight = Hull.flight
        let welder = simulation.drones[st.name]?.first { $0.task == .weld(key) }
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
        for name in ["nose", "hatch", "name", "rcs"] {
            for c in tip.childNodes where (c.value(forKey: "part") as? String) == name {
                if whole, c.isHidden { c.isHidden = false; c.setValue(clock, forKey: "on") }
                if let on = c.value(forKey: "on") as? Double {
                    let k = CGFloat(min(1, max(0, (clock - on) / 0.35)))
                    c.opacity = k
                    if k >= 1 { c.setValue(nil, forKey: "on") }
                }
            }
        }
    }

    private func paintHull(_ r: ShownRocket, _ v: RocketView) {
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

    private func signal(_ st: Station, _ key: String, _ r: ShownRocket, _ v: RocketView) {
        guard let ring = padRings[key] else { return }
        let progress = r.welding ? st.facts.staging[r.repo]?.progress(at: now) : nil
        stagingWhole(st, r, v)
        noseLamp(st, r, v, progress: progress)
        let beat = r.kind == .release ? stagingBeat(station: st.name, repo: r.repo) : nil
        let flash = beat.map { $0.live ? max(0, 1 - (clock - $0.at) / StagingBeat.flash) : 0 } ?? 0
        let color = NSColor(fleet.color(forRepo: r.repo)).blended(withFraction: CGFloat(flash), of: .white) ?? NSColor(fleet.color(forRepo: r.repo))
        ring.geometry?.firstMaterial?.diffuse.contents = color
        if var strip = padStrips[key] {
            strip.node.isHidden = progress == nil
            if let p = progress {
                let shown = min(1, (p * 200).rounded() / 200)
                if strip.shown != shown {
                    strip.node.geometry = StationController.hexStrip(fraction: shown, inner: Hall.padRadius - 0.075, outer: Hall.padRadius + 0.012)
                    let m = flat(color); m.isDoubleSided = true
                    strip.node.geometry?.firstMaterial = m
                    strip.shown = shown
                    padStrips[key] = strip
                }
                let beat = p < 1 ? 0.0 : pow(max(0, cos((clock * (p > StagingFact.late ? 3 : 1.2)).truncatingRemainder(dividingBy: 1) * 2 * .pi)), 2)
                strip.node.opacity = CGFloat(1 - 0.6 * beat)
            }
        }
        if progress != nil {
            ring.opacity = 0.3
        } else if flash > 0 {
            ring.opacity = CGFloat(0.75 + 0.25 * flash)
        } else if r.held {
            ring.opacity = CGFloat(0.5 + 0.25 * sin(clock * 1.3))
        } else {
            ring.opacity = 0.75
        }
    }

    private func vent(_ r: ShownRocket, _ v: RocketView) {
        guard r.venting, Double.random(in: 0...1) < 0.3 else { return }
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

    func seamPoint(_ key: String, panel: Int) -> SCNVector3? {
        guard let tip = rocketViews[key].flatMap({ Props.part($0.node, "tip") }),
              let seam = tip.childNodes.first(where: { ($0.value(forKey: "part") as? String) == "panel\(panel)" }) else { return nil }
        return seam.convertPosition(SCNVector3Zero, to: propRoot)
    }

    private func placeKick(_ r: ShownRocket, _ v: RocketView) {
        guard let tip = Props.part(v.node, "tip"), let stage = Props.part(v.node, "lifter") else { return }
        stage.isHidden = r.dock <= 0
        stage.position = v3(0, RocketGeometry.deck(dock: r.dock), 0)
        tip.position.y = CGFloat(r.tipOffset)
        RocketShape.fold(tip, RocketGeometry.fold(dock: r.dock))
        RocketShape.showLegs(tip, r.dock < 1)
    }

    func tickUndocking() {
        for u in undocking {
            guard let from = u.from else { continue }
            let t = clock - u.since
            if t >= Looks.current.launchSeconds { u.node.removeFromParentNode() } else { pose(u.node, at: from, t: t) }
        }
        undocking.removeAll { $0.node.parent == nil || ($0.from == nil && clock - $0.since > 6) }
        for u in undocking where clock - u.since <= 6 && Double.random(in: 0...1) < 0.35 {
            let side = Double.random(in: 0..<(2 * .pi))
            let out = SIMD3(sin(side), Double.random(in: -0.6 ... -0.1), cos(side))
            let p = u.node.presentation.worldPosition
            let at = SIMD3(Double(p.x), Double(p.y), Double(p.z)) + SIMD3(out.x * 0.2, 0.9 + Double.random(in: 0...0.5), out.z * 0.2)
            emitPuff(at: at, vel: out * 0.8, life: 0.5, grow: 2.4)
        }
    }

    func refreshRockets() { rebuildPadHexes() }
}
