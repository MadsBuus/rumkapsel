import Foundation

extension Rules {
    static let flightWindow: TimeInterval = 60

    static func release(_ repo: String, production: Bool?, label: String, quiet: Bool, _ f: inout Facts, _ fx: inout [Effect]) {
        let r = f.repo(repo)
        let standing = f.rockets.values.filter { $0.repo == repo && $0.kind == .release && !$0.launched }.min { $0.id < $1.id }
        guard production != nil || (r.ships && !r.shipsAtOnce && !f.cargo(repo).isEmpty) else {
            if let standing { f.rockets[standing.id] = nil }
            return
        }
        var rocket = standing ?? RocketFact(id: "\(repo)|release#\(f.take())", repo: repo, kind: .release, label: label)
        rocket.label = label
        rocket.docked = production == true
        f.rockets[rocket.id] = rocket
        if quiet { fx.append(.quiet(.rocket(rocket.id))) } else if standing == nil { fx.append(.log("\(repo) \(Words.current.standingBy)")) }
    }

    static func hotfixes(_ repo: String, open: [Int: String], quiet: Bool, _ f: inout Facts, _ fx: inout [Effect]) {
        for r in f.rockets.values.sorted(by: { $0.id < $1.id }) where r.repo == repo && !r.launched {
            if case .hotfix(let n) = r.kind, open[n] == nil { f.rockets[r.id] = nil }
        }
        for (n, label) in open.sorted(by: { $0.key < $1.key }) {
            let id = "\(repo)|hotfix#\(n)"
            if f.rockets[id] != nil { f.rockets[id]?.label = label; continue }
            f.rockets[id] = RocketFact(id: id, repo: repo, kind: .hotfix(n), label: label, docked: true)
            fx.append(quiet ? .quiet(.rocket(id)) : .log("\(repo) \(Words.current.standingBy)"))
        }
    }

    static func launch(_ repo: String, hotfix: Int?, crates: [Int]?, label: String, _ now: Date, _ f: inout Facts, _ g: YardGeometry, _ fx: inout [Effect]) {
        let listed = crates ?? hotfix.map { [$0] }
        let going = listed.map { numbers in
            numbers.map { CrateID(repo: repo, number: $0) }.filter { id in f.crates[id].map { if case .aboard = $0.place { return false }; return true } ?? false }
        } ?? f.cargo(repo).sorted { $0.seq > $1.seq }.map(\.id)
        let releases = f.rockets.values.filter { $0.repo == repo && $0.kind == .release }.sorted { $0.id < $1.id }
        var rocket: RocketFact
        if let n = hotfix {
            let id = "\(repo)|hotfix#\(n)"
            rocket = f.rockets[id] ?? RocketFact(id: id, repo: repo, kind: .hotfix(n), label: label)
            guard !rocket.launched else { return }
        } else if let fresh = releases.first(where: { $0.launchedAt == now }) {
            rocket = fresh
        } else if crates != nil, going.isEmpty {
            return
        } else if let standing = releases.first(where: { !$0.launched }) {
            rocket = standing
        } else {
            guard !going.isEmpty else { return }
            rocket = RocketFact(id: "\(repo)|release#\(f.take())", repo: repo, kind: .release, label: label)
        }
        if !label.isEmpty { rocket.label = label }
        rocket.docked = true
        rocket.launchedAt = now
        f.rockets[rocket.id] = rocket
        for id in going { put(id, .aboard(rocket.id), &f, g) }
        let what = hotfix.map { "hotfix #\($0) merged" } ?? crates.map { "\($0.sorted().map { "#\($0)" }.joined(separator: ", ")) shipped" } ?? "release merged"
        fx.append(.log("\(repo): \(what), \(aboard(f.aboard(rocket.id).count))"))
    }

    static func mergeRocket(_ crate: CrateID, link: String, quiet: Bool, _ now: Date, _ f: inout Facts, _ fx: inout [Effect]) -> RocketID {
        let id = "\(crate.repo)|merge#\(f.nextSeq)"
        var rocket = RocketFact(id: id, repo: crate.repo, kind: .merge, label: "rocket:\(link)|\(crate.repo) · deployed on merge", docked: true)
        rocket.launchedAt = now
        f.rockets[id] = rocket
        fx.append(quiet ? .quiet(.rocket(id)) : .log("\(crate.repo): #\(crate.number) merged, \(aboard(1))"))
        return id
    }

    private static func aboard(_ n: Int) -> String {
        n == 0 ? "nothing \(Words.current.aboard)" : n == 1 ? "1 \(Words.current.crate) \(Words.current.aboard)" : "\(n) \(Words.current.crates) \(Words.current.aboard)"
    }

    static func ready(_ f: inout Facts) {
        for r in f.rockets.values.sorted(by: { $0.id < $1.id }) where !r.launched {
            if r.kind == .release, f.repo(r.repo).shipsAtOnce { f.rockets[r.id] = nil; continue }
            let cargo = f.cargo(r.repo)
            let go = r.kind == .release && r.docked && !cargo.isEmpty && (!f.repo(r.repo).hasCleared || cargo.allSatisfy(\.cleared))
            f.rockets[r.id]?.go = go
        }
    }

    static func assignPads(_ f: inout Facts, pads: Int, at now: Date) {
        func flying(_ r: RocketFact) -> Bool { r.launchedAt.map { now.timeIntervalSince($0) < flightWindow } ?? false }
        func rank(_ r: RocketFact) -> Int {
            if r.launched { return flying(r) ? 2 : 0 }
            if r.kind != .release || r.docked || f.staging[r.repo]?.underway == true { return 2 }
            return 1
        }
        for id in f.rockets.keys.sorted() {
            guard let r = f.rockets[id], let slot = r.slot, slot >= pads || rank(r) == 0 else { continue }
            f.rockets[id]?.slot = nil
        }
        let waiting = f.rockets.values.filter { $0.slot == nil && rank($0) > 0 }.sorted { rank($0) != rank($1) ? rank($0) > rank($1) : $0.id < $1.id }
        for r in waiting {
            let held = f.rockets.values.filter { $0.slot != nil }
            let taken = Set(held.compactMap(\.slot))
            if let free = (0..<pads).first(where: { !taken.contains($0) }) { f.rockets[r.id]?.slot = free; continue }
            guard let victim = held.filter({ rank($0) < rank(r) }).min(by: { rank($0) != rank($1) ? rank($0) < rank($1) : $0.id > $1.id }) else { continue }
            f.rockets[r.id]?.slot = victim.slot
            f.rockets[victim.id]?.slot = nil
        }
    }
}
