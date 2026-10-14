import Foundation
import simd

final class ReleaseBook {
    var announced: Set<String> = []
    var seen: Set<String> = []
    var stagingPRs: [String: (number: Int, state: String)] = [:]
    var stagingSeen: Set<String> = []
    var awaitingDeploy: [String: Date] = [:]
    var hotfixRecords: Set<Int> = []
}

extension World {
    func root(station: String, repo: String) -> String? { repoRoots.first { $0.value.station == station && $0.value.repo == repo }?.key }
    func stagingIsDeck(station: String, repo: String) -> Bool {
        root(station: station, repo: repo).map { github.pipeline(repoRoot: $0).hasStaging } ?? true
    }
    func deckInUse(station: String) -> Bool {
        let roots = repoRoots.filter { $0.value.station == station }.map(\.key)
        return roots.isEmpty || roots.contains { github.pipeline(repoRoot: $0).hasStaging }
    }

    private func padRelease(root: String) -> ReleasePR? {
        guard let open = github.openReleases(repoRoot: root) else { return nil }
        let hasProduction = open.contains(where: \.isProduction)
        return open.first { $0.isProduction || (!hasProduction && !github.pipeline(repoRoot: root).hasStaging) }
    }

    func waiting(repo: String, station: String) -> [WorkBook.Record] {
        let from: Stage = stagingIsDeck(station: station, repo: repo) ? .qa : .stored
        return works.records(repo: repo).filter { r in
            guard !releases.hotfixRecords.contains(r.id), let stage = r.stage, stage >= from, stage < .shipped else { return false }
            return !r.quiet || r.words[.git] != nil || r.words[.board] != nil
        }
    }

    private func hotfixRecord(repo: String, pr: ReleasePR) -> WorkBook.Record {
        let r = works.find(repo: repo, pull: pr.number) ?? works.note(repo: repo, branch: pr.head, pull: pr.number, pullState: pr.state)
        releases.hotfixRecords.insert(r.id)
        return r
    }

    private func label(repo: String, hotfix pr: ReleasePR) -> String { "rocket:\(pr.url)|\(repo) · hotfix #\(pr.number) \(pr.title)" }

    private func label(repo: String, release pr: ReleasePR) -> String {
        pr.tag ? "rocket:\(pr.url)|\(repo) · \(pr.title) tagged on \(pr.base)" : "rocket:\(pr.url)|\(repo) · \(pr.head) → \(pr.base) · #\(pr.number) \(pr.title)"
    }

    private func label(repo: String, waiting n: Int) -> String {
        "rocket:\(waitingURL(repo: repo))|\(repo) · \(n) \(n == 1 ? Words.current.crate : Words.current.crates) waiting for a release"
    }

    private func applyHotfixes() -> [WorldEvent] {
        var events: [WorldEvent] = []
        for launch in github.takeHotfixLaunches() {
            guard let info = repoRoots[launch.repoRoot], let station = fleet.stations[info.station], station.hasPad else { continue }
            let pr = launch.pr
            let record = hotfixRecord(repo: info.repo, pr: pr)
            learn(.launched(repo: info.repo, hotfix: pr.number, crates: [record.number ?? pr.number], label: label(repo: info.repo, hotfix: pr)), repo: info.repo)
            works.report(record, .shipped, by: .git, at: pr.mergedAt ?? now)
            events.append(.chime(pr.number))
            events += flyAtMerge(repoRoot: launch.repoRoot, station: info.station, repo: info.repo, pr: pr)
        }
        for (root, info) in repoRoots.sorted(by: { $0.key < $1.key }) {
            guard let station = fleet.stations[info.station], station.hasPad, let all = github.hotfixes(repoRoot: root) else { continue }
            let quiet = releases.seen.insert("hotfix|" + root).inserted || settling
            var open: [Int: String] = [:]
            for pr in all where pr.state == "OPEN" {
                _ = hotfixRecord(repo: info.repo, pr: pr)
                open[pr.number] = label(repo: info.repo, hotfix: pr)
                if releases.announced.insert(RocketKey.of(station: info.station, repo: info.repo, hotfix: pr.number)).inserted, !quiet {
                    events.append(.log("\(info.repo): hotfix #\(pr.number) \(Words.current.onThePad)"))
                }
            }
            learn(.hotfixes(repo: info.repo, open: open, quiet: quiet), repo: info.repo)
        }
        return events
    }

