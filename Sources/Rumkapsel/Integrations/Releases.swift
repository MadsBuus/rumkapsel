import Foundation
import simd

extension Array where Element == ReleasePR {
    var currentStaging: ReleasePR? {
        if let open = first(where: { $0.isStaging && $0.state == "OPEN" }) { return open }
        let shipped = filter { $0.isProduction && $0.state == "MERGED" }.compactMap(\.mergedAt).max() ?? .distantPast
        return filter { $0.isStaging && $0.state == "MERGED" && ($0.mergedAt ?? .distantPast) > shipped }
            .max { ($0.mergedAt ?? .distantPast) < ($1.mergedAt ?? .distantPast) }
    }
}

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
        guard let open = github.releases.open(repoRoot: root) else { return nil }
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

    private func label(repo: String, waiting n: Int, staging: ReleasePR?) -> String {
        let crates = "\(n) \(n == 1 ? Words.current.crate : Words.current.crates) waiting for a release"
        guard let staging else { return "rocket:\(waitingURL(repo: repo))|\(repo) · " + crates }
        return "rocket:\(staging.url)|\(repo) · staging release #\(staging.number) \(staging.title) · " + crates
    }

    func hotfixMerged(_ pr: ReleasePR, repoRoot: String) -> [WorldEvent] {
        guard let info = repoRoots[repoRoot], let station = fleet.stations[info.station], station.hasPad else { return [] }
        let record = hotfixRecord(repo: info.repo, pr: pr)
        learn(.launched(repo: info.repo, hotfix: pr.number, crates: [record.number ?? pr.number], label: label(repo: info.repo, hotfix: pr)), repo: info.repo)
        works.report(record, .shipped, by: .git, at: pr.mergedAt ?? now)
        return [.chime(pr.number)] + flyAtMerge(repoRoot: repoRoot, station: info.station, repo: info.repo, pr: pr)
    }

    func released(_ pr: ReleasePR, repoRoot: String) -> [WorldEvent] {
        guard let info = repoRoots[repoRoot], let station = fleet.stations[info.station] else { return [] }
        var events: [WorldEvent] = [.chime(pr.number)]
        guard pr.isProduction else { return events }
        learn(.launched(repo: info.repo, label: label(repo: info.repo, release: pr)), repo: info.repo)
        events += flyAtMerge(repoRoot: repoRoot, station: info.station, repo: info.repo, pr: pr)
        for r in waiting(repo: info.repo, station: station.name) {
            works.report(r, .shipped, by: pr.tag ? .git : .pulls, at: pr.mergedAt ?? now)
            if let n = r.number { report(crate: n, repo: info.repo, .shipped, by: pr.tag ? .git : .pulls, at: pr.mergedAt ?? now) }
        }
        releases.announced = releases.announced.filter { !$0.hasPrefix("\(info.station)|\(info.repo)|") }
        return events
    }

    private func applyHotfixes() -> [WorldEvent] {
        var events: [WorldEvent] = []
        for (root, info) in repoRoots.sorted(by: { $0.key < $1.key }) {
            guard let station = fleet.stations[info.station], station.hasPad, let all = github.releases.hotfixes(repoRoot: root) else { continue }
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
              github.releases.hotfixes(repoRoot: root)?.contains(where: { $0.number == n }) == true else { return station + "|" + repo }
        return RocketKey.of(station: station, repo: repo, hotfix: n)
    }

    private func flyAtMerge(repoRoot: String, station: String, repo: String, pr: ReleasePR) -> [WorldEvent] {
        guard let d = github.deployments.deploys(repoRoot: repoRoot).first(where: \.production), let newest = d.newest else { return [] }
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
        return github.pipeline(repoRoot: root).waitingURL(owner: owner, tag: github.releases.all(repoRoot: root)?.first(where: \.tag)?.head)
    }

    func launchShipped(_ r: WorkBook.Record, _ t: Transition) {
        guard t.to == .shipped, t.from != nil, !t.wasQuiet, !releases.hotfixRecords.contains(r.id), let n = r.number,
              let root = repoRoots.first(where: { $0.value.repo == r.repo })?.key, !github.pipeline(repoRoot: root).shipsAtOnce else { return }
        learn(.launched(repo: r.repo, crates: [n], label: "rocket:\(waitingURL(repo: r.repo))|\(r.repo) · shipped"), repo: r.repo)
    }

    func applyReleases() -> [WorldEvent] {
        let said = github.releases.reports()
        var events = hear(said.filter { if case .hotfixMerged = $0 { return true }; return false })
        events += applyHotfixes()
        events += hear(said.filter { if case .released = $0 { return true }; return false })
        for (root, info) in repoRoots.sorted(by: { $0.key < $1.key }) {
            guard let station = fleet.stations[info.station], station.hasPad, github.releases.open(repoRoot: root) != nil else { continue }
            let quiet = releases.seen.insert(root).inserted || settling
            let key = info.station + "|" + info.repo
            guard let pr = padRelease(root: root) else {
                learn(.release(repo: info.repo, production: nil, label: label(repo: info.repo, waiting: waiting(repo: info.repo, station: station.name).count,
                                                                               staging: github.releases.all(repoRoot: root)?.currentStaging), quiet: quiet), repo: info.repo)
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
            guard fleet.stations[info.station] != nil, let all = github.releases.all(repoRoot: root) else { continue }
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
                    let stamp = "\(github.board.fetchedAt?.timeIntervalSince1970 ?? 0)|\(String(describing: github.git.counted(repoRoot: root)))|"
                        + "\(String(describing: ConfigStore.shared.current.project))|\(String(describing: github.pipeline(repoRoot: root)))"
                    guard yardStamps[root] != stamp else { continue }
                    if let c = github.cargo(repoRoot: root) { reconcile(repo: info.repo, root: root, cargo: c); yardStamps[root] = stamp }
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
        for pull in c.staged {
            guard let r = works.find(repo: repo, pull: pull) ?? github.task(repo: repo, pull: pull).flatMap({ works.find(repo: repo, crate: $0) }),
                  r.stage == .stored else { continue }
            works.report(r, .qa, by: .git, at: now)
        }
        let listed = Set(c.storageNumbers + c.deckNumbers + c.clearedNumbers)
        let shippedColumn = ConfigStore.shared.current.statuses.shipped
        for r in works.records(repo: repo) {
            guard let n = r.number, let stage = r.stage, stage >= .stored, stage < .shipped else { continue }
            if c.source == .git, c.exact, !listed.contains(n), !r.pulls.keys.contains(where: listed.contains),
               let at = r.stagedAt, at < c.at {
                works.report(r, .shipped, by: .git, at: c.at)
            } else if !shippedColumn.isEmpty, github.board.liveItems?.contains(where: { $0.repo == repo && $0.number == n && $0.status == shippedColumn }) == true {
                works.report(r, .shipped, by: .board, at: now)
            }
        }
        guard c.exact || c.source == .board, feed.swept.insert(repo + "|" + c.source.rawValue).inserted else { return }
        let held = works.records(repo: repo).compactMap { r -> Int? in
            let inYard = r.stage.map { $0 >= .stored && $0 < .shipped } ?? false
            return inYard || r.pulls.keys.contains(where: listed.contains) ? r.number : nil
        }
        learn(.sweep(repo: repo, keep: listed.union(held).sorted()), repo: repo)
    }

    func yardNumbers() -> [(root: String, repo: String, numbers: [Int])] {
        var seen = Set<String>()
        return repoRoots.sorted { $0.key < $1.key }.compactMap { root, info in
            guard seen.insert(info.repo).inserted else { return nil }
            let numbers = works.records(repo: info.repo).filter { $0.stage.map { $0 >= .stored && $0 < .shipped } == true }.compactMap(\.number)
            return numbers.isEmpty ? nil : (root, info.repo, numbers.sorted())
        }
    }

    func rebuildYard(dug: [(repo: String, found: [Int: [PullSource.Dug]])] = []) {
        for (repo, found) in dug {
            for (n, pulls) in found.sorted(by: { $0.key < $1.key }) {
                for p in pulls {
                    let r = works.note(repo: repo, issue: p.number == n ? nil : n, pull: p.number, pullState: p.state)
                    report(pullState: p.state, record: r, shipped: p.shipped, at: now)
                }
            }
        }
        yardStamps = [:]
        feed.swept = []
        for repo in Set(repoRoots.values.map(\.repo)).sorted() {
            let yard = works.records(repo: repo).filter { r in r.number != nil && r.stage.map { $0 >= .stored && $0 < .shipped } == true }
            learn(.sweep(repo: repo, keep: yard.compactMap(\.number).sorted()), repo: repo)
            for r in yard {
                var news = WorkNews(crate: CrateID(repo: repo, number: r.number!), office: office(for: r)?.room.key, stage: r.stage!, quiet: true)
                news.untested = offBoard(r)
                news.housekeeping = r.housekeeping
                learn(.work(news), repo: repo)
            }
        }
        learn(.restack)
    }

    func padSlots(station: Station) -> [SIMD2<Double>] { station.hall.padSlots }
}

final class ReleaseSource: Intake {
    let name = "releases"
    private weak var github: GitHubResolver?
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "rumkapsel.releases", qos: .utility, attributes: .concurrent)
    private var releases: [String: ([ReleasePR], Date)] = [:]
    private var hotfixes: [String: ([ReleasePR], Date)] = [:]
    private var launches: [Report] = []
    private var reading = Set<String>()
    private var rerun = Set<String>()

    init(github: GitHubResolver) { self.github = github }

    func checks() -> [Watch.Check] { [] }

    func reports() -> [Report] {
        lock.lock(); defer { lock.unlock() }
        let out = launches; launches = []; return out
    }

    func open(repoRoot: String) -> [ReleasePR]? {
        lock.lock(); defer { lock.unlock() }
        return releases[repoRoot]?.0.filter { $0.state == "OPEN" }
    }

    func all(repoRoot: String) -> [ReleasePR]? {
        lock.lock(); defer { lock.unlock() }
        return releases[repoRoot]?.0
    }

    func hotfixes(repoRoot: String) -> [ReleasePR]? {
        lock.lock(); defer { lock.unlock() }
        return hotfixes[repoRoot]?.0
    }

    func isBusy(repoRoot: String) -> Bool { lock.lock(); defer { lock.unlock() }; return reading.contains(repoRoot) }

    func invalidate(repoRoot: String?) {
        lock.lock(); defer { lock.unlock() }
        for k in releases.keys where repoRoot.map({ $0 == k }) ?? true { releases[k] = (releases[k]!.0, .distantPast) }
    }

    func refetch(_ repoRoot: String) {
        lock.lock()
        if let r = releases[repoRoot] { releases[repoRoot] = (r.0, .distantPast) }
        if reading.contains(repoRoot) { rerun.insert(repoRoot) }
        lock.unlock()
        refresh(repoRoot: repoRoot)
    }

    func refresh(repoRoot: String) {
        guard let github, !github.frozen else { return }
        lock.lock()
        if let (_, at) = releases[repoRoot], Date().timeIntervalSince(at) < github.baseInterval { lock.unlock(); return }
        if reading.contains(repoRoot) { lock.unlock(); return }
        reading.insert(repoRoot)
        lock.unlock()
        github.trace("ask releases \(repoRoot)")
        queue.async { [self] in
            guard let github = self.github else { lock.lock(); reading.remove(repoRoot); lock.unlock(); return }
            let began = Date()
            let (pipe, pipelineChanged) = github.readPipeline(repoRoot: repoRoot)
            let (found, foundHotfixes) = read(pipe, repoRoot: repoRoot, github: github)
            let cargoChanged = github.git.count(repoRoot: repoRoot, pipe: pipe, releases: found, began: began)
            lock.lock()
            var heat = false
            if let (before, at) = hotfixes[repoRoot] {
                for pr in foundHotfixes where pr.state == "MERGED" {
                    let was = before.first { $0.number == pr.number }
                    guard was?.state == "OPEN" || (was == nil && (pr.mergedAt ?? .distantPast) > at) else { continue }
                    launches.append(.hotfixMerged(repoRoot: repoRoot, pr))
                    heat = true
                }
            }
            let previous = releases[repoRoot]?.0 ?? []
            for pr in found where pr.state == "MERGED" && previous.contains(where: { $0.number == pr.number && $0.state == "OPEN" }) {
                launches.append(.released(repoRoot: repoRoot, pr))
                heat = true
            }
            if let tag = found.first(where: \.tag), !previous.isEmpty, !previous.contains(where: { $0.tag && $0.head == tag.head }) {
                launches.append(.released(repoRoot: repoRoot, tag))
            }
            let changed = previous != found || hotfixes[repoRoot]?.0 != foundHotfixes
            hotfixes[repoRoot] = (foundHotfixes, Date())
            releases[repoRoot] = (found, Date())
            reading.remove(repoRoot)
            let again = rerun.remove(repoRoot) != nil
            lock.unlock()
            if heat { github.watch.tune(repoRoot + "#watch:runs") { $0.heat(for: Deployments.findWithin, Date()) } }
            if again { refetch(repoRoot) }
            if changed || cargoChanged || pipelineChanged { DispatchQueue.main.async { github.onUpdate?() } }
        }
    }

    private func read(_ pipe: Pipeline, repoRoot: String, github: GitHubResolver) -> (releases: [ReleasePR], hotfixes: [ReleasePR]) {
        let trunk = pipe.trunk, stagingBranch = pipe.staging, productionBranch = pipe.production
        var found: [ReleasePR] = []
        var foundHotfixes: [ReleasePR] = []
        let bases = pipe.remote ? [stagingBranch, productionBranch].filter { !$0.isEmpty } : []
        func isReleaseHead(_ head: String) -> Bool { pipe.isReleaseHead(head) }
        for base in bases {
            guard let out = github.run(["gh", "pr", "list", "--base", base, "--state", "all", "--limit", "5",
                                 "--json", "number,title,baseRefName,headRefName,state,url,labels,mergedAt"], cwd: repoRoot),
                  let arr = try? JSONSerialization.jsonObject(with: out) as? [[String: Any]] else { continue }
            for o in arr {
                let head = o["headRefName"] as? String ?? ""
                let hotfix = base == productionBranch && !isReleaseHead(head)
                guard isReleaseHead(head) || hotfix else { continue }
                let labels = (o["labels"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
                var pr = ReleasePR(number: o["number"] as? Int ?? 0, title: o["title"] as? String ?? "", base: base,
                                   head: head, state: o["state"] as? String ?? "", url: o["url"] as? String ?? "", labels: labels,
                                   mergedAt: (o["mergedAt"] as? String).flatMap(ISO8601DateFormatter().date(from:)),
                                   production: base == productionBranch, staging: !stagingBranch.isEmpty && base == stagingBranch)
                pr.hotfix = hotfix
                if hotfix { foundHotfixes.append(pr) } else { found.append(pr) }
            }
        }
        if pipe.shipsOnTag, let newest = GitHubResolver.tags(repoRoot: repoRoot, run: github.run).first {
            let owner = github.nameWithOwner(repoRoot: repoRoot)
            let url = owner.map { "https://github.com/\($0)/releases/tag/\(newest.name)" } ?? ""
            found.append(ReleasePR(number: 0, title: newest.name, base: trunk, head: newest.name, state: "MERGED",
                                   url: url, labels: [], mergedAt: newest.at, production: true, staging: false, tag: true))
        }
        return (found, foundHotfixes)
    }

    func reset() { lock.lock(); releases = [:]; hotfixes = [:]; launches = []; lock.unlock() }

    func inject(releases rs: [ReleasePR], for repoRoot: String, merged: [ReleasePR]) {
        lock.lock()
        releases[repoRoot] = (rs, Date())
        for pr in merged { launches.append(.released(repoRoot: repoRoot, pr)) }
        lock.unlock()
    }

    func inject(hotfixes hs: [ReleasePR], for repoRoot: String, merged: [ReleasePR]) {
        lock.lock()
        hotfixes[repoRoot] = (hs, Date())
        for pr in merged { launches.append(.hotfixMerged(repoRoot: repoRoot, pr)) }
        lock.unlock()
    }
}
