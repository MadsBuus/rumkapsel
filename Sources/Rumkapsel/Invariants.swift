import Foundation
import SceneKit

final class Invariants {
    var onViolation: ((String) -> Void)?

    private var seen: Set<String> = []

    private var slowAt = -1.0
    private static let slowEvery = 0.5

    private var scanned = false

    private var resting: [String: SIMD3<Double>] = [:]
    private var restingTested: [String: Bool] = [:]
    private var lastPhase: [String: (id: Int, phase: Int)] = [:]
    private var bath: [String: (id: Int, until: Double)] = [:]
    private var launched: Set<String> = []
    private var floorCache: [String: (signature: Int, cells: Set<Cell>)] = [:]
    private var furniture: [String: [(SIMD2<Double>, Double)]] = [:]
    private var furnitureAt = -1

    private func flag(_ rule: String, _ subject: String, _ detail: String) {
        guard seen.insert(rule + "|" + subject).inserted else { return }
        onViolation?("VIOLATION: \(rule): \(subject) \(detail)")
    }

    // MARK: the pass

    func check(_ c: StationController) {
        if !scanned, c.clock > 2 { scanned = true; scanShapes(c) }
        minions(c)
        shuttlesOverhead(c)
        shuttleNoses(c)
        rockets(c)
        phases(c)
        if c.clock - slowAt >= Invariants.slowEvery {
            slowAt = c.clock
            crates(c)
        }
    }

    // MARK: crates

    private struct Standing {
        let name: String
        let station: String
        let repo: String
        let number: Int
        let pos: SIMD3<Double>
        let half: Double
    }

    private func standing(_ c: StationController) -> [Standing] {
        var out: [Standing] = []
        for n in c.markerRoot.childNodes {
            guard let name = n.name, name.hasPrefix("storage:") || name.hasPrefix("deck:") || name.hasPrefix("decon:") else { continue }
            let parts = name.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let bits = parts[1].split(separator: "|")
            guard bits.count == 3, let number = Int(bits[2]) else { continue }
            let p = n.worldPosition
            let (lo, hi) = n.boundingBox
            out.append(Standing(name: name, station: String(bits[0]), repo: String(bits[1]), number: number,
                                pos: SIMD3(Double(p.x), Double(p.y), Double(p.z)),
                                half: Double(max(hi.x - lo.x, hi.z - lo.z)) / 2))
        }
        return out
    }

    private func merged(_ c: StationController) {
        guard let fate = c.sim?.pullState else { return }
        for station in c.fleet.stations.values {
            for row in station.ledger.crates.values where (row.placed != nil || row.at != nil) && row.placed != .decon {
                if fate(row.repo, row.number) == "CLOSED" {
                    flag("a crate is a merged pull request", "\(station.name)|\(row.repo)#\(row.number)", "its pull request closed without merging")
                }
            }
        }
    }

