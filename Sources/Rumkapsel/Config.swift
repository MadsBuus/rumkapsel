import Foundation

/// Where the app keeps its files: Application Support, or the folder RUMKAPSEL_SUPPORT names, so a
/// second copy can run beside the real one without touching its layout, board and settings.
enum AppSupport {
    static var root: URL {
        if let dir = ProcessInfo.processInfo.environment["RUMKAPSEL_SUPPORT"] { return URL(fileURLWithPath: dir, isDirectory: true) }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }
}

/// Everything the user can tune, persisted as JSON in Application Support.
struct AppConfig: Codable, Equatable {
    struct RepoOverride: Codable, Equatable {
        var station: String = "auto"   // auto or hidden; "private" from before there was one station reads as hidden
        var crew: Bool = true          // unused since 0.18, kept so old config files still decode
        var share: Bool = false        // visible to other rumkapsels on the local network
        var color: RGB?                // picked in Settings; nil is the colour the name hashes to
        var branches: Branches?        // the pipeline set by hand; nil is the one read from the repository
        var workflow: Workflow?        // the way of working set by hand; nil is the one detected
        var path: String?              // a checkout added by hand in Settings, on the station with no session in it
    }
    /// A repository's way to production as set in Settings, over whatever was detected.
    struct Branches: Codable, Equatable {
        var trunk: String
        var staging: String            // "" for none
        var production: String         // "" for no releases
    }
    var workOwners: [String] = []           // unused since there is one station, kept so old config files still decode
    var repos: [String: RepoOverride] = [:]
    var crewNames: [String: String] = [:]
    /// Whose GitHub account this is. Remembered because it does not change, and because asking costs a
    /// subprocess that cannot answer until a repository has been found: without it the offices you have
    /// checked out are labelled "me" for the first few seconds of every launch, and then relabelled.
    var viewerLogin: String?
    /// The backstop: how often the whole board and every repository are read again. Changes arrive
    /// within seconds regardless, from the board's delta, the activity feeds and the predictive asks.
    var githubMinutes: Int = 5
    var sleepMinutes: Int = 5
    var showCrew: Bool = true
    /// The repository titles across the top: shown unless turned off. Optional so config files from before
    /// it existed still decode.
    var showRepoTitles: Bool?
    var showTitles: Bool { showRepoTitles ?? true }
    /// The look the station is drawn in, by `Theme` name; classic when unset or unknown.
    var themeName: String?
    var theme: Theme { Theme(rawValue: themeName ?? "") ?? .classic }
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
    /// The single-select field on the board that says where an issue is; GitHub's own Status unless set.
    var projectField: String?
    /// Off keeps the board's settings but goes without it.
    var useProject: Bool?
    var statusField: String { projectField ?? "Status" }

    /// The project's Status names for each stage of the station.
    struct ProjectStatuses: Codable, Equatable {
        var development = "In Development"      // a branch exists: an office
        var storage = "Ready for staging"       // merged to trunk: a crate in storage
        var deck = "QA"                         // on staging: a crate on the test deck
        var cleared = "Ready to ship"           // QA passed: a ticked crate on the deck
        var shipped = "Shipped"                 // in production: launched
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
        // Carry over the old crew.json names if present.
        let crewURL = url.deletingLastPathComponent().appendingPathComponent("crew.json")
        if let data = try? Data(contentsOf: crewURL), let names = try? JSONDecoder().decode([String: String].self, from: data) { c.crewNames = names }
        // A scripted run starts from a fresh config and plays a board of its own making: it needs one set.
        if Scripted.run { c.projectOwner = "example"; c.projectNumber = 1 }
        c.save()
        return c
    }

    func save() {
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(self) { try? data.write(to: AppConfig.url) }
    }

    /// Where a session goes: the station, unless its repository is kept off it. There is only ever one.
    func station(cwd: String, owner: String?, repo: String) -> String {
        shown(repo: repo) ? "work" : "hidden"
    }

    /// Whether a repository is on the station at all, asked in one place so everything agrees.
    /// A repository once sent to the private station is kept off it, as it was while that station was
    /// hidden: it is read as hidden rather than rewritten, so loading a config never changes it.
    func shown(repo: String) -> Bool { !["hidden", "private"].contains(repos[repo]?.station ?? "auto") }
    func crewEnabled(repo: String) -> Bool { showCrew && shown(repo: repo) }
    /// Hidden takes a repository off the network as well as off the floor.
    func shared(repo: String) -> Bool { shareOnLAN && shown(repo: repo) && (repos[repo]?.share ?? false) }
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
