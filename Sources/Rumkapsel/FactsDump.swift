import AppKit

extension StationController {
    func factsReport(only repo: String?) -> String {
        var lines: [String] = []
        func say(_ s: String) { lines.append(s) }
        let stamp = DateFormatter()
        stamp.dateFormat = "MM-dd HH:mm"
        func when(_ d: Date?) -> String { d.map(stamp.string(from:)) ?? "-" }
        func pad(_ s: String, _ n: Int) -> String { s.padding(toLength: max(n, s.count), withPad: " ", startingAt: 0) }

        for station in fleet.stations.values.sorted(by: { $0.name < $1.name }) {
            say("station \(station.name): \(station.facts.crates.count) crates")
            let repos = world.repoRoots.values.filter { $0.station == station.name }.map(\.repo)
            let view = simulation.shown[station.name] ?? Shown()
            let spots = Layout.spots(station.facts, station.yard)
            for name in Set(repos).union(station.facts.crates.keys.map(\.repo)).sorted() where repo == nil || name == repo {
                let root = world.repoRoots.first { $0.value.repo == name && $0.value.station == station.name }?.key
                let cargo = root.flatMap { github.cargo(repoRoot: $0) }
                say("")
                say("  \(name)")
                if let c = cargo {
                    say("    source (\(c.source)\(c.exact ? ", exact" : "")): storage \(c.storageNumbers) deck \(c.deckNumbers) cleared \(c.clearedNumbers)")
                } else {
                    say("    source: nothing — the poller has no count for this repository")
                }
                if let r = station.facts.repos[name] {
                    say("    repository: staging \(r.hasStaging) · cleared \(r.hasCleared) · ships on merge \(r.shipsOnMerge) · on tags \(r.shipsOnTag) · home band \(station.facts.homes[name].map(String.init) ?? "-")")
                }
                let facts = station.facts.crates.values.filter { $0.id.repo == name }.sorted { $0.id < $1.id }
                if facts.isEmpty { say("    facts: empty"); continue }
                say("    number  place     column level stage    cleared  closed       seq   shown")
                for c in facts {
                    let place: String
                    switch c.place {
                    case .office(let key): place = "office " + key
                    case .aboard(let rocket): place = "aboard " + rocket
                    default: place = c.zone?.rawValue ?? "-"
                    }
                    let row = [pad(String(c.id.number), 7), pad(place, 9), pad(c.column.map(String.init) ?? "-", 6),
                               pad(spots[c.id].map { String($0.level) } ?? "-", 5), pad(c.stage.map(String.init(describing:)) ?? "-", 8),
                               pad(c.cleared ? "yes" : "no", 8), pad(when(c.closedAt), 12), pad(String(c.seq), 5), simulation.describe(view.crates[c.id])]
                    say("    " + row.joined(separator: " "))
                }
                for (id, at) in view.crates.sorted(by: { $0.key < $1.key }) where id.repo == name && station.facts.crates[id] == nil {
                    say("    \(id.number): no fact, shown \(simulation.describe(at))")
                }
                for job in simulation.cargo.values.sorted(by: { $0.command.id < $1.command.id }) where job.crate.repo == name && job.command.crate?.station == station.name {
                    let blocked = job.blockedBy.isEmpty ? "" : " · waits on \(job.blockedBy.sorted().map(\.description).joined(separator: ", "))"
                    say("    move: \(job.command.words) · \(job.rank) · \(job.carrier ?? "nobody yet")\(blocked)")
                }
            }
        }
        return lines.joined(separator: "\n")
    }
}
