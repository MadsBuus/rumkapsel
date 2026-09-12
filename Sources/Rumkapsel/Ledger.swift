import Foundation

/// A yard a crate can belong to: storage, the deck (both its rows), or the pad, meaning aboard the
/// rocket standing there.
enum Yard: String, Codable {
    case storage, deck, pad

    /// What to call it out loud.
    var words: String {
        switch self {
        case .storage: return "storage"
        case .deck: return "the deck"
        case .pad: return "the rocket"
        }
    }

    init?(area: Spot.Area) {
        switch area {
        case .storage: self = .storage
        case .deck, .tested: self = .deck
        case .pad: self = .pad
        default: return nil
        }
    }
}

/// The crate ledger: for every crate a station knows, where the source wants it and where the
/// station has it. Sources write `wanted`, and only through `adopt`; completions write `placed`, and
/// only through `landed`. The rows are drawn from `placed`, the counts are read off it, and nothing
/// about a crate's whereabouts is kept anywhere else.
///
/// The two sides may disagree for as long as it takes a minion to carry something. Where they
/// disagree is a queue for the reconciler, not an event: it hands out one carry per crate where a
/// carry exists, and where none does the station redraws the crate where the source says, once.
///
/// A source's word about a crate is news only if it is newer than the station's own hand on that
/// crate: a board item carries when it last moved, and an answer older than a landing is stale for
/// that crate, however fresh the poll. A source with no times of its own (git history) is believed
/// again the moment it agrees with what the station did.
struct Ledger: Codable {
    /// Where the station physically has a crate: on a slot, on someone's arms, or on the pallet.
    enum Placement: Codable, Equatable {
        case slot(area: Spot.Area, cell: Cell, level: Int)
        /// On the arms, or spoken for by a carry that has not found its carrier yet (an empty name).
        case carried(by: String)
        /// On the pallet: three rows of four, stacked when there are more than twelve.
        case pallet(row: Int, column: Int, level: Int)
    }

    /// A crate's place in a yard: which group of rows (the deck's tested or untested), which column,
    /// and the order it was given there, from which its level in the stack is ranked.
    struct Slot: Codable, Equatable { var yard: Yard; var group: Int; var column: Int; var order: Int }

    struct Crate: Codable {
        let repo: String
        let number: Int
        /// The source's word: nil once the source counts it in no yard, shipped or gone.
        var wanted: Yard?
        /// The source's own time for that word, when it has one.
        var wantedAt: Date?
        /// The tested sticker, the source's word too.
        var cleared = false
        /// The station's word: the yard it stands in, or belongs to while on someone's arms or the pallet.
        var placed: Yard?
        /// When the station last moved it, a minion, the pallet or the hatch setting it down; cleared once
        /// the source has said something newer. While set, the station's word stands over the source's.
        var movedAt: Date?
        /// Where a carry under way is taking it: its slot there is spoken for from the order.
        var heading: Yard?
        /// Where the station physically has it. Nil while the source alone has placed it: standing
        /// wherever the rows draw it.
        var at: Placement?
        /// The place it holds in the yard it stands in, given when it was set down or first drawn.
        var slot: Slot?
        /// The place spoken for ahead of it in the yard it is bound for, from the order until set-down.
        var bound: Slot?

        var key: String { "\(repo)|\(number)" }
        /// On someone's arms, spoken for, or on the pallet: not standing on its row.
        var inTransit: Bool {
            switch at {
            case .carried, .pallet: return true
            default: return false
            }
        }
        var isCarried: Bool { if case .carried = at { return true }; return false }
        var isOnPallet: Bool { if case .pallet = at { return true }; return false }
        var carrier: String? { if case .carried(let who) = at { return who }; return nil }
        /// The area it was last set down in, by hand.
        var area: Spot.Area? { if case .slot(let area, _, _) = at { return area }; return nil }
        /// A row with nothing left to say is dropped.
        var isEmpty: Bool { placed == nil && wanted == nil && heading == nil && at == nil }
        /// Standing in a yard's rows: belonging there and not on the arms or the pallet.
        func stands(in yard: Yard) -> Bool { placed == yard && !inTransit }
        /// Where the rows draw it or hold a slot for it: the yard it belongs to, or the one it is bound for.
        func belongs(to yard: Yard) -> Bool { placed == yard || heading == yard }
        /// The source and the station disagree, nothing is carrying it, and the source's word is the
        /// newer one: a move the source has not caught up with is the station's to keep.
        var disagrees: Bool { wanted != placed && heading == nil && movedAt == nil }
    }

