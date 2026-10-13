import Foundation
import simd

final class ReleaseBook {
    var announced: Set<String> = []
    var seen: Set<String> = []
    var stagingPRs: [String: (number: Int, state: String)] = [:]
    var stagingSeen: Set<String> = []
    var mergeLaunches: Set<String> = []
    var awaitingDeploy: [String: Date] = [:]
    var padSlotOf: [String: Int] = [:]
    var launchedThisPass: Set<String> = []
    var hotfixLoads: [String: (crate: Int?, at: Date)] = [:]
    var hotfixRecords: Set<Int> = []
}

extension World {
    func root(station: String, repo: String) -> String? { repoRoots.first { $0.value.station == station && $0.value.repo == repo }?.key }
    func stagingIsDeck(station: String, repo: String) -> Bool {
        root(station: station, repo: repo).map { github.pipeline(repoRoot: $0).hasStaging } ?? !ConfigStore.shared.current.stagingBranch.isEmpty
    }
    func shipsOnMerge(station: String, repo: String) -> Bool {
        root(station: station, repo: repo).map { github.pipeline(repoRoot: $0).shipsOnMerge } ?? false
    }
    func forgetShipped(station: String, repo: String) {
        guard let st = fleet.stations[station] else { return }
        for c in st.ledger.crates(of: repo) where c.placed == .pad {
            report(crate: c.number, repo: repo, .shipped, by: releases.mergeLaunches.contains(station + "|" + repo) ? .git : .pulls, at: now)
            st.ledger.forget(repo: repo, number: c.number)
        }
    }
    func deckInUse(station: String) -> Bool {
        let roots = repoRoots.filter { $0.value.station == station }.map(\.key)
        return roots.isEmpty ? !ConfigStore.shared.current.stagingBranch.isEmpty : roots.contains { github.pipeline(repoRoot: $0).hasStaging }
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
    func clearedToLoad(repo: String, station: String) -> Bool {
        let w = waiting(repo: repo, station: station)
        return !w.isEmpty && (!workflow(repo: repo).has(.cleared) || w.allSatisfy { $0.stage.map { $0 >= .cleared } ?? false })
    }

    func padRockets() -> Set<String> {
        var pads = Set(repoRoots.compactMap { root, info in padRelease(root: root) != nil ? info.station + "|" + info.repo : nil }).union(releases.mergeLaunches)
        for (root, info) in repoRoots where fleet.stations[info.station]?.hasPad == true && !workflow(repo: info.repo).shipped.isEmpty
            && !github.pipeline(repoRoot: root).shipsAtOnce && !waiting(repo: info.repo, station: info.station).isEmpty { pads.insert(info.station + "|" + info.repo) }
        for (root, info) in repoRoots where fleet.stations[info.station]?.hasPad == true {
            for pr in github.hotfixes(repoRoot: root) where pr.state == "OPEN" {
                pads.insert(RocketKey.of(station: info.station, repo: info.repo, hotfix: pr.number))
            }
        }
        return pads.union(releases.hotfixLoads.keys)
    }

    private func hotfixRecord(repo: String, pr: ReleasePR) -> WorkBook.Record {
        let r = works.find(repo: repo, pull: pr.number) ?? works.note(repo: repo, branch: pr.head, pull: pr.number, pullState: pr.state)
        releases.hotfixRecords.insert(r.id)
        return r
    }

    func hotfixWish(_ stage: Command.RocketStage, station: Station, repo: String, pr: ReleasePR) -> WorldEvent {
        .rocketCommand(station: station.name, repo: repo, label: "rocket:\(pr.url)|\(repo) · hotfix #\(pr.number) \(pr.title)",
                       untested: false, tall: true, cargo: 1, command: .rocket(stage, station: station.name, repo: repo), hotfix: pr.number)
    }

    private func applyHotfixes() -> [WorldEvent] {
        var events: [WorldEvent] = []
        for launch in github.takeHotfixLaunches() {
            guard let info = repoRoots[launch.repoRoot], let station = fleet.stations[info.station], station.hasPad else { continue }
            let pr = launch.pr
            let key = RocketKey.of(station: info.station, repo: info.repo, hotfix: pr.number)
            releases.hotfixLoads[key] = (hotfixRecord(repo: info.repo, pr: pr).number, now)
            assignPads()
            events.append(.chime(pr.number))
            events += flyAtMerge(repoRoot: launch.repoRoot, station: info.station, repo: info.repo, pr: pr)
            events.append(.log("\(info.repo) \(Words.current.launchedTo) production as a hotfix: \(pr.title)"))
            events.append(hotfixWish(.launch, station: station, repo: info.repo, pr: pr))
        }
        for (root, info) in repoRoots {
            guard let station = fleet.stations[info.station], station.hasPad else { continue }
            for pr in github.hotfixes(repoRoot: root) where pr.state == "OPEN" {
                let key = RocketKey.of(station: info.station, repo: info.repo, hotfix: pr.number)
                _ = hotfixRecord(repo: info.repo, pr: pr)
                guard releases.padSlotOf[key] != nil, releases.hotfixLoads[key] == nil else { continue }
                if releases.announced.insert(key).inserted {
                    events.append(.log("\(info.repo): hotfix #\(pr.number) \(Words.current.onThePad)"))
                }
                events.append(hotfixWish(.standBy, station: station, repo: info.repo, pr: pr))
            }
        }
        return events
    }

    func rocketKey(station: String, repo: String, release: String) -> String {
        guard release.hasPrefix("#"), let n = Int(release.dropFirst()), let root = root(station: station, repo: repo),
              github.hotfixes(repoRoot: root).contains(where: { $0.number == n }) else { return station + "|" + repo }
        return RocketKey.of(station: station, repo: repo, hotfix: n)
    }

    func hotfixCrateComing(_ key: String) -> Bool {
        guard let load = releases.hotfixLoads[key], let n = load.crate, now.timeIntervalSince(load.at) < 120 else { return false }
        let p = RocketKey.parts(key)
        guard let station = fleet.stations[p.station] else { return false }
        if let row = station.ledger[p.repo, n] { return !row.stands(in: .pad) }
        return works.find(repo: p.repo, crate: n).flatMap { office(for: $0) } != nil
    }

    func hotfixAboard(_ key: String) {
        let p = RocketKey.parts(key)
        guard let n = releases.hotfixLoads[key]?.crate, let station = fleet.stations[p.station] else { return }
        if let r = works.find(repo: p.repo, crate: n) { works.report(r, .shipped, by: .pulls, at: now) }
        station.ledger.forget(repo: p.repo, number: n)
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

    func wish(_ stage: Command.RocketStage, station: Station, repo: String, waiting n: Int, cleared: Bool) -> WorldEvent {
        let status = " · " + (cleared ? Words.current.cleared : Words.current.holding)
        let label = "rocket:\(waitingURL(repo: repo))|\(repo) · \(n) \(n == 1 ? Words.current.crate : Words.current.crates) waiting for a release\(status)"
        return .rocketCommand(station: station.name, repo: repo, label: label, untested: !cleared, tall: stage.rank >= 3, cargo: n,
                              command: .rocket(stage, station: station.name, repo: repo))
    }

    func waitingURL(repo: String) -> String {
        guard let root = repoRoots.first(where: { $0.value.repo == repo })?.key, let owner = github.nameWithOwner(repoRoot: root) else { return "" }
        let p = github.pipeline(repoRoot: root)
        let shipped = github.releases(repoRoot: root)?.first(where: \.tag)?.head ?? p.production
        return shipped.isEmpty ? "https://github.com/\(owner)" : "https://github.com/\(owner)/compare/\(shipped)...\(p.trunk)"
    }

    func wish(_ stage: Command.RocketStage, station: Station, repo: String, pr: ReleasePR, cleared: Bool? = nil) -> WorldEvent {
        let cleared = cleared ?? !pr.untested
        let status = " · " + (cleared ? Words.current.cleared : Words.current.holding)
        let label = pr.tag ? "rocket:\(pr.url)|\(repo) · \(pr.title) tagged on \(pr.base)\(status)"
            : "rocket:\(pr.url)|\(repo) · \(pr.head) → \(pr.base) · #\(pr.number) \(pr.title)\(status)"
        return .rocketCommand(station: station.name, repo: repo, label: label, untested: !cleared,
                              tall: pr.isProduction, cargo: cargoWaiting(station: station, repo: repo),
                              command: .rocket(stage, station: station.name, repo: repo))
    }

    func cargoWaiting(station: Station, repo: String) -> Int {
        (stagingIsDeck(station: station.name, repo: repo) ? station.staged : station.stored)[repo] ?? 0
    }

    func applyReleases() -> [WorldEvent] {
        var events: [WorldEvent] = []
        var launched: Set<String> = []
        releases.launchedThisPass = []
        assignPads()
        events += applyHotfixes()
        for launch in github.takeLaunches() {
            guard let info = repoRoots[launch.repoRoot], let station = fleet.stations[info.station] else { continue }
            let pr = launch.pr
            events.append(.releaseMerged(station: info.station, repo: info.repo, number: pr.number, base: pr.base,
                                         title: pr.title, isProduction: pr.isProduction))
            events.append(.chime(pr.number))
            guard pr.isProduction else { continue }
            launched.insert(info.station + "|" + info.repo)
            events += flyAtMerge(repoRoot: launch.repoRoot, station: info.station, repo: info.repo, pr: pr)
            for r in waiting(repo: info.repo, station: station.name) {
                works.report(r, .shipped, by: pr.tag ? .git : .pulls, at: pr.mergedAt ?? now)
                if let n = r.number { report(crate: n, repo: info.repo, .shipped, by: pr.tag ? .git : .pulls, at: pr.mergedAt ?? now) }
            }
            for c in station.ledger.crates(of: info.repo) where c.placed == .pad { report(crate: c.number, repo: info.repo, .shipped, by: pr.tag ? .git : .pulls, at: pr.mergedAt ?? now) }
            releases.announced = releases.announced.filter { !$0.hasPrefix("\(info.station)|\(info.repo)|") }
            events.append(.log(pr.tag ? "\(info.repo) \(Words.current.launchedTo) \(pr.title)"
                                       : "\(info.repo) \(Words.current.launchedTo) \(pr.base): \(pr.title)"))
            events.append(wish(.launch, station: station, repo: info.repo, pr: pr))
            releases.launchedThisPass.insert(info.station + "|" + info.repo)
        }
        for (root, info) in repoRoots {
            guard let station = fleet.stations[info.station], github.openReleases(repoRoot: root) != nil else { continue }
            let quiet = !releases.seen.contains(root)
            releases.seen.insert(root)
            let key = info.station + "|" + info.repo
            guard !launched.contains(key) else { continue }
            guard releases.padSlotOf[key] != nil || padRelease(root: root) == nil else { continue }
            guard let pr = padRelease(root: root) else {
                let w = waiting(repo: info.repo, station: station.name)
                guard station.hasPad, !w.isEmpty, !workflow(repo: info.repo).shipped.isEmpty, !releases.mergeLaunches.contains(key),
                      !github.pipeline(repoRoot: root).shipsAtOnce, releases.padSlotOf[key] != nil else { continue }
                let cleared = clearedToLoad(repo: info.repo, station: station.name)
                if !cleared { events += standDown(station: station, repo: info.repo) }
                events.append(wish(cleared ? .load(cargoWaiting(station: station, repo: info.repo)) : .standBy,
                                   station: station, repo: info.repo, waiting: w.count, cleared: cleared))
                continue
            }
            let mark = "\(key)|\(pr.number)|\(pr.untested)"
            if quiet { releases.announced.insert(mark) }
            if !releases.announced.contains(mark) {
                releases.announced.insert(mark)
                events.append(.releaseOpened(station: info.station, repo: info.repo, number: pr.number, base: pr.base,
                                             untested: pr.untested, isProduction: pr.isProduction))
                events.append(.log("\(info.repo): release to \(pr.base) \(Words.current.onThePad)" + (pr.untested ? " (untested)" : "")))
            }
            let flow = workflow(repo: info.repo)
            let boardClears = flow.cleared?.first == .board && flow.has(.qa)
            let labelClears = !pr.untested && flow.cleared?.contains(.pulls) == true
            if labelClears {
                for r in waiting(repo: info.repo, station: station.name) where !boardClears || r.words[.board] == nil {
                    works.report(r, .cleared, by: .pulls, at: now)
                }
            }
            let cleared = pr.isProduction && ((labelClears && !boardClears) || clearedToLoad(repo: info.repo, station: station.name))
            if !cleared { events += standDown(station: station, repo: info.repo) }
            events.append(wish(cleared ? .load(cargoWaiting(station: station, repo: info.repo)) : .standBy,
                               station: station, repo: info.repo, pr: pr, cleared: cleared))
        }
        return events + applyStaging()
    }

    private func standDown(station: Station, repo: String) -> [WorldEvent] {
        let yard: Yard = stagingIsDeck(station: station.name, repo: repo) ? .deck : .storage
        let back = station.ledger.unload(repo: repo, to: yard)
        guard !back.isEmpty else { return [] }
        return [.log("\(repo): not cleared to ship, \(back.count) back off the rocket"), .layoutChanged]
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
                if let open { releases.stagingPRs[key] = (open.number, "OPEN") }
                continue
            }
            if let open, releases.stagingPRs[key]?.number != open.number {
                releases.stagingPRs[key] = (open.number, "OPEN")
                events.append(.stagingOpened(station: info.station, repo: info.repo, number: open.number))
                continue
            }
            guard let known = releases.stagingPRs[key], known.state == "OPEN",
                  let pr = staging.first(where: { $0.number == known.number }), pr.state != "OPEN" else { continue }
            releases.stagingPRs[key] = (pr.number, pr.state)
            let merged = pr.state == "MERGED"
            events.append(merged ? .stagingMerged(station: info.station, repo: info.repo, number: pr.number)
                                 : .stagingClosed(station: info.station, repo: info.repo, number: pr.number))
        }
        return events
    }

