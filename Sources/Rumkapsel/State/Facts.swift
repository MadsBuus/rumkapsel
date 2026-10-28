import Foundation

extension Stage: Codable {}

struct CrateID: Hashable, Codable, Comparable, CustomStringConvertible {
    let repo: String
    let number: Int
    static func < (a: CrateID, b: CrateID) -> Bool { (a.repo, a.number) < (b.repo, b.number) }
    var description: String { "\(repo)#\(number)" }
}

typealias RocketID = String

enum Zone: String, Codable, CaseIterable {
    case waiting, testing, cleared, decon

    var isRow: Bool { self != .decon }
    var crateSize: Double { self == .decon ? 0.3 : 0.38 }
    static let crateHeight = 0.8
    var stackStep: Double { crateSize * Zone.crateHeight }

    var words: String {
        switch self {
        case .waiting: return Words.current.inStorage
        case .testing: return Words.current.theDeck
        case .cleared: return Words.current.testedRow
        case .decon: return Words.current.inDecon
        }
    }
}

struct CrateFact: Codable, Equatable {
    enum Place: Hashable, Codable {
        case office(String)
        case waiting, testing, cleared
        case decon
        case aboard(RocketID)

        init(_ zone: Zone) {
            switch zone {
            case .waiting: self = .waiting
            case .testing: self = .testing
            case .cleared: self = .cleared
            case .decon: self = .decon
            }
        }

        var zone: Zone? {
            switch self {
            case .waiting: return .waiting
            case .testing: return .testing
            case .cleared: return .cleared
            case .decon: return .decon
            case .office, .aboard: return nil
            }
        }
    }

    let id: CrateID
    var place: Place
    var stage: Stage?
    var alien = false
    var seq: Int
    var column: Int?
    var closedAt: Date?
    var storedAt: Date?

    var cleared: Bool { alien || (stage.map { $0 >= .cleared } ?? false) }
    var zone: Zone? { place.zone }
    var onRow: Bool { zone?.isRow ?? false }

    init(id: CrateID, place: Place, stage: Stage? = nil, alien: Bool = false, seq: Int, column: Int? = nil, closedAt: Date? = nil) {
        self.id = id; self.place = place; self.stage = stage; self.alien = alien; self.seq = seq; self.column = column; self.closedAt = closedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(CrateID.self, forKey: .id)
        place = try c.decode(Place.self, forKey: .place)
        stage = try c.decodeIfPresent(Stage.self, forKey: .stage)
        alien = try c.decodeIfPresent(Bool.self, forKey: .alien) ?? false
        seq = try c.decodeIfPresent(Int.self, forKey: .seq) ?? 0
        column = try c.decodeIfPresent(Int.self, forKey: .column)
        closedAt = try c.decodeIfPresent(Date.self, forKey: .closedAt)
        storedAt = try c.decodeIfPresent(Date.self, forKey: .storedAt)
    }
}

struct OfficeFact: Codable, Equatable {
    enum Via: Equatable { case appear, fade, shuttle(for: String?) }

    let key: String
    var repo: String?
    var crate: CrateID?
    var merged = false
    var closedAt: Date?
    var via: Via = .appear

    init(key: String, repo: String?, via: Via = .appear) { self.key = key; self.repo = repo; self.via = via }

    func keyed(_ key: String) -> OfficeFact {
        var o = OfficeFact(key: key, repo: repo, via: via)
        o.crate = crate; o.merged = merged; o.closedAt = closedAt
        return o
    }

    enum CodingKeys: String, CodingKey { case key, repo, crate, merged, closedAt }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = try c.decode(String.self, forKey: .key)
        repo = try c.decodeIfPresent(String.self, forKey: .repo)
        crate = try c.decodeIfPresent(CrateID.self, forKey: .crate)
        merged = try c.decodeIfPresent(Bool.self, forKey: .merged) ?? false
        closedAt = try c.decodeIfPresent(Date.self, forKey: .closedAt)
    }
}

struct StagingFact: Codable, Equatable {
    var number: Int
    var merged = false
    var deploy: Deploy = .unheard
    var mergedAt: Date?
    var heardAt: Date?
    enum Deploy: Codable, Equatable { case unheard, running(since: Date, usual: TimeInterval), live, failed }

    var underway: Bool { merged && deploy != .live }

    func settled(at now: Date) -> Bool {
        guard merged else { return false }
        switch deploy {
        case .unheard, .failed: return now.timeIntervalSince(heardAt ?? mergedAt ?? .distantPast) > Deployments.findWithin
        case .running(let since, let usual): return now.timeIntervalSince(since) > usual * 3 + Deployments.findWithin
        case .live: return number == 0 && now.timeIntervalSince(heardAt ?? .distantPast) > 60
        }
    }
}

