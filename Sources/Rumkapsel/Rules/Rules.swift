import Foundation

struct WorkNews: Equatable {
    var crate: CrateID
    var office: String?
    var stage: Stage
    var closed = false
    var quiet = false
    var link = ""
    var by: Source?
    var pull: Int?
    var untested = false
}

enum OfficeNews: Equatable {
    case opened(String, repo: String?, via: OfficeFact.Via)
    case renamed(from: String, to: String)
    case status(String, crate: CrateID?, merged: Bool, closedAt: Date?)
    case gone(String)
}

enum StagingNews: Equatable { case opened(Int), merged(Int), closed(Int), deploy(StagingFact.Deploy) }

enum Event: Equatable {
    case policy(repo: String, RepoFacts)
    case work(WorkNews)
    case office(OfficeNews)
    case decon(repo: String, open: [Int], quiet: Bool = false)
    case deconClosed(CrateID)
    case renumbered(from: CrateID, to: CrateID)
    case staging(repo: String, StagingNews)
    case release(repo: String, production: Bool?, label: String, quiet: Bool = false)
    case hotfixes(repo: String, open: [Int: String], quiet: Bool = false)
    case launched(repo: String, hotfix: Int? = nil, crates: [Int]? = nil, label: String = "")
    case sweep(repo: String, keep: [Int])
    case restack
    case tick
}

enum Subject: Hashable { case crate(CrateID), office(String), rocket(RocketID) }

enum Effect: Equatable {
    case log(String)
    case quiet(Subject)
    case renamed(Subject, to: Subject)
    case hatch(repo: String)
}

enum Rules {
    static let closedFor: TimeInterval = 600, launchedFor: TimeInterval = 600, unshippedFor: TimeInterval = 3 * 3600

