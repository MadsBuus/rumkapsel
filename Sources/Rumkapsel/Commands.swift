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
    /// How long a carry may wait for a carrier, in station seconds, before it is let land where it stands.
    let patience: Double?
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
        /// Packing the office's crate for a pull request just opened, cones cleared first.
        case pack(office: String)
        /// Stowing the cube for a commit that just landed, where the office keeps its cubes.
        case stow(office: String)
        case leave
        case sleep
        case work(office: String)
        /// A shuttle flight to one bay slot: a new worker, or an office's crate.
        case flight(kind: Flight, station: String, slot: Int)
        /// A rocket on the pad, one stage at a time.
        case rocket(stage: RocketStage, station: String, repo: String)
        /// A teammate acting on something they just did, until the time runs out.
        case react(activity: Activity, place: Place, for: TimeInterval)
        /// The dispatcher's errand: clipboard in hand, to the storage console to order a pallet.
        case dispatch(station: String, repo: String, number: Int)
        /// Lifting a repository's crates off their slots and onto the pallet, one at a time.
        case loadPallet(station: String, repo: String)
        /// Standing by: at the console for a pallet, or beside a loaded one for the merge.
        case waitPallet(station: String, repo: String)
        /// Hands on its edge, the pallet pushed out of storage and across to the deck.
        case pushPallet(station: String, repo: String)
        /// Floating the crates off again: onto the deck, or back into storage when the release closed.
        case unloadPallet(station: String, repo: String, back: Bool)
    }

    enum Bath { case shower, quick }

    /// What a shuttle is carrying in.
    enum Flight: Equatable {
        case bringWorker(String)
        case dropCrate(roomKey: String)
    }

    /// A rocket's stages, in the order they can only ever go.
    enum RocketStage: Equatable {
        case standBy, load(Int), steam, launch

        /// Stages only move forward: a wish for an earlier one is stale and ignored.
        var rank: Int {
            switch self {
            case .standBy: return 0
            case .load: return 1
            case .steam: return 2
            case .launch: return 3
            }
        }
    }

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
        /// In the middle of something that lasts its whole time, a shower say: not now.
        case act
        /// A shuttle coming down onto its slot: not now.
        case descend
        /// A shuttle setting its cargo out: not now.
        case unload
        /// A shuttle lifting off the slot again.
        case rise
        /// A shuttle on its way out of the frame.
        case leave
        /// A rocket taking its crates aboard.
        case load
        /// A rocket on its way up: nothing stops that.
        case climb

        var interruptible: Bool {
            switch self {
            case .walk, .approach, .settle, .load: return true
            case .lift, .setDown, .stepOut, .haul, .descend, .unload, .rise, .leave, .climb, .act: return false
            }
        }
        /// Carrying can be redirected, but only to another destination for the crate on the arms.
        var takesNewDestination: Bool { self == .haul }
    }

    var phases: [Phase] { Command.phases(of: kind) }
    /// The kind without its payload: "carry", "bath", "goTo".
    var kindName: String { String(String(describing: kind).split(separator: "(").first ?? "") }

    static func phases(of kind: Kind) -> [Phase] {
        switch kind {
        case .carry, .deliverOffice: return [.walk, .approach, .lift, .haul, .setDown]
        case .leave: return [.walk, .stepOut]
        case .flight: return [.approach, .descend, .unload, .rise, .leave]
        case .pushPallet: return [.walk, .approach, .haul]
        case .dispatch, .loadPallet, .waitPallet, .unloadPallet: return [.walk, .act]   // a pallet errand is a job: nothing calls the operator away
        case .bath, .pack, .stow: return [.walk, .act]   // a visit lasts its whole time; so does packing
        case .rocket(let stage, _, _):
            switch stage {
            case .standBy, .steam: return [.settle]
            case .load: return [.load]
            case .launch: return [.load, .climb]
            }
        default: return [.walk, .settle]
        }
    }

    /// Carrying and delivering are jobs: they hold something and may not simply be dropped.
    var isJob: Bool {
        switch kind {
        case .carry, .deliverOffice, .leave: return true
        case .dispatch, .loadPallet, .waitPallet, .pushPallet, .unloadPallet: return true
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

    init(kind: Kind, words: String, patience: Double? = nil, after: [Int] = []) {
        self.id = Command.nextCommandId()
        self.kind = kind
        self.words = words
        self.patience = patience
        self.after = after
    }

    // MARK: the usual ones

    static func carry(_ crate: CrateRef, from: Spot, to: Spot, within seconds: TimeInterval = 90, after: [Int] = []) -> Command {
        Command(kind: .carry(crate: crate, from: from, to: to),
                words: "carrying \(crate.words) to \(to.words)",
                patience: seconds, after: after)
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

    static func stow(office: String) -> Command {
        Command(kind: .stow(office: office), words: "stowing a cube for the commit")
    }

    static func pack(office: String) -> Command {
        Command(kind: .pack(office: office), words: "packing a crate for the pull request")
    }

    static func qa(deck station: String) -> Command {
        Command(kind: .qa(deck: station), words: "walking the rows on the deck")
    }

    static let leave = Command(kind: .leave, words: "off the station through the airlock")

    /// A shuttle on its way in. `what` is what the log and the bubble call the cargo.
    static func flight(_ flight: Flight, station: String, slot: Int, what: String) -> Command {
        Command(kind: .flight(kind: flight, station: station, slot: slot),
                words: "shuttle inbound with \(what)")
    }

    static func rocket(_ stage: RocketStage, station: String, repo: String) -> Command {
        let words: String
        switch stage {
        case .standBy: words = "\(repo) standing by on the pad"
        case .load(let n): words = "loading \(n == 1 ? "one crate" : "\(n) crates") of \(repo) into the rocket"
        case .steam: words = "\(repo) loaded and steaming, waiting for the release to merge"
        case .launch: words = "\(repo) lifting off"
        }
        return Command(kind: .rocket(stage: stage, station: station, repo: repo), words: words)
    }

    // MARK: the pallet

    static func dispatch(station: String, repo: String, number: Int) -> Command {
        Command(kind: .dispatch(station: station, repo: repo, number: number),
                words: "off to the storage console with the clipboard")
    }

    static func loadPallet(station: String, repo: String) -> Command {
        Command(kind: .loadPallet(station: station, repo: repo), words: "loading the pallet for \(repo)")
    }

    static func waitPallet(station: String, repo: String, words: String) -> Command {
        Command(kind: .waitPallet(station: station, repo: repo), words: words)
    }

    static func pushPallet(station: String, repo: String) -> Command {
        Command(kind: .pushPallet(station: station, repo: repo), words: "pushing the pallet to the deck")
    }

    static func unloadPallet(station: String, repo: String, back: Bool) -> Command {
        Command(kind: .unloadPallet(station: station, repo: repo, back: back),
                words: back ? "unloading the pallet back into storage" : "unloading the pallet")
    }

    /// A teammate acting on what they just did: coding in their office, walking the halls, at the core.
    static func react(_ activity: Activity, place: Place, for seconds: TimeInterval, words: String) -> Command {
        Command(kind: .react(activity: activity, place: place, for: seconds), words: words)
    }

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
        /// On the pallet: three rows of four, stacked when there are more than twelve.
        case pallet(row: Int, column: Int, level: Int)
    }

    /// A crate's place on the pallet: three rows of four, counted from the floor of the pallet up.
    struct PalletSlot: Equatable { var row: Int; var column: Int; var level: Int }

    /// The one hover pallet a station may have out, and what stands on it.
    struct Pallet {
        enum State: String { case arriving, loading, loaded, moving, unloading }
        var repo: String
        var number: Int
        /// Where it stands: a storage cell on the row nearest the deck, or a deck cell once pushed.
        var cell: Cell
        var pos: SIMD3<Double>
        var state: State
        /// Its crates by `CrateRef.key`, each on its own slot.
        var crates: [String: PalletSlot] = [:]
    }

    /// Where every crate the station has moved by hand stands, by `CrateRef.key`.
    private(set) var crates: [String: Placement] = [:]
    /// Offices on the floor whose crate has not been walked in yet, by "station|roomKey".
    private(set) var pendingOffices: Set<String> = []
    /// Office crates a shuttle has set down in the bay, waiting to be fetched, by "station|roomKey".
    private(set) var bayCrates: Set<String> = []
    /// The crate each merged office's package became, by office key ("station|roomKey"), from the
    /// moment its haul was ordered. Whether it has left is read off the crate's placement, never a flag.
    private(set) var officeCrates: [String: CrateRef] = [:]
    /// What each actor is doing, by minion id: its command and how far into it.
    var jobs: [String: (command: Command, phase: Int)] = [:]
    /// One pallet per station at a time, by station name.
    private(set) var pallets: [String: Pallet] = [:]
    /// Pallets asked for while one is out, in the order they were asked for.
    private(set) var palletQueue: [String: [(repo: String, number: Int)]] = [:]

    // MARK: the pallet

    /// Asks for a pallet. A repository already waiting or already out keeps its place in the queue.
    mutating func queuePallet(station: String, repo: String, number: Int) {
        if pallets[station]?.repo == repo { return }
        if palletQueue[station, default: []].contains(where: { $0.repo == repo }) { return }
        palletQueue[station, default: []].append((repo, number))
    }

    /// What the station should put out next, if it has nothing out already.
    func nextPallet(station: String) -> (repo: String, number: Int)? {
        guard pallets[station] == nil else { return nil }
        return palletQueue[station]?.first
    }

    mutating func startPallet(station: String, repo: String, number: Int, cell: Cell, pos: SIMD3<Double>) {
        palletQueue[station] = palletQueue[station]?.filter { $0.repo != repo }
        pallets[station] = Pallet(repo: repo, number: number, cell: cell, pos: pos, state: .arriving)
    }

    mutating func setPallet(station: String, state: Pallet.State) { pallets[station]?.state = state }
    mutating func movePallet(station: String, cell: Cell, pos: SIMD3<Double>) {
        pallets[station]?.cell = cell; pallets[station]?.pos = pos
    }

    mutating func putOnPallet(_ crate: CrateRef, at slot: PalletSlot) {
        pallets[crate.station]?.crates[crate.key] = slot
        crates[crate.key] = .pallet(row: slot.row, column: slot.column, level: slot.level)
    }

    mutating func takeOffPallet(_ crate: CrateRef) { pallets[crate.station]?.crates[crate.key] = nil }

    /// The pallet is gone: it took nothing with it, everything on it has been set down by now.
    mutating func endPallet(station: String) { pallets[station] = nil }

    func isOnPallet(_ crate: CrateRef) -> Bool {
        if case .pallet = crates[crate.key] { return true }
        return false
    }
    func isOnPallet(station: String, repo: String, number: Int) -> Bool {
        isOnPallet(CrateRef(station: station, repo: repo, number: number))
    }
    /// How many of a repository's crates the pallet holds right now.
    func palletCount(station: String, repo: String) -> Int {
        pallets[station].map { p in p.crates.keys.filter { $0.hasPrefix("\(station)|\(repo)|") }.count } ?? 0
    }

    // MARK: crates

    func carrier(of crate: CrateRef) -> String? {
        if case .carried(let who) = crates[crate.key] { return who }
        return nil
    }

    /// A crate on someone's arms is truth from the pickup: nothing else may be told to move it.
    func isCarried(_ crate: CrateRef) -> Bool { carrier(of: crate) != nil }
    /// How many of a repository's crates are on someone's arms right now.
    func carriedCount(station: String, repo: String) -> Int {
        crates.filter { key, placement in
            if case .carried = placement { return key.hasPrefix("\(station)|\(repo)|") }
            return false
        }.count
    }
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
        takeOffPallet(crate)
        crates[crate.key] = .slot(area: spot.area, cell: spot.cell, level: spot.level)
    }

    mutating func forget(_ crate: CrateRef) { crates[crate.key] = nil }

    /// Whatever this minion was holding is no longer on anyone's arms.
    mutating func dropped(by minion: String) {
        for (k, p) in crates where p == .carried(by: minion) { crates[k] = nil }
    }

    // MARK: office hauls

    /// A merged office's package is to go to storage: spoken for from now on.
    mutating func haulOrdered(office key: String, crate: CrateRef) {
        officeCrates[key] = crate
        claimed(crate)
    }
    func haulOrdered(office key: String) -> Bool { officeCrates[key] != nil }
    /// Ordered and not yet down anywhere in the yard: on the floor of the office still, spoken for,
    /// or on someone's arms.
    func haulUnderway(office key: String) -> Bool { haulOrdered(office: key) && !haulLanded(office: key) }
    /// The package is down in the yard, or on a pallet already: the office may clear.
    func haulLanded(office key: String) -> Bool {
        guard let c = officeCrates[key] else { return false }
        switch crates[c.key] {
        case .slot(let area, _, _): return area != .office
        case .pallet: return true
        default: return false
        }
    }
    mutating func forgetOffice(_ key: String) { officeCrates[key] = nil }

    // MARK: offices

    mutating func officeOrdered(_ key: String) { pendingOffices.insert(key) }
    @discardableResult
    mutating func officeDelivered(_ key: String) -> Bool { bayCrates.remove(key); return pendingOffices.remove(key) != nil }
    func isPending(_ key: String) -> Bool { pendingOffices.contains(key) }
    mutating func renameOffice(from old: String, to new: String) {
        if pendingOffices.remove(old) != nil { pendingOffices.insert(new) }
        if bayCrates.remove(old) != nil { bayCrates.insert(new) }
    }

    /// A shuttle has set an office's crate down in the bay: from here a carrier may pick it up.
    mutating func crateInBay(_ key: String) { bayCrates.insert(key) }
    func isInBay(_ key: String) -> Bool { bayCrates.contains(key) }
    mutating func tookFromBay(_ key: String) { bayCrates.remove(key) }

    // MARK: the pad

    /// Crates of a repository already set down on the rocket.
    func aboard(station: String, repo: String) -> Int {
        crates.filter { key, placement in
            guard key.hasPrefix("\(station)|\(repo)|") else { return false }
            if case .slot(let area, _, _) = placement { return area == .pad }
            return false
        }.count
    }

    /// The rocket left: what it carried is off the station.
    mutating func clearPad(station: String, repo: String) {
        for (key, placement) in crates where key.hasPrefix("\(station)|\(repo)|") {
            if case .slot(let area, _, _) = placement, area == .pad { crates[key] = nil }
        }
    }
}
