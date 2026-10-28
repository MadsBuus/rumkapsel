import Foundation

enum AppSupport {
    static var root: URL {
        if let dir = ProcessInfo.processInfo.environment["RUMKAPSEL_SUPPORT"] { return URL(fileURLWithPath: dir, isDirectory: true) }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }
}

struct AppConfig: Codable, Equatable {
    struct RepoOverride: Codable, Equatable {
        var shown = true
        var share = false
        var color: RGB?
        var path: String?
        var trunk: String?
        var ships: Ships?
        var production: String?
        var staging: String?
        var workflow: Workflow?
        var answered: Bool?
        var kept: [String]?

        var setsPipeline: Bool { trunk != nil || ships != nil || production != nil || staging != nil }

        var usingRepository: RepoOverride {
            var o = self
            o.trunk = nil; o.ships = nil; o.production = nil; o.staging = nil; o.kept = nil
            return o
        }
    }
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
    var dramaticLight: Bool?
    var officePlacement: OfficePlacement { OfficePlacement(rawValue: placementName ?? "") ?? .rings }
    var shareOnLAN: Bool = false
    var shareName: String = NSUserName()
    var projectOwner: String?
    var projectNumber: Int?
    var projectStatuses: ProjectStatuses?
    var projectField: String?
    var useProject: Bool?
    var sentryOrg: String?
    var sentryRegion: String?
    var sentryProjects: [String: String]?
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

    static func fresh() -> AppConfig {
        var c = AppConfig()
        let crewURL = url.deletingLastPathComponent().appendingPathComponent("crew.json")
        if let data = try? Data(contentsOf: crewURL), let names = try? JSONDecoder().decode([String: String].self, from: data) { c.crewNames = names }
        if Scripted.run { c.projectOwner = "example"; c.projectNumber = 1 }
        return c
    }

    func station(cwd: String, owner: String?, repo: String) -> String {
        shown(repo: repo) ? "work" : "hidden"
    }

    func shown(repo: String) -> Bool { repos[repo]?.shown ?? true }
    func crewEnabled(repo: String) -> Bool { showCrew && shown(repo: repo) }
    func shared(repo: String) -> Bool { shareOnLAN && shown(repo: repo) && (repos[repo]?.share ?? false) }

    var withoutAnswers: AppConfig {
        var c = self
        for (name, r) in c.repos {
            var bare = r
            bare.answered = nil
            bare.kept = nil
            c.repos[name] = bare == RepoOverride() ? nil : bare
        }
        return c
    }
}

extension AppConfig.RepoOverride {
    enum CodingKeys: String, CodingKey { case shown, share, color, path, trunk, ships, production, staging, workflow, answered, kept }
    private enum Retired: String, CodingKey { case station, crew, branches }
    private struct Branches: Decodable { var trunk: String; var staging: String; var production: String }

    init(from decoder: Decoder) throws {
        self.init()
        guard let c = try? decoder.container(keyedBy: CodingKeys.self), let old = try? decoder.container(keyedBy: Retired.self) else { return }
        func read<T: Decodable>(_ key: CodingKeys) -> T? { (try? c.decodeIfPresent(T.self, forKey: key)) ?? nil }
        let station = ((try? old.decodeIfPresent(String.self, forKey: .station)) ?? nil) ?? "auto"
        shown = read(.shown) ?? !["hidden", "private"].contains(station)
        share = read(.share) ?? false
        color = read(.color)
        path = read(.path)
        trunk = read(.trunk)
        ships = read(.ships)
        production = read(.production)
        staging = read(.staging)
        workflow = read(.workflow)
        answered = read(.answered)
        kept = read(.kept)
        if !setsPipeline, let b = (try? old.decodeIfPresent(Branches.self, forKey: .branches)) ?? nil {
            trunk = b.trunk.isEmpty ? nil : b.trunk
            staging = b.staging
            if b.production.isEmpty { ships = .never } else { production = b.production; ships = .release }
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(shown, forKey: .shown)
        try c.encode(share, forKey: .share)
        try c.encodeIfPresent(color, forKey: .color)
        try c.encodeIfPresent(path, forKey: .path)
        try c.encodeIfPresent(trunk, forKey: .trunk)
        try c.encodeIfPresent(ships, forKey: .ships)
        try c.encodeIfPresent(production, forKey: .production)
        try c.encodeIfPresent(staging, forKey: .staging)
        try c.encodeIfPresent(workflow, forKey: .workflow)
        try c.encodeIfPresent(answered, forKey: .answered)
        try c.encodeIfPresent(kept, forKey: .kept)
        var old = encoder.container(keyedBy: Retired.self)
        try old.encode(shown ? "auto" : "hidden", forKey: .station)
        try old.encode(true, forKey: .crew)
    }
}

enum ConfigFile {
    static let legacy: [String: Any] = ["trunkBranch": "develop", "stagingBranch": "staging", "productionBranch": "production", "workOwners": [String]()]
    private static let retired: Set<String> = ["branches"]
    private static let lock = NSLock()
    private static var raws: [String: [String: Any]] = [:]

