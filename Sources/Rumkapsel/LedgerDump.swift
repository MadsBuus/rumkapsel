// What the station thinks is where: `rumkapsel --dump-ledger [seconds] [repo]`.
//
// The floor draws its crates from the ledger, and the ledger is fed by the source — the board, or git
// history — through `World.reconcile`. When the two disagree about what stands in a yard, the question
// is always which of the three links dropped it: the source's word, the ledger's record of it, or the
// rule that decides whether a record may be snapped into place.
//
// This prints all three, per repository: what the source counts, what the ledger holds for every crate,
// and the state of each rule that can hold a snap back. It runs the real app against the real board and
// the real checkouts, waits for the poller to answer, prints and exits.

import AppKit

extension StationController {
    /// One line per crate, and the reasons a crate may be standing somewhere the source did not ask for.
    func ledgerReport(only repo: String?) -> String {
        var lines: [String] = []
        func say(_ s: String) { lines.append(s) }
        let stamp = DateFormatter()
        stamp.dateFormat = "MM-dd HH:mm"
        func when(_ d: Date?) -> String { d.map(stamp.string(from:)) ?? "-" }

        for station in fleet.stations.values.sorted(by: { $0.name < $1.name }) {
            say("station \(station.name): \(station.ledger.crates.count) crates")
            let repos = Set(station.ledger.crates.values.map(\.repo))
                .union(world.repoRoots.values.filter { $0.station == station.name }.map(\.repo))
            for name in repos.sorted() where repo == nil || name == repo {
                let root = world.repoRoots.first { $0.value.repo == name && $0.value.station == station.name }?.key
                // The source's word, and whether it is the board's or git's.
                let cargo = root.flatMap { github.cargo(repoRoot: $0) }
                say("")
                say("  \(name)")
                if let c = cargo {
                    say("    source (\(c.source)): storage \(c.storageNumbers) deck \(c.deckNumbers) cleared \(c.clearedNumbers)")
                } else {
                    say("    source: nothing — the poller has no count for this repository")
                }
                // Every rule in `reconcile` that can stop a crate being snapped where the source wants it.
                if let root {
                    let pipeline = github.pipeline(repoRoot: root)
                    let launching = github.hasPendingLaunch(repoRoot: root)
                        || (github.openReleases(repoRoot: root)?.contains(where: \.isProduction) ?? false)
                    let held = world.truth.pallets[station.name]?.repo == name
                        || world.truth.palletQueue[station.name]?.contains(where: { $0.repo == name }) == true
                    say("    rules: shipsOnMerge \(pipeline.shipsOnMerge) · launching \(launching) · pallet holds it \(held)")
                }
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
                // A crate the source counts that the ledger has never heard of is the loudest case.
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
