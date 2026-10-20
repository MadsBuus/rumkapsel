import Foundation

enum Ships: String, Codable, CaseIterable { case release, tag, merge, never }

struct ReleaseFile: Codable, Equatable {
    var trunk: String?
    var staging: String?
    var production: String?
    var releaseBranches: [String]?
    var boardColumns: Bool?
    var ship: Ships?
}

struct Pipeline: Equatable {
    static let trunkNames = ["develop", "main", "master"]
    static let stagingName = "staging"
    static let productionName = "production"
    static let unread = Pipeline(trunk: "", staging: stagingName, production: productionName)

    var trunk: String
    var staging: String
    var production: String
    var releaseBranches: [String] = PipelineDetection.defaultReleaseBranches
    var boardColumns: Bool? = nil
    var source: String = "unread"
    var why: String = ""
    var ship: Ships = .release
    var remote = true
    var shipsOnMerge: Bool { ship == .merge }
    var shipsOnTag: Bool { ship == .tag }
    var shipsAtOnce: Bool { shipsOnMerge || shipsOnTag }
    var ships: Bool { ship != .never }
    var hasStaging: Bool { !staging.isEmpty }
    func isReleaseHead(_ head: String) -> Bool {
        head == trunk || (hasStaging && head == staging) || releaseBranches.contains { PipelineDetection.matches(head, $0) }
    }

    func overridden(by o: AppConfig.RepoOverride?) -> Pipeline {
        guard let o, o.setsPipeline else { return self }
        var p = self
        if let t = o.trunk, !t.isEmpty { p.trunk = t }
        if let s = o.staging { p.staging = s }
        if let s = o.ships { p.ship = s }
        if let b = o.production, !b.isEmpty { p.production = b }
        if p.ship != .release { p.production = "" } else if p.production.isEmpty { p.production = Pipeline.productionName }
        p.source = "override"; p.why = "set in Settings"
        return p
    }

    static func override(forRoot root: String) -> AppConfig.RepoOverride? {
        ConfigStore.shared.current.repos[URL(fileURLWithPath: root).lastPathComponent]
    }
}

enum PipelineDetection {
    struct Merge: Equatable { let base: String; let head: String }

    static let defaultReleaseBranches = ["release*", "hotfix*"]

    static func matches(_ branch: String, _ pattern: String) -> Bool {
        pattern.hasSuffix("*") ? branch.hasPrefix(String(pattern.dropLast())) : branch == pattern
    }

