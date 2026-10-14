import Foundation

final class FactFeed {
    static func together(_ events: [Event]) -> [Event] {
        var out: [Event] = []
        var first: [String: Int] = [:]
        for e in events {
            guard case .launched(let repo, nil, let crates?, let label) = e else { out.append(e); continue }
            guard let i = first[repo], case .launched(_, _, let had?, _) = out[i] else { first[repo] = out.count; out.append(e); continue }
            out[i] = .launched(repo: repo, crates: had + crates.filter { !had.contains($0) }, label: label)
        }
        return out
    }

    var pending: [(repo: String?, event: Event)] = []
    var numbered: [Int: CrateID] = [:]
    var swept: Set<String> = []
    var unsaved = false
    var savedAt = Date.distantPast
    var depth = 0
    var settling = false
    static let unrouted = 500, saveEvery: TimeInterval = 5
}

extension World {
    func learn(_ event: Event, repo: String? = nil) {
        feed.pending.append((repo, event))
        if feed.depth == 0 { settle() }
    }

    func batch<T>(_ body: () -> T) -> T {
        feed.depth += 1
        let out = body()
        feed.depth -= 1
        if feed.depth == 0 { settle() }
        return out
    }

    func settle(tick: Bool = false) {
        guard !feed.settling else { return }
        feed.settling = true
        defer { feed.settling = false }
        var ticking = tick
        for _ in 0..<4 {
            let out = applyFacts(now: now, tick: ticking)
            ticking = false
            for (name, effects) in out { if let st = fleet.stations[name] { onFacts(st, effects) } }
            if feed.pending.allSatisfy({ $0.repo.map { r in !repoRoots.values.contains { $0.repo == r } } ?? false }) { break }
        }
    }
    func learn(_ news: OfficeNews, station name: String) {
        guard let station = fleet.stations[name] else { return }
        let effects = Rules.apply([.office(news)], at: now, to: &station.facts, yard: station.yard)
        feed.unsaved = true
        onOffices(station, effects)
    }

    func touch(_ station: Station) { onOffices(station, []) }

    func learn(_ record: WorkBook.Record, _ t: Transition) {
        guard let n = record.number else { return }
        let crate = CrateID(repo: record.repo, number: n)
        feed.numbered[record.id] = crate
        var news = WorkNews(crate: crate, office: office(for: record)?.room.key, stage: t.to, quiet: t.from == nil)
        if t.to == .stored, let root = repoRoots.first(where: { $0.value.repo == record.repo })?.key, github.pipeline(repoRoot: root).shipsOnMerge {
            news.link = waitingURL(repo: record.repo)
        }
        learn(.work(news), repo: record.repo)
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

    private func applyFacts(now: Date, tick: Bool) -> [(station: String, effects: [Effect])] {
        let news = renumbered() + feed.pending
        let routed = Set(repoRoots.values.map(\.repo))
        feed.pending = Array(news.filter { $0.repo.map { !routed.contains($0) } ?? false }.suffix(FactFeed.unrouted))
        var out: [(station: String, effects: [Effect])] = []
        for station in fleet.stations.values.sorted(by: { $0.name < $1.name }) {
            let roots = repoRoots.filter { $0.value.station == station.name }.sorted { $0.key < $1.key }
            let repos = Set(roots.map(\.value.repo))
            var events: [Event] = []
            for (root, info) in roots {
                let r = policy(root: root, repo: info.repo, station: station.name)
                if station.facts.repos[info.repo] != r { events.append(.policy(repo: info.repo, r)) }
            }
            events += FactFeed.together(news.filter { $0.repo.map(repos.contains) ?? true }.map(\.event))
            guard tick || !events.isEmpty else { continue }
            let before = station.facts
            var effects = Rules.apply(events + (tick ? [.tick] : []), at: now, to: &station.facts, yard: station.yard)
            if tick {
                let drift = officeDrift(station)
                if !drift.isEmpty { effects += Rules.apply(drift, at: now, to: &station.facts, yard: station.yard) }
            }
            if station.facts != before || !effects.isEmpty { out.append((station.name, effects)) }
            if station.facts != before { feed.unsaved = true }
            shipAboardMerges(station, now: now)
        }
        if tick, feed.unsaved, now.timeIntervalSince(feed.savedAt) >= FactFeed.saveEvery {
            feed.unsaved = false
            feed.savedAt = now
            fleet.save()
        }
        return out
    }

    func officeDrift(_ station: Station) -> [Event] {
        let rooms = station.rooms.values.filter { !$0.key.hasPrefix("kind:") }
        let known = Set(rooms.map(\.key))
        let opened = rooms.filter { station.facts.offices[$0.key] == nil }.sorted { $0.key < $1.key }.map { OfficeNews.opened($0.key, repo: $0.repo, via: .appear) }
        let gone = station.facts.offices.keys.filter { !known.contains($0) }.sorted().map { OfficeNews.gone($0) }
        for news in opened + gone { StationLog.write("facts", "\(station.name): \(news), set from the rooms: no word came for it") }
        return (opened + gone).map { .office($0) }
    }

    private func shipAboardMerges(_ station: Station, now: Date) {
        for c in station.facts.crates.values.filter({ if case .aboard = $0.place { return true }; return false }).sorted(by: { $0.id < $1.id }) {
            guard case .aboard(let rocket) = c.place, rocket.contains("|merge#"),
                  let r = works.find(repo: c.id.repo, crate: c.id.number), (r.stage ?? .shipped) < .shipped else { continue }
            works.report(r, .shipped, by: .git, at: now)
        }
    }
}
