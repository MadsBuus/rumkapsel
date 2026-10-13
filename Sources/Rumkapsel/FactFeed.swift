import Foundation

final class FactFeed {
    struct Mismatch: Hashable {
        let station: String
        let crate: CrateID
        let facts: Zone?
        let ledger: Zone?
        let why: String?
        var line: String { "\(station) \(crate): facts \(facts?.rawValue ?? "none"), ledger \(ledger?.rawValue ?? "none")\(why.map { " · \($0)" } ?? "")" }
    }

    var pending: [(repo: String?, event: Event)] = []
    var numbered: [Int: CrateID] = [:]
    private var said: Set<Mismatch> = []
    private(set) var unexplained: [String] = []
    private(set) var explained = 0

    func note(_ now: Set<Mismatch>) {
        for m in now.subtracting(said).sorted(by: { $0.line < $1.line }) {
            StationLog.write("facts", m.line)
            if m.why == nil { unexplained.append(m.line) } else { explained += 1 }
        }
        said = now
    }
}

extension Ledger.Crate {
    var zone: Zone? {
        switch wanted {
        case .storage?: return .waiting
        case .deck?: return cleared ? .cleared : .testing
        case .decon?: return .decon
        case .pad?, nil: return nil
        }
    }
}

extension World {
    func learn(_ event: Event, repo: String? = nil) { feed.pending.append((repo, event)) }

    func learn(_ record: WorkBook.Record, _ t: Transition) {
        guard let n = record.number else { return }
        let crate = CrateID(repo: record.repo, number: n)
        feed.numbered[record.id] = crate
        learn(.work(WorkNews(crate: crate, office: office(for: record)?.room.key, stage: t.to, quiet: t.from == nil)), repo: record.repo)
    }

    func learnClosed(office key: String, repo: String?) {
        guard let repo, let r = works.find(officeKey: key, repo: repo), let n = r.number, let stage = r.stage else { return }
        learn(.work(WorkNews(crate: CrateID(repo: repo, number: n), office: key, stage: stage, closed: true)), repo: repo)
    }

    func policy(root: String, repo: String, station: String) -> RepoFacts {
        let p = github.pipeline(repoRoot: root), w = workflow(repo: repo)
        return RepoFacts(hasStaging: stagingIsDeck(station: station, repo: repo), hasCleared: w.has(.cleared), shipsOnMerge: p.shipsOnMerge,
                         shipsOnTag: p.shipsOnTag, ships: !w.shipped.isEmpty, shipsAtOnce: p.shipsAtOnce)
    }

    private func renumbered() -> [(repo: String?, event: Event)] {
        var out: [(repo: String?, event: Event)] = []
        for (id, crate) in feed.numbered.sorted(by: { $0.key < $1.key }) {
            guard let r = works.record(id: id) ?? works.find(repo: crate.repo, crate: crate.number), let n = r.number else { feed.numbered[id] = nil; continue }
            let to = CrateID(repo: crate.repo, number: n)
            if r.id != id { feed.numbered[id] = nil }
            feed.numbered[r.id] = to
            if to != crate { out.append((crate.repo, .renumbered(from: crate, to: to))) }
        }
        return out
    }

    func beatFacts(now: Date) {
        let news = renumbered() + feed.pending
        feed.pending = []
        for station in fleet.stations.values.sorted(by: { $0.name < $1.name }) where station.hasPad {
            let roots = repoRoots.filter { $0.value.station == station.name }.sorted { $0.key < $1.key }
            let repos = Set(roots.map(\.value.repo))
            var events: [Event] = []
            for (root, info) in roots {
                let r = policy(root: root, repo: info.repo, station: station.name)
                if station.facts.repos[info.repo] != r { events.append(.policy(repo: info.repo, r)) }
            }
            events += news.filter { $0.repo.map(repos.contains) ?? true }.map(\.event)
            let before = station.facts
            _ = Rules.apply(events + [.tick], at: now, to: &station.facts, yard: station.yard)
            if station.facts != before { fleet.save() }
        }
        feed.note(factMismatches())
    }

    func factMismatches() -> Set<FactFeed.Mismatch> {
        var out: Set<FactFeed.Mismatch> = []
        for station in fleet.stations.values where station.hasPad {
            let rows = Dictionary(station.ledger.allCrates.map { (CrateID(repo: $0.repo, number: $0.number), $0) }) { a, _ in a }
            for id in Set(rows.keys).union(station.facts.crates.keys) {
                let fact = station.facts.crates[id], row = rows[id]
                guard fact?.zone != row?.zone else { continue }
                out.insert(.init(station: station.name, crate: id, facts: fact?.zone, ledger: row?.zone, why: quirk(fact, row, in: station)))
            }
        }
        return out
    }

    private func quirk(_ fact: CrateFact?, _ row: Ledger.Crate?, in station: Station) -> String? {
        let repo = fact?.id.repo ?? row?.repo ?? ""
        if case .aboard(let rocket)? = fact?.place, rocket.contains("|hotfix#") {
            return "a hotfix is aboard at its merge; the ledger keeps it until the vortex says shipped"
        }
        if let row, row.alien, fact?.zone == .waiting, row.wanted == .decon || (row.wanted == nil && row.placed == .storage) {
            return "a merged bot crate: the ledger says decon until the carry lands, then nothing"
        }
        if station.facts.repo(repo).shipsOnMerge { return "the ledger stops listening to a repository that ships on merge" }
        if root(station: station.name, repo: repo).map({ github.cargo(repoRoot: $0) == nil }) ?? true {
            return "the ledger has had no count from the source yet"
        }
        return nil
    }
}