    private func crates(_ c: StationController) {
        merged(c)
        let all = standing(c)
        var counts: [String: Int] = [:]
        for s in all { counts[s.name, default: 0] += 1 }

        var live: Set<String> = []
        for s in all where counts[s.name] == 1 && !s.name.hasPrefix("decon:") {
            live.insert(s.name)
            let crate = CrateRef(station: s.station, repo: s.repo, number: s.number)
            if c.world.crate(crate)?.inTransit == true { resting[s.name] = nil; continue }
            let tested = c.world.crate(crate)?.cleared ?? false
            defer { restingTested[s.name] = tested }
            if restingTested[s.name] == true, !tested { resting[s.name] = s.pos; continue }
            if let was = resting[s.name] {
                let d = ((was.x - s.pos.x) * (was.x - s.pos.x) + (was.y - s.pos.y) * (was.y - s.pos.y)
                         + (was.z - s.pos.z) * (was.z - s.pos.z)).squareRoot()
                if d > 0.01 {
                    flag("a set-down crate does not move", s.name,
                         String(format: "moved %.2f from (%.2f, %.2f, %.2f) to (%.2f, %.2f, %.2f)",
                                d, was.x, was.y, was.z, s.pos.x, s.pos.y, s.pos.z))
                    resting[s.name] = s.pos
                }
            } else {
                resting[s.name] = s.pos
            }
        }
        for name in resting.keys where !live.contains(name) { resting[name] = nil; restingTested[name] = nil }

        for (i, a) in all.enumerated() {
            guard let station = c.fleet.stations[a.station] else { continue }
            let local = SIMD2(a.pos.x - station.offset.x, a.pos.z - station.offset.y)
            let cell = Cell(x: Int(local.x.rounded()), y: Int(local.y.rounded()))
            if !floor(of: station).contains(cell) {
                flag("a crate is never in a wall", a.name, "stands on \(cell.x),\(cell.y), which is not floor")
            }
            for b in all[(i + 1)...] where b.station == a.station {
                guard abs(a.pos.y - b.pos.y) < 0.2 else { continue }
                let dx = abs(a.pos.x - b.pos.x), dz = abs(a.pos.z - b.pos.z)
                let reach = (a.half + b.half) * 0.6
                if dx < reach && dz < reach {
                    flag("a crate is never inside another crate", a.name + " / " + b.name,
                         String(format: "%.2f apart in x, %.2f in z", dx, dz))
                }
            }
            for m in c.minions.values where m.station == a.station && a.pos.y < 0.5 {
                let dx = abs(m.pos.x - local.x), dz = abs(m.pos.y - local.y)
                if dx < 0.2 && dz < 0.2 && !m.hasLoad {
                    flag("a crate is never inside a minion", a.name + " / " + m.id,
                         String(format: "%.2f apart in x, %.2f in z · crate at %.2f,%.2f · %@",
                                dx, dz, local.x, local.y, (m.current?.words ?? "nothing") as NSString))
                }
            }
            for (spot, half) in furnishings(c, station: station) {
                if abs(spot.x - local.x) < half + a.half * 0.6 && abs(spot.y - local.y) < half + a.half * 0.6 {
                    flag("a crate is never inside furniture", a.name,
                         String(format: "furniture at %.2f,%.2f", spot.x, spot.y))
                }
            }
        }

        var rows: [String: [Standing]] = [:]
        for s in all where !s.name.hasPrefix("decon:") {
            guard let station = c.fleet.stations[s.station] else { continue }
            rows["\(s.station)|\(Int((s.pos.z - station.offset.y).rounded()))", default: []].append(s)
        }
        for (_, row) in rows {
            var column: [Standing] = []
            func settle() {
                guard !column.isEmpty else { return }
                let levels = Set(column.map { Int(($0.pos.y / 0.34).rounded()) })
                if let top = levels.max(), top > 0 {
                    let missing = (0..<top).filter { !levels.contains($0) }
                    if !missing.isEmpty, let highest = column.max(by: { $0.pos.y < $1.pos.y }) {
                        flag("stacks are built from the floor", highest.name,
                             "level \(top) with nothing on level \(missing.map(String.init).joined(separator: ", "))")
                    }
                }
                column = []
            }
            for s in row.sorted(by: { $0.pos.x < $1.pos.x }) {
                if let last = column.last, s.pos.x - last.pos.x > 0.24 { settle() }
                column.append(s)
            }
            settle()
        }
    }

    private func floor(of station: Station) -> Set<Cell> {
        let signature = station.rooms.count * 1000 + station.rooms.values.reduce(0) { $0 + $1.cells.count }
        if let cached = floorCache[station.name], cached.signature == signature { return cached.cells }
        var cells = Set(station.coreCells)
        cells.formUnion(station.hangarCells)
        cells.formUnion(station.airlockCells)
        cells.formUnion(station.hall.padCells)
        cells.formUnion(station.hall.cells)
        cells.formUnion(station.hall.deconCells)
        cells.formUnion(station.corridorCells)
        for room in station.rooms.values { cells.formUnion(room.cells) }
        floorCache[station.name] = (signature, cells)
        return cells
    }