struct RocketFact: Codable, Equatable {
    enum Kind: Codable, Equatable { case release, hotfix(Int), merge }

    let id: RocketID
    let repo: String
    var kind: Kind
    var slot: Int?
    var label: String
    var docked = false
    var go = false
    var launchedAt: Date?

    init(id: RocketID, repo: String, kind: Kind, label: String, docked: Bool = false) {
        self.id = id; self.repo = repo; self.kind = kind; self.label = label; self.docked = docked
    }

    var launched: Bool { launchedAt != nil }
}

struct RepoFacts: Codable, Equatable {
    var hasStaging = false, hasCleared = false, shipsOnMerge = false, shipsOnTag = false
    var ships = true, shipsAtOnce = false
    var loadZones: [Zone] { hasStaging ? [.testing, .cleared] : [.waiting] }

    init(hasStaging: Bool = false, hasCleared: Bool = false, shipsOnMerge: Bool = false, shipsOnTag: Bool = false, ships: Bool = true, shipsAtOnce: Bool = false) {
        self.hasStaging = hasStaging; self.hasCleared = hasCleared; self.shipsOnMerge = shipsOnMerge; self.shipsOnTag = shipsOnTag
        self.ships = ships; self.shipsAtOnce = shipsAtOnce
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hasStaging = try c.decodeIfPresent(Bool.self, forKey: .hasStaging) ?? false
        hasCleared = try c.decodeIfPresent(Bool.self, forKey: .hasCleared) ?? false
        shipsOnMerge = try c.decodeIfPresent(Bool.self, forKey: .shipsOnMerge) ?? false
        shipsOnTag = try c.decodeIfPresent(Bool.self, forKey: .shipsOnTag) ?? false
        ships = try c.decodeIfPresent(Bool.self, forKey: .ships) ?? true
        shipsAtOnce = try c.decodeIfPresent(Bool.self, forKey: .shipsAtOnce) ?? false
    }
}

struct Facts: Codable, Equatable {
    static let scheme = 3
    var scheme = Facts.scheme
    var nextSeq = 0
    var repos: [String: RepoFacts] = [:]
    var crates: [CrateID: CrateFact] = [:]
    var homes: [String: Int] = [:]
    var offices: [String: OfficeFact] = [:]
    var staging: [String: StagingFact] = [:]
    var rockets: [RocketID: RocketFact] = [:]

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        scheme = try c.decodeIfPresent(Int.self, forKey: .scheme) ?? 0
        nextSeq = try c.decodeIfPresent(Int.self, forKey: .nextSeq) ?? 0
        repos = try c.decodeIfPresent([String: RepoFacts].self, forKey: .repos) ?? [:]
        crates = try c.decodeIfPresent([CrateID: CrateFact].self, forKey: .crates) ?? [:]
        homes = try c.decodeIfPresent([String: Int].self, forKey: .homes) ?? [:]
        offices = try c.decodeIfPresent([String: OfficeFact].self, forKey: .offices) ?? [:]
        staging = try c.decodeIfPresent([String: StagingFact].self, forKey: .staging) ?? [:]
        rockets = try c.decodeIfPresent([RocketID: RocketFact].self, forKey: .rockets) ?? [:]
        nextSeq = max(nextSeq, (crates.values.map(\.seq).max() ?? -1) + 1)
    }

    var persisted: Facts {
        var f = self
        f.rockets = f.rockets.filter { !$0.value.launched }
        f.crates = f.crates.filter { if case .aboard = $0.value.place { return false }; return true }
        return f
    }

    mutating func take() -> Int { defer { nextSeq += 1 }; return nextSeq }

    func repo(_ name: String) -> RepoFacts { repos[name] ?? RepoFacts() }
    func count(_ zone: Zone) -> Int { crates.values.filter { $0.zone == zone }.count }
    func rowCrates(of repo: String) -> Int { crates.values.filter { $0.id.repo == repo && $0.onRow }.count }
    func cargo(_ repo: String) -> [CrateFact] {
        let zones = self.repo(repo).loadZones
        return crates.values.filter { $0.id.repo == repo && $0.zone.map(zones.contains) == true }.sorted { $0.id < $1.id }
    }
    func aboard(_ rocket: RocketID) -> [CrateFact] { crates.values.filter { $0.place == .aboard(rocket) }.sorted { $0.id < $1.id } }
}
