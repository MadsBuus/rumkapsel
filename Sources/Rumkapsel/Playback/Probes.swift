import Foundation

enum Probe {
    static let atMonolith = 6.0...10.0
    static let atHome = 2.0...4.0
    static let dockFade = 2.5
}

extension Simulation {
    func probePlace(_ m: B) -> Place {
        guard let st = fleet.stations[m.station] else { return .core }
        let office = Place.room(m.home.key)
        guard standing(st, m.home.key) else { return .core }
        return m.activity == .researching && !m.tripHome ? .core : office
    }

    func unclaimed(_ cells: [Cell], by m: B) -> [Cell] {
        let others = bodies.values.filter { $0.id != m.id && $0.station == m.station && $0.state != .leaving }
        let held = Set(others.map(\.cell) + others.compactMap { $0.path.last.map { Cell(x: Int($0.x.rounded()), y: Int($0.y.rounded())) } })
        return cells.filter { !held.contains($0) }
    }

    func parent(of m: B) -> B? {
        bodies.values.first { $0.station == m.station && !$0.isSubagent && $0.home.key == m.home.key && $0.state != .leaving }
    }

    func makeRoom(_ m: B, station: Station) {
        guard bodies.values.contains(where: { $0.id != m.id && $0.station == m.station && $0.state != .leaving && $0.cell == m.cell }) else { return }
        let near = station.cells(of: m.place).sorted { abs($0.x - m.cell.x) + abs($0.y - m.cell.y) < abs($1.x - m.cell.x) + abs($1.y - m.cell.y) }
        guard let free = unclaimed(near.filter { $0 != m.cell && !station.thresholds.contains($0) }, by: m).first else { return }
        m.path = route(m, to: free)
    }

    func tripOn(_ m: B, station: Station) {
        guard m.activity == .researching, m.state == .settled else { m.tripHome = false; return }
        if m.tripSince == 0 { m.tripSince = clock }
        let dwell = m.tripHome ? Probe.atHome : Probe.atMonolith
        guard m.place == restPlace(m), clock - m.tripSince >= dwell.lowerBound + (dwell.upperBound - dwell.lowerBound) * m.bobPhase / 6.28 else { return }
        m.tripHome.toggle()
        m.tripSince = 0
        send(m, to: restPlace(m))
    }

    func dock(_ m: B, station: Station, dt: Double) -> Outcome {
        let target = parent(of: m)?.cell ?? station.cells(of: .room(m.home.key)).first
        if let target, abs(m.cell.x - target.x) + abs(m.cell.y - target.y) > 1 {
            let beside = target.neighbours.filter { station.walkable.contains($0) && station.canStep(from: $0, to: target) }
            let to = unclaimed(beside, by: m).min { abs($0.x - m.cell.x) + abs($0.y - m.cell.y) < abs($1.x - m.cell.x) + abs($1.y - m.cell.y) } ?? target
            let path = route(m, to: to)
            if !path.isEmpty { m.path = path; return .posed }
        }
        m.opacity -= dt / Probe.dockFade
        return m.opacity <= 0 ? .gone : .posed
    }
}