    func releaseUnderway(station: Station, repo: String, root: String) -> Bool {
        rocketBusy(station.name + "|" + repo) || github.hasPendingLaunch(repoRoot: root)
            || (github.openReleases(repoRoot: root)?.contains(where: \.isProduction) ?? false)
    }

    func reconcile(station: Station, repo: String, root: String, cargo c: GitHubResolver.Cargo) {
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
        station.ledger.adopt(yardWord(repo: repo, station: station), repo: repo)
        let open = station.ledger.disagreements(repo: repo)
        guard !open.isEmpty else { return }
        let underway = releaseUnderway(station: station, repo: repo, root: root)
        let due = carriesDueToDeck(repo: repo)
        for crate in open {
            if underway, crate.placed == .deck { continue }
            if crate.placed == .storage, due.contains(crate.number) { continue }
            station.ledger.snap(repo: repo, number: crate.number)
        }
    }

    func yardWord(repo: String, station: Station) -> Ledger.Word {
        var word = Ledger.Word(storage: [], deck: [])
        let deck = stagingIsDeck(station: station.name, repo: repo)
        for r in works.records(repo: repo) {
            guard let n = r.number, let stage = r.stage else { continue }
            switch stage {
            case .stored: word.storage.append(n)
            case .qa, .cleared: if deck { word.deck.append(n) } else { word.storage.append(n) }
            default: continue
            }
            if stage >= .cleared { word.cleared.append(n) }
            if let at = r.stagedAt { word.updated[n] = at }
        }
        return word
    }

