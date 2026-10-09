// The shuttles and the rockets as the scene draws them: a ship node per flight, placed where the
// simulation's `Flight` says; a rocket node per `RocketJob`, sized to its pile while it stands by,
// lifting off with flame and steam when the simulation says so. Nothing here decides anything.

import AppKit
import SceneKit

/// The node for one flight: the ship hung under a node that carries the heading, so the hull may pitch
/// and bank inside it, and the nose it is turned to this instant.
final class ShuttleView {
    let node: SCNNode
    let hull: SCNNode
    var yaw: Double
    var pitch = 0.0, bank = 0.0
    /// Set while a look is drawing this ship's path itself, so nothing judges the nose the scene did not turn.
    var posedByLook = false
    init(node: SCNNode, hull: SCNNode, yaw: Double) { self.node = node; self.hull = hull; self.yaw = yaw }
}

/// The node for one rocket, and what it was drawn for, so it is only redrawn when that changes.
final class RocketView {
    var node: SCNNode
    var untestedShown: Bool
    /// The tip's panels drawn so far, and whether the lifter is under it.
    var panelsShown: Int
    var lifterShown: Bool
    /// Whether the lifter was under the tip when the tower was stood, which sets its arm's height.
    var towerLifter: Bool
    /// On the station clock, like everything else that moves: when it came, the panels in the air and
    /// when each set off, and the lifter coming up or going down.
    var bornAt: Double
    var flying: [Int: Double] = [:]
    var rise: (up: Bool, since: Double)?
    /// The hull's paint: the node it was put on, how far the weld had come, the panels glowing from the
    /// torch and since when, and those stripped bare for a weld afresh and when.
    var paintedNode: SCNNode?
    var weldedShown = 0
    var hot: [Int: Double] = [:]
    var stripping: [Int: Double] = [:]
    /// The tower's beacon and its light as the rocket's own state has it, put back once the weld is over.
    var beaconRest: (beacon: SCNNode, material: SCNMaterial?)?
    init(node: SCNNode, untested: Bool, panels: Int, lifter: Bool, at clock: Double) {
        self.node = node; untestedShown = untested; panelsShown = panels; lifterShown = lifter; towerLifter = lifter; bornAt = clock
    }
}

/// A spark off the torch, in the air.
struct Spark {
    let node: SCNNode
    var vel: SIMD3<Double>
    let born: Double
    let life: Double
}

/// The paint of a tip's hull while it is welded.
enum Hull {
    static let white = NSColor(rgb: (0.92, 0.92, 0.95))
    /// Bare metal, not yet welded.
    static let bare = NSColor(rgb: (0.48, 0.5, 0.55))
    /// Just welded: glowing, and cooling to white.
    static let hot = NSColor(rgb: (1.0, 0.52, 0.14))
    static let glow = NSColor(rgb: (0.95, 0.38, 0.06))
    static let cooling = 2.5
    /// How long a new panel takes to fly from the tower onto its place.
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

    /// The shuttle body, wings in a repo colour: the look's.
    private func shuttle(color: NSColor) -> SCNNode { Looks.current.shuttle(color: color) }

