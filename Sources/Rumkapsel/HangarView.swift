import AppKit
import SceneKit

final class HangarField {
    let node: SCNNode
    let sheet: SCNNode
    let z: Double, x0: Double, x1: Double
    var sides: [ObjectIdentifier: Bool] = [:]
    var ripples: [(node: SCNNode, born: Double)] = []
    var struck = -10.0
    init(node: SCNNode, sheet: SCNNode, z: Double, x0: Double, x1: Double) {
        self.node = node; self.sheet = sheet; self.z = z; self.x0 = x0; self.x1 = x1
    }
}

extension Props {
    static let fieldBlue = NSColor(rgb: (0.45, 0.82, 1.0))

    static let fieldImage: NSImage = {
        NSImage(size: NSSize(width: 64, height: 256), flipped: false) { r in
            NSColor.black.setFill(); r.fill()
            for y in stride(from: 0.0, to: r.height, by: 8) {
                let edge = min(y, r.height - y) / (r.height / 2)
                NSColor(white: 0.55 + 0.45 * (1 - edge), alpha: 1).setFill()
                NSRect(x: 0, y: y, width: r.width, height: 2).fill()
            }
            return true
        }
    }()

    static func hangarField(width: Double) -> (node: SCNNode, sheet: SCNNode) {
        let n = SCNNode()
        let h = Station.fieldTop
        let sheet = SCNNode(geometry: SCNPlane(width: width, height: h - 0.08))
        let m = Props.glowing(fieldBlue, alpha: 1)
        m.diffuse.contents = fieldImage
        m.diffuse.wrapT = .repeat
        m.multiply.contents = fieldBlue
        sheet.geometry!.firstMaterial = m
        sheet.opacity = 0.34
        sheet.position = v3(0, h / 2, 0)
        sheet.name = "sheet"
        sheet.castsShadow = false
        sheet.categoryBitMask = Pick.scenery
        n.addChildNode(sheet)
        for y in [0.03, h - 0.03] {
            let bar = SCNNode(geometry: SCNBox(width: width + 0.1, height: 0.05, length: 0.08, chamferRadius: 0))
            bar.geometry!.firstMaterial = lit(NSColor(rgb: (0.24, 0.26, 0.32)))
            bar.position = v3(0, y, 0)
            n.addChildNode(bar)
            let glow = SCNNode(geometry: SCNBox(width: width, height: 0.02, length: 0.085, chamferRadius: 0))
            glow.geometry!.firstMaterial = flat(fieldBlue)
            glow.position = v3(0, y + (y < 0.5 ? 0.02 : -0.02), 0)
            glow.castsShadow = false
            n.addChildNode(glow)
        }
        return (n, sheet)
    }

    static func fieldRipple() -> SCNNode {
        let n = SCNNode()
        let m = Props.glowing(fieldBlue, alpha: 0.9)
        for (w, h, x, y) in [(1.0, 0.03, 0.0, 0.5), (1.0, 0.03, 0.0, -0.5), (0.03, 1.0, 0.5, 0.0), (0.03, 1.0, -0.5, 0.0)] {
            let edge = SCNNode(geometry: SCNPlane(width: w, height: h))
            edge.geometry!.firstMaterial = m
            edge.position = v3(x, y, 0)
            n.addChildNode(edge)
        }
        n.castsShadow = false
        return n
    }
}

extension StationController {
    func buildHangar(_ station: Station) {
        fields[station.name]?.node.removeFromParentNode()
        fields[station.name] = nil
        guard let x0 = station.hangarCells.map(\.x).min(), let x1 = station.hangarCells.map(\.x).max(),
              let y0 = station.hangarCells.map(\.y).min(), let y1 = station.hangarCells.map(\.y).max() else { return }
        let wide = Double(x1 - x0 + 1), deep = Double(y1 - y0 + 1)
        let cx = station.offset.x + Double(x0 + x1) / 2, cz = station.offset.y + Double(y0 + y1) / 2
        let mouth = station.offset.y + station.bayMouth.z
        if let wall = Looks.current.hullWall(width: wide + 0.2, depth: deep, doorway: wide - 0.5, doorTop: Station.fieldTop) {
            wall.position = v3(cx, 0, mouth + 0.04)
            wall.name = "hull:" + station.name
            staticRoot.addChildNode(wall)
        }
        for side in [-1.0, 1.0] {
            guard let wall = Looks.current.hullWall(width: deep, depth: wide / 2, doorway: 0, doorTop: 0) else { continue }
            wall.eulerAngles.y = CGFloat(side * .pi / 2)
            wall.position = v3(cx + side * (wide / 2 + 0.04), 0, cz)
            wall.name = "hull:" + station.name
            staticRoot.addChildNode(wall)
        }
        guard Looks.current.hangarField else { return }
        let built = Props.hangarField(width: wide - 0.5)
        built.node.position = v3(cx, 0, mouth)
        built.node.name = "hangar:" + station.name
        staticRoot.addChildNode(built.node)
        fields[station.name] = HangarField(node: built.node, sheet: built.sheet, z: mouth, x0: cx - wide / 2, x1: cx + wide / 2)
    }

    func tickHangars() {
        for (name, field) in fields {
            guard let station = fleet.stations[name] else { continue }
            let drift = CGFloat(clock * 0.12).truncatingRemainder(dividingBy: 1)
            field.sheet.geometry?.firstMaterial?.diffuse.contentsTransform = SCNMatrix4MakeTranslation(0, drift, 0)
            var live = Set<ObjectIdentifier>()
            for f in simulation.flights where f.station == name {
                let id = ObjectIdentifier(f)
                live.insert(id)
                let x = station.offset.x + f.pos.x, z = station.offset.y + f.pos.z
                let outside = z > field.z
                if let was = field.sides[id], was != outside, x > field.x0 - 0.3, x < field.x1 + 0.3, f.pos.y < Station.fieldTop + 0.3 {
                    let ripple = Props.fieldRipple()
                    ripple.position = v3(x - Double(field.node.position.x), f.pos.y, 0.01)
                    field.node.addChildNode(ripple)
                    field.ripples.append((ripple, clock))
                    field.struck = clock
                    drone.ping(seed: 9)
                }
                field.sides[id] = outside
            }
            for id in field.sides.keys where !live.contains(id) { field.sides[id] = nil }
            let glow = max(0, 1 - (clock - field.struck) / 1.2)
            field.sheet.opacity = CGFloat(0.34 + 0.4 * glow + 0.05 * sin(clock * 1.7))
            for (i, r) in field.ripples.enumerated().reversed() {
                let age = (clock - r.born) / 1.1
                guard age < 1 else { r.node.removeFromParentNode(); field.ripples.remove(at: i); continue }
                let s = CGFloat(0.25 + 1.6 * age)
                r.node.scale = SCNVector3(s, s, 1)
                r.node.opacity = CGFloat((1 - age) * (1 - age))
            }
        }
    }
}
