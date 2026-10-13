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

    var cleared: Bool { alien || (stage.map { $0 >= .cleared } ?? false) }
    var zone: Zone? { place.zone }
    var onRow: Bool { zone?.isRow ?? false }
}

struct StagingFact: Codable, Equatable {
    var number: Int
    var merged = false
    var deploy: Deploy = .unheard
    enum Deploy: Codable, Equatable { case unheard, running(since: Date, usual: TimeInterval), live, failed }
}

struct RepoFacts: Codable, Equatable {
    var hasStaging = false, hasCleared = false, shipsOnMerge = false, shipsOnTag = false
    var ships = true, shipsAtOnce = false
    var loadZones: [Zone] { hasStaging ? [.testing, .cleared] : [.waiting] }
}

struct Facts: Codable, Equatable {
    static let scheme = 3
    var scheme = Facts.scheme
    var nextSeq = 0
    var repos: [String: RepoFacts] = [:]
    var crates: [CrateID: CrateFact] = [:]
    var homes: [String: Int] = [:]
    var staging: [String: StagingFact] = [:]
    var launches: [RocketID: Date] = [:]

    mutating func take() -> Int { defer { nextSeq += 1 }; return nextSeq }

    func repo(_ name: String) -> RepoFacts { repos[name] ?? RepoFacts() }
    func count(_ zone: Zone) -> Int { crates.values.filter { $0.zone == zone }.count }
    func rowCrates(of repo: String) -> Int { crates.values.filter { $0.id.repo == repo && $0.onRow }.count }
}