    private(set) var crates: [String: Crate] = [:]

    private static func key(_ repo: String, _ number: Int) -> String { "\(repo)|\(number)" }

    subscript(repo: String, number: Int) -> Crate? { crates[Ledger.key(repo, number)] }

    /// Every crate of a repository, by number.
    func crates(of repo: String) -> [Crate] { crates.values.filter { $0.repo == repo }.sorted { $0.number < $1.number } }

    /// The crates a yard holds of a repository, or holds a slot for: standing, on the arms, on the
    /// pallet, or on their way in.
    func holds(_ yard: Yard, repo: String) -> [Crate] { crates(of: repo).filter { $0.belongs(to: yard) } }

    /// How many crates of each repository belong to a yard.
    func counts(in yard: Yard) -> [String: Int] {
        var out: [String: Int] = [:]
        for c in crates.values where c.placed == yard { out[c.repo, default: 0] += 1 }
        return out
    }

    /// Crates the source and the station disagree about, the source's word being news.
    func disagreements(repo: String) -> [Crate] { crates(of: repo).filter(\.disagrees) }

    // MARK: the source's side

    /// One answer from the source about a repository: which numbers it counts in storage and on the
    /// deck, which of those are tested, and the source's own time per number where it has one.
    struct Word {
        var storage: [Int]
        var deck: [Int]
        var cleared: [Int] = []
        var updated: [Int: Date] = [:]
    }

    /// The source's word, taken per crate. A crate the station has never touched follows the source
    /// at once: its first answer is where the crate is. A crate the station has set down by hand keeps
    /// the station's word until the source says something newer, or, with no time to go by, until it
    /// agrees. A crate aboard the rocket that the source has stopped counting has shipped.
    mutating func adopt(_ word: Word, repo: String) {
        var said: [Int: Yard] = [:]
        for n in word.storage { said[n] = .storage }
        for n in word.deck { said[n] = .deck }
        let numbers = Set(said.keys).union(crates(of: repo).map(\.number))
        for number in numbers {
            let k = Ledger.key(repo, number)
            let yard = said[number]
            var c = crates[k] ?? Crate(repo: repo, number: number)
            c.cleared = word.cleared.contains(number)
            let at = word.updated[number]
            var news: Bool
            if let moved = c.movedAt {
                // The station moved this crate since the source last spoke: the source's word counts only
                // if its time is later than that move; with no time to go by, only if it agrees. A crate
                // aboard the rocket that the source counts nowhere any more has shipped: agreement too.
                if let at { news = at > moved } else { news = yard == c.placed || (c.placed == .pad && yard == nil) }
            } else {
                news = true
            }
            // An older word than the one already held, a peer's lagging copy of the board say, is not news either.
            if news, let at, let held = c.wantedAt, at < held { news = false }
            if news {
                // A newer word from the source outranks the station's move, agreeing or not.
                c.wanted = yard
                c.wantedAt = at
                c.movedAt = nil
            }
            if c.placed == nil, c.heading == nil {
                // Never touched here: the source's word is the station's word.
                c.placed = c.wanted
                c.movedAt = nil
            }
            if c.placed == .pad, c.wanted == nil, c.heading == nil {
                // Aboard, and the source no longer counts it anywhere: it lifted off with the rocket.
                crates[k] = nil
                continue
            }
            if c.isEmpty { crates[k] = nil; continue }
            crates[k] = c
        }
    }

    // MARK: the station's side

    /// A carry was ordered: the crate is bound for a yard, and its slot there is spoken for.
    mutating func order(repo: String, number: Int, to yard: Yard) {
        let k = Ledger.key(repo, number)
        var c = crates[k] ?? Crate(repo: repo, number: number)
        c.heading = yard
        crates[k] = c
    }

    /// The order is off: the crate stays where it was.
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

