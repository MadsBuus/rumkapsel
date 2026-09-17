// The staging pallet as the scene draws it: the slab on its cushion of light, the shadow that stays
// down, the corner light, the pusher's lean, and the crate in the air, all from what the simulation's
// `PalletJob` says. The errand itself is in `Pallet.swift`; nothing here decides anything.

import AppKit
import SceneKit

/// The nodes for one pallet out: the slab, its shadow, the light on the corner, the crate in the
/// air and the crates aboard, by crate key.
final class PalletView {
    let node: SCNNode
    /// The dark patch on the floor under it. Its own node, because it must not bob with the slab.
    let shadow: SCNNode
    /// The blinking light on the corner, found once when the prop is built.
    let beacon: SCNNode?
    let bobPhase = Double.random(in: 0..<6.28)
    var flying: SCNNode?
    var aboard: [String: SCNNode] = [:]

    init(node: SCNNode, shadow: SCNNode) {
        self.node = node; self.shadow = shadow
        beacon = node.childNode(withName: "beacon", recursively: true)
    }
}

extension StationController {
    /// One frame of every pallet out: the bob, the light, the pusher, and the crate in the air, drawn
    /// where the simulation has them; a pallet the simulation no longer has fades where it stood.
    func drawPallets() {
        // The panel by the storage doorway blinks while an order stands unanswered.
        for station in fleet.stations.values where consolePanels[station.name] != nil {
            if world.truth.palletQueue[station.name]?.isEmpty == false { flashConsole(station) } else { stopConsole(station) }
        }
        for (name, p) in simulation.pallets {
            guard let station = fleet.stations[name] else { continue }
            let v = palletViews[name] ?? makePalletView(p, station: station)
            // A slow, plain sine: the slab rides its cushion of light.
            let bob = sin(clock * (2 * .pi / 2.4) + v.bobPhase) * 0.06
            v.node.position = v3(station.offset.x + p.spot.x, PalletGeometry.lift + bob, station.offset.y + p.spot.y)
            v.node.eulerAngles.y = 0
            v.node.opacity = min(1, (clock - p.bornAt) / 0.9)
            // The shadow keeps to the floor: it tightens and darkens as the slab comes down.
            let high = bob / 0.06 * 0.5 + 0.5
            v.shadow.position = v3(station.offset.x + p.spot.x, 0.006, station.offset.y + p.spot.y)
            v.shadow.scale = SCNVector3(1.06 - high * 0.12, 1.06 - high * 0.12, 1)
            v.shadow.opacity = v.node.opacity * CGFloat(1.06 - high * 0.26)
            // The corner light: half a second on, half off, off the station's own clock.
            if let beacon = v.beacon {
                let on = clock.truncatingRemainder(dividingBy: 1.0) < 0.5
                beacon.geometry?.firstMaterial?.diffuse.contents = on ? Props.palletAmber : Props.palletAmberOff
                beacon.geometry?.firstMaterial?.emission.contents = on ? Props.palletAmber : NSColor.black
            }
            let m = minions[p.dispatcher]
            if m?.tool == .telekinesis { m?.setWand(lifting: p.flight != nil) }
            // The crate in the air: an arc on the station's own clock, so it lands whatever is drawing.
            if let f = p.flight, let node = v.flying {
                let (pos, yaw, _) = f.position(at: clock)
                node.position = v3(pos.x, pos.y, pos.z)
                node.eulerAngles = SCNVector3(0, yaw, 0)
            }
        }
        // Empty and gone: the slab fades where it stood.
        for (name, v) in palletViews where simulation.pallets[name] == nil {
            fadingProps.append((v.node, clock))
            fadingProps.append((v.shadow, clock))
            palletViews[name] = nil
        }
        for (i, f) in fadingProps.enumerated().reversed() {
            let t = (clock - f.at) / 0.9
            f.node.opacity = max(0, 1 - t)
            if t >= 1 { f.node.removeFromParentNode(); fadingProps.remove(at: i) }
        }
    }