    func rocketKey(station: String, repo: String, release: String) -> String {
        guard release.hasPrefix("#"), let n = Int(release.dropFirst()), let root = root(station: station, repo: repo),
              github.hotfixes(repoRoot: root)?.contains(where: { $0.number == n }) == true else { return station + "|" + repo }
        return RocketKey.of(station: station, repo: repo, hotfix: n)
    }

    private func flyAtMerge(repoRoot: String, station: String, repo: String, pr: ReleasePR) -> [WorldEvent] {
        guard let d = github.deploys(repoRoot: repoRoot).first(where: \.production), let newest = d.newest else { return [] }
        let merged = pr.mergedAt ?? now
        guard now.timeIntervalSince(merged) < Deployments.recent else { return [] }
        if let began = newest.startedAt, began > merged.addingTimeInterval(-120) { return [] }
        releases.awaitingDeploy[repoRoot] = now
        return [.deployStarted(station: station, repo: repo, production: true, expected: d.usual,
                               release: pr.tag ? pr.title : "#\(pr.number)", elapsed: max(0, now.timeIntervalSince(merged)))]
    }

    func lostDeploys() -> [WorldEvent] {
        var out: [WorldEvent] = []
        for (root, at) in releases.awaitingDeploy where now.timeIntervalSince(at) > Deployments.findWithin {
            releases.awaitingDeploy[root] = nil
            if let info = repoRoots[root] { out.append(.deployEnded(station: info.station, repo: info.repo, production: true, outcome: .lost)) }
        }
        return out
    }

    func waitingURL(repo: String) -> String {
        guard let root = repoRoots.first(where: { $0.value.repo == repo })?.key, let owner = github.nameWithOwner(repoRoot: root) else { return "" }
        let p = github.pipeline(repoRoot: root)
        let shipped = github.releases(repoRoot: root)?.first(where: \.tag)?.head ?? p.production
        return shipped.isEmpty ? "https://github.com/\(owner)" : "https://github.com/\(owner)/compare/\(shipped)...\(p.trunk)"
    }

    func launchShipped(_ r: WorkBook.Record, _ t: Transition) {
        guard t.to == .shipped, t.from != nil, !t.wasQuiet, !releases.hotfixRecords.contains(r.id), let n = r.number,
              let root = repoRoots.first(where: { $0.value.repo == r.repo })?.key, !github.pipeline(repoRoot: root).shipsAtOnce else { return }
        learn(.launched(repo: r.repo, crates: [n], label: "rocket:\(waitingURL(repo: r.repo))|\(r.repo) · shipped"), repo: r.repo)
    }

    func applyReleases() -> [WorldEvent] {
        var events = applyHotfixes()
        for launch in github.takeLaunches() {
            guard let info = repoRoots[launch.repoRoot], let station = fleet.stations[info.station] else { continue }
            let pr = launch.pr
            events.append(.chime(pr.number))
            guard pr.isProduction else { continue }
            learn(.launched(repo: info.repo, label: label(repo: info.repo, release: pr)), repo: info.repo)
            events += flyAtMerge(repoRoot: launch.repoRoot, station: info.station, repo: info.repo, pr: pr)
            for r in waiting(repo: info.repo, station: station.name) {
                works.report(r, .shipped, by: pr.tag ? .git : .pulls, at: pr.mergedAt ?? now)
                if let n = r.number { report(crate: n, repo: info.repo, .shipped, by: pr.tag ? .git : .pulls, at: pr.mergedAt ?? now) }
            }
            releases.announced = releases.announced.filter { !$0.hasPrefix("\(info.station)|\(info.repo)|") }
        }
        for (root, info) in repoRoots.sorted(by: { $0.key < $1.key }) {
            guard let station = fleet.stations[info.station], station.hasPad, github.openReleases(repoRoot: root) != nil else { continue }
            let quiet = releases.seen.insert(root).inserted || settling
            let key = info.station + "|" + info.repo
            guard let pr = padRelease(root: root) else {
                learn(.release(repo: info.repo, production: nil, label: label(repo: info.repo, waiting: waiting(repo: info.repo, station: station.name).count), quiet: quiet), repo: info.repo)
                continue
            }
            let mark = "\(key)|\(pr.number)|\(pr.untested)"
            if releases.announced.insert(mark).inserted, !quiet {
                events.append(.log("\(info.repo): release to \(pr.base) \(Words.current.onThePad)" + (pr.untested ? " (untested)" : "")))
            }
            let flow = workflow(repo: info.repo)
            let boardClears = flow.cleared?.first == .board && flow.has(.qa)
            if !pr.untested, flow.cleared?.contains(.pulls) == true {
                for r in waiting(repo: info.repo, station: station.name) where !boardClears || r.words[.board] == nil {
                    works.report(r, .cleared, by: .pulls, at: now)
                }
            }
            learn(.release(repo: info.repo, production: pr.isProduction, label: label(repo: info.repo, release: pr), quiet: quiet), repo: info.repo)
        }
        return events + applyStaging()
    }

