import Foundation

struct CrateRef: Hashable {
    var station: String
    var repo: String
    var number: Int

    var key: String { "\(station)|\(repo)|\(number)" }
    var words: String { "#\(number)" }
}

struct Spot: Equatable {
    enum Area: String, Codable { case office, storage, deck, tested, pad, decon }
    var area: Area
    var station: String
    var owner = ""
    var label = ""
    var cell: Cell
    var pos: SIMD3<Double>
    var level = 0
    var yaw = 0.0

    var words: String {
        switch area {
        case .office: return label.isEmpty ? "the office" : label
        case .storage: return Words.current.inStorage
        case .deck: return Words.current.theDeck
        case .tested: return Words.current.testedRow
        case .pad: return Words.current.theRocket
        case .decon: return Words.current.inDecon
        }
    }
}

struct Command {
    let id: Int
    let kind: Kind
    let words: String

    enum Kind {
        case carry(crate: CrateRef, from: Spot, to: Zone)
        case deliverOffice(order: Int)
        case goTo(place: Place)
        case exercise(kind: Workout, back: Place, seconds: Double)
        case galley(fare: Fare, back: Place, seconds: Double)
        case use(FixtureRef, kind: FixtureKind, back: Place, seconds: Double)
        case chore(spot: Cell, seconds: Double)
        case qa(deck: String)
        case pack(office: String)
        case stow(office: String)
        case leave
        case sleep
        case work(office: String)
        case flight(kind: Flight, station: String, slot: Int)
        case react(activity: Activity, place: Place, for: TimeInterval)
    }

    enum Workout: Int, CaseIterable {
        case treadmill, bench, bag, mat
        var words: String {
            switch self {
            case .treadmill: return "a run on the treadmill"
            case .bench: return "a few presses on the bench"
            case .bag: return "a round on the bag"
            case .mat: return "jumping jacks on the mat"
            }
        }
        var doing: String {
            switch self {
            case .treadmill: return "running on the treadmill"
            case .bench: return "pressing on the bench"
            case .bag: return "boxing the bag"
            case .mat: return "doing jumping jacks on the mat"
            }
        }
    }

    enum Fare: CaseIterable {
        case coffee, bite
        var words: String { self == .coffee ? Words.current.coffee : Words.current.bite }
        var doing: String { "waiting on \(words)" }
        var seconds: ClosedRange<Double> {
            let printed = Galley.printSeconds + Galley.slideSeconds + Galley.pickSeconds
            return self == .coffee ? 18...26 : printed...printed
        }
    }

    enum Flight: Equatable {
        case bringWorker(String)
        case dropCrate(order: Int)
        case takeWorker(String)
    }

    enum Phase {
        case walk
        case approach
        case lift
        case haul
        case setDown
        case stepOut
        case settle
        case act
        case descend
        case unload
        case rise
        case leave

        var interruptible: Bool {
            switch self {
            case .walk, .approach, .settle: return true
            case .lift, .setDown, .stepOut, .haul, .descend, .unload, .rise, .leave, .act: return false
            }
        }
        var takesNewDestination: Bool { self == .haul }
    }

    var phases: [Phase] { Command.phases(of: kind) }
    var kindName: String { String(String(describing: kind).split(separator: "(").first ?? "") }

    static func phases(of kind: Kind) -> [Phase] {
        switch kind {
        case .carry, .deliverOffice: return [.walk, .approach, .lift, .haul, .setDown]
        case .leave: return [.walk, .stepOut]
        case .flight: return [.approach, .descend, .unload, .rise, .leave]
        case .exercise, .galley, .use, .pack, .stow: return [.walk, .act]
        default: return [.walk, .settle]
        }
    }

    var isJob: Bool {
        switch kind {
        case .carry, .deliverOffice, .leave: return true
        default: return false
        }
    }

    var isRest: Bool {
        switch kind {
        case .goTo, .sleep, .work: return true
        default: return false
        }
    }

    var holdsMug: Bool {
        switch kind {
        case .chore, .qa: return true
        default: return false
        }
    }

    var crate: CrateRef? {
        if case .carry(let c, _, _) = kind { return c }
        return nil
    }

    private static var nextId = 0
    static func nextCommandId() -> Int { nextId += 1; return nextId }

    init(kind: Kind, words: String) {
        self.id = Command.nextCommandId()
        self.kind = kind
        self.words = words
    }

    private init(id: Int, kind: Kind, words: String) {
        self.id = id; self.kind = kind; self.words = words
    }

    func from(_ spot: Spot) -> Command {
        guard case .carry(let crate, _, let to) = kind else { return self }
        return Command(id: id, kind: .carry(crate: crate, from: spot, to: to), words: words)
    }