    private func furnishings(_ c: StationController, station: Station) -> [(SIMD2<Double>, Double)] {
        let size = c.staticRoot.childNodes.count
        if size != furnitureAt {
            furnitureAt = size
            furniture = [:]
            for n in c.staticRoot.childNodes {
                guard let name = n.name, name.hasPrefix("room:"), n.geometry != nil, !(n.geometry is SCNPlane) else { continue }
                let key = String(name.dropFirst(5))
                guard let bar = key.firstIndex(of: "|"), let st = c.fleet.stations[String(key[..<bar])] else { continue }
                let (lo, hi) = n.boundingBox
                let half = Double(max(hi.x - lo.x, hi.z - lo.z)) / 2 * 0.8
                furniture[st.name, default: []].append(
                    (SIMD2(Double(n.position.x) - st.offset.x, Double(n.position.z) - st.offset.y), half))
            }
        }
        return furniture[station.name] ?? []
    }

    // MARK: minions

    private func minions(_ c: StationController) {
        let all = Array(c.minions.values)
        for (i, m) in all.enumerated() {
            if m.state == .settled, m.path.isEmpty {
                if m.current == nil {
                    flag("a minion is always doing something with a name", m.id, "settled with no command")
                } else if m.current!.words.trimmingCharacters(in: .whitespaces).isEmpty {
                    flag("a minion is always doing something with a name", m.id, "command \(m.current!.id) has no words")
                }
            }
            for other in all[(i + 1)...] where other.station == m.station {
                if let a = m.couch, let b = other.couch, a == b {
                    flag("two never share a couch", pair(m.id, other.id), "couch \(a)")
                }
                if let a = m.bed, let b = other.bed, a == b {
                    flag("two never share a bed", pair(m.id, other.id), "bed \(a)")
                }
            }
            let kit = c.kit(m)
            if m.showsBathPixels != kit.pixels || m.showsTowel != kit.towel || m.holding != kit.tool {
                flag("a prop belongs to the activity that put it there", m.id,
                     "wearing pixels \(m.showsBathPixels), towel \(m.showsTowel), \(m.holding.map { "\($0)" } ?? "empty-handed")"
                     + " while \(m.words) wants pixels \(kit.pixels), towel \(kit.towel), \(kit.tool.map { "\($0)" } ?? "empty-handed")")
            }
            if m.bathing, m.path.isEmpty, let st = c.fleet.stations[m.station], !st.cells(of: .bath).contains(m.cell) {
                flag("a visit's order never leaves its room", m.id,
                     "washing at \(m.cell.x),\(m.cell.y), which is not the bath")
            }
            if case .bath = m.current?.kind, let cur = m.current, m.phaseKind == .settle, m.phaseUntil > 0 {
                bath[m.id] = (cur.id, m.phaseUntil)
            } else if let owed = bath[m.id] {
                bath[m.id] = nil
                if c.clock < owed.until - 0.1, !m.busy {
                    flag("a visit lasts its whole time", m.id,
                         String(format: "left the bath %.1fs early", owed.until - c.clock))
                }
            }
        }
    }

    private func pair(_ a: String, _ b: String) -> String { a < b ? a + " / " + b : b + " / " + a }

    // MARK: ships

    private func shuttlesOverhead(_ c: StationController) {
        for s in c.simulation.flights {
            guard s.phaseKind == .descend || s.phaseKind == .unload else { continue }
            let local = SIMD2(s.pos.x, s.pos.z)
            var passenger: String?
            var order: Int?
            switch s.command.kind {
            case .flight(.bringWorker(let id), _, _), .flight(.takeWorker(let id), _, _): passenger = id
            case .flight(.dropCrate(let o), _, _): order = o
            default: break
            }
            for m in c.minions.values where m.station == s.station && m.id != passenger {
                if let order, case .deliverOffice(let k) = m.current?.kind, k == order { continue }
                let d = ((m.pos.x - local.x) * (m.pos.x - local.x) + (m.pos.y - local.y) * (m.pos.y - local.y)).squareRoot()
                if d < 0.5 {
                    flag("nobody walks under a shuttle", s.station + " / " + m.id,
                         String(format: "%.2f from the ship in phase %d: body at %.2f,%.2f doing %@, ship at %.2f,%.2f on %@", d, s.phase, m.pos.x, m.pos.y, m.words, local.x, local.y, s.command.words))
                }
            }
        }
    }