    static func tagged(_ tags: [(name: String, at: Date)], now: Date) -> Bool {
        tags.contains { $0.name.firstMatch(of: #/^v?\d+(\.\d+)*$/#) != nil && now.timeIntervalSince($0.at) < 365 * 24 * 3600 }
    }

    static func settle(cached: Pipeline?, read: Pipeline, failed: Bool) -> Pipeline? {
        guard failed else { return read }
        return cached.flatMap { $0.remote == read.remote ? $0 : nil }
    }

    static func detect(branches: Set<String>, merges: [Merge], file: ReleaseFile?, defaultBranch: String? = nil, history: Bool = true,
                       deploysOnPush: Bool = false, tagged: Bool = false, remote: Bool = true) -> Pipeline {
        let exists: (String) -> Bool = { b in !b.isEmpty && (branches.isEmpty || branches.contains(b)) }
        let releaseLike: (String) -> Bool = { h in defaultReleaseBranches.contains { matches(h, $0) } }
        let named = [defaultBranch].compactMap { $0 }.filter { !$0.isEmpty && $0 != Pipeline.stagingName && $0 != Pipeline.productionName }
        let longLived = Set(named + Pipeline.trunkNames + [Pipeline.stagingName, Pipeline.productionName])

        var trunk = (history ? named + Pipeline.trunkNames : Pipeline.trunkNames + named).first(where: exists) ?? named.first ?? Pipeline.trunkNames[0]
        var staging = exists(Pipeline.stagingName) && Pipeline.stagingName != trunk ? Pipeline.stagingName : ""
        var production = [Pipeline.productionName, "master", "main"].first { exists($0) && $0 != trunk && $0 != staging } ?? ""
        var releaseBranches = defaultReleaseBranches
        var source = "branches", why = "branch names only: no release history read"

        var featureInto: [String: Int] = [:]
        for m in merges where longLived.contains(m.base) && !longLived.contains(m.head) && !releaseLike(m.head) { featureInto[m.base, default: 0] += 1 }
        if let t = featureInto.sorted(by: { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }).first?.key, exists(t) { trunk = t }

        let candidates = merges.filter { longLived.contains($0.base) && $0.base != trunk && $0.base != $0.head && (longLived.contains($0.head) || releaseLike($0.head)) }
        var edges: [String: Int] = [:]
        for c in candidates { edges["\(c.head)>\(c.base)", default: 0] += 1 }
        var fromTrunk: [String: Int] = [trunk: 0]
        var frontier = [trunk]
        while !frontier.isEmpty {
            var next: [String] = []
            for b in frontier { for c in candidates where c.head == b && fromTrunk[c.base] == nil { fromTrunk[c.base] = fromTrunk[b]! + 1; next.append(c.base) } }
            frontier = next
        }
        let releases = candidates.filter { c in
            if let h = fromTrunk[c.head], let b = fromTrunk[c.base], h != b { return h < b }
            return edges["\(c.head)>\(c.base)", default: 0] > edges["\(c.base)>\(c.head)", default: 0]
        }
        if !releases.isEmpty {
            var perBase: [String: Int] = [:]
            for r in releases { perBase[r.base, default: 0] += 1 }
            let byCount: (String, String) -> Bool = { a, b in perBase[a, default: 0] != perBase[b, default: 0] ? perBase[a, default: 0] > perBase[b, default: 0] : a < b }
            let onward = Set(releases.map(\.head))
            if let p = Set(releases.map(\.base)).filter({ !onward.contains($0) && exists($0) }).sorted(by: byCount).first {
                production = p
                staging = Set(releases.map(\.base)).filter { b in b != p && exists(b) && releases.contains { $0.base == p && $0.head == b } }.sorted(by: byCount).first ?? ""
                let intoProduction = releases.filter { $0.base == p }
                var labels: [String] = []
                for h in Set(intoProduction.map(\.head)).sorted() {
                    if h != trunk && h != staging && !releaseLike(h) && !releaseBranches.contains(h) { releaseBranches.append(h) }
                    let label = releaseLike(h) ? (h.hasPrefix("hotfix") ? "hotfix branches" : "release branches") : h
                    if !labels.contains(label) { labels.append(label) }
                }
                source = "history"
                why = "\(intoProduction.count) release\(intoProduction.count == 1 ? "" : "s") into \(p) from \(labels.joined(separator: ", "))"
                    + (staging.isEmpty ? "" : "; \(releases.filter { $0.base == staging }.count) into \(staging)")
            }
        }

        if source == "branches" {
            why = merges.isEmpty ? "branch names only: no history read" : "branch names: no release among the last \(merges.count) merges"
        }
        var ship = Ships.release
        if source == "branches", production != Pipeline.productionName, deploysOnPush || tagged { production = "" }
        if production.isEmpty {
            if !remote {
                ship = .never; source = "local"; why = "no GitHub remote: local work only"
            } else if deploysOnPush {
                ship = .merge; source = "workflow"; why = "deploys on every push to \(trunk)"
            } else if tagged {
                ship = .tag; source = "tags"; why = "no release branch: what is tagged on \(trunk) has shipped"
            } else {
                ship = .never; why = "no release branch, no recent tags and no deploy on push to \(trunk)"
            }
        }

        if let f = file {
            if let t = f.trunk, !t.isEmpty { trunk = t }
            if let s = f.staging { staging = s }
            if let p = f.production { production = p }
            if let r = f.releaseBranches { releaseBranches = r }
            if let s = f.ship { ship = s } else if !production.isEmpty { ship = .release }
            source = "file"; why = ".github/rumkapsel.json"
        }
        if ship == .release, production.isEmpty { ship = .never }
        if ship != .release { production = "" }
        return Pipeline(trunk: trunk, staging: staging, production: production, releaseBranches: releaseBranches,
                        boardColumns: file?.boardColumns, source: source, why: why, ship: ship, remote: remote)
    }
}