    func slotNow(for crate: CrateRef, toward yard: Yard) -> Spot? {
        guard let station = fleet.stations[crate.station] else { return nil }
        return yard == .pad ? padSpot(station: station, repo: crate.repo) : station.spot(for: crate, toward: yard)
    }

    func padSlots(station: Station) -> [SIMD2<Double>] { station.hall.padSlots }

    func assignPads() {
        let wanted = padRockets().union(releases.padSlotOf.keys.filter(rocketBusy))
        for key in releases.padSlotOf.keys where !wanted.contains(key) { releases.padSlotOf[key] = nil }
        for station in fleet.stations.values {
            let prefix = station.name + "|"
            let count = padSlots(station: station).count
            func urgent(_ key: String) -> Bool {
                if RocketKey.parts(key).hotfix != nil || releases.mergeLaunches.contains(key) || rocketBusy(key) { return true }
                let repo = String(key.dropFirst(prefix.count))
                if stagingUnderway(key) { return true }
                return repoRoots.contains { $0.value.repo == repo && $0.value.station == station.name && padRelease(root: $0.key) != nil }
            }
            let keys = wanted.filter { $0.hasPrefix(prefix) }.sorted { a, b in urgent(a) != urgent(b) ? urgent(a) : a < b }
            for key in keys where releases.padSlotOf[key] == nil {
                let taken = Set(releases.padSlotOf.filter { $0.key.hasPrefix(prefix) }.values)
                if let free = (0..<count).first(where: { !taken.contains($0) }) { releases.padSlotOf[key] = free; continue }
                guard urgent(key), let victim = releases.padSlotOf.keys.filter({ $0.hasPrefix(prefix) && !urgent($0) }).sorted().last else { continue }
                releases.padSlotOf[key] = releases.padSlotOf.removeValue(forKey: victim)
            }
        }
    }
    func padOrder(station: Station) -> [String] {
        releases.padSlotOf.filter { $0.key.hasPrefix(station.name + "|") }.sorted { $0.value < $1.value }.map(\.key)
    }
    func padKeys() -> Set<String> { Set(releases.padSlotOf.keys) }

    func padSpot(station: Station, repo: String, key: String? = nil) -> Spot {
        let slots = padSlots(station: station)
        let slot = releases.padSlotOf[key ?? station.name + "|" + repo] ?? 0
        let pc = slots[slot % slots.count]
        let foot = SIMD2(pc.x, pc.y + 1.05)
        let stand = Cell(x: Int(foot.x.rounded()), y: Int(foot.y.rounded()))
        func off(_ c: Cell) -> Double { simd_distance(SIMD2(Double(c.x), Double(c.y)), foot) }
        let cell = station.hall.padCells.contains(stand) ? stand : (station.hall.padCells.min { off($0) < off($1) } ?? Cell(x: 0, y: 0))
        return Spot(area: .pad, station: station.name, owner: repo, label: repo, cell: cell,
                    pos: SIMD3(station.offset.x + foot.x, 0, station.offset.y + foot.y))
    }
}