    private func applyStaging() -> [WorldEvent] {
        var events: [WorldEvent] = []
        for (root, info) in repoRoots.sorted(by: { $0.key < $1.key }) {
            guard fleet.stations[info.station] != nil, let all = github.releases(repoRoot: root) else { continue }
            let key = info.station + "|" + info.repo
            let staging = all.filter(\.isStaging)
            let open = staging.first { $0.state == "OPEN" }
            guard releases.stagingSeen.contains(key) else {
                releases.stagingSeen.insert(key)
                if let open { releases.stagingPRs[key] = (open.number, "OPEN"); learn(.staging(repo: info.repo, .opened(open.number)), repo: info.repo) }
                continue
            }
            if let open, releases.stagingPRs[key]?.number != open.number {
                releases.stagingPRs[key] = (open.number, "OPEN")
                learn(.staging(repo: info.repo, .opened(open.number)), repo: info.repo)
                events.append(.log("\(info.repo): staging release #\(open.number) open"))
                continue
            }
            guard let known = releases.stagingPRs[key], known.state == "OPEN",
                  let pr = staging.first(where: { $0.number == known.number }), pr.state != "OPEN" else { continue }
            releases.stagingPRs[key] = (pr.number, pr.state)
            let merged = pr.state == "MERGED"
            learn(.staging(repo: info.repo, merged ? .merged(pr.number) : .closed(pr.number)), repo: info.repo)
            events.append(.log("\(info.repo): staging release #\(pr.number) \(merged ? "merged" : "closed, not merged")"))
        }
        return events
    }

    func reconcileYards() -> [WorldEvent] {
        batch {
            for station in fleet.stations.values.sorted(by: { $0.name < $1.name }) where station.hasPad {
                for (root, info) in repoRoots.sorted(by: { $0.key < $1.key }) where info.station == station.name {
                    if let c = github.cargo(repoRoot: root) { reconcile(repo: info.repo, root: root, cargo: c) }
                }
            }
            return stationEvents()
        }
    }

    func reconcile(repo: String, root: String, cargo c: GitHubResolver.Cargo) {
        if github.pipeline(repoRoot: root).shipsOnMerge { return }
        for n in c.storageNumbers { report(crate: n, repo: repo, .stored, by: c.source, at: c.updated[n] ?? now) }
        for n in c.deckNumbers where !c.clearedNumbers.contains(n) { report(crate: n, repo: repo, .qa, by: c.source, at: c.updated[n] ?? now) }
        for n in c.clearedNumbers { report(crate: n, repo: repo, .cleared, by: c.source, at: c.updated[n] ?? now) }
        let listed = Set(c.storageNumbers + c.deckNumbers + c.clearedNumbers)
        let shippedColumn = ConfigStore.shared.current.statuses.shipped
        for r in works.records(repo: repo) {
            guard let n = r.number, let stage = r.stage, stage >= .stored, stage < .shipped else { continue }
            if c.source == .git, c.exact, !listed.contains(n), !r.pulls.keys.contains(where: listed.contains),
               let at = r.stagedAt, at < c.at {
                works.report(r, .shipped, by: .git, at: c.at)
            } else if !shippedColumn.isEmpty, github.projectItems()?.contains(where: { $0.repo == repo && $0.number == n && $0.status == shippedColumn }) == true {
                works.report(r, .shipped, by: .board, at: now)
            }
        }
        guard c.exact || c.source == .board, feed.swept.insert(repo).inserted else { return }
        let held = works.records(repo: repo).compactMap { r -> Int? in
            let inYard = r.stage.map { $0 >= .stored && $0 < .shipped } ?? false
            return inYard || r.pulls.keys.contains(where: listed.contains) ? r.number : nil
        }
        learn(.sweep(repo: repo, keep: listed.union(held).sorted()), repo: repo)
    }

    func padSlots(station: Station) -> [SIMD2<Double>] { station.hall.padSlots }
}
