import Foundation

/// Commands and station truth: the seam between what the world wants and what is on the floor.
///
/// Reconciliation compares the two and issues `Command`s as values. Actors — minions, mostly — run
/// one command at a time, phase by phase. Completions write `StationTruth` and nothing else, so a
/// source catching up later cannot undo what a minion just did.

/// One crate on a station: whose repository, which pull request.
struct CrateRef: Hashable {
    var station: String
    var repo: String
    var number: Int

    var key: String { "\(station)|\(repo)|\(number)" }
    var words: String { number > 0 ? "#\(number)" : "a crate" }
}

/// Somewhere on the floor a crate can stand, and enough to walk there.
struct Spot {
    enum Area: String { case office, bay, storage, deck, tested, pad, floor }
    var area: Area
    var station: String
    /// The room key of an office, the repository of a yard row; empty elsewhere.
    var owner = ""
    /// What to call it out loud: an office's name, a repository's.
    var label = ""
    var cell: Cell
    var pos: SIMD3<Double>
    /// How high in a stack: 0 on the floor, 1 at waist height, 2 and up a reach. `pos.y` follows it.
    var level = 0
    /// Which way the crate stands there, so a set-down ends turned as the layout will redraw it.
    var yaw = 0.0

    var words: String {
        switch area {
        case .office: return label.isEmpty ? "the office" : label
        case .bay: return "the bay"
        case .storage: return "storage"
        case .deck: return "the deck"
        case .tested: return "the deck, tested row"
        case .pad: return "the rocket"
        case .floor: return "the floor"
        }
    }
}

/// A job, as a value. Everything a minion or a prop can be asked to do.
struct Command {
    let id: Int
    let kind: Kind
    /// Commands that must finish first: the crates stacked above this one, moved aside.
    let after: [Int]
    /// Must be true by: after this the reconciler stops waiting for the carry and lets the change
    /// appear where it stands.
    let deadline: Date?
    /// For the log and the speech bubble.
    let words: String

    enum Kind {
        /// A crate from one spot to another: an office's package to storage, storage to the deck,
        /// the untested row to the tested one, either to the rocket.
        case carry(crate: CrateRef, from: Spot, to: Spot)
        /// Fetch a new office's crate from the bay and walk it in.
        case deliverOffice(key: String)
        /// Somewhere to be: the lounge, the dorm, the hallway.
        case goTo(place: Place)
        case bath(kind: Bath, back: Place)
        case chore(spot: Cell)
        case qa(deck: String)
        case leave
        case sleep
        case work(office: String)
    }

    enum Bath { case shower, quick }

    /// A command is a sequence of phases; the actor holds an index into it.
    enum Phase {
        /// Walking there: anything may cut in.
        case walk
        /// Shuffling to arm's length of the crate: still fine to cut in.
        case approach
        /// Crouched with the crate coming up past the chest: not now.
        case lift
        /// Carrying: only a new destination for the same crate may cut in.
        case haul
        /// Setting it down squarely: not now.
        case setDown
        /// Stepping out of the shuttle: not now.
        case stepOut
        /// Being there: resting, working, walking the rows.
        case settle

        var interruptible: Bool {
            switch self {
            case .walk, .approach, .settle: return true
            case .lift, .setDown, .stepOut, .haul: return false
            }
        }
        /// Carrying can be redirected, but only to another destination for the crate on the arms.
        var takesNewDestination: Bool { self == .haul }
    }

    var phases: [Phase] { Command.phases(of: kind) }

    static func phases(of kind: Kind) -> [Phase] {
        switch kind {
        case .carry, .deliverOffice: return [.walk, .approach, .lift, .haul, .setDown]
        case .leave: return [.walk, .stepOut]
        default: return [.walk, .settle]
        }
    }

    /// Carrying and delivering are jobs: they hold something and may not simply be dropped.
    var isJob: Bool {
        switch kind {
        case .carry, .deliverOffice, .leave: return true
        default: return false
        }
    }

    /// Resting: the couch and the bed only pull on a minion while one of these is current.
    var isRest: Bool {
        switch kind {
        case .goTo, .sleep, .work: return true
        default: return false
        }
    }

    var crate: CrateRef? {
        if case .carry(let c, _, _) = kind { return c }
        return nil
    }

    private static var nextId = 0
    static func nextCommandId() -> Int { nextId += 1; return nextId }

    init(kind: Kind, words: String, deadline: Date? = nil, after: [Int] = []) {
        self.id = Command.nextCommandId()
        self.kind = kind
        self.words = words
        self.deadline = deadline
        self.after = after
    }

    // MARK: the usual ones

    static func carry(_ crate: CrateRef, from: Spot, to: Spot, within seconds: TimeInterval = 90, after: [Int] = []) -> Command {
        Command(kind: .carry(crate: crate, from: from, to: to),
                words: "carrying \(crate.words) to \(to.words)",
                deadline: Date().addingTimeInterval(seconds), after: after)
    }

    static func deliverOffice(key: String, name: String) -> Command {
        Command(kind: .deliverOffice(key: key), words: "fetching \(name) from the bay")
    }

    static func bath(_ kind: Bath, back: Place) -> Command {
        Command(kind: .bath(kind: kind, back: back),
                words: "off to the bath, back to \(back.words) after")
    }

