import AppKit

extension StationController {
    func ledgerReport(only repo: String?) -> String {
        var lines: [String] = []
        func say(_ s: String) { lines.append(s) }
        let stamp = DateFormatter()
        stamp.dateFormat = "MM-dd HH:mm"
        func when(_ d: Date?) -> String { d.map(stamp.string(from:)) ?? "-" }
        func pad(_ s: String, _ n: Int) -> String { s.padding(toLength: max(n, s.count), withPad: " ", startingAt: 0) }

        for station in fleet.stations.values.sorted(by: { $0.name < $1.name }) {
            say("station \(station.name): \(station.ledger.crates.count) crates")
            let repos = Set(station.ledger.crates.values.map(\.repo))
                .union(world.repoRoots.values.filter { $0.station == station.name }.map(\.repo))
                .union(station.facts.crates.keys.map(\.repo))
            let spots = Layout.spots(station.facts, station.yard)
            for name in repos.sorted() where repo == nil || name == repo {
                let root = world.repoRoots.first { $0.value.repo == name && $0.value.station == station.name }?.key
                let cargo = root.flatMap { github.cargo(repoRoot: $0) }
                say("")
                say("  \(name)")
                if let c = cargo {
                    say("    source (\(c.source)): storage \(c.storageNumbers) deck \(c.deckNumbers) cleared \(c.clearedNumbers)")
                } else {
                    say("    source: nothing — the poller has no count for this repository")
                }
                if let root {
                    let pipeline = github.pipeline(repoRoot: root)
                    let launching = github.hasPendingLaunch(repoRoot: root)
                        || (github.openReleases(repoRoot: root)?.contains(where: \.isProduction) ?? false)
                    say("    rules: shipsOnMerge \(pipeline.shipsOnMerge) · launching \(launching)")
                }
                let facts = station.facts.crates.values.filter { $0.id.repo == name }.sorted { $0.id < $1.id }
                if facts.isEmpty { say("    facts: empty") } else {
                    say("    facts:  number  place    column level stage    cleared  closed  seq")
                        for c in facts {
                        let place: String
                        switch c.place {
                        case .office(let key): place = "office " + key
                        case .aboard(let rocket): place = "aboard " + rocket
                        default: place = c.zone?.rawValue ?? "-"
                        }
                        say("            " + [pad(String(c.id.number), 7), pad(place, 8), pad(c.column.map(String.init) ?? "-", 6),
                                              pad(spots[c.id].map { String($0.level) } ?? "-", 5), pad(c.stage.map(String.init(describing:)) ?? "-", 8),
                                              pad(c.cleared ? "yes" : "no", 8), pad(when(c.closedAt), 7), String(c.seq)].joined(separator: " "))
                    }
                }
                if let r = station.facts.repos[name] {
                    say("    facts' repository: staging \(r.hasStaging) · cleared \(r.hasCleared) · ships on merge \(r.shipsOnMerge) · on tags \(r.shipsOnTag) · home band \(station.facts.homes[name].map(String.init) ?? "-")")
                }
                let off = world.factMismatches().filter { $0.station == station.name && $0.crate.repo == name }.map(\.line).sorted()
                say("    facts against the ledger: \(off.isEmpty ? "agree" : off.joined(separator: "; "))")
                let crates = station.ledger.crates(of: name)
                if crates.isEmpty { say("    ledger: empty"); continue }
                say("    ledger: number  wanted   placed   heading  cleared  movedAt      wantedAt     disagrees")
                func pad(_ s: String, _ n: Int) -> String { s.padding(toLength: max(n, s.count), withPad: " ", startingAt: 0) }
                for c in crates {
                    say("            " + [pad(String(c.number), 7), pad(c.wanted?.rawValue ?? "-", 8),
                                          pad(c.placed?.rawValue ?? "-", 8), pad(c.heading?.rawValue ?? "-", 8),
                                          pad(c.cleared ? "yes" : "no", 8), pad(when(c.movedAt), 12),
                                          pad(when(c.wantedAt), 12), c.disagrees ? "yes" : "no"].joined(separator: " "))
                }
                if let c = cargo {
                    let known = Set(crates.map(\.number))
                    let missing = (c.storageNumbers + c.deckNumbers).filter { !known.contains($0) }
                    if !missing.isEmpty { say("    counted by the source, absent from the ledger: \(missing.sorted())") }
                }
                let open = station.ledger.disagreements(repo: name)
                say("    disagreeing: \(open.isEmpty ? "none" : open.map { "\($0.number) \($0.placed?.rawValue ?? "-")→\($0.wanted?.rawValue ?? "-")" }.joined(separator: ", "))")
            }
        }
        return lines.joined(separator: "\n")
    }
}
