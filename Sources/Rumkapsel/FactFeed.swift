import Foundation

final class FactFeed {
    var pending: [(repo: String?, event: Event)] = []
    var numbered: [Int: CrateID] = [:]
    var swept: Set<String> = []
    var unsaved = false
    var savedAt = Date.distantPast
    static let unrouted = 500, saveEvery: TimeInterval = 5
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

    func beatFacts(now: Date) -> [(station: String, effects: [Effect])] {
        let news = renumbered() + feed.pending
        let routed = Set(repoRoots.values.map(\.repo))
        feed.pending = Array(news.filter { $0.repo.map { !routed.contains($0) } ?? false }.suffix(FactFeed.unrouted))
        var out: [(station: String, effects: [Effect])] = []
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
            out.append((station.name, Rules.apply(events + [.tick], at: now, to: &station.facts, yard: station.yard)))
            if station.facts != before { feed.unsaved = true }
            shipAboardMerges(station, now: now)
        }
        if feed.unsaved, now.timeIntervalSince(feed.savedAt) >= FactFeed.saveEvery {
            feed.unsaved = false
            feed.savedAt = now
            fleet.save()
        }
        return out
    }

    private func shipAboardMerges(_ station: Station, now: Date) {
        for c in station.facts.crates.values.filter({ if case .aboard = $0.place { return true }; return false }).sorted(by: { $0.id < $1.id }) {
            guard case .aboard(let rocket) = c.place, rocket.contains("|merge#"),
                  let r = works.find(repo: c.id.repo, crate: c.id.number), (r.stage ?? .shipped) < .shipped else { continue }
            works.report(r, .shipped, by: .git, at: now)
        }
    }
}