    /// Every ship in the air, where the simulation has it. Everything is parented to the hangar
    /// anchor, so a station shifting underneath does not misalign it; a flight that is over loses its node.
    /// The nose follows the line the ship is flying, turning onto it rather than snapping, and the hull
    /// pitches with the climb and banks into the turn.
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
                // A look that draws its own path says where the ship is and which way it points, and nothing else moves it.
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
                // The shortest way round to the new heading, at a rate a ship this size could turn at.
                var turn = (want - v.yaw).truncatingRemainder(dividingBy: 2 * .pi)
                if turn > .pi { turn -= 2 * .pi } else if turn < -.pi { turn += 2 * .pi }
                let step = max(-2.6 * dt, min(2.6 * dt, turn))
                v.yaw += step
                v.bank += (max(-0.5, min(0.5, -step / max(dt, 1e-3) * 0.22)) - v.bank) * min(1, dt * 5)
                wantPitch = max(-0.85, min(0.85, atan2(h.y, max(flat, 1e-4))))
            } else {
                v.bank += (0 - v.bank) * min(1, dt * 4)   // standing still: the wings come level
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

    /// A new office's crate, ordered: it lies unseen on its bay slot until the ship drops it.
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

    /// The ship set it down: the crate comes into view and settles onto the floor.
    func crateDropped(key: String, station name: String, slot: Int) {
        guard let station = fleet.stations[name], let box = boxes[key], slot < station.hangarSlots.count else { return }
        let local = station.hangarSlots[slot] - station.hangarCenter
        box.opacity = 1
        box.position = v3(local.x, 0.42, local.y)
        moveCrate(box, legs: [MotionLeg(to: SIMD3(local.x, 0.09, local.y), seconds: 0.5, ease: .easeIn)])
    }

    // MARK: rockets

    /// Where a rocket stands on the pad, by slot, as the pad is now.
    func padPosition(station: Station, slot: Int) -> SCNVector3 {
        let slots = world.padSlots(station: station)
        let pc = slots[slot % slots.count]
        return v3(station.offset.x + pc.x, 0, station.offset.y + pc.y)
    }
    /// A rocket's slot on its pad, by the world's one rule for who stands where.
    func padSlot(station: Station, key: String) -> Int { world.padSlotOf[key] ?? 0 }

    private func rocketNode(station: Station, _ r: RocketJob, slot: Int) -> SCNNode {
        let color = NSColor(fleet.color(forRepo: r.repo))
        let n = Looks.current.rocket(color: color, tall: r.tall, cargo: r.cargo)
        Props.shape(n, lifter: r.tall, panels: r.panels)
        // A look with a hold of its own shows it while the rocket is held; the classic pad stands its service
        // tower beside the rocket the whole time, the beacon lit while held.
        if let own = Looks.current.hold(tall: r.tall) {
            if r.untested { own.name = "hold"; n.addChildNode(own) }
        } else {
            Props.attachTower(to: n, tall: r.tall, held: r.untested)
        }
        n.position = padPosition(station: station, slot: slot)
        n.name = r.label
        n.enumerateChildNodes { c, _ in if c.name != "flame" && c.name != "hold" { c.name = r.label } }
        rocketRoot.addChildNode(n)
        n.opacity = 0   // it fades in on the station clock, in `drawRockets`
        return n
    }

    /// Every rocket on a pad, drawn for what the simulation says it is: a new one gets a node on the
    /// next slot; one standing by grows with what it will carry and stands where the pad is now; once
    /// it is loading it keeps the size it had, and the steam and the flame stay where they are.
    func drawRockets() {
        for (key, r) in simulation.rockets {
            guard let st = fleet.stations[r.station] else { continue }
            let slot = padSlot(station: st, key: key)
            guard let v = rocketViews[key] else {
                rocketViews[key] = RocketView(node: rocketNode(station: st, r, slot: slot), untested: r.untested, panels: r.panels, lifter: r.tall, at: clock)
                continue
            }
            // A rocket that was already standing there when the station came up fades in where it stands;
            // one going up has its own way of leaving and is left to it.
            if v.node.opacity < 1, !v.node.hasActions { v.node.opacity = CGFloat(min(1, (clock - v.bornAt) / 1.2)) }
            weld(r, v)
            paintHull(r, v)
            signal(r, v)
            stepLifter(v)
            // Going up from the cradle, with no time for the lifter to rise: it is simply there.
            if r.stage.rank >= 3, !v.lifterShown { v.lifterShown = true; Props.shape(v.node, lifter: true, panels: RocketGeometry.panels) }
            guard r.stage.rank < 3, !v.node.hasActions else { continue }
            if r.tall != v.lifterShown, v.rise == nil {
                v.lifterShown = r.tall
                v.rise = (r.tall, clock)
                continue
            }
            let moving = v.rise != nil
            // The tower was stood for the rocket as it was; once the lifter has come or gone its arm is
            // put back at the hatch.
            if r.untested != v.untestedShown || (!moving && v.towerLifter != v.lifterShown) {
                v.towerLifter = v.lifterShown
                let position = v.node.position
                v.node.removeFromParentNode()
                v.node = rocketNode(station: st, r, slot: slot)
                v.node.opacity = 1   // the same rocket redrawn, not one arriving: no fade
                v.flying = [:]
                v.node.position = position
                v.untestedShown = r.untested
                v.panelsShown = r.panels
                if r.stage.rank == 2 { addSteam(to: v.node) }   // redrawn mid-wait: it was venting, and still is
            } else if v.node.name != r.label {
                v.node.name = r.label
                v.node.enumerateChildNodes { c, _ in if c.name != "flame" && c.name != "hold" { c.name = r.label } }
            }
            // Standing by, a rocket stands where the pad is now: the floor may have grown under it. One that has
            // lost its slot stays where it stands rather than on somebody else's.
            if world.padSlotOf[key] != nil { v.node.position = padPosition(station: st, slot: slot) }
        }
    }

    /// The tip as it is built: each new panel flies across from the top of the tower onto its place, and
    /// the nose and the hatch go on with the last.
    private func weld(_ r: RocketJob, _ v: RocketView) {
        guard let tip = Props.part(v.node, "tip") else { return }
        func piece(_ name: String) -> SCNNode? { tip.childNodes.first { ($0.value(forKey: "part") as? String) == name } }
        if r.panels > v.panelsShown {
            for i in v.panelsShown..<r.panels { v.flying[i] = clock + Double(i - v.panelsShown) * 0.15 }
        } else if r.panels < v.panelsShown {
            Props.shape(v.node, lifter: v.lifterShown, panels: r.panels)
            v.flying = [:]
        }
        v.panelsShown = r.panels
        // In the air: from the top of the tower, over and down onto its place.
        let flight = Hull.flight
        for (i, at) in v.flying {
            guard let panel = piece("panel\(i)"), let rest = panel.value(forKey: "rest") as? SCNVector3 ?? {
                let p = panel.position; panel.setValue(p, forKey: "rest"); return p }() else { continue }
            let t = (clock - at) / flight
            panel.isHidden = t < 0
            let from = SIMD3(0.44, 1.8 - Double(tip.position.y), 0.02), to = SIMD3(Double(rest.x), Double(rest.y), Double(rest.z))
            let k = min(1, max(0, t)), e = k * k * (3 - 2 * k)
            let p = from + (to - from) * e + SIMD3(0, sin(k * .pi) * 0.15, 0)
            panel.position = v3(p.x, p.y, p.z)
            if t >= 1 { panel.position = rest; v.flying[i] = nil }
        }
        // With the last panel home, the nose, the hatch and the portholes go on.
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

    /// The hull as far as the weld has come: panels it has passed are white, each glowing hot as it is done
    /// and cooling, the rest bare metal. A tip welded over afresh is stripped bare from the top down.
    private func paintHull(_ r: RocketJob, _ v: RocketView) {
        guard let tip = Props.part(v.node, "tip") else { return }
        let done = Int(r.welded)
        func paint(_ i: Int, _ color: NSColor, glow: NSColor = .black) {
            guard let panel = tip.childNodes.first(where: { ($0.value(forKey: "part") as? String) == "panel\(i)" }) else { return }
            if panel.value(forKey: "paint") == nil {
                panel.geometry?.firstMaterial = (panel.geometry?.firstMaterial?.copy() as? SCNMaterial) ?? lit(Hull.white)   // its own paint, not its neighbours'
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
            // Done as it lands, for a panel still in the air.
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

    /// The tower's beacon while the tip is welded: a turning amber light, flashing as it comes round. After,
    /// it is what the rocket's own state makes it.
    private func signal(_ r: RocketJob, _ v: RocketView) {
        var found: SCNNode?
        v.node.childNode(withName: "hold", recursively: false)?.enumerateChildNodes { c, stop in
            if c.value(forKey: "beacon") != nil { found = c; stop.pointee = true }
        }
        guard let beacon = found else { return }
        let lamp = beacon.childNode(withName: "beaconLight", recursively: false)
        guard r.welding else {
            if let rest = v.beaconRest, rest.beacon === beacon { beacon.geometry?.firstMaterial = rest.material }
            v.beaconRest = nil
            lamp?.removeFromParentNode()
            return
        }
        if v.beaconRest?.beacon !== beacon {
            v.beaconRest = (beacon, beacon.geometry?.firstMaterial)
            beacon.geometry?.firstMaterial = flat(Props.palletAmber)
        }
        let turn = (clock / 0.9).truncatingRemainder(dividingBy: 1)
        let flash = max(0, cos(turn * 2 * .pi))
        let bright = pow(flash, 6)
        beacon.geometry?.firstMaterial?.diffuse.contents = Props.palletAmberOff.blended(withFraction: CGFloat(0.4 + 0.6 * flash), of: Props.palletAmber)
        beacon.geometry?.firstMaterial?.emission.contents = NSColor.black.blended(withFraction: CGFloat(bright), of: Props.palletAmber)
        let l = lamp ?? {
            let l = SCNNode()
            l.name = "beaconLight"
            l.light = SCNLight()
            l.light!.type = .omni
            l.light!.color = Props.palletAmber
            l.light!.attenuationEndDistance = 1.4
            beacon.addChildNode(l)
            return l
        }()
        l.light?.intensity = CGFloat(60 + 900 * bright)
    }

    /// A shower of sparks off the seam the torch is on: thrown out from the hull, falling, bouncing once off
    /// the pad and dying away, on the station clock.
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

    /// Every spark in the air, one frame on.
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

    /// Where the torch is on a rocket being welded: the seam panel, in the scene.
    func seamPoint(_ r: RocketJob) -> SCNVector3? {
        guard let tip = rocketViews[r.key].flatMap({ Props.part($0.node, "tip") }),
              let seam = tip.childNodes.first(where: { ($0.value(forKey: "part") as? String) == "panel\(r.seam)" }) else { return nil }
        return seam.convertPosition(SCNVector3Zero, to: propRoot)
    }

    /// A production release opened: the lifter comes up out of the pad under the tip and lifts it off
    /// its cradle, which folds away. Closed again, it goes back down and the tip settles on the cradle.
    private func stepLifter(_ v: RocketView) {
        guard let rise = v.rise else { return }
        guard let tip = Props.part(v.node, "tip"), let lifter = Props.part(v.node, "lifter") else { v.rise = nil; return }
        let base = (tip.value(forKey: "base") as? Double) ?? 0
        let low = RocketGeometry.cradleTop - base, deep = -(base + 0.2)
        let cradle = Props.part(v.node, "cradle")
        func ease(_ t: Double) -> Double { let k = min(1, max(0, t)); return k * k * (3 - 2 * k) }
        let t = (clock - rise.since) / 3.5
        // Up: the lifter climbs out of the pad; half way it meets the tip and carries it up to its place.
        // Down: the same the other way round.
        let k = rise.up ? t : 1 - t
        let lifterY = deep + (0 - deep) * ease(k)
        let tipY = low + (0 - low) * ease((k - 0.45) / 0.55)
        lifter.isHidden = false
        lifter.position.y = CGFloat(lifterY)
        tip.position.y = CGFloat(tipY)
        cradle?.isHidden = false
        cradle?.opacity = CGFloat(1 - ease((k - 0.6) / 0.3))
        guard t >= 1 else { return }
        v.rise = nil
        cradle?.opacity = 1
        lifter.position.y = 0
        Props.shape(v.node, lifter: rise.up, panels: v.panelsShown)
    }

    /// The simulation's word on a rocket, shown once: the hold's tape comes down, the flame goes on,
    /// the steam starts, the node goes with the rocket, or a crate goes in through the hatch.
    func play(rocket cue: Cue) {
        switch cue {
        case .rocketLoading(let key):
            // Cleared: a look's own hold comes down; the tower stays to load, its beacon goes dark.
            if let hold = rocketViews[key]?.node.childNode(withName: "hold", recursively: false) {
                if let beacon = hold.childNode(withName: "beacon", recursively: true) {
                    beacon.geometry?.firstMaterial = lit(NSColor(rgb: (0.38, 0.4, 0.45)))
                } else { hold.removeFromParentNode() }
            }
        case .liftOff(let key):
            if let node = rocketViews[key]?.node {
                // The tower is let go of the rocket a moment before the climb and stays on the pad.
                if let hold = node.childNode(withName: "hold", recursively: false) {
                    hold.removeFromParentNode()
                    hold.position = node.position
                    rocketRoot.addChildNode(hold)
                    hold.runAction(.sequence([.wait(duration: 6), .fadeOut(duration: 1.5), .removeFromParentNode()]))
                }
                liftOff(node, repo: String(key.split(separator: "|", maxSplits: 1).last ?? ""))
            }
        case .steam(let key):
            if let node = rocketViews[key]?.node {
                addSteam(to: node)
                // Loaded and ready: the swing arm comes off the hatch and folds back along the tower.
                node.childNode(withName: "arm", recursively: true)?.runAction(.rotateBy(x: 0, y: .pi / 2, z: 0, duration: 2))
            }
        case .rocketGone(let key):
            rocketViews.removeValue(forKey: key)?.node.removeFromParentNode()
        case .intoHold(let key, let command):
            // Through the hatch into the hold: up off the floor, in toward the hull, shrinking as it
            // goes, since the rocket is far too small for it. The hatch opens for it and closes after.
            guard let b = cargoNodes[command] else { return }
            let at = SIMD3(Double(b.position.x), Double(b.position.y), Double(b.position.z))
            guard let rocket = rocketViews[key]?.node, let hatch = rocket.childNode(withName: "hatch", recursively: true) else {
                moveCrate(b, legs: [MotionLeg(to: SIMD3(at.x, at.y + 0.22, at.z), seconds: 0.3, ease: .easeOut),
                                    MotionLeg(to: SIMD3(at.x, at.y + 0.22, at.z - 0.45), seconds: 0.6, ease: .easeIn, scale: 0.02)]) { b.removeFromParentNode() }
                return
            }
            // Up the tower and in through the hatch, shrinking as it goes: the rocket is far too small for it.
            let base = SIMD3(Double(rocket.position.x), Double(rocket.position.y), Double(rocket.position.z))
            let towerX = rocket.childNode(withName: "tower", recursively: true).map { Double($0.position.x) } ?? 0.44
            let hatchAt = SIMD3(Double(hatch.position.x), Double(hatch.position.y), Double(hatch.position.z))
            let foot = SIMD3(base.x + towerX - 0.1, at.y + 0.1, base.z + 0.02)
            let top = SIMD3(foot.x, base.y + hatchAt.y - 0.06, foot.z)
            let door = base + hatchAt
            // The door opens on the hold's black as the crate reaches it, and closes white behind it.
            if let door = hatch.childNode(withName: "door", recursively: false) {
                let shut = door.geometry?.firstMaterial
                let open = flat(NSColor(rgb: (0.04, 0.04, 0.05)))
                door.runAction(.sequence([.wait(duration: 1.2), .run { $0.geometry?.firstMaterial = open },
                                          .wait(duration: 0.9), .run { $0.geometry?.firstMaterial = shut }]))
            } else {
                hatch.runAction(.sequence([.wait(duration: 1.3), .scale(to: 0.05, duration: 0.2), .wait(duration: 0.6), .scale(to: 1, duration: 0.2)]))
            }
            moveCrate(b, legs: [MotionLeg(to: foot, seconds: 0.4, ease: .easeOut, scale: 0.3),
                                MotionLeg(to: top, seconds: 0.9, ease: .easeInOut, scale: 0.3),
                                MotionLeg(to: door, seconds: 0.6, ease: .linear, scale: 0.05)]) { b.removeFromParentNode() }
        default: break
        }
    }

    /// Flame on, a slow climb that carries the rocket out of the frame, then gone. A rocket whose flight is
    /// already on screen is that flight: it leaves the pad quietly rather than lifting off a second time.
    func liftOff(_ node: SCNNode, repo: String) {
        scorch(at: node.position)
        let flying = (mission.map { $0.repo == repo && $0.ended == nil } ?? false) || queuedMissions.contains { $0.repo == repo && $0.ended == nil }
        if flying {
            node.runAction(.sequence([.fadeOut(duration: 0.6), .removeFromParentNode()]))
            return
        }
        drone.sweep(up: true)
        node.opacity = 1
        node.childNode(withName: "flame", recursively: false)?.opacity = 1
        node.runAction(.sequence([Looks.current.launch(node), .removeFromParentNode()]))
    }

    /// The blast's soot on the pad where a rocket stood: dark for a good while, then fading out.
    func scorch(at p: SCNVector3) {
        let key = "\(Int((p.x * 10).rounded())),\(Int((p.z * 10).rounded()))"
        if let fresh = scorches[key], fresh.value(forKey: "at") as? Double ?? 0 > clock - 30 { return }   // this launch's, already down
        scorches.removeValue(forKey: key)?.removeFromParentNode()
        let size = Station.hexRadius * 2.6
        let mark = SCNNode(geometry: SCNPlane(width: size, height: size))
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = Props.scorchImage(seed: UInt64(clock * 1000))
        m.writesToDepthBuffer = false
        m.isDoubleSided = false
        mark.geometry!.firstMaterial = m
        mark.eulerAngles.x = -.pi / 2
        mark.eulerAngles.y = CGFloat(Double.random(in: 0..<(2 * .pi)))
        mark.position = SCNVector3(p.x, 0.007, p.z)
        mark.renderingOrder = 2
        mark.opacity = 0
        mark.setValue(clock, forKey: "at")
        propRoot.addChildNode(mark)
        scorches[key] = mark
        mark.runAction(.sequence([.wait(duration: 0.6), .fadeIn(duration: 1.2), .wait(duration: 600), .fadeOut(duration: 600),
                                  .run { [weak self] n in if self?.scorches[key] === n { self?.scorches[key] = nil } }, .removeFromParentNode()]))
    }

    /// Pads whose release is gone lose their rocket, the ones standing by are resized, and the pad's hexagons redrawn.
    func refreshRockets() {
        simulation.refreshRockets()
        rebuildPadHexes()
    }
}
