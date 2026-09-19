// The shuttles and the rockets as the scene draws them: a ship node per flight, placed where the
// simulation's `Flight` says; a rocket node per `RocketJob`, sized to its pile while it stands by,
// lifting off with flame and steam when the simulation says so. Nothing here decides anything.

import AppKit
import SceneKit

/// The node for one flight, and whether it has turned toward its way out.
final class ShuttleView {
    let node: SCNNode
    var leaving = false
    init(node: SCNNode) { self.node = node }
}

/// The node for one rocket, and what it was drawn for, so it is only redrawn when that changes.
final class RocketView {
    var node: SCNNode
    var cargoShown: Int
    var untestedShown: Bool
    init(node: SCNNode, cargo: Int, untested: Bool) { self.node = node; cargoShown = cargo; untestedShown = untested }
}

extension StationController {
    // MARK: shuttles

    /// The shuttle body, wings in a repo colour: the look's.
    private func shuttle(color: NSColor) -> SCNNode { Looks.current.shuttle(color: color) }

    /// Every ship in the air, where the simulation has it. Everything is parented to the hangar
    /// anchor, so a station shifting underneath does not misalign it; a flight that is over loses its node.
    func drawShuttles() {
        var live = Set<ObjectIdentifier>()
        for f in simulation.flights {
            guard let station = fleet.stations[f.station], let anchor = hangarAnchors[f.station] else { continue }
            let id = ObjectIdentifier(f)
            live.insert(id)
            let v = shuttleViews[id] ?? {
                let ship = shuttle(color: NSColor(fleet.color(forRepo: f.repo)))
                anchor.addChildNode(ship)
                let v = ShuttleView(node: ship)
                shuttleViews[id] = v
                return v
            }()
            let hc = station.hangarCenter
            let leg = ShipLeg(phase: f.phaseKind, progress: f.progress(at: clock), slot: SIMD2(f.down.x, f.down.z), side: f.exit.x >= f.down.x ? 1 : -1)
            if let pose = Looks.current.shipPose(leg) {
                v.node.position = v3(pose.pos.x - hc.x, pose.pos.y, pose.pos.z - hc.y)
                v.node.eulerAngles = SCNVector3(0, pose.yaw, 0)
                continue
            }
            v.node.position = v3(f.pos.x - hc.x, f.pos.y, f.pos.z - hc.y)
            if f.phaseKind == .leave, f.restYaw != nil, !v.leaving {
                v.leaving = true
                v.node.look(at: v3(f.exit.x - hc.x, f.exit.y, f.exit.z - hc.y), up: SCNVector3(0, 1, 0), localFront: SCNVector3(1, 0, 0))
            } else if f.phaseKind == .approach, f.restYaw != nil, f.phase == 0 {
                v.node.look(at: v3(f.high.x - hc.x, f.high.y, f.high.z - hc.y), up: SCNVector3(0, 1, 0), localFront: SCNVector3(1, 0, 0))
            } else if let yaw = f.yaw, !v.leaving {
                v.node.eulerAngles = SCNVector3(0, yaw, 0)
            }
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
        let offsets: [SIMD2<Double>] = [SIMD2(0, 0), SIMD2(1.3, 0), SIMD2(-1.3, 0), SIMD2(0, 1.2)]
        let pc = station.padCenter + offsets[slot % offsets.count]
        return v3(station.offset.x + pc.x, 0, station.offset.y + pc.y)
    }

    private func rocketNode(station: Station, _ r: RocketJob, slot: Int) -> SCNNode {
        let color = NSColor(fleet.color(forRepo: r.repo))
        let n = Looks.current.rocket(color: color, tall: r.tall, cargo: r.cargo)
        // A look with a hold of its own shows it while the rocket is held; the classic pad has its
        // service tower beside the rocket all the while it stands, lit red while held.
        if let own = Looks.current.hold(tall: r.tall) {
            if r.untested { own.name = "hold"; n.addChildNode(own) }
        } else {
            Props.attachTower(to: n, tall: r.tall, held: r.untested)
        }
        n.position = padPosition(station: station, slot: slot)
        n.name = r.label
        n.enumerateChildNodes { c, _ in if c.name != "flame" && c.name != "hold" { c.name = r.label } }
        rocketRoot.addChildNode(n)
        // A rocket that was already standing there when the station came up fades in where it stands;
        // one that arrives later has its own way of getting there and is left to it.
        n.opacity = 0
        n.runAction(.sequence([.wait(duration: Double.random(in: 0...0.5)), .fadeIn(duration: 1.2)]))
        return n
    }

    /// Every rocket on a pad, drawn for what the simulation says it is: a new one gets a node on the
    /// next slot; one standing by grows with what it will carry and stands where the pad is now; once
    /// it is loading it keeps the size it had, and the steam and the flame stay where they are.
    func drawRockets() {
        let keys = simulation.rockets.keys.sorted()
        for (key, r) in simulation.rockets {
            guard let st = fleet.stations[r.station] else { continue }
            let slot = (keys.firstIndex(of: key) ?? 0) % 4
            guard let v = rocketViews[key] else {
                rocketViews[key] = RocketView(node: rocketNode(station: st, r, slot: slot), cargo: r.cargo, untested: r.untested)
                continue
            }
            guard r.stage.rank == 0, !v.node.hasActions else { continue }
            if r.cargo / 3 != v.cargoShown / 3 || r.untested != v.untestedShown {
                let position = v.node.position
                v.node.removeFromParentNode()
                v.node = rocketNode(station: st, r, slot: slot)
                v.node.position = position
                v.cargoShown = r.cargo
                v.untestedShown = r.untested
            } else if v.node.name != r.label {
                v.node.name = r.label
                v.node.enumerateChildNodes { c, _ in if c.name != "flame" && c.name != "hold" { c.name = r.label } }
            }
            // Standing by, a rocket stands where the pad is now: the floor may have grown under it.
            v.node.position = padPosition(station: st, slot: slot)
        }
    }

    /// The simulation's word on a rocket, shown once: the hold's tape comes down, the flame goes on,
    /// the steam starts, the node goes with the rocket, or a crate goes in through the hatch.
    func play(rocket cue: Cue) {
        switch cue {
        case .rocketLoading(let key):
            // Cleared: a look's own hold comes down; the tower stays for the loading, its beacon goes dark.
            if let hold = rocketViews[key]?.node.childNode(withName: "hold", recursively: false) {
                if let beacon = hold.childNode(withName: "beacon", recursively: true) {
                    beacon.geometry?.firstMaterial = lit(NSColor(rgb: (0.38, 0.4, 0.45)))
                } else { hold.removeFromParentNode() }
            }
        case .liftOff(let key):
            if let node = rocketViews[key]?.node {
                // The tower stays on the pad: it is let go of the rocket a moment before the climb.
                if let hold = node.childNode(withName: "hold", recursively: false) {
                    hold.removeFromParentNode()
                    hold.position = node.position
                    rocketRoot.addChildNode(hold)
                    hold.runAction(.sequence([.wait(duration: 6), .fadeOut(duration: 1.5), .removeFromParentNode()]))
                }
                liftOff(node)
            }
        case .steam(let key):
            if let node = rocketViews[key]?.node { addSteam(to: node) }
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
            // Up the service tower and in through the hatch: to the tower's foot, up its face to the swing
            // arm, across the arm and in, shrinking as it goes, since the rocket is far too small for it.
            let base = SIMD3(Double(rocket.position.x), Double(rocket.position.y), Double(rocket.position.z))
            let towerX = rocket.childNode(withName: "tower", recursively: true).map { Double($0.position.x) } ?? 0.44
            let hatchAt = SIMD3(Double(hatch.position.x), Double(hatch.position.y), Double(hatch.position.z))
            let foot = SIMD3(base.x + towerX + 0.12, at.y + 0.1, base.z + 0.02)
            let top = SIMD3(foot.x, base.y + hatchAt.y, foot.z)
            let door = base + hatchAt
            hatch.runAction(.sequence([.wait(duration: 1.3), .scale(to: 0.05, duration: 0.2), .wait(duration: 0.6), .scale(to: 1, duration: 0.2)]))
            moveCrate(b, legs: [MotionLeg(to: foot, seconds: 0.4, ease: .easeOut),
                                MotionLeg(to: top, seconds: 0.9, ease: .easeInOut, scale: 0.5),
                                MotionLeg(to: door, seconds: 0.5, ease: .easeIn, scale: 0.02)]) { b.removeFromParentNode() }
        default: break
        }
    }

    /// Flame on, a slow climb that carries the rocket out of the frame, then gone.
    func liftOff(_ node: SCNNode) {
        drone.sweep(up: true)
        node.childNode(withName: "flame", recursively: false)?.opacity = 1
        node.runAction(.sequence([Looks.current.launch(node), .removeFromParentNode()]))
    }

    /// Pads whose release is gone lose their rocket, the ones standing by are resized, and the due rings redrawn.
    func refreshRockets() {
        simulation.refreshRockets()
        rebuildDueRings()
    }
}
