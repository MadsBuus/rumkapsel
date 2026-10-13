import Foundation

enum Yard: String, Codable {
    case storage, deck, pad, decon

    var words: String {
        switch self {
        case .storage: return Words.current.inStorage
        case .deck: return Words.current.theDeck
        case .pad: return Words.current.theRocket
        case .decon: return Words.current.inDecon
        }
    }

    init?(area: Spot.Area) {
        switch area {
        case .storage: self = .storage
        case .deck, .tested: self = .deck
        case .pad: self = .pad
        case .decon: self = .decon
        default: return nil
        }
    }
}

struct Ledger: Codable {
    enum Placement: Codable, Equatable {
        case slot(area: Spot.Area, cell: Cell, level: Int)
        case carried(by: String)
    }

    struct Slot: Codable, Equatable { var yard: Yard; var group: Int; var column: Int; var order: Int }

    struct Crate: Codable {
        let repo: String
        let number: Int
        var wanted: Yard?
        var wantedAt: Date?
        var cleared = false
        var placed: Yard?
        var movedAt: Date?
        var heading: Yard?
        var orderedOver: Yard?
        var at: Placement?
        var slot: Slot?
        var bound: Slot?
        var alien = false

        init(repo: String, number: Int) { self.repo = repo; self.number = number }

