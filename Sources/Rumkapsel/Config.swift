import Foundation

/// Everything the user can tune, persisted as JSON in Application Support.
struct AppConfig: Codable, Equatable {
    struct RepoOverride: Codable, Equatable {
        var station: String = "auto"   // auto, work, private, hidden
        var crew: Bool = true
    }
    var stationRule: String = "none"          // conductor, owner, none
    var workOwners: [String] = ["Tattoodo"]
    var repos: [String: RepoOverride] = [:]
    var crewNames: [String: String] = [:]
    var githubMinutes: Int = 5
    var sleepMinutes: Int = 5
    var showCrew: Bool = true
    var trunkBranch: String = "develop"        // where feature branches merge
    var stagingBranch: String = "staging"      // optional: a test deck between trunk and production
    var productionBranch: String = "production"

    static var url: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Rumkapsel", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("config.json")
    }

    static func load() -> AppConfig {
        if let data = try? Data(contentsOf: url), let c = try? JSONDecoder().decode(AppConfig.self, from: data) { return c }
        var c = AppConfig()
        let home = FileManager.default.homeDirectoryForCurrentUser
        c.stationRule = FileManager.default.fileExists(atPath: home.appendingPathComponent("conductor/workspaces").path) ? "conductor" : "none"
        // Carry over the old crew.json names if present.
        let crewURL = url.deletingLastPathComponent().appendingPathComponent("crew.json")
        if let data = try? Data(contentsOf: crewURL), let names = try? JSONDecoder().decode([String: String].self, from: data) { c.crewNames = names }
        if c.crewNames.isEmpty { c.crewNames = ["donlion": "Leo", "johanplenge": "Johan", "skogge": "Chris", "MadsBuus": "Mads"] }
        c.save()
        return c
    }

    func save() {
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(self) { try? data.write(to: AppConfig.url) }
    }

    /// Station for a session: an explicit repo override first, then the rule.
    func station(cwd: String, owner: String?, repo: String) -> String {
        if let o = repos[repo], o.station != "auto" { return o.station }
        switch stationRule {
        case "conductor": return cwd.contains("/conductor/") ? "work" : "private"
        case "owner":
            let owners = Set(workOwners.map { $0.lowercased() })
            return (owner.map { owners.contains($0) } ?? false) || cwd.contains("/conductor/") ? "work" : "private"
        default: return "work"
        }
    }

    func crewEnabled(repo: String) -> Bool { showCrew && (repos[repo]?.crew ?? true) }
}

/// Shared, mutable copy used by the scene; the settings window replaces it and notifies.
final class ConfigStore {
    static let shared = ConfigStore()
    private let lock = NSLock()
    private var value = AppConfig.load()
    var onChange: ((AppConfig) -> Void)?

    var current: AppConfig { lock.lock(); defer { lock.unlock() }; return value }

    func update(_ f: (inout AppConfig) -> Void) {
        lock.lock()
        var c = value; f(&c)
        let changed = c != value
        value = c
        lock.unlock()
        if changed { c.save(); onChange?(c) }
    }
}