    func carrying(from spot: Spot, to zone: Zone, words: String) -> Command {
        guard case .carry(let crate, _, _) = kind else { return self }
        return Command(id: id, kind: .carry(crate: crate, from: spot, to: zone), words: words)
    }

    var office: String? {
        switch kind {
        case .pack(let o), .stow(let o), .work(let o): return o
        default: return nil
        }
    }

    var chore: Int? {
        switch kind {
        case .pack: return 0
        case .stow: return 1
        default: return nil
        }
    }

    func moved(from old: String, to new: String) -> Command {
        switch kind {
        case .pack(let o) where o == old: return Command(id: id, kind: .pack(office: new), words: words)
        case .stow(let o) where o == old: return Command(id: id, kind: .stow(office: new), words: words)
        case .work(let o) where o == old: return Command(id: id, kind: .work(office: new), words: words)
        default: return self
        }
    }

    func reworded(_ words: String) -> Command {
        Command(id: id, kind: kind, words: words)
    }

    // MARK: the usual ones

    static func carry(_ crate: CrateRef, from: Spot, to: Zone, words: String? = nil) -> Command {
        Command(kind: .carry(crate: crate, from: from, to: to), words: words ?? "carrying \(crate.words) to \(to.words)")
    }

    static func deliverOffice(order: Int, name: String) -> Command {
        Command(kind: .deliverOffice(order: order), words: "fetching \(name) from \(Words.current.theBay)")
    }

    static func exercise(_ kind: Workout, back: Place, seconds: Double) -> Command {
        Command(kind: .exercise(kind: kind, back: back, seconds: seconds), words: "off to \(Words.current.theGym) for \(kind.words), back to \(back.words) after")
    }

    static func galley(_ fare: Fare, back: Place, seconds: Double) -> Command {
        Command(kind: .galley(fare: fare, back: back, seconds: seconds), words: "off to \(Words.current.theGalley) for \(fare.words), back to \(back.words) after")
    }

    static func use(_ ref: FixtureRef, kind: FixtureKind, back: Place, seconds: Double) -> Command {
        Command(kind: .use(ref, kind: kind, back: back, seconds: seconds),
                words: "off to \(Place.room(ref.room).words) to \(kind.going), back to \(back.words) after")
    }

    static func chore(spot: Cell, seconds: Double) -> Command {
        Command(kind: .chore(spot: spot, seconds: seconds), words: Words.current.lookRound)
    }

    var visitSeconds: Double? {
        switch kind {
        case .exercise(_, _, let s), .galley(_, _, let s), .use(_, _, _, let s), .chore(_, let s): return s
        default: return nil
        }
    }

    static func stow(office: String) -> Command {
        Command(kind: .stow(office: office), words: Words.current.stow)
    }

    static func pack(office: String) -> Command {
        Command(kind: .pack(office: office), words: Words.current.pack)
    }

    static func qa(deck station: String) -> Command {
        Command(kind: .qa(deck: station), words: Words.current.qaWalk)
    }

    static var leave: Command { Command(kind: .leave, words: Words.current.leaving) }

    static func flight(_ flight: Flight, station: String, slot: Int, what: String) -> Command {
        Command(kind: .flight(kind: flight, station: station, slot: slot),
                words: "\(Words.current.inbound) \(what)")
    }

    static func react(_ activity: Activity, place: Place, for seconds: TimeInterval, words: String) -> Command {
        Command(kind: .react(activity: activity, place: place, for: seconds), words: words)
    }

    static func rest(place: Place, home: String, office: String, yours: Bool, asleep: Bool) -> Command {
        if asleep && place == .quarters { return Command(kind: .sleep, words: Words.current.asleep) }
        if place == .room(home), !home.hasPrefix("kind:") {
            return Command(kind: .work(office: home), words: (yours ? "waiting for you in " : "at work in ") + office)
        }
        return Command(kind: .goTo(place: place), words: "heading for \(place.words)")
    }
}

extension Place {
    var hereWords: String {
        switch self {
        case .core: return "by " + Words.current.theMonolith
        case .lounge: return "on " + Words.current.theCouch
        default: return "in " + words
        }
    }

    var words: String {
        switch self {
        case .core: return Words.current.theMonolith
        case .room(let key):
            switch key {
            case "kind:quarters": return Words.current.theDorm
            case "kind:lounge": return Words.current.theCouch
            case "kind:bath": return Words.current.theBath
            case "kind:gym": return Words.current.theGym
            case "kind:galley": return Words.current.theGalley
            case "kind:mission": return Words.current.theMission
            case "kind:hangar": return Words.current.theBay
            case "kind:deck": return Words.current.theDeck
            case "kind:pad": return Words.current.thePad
            default: return key.split(separator: ":").last.map(String.init) ?? key
            }
        }
    }
}