        private enum Keys: String, CodingKey { case repo, number, wanted, wantedAt, cleared, placed, movedAt, heading, orderedOver, at, slot, bound, alien }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Keys.self)
            repo = try c.decode(String.self, forKey: .repo)
            number = try c.decode(Int.self, forKey: .number)
            wanted = try c.decodeIfPresent(Yard.self, forKey: .wanted)
            wantedAt = try c.decodeIfPresent(Date.self, forKey: .wantedAt)
            cleared = try c.decodeIfPresent(Bool.self, forKey: .cleared) ?? false
            placed = try c.decodeIfPresent(Yard.self, forKey: .placed)
            movedAt = try c.decodeIfPresent(Date.self, forKey: .movedAt)
            heading = try c.decodeIfPresent(Yard.self, forKey: .heading)
            orderedOver = try c.decodeIfPresent(Yard.self, forKey: .orderedOver)
            at = try c.decodeIfPresent(Placement.self, forKey: .at)
            slot = try c.decodeIfPresent(Slot.self, forKey: .slot)
            bound = try c.decodeIfPresent(Slot.self, forKey: .bound)
            alien = try c.decodeIfPresent(Bool.self, forKey: .alien) ?? false
        }
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: Keys.self)
            try c.encode(repo, forKey: .repo); try c.encode(number, forKey: .number)
            try c.encodeIfPresent(wanted, forKey: .wanted); try c.encodeIfPresent(wantedAt, forKey: .wantedAt)
            try c.encode(cleared, forKey: .cleared); try c.encodeIfPresent(placed, forKey: .placed)
            try c.encodeIfPresent(movedAt, forKey: .movedAt); try c.encodeIfPresent(heading, forKey: .heading)
            try c.encodeIfPresent(orderedOver, forKey: .orderedOver); try c.encodeIfPresent(at, forKey: .at)
            try c.encodeIfPresent(slot, forKey: .slot); try c.encodeIfPresent(bound, forKey: .bound)
            try c.encode(alien, forKey: .alien)
        }

        var key: String { "\(repo)|\(number)" }
        var inTransit: Bool {
            switch at {
            case .carried: return true
            default: return false
            }
        }
        var isCarried: Bool { if case .carried = at { return true }; return false }
        var carrier: String? { if case .carried(let who) = at { return who }; return nil }
        var area: Spot.Area? { if case .slot(let area, _, _) = at { return area }; return nil }
        var isEmpty: Bool { placed == nil && wanted == nil && heading == nil && at == nil }
        func stands(in yard: Yard) -> Bool { placed == yard && !inTransit }
        func belongs(to yard: Yard) -> Bool { placed == yard || heading == yard }
        var disagrees: Bool { wanted != placed && heading == nil && movedAt == nil }
    }

    private(set) var crates: [String: Crate] = [:]

    private static func key(_ repo: String, _ number: Int) -> String { "\(repo)|\(number)" }

    subscript(repo: String, number: Int) -> Crate? { crates[Ledger.key(repo, number)] }

    func crates(of repo: String) -> [Crate] { crates.values.filter { $0.repo == repo }.sorted { $0.number < $1.number } }
    var allCrates: [Crate] { Array(crates.values) }

    func holds(_ yard: Yard, repo: String) -> [Crate] { crates(of: repo).filter { $0.belongs(to: yard) } }

    func counts(in yard: Yard) -> [String: Int] {
        var out: [String: Int] = [:]
        for c in crates.values where c.placed == yard { out[c.repo, default: 0] += 1 }
        return out
    }

    func disagreements(repo: String) -> [Crate] { crates(of: repo).filter(\.disagrees) }

    // MARK: the source's side

    struct Word {
        var storage: [Int]
        var deck: [Int]
        var cleared: [Int] = []
        var updated: [Int: Date] = [:]
    }

    mutating func adopt(_ word: Word, repo: String) {
        var said: [Int: Yard] = [:]
        for n in word.storage { said[n] = .storage }
        for n in word.deck { said[n] = .deck }
        let numbers = Set(said.keys).union(crates(of: repo).map(\.number))
        for number in numbers {
            let k = Ledger.key(repo, number)
            let yard = said[number]
            var c = crates[k] ?? Crate(repo: repo, number: number)
            if c.alien, c.placed == .decon { continue }
            c.cleared = word.cleared.contains(number) || c.alien
            let at = word.updated[number]
            var news: Bool
            if let moved = c.movedAt {
                if let at { news = at > moved } else { news = yard == c.placed || (c.placed == .pad && yard == nil) }
            } else {
                news = true
            }
            if news, let at, let held = c.wantedAt, at < held { news = false }
            if news {
                c.wanted = yard
                c.wantedAt = at
                c.movedAt = nil
            }
            if c.placed == nil, c.heading == nil {
                c.placed = c.wanted
                c.movedAt = nil
            }
            if c.placed == .pad, c.wanted == nil, c.heading == nil {
                crates[k] = nil
                continue
            }
            if c.isEmpty { crates[k] = nil; continue }
            crates[k] = c
        }
    }

    mutating func adoptDecon(open: [Int], repo: String) -> (arrived: [Int], gone: [Int]) {
        var arrived: [Int] = []
        for number in open where crates[Ledger.key(repo, number)] == nil {
            var c = Crate(repo: repo, number: number)
            c.alien = true; c.wanted = .decon; c.placed = .decon; c.cleared = true
            crates[c.key] = c
            arrived.append(number)
        }
        let gone = crates(of: repo).filter { $0.alien && $0.placed == .decon && $0.heading == nil && !open.contains($0.number) }.map(\.number)
        return (arrived, gone)
    }

    // MARK: the station's side

    mutating func order(repo: String, number: Int, to yard: Yard) {
        let k = Ledger.key(repo, number)
        var c = crates[k] ?? Crate(repo: repo, number: number)
        c.heading = yard
        c.orderedOver = c.wanted
        crates[k] = c
    }

    mutating func unorder(repo: String, number: Int) {
        guard var c = crates[Ledger.key(repo, number)] else { return }
        c.heading = nil
        c.bound = nil
        crates[c.key] = c.isEmpty ? nil : c
    }

    // MARK: the physical side, written by the floor

    private mutating func place(_ repo: String, _ number: Int, _ at: Placement?) {
        var c = crates[Ledger.key(repo, number)] ?? Crate(repo: repo, number: number)
        c.at = at
        crates[c.key] = c.isEmpty ? nil : c
    }

    mutating func claim(repo: String, number: Int) {
        if self[repo, number]?.isCarried == true { return }
        place(repo, number, .carried(by: ""))
    }
    mutating func pickedUp(repo: String, number: Int, by minion: String) { place(repo, number, .carried(by: minion)) }
    mutating func setDown(repo: String, number: Int, at spot: Spot) { place(repo, number, .slot(area: spot.area, cell: spot.cell, level: spot.level)) }
    mutating func forgetPlacement(repo: String, number: Int) { place(repo, number, nil) }
    mutating func dropped(by minion: String) {
        for c in crates.values where c.carrier == minion { place(c.repo, c.number, nil) }
    }
    mutating func unload(repo: String, to yard: Yard) -> [Int] {
        var back: [Int] = []
        for var c in crates.values where c.repo == repo && c.placed == .pad && c.heading == nil && !c.inTransit {
            c.placed = yard; c.wanted = yard; c.movedAt = nil
            c.at = nil; c.slot = nil; c.bound = nil
            crates[c.key] = c
            back.append(c.number)
        }
        return back.sorted()
    }

    mutating func clearPad(repo: String) {
        for c in crates.values where c.repo == repo && c.area == .pad { place(c.repo, c.number, nil) }
    }
    mutating func forgetTransit() {
        for var c in crates.values where c.inTransit || c.bound != nil || c.heading != nil || c.movedAt != nil {
            c.at = nil; c.bound = nil; c.heading = nil; c.orderedOver = nil
            if c.placed != .pad { c.movedAt = nil }
            crates[c.key] = c.isEmpty ? nil : c
        }
    }

    func carriedCount(repo: String) -> Int { crates.values.filter { $0.repo == repo && $0.isCarried }.count }
    func aboard(repo: String) -> Int { crates.values.filter { $0.repo == repo && $0.area == .pad }.count }

    mutating func landed(repo: String, number: Int, in yard: Yard, at: Date) {
        let k = Ledger.key(repo, number)
        var c = crates[k] ?? Crate(repo: repo, number: number)
        if c.alien, c.wanted == .decon, yard != .decon { c.wanted = nil; c.orderedOver = nil }
        c.placed = yard
        let ordered = c.heading != nil
        c.heading = nil
        let changedMind = ordered && c.wanted != c.orderedOver
        c.movedAt = (c.wanted == yard || changedMind) ? nil : at
        c.orderedOver = nil
        if let b = c.bound, b.yard == yard { c.slot = b }
        c.bound = nil
        crates[k] = c
    }

    // MARK: places in the rows

    mutating func setSlot(repo: String, number: Int, _ slot: Slot?) {
        guard var c = crates[Ledger.key(repo, number)] else { return }
        c.slot = slot; crates[c.key] = c
    }
    mutating func setBound(repo: String, number: Int, _ slot: Slot?) {
        guard var c = crates[Ledger.key(repo, number)] else { return }
        c.bound = slot; crates[c.key] = c
    }

    static func place(repo: String, in yard: Yard, group: Int, among held: [(repo: String, slot: Slot)], cap: Int, avoiding: Int? = nil, tall: Bool = false) -> Slot {
        let here = held.filter { $0.slot.yard == yard && $0.slot.group == group }
        func height(_ column: Int) -> Int { here.filter { $0.slot.column == column }.count }
        func next(_ column: Int) -> Slot { Slot(yard: yard, group: group, column: column, order: (here.filter { $0.slot.column == column }.map(\.slot.order).max() ?? -1) + 1) }
        let tiles = Set(here.filter { $0.repo == repo }.map { $0.slot.column / 2 })
        let mine = tiles.flatMap { [$0 * 2, $0 * 2 + 1] }.filter { $0 < max(cap, 1) && $0 != avoiding }
        func lowest(_ columns: [Int], under limit: Int) -> Int? {
            columns.filter { height($0) < limit }.min { (height($0), $0) < (height($1), $1) }
        }
        if let column = lowest(mine, under: tall ? 12 : 3) { return next(column) }
        let taken = Set(here.map { $0.slot.column / 2 })
        if let tile = (0..<max(cap / 2, 1)).first(where: { !taken.contains($0) && $0 * 2 != avoiding }) { return next(tile * 2) }
        if let column = lowest(mine, under: .max) { return next(column) }
        return next(0)
    }

    mutating func snap(repo: String, number: Int) {
        guard var c = crates[Ledger.key(repo, number)], c.heading == nil else { return }
        c.placed = c.wanted
        c.movedAt = nil
        if c.placed == nil { crates[c.key] = nil } else { crates[c.key] = c }
    }

    mutating func forget(repo: String, number: Int) { crates[Ledger.key(repo, number)] = nil }

    mutating func forget(repo: String) { crates = crates.filter { $0.value.repo != repo } }
}
