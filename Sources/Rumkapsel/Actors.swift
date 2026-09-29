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
    /// when each set off, the lifter coming up or going down, and the sparks.
    var bornAt: Double
    var flying: [Int: Double] = [:]
    var rise: (up: Bool, since: Double)?
    var sparks: [(node: SCNNode, from: SIMD3<Double>, velocity: SIMD3<Double>, at: Double)] = []
    var sparkAt = 0.0
    init(node: SCNNode, untested: Bool, panels: Int, lifter: Bool, at clock: Double) {
        self.node = node; untestedShown = untested; panelsShown = panels; lifterShown = lifter; towerLifter = lifter; bornAt = clock
    }
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
            stepLifter(v)
            // Going up from the cradle, with no time for the lifter to rise: it is simply there.
            if r.stage.rank >= 3, !v.lifterShown { v.lifterShown = true; Props.shape(v.node, lifter: true, panels: RocketJob.hullPanels) }
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
            // Standing by, a rocket stands where the pad is now: the floor may have grown under it.
            v.node.position = padPosition(station: st, slot: slot)
        }
    }

    /// The tip as the welders have it: each new panel flies across from the top of the tower onto its
    /// place, the nose and the hatch go on with the last; sparks fly where the torch is while the welder
    /// stands at the rocket.
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
        let flight = 0.6
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
        let whole = r.panels >= RocketJob.hullPanels && v.flying.isEmpty
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
        // Sparks: each on its own arc, gone in half a second.
        let life = 0.45
        v.sparks = v.sparks.filter { s in
            let t = clock - s.at
            guard t < life else { s.node.removeFromParentNode(); return false }
            let p = s.from + s.velocity * t + SIMD3(0, -1.6 * t * t, 0)
            s.node.position = v3(p.x, p.y, p.z)
            s.node.opacity = CGFloat(1 - t / life)
            return true
        }
        guard r.welding, let p = simulation.pallets[r.station], let m = minions[p.dispatcher], m.path.isEmpty,
              let station = fleet.stations[r.station], let spot = simulation.weldCell(station: station, repo: r.repo),
              abs(m.pos.x - Double(spot.x)) + abs(m.pos.y - Double(spot.y)) < 0.8, clock >= v.sparkAt,
              let seam = piece("panel\(r.seam)") else { return }
        v.sparkAt = clock + 0.04
        let w = seam.convertPosition(SCNVector3(Double.random(in: -0.06...0.06), -0.05, 0.02), to: propRoot)
        for _ in 0..<2 {
            let spark = SCNNode(geometry: SCNBox(width: 0.018, height: 0.018, length: 0.018, chamferRadius: 0))
            spark.geometry!.firstMaterial = flat(Bool.random() ? NSColor(rgb: (1, 0.9, 0.55)) : NSColor(rgb: (0.75, 0.9, 1)))
            spark.position = w
            propRoot.addChildNode(spark)
            let velocity = SIMD3(Double.random(in: -0.5...0.5), Double.random(in: 0.1...0.6), Double.random(in: -0.5...0.5))
            v.sparks.append((spark, SIMD3(Double(w.x), Double(w.y), Double(w.z)), velocity, clock))
        }
    }

    /// A production release opened: the lifter comes up out of the pad under the tip and lifts it off
    /// its cradle, which folds away. Closed again, it goes back down and the tip settles on the cradle.
    private func stepLifter(_ v: RocketView) {
        guard let rise = v.rise else { return }
        guard let tip = Props.part(v.node, "tip"), let lifter = Props.part(v.node, "lifter") else { v.rise = nil; return }
        let base = (tip.value(forKey: "base") as? Double) ?? 0
        let low = Props.cradleTop - base, deep = -(base + 0.2)
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

    /// Pads whose release is gone lose their rocket, the ones standing by are resized, and the pad's hexagons redrawn.
    func refreshRockets() {
        simulation.refreshRockets()
        rebuildPadHexes()
    }
}
