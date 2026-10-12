import Foundation

enum ColorDump {
    static func run() -> Never {
        let fleet = Fleet()
        fleet.load(alone: false)
        let repos = fleet.repoColors.keys.sorted()
        print("\(repos.count) repositories over \(Colors.repos.count) palette slots")
        for r in repos {
            let c = fleet.color(forRepo: r)
            let hex = String(format: "#%02X%02X%02X", Int(c.r * 255), Int(c.g * 255), Int(c.b * 255))
            print(String(format: "  slot %2d  %@  %@", fleet.repoColors[r] ?? -1, hex, r))
        }
        var used: [String: [String]] = [:]
        for r in repos {
            let c = fleet.color(forRepo: r)
            used[String(format: "#%02X%02X%02X", Int(c.r * 255), Int(c.g * 255), Int(c.b * 255)), default: []].append(r)
        }
        let shared = used.filter { $0.value.count > 1 }
        print(shared.isEmpty ? "every repository has a colour to itself"
                             : "same colour: \(shared.map { "\($0.key) \($0.value.joined(separator: " and "))" }.joined(separator: ", "))")
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
                              ("decon", s.hall.deconCells), ("airlock", s.airlockCells), ("hangar", s.hangarCells)] {
            out.append("\"\(name)\":[\(list(cells))]")
        }
        print("{\(out.joined(separator: ","))}")
        exit(0)
    }
}
