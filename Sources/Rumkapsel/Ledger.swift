import Foundation

/// A yard a crate can belong to: storage, the deck (both its rows), or the pad, meaning aboard the
/// rocket standing there.
enum Yard: String, Codable {
    case storage, deck, pad

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
        /// When the station last set it down by hand; nil once the source has agreed with that.
        var handAt: Date?
        /// Where a carry under way is taking it: its slot there is spoken for from the order.
        var heading: Yard?

        var key: String { "\(repo)|\(number)" }
        /// Where the rows draw it or hold a slot for it: the yard it belongs to, or the one it is bound for.
        func belongs(to yard: Yard) -> Bool { placed == yard || heading == yard }
        /// The source and the station disagree, nothing is carrying it, and the source's word is the
        /// newer one: a hand landing the source has not caught up with is the station's to keep.
        var disagrees: Bool { wanted != placed && heading == nil && handAt == nil }
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
            if let hand = c.handAt {
                // Against a hand landing, the source's word counts only if it is newer; with no time to
                // go by, only if it agrees. A crate aboard the rocket that the source counts nowhere any
                // more has shipped: that is agreement too.
                if let at { news = at > hand } else { news = yard == c.placed || (c.placed == .pad && yard == nil) }
            } else {
                news = true
            }
            // An older word than the one already held, a peer's lagging copy of the board say, is not news either.
            if news, let at, let held = c.wantedAt, at < held { news = false }
            if news {
                // A newer word from the source outranks the station's hand, agreeing or not.
                c.wanted = yard
                c.wantedAt = at
                c.handAt = nil
            }
            if c.placed == nil, c.heading == nil {
                // Never touched here: the source's word is the station's word.
                c.placed = c.wanted
                c.handAt = nil
            }
            if c.placed == .pad, c.wanted == nil, c.heading == nil {
                // Aboard, and the source no longer counts it anywhere: it lifted off with the rocket.
                crates[k] = nil
                continue
            }
            if c.placed == nil, c.wanted == nil, c.heading == nil { crates[k] = nil; continue }
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
        if c.placed == nil, c.wanted == nil { crates[c.key] = nil } else { crates[c.key] = c }
    }

    /// A completion: the crate is down in a yard, by hand. The station's word from here until the
    /// source catches up.
    mutating func landed(repo: String, number: Int, in yard: Yard, at: Date) {
        let k = Ledger.key(repo, number)
        var c = crates[k] ?? Crate(repo: repo, number: number)
        c.placed = yard
        c.heading = nil
        c.handAt = c.wanted == yard ? nil : at
        crates[k] = c
    }

    /// What cannot be carried is redrawn where the source says, once.
    mutating func snap(repo: String, number: Int) {
        guard var c = crates[Ledger.key(repo, number)], c.heading == nil else { return }
        c.placed = c.wanted
        c.handAt = nil
        if c.placed == nil { crates[c.key] = nil } else { crates[c.key] = c }
    }

    /// Everything of a repository forgotten: the source is gone from the fleet.
    mutating func forget(repo: String) { crates = crates.filter { $0.value.repo != repo } }
}
