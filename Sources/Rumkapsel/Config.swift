import Foundation

enum AppSupport {
    static var root: URL {
        if let dir = ProcessInfo.processInfo.environment["RUMKAPSEL_SUPPORT"] { return URL(fileURLWithPath: dir, isDirectory: true) }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }
}

struct AppConfig: Codable, Equatable {
    struct RepoOverride: Codable, Equatable {
        var station: String = "auto"
        var crew: Bool = true
        var share: Bool = false
        var color: RGB?
        var branches: Branches?
        var workflow: Workflow?
        var path: String?
    }
    struct Branches: Codable, Equatable {
        var trunk: String
        var staging: String
        var production: String
    }
    var workOwners: [String] = []
    var repos: [String: RepoOverride] = [:]
    var crewNames: [String: String] = [:]
    var viewerLogin: String?
    var githubMinutes: Int = 5
    var sleepMinutes: Int = 5
    var showCrew: Bool = true
    var showRepoTitles: Bool?
    var showTitles: Bool { showRepoTitles ?? true }
    var themeName: String?
    var theme: Theme { Theme(rawValue: themeName ?? "") ?? .classic }
    var placementName: String?
    var officePlacement: OfficePlacement { OfficePlacement(rawValue: placementName ?? "") ?? .rings }
    var trunkBranch: String = "develop"
    var stagingBranch: String = "staging"
    var productionBranch: String = "production"
    var shareOnLAN: Bool = false
    var shareName: String = NSUserName()
    var projectOwner: String?
    var projectNumber: Int?
    var projectStatuses: ProjectStatuses?
    var projectField: String?
    var useProject: Bool?
    var statusField: String { projectField ?? "Status" }

    struct ProjectStatuses: Codable, Equatable {
        var development = "In Development"
        var storage = "Ready for staging"
        var deck = "QA"
        var cleared = "Ready to ship"
        var shipped = "Shipped"
    }
    var project: (owner: String, number: Int)? {
        guard useProject != false, let o = projectOwner, !o.isEmpty, let n = projectNumber, n > 0 else { return nil }
        return (o, n)
    }
    var statuses: ProjectStatuses { projectStatuses ?? ProjectStatuses() }

    static var url: URL {
        let dir = AppSupport.root.appendingPathComponent("Rumkapsel", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("config.json")
    }

    static func load() -> AppConfig {
        if let data = try? Data(contentsOf: url), let c = try? JSONDecoder().decode(AppConfig.self, from: data) { return c }
        var c = AppConfig()
        let crewURL = url.deletingLastPathComponent().appendingPathComponent("crew.json")
        if let data = try? Data(contentsOf: crewURL), let names = try? JSONDecoder().decode([String: String].self, from: data) { c.crewNames = names }
        if Scripted.run { c.projectOwner = "example"; c.projectNumber = 1 }
        c.save()
        return c
    }

    func save() {
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(self) { try? data.write(to: AppConfig.url) }
    }

    func station(cwd: String, owner: String?, repo: String) -> String {
        shown(repo: repo) ? "work" : "hidden"
    }

    func shown(repo: String) -> Bool { !["hidden", "private"].contains(repos[repo]?.station ?? "auto") }
    func crewEnabled(repo: String) -> Bool { showCrew && shown(repo: repo) }
    func shared(repo: String) -> Bool { shareOnLAN && shown(repo: repo) && (repos[repo]?.share ?? false) }
}

final class ConfigStore {
    static let shared = ConfigStore()
    private let lock = NSLock()
    private var value = AppConfig.load()
    var onChange: ((_ old: AppConfig, _ new: AppConfig) -> Void)?

    var current: AppConfig { lock.lock(); defer { lock.unlock() }; return value }

    func update(_ f: (inout AppConfig) -> Void) {
        lock.lock()
        let old = value
        var c = value; f(&c)
        let changed = c != value
        value = c
        lock.unlock()
        if changed { c.save(); onChange?(old, c) }
    }
}
