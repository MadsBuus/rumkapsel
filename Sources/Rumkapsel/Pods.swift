// The payload pods on the deck, as the scene draws them: one round each repository's tested crates on the deck's
// row nearest the pad, so what is ready to ship stands apart from what still waits for QA. Its lid stands open
// while anything the release would ship is untested and closes, glass, once all of it is: sealed and lit green.
// At the merge the whole pod goes out through the cargo lock to its rocket in one move. Which crates are tested,
// and when a pod is sealed or goes, is the simulation's (`yardLayout`, `Simulation.podSealed`, `Cue.podOut`).

import AppKit
import SceneKit

/// One pod on the deck.
final class PodView {
    let node: SCNNode
    let lid: SCNNode?, lamp: SCNNode?
    let station: String, repo: String
    /// Where it stands and how wide it is, so it is only built again when its crates move.
    let shape: String
    /// How far its lid stands open as drawn, 1 open to 0 shut.
    var open = 1.0
    init(node: SCNNode, station: String, repo: String, shape: String) {
        self.node = node; self.station = station; self.repo = repo; self.shape = shape
        lid = node.childNode(withName: "lid", recursively: true)
        lamp = node.childNode(withName: "lamp", recursively: true)
    }
}

extension Props {
    /// How high a pod's lid closes: over a stack three crates high.
    static let podTop = 1.08

    /// A pod `width` along x and `depth` along z, standing on the origin, its back (the pad's side) at -z: a deck
    /// plate, low walls with a hazard band, a post at each corner, a lamp along the front ("lamp"), and a glass
    /// lid on a hinge along the back ("lid") that the scene swings open.
    static func payloadPod(width: Double, depth: Double) -> SCNNode {
        let n = SCNNode()
        let shell = lit(NSColor(rgb: (0.8, 0.82, 0.86))), steel = lit(NSColor(rgb: (0.55, 0.57, 0.62)))
        func box(_ w: Double, _ h: Double, _ l: Double, _ m: SCNMaterial, _ p: SCNVector3, in parent: SCNNode? = nil, name: String? = nil) -> SCNNode {
            let b = SCNNode(geometry: SCNBox(width: w, height: h, length: l, chamferRadius: 0))
            b.geometry!.firstMaterial = m
            b.position = p
            b.name = name
            (parent ?? n).addChildNode(b)
            return b
        }
        let wall = 0.2, t = 0.04
        _ = box(width, 0.012, depth, lit(NSColor(rgb: (0.2, 0.21, 0.25))), v3(0, 0.006, 0))
        for side in [-1.0, 1.0] {
            _ = box(width, wall, t, shell, v3(0, wall / 2, side * depth / 2))
            _ = box(t, wall, depth, shell, v3(side * width / 2, wall / 2, 0))
            _ = box(width + 0.004, 0.035, t + 0.004, flat(hazard), v3(0, wall - 0.03, side * depth / 2))
            for end in [-1.0, 1.0] { _ = box(0.05, podTop, 0.05, steel, v3(side * width / 2, podTop / 2, end * depth / 2)) }
        }
        let lamp = box(width * 0.7, 0.03, 0.02, flat(gateIdle), v3(0, wall + 0.02, depth / 2 + 0.02), name: "lamp")
        lamp.castsShadow = false
        let hinge = SCNNode()
        hinge.name = "lid"
        hinge.position = v3(0, podTop, -depth / 2)
        let glassLid = box(width, 0.014, depth, Props.glass(alpha: 0.16), v3(0, 0, depth / 2), in: hinge)
        glassLid.castsShadow = false
        for side in [-1.0, 1.0] { _ = box(t, 0.03, depth, steel, v3(side * width / 2, 0, depth / 2), in: hinge) }
        _ = box(width, 0.03, t, steel, v3(0, 0, depth), in: hinge)
        n.addChildNode(hinge)
        return n
    }
}

