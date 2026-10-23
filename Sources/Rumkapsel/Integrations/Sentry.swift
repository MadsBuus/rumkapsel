import Foundation
import Security

enum Keychain {
    static let service = "dev.madsbuus.rumkapsel"
    static var off: Bool { Scripted.run || ProcessInfo.processInfo.environment["RUMKAPSEL_SUPPORT"] != nil }

    static func read(_ account: String) -> String? {
        guard !off else { return nil }
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: account, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func write(_ account: String, _ value: String) -> Bool {
        guard !off else { return false }
        delete(account)
        let item: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account,
                                   kSecValueData as String: Data(value.utf8), kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock]
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    static func delete(_ account: String) {
        guard !off else { return }
        SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account] as CFDictionary)
    }
}

struct SentryIssue: Equatable {
    let id: String
    let title: String
    let level: String
    let count: Int
    let firstSeen: Date
    let lastSeen: Date
    let link: String?
    let hourly: [Int]

    init(id: String, title: String, level: String = "error", count: Int, firstSeen: Date, lastSeen: Date, link: String? = nil, hourly: [Int] = []) {
        self.id = id; self.title = title; self.level = level; self.count = count; self.firstSeen = firstSeen; self.lastSeen = lastSeen; self.link = link
        self.hourly = hourly
    }

    init?(api o: [String: Any]) {
        guard let id = o["id"] as? String, let title = o["title"] as? String,
              let first = (o["firstSeen"] as? String).flatMap(Sentry.date), let last = (o["lastSeen"] as? String).flatMap(Sentry.date) else { return nil }
        let count = (o["count"] as? String).flatMap(Int.init) ?? (o["count"] as? Int) ?? 0
        let buckets = ((o["stats"] as? [String: Any])?["24h"] as? [[Any]]) ?? []
        let hourly = buckets.map { ($0.last as? NSNumber)?.intValue ?? 0 }
        self.init(id: id, title: title, level: o["level"] as? String ?? "error", count: count, firstSeen: first, lastSeen: last,
                  link: o["permalink"] as? String, hourly: hourly)
    }

    func fresh(at now: Date) -> Bool { now.timeIntervalSince(firstSeen) < Sentry.freshFor }
    func alarming(at now: Date) -> Bool { fresh(at: now) && (level == "fatal" || count >= Sentry.spike) }
}

enum Sentry {
    static let account = "sentry-token"
    private static let lock = NSLock()
    private static var held: String??

    static var token: String? {
        lock.lock(); defer { lock.unlock() }
        if let held { return held }
        let read = Keychain.read(account)
        held = .some(read)
        return read
    }

    static func keep(_ token: String?) {
        lock.lock(); defer { lock.unlock() }
        if let token { Keychain.write(account, token) } else { Keychain.delete(account) }
        held = .some(token)
    }
    static let freshFor: TimeInterval = 3600, spike = 20

    static func date(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }

    enum Level: Int, Comparable {
        case calm, rising, spiking
        static func < (a: Level, b: Level) -> Bool { a.rawValue < b.rawValue }
        var words: String { ["calm", "rising", "spiking"][rawValue] }
    }

    struct Trend: Equatable {
        let hourly: [Int]
        let level: Level
        let worst: SentryIssue?
        var lastHour: Int { hourly.last ?? 0 }
    }

    static let hours = 24

    static func trend(_ issues: [SentryIssue], at now: Date) -> Trend {
        var sum = Array(repeating: 0, count: hours)
        for i in issues { for (k, v) in i.hourly.suffix(hours).reversed().enumerated() { sum[hours - 1 - k] += v } }
        let last = sum[hours - 1], before = sum.dropLast()
        let usual = Double(before.reduce(0, +)) / Double(before.count)
        let ratio = (Double(last) + 1) / (usual + 1)
        var level: Level = last >= spike && ratio >= 4 ? .spiking : last >= 5 && ratio >= 1.8 ? .rising : .calm
        if issues.contains(where: { $0.alarming(at: now) }) { level = .spiking }
        else if issues.contains(where: { $0.fresh(at: now) }) { level = max(level, .rising) }
        let worst = issues.max { ($0.hourly.last ?? 0, $0.lastSeen) < ($1.hourly.last ?? 0, $1.lastSeen) }
        return Trend(hourly: sum, level: level, worst: worst)
    }

    static func issuesPage(org: String) -> String { "https://\(org).sentry.io/issues/" }

    static func guess(project: String, repos: [String]) -> String? {
        guard !["staging", "dev", "test"].contains(where: project.lowercased().contains) else { return nil }
        func prefix(_ a: String, _ b: String) -> Int { zip(a, b).prefix { $0 == $1 }.count }
        let best = repos.map { ($0, prefix(project.lowercased(), $0.lowercased())) }.max { ($0.1, -$0.0.count) < ($1.1, -$1.0.count) }
        return best.flatMap { $0.1 >= 5 ? $0.0 : nil }
    }

    static func get(_ url: URL, token: String) -> (data: Data, status: Int)? {
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        let done = DispatchSemaphore(value: 0)
        var out: (Data, Int)?
        URLSession.shared.dataTask(with: request) { data, response, _ in
            if let data, let http = response as? HTTPURLResponse { out = (data, http.statusCode) }
            done.signal()
        }.resume()
        done.wait()
        return out
    }

    static func base(_ region: String?) -> String { (region?.isEmpty == false ? region! : "https://sentry.io") + "/api/0/" }
}

final class SentrySource: Intake {
    let name = "sentry"
    private let lock = NSLock()
    private var pending: [Report] = []
    var trace: (String) -> Void = { _ in }

    static let detector = Detector(every: [60, 90, 300])

    func checks() -> [Watch.Check] {
        let cfg = ConfigStore.shared.current
        guard let org = cfg.sentryOrg, !(cfg.sentryProjects ?? [:]).isEmpty else { return [] }
        return (cfg.sentryProjects ?? [:]).sorted { $0.key < $1.key }.map { project, repo in
            Watch.Check("sentry:" + project, SentrySource.detector) { [weak self] in self?.read(org: org, region: cfg.sentryRegion, project: project, repo: repo) }
        }
    }

    func reports() -> [Report] {
        lock.lock(); defer { lock.unlock() }
        let out = pending; pending = []; return out
    }

    private func read(org: String, region: String?, project: String, repo: String) {
        guard let token = Sentry.token,
              let url = URL(string: Sentry.base(region) + "projects/\(org)/\(project)/issues/?query=is:unresolved&sort=new&statsPeriod=24h&limit=10") else { return }
        guard let answer = Sentry.get(url, token: token), answer.status == 200,
              let arr = try? JSONSerialization.jsonObject(with: answer.data) as? [[String: Any]] else {
            trace("sentry \(project): no answer")
            return
        }
        let found = arr.compactMap(SentryIssue.init(api:))
        lock.lock()
        pending.append(.errors(repo: repo, project: project, issues: found))
        lock.unlock()
    }
}
