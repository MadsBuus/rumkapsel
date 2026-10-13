import AppKit
import SceneKit

final class PadLiftView {
    let at: SIMD2<Double>
    let centre = SCNNode()
    let pivot = SCNNode()
    var blades: [(node: SCNNode, out: SIMD2<Double>)] = []
    let deck = SCNNode()
    let shaft = SCNNode()
    var iris = 0.0
    var deckY = -RocketGeometry.shaftDepth
    init(at: SIMD2<Double>) { self.at = at }
}

extension StationController {
    private static func doorCorner(_ k: Int, radius r: Double) -> SIMD2<Double> {
        let a = .pi / 6 + Double(k) * .pi / 3
        return SIMD2(cos(a), sin(a)) * r
    }

    static func outline(_ cells: [Cell]) -> [[NSPoint]] {
        struct Corner: Hashable { let x: Int, y: Int }
        var next: [Corner: Corner] = [:]
        var edges = Set<[Int]>()
        for c in cells {
            let a = Corner(x: c.x, y: -c.y), b = Corner(x: c.x + 1, y: -c.y), d = Corner(x: c.x + 1, y: -c.y + 1), e = Corner(x: c.x, y: -c.y + 1)
            for (p, q) in [(a, b), (b, d), (d, e), (e, a)] {
                if edges.remove([q.x, q.y, p.x, p.y]) == nil { edges.insert([p.x, p.y, q.x, q.y]) }
            }
        }
        for e in edges { next[Corner(x: e[0], y: e[1])] = Corner(x: e[2], y: e[3]) }
        var loops: [[NSPoint]] = []
        while let start = next.keys.first {
            var loop: [NSPoint] = [], at = start
            while let to = next.removeValue(forKey: at) {
                loop.append(NSPoint(x: Double(at.x) - 0.5, y: Double(at.y) - 0.5))
                at = to
            }
            loops.append(loop)
        }
        return loops
    }

    func padSlab(_ station: Station) -> SCNNode {
        let path = NSBezierPath()
        path.windingRule = .evenOdd
        for loop in Self.outline(station.hall.padCells) {
            for (i, p) in loop.enumerated() { i == 0 ? path.move(to: p) : path.line(to: p) }
            path.close()
        }
        for slot in station.hall.padSlots {
            for k in 0..<6 {
                let p = slot + Self.doorCorner(k, radius: RocketGeometry.doorRadius)
                k == 0 ? path.move(to: NSPoint(x: p.x, y: -p.y)) : path.line(to: NSPoint(x: p.x, y: -p.y))
            }
            path.close()
        }
        let depth = 0.02
        let shape = SCNShape(path: path, extrusionDepth: depth)
        let floor = flat(Looks.current.floorColor(Palette.padFloor, floor: .pad))
        shape.materials = [floor, floor, floor]
        let slab = SCNNode(geometry: shape)
        slab.eulerAngles.x = -.pi / 2
        slab.position = v3(station.offset.x, -depth / 2, station.offset.y)
        slab.name = "pad:" + station.name
        return slab
    }

