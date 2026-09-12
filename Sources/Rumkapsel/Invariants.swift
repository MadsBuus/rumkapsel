// The rules of STATION.md, checked by machine.
//
// The simulator runs this at the end of every simulated step: thirty times a simulated second, so
// each check is either trivial or on the half-second slow pass. A rule that fails is written to the
// simulator log once per (rule, subject) as
//
//     VIOLATION: <rule>: <subject> <detail>
//
// and never again for that subject, so a stuck crate does not drown the log. Nothing here fixes
// anything: it only says what the floor is doing that the rulebook does not allow.

import Foundation
import SceneKit

final class Invariants {
    /// Where a violation goes: the simulator's log.
    var onViolation: ((String) -> Void)?

    /// One line per (rule, subject), ever.
    private var seen: Set<String> = []

    /// The last time the geometry pass ran, on the station clock.
    private var slowAt = -1.0
    private static let slowEvery = 0.5

    /// Set once the scene graph has been swept for round things.
    private var scanned = false

    /// Where a crate stood when it was last seen resting, by node name.
    private var resting: [String: SIMD3<Double>] = [:]
    /// Command id and phase index per actor, so a phase can only go forward.
    private var lastPhase: [String: (id: Int, phase: Int)] = [:]
    /// A bath in progress: the command it belongs to and when it is due to end.
    private var bath: [String: (id: Int, until: Double)] = [:]
    /// Rockets already checked at lift-off.
    private var launched: Set<String> = []
    /// A station's floor cells, cached until its room count changes.
    private var floorCache: [String: (signature: Int, cells: Set<Cell>)] = [:]
    /// Furniture footprints per station, cached against the static root's size.
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
        rockets(c)
        phases(c)
        if c.clock - slowAt >= Invariants.slowEvery {
            slowAt = c.clock
            crates(c)
        }
    }

    // MARK: crates

    /// One crate standing in a yard row, as the scene names it.
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
            guard let name = n.name, name.hasPrefix("storage:") || name.hasPrefix("deck:") else { continue }
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

    /// A crate that has been set down does not move; and it never stands in a wall, in another
    /// crate, in a minion or in a piece of furniture; and a stack is built from the floor.
    private func crates(_ c: StationController) {
        let all = standing(c)
        // Names are unique per crate except for unnumbered ones, which share a name: those are
        // interchangeable and no rule here can tell one from another.
        var counts: [String: Int] = [:]
        for s in all { counts[s.name, default: 0] += 1 }

        var live: Set<String> = []
        for s in all where counts[s.name] == 1 {
            live.insert(s.name)
            let crate = CrateRef(station: s.station, repo: s.repo, number: s.number)
            // On someone's arms, on the pallet or in the air: it is allowed to move.
            if c.world.crate(crate)?.inTransit == true { resting[s.name] = nil; continue }
            if c.pallets[s.station]?.flight != nil { continue }
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
        for name in resting.keys where !live.contains(name) { resting[name] = nil }

        // Nothing inside anything else.
        for (i, a) in all.enumerated() {
            guard let station = c.fleet.stations[a.station] else { continue }
            let local = SIMD2(a.pos.x - station.offset.x, a.pos.z - station.offset.y)
            let cell = Cell(x: Int(local.x.rounded()), y: Int(local.y.rounded()))
            if !floor(of: station).contains(cell) {
                flag("a crate is never in a wall", a.name, "stands on \(cell.x),\(cell.y), which is not floor")
            }
            for b in all[(i + 1)...] where b.station == a.station {
                guard abs(a.pos.y - b.pos.y) < 0.2 else { continue }   // a stack, not an overlap
                let dx = abs(a.pos.x - b.pos.x), dz = abs(a.pos.z - b.pos.z)
                // Well inside the sum of the halves: storage nudges a crate about, and two on
                // neighbouring columns may lean towards each other without being in each other.
                let reach = (a.half + b.half) * 0.6
                if dx < reach && dz < reach {
                    flag("a crate is never inside another crate", a.name + " / " + b.name,
                         String(format: "%.2f apart in x, %.2f in z", dx, dz))
                }
            }
            for m in c.minions.values where m.station == a.station && a.pos.y < 0.5 {
                let dx = abs(m.pos.x - local.x), dz = abs(m.pos.y - local.y)
                if dx < 0.2 && dz < 0.2 && m.carried == nil {
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

        // Stacks are built from the floor: no crate with air under it. Columns are half a cell apart
        // and storage nudges each crate by up to a tenth, so a column is a cluster in x along its
        // row rather than a rounding. A level is 0.34 high.
        var rows: [String: [Standing]] = [:]
        for s in all {
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

    /// A station's floor, from the parts that make it: the yard, the bay, the corridor and the rooms.
    private func floor(of station: Station) -> Set<Cell> {
        let signature = station.rooms.count * 1000 + station.rooms.values.reduce(0) { $0 + $1.cells.count }
        if let cached = floorCache[station.name], cached.signature == signature { return cached.cells }
        var cells = Set(station.coreCells)
        cells.formUnion(station.hangarCells)
        cells.formUnion(station.airlockCells)
        cells.formUnion(station.padCells)
        cells.formUnion(station.storageCells)
        cells.formUnion(station.deckCells)
        cells.formUnion(station.corridorCells)
        for room in station.rooms.values { cells.formUnion(room.cells) }
        floorCache[station.name] = (signature, cells)
        return cells
    }

    /// Everything standing on a room's floor that is not a tile: beds, couches, the shower, the desks.
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
            // One thing at a time, and it has a name.
            if m.state == .settled, m.path.isEmpty {
                if m.current == nil {
                    flag("a minion is always doing something with a name", m.id, "settled with no command")
                } else if m.current!.words.trimmingCharacters(in: .whitespaces).isEmpty {
                    flag("a minion is always doing something with a name", m.id, "command \(m.current!.id) has no words")
                }
            }
            for other in all[(i + 1)...] where other.station == m.station {
                if m.path.isEmpty, other.path.isEmpty {
                    let d = ((m.pos.x - other.pos.x) * (m.pos.x - other.pos.x)
                             + (m.pos.y - other.pos.y) * (m.pos.y - other.pos.y)).squareRoot()
                    if d < 0.15 {
                        flag("two minions never share a spot", pair(m.id, other.id), String(format: "%.3f apart", d))
                    }
                }
                if let a = m.couch, let b = other.couch, a == b {
                    flag("two never share a couch", pair(m.id, other.id), "couch \(a)")
                }
                if let a = m.bed, let b = other.bed, a == b {
                    flag("two never share a bed", pair(m.id, other.id), "bed \(a)")
                }
            }
            // A visit lasts its whole time.
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

    /// A shuttle leaves before anyone walks under it.
    private func shuttlesOverhead(_ c: StationController) {
        for s in c.shuttles {
            let rise = s.command.phases.firstIndex(of: .rise) ?? Int.max
            guard s.phase < rise else { continue }
            let p = s.node.worldPosition
            guard let station = c.fleet.stations[s.station] else { continue }
            let local = SIMD2(Double(p.x) - station.offset.x, Double(p.z) - station.offset.y)
            for m in c.minions.values where m.station == s.station {
                let d = ((m.pos.x - local.x) * (m.pos.x - local.x) + (m.pos.y - local.y) * (m.pos.y - local.y)).squareRoot()
                if d < 0.5 {
                    flag("nobody walks under a shuttle", s.station + " / " + m.id,
                         String(format: "%.2f from the ship in phase %d", d, s.phase))
                }
            }
        }
    }

    /// A rocket leaves only with its cargo aboard: nothing of its repository left on the deck or
    /// on anyone's arms when the climb starts.
    private func rockets(_ c: StationController) {
        for r in c.rocketActors.values {
            // The launch command loads first; the rule is about the moment the climb begins.
            guard case .launch = r.stage, r.phaseKind == .climb else { continue }
            guard launched.insert(r.key).inserted else { continue }
            let prefix = "deck:\(r.station)|\(r.repo)|"
            let left = c.markerRoot.childNodes.filter { ($0.name ?? "").hasPrefix(prefix) }.count
            let arms = c.world.carriedCount(station: r.station, repo: r.repo)
            if left > 0 || arms > 0 {
                flag("a rocket leaves only with its cargo aboard", r.key,
                     "\(left) crate(s) still on the deck, \(arms) on someone's arms")
            }
        }
    }

    // MARK: phases

    /// A command's phases only ever go forward. A new command id starts again from anywhere.
    private func phases(_ c: StationController) {
        for m in c.minions.values {
            guard let cur = m.current else { lastPhase[m.id] = nil; continue }
            // The pallet push is legs, not phases: each corner sends the pusher back to walking
            // round to the new back side, on the same command. Nothing else may rewind.
            if case .pushPallet = cur.kind { lastPhase["minion " + m.id] = nil; continue }
            step("minion " + m.id, id: cur.id, phase: m.phase)
        }
        for s in c.shuttles { step("shuttle " + s.station + " \(s.command.id)", id: s.command.id, phase: s.phase) }
        for r in c.rocketActors.values { step("rocket " + r.key, id: r.command.id, phase: r.phase) }
    }

    private func step(_ who: String, id: Int, phase: Int) {
        if let was = lastPhase[who], was.id == id, phase < was.phase {
            flag("phases only go forward", who, "command \(id) went from phase \(was.phase) back to \(phase)")
        }
        lastPhase[who] = (id, phase)
    }

    // MARK: nothing is round

    /// One sweep of the scene graph: a sphere, or a cylinder, cone or tube smooth enough to read as
    /// round, is a shape the rulebook does not have.
    private func scanShapes(_ c: StationController) {
        var found: [String: String] = [:]
        c.scene.rootNode.enumerateHierarchy { node, _ in
            guard let g = node.geometry else { return }
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