    /// A pallet just out: the slab by the near wall and its shadow, both fading in on the clock.
    private func makePalletView(_ p: PalletJob, station: Station) -> PalletView {
        let node = Looks.current.pallet(color: NSColor(fleet.color(forRepo: p.repo))) ?? Props.pallet(color: NSColor(fleet.color(forRepo: p.repo)))
        node.opacity = 0
        node.name = "pallet:" + station.name
        propRoot.addChildNode(node)
        let shadow = Props.palletShadow()
        shadow.opacity = 0
        propRoot.addChildNode(shadow)
        let v = PalletView(node: node, shadow: shadow)
        palletViews[station.name] = v
        return v
    }

    /// A crate leaves the ground for the pallet, or the pallet for a yard: its node comes free to fly.
    func palletLift(station name: String, crate: CrateRef) {
        guard let station = fleet.stations[name], let p = simulation.pallets[name] else { return }
        let v = palletViews[name] ?? makePalletView(p, station: station)
        // The rows are redrawn every time one leaves, so take the crate standing there now.
        let node: SCNNode
        if let aboard = v.aboard.removeValue(forKey: crate.key) { node = aboard }
        else if let standing = crateNode(crate) { node = standing }
        else { return }
        let at = node.worldPosition
        node.removeAllActions()
        stopCrate(node)
        node.removeFromParentNode()
        node.position = at
        propRoot.addChildNode(node)
        v.flying = node
        rebuildMarkers()   // the rows are one crate lighter now
    }

    /// The crate came down: onto the pallet, where it rides along, or off it onto its slot, where the
    /// rows draw it from here.
    func palletLanded(station name: String, crate: CrateRef, aboard: Bool) {
        guard let v = palletViews[name], let node = v.flying else { return }
        v.flying = nil
        if aboard, let slot = world.truth.pallets[name]?.crates[crate.key] {
            let to = PalletGeometry.offset(row: slot.row, column: slot.column, level: slot.level)
            node.removeFromParentNode()
            v.node.addChildNode(node)
            node.position = v3(to.x, to.y, to.z)
            node.eulerAngles = SCNVector3(0, 0, 0)
            v.aboard[crate.key] = node
            drone.thud()
        } else {
            node.removeFromParentNode()
            drone.thud()
            rebuildMarkers()
            refreshRockets()
        }
    }

    /// Puts the pusher's figure where its body says, with the lean it is holding: into the pallet
    /// while shoving, upright between legs. The tick's minion loop leaves a pallet errand's body
    /// alone, so this is where the pusher is drawn.
    func drawPusher(_ m: Minion, station: Station) {
        let pushing = simulation.pallets[station.name].map { $0.pushing && $0.dispatcher == m.id } ?? false
        let tilt = pushing ? 0.35 : 0.0
        let shove = pushing ? sin(clock * 3.6 + m.bobPhase) * 0.02 : 0.0
        m.smoothFacing = m.facing
        m.node.position = v3(station.offset.x + m.pos.x + sin(m.facing) * shove, 0,
                             station.offset.y + m.pos.y + cos(m.facing) * shove)
        m.node.eulerAngles = SCNVector3(0, m.smoothFacing, 0)
        m.tilt.eulerAngles = SCNVector3(tilt, 0, 0)
    }

    /// What is in the hands on a pallet errand: the tablet to the console, the wand while crates
    /// fly, both hands on the pallet while it is shoved.
    func errandTool(_ m: Minion) -> Minion.Tool? {
        switch m.current?.kind {
        case .dispatch: return .tablet
        case .waitPallet(_, let repo): return simulation.pallets[m.station]?.repo == repo ? .telekinesis : .tablet
        case .loadPallet, .unloadPallet: return .telekinesis
        case .pushPallet: return simulation.pallets[m.station]?.pushing == true ? .hands : nil
        default: return nil
        }
    }

    // MARK: the console

    /// The panel by the storage doorway blinks while an order is being placed.
    private func flashConsole(_ station: Station) {
        guard let panel = consolePanels[station.name], panel.action(forKey: "flash") == nil else { return }
        panel.runAction(.repeatForever(.sequence([.fadeOpacity(to: 0.3, duration: 0.5), .fadeOpacity(to: 1, duration: 0.5)])), forKey: "flash")
    }

    private func stopConsole(_ station: Station) {
        guard let panel = consolePanels[station.name] else { return }
        panel.removeAction(forKey: "flash")
        panel.opacity = 1
    }
}