    /// Spoken for by a carry that has not found a carrier yet: off the rows already, so it is not
    /// drawn twice while it waits.
    mutating func claim(repo: String, number: Int) {
        if self[repo, number]?.isCarried == true { return }
        place(repo, number, .carried(by: ""))
    }
    mutating func pickedUp(repo: String, number: Int, by minion: String) { place(repo, number, .carried(by: minion)) }
    mutating func setDown(repo: String, number: Int, at spot: Spot) { place(repo, number, .slot(area: spot.area, cell: spot.cell, level: spot.level)) }
    mutating func onPallet(repo: String, number: Int, row: Int, column: Int, level: Int) { place(repo, number, .pallet(row: row, column: column, level: level)) }
    /// Nowhere in particular any more: the rows draw it where the ledger says it belongs.
    mutating func forgetPlacement(repo: String, number: Int) { place(repo, number, nil) }
    /// Whatever this minion was holding is no longer on anyone's arms.
    mutating func dropped(by minion: String) {
        for c in crates.values where c.carrier == minion { place(c.repo, c.number, nil) }
    }
    /// The rocket left: what it carried is off the station's floor. The row stays, placed on the pad,
    /// until the source stops counting the crate; only then is it gone from the ledger too.
    mutating func clearPad(repo: String) {
        for c in crates.values where c.repo == repo && c.area == .pad { place(c.repo, c.number, nil) }
    }
    /// After a relaunch nothing is on anyone's arms or on a pallet, and nothing is bound anywhere:
    /// what was is standing somewhere, and asks for its place again.
    mutating func forgetTransit() {
        for var c in crates.values where c.inTransit || c.bound != nil || c.heading != nil {
            c.at = nil; c.bound = nil; c.heading = nil
            crates[c.key] = c.isEmpty ? nil : c
        }
    }

    /// How many of a repository's crates are on someone's arms right now.
    func carriedCount(repo: String) -> Int { crates.values.filter { $0.repo == repo && $0.isCarried }.count }
    /// Crates of a repository already set down on the rocket.
    func aboard(repo: String) -> Int { crates.values.filter { $0.repo == repo && $0.area == .pad }.count }

    /// A completion: the crate is down in a yard, by hand. The station's word from here until the
    /// source catches up.
    mutating func landed(repo: String, number: Int, in yard: Yard, at: Date) {
        let k = Ledger.key(repo, number)
        var c = crates[k] ?? Crate(repo: repo, number: number)
        c.placed = yard
        c.heading = nil
        c.movedAt = c.wanted == yard ? nil : at
        // Down: the place spoken for ahead is the place it holds now.
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

    /// A place in a yard for one more crate, among the places already held there: the lowest free
    /// rank on one of the repository's own columns, else the lowest column nobody holds, else the
    /// repository's shortest column, never one tower. `avoiding` is a column it may not go back to.
    static func place(repo: String, in yard: Yard, group: Int, among held: [(repo: String, slot: Slot)], cap: Int, avoiding: Int? = nil) -> Slot {
        let here = held.filter { $0.slot.yard == yard && $0.slot.group == group }
        func height(_ column: Int) -> Int { here.filter { $0.slot.column == column }.count }
        func next(_ column: Int) -> Slot { Slot(yard: yard, group: group, column: column, order: (here.filter { $0.slot.column == column }.map(\.slot.order).max() ?? -1) + 1) }
        let mine = Set(here.filter { $0.repo == repo }.map(\.slot.column)).sorted()
        for column in mine where column != avoiding && height(column) < 3 { return next(column) }
        let owned = Set(here.map(\.slot.column))
        if let free = (0..<max(cap, 1)).first(where: { !owned.contains($0) && $0 != avoiding }) { return next(free) }
        if let column = mine.filter({ $0 != avoiding }).min(by: { height($0) < height($1) }) { return next(column) }
        return next(0)
    }

    /// What cannot be carried is redrawn where the source says, once.
    mutating func snap(repo: String, number: Int) {
        guard var c = crates[Ledger.key(repo, number)], c.heading == nil else { return }
        c.placed = c.wanted
        c.movedAt = nil
        if c.placed == nil { crates[c.key] = nil } else { crates[c.key] = c }
    }

    /// One crate struck off: its pull request closed without merging, so it was never merged work.
    mutating func forget(repo: String, number: Int) { crates[Ledger.key(repo, number)] = nil }

    /// Everything of a repository forgotten: the source is gone from the fleet.
    mutating func forget(repo: String) { crates = crates.filter { $0.value.repo != repo } }
}