    private func shuttleNoses(_ c: StationController) {
        for s in c.simulation.flights {
            guard let h = s.heading, let v = c.shuttleViews[ObjectIdentifier(s)], !v.posedByLook,
                  s.progress(at: c.clock) > 0.4 else { continue }
            let flat = (h.x * h.x + h.z * h.z).squareRoot()
            guard flat > 0.05 else { continue }
            var off = (atan2(-h.z, h.x) - v.yaw).truncatingRemainder(dividingBy: 2 * .pi)
            if off > .pi { off -= 2 * .pi } else if off < -.pi { off += 2 * .pi }
            if abs(off) > .pi / 2 {
                flag("a ship flies the way it is pointing", s.station + " / " + s.command.words,
                     String(format: "%.0f degrees off its heading in phase %d", abs(off) * 180 / .pi, s.phase))
            }
        }
    }

    private func rockets(_ c: StationController) {
        for r in c.simulation.rockets.values {
            guard case .launch = r.stage, r.phaseKind == .climb else { continue }
            guard launched.insert(r.key).inserted else { continue }
            let deck = c.world.stagingIsDeck(station: r.station, repo: r.repo)
            let prefix = "\(deck ? "deck" : "storage"):\(r.station)|\(r.repo)|"
            let left = c.markerRoot.childNodes.filter { ($0.name ?? "").hasPrefix(prefix) }.count
            let arms = c.world.carriedCount(station: r.station, repo: r.repo)
            if left > 0 || arms > 0 {
                flag("a rocket leaves only with its cargo aboard", r.key,
                     "\(left) crate(s) still \(deck ? "on the deck" : "in storage"), \(arms) on someone's arms")
            }
        }
    }

    // MARK: phases

    private func phases(_ c: StationController) {
        for m in c.minions.values {
            guard let cur = m.current else { lastPhase[m.id] = nil; continue }
            step("minion " + m.id, id: cur.id, phase: m.phase)
        }
        for s in c.simulation.flights { step("shuttle " + s.station + " \(s.command.id)", id: s.command.id, phase: s.phase) }
        for r in c.simulation.rockets.values { step("rocket " + r.key, id: r.command.id, phase: r.phase) }
    }

    private func step(_ who: String, id: Int, phase: Int) {
        if let was = lastPhase[who], was.id == id, phase < was.phase {
            flag("phases only go forward", who, "command \(id) went from phase \(was.phase) back to \(phase)")
        }
        lastPhase[who] = (id, phase)
    }

    // MARK: nothing is round

    private func scanShapes(_ c: StationController) {
        var found: [String: String] = [:]
        c.scene.rootNode.enumerateHierarchy { node, _ in
            guard let g = node.geometry, node.categoryBitMask & (Pick.planet | Pick.colony | Pick.onboard) == 0 else { return }
            let name = node.name ?? g.name ?? String(describing: type(of: g))
            switch g {
            case is SCNSphere: found[name] = "SCNSphere"
            case let cyl as SCNCylinder where cyl.radialSegmentCount > 8: found[name] = "SCNCylinder, \(cyl.radialSegmentCount) sides"
            case let cone as SCNCone where cone.radialSegmentCount > 8: found[name] = "SCNCone, \(cone.radialSegmentCount) sides"
            case let tube as SCNTube where tube.radialSegmentCount > 8: found[name] = "SCNTube, \(tube.radialSegmentCount) sides"
            default: break
            }
        }
        for (name, what) in found.sorted(by: { $0.key < $1.key }) {
            flag("nothing is round", name, what)
        }
    }
}
