// Printing a theme's fixed floor, so the generator that draws the plans works against the real thing
// rather than a copy of it: `--dump-floor classic`. The yard, the airlock and the bay are the app's,
// with all their doorways and lanes; a baked plan only ever adds hallway and offices around them.

import Foundation

enum ColorDump {
    /// What colour each repository actually has, for when a station reads as three colours and there
    /// are five repositories on it.
    static func run() -> Never {
        let fleet = Fleet()
        fleet.load()
        let repos = fleet.repoColors.keys.sorted()
        print("\(repos.count) repositories over \(Colors.repos.count) palette slots")
        for r in repos {
            let c = fleet.color(forRepo: r)
            let hex = String(format: "#%02X%02X%02X", Int(c.r * 255), Int(c.g * 255), Int(c.b * 255))
            print(String(format: "  slot %2d  %@  %@", fleet.repoColors[r] ?? -1, hex, r))
        }
        var used: [Int: Int] = [:]
        for r in repos { used[(fleet.repoColors[r] ?? 0) % Colors.repos.count, default: 0] += 1 }
        let shared = used.filter { $0.value > 1 }
        print(shared.isEmpty ? "every repository has a slot to itself"
                             : "slots shared: \(shared.map { "slot \($0.key) by \($0.value)" }.joined(separator: ", "))")
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
        for (name, cells) in [("storage", s.storageCells), ("deck", s.deckCells), ("pad", s.padCells),
                              ("decon", s.deconCells), ("airlock", s.airlockCells), ("hangar", s.hangarCells)] {
            out.append("\"\(name)\":[\(list(cells))]")
        }
        print("{\(out.joined(separator: ","))}")
        exit(0)
    }
}