extension StationController {
    /// The pods on a station's deck, from its layout: one round each repository's tested crates, built again only
    /// when those move.
    func rebuildPods(_ station: Station, deck layout: [World.YardSlot]) {
        var wanted: [String: (x0: Double, x1: Double, z: Double)] = [:]
        for slot in layout where slot.group == 0 && slot.cleared {
            let key = station.name + "|" + slot.repo
            let w = wanted[key]
            wanted[key] = (min(w?.x0 ?? slot.pos.x, slot.pos.x), max(w?.x1 ?? slot.pos.x, slot.pos.x), slot.pos.z)
        }
        for (key, pod) in pods where pod.station == station.name && wanted[key] == nil {
            pod.node.removeFromParentNode()
            pods[key] = nil
        }
        for (key, at) in wanted {
            let shape = String(format: "%.2f|%.2f|%.2f", at.x0, at.x1, at.z)
            if pods[key]?.shape == shape { continue }
            pods[key]?.node.removeFromParentNode()
            let width = at.x1 - at.x0 + 0.62, depth = 0.66
            let node = Props.payloadPod(width: width, depth: depth)
            node.position = v3((at.x0 + at.x1) / 2, 0, at.z)
            node.name = "pod:" + station.name
            propRoot.addChildNode(node)
            let repo = String(key.dropFirst(station.name.count + 1))
            let view = PodView(node: node, station: station.name, repo: repo, shape: shape)
            view.open = simulation.podSealed(station: station.name, repo: repo) ? 0 : 1
            pods[key] = view
        }
    }

    /// Every pod's lid and lamp, from whether its release is all tested: open and amber while anything is not,
    /// shut and green once it all is.
    func tickPods(dt: Double) {
        for pod in pods.values {
            let sealed = simulation.podSealed(station: pod.station, repo: pod.repo)
            pod.open += ((sealed ? 0 : 1) - pod.open) * min(1, dt * 2.5)
            pod.lid?.eulerAngles.x = CGFloat(-1.75 * pod.open)
            let pulse = sealed ? 1 : 0.65 + 0.35 * sin(clock * 2.4)
            let color = sealed ? Props.passedLight : Props.gateIdle
            pod.lamp?.geometry?.firstMaterial?.diffuse.contents = color.blended(withFraction: CGFloat(1 - pulse), of: .black) ?? color
        }
    }

    /// The merge: a rocket's pod goes out whole, sealed, up off the deck, through the cargo lock with both its
    /// doors open, across the pad and into the rocket's hatch. The crates in it are aboard already.
    func podOut(key: String, crates: [CrateRef]) {
        let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2, let station = fleet.stations[parts[0]] else { return }
        let pod = pods.removeValue(forKey: key)
        let carrier = pod?.node ?? {
            let n = Props.payloadPod(width: Double(max(1, crates.count)) * 0.44 + 0.2, depth: 0.66)
            if let lock = station.lock { n.position = v3(lock.inner.x, 0, lock.inner.z) }
            propRoot.addChildNode(n)
            return n
        }()
        carrier.name = nil
        carrier.childNode(withName: "lid", recursively: true)?.eulerAngles.x = 0
        // The crates it holds, in a row on its floor, two high where it is narrow.
        let width = Double(carrier.boundingBox.max.x - carrier.boundingBox.min.x) - 0.2
        let across = max(1, Int(width / 0.44))
        for (i, crate) in crates.enumerated() {
            let n = lockCrate(crate)
            n.position = v3(-width / 2 + 0.22 + Double(i % across) * 0.44, 0.012 + Double(i / across) * 0.34, 0)
            carrier.addChildNode(n)
        }
        stopCrate(carrier)
        guard let lock = station.lock else {
            moveCrate(carrier, legs: [MotionLeg(to: SIMD3(Double(carrier.position.x), 3, Double(carrier.position.z)), seconds: 2, ease: .easeIn, scale: 0.05)]) {
                carrier.removeFromParentNode()
            }
            return
        }
        locks[station.name]?.passUntil = clock + RocketJob.podSeconds
        let start = SIMD3(Double(carrier.position.x), 0, Double(carrier.position.z))
        var legs = [MotionLeg(to: start + SIMD3(0, 0.25, 0), seconds: 0.6, ease: .easeOut),
                    MotionLeg(to: SIMD3(lock.inner.x, 0.25, lock.inner.z), seconds: 1.0),
                    MotionLeg(to: SIMD3(lock.outer.x, 0.25, lock.outer.z), seconds: 1.0, scale: 0.6)]
        if let rocket = rocketViews[key]?.node, let r = simulation.rockets[key] {
            let h = RocketGeometry.hatch(lift: r.lift)
            let door = SIMD3(Double(rocket.position.x) + h.x + 0.15, h.y - 0.1, Double(rocket.position.z) + h.z)
            legs.append(MotionLeg(to: door, seconds: 1.4, ease: .easeInOut, scale: 0.2))
            legs.append(MotionLeg(to: door - SIMD3(0.12, 0, 0), seconds: 0.4, ease: .easeIn, scale: 0.02))
        }
        moveCrate(carrier, legs: legs) { carrier.removeFromParentNode() }
    }
}