    static func chore(spot: Cell) -> Command {
        Command(kind: .chore(spot: spot), words: "having a look round the station")
    }

    static func qa(deck station: String) -> Command {
        Command(kind: .qa(deck: station), words: "walking the rows on the deck")
    }

    static let leave = Command(kind: .leave, words: "off the station through the airlock")

    /// Where a minion should be when it has no job: asleep in the dorm, at work in its office, or just there.
    static func rest(place: Place, home: String, name: String, asleep: Bool) -> Command {
        if asleep && place == .quarters { return Command(kind: .sleep, words: "asleep in the dorm") }
        if place == .room(home), !home.hasPrefix("kind:") {
            return Command(kind: .work(office: home), words: "waiting for you in \(name)")
        }
        return Command(kind: .goTo(place: place), words: "heading for \(place.words)")
    }
}

extension Place {
    /// The room as a person would say it.
    var words: String {
        switch self {
        case .core: return "the monolith"
        case .room(let key):
            switch key {
            case "kind:quarters": return "the dorm"
            case "kind:lounge": return "the couch"
            case "kind:bath": return "the bath"
            case "kind:airlock": return "the airlock"
            case "kind:hangar": return "the bay"
            case "kind:deck": return "the deck"
            case "kind:pad": return "the pad"
            default: return key.split(separator: ":").last.map(String.init) ?? key
            }
        }
    }
}

/// What is actually on the floor right now, as opposed to what the world wants. Only completions
/// write here.
struct StationTruth {
    enum Placement: Equatable {
        case slot(area: Spot.Area, cell: Cell, level: Int)
        case carried(by: String)
    }

    /// Where every crate the station has moved by hand stands, by `CrateRef.key`.
    private(set) var crates: [String: Placement] = [:]
    /// Offices on the floor whose crate has not been walked in yet, by "station|roomKey".
    private(set) var pendingOffices: Set<String> = []
    /// Crates set down in storage by hand that the source has not counted yet.
    private(set) var landed: [String: (repo: String, number: Int, at: Date)] = [:]
    /// Crates on their way from storage to the deck, by "station|repo".
    private(set) var toDeck: [String: Int] = [:]
    /// What each actor is doing, by minion id: its command and how far into it.
    var jobs: [String: (command: Command, phase: Int)] = [:]

    // MARK: crates

    func carrier(of crate: CrateRef) -> String? {
        if case .carried(let who) = crates[crate.key] { return who }
        return nil
    }

    /// A crate on someone's arms is truth from the pickup: nothing else may be told to move it.
    func isCarried(_ crate: CrateRef) -> Bool { carrier(of: crate) != nil }
    func isCarried(station: String, repo: String, number: Int) -> Bool {
        isCarried(CrateRef(station: station, repo: repo, number: number))
    }

    /// Spoken for by a command that has not found a carrier yet: already off the layout, so the crate
    /// is not drawn twice while it waits.
    mutating func claimed(_ crate: CrateRef) {
        if case .carried = crates[crate.key] { return }
        crates[crate.key] = .carried(by: "")
    }

    mutating func pickedUp(_ crate: CrateRef, by minion: String) {
        crates[crate.key] = .carried(by: minion)
    }

    mutating func setDown(_ crate: CrateRef, at spot: Spot) {
        crates[crate.key] = .slot(area: spot.area, cell: spot.cell, level: spot.level)
    }

    mutating func forget(_ crate: CrateRef) { crates[crate.key] = nil }

    /// Whatever this minion was holding is no longer on anyone's arms.
    mutating func dropped(by minion: String) {
        for (k, p) in crates where p == .carried(by: minion) { crates[k] = nil }
    }

    // MARK: what landed by hand

    mutating func landedByHand(_ crate: CrateRef, at: Date = Date()) {
        landed[crate.key] = (crate.repo, crate.number, at)
    }

    /// Numbers of hand-landed crates the source still lacks for a repository. Ones the source has
    /// caught up with, and stale ones, are forgotten here.
    mutating func freshLanded(station: String, repo: String, counted: [Int], now: Date = Date()) -> [Int] {
        for (k, l) in landed where now.timeIntervalSince(l.at) > 15 * 60 || counted.contains(l.number) { landed[k] = nil }
        return landed.filter { $0.key.hasPrefix(station + "|") && $0.value.repo == repo }.map(\.value.number).sorted()
    }

    // MARK: carries in flight

    mutating func startedToDeck(station: String, repo: String, count: Int) { toDeck[station + "|" + repo, default: 0] += count }
    mutating func finishedToDeck(station: String, repo: String) {
        let k = station + "|" + repo
        toDeck[k] = max(0, (toDeck[k] ?? 1) - 1)
    }
    func inFlightToDeck(_ key: String) -> Int { toDeck[key] ?? 0 }

    // MARK: offices

    mutating func officeOrdered(_ key: String) { pendingOffices.insert(key) }
    @discardableResult
    mutating func officeDelivered(_ key: String) -> Bool { pendingOffices.remove(key) != nil }
    func isPending(_ key: String) -> Bool { pendingOffices.contains(key) }
    mutating func renameOffice(from old: String, to new: String) {
        if pendingOffices.remove(old) != nil { pendingOffices.insert(new) }
    }
}
