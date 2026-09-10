import Foundation

/// Everything the user can tune, persisted as JSON in Application Support.
struct AppConfig: Codable, Equatable {
    struct RepoOverride: Codable, Equatable {
        var station: String = "auto"   // auto, work, private, hidden
        var crew: Bool = true          // unused since 0.18, kept so old config files still decode
        var share: Bool = false        // visible to other rumkapsels on the local network
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
    var shareOnLAN: Bool = false
    var shareName: String = NSUserName()
    // A GitHub project whose Status field tracks issues through the pipeline. Optional fields, so
    // config files written before they existed still decode.
    var projectOwner: String?
    var projectNumber: Int?
    var projectStatuses: ProjectStatuses?

    /// The project's Status names for each stage of the station.
    struct ProjectStatuses: Codable, Equatable {
        var development = "In Development"      // a branch exists: an office
        var storage = "Ready for staging"       // merged to trunk: a crate in storage
        var deck = "QA"                         // on staging: a crate on the test deck
        var cleared = "Ready to ship"           // QA passed: a ticked crate on the deck
        var shipped = "Shipped"                 // in production: launched
    }
    var project: (owner: String, number: Int)? {
        guard let o = projectOwner, !o.isEmpty, let n = projectNumber, n > 0 else { return nil }
        return (o, n)
    }
    var statuses: ProjectStatuses { projectStatuses ?? ProjectStatuses() }

    static var url: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Rumkapsel", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("config.json")
    }

    static func load() -> AppConfig {
        if let data = try? Data(contentsOf: url), var c = try? JSONDecoder().decode(AppConfig.self, from: data) {
            // Configs from before the board existed: Tattoodo's own board, once.
            if c.projectOwner == nil, c.projectNumber == nil, c.workOwners == ["Tattoodo"] { c.projectOwner = "Tattoodo"; c.projectNumber = 4; c.save() }
            return c
        }
        var c = AppConfig()
        let home = FileManager.default.homeDirectoryForCurrentUser
        c.stationRule = FileManager.default.fileExists(atPath: home.appendingPathComponent("conductor/workspaces").path) ? "conductor" : "none"
        // Carry over the old crew.json names if present.
        let crewURL = url.deletingLastPathComponent().appendingPathComponent("crew.json")
        if let data = try? Data(contentsOf: crewURL), let names = try? JSONDecoder().decode([String: String].self, from: data) { c.crewNames = names }
        if c.crewNames.isEmpty { c.crewNames = ["donlion": "Leo", "johanplenge": "Johan", "skogge": "Chris", "MadsBuus": "Mads"] }
        if c.workOwners == ["Tattoodo"] { c.projectOwner = "Tattoodo"; c.projectNumber = 4 }
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

    func crewEnabled(repo: String) -> Bool { showCrew && repos[repo]?.station != "hidden" }
    func shared(repo: String) -> Bool { shareOnLAN && (repos[repo]?.share ?? false) }
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