    private func buildLift(_ station: Station, at slot: SIMD2<Double>) -> PadLiftView {
        let v = PadLiftView(at: slot)
        let r = RocketGeometry.doorRadius, depth = RocketGeometry.shaftDepth
        let centre = v.centre
        centre.position = v3(station.offset.x + slot.x, 0, station.offset.y + slot.y)
        padLiftRoot.addChildNode(centre)
        let corners = (0..<6).map { Self.doorCorner($0, radius: r) }
        func hexPlate(_ radius: Double, thick: Double, _ material: SCNMaterial) -> SCNNode {
            let path = NSBezierPath()
            for k in 0..<6 {
                let p = Self.doorCorner(k, radius: radius)
                k == 0 ? path.move(to: NSPoint(x: p.x, y: -p.y)) : path.line(to: NSPoint(x: p.x, y: -p.y))
            }
            path.close()
            let g = SCNShape(path: path, extrusionDepth: thick)
            g.materials = [material, material, material]
            let n = SCNNode(geometry: g)
            n.eulerAngles.x = -.pi / 2
            return n
        }
        centre.addChildNode(v.shaft)
        let wall = lit(NSColor(rgb: (0.16, 0.17, 0.21)))
        for k in 0..<6 {
            let a = corners[k], b = corners[(k + 1) % 6], bottom = -depth - 0.08
            let quad = SCNGeometry(sources: [SCNGeometrySource(vertices: [v3(a.x, 0, a.y), v3(b.x, 0, b.y), v3(b.x, bottom, b.y), v3(a.x, bottom, a.y)])],
                                   elements: [SCNGeometryElement(indices: [Int32](arrayLiteral: 0, 2, 1, 0, 3, 2), primitiveType: .triangles)])
            quad.firstMaterial = wall
            v.shaft.addChildNode(SCNNode(geometry: quad))
        }
        let basement = hexPlate(r, thick: 0.02, flat(NSColor(rgb: (0.07, 0.075, 0.1))))
        basement.position = v3(0, -depth - 0.08, 0)
        v.shaft.addChildNode(basement)
        let glow = SCNMaterial()
        glow.lightingModel = .constant
        glow.diffuse.contents = NSColor(rgb: (0.35, 0.6, 0.85))
        glow.isDoubleSided = true
        for k in 0..<6 {
            let a = corners[k] * 0.995, b = corners[(k + 1) % 6] * 0.995
            let strip = SCNGeometry(sources: [SCNGeometrySource(vertices: [v3(a.x, -0.05, a.y), v3(b.x, -0.05, b.y), v3(b.x, -0.035, b.y), v3(a.x, -0.035, a.y)])],
                                    elements: [SCNGeometryElement(indices: [Int32](arrayLiteral: 0, 1, 2, 0, 2, 3), primitiveType: .triangles)])
            strip.firstMaterial = glow
            v.shaft.addChildNode(SCNNode(geometry: strip))
        }
        let deckSkin = flat(Looks.current.floorColor(Palette.padFloor, floor: .pad))
        let deckPlate = hexPlate(r * 0.985, thick: 0.04, deckSkin)
        deckPlate.position = v3(0, -0.02, 0)
        v.deck.addChildNode(deckPlate)
        centre.addChildNode(v.deck)
        let blade = flat(Looks.current.floorColor(Palette.padFloor, floor: .pad).blended(withFraction: 0.18, of: .black) ?? Palette.padFloor)
        blade.isDoubleSided = true
        centre.addChildNode(v.pivot)
        for k in 0..<6 {
            let a = corners[k] * 0.99, b = corners[(k + 1) % 6] * 0.99
            let tri = SCNGeometry(sources: [SCNGeometrySource(vertices: [v3(0, 0, 0), v3(a.x, 0, a.y), v3(b.x, 0, b.y)]),
                                            SCNGeometrySource(normals: [SCNVector3(0, 1, 0), SCNVector3(0, 1, 0), SCNVector3(0, 1, 0)])],
                                  elements: [SCNGeometryElement(indices: [Int32](arrayLiteral: 0, 1, 2), primitiveType: .triangles)])
            tri.firstMaterial = blade
            let node = SCNNode(geometry: tri)
            let mid = (a + b) / 2
            v.blades.append((node, mid / max(1e-6, simd_length(mid))))
            v.pivot.addChildNode(node)
        }
        return v
    }

    func tickPadLifts(dt: Double) {
        guard Theme.forPlan.kickRises else {
            if !padLifts.isEmpty { padLiftRoot.childNodes.forEach { $0.removeFromParentNode() }; padLifts = [:] }
            return
        }
        if padLiftRoot.parent == nil { propRoot.addChildNode(padLiftRoot) }
        let depth = RocketGeometry.shaftDepth
        var live = Set<String>()
        for station in fleet.stations.values where station.hasPad {
            let slots = world.padSlots(station: station)
            for (i, slot) in slots.enumerated() {
                let id = "\(station.name)|\(i)"
                live.insert(id)
                let world3 = v3(station.offset.x + slot.x, 0, station.offset.y + slot.y)
                if let v = padLifts[id], v.at != slot || v.centre.position.x != world3.x || v.centre.position.z != world3.z {
                    v.centre.removeFromParentNode()
                    padLifts[id] = nil
                }
                let v = padLifts[id] ?? buildLift(station, at: slot)
                padLifts[id] = v
                let key = world.releases.padSlotOf.first { $0.value == i && $0.key.hasPrefix(station.name + "|") }?.key
                if let key, let r = simulation.rockets[key], let view = rocketViews[key], Props.part(view.node, "lifter") != nil,
                   view.node.parent != nil, view.node.position.y < 0.3 {
                    v.iris = RocketGeometry.iris(dock: r.dock)
                    v.deckY = RocketGeometry.deck(dock: r.dock)
                } else if v.deckY > -depth {
                    v.deckY = max(-depth, v.deckY - dt * depth / 3)
                } else {
                    v.iris = max(0, v.iris - dt / 1.3)
                }
                v.deck.position = v3(0, v.deckY - 0.001, 0)
                let idle = v.deckY <= -depth + 1e-6 && v.iris <= 0
                v.deck.isHidden = idle
                v.shaft.isHidden = idle || v.deckY >= -1e-6
                let apothem = RocketGeometry.doorRadius * cos(.pi / 6)
                v.pivot.eulerAngles.y = CGFloat(v.iris * 0.5)
                for b in v.blades {
                    let out = b.out * (apothem * 1.25 * v.iris)
                    b.node.position = v3(out.x, -0.004 - 0.012 * v.iris, out.y)
                }
            }
        }
        for (id, v) in padLifts where !live.contains(id) {
            v.centre.removeFromParentNode()
            padLifts[id] = nil
        }
    }
}