    static func read(from url: URL = AppConfig.url) -> (config: AppConfig, held: Bool) {
        guard let data = try? Data(contentsOf: url) else {
            let c = AppConfig.fresh()
            write(c, to: url)
            return (c, false)
        }
        do {
            let c = try JSONDecoder().decode(AppConfig.self, from: data)
            lock.lock(); raws[url.path] = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]; lock.unlock()
            return (c, false)
        } catch {
            let aside = url.deletingPathExtension().appendingPathExtension("unreadable-\(Int(Date().timeIntervalSince1970)).json")
            try? data.write(to: aside)
            StationLog.write("config", "config.json could not be read (\(error)); kept a copy as \(aside.lastPathComponent), running on defaults until a setting changes")
            return (AppConfig.fresh(), true)
        }
    }

    static func write(_ c: AppConfig, to url: URL = AppConfig.url) {
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? enc.encode(c), let fresh = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        lock.lock()
        let raw = raws[url.path] ?? [:]
        var out = raw
        for (k, v) in fresh where k != "repos" { out[k] = v }
        for k in ["viewerLogin", "showRepoTitles", "themeName", "placementName", "dramaticLight", "projectOwner", "projectNumber", "projectStatuses", "projectField", "useProject"]
            where fresh[k] == nil { out[k] = nil }
        let before = raw["repos"] as? [String: Any] ?? [:]
        var repos: [String: Any] = [:]
        for (name, entry) in fresh["repos"] as? [String: Any] ?? [:] {
            var merged = (before[name] as? [String: Any] ?? [:]).filter { !retired.contains($0.key) }
            for (k, v) in entry as? [String: Any] ?? [:] { merged[k] = v }
            for k in ["color", "path", "trunk", "ships", "production", "staging", "workflow", "answered", "kept"] where (entry as? [String: Any])?[k] == nil { merged[k] = nil }
            repos[name] = merged
        }
        out["repos"] = repos
        for (k, v) in legacy where out[k] == nil { out[k] = v }
        raws[url.path] = out
        lock.unlock()
        guard let bytes = try? JSONSerialization.data(withJSONObject: out, options: [.prettyPrinted, .sortedKeys]) else { return }
        let backup = url.appendingPathExtension("bak")
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path), !fm.fileExists(atPath: backup.path) { try? fm.copyItem(at: url, to: backup) }
        try? bytes.write(to: url, options: .atomic)
    }
}

final class ConfigStore {
    static let shared = ConfigStore()
    private let lock = NSLock()
    private var value: AppConfig
    private var held: Bool
    var onChange: ((_ old: AppConfig, _ new: AppConfig) -> Void)?

    init() { (value, held) = ConfigFile.read() }

    var current: AppConfig { lock.lock(); defer { lock.unlock() }; return value }

    func update(byUser: Bool = false, _ f: (inout AppConfig) -> Void) {
        lock.lock()
        let old = value
        var c = value; f(&c)
        let changed = c != value
        value = c
        if byUser { held = false }
        let save = changed && !held
        lock.unlock()
        if save { ConfigFile.write(c) }
        if changed { onChange?(old, c) }
    }
}
