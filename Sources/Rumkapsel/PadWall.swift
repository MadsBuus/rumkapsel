import AppKit
import SceneKit

extension StationController {
    func buildPadWall(_ station: Station) {
        droneRacks[station.name]?.removeFromParentNode()
        droneRacks[station.name] = nil
        _ = buildPadField(station)
        if let r = simulation.rack(station) {
            let n = Props.droneRack(count: DroneFlight.count, pitch: DroneFlight.berthPitch)
            n.position = v3(station.offset.x + r.at.x, 0, station.offset.y + r.at.y)
            n.eulerAngles.y = CGFloat(atan2(-r.along.y, r.along.x))
            n.name = "station:" + station.name
            staticRoot.addChildNode(n)
            droneRacks[station.name] = n
        }
    }

    func buildPadField(_ station: Station) -> SCNNode? {
        padFields[station.name] = nil
        guard let field = station.hall.padField else { return nil }
        let width = field.to.x - field.from.x
        let built = Props.hangarField(width: width)
        let x = station.offset.x + (field.from.x + field.to.x) / 2, z = station.offset.y + field.from.y
        built.node.position = v3(x, 0, z)
        built.node.name = "station:" + station.name
        staticRoot.addChildNode(built.node)
        padFields[station.name] = HangarField(node: built.node, sheet: built.sheet, z: z, x0: x - width / 2, x1: x + width / 2)
        return built.node
    }

    func tickPadFields() {
        for (name, field) in padFields {
            let drift = CGFloat(clock * 0.12).truncatingRemainder(dividingBy: 1)
            field.sheet.geometry?.firstMaterial?.diffuse.contentsTransform = SCNMatrix4MakeTranslation(0, drift, 0)
            let pulling = simulation.vortices.values.contains { $0.station == name && $0.closedAt == nil }
            let glow = max(0, 1 - (clock - field.struck) / 1.2)
            field.sheet.opacity = CGFloat(0.3 + (pulling ? 0.12 : 0) + 0.4 * glow + 0.05 * sin(clock * 1.7))
            for (i, r) in field.ripples.enumerated().reversed() {
                let age = (clock - r.born) / 1.1
                guard age < 1 else { r.node.removeFromParentNode(); field.ripples.remove(at: i); continue }
                let s = CGFloat(0.2 + 1.2 * age)
                r.node.scale = SCNVector3(s, s, 1)
                r.node.opacity = CGFloat((1 - age) * (1 - age))
            }
        }
    }
}
