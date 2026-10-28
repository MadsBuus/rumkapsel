import AppKit
import SceneKit

extension StationController {
    func shownOffices(_ station: Station) -> [(key: String, office: ShownOffice)] {
        (simulation.shown[station.name]?.offices ?? [:]).sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }

    func drawnRooms(_ station: Station) -> [(room: Room, office: ShownOffice?)] {
        station.rooms.values.filter { $0.key.hasPrefix("kind:") }.sorted { $0.key < $1.key }.map { ($0, nil) }
            + shownOffices(station).map { ($0.office.room($0.key), $0.office) }
    }

    func shownOffice(_ station: Station, _ key: String) -> ShownOffice? { simulation.shown[station.name]?.offices[key] }

    func officeUp(_ station: Station, _ key: String) -> Bool {
        guard !key.hasPrefix("kind:") else { return true }
        return shownOffice(station, key)?.up ?? false
    }

    func tileBase(_ look: ShownOffice.Look) -> Double { look.unchecked ? StationController.unlitOffice : look.provisional ? 0.38 : 1 }

    func labelBase(_ look: ShownOffice.Look) -> Double { look.provisional ? 0.55 : 1 }

    func tickOffices() {
        var sinking: Set<String> = []
        for station in fleet.stations.values {
            let view = simulation.shown[station.name] ?? Shown()
            for (key, o) in view.offices where o.epic != nil && clock - o.epicAt < ShownOffice.furnishSeconds + 0.2 {
                let grown = CGFloat(max(0.01, o.furnished(at: clock)))
                for n in epicProps[station.name + "|" + key] ?? [] { n.scale = SCNVector3(1, grown, 1) }
            }
            for (key, o) in view.offices where o.phase != .built {
                let full = station.name + "|" + key
                let base = tileBase(o.look)
                for t in roomTiles[full] ?? [] {
                    let cell = Cell(x: Int((Double(t.position.x) - station.offset.x).rounded()), y: Int((Double(t.position.z) - station.offset.y).rounded()))
                    t.opacity = CGFloat(base * o.tile(cell, at: clock))
                }
                let label = o.label(at: clock)
                roomLabels[full]?.opacity = CGFloat(label * labelBase(o.look))
                ownerSigns[full]?.opacity = CGFloat(label)
                for part in officeParts[full] ?? [] {
                    if let b = part.base { part.node.opacity = CGFloat(b * label) } else { part.node.isHidden = label < 1 }
                }
                for b in markerRoot.childNodes where b.name == "box:" + full {
                    if case .folding = o.phase { b.scale = SCNVector3(max(0.01, label), max(0.01, label), max(0.01, label)) } else { b.opacity = CGFloat(label) }
                }
                guard let c = o.crate(at: clock), let door = o.door else { continue }
                sinking.insert(full)
                let hex = foldCrates[full] ?? {
                    let n = Looks.current.crate(color: NSColor(o.color)) ?? Props.crate(color: NSColor(o.color))
                    propRoot.addChildNode(n)
                    foldCrates[full] = n
                    return n
                }()
                hex.scale = SCNVector3(c.scale, c.scale, c.scale)
                hex.position = v3(station.offset.x + Double(door.x), 0.09 - c.sink, station.offset.y + Double(door.y))
            }
            for (id, since) in view.folds {
                guard let box = boxes[id] else { continue }
                let s = ShownOffice.folded(since, at: clock)
                box.scale = SCNVector3(s, s, s)
            }
        }
        for (key, n) in foldCrates where !sinking.contains(key) { n.removeFromParentNode(); foldCrates[key] = nil }
        let live = Set(simulation.deliveries.map(\.id)).union(simulation.shown.values.flatMap(\.folds.keys))
        for (id, box) in boxes where !live.contains(id) {
            stopCrate(box)
            box.removeFromParentNode()
            boxes[id] = nil
        }
    }
}
