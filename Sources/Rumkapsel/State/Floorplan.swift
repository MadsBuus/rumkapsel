import Foundation

struct Floorplan {
    struct Slot {
        let cells: [Cell]
        let hall: [Cell]
        let ring: Int
    }

    let seed: Int
    let quarters: [String: [Cell]]
    let base: [Cell]
    let slots: [Slot]

    let allHall: Set<Cell>
    let slotOf: [Cell: Int]

    static func forStation(_ name: String, theme: Theme = Theme.forPlan) -> Floorplan {
        let pool = all(theme)
        return pool[Int(stableHash(name) % UInt64(pool.count))]
    }

    private static var cached: [Theme: [Floorplan]] = [:]
    static func all(_ theme: Theme = Theme.forPlan) -> [Floorplan] {
        if let c = cached[theme] { return c }
        let plans = BakedPlans.forTheme(theme).map { parse($0) }
        cached[theme] = plans
        return plans
    }

    // MARK: reading the bake

    private static func cell(_ s: Substring) -> Cell {
        let p = s.split(separator: ",")
        return Cell(x: Int(p[0]) ?? 0, y: Int(p[1]) ?? 0)
    }
    private static func cells(_ s: Substring) -> [Cell] {
        s.isEmpty ? [] : s.split(separator: ";").map(cell)
    }

    private static func parse(_ text: String) -> Floorplan {
        var seed = 0
        var quarters: [String: [Cell]] = [:]
        var base: [Cell] = []
        var slots: [Slot] = []
        for line in text.split(separator: "\n") {
            let line = line.trimmingCharacters(in: .whitespaces)[...]
            guard let eq = line.firstIndex(of: "=") else { continue }
            let body = line[line.index(after: eq)...]
            switch line[..<eq] {
            case "seed": seed = Int(body) ?? 0
            case "base": base = cells(body)
            case "quarters":
                for part in body.split(separator: "|") {
                    guard let colon = part.firstIndex(of: ":") else { continue }
                    quarters[String(part[..<colon])] = cells(part[part.index(after: colon)...])
                }
            case "offices":
                for part in body.split(separator: "|") {
                    let f = part.split(separator: "/", maxSplits: 2, omittingEmptySubsequences: false)
                    slots.append(Slot(cells: cells(f[0]),
                                      hall: f.count > 1 ? cells(f[1]) : [],
                                      ring: f.count > 2 ? (Int(f[2]) ?? 0) : 0))
                }
            default: break
            }
        }
        var allHall = Set(base)
        var slotOf: [Cell: Int] = [:]
        for (i, s) in slots.enumerated() {
            allHall.formUnion(s.hall)
            for c in s.cells { slotOf[c] = i }
        }
        let plan = Floorplan(seed: seed, quarters: quarters, base: base, slots: slots,
                             allHall: allHall, slotOf: slotOf)
        plan.check()
        return plan
    }

    // MARK: what the bake promises

    func check() {
        var lit = Set(base)
        let rooms = Set(quarters.values.joined())
        precondition(!lit.isEmpty, "plan \(seed): nothing is lit before the offices")
        precondition(connected(lit, through: lit.union(rooms)), "plan \(seed): the base hallway is in pieces")
        for (name, cs) in quarters {
            let way = Station.opensInto["kind:" + name].map { Set(quarters[String($0.dropFirst(5))] ?? []) } ?? lit
            precondition(cs.contains { c in c.neighbours.contains { way.contains($0) } },
                         "plan \(seed): the \(name) has no way in before any office opens")
        }
        for (i, slot) in slots.enumerated() {
            lit.formUnion(slot.hall)
            precondition(connected(lit, through: lit.union(rooms)), "plan \(seed): the hallway broke at office \(i)")
            precondition(slot.cells.contains { c in c.neighbours.contains { lit.contains($0) } },
                         "plan \(seed): office \(i) opens with no door")
            precondition(!slot.cells.contains { lit.contains($0) || rooms.contains($0) },
                         "plan \(seed): office \(i) stands on hallway or the quarters")
        }
    }

    private func connected(_ want: Set<Cell>, through floor: Set<Cell>) -> Bool {
        guard let start = want.first else { return true }
        var seen: Set<Cell> = [start]
        var queue = [start]
        var head = 0
        while head < queue.count {
            let c = queue[head]; head += 1
            for n in c.neighbours where floor.contains(n) && !seen.contains(n) { seen.insert(n); queue.append(n) }
        }
        return want.isSubset(of: seen)
    }
}

enum OfficePlacement: String, CaseIterable, Identifiable {
    case rings
    case byRepo

    var id: String { rawValue }
    var title: String {
        switch self {
        case .rings: return "In rings from the middle"
        case .byRepo: return "Beside their repository"
        }
    }

    static var pinned: OfficePlacement?
    static var current: OfficePlacement { pinned ?? ConfigStore.shared.current.officePlacement }
}
