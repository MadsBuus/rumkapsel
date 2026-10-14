import Foundation

enum ColorDump {
    static func run() -> Never {
        let fleet = Fleet()
        fleet.load(alone: false)
        let cfg = ConfigStore.shared.current
        let repos = Set(fleet.stations.values.flatMap { $0.rooms.values.compactMap(\.repo) }).filter { !$0.isEmpty }.sorted()
        print("\(repos.count) repositories on the floor, \(Colors.repos.count) palette slots")
        func hex(_ c: RGB) -> String { String(format: "#%02X%02X%02X", Int(c.r * 255), Int(c.g * 255), Int(c.b * 255)) }
        for r in repos {
            let c = fleet.color(forRepo: r)
            let from = cfg.repos[r]?.color != nil ? "settings" : fleet.repoColors[r].map { "slot \($0)" } ?? "?"
            print("  \(from.padding(toLength: 9, withPad: " ", startingAt: 0))  \(hex(c))  \(r)")
        }
        let pairs = repos.enumerated().flatMap { i, a in repos[(i + 1)...].map { (a, $0, fleet.color(forRepo: a).distance(to: fleet.color(forRepo: $0))) } }
        for (a, b, d) in pairs.sorted(by: { $0.2 < $1.2 }).prefix(3) { print(String(format: "  closest  %.3f  %@ and %@", d, a, b)) }
        exit(0)
    }
}

enum FloorDump {
    static func run(theme: String) -> Never {
        Theme.pinnedForPlan = Theme(rawValue: theme) ?? .classic
        let s = Station(name: "work")
        func list(_ cells: [Cell]) -> String {
            cells.map { "[\($0.x),\($0.y)]" }.joined(separator: ",")
        }
        let plan = s.plan
        var out: [String] = []
        out.append("\"plaza\":[\(list(plan.plaza))]")
        out.append("\"monolith\":[\(plan.monolith.x),\(plan.monolith.y)]")
        out.append("\"west\":[\(list(plan.west))]")
        out.append("\"south\":[\(list(plan.south))]")
        for (name, cells) in [("hall", s.hall.cells), ("pad", s.hall.padCells),
                              ("decon", s.hall.deconCells), ("hangar", s.hangarCells), ("bayMargin", s.bayMargin)] {
            out.append("\"\(name)\":[\(list(cells))]")
        }
        print("{\(out.joined(separator: ","))}")
        exit(0)
    }
}
