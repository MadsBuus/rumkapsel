import Foundation

struct ReleaseFile: Codable, Equatable {
    var trunk: String?
    var staging: String?
    var production: String?
    var releaseBranches: [String]?
    var boardColumns: Bool?
    var ship: String?
}

extension Pipeline {
    func overridden(by b: AppConfig.Branches?) -> Pipeline {
        guard let b else { return self }
        var p = self
        p.trunk = b.trunk; p.staging = b.staging; p.production = b.production
        p.source = "override"; p.why = "set in Settings"
        if !b.production.isEmpty, p.ship == "merge" || p.ship == "tag" { p.ship = "release" }
        return p
    }

    var flow: String {
        shipsOnMerge ? "\(trunk), ships on merge"
            : shipsOnTag ? "\(trunk), ships on tags"
            : production.isEmpty ? "\(trunk), no releases"
            : [trunk, staging, production].filter { !$0.isEmpty }.joined(separator: " → ")
    }

    static func override(forRoot root: String) -> AppConfig.Branches? {
        ConfigStore.shared.current.repos[URL(fileURLWithPath: root).lastPathComponent]?.branches
    }
}

enum PipelineDetection {
    struct Merge: Equatable { let base: String; let head: String }

    static let defaultReleaseBranches = ["release*", "hotfix*"]

    static func matches(_ branch: String, _ pattern: String) -> Bool {
        pattern.hasSuffix("*") ? branch.hasPrefix(String(pattern.dropLast())) : branch == pattern
    }

    static func detect(branches: Set<String>, merges: [Merge], file: ReleaseFile?,
                       names: (trunk: String, staging: String, production: String), deploysOnPush: Bool = false,
                       tagged: Bool = false) -> Pipeline {
        let exists: (String) -> Bool = { b in !b.isEmpty && (branches.isEmpty || branches.contains(b)) }
        let releaseLike: (String) -> Bool = { h in defaultReleaseBranches.contains { matches(h, $0) } }
        let longLived = Set([names.trunk, names.staging, names.production, "develop", "main", "master", "staging", "production"].filter { !$0.isEmpty })

        var trunk = [names.trunk, "develop", "main", "master"].first(where: exists) ?? names.trunk
        var staging = exists(names.staging) && names.staging != trunk ? names.staging : ""
        var production = [names.production, "master", "main"].first { exists($0) && $0 != trunk && $0 != staging } ?? ""
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
            let forward = edges["\(c.head)>\(c.base)", default: 0], back = edges["\(c.base)>\(c.head)", default: 0]
            if forward != back { return forward > back }
            guard let h = fromTrunk[c.head], let b = fromTrunk[c.base] else { return false }
            return h < b
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
        var ship = "release"
        if production.isEmpty, deploysOnPush {
            ship = "merge"; source = "workflow"; why = "deploys on every push to \(trunk)"
        }
        if production.isEmpty, ship == "release", tagged {
            ship = "tag"; source = "tags"; why = "no release branch: what is tagged on \(trunk) has shipped"
        }

        if let f = file {
            if let t = f.trunk, !t.isEmpty { trunk = t }
            if let s = f.staging { staging = s }
            if let p = f.production { production = p }
            if let r = f.releaseBranches { releaseBranches = r }
            if let s = f.ship { ship = s }
            source = "file"; why = ".github/rumkapsel.json"
        }
        return Pipeline(trunk: trunk, staging: staging, production: production, releaseBranches: releaseBranches,
                        boardColumns: file?.boardColumns, source: source, why: why, ship: ship)
    }
}