    static func apply(_ events: [Event], at now: Date, to f: inout Facts, yard g: YardGeometry) -> [Effect] {
        var fx: [Effect] = []
        var arrived: [String: [Zone: [Int]]] = [:]
        let go = Set(f.rockets.values.filter(\.go).map(\.id))
        for event in events {
            switch event {
            case .policy(let repo, let r):
                let first = f.repos[repo] == nil
                f.repos[repo] = r
                for id in f.crates.values.filter({ $0.id.repo == repo }).sorted(by: { $0.seq < $1.seq }).map(\.id) {
                    guard let c = f.crates[id], let stage = c.stage else { continue }
                    if put(id, place(stage, r, office: nil, old: c.place), &f, g), first { fx.append(.quiet(.crate(id))) }
                }
            case .work(let news):
                work(news, now, &f, g, &fx, &arrived)
            case .office(let news):
                office(news, &f, g, &fx)
            case .decon(let repo, let open, let quiet):
                let new = Set(open).sorted().filter { f.crates[CrateID(repo: repo, number: $0)] == nil }
                guard !new.isEmpty else { continue }
                if !quiet { fx.append(.hatch(repo: repo)) }
                for number in new {
                    let id = CrateID(repo: repo, number: number)
                    put(id, .decon, &f, g)
                    f.crates[id]?.alien = true
                    fx.append(quiet ? .quiet(.crate(id)) : .log("\(Words.current.unidentified) #\(number) in \(Words.current.inDecon)"))
                }
            case .deconClosed(let id):
                guard f.crates[id]?.zone == .decon else { continue }
                put(id, nil, &f, g)
                fx.append(.log("#\(id.number) \(Words.current.ejected), never cleared"))
            case .renumbered(let from, let to):
                guard from != to, let c = f.crates[from] else { continue }
                if f.crates[to] == nil {
                    f.crates[from] = nil
                    f.crates[to] = CrateFact(id: to, place: c.place, stage: c.stage, alien: c.alien, seq: c.seq, column: c.column, closedAt: c.closedAt)
                    f.crates[to]?.storedAt = c.storedAt
                    fx.append(.renamed(.crate(from), to: .crate(to)))
                } else {
                    put(from, nil, &f, g)
                }
            case .staging(let repo, let news):
                staging(repo, news, now, &f)
            case .release(let repo, let production, let label, let quiet):
                release(repo, production: production, label: label, quiet: quiet, &f, &fx)
            case .hotfixes(let repo, let open, let quiet):
                hotfixes(repo, open: open, quiet: quiet, &f, &fx)
            case .launched(let repo, let hotfix, let crates, let label):
                launch(repo, hotfix: hotfix, crates: crates, label: label, now, &f, g, &fx)
            case .sweep(let repo, let keep):
                let kept = Set(keep)
                for c in f.crates.values.filter({ $0.id.repo == repo && $0.onRow && !kept.contains($0.id.number) }).sorted(by: { $0.seq > $1.seq }) {
                    put(c.id, nil, &f, g)
                    fx.append(.quiet(.crate(c.id)))
                }
            case .restack:
                Layout.relayout(&f, yard: g)
            case .tick:
                for c in f.crates.values.sorted(by: { $0.id < $1.id }) where c.place == .waiting && !f.repo(c.id.repo).ships {
                    if let at = c.storedAt, now.timeIntervalSince(at) > unshippedFor { put(c.id, nil, &f, g) }
                }
            }
        }
        for repo in arrived.keys.sorted() {
            for zone in Zone.allCases {
                guard let numbers = arrived[repo]?[zone] else { continue }
                fx.append(.log("\(repo) \(numbers.map { "#\($0)" }.joined(separator: ", ")) to \(zone.words)"))
            }
        }
        normalize(&f, at: now, yard: g)
        for r in f.rockets.values.sorted(by: { $0.id < $1.id }) where r.go && !go.contains(r.id) && !fx.contains(.quiet(.rocket(r.id))) {
            fx.append(.log("\(r.repo) \(Words.current.steaming), waiting for the release to merge"))
        }
        return fx
    }

    static func officeEnds(_ o: OfficeFact, now: Date, mine: Bool, lan: Bool) -> String? {
        guard !mine, !lan else { return nil }
        if o.merged { return "merged" }
        if let at = o.closedAt, now.timeIntervalSince(at) > closedFor { return "closed, not merged" }
        return nil
    }

    static func place(_ stage: Stage, _ r: RepoFacts, office: String?, old: CrateFact.Place?) -> CrateFact.Place? {
        if case .aboard? = old { return old }
        switch stage {
        case .inbound, .working: return nil
        case .ready: return office.map(CrateFact.Place.office) ?? old
        case .stored: return .waiting
        case .qa: return r.hasStaging ? .testing : .waiting
        case .cleared: return r.hasStaging ? .cleared : .waiting
        case .shipped: return nil
        }
    }

    static func normalize(_ f: inout Facts, at now: Date, yard g: YardGeometry) {
        for c in f.crates.values where (c.place == .waiting) != (c.storedAt != nil) { f.crates[c.id]?.storedAt = c.place == .waiting ? now : nil }
        let expired = f.crates.values.filter { $0.closedAt.map { now.timeIntervalSince($0) >= closedFor } ?? false }.map(\.id)
        for id in expired.sorted() { put(id, nil, &f, g) }
        for r in f.rockets.values.sorted(by: { $0.id < $1.id }) {
            guard let at = r.launchedAt, now.timeIntervalSince(at) >= launchedFor else { continue }
            f.rockets[r.id] = nil
            f.crates = f.crates.filter { $0.value.place != .aboard(r.id) }
        }
        let onRows = Set(f.crates.values.filter(\.onRow).map(\.id.repo))
        for repo in f.homes.keys.sorted() where !onRows.contains(repo) { f.homes[repo] = nil }
        var full: Set<Zone> = []
        for c in f.crates.values.filter({ $0.zone != nil && $0.column == nil }).sorted(by: { $0.seq < $1.seq }) {
            guard let zone = c.zone, !full.contains(zone) else { continue }
            if zone.isRow, f.homes[c.id.repo] == nil { f.homes[c.id.repo] = Layout.newHome(c.id.repo, f) }
            guard let column = Layout.pickColumn(c.id.repo, zone, f, g) else { full.insert(zone); continue }
            let seq = f.take()
            f.crates[c.id]?.seq = seq
            f.crates[c.id]?.column = column
        }
        let strays = f.crates.values.filter { c in c.onRow && c.column.map { Layout.band($0) != f.homes[c.id.repo] } ?? false }
        var noRoom: [Zone: Set<String>] = [:]
        for c in strays.sorted(by: { $0.id < $1.id }) {
            guard let zone = c.zone, noRoom[zone]?.contains(c.id.repo) != true else { continue }
            guard let to = Layout.homeColumn(c.id.repo, zone, f) else { noRoom[zone, default: []].insert(c.id.repo); continue }
            let seq = f.take()
            f.crates[c.id]?.seq = seq
            f.crates[c.id]?.column = to
            break
        }
        for (repo, s) in f.staging.sorted(by: { $0.key < $1.key }) where s.settled(at: now) { f.staging[repo] = nil }
        ready(&f)
        assignPads(&f, pads: g.pads, at: now)
    }

    private static func work(_ news: WorkNews, _ now: Date, _ f: inout Facts, _ g: YardGeometry, _ fx: inout [Effect],
                             _ arrived: inout [String: [Zone: [Int]]]) {
        let id = news.crate, r = f.repo(id.repo)
        let old = f.crates[id]?.place
        var to = place(news.stage, r, office: news.office, old: old)
        if news.untested, to == .testing { to = .cleared }
        if r.shipsOnMerge, to == .waiting, old != .waiting {
            to = .aboard(mergeRocket(id, link: news.link, quiet: news.quiet, now, &f, &fx))
        }
        let moved = put(id, to, &f, g)
        guard f.crates[id] != nil else { return }
        f.crates[id]?.stage = news.stage
        let closedAt = f.crates[id]?.closedAt
        f.crates[id]?.closedAt = news.closed ? closedAt ?? now : nil
        guard moved else { return }
        if news.quiet { fx.append(.quiet(.crate(id))) }
        else if let zone = to?.zone { arrived[id.repo, default: [:]][zone, default: []].append(id.number) }
    }

    private static func office(_ news: OfficeNews, _ f: inout Facts, _ g: YardGeometry, _ fx: inout [Effect]) {
        switch news {
        case .opened(let key, let repo, let via):
            guard f.offices[key] == nil else { return }
            f.offices[key] = OfficeFact(key: key, repo: repo, via: via)
            if via == .appear { fx.append(.quiet(.office(key))) }
        case .renamed(let from, let to):
            guard from != to else { return }
            for c in f.crates.values where c.place == .office(from) { f.crates[c.id]?.place = .office(to) }
            guard let o = f.offices.removeValue(forKey: from) else { return }
            if f.offices[to] == nil { f.offices[to] = o.keyed(to) }
            fx.append(.renamed(.office(from), to: .office(to)))
        case .status(let key, let crate, let merged, let closedAt):
            guard var o = f.offices[key] else { return }
            o.crate = crate; o.merged = merged
            o.closedAt = closedAt.map { at in o.closedAt.map { min($0, at) } ?? at }
            f.offices[key] = o
        case .gone(let key):
            guard f.offices.removeValue(forKey: key) != nil else { return }
            for c in f.crates.values.filter({ $0.place == .office(key) }).sorted(by: { $0.id < $1.id }) { put(c.id, nil, &f, g) }
        }
    }

    private static func staging(_ repo: String, _ news: StagingNews, _ now: Date, _ f: inout Facts) {
        switch news {
        case .opened(let n):
            f.staging[repo] = StagingFact(number: n)
        case .merged(let n):
            var s = f.staging[repo] ?? StagingFact(number: n)
            s.number = n
            s.merged = true
            s.mergedAt = now
            f.staging[repo] = s
        case .closed(let n):
            if f.staging[repo]?.number == n { f.staging[repo] = nil }
        case .deploy(let d):
            f.staging[repo, default: StagingFact(number: 0, merged: true, mergedAt: now)].deploy = d
            f.staging[repo]?.heardAt = now
        }
    }

    @discardableResult
    static func put(_ id: CrateID, _ to: CrateFact.Place?, _ f: inout Facts, _ g: YardGeometry) -> Bool {
        let old = f.crates[id]
        guard old?.place != to else { return false }
        if let old, let zone = old.zone, let column = old.column { leave(old, zone, column, &f, g) }
        guard let to else { f.crates[id] = nil; return true }
        var c = old ?? CrateFact(id: id, place: to, seq: 0)
        c.place = to
        c.column = nil
        c.seq = f.take()
        f.crates[id] = c
        guard let zone = to.zone else { return true }
        if zone.isRow, f.homes[id.repo] == nil { f.homes[id.repo] = Layout.newHome(id.repo, f) }
        let column = Layout.pickColumn(id.repo, zone, f, g)
        f.crates[id]?.column = column
        return true
    }

    private static func leave(_ c: CrateFact, _ zone: Zone, _ column: Int, _ f: inout Facts, _ g: YardGeometry) {
        f.crates[c.id]?.column = nil
        guard zone.isRow else { return }
        let above = f.crates.values.filter { $0.zone == zone && $0.column == column && $0.seq > c.seq }.sorted { $0.seq > $1.seq }.map(\.id)
        var stay: [CrateID] = []
        for id in above {
            f.crates[id]?.column = nil
            guard let to = Layout.pickColumn(id.repo, zone, f, g, avoiding: column) else { stay.append(id); continue }
            let seq = f.take()
            f.crates[id]?.seq = seq
            f.crates[id]?.column = to
        }
        for id in stay.reversed() {
            let seq = f.take()
            f.crates[id]?.seq = seq
            f.crates[id]?.column = column
        }
    }
}
