import Foundation

struct LegacyLedger: Decodable {
    struct Crate: Decodable {
        let repo: String
        let number: Int
        var wanted: String?
        var placed: String?
        var cleared: Bool?
        var alien: Bool?
    }
    var crates: [String: Crate]
}

extension LegacyLedger {
    init(_ l: Ledger) {
        crates = Dictionary(l.allCrates.map { c in
            (c.key, Crate(repo: c.repo, number: c.number, wanted: c.wanted?.rawValue, placed: c.placed?.rawValue, cleared: c.cleared, alien: c.alien))
        }) { a, _ in a }
    }
}

extension Facts {
    static func migrate(_ old: LegacyLedger, yard: YardGeometry) -> Facts {
        var f = Facts()
        let size = Dictionary(grouping: old.crates.values, by: \.repo).mapValues(\.count)
        for c in old.crates.values.sorted(by: { (-size[$0.repo]!, $0.repo, $0.number) < (-size[$1.repo]!, $1.repo, $1.number) }) {
            let place: CrateFact.Place?
            switch c.wanted ?? c.placed {
            case "storage": place = .waiting
            case "deck": place = c.cleared == true ? .cleared : .testing
            case "decon": place = .decon
            default: place = nil
            }
            guard let place else { continue }
            let id = CrateID(repo: c.repo, number: c.number)
            let alien = c.alien ?? false
            f.crates[id] = CrateFact(id: id, place: place, stage: stage(guessedFrom: place), alien: alien, seq: f.take())
            if place == .testing || place == .cleared { f.repos[c.repo, default: RepoFacts()].hasStaging = true }
        }
        Layout.relayout(&f, yard: yard)
        return f
    }

    private static func stage(guessedFrom place: CrateFact.Place) -> Stage? {
        switch place {
        case .waiting: return .stored
        case .testing: return .qa
        case .cleared: return .cleared
        case .office: return .ready
        case .decon, .aboard: return nil
        }
    }
}
