import Foundation

enum GitHubMeter {
    struct Tally { var calls = 0, fresh = 0, same = 0, failed = 0, bytes = 0, late = 0 }

    static var on = false
    private static let lock = NSLock()
    private static var tallies: [String: Tally] = [:]
    private static var began = Date()
    private static let warmup: TimeInterval = 30

    static func start() { lock.lock(); on = true; tallies = [:]; began = Date(); lock.unlock() }

    private static var rates: [String: (used: Int, left: Int)] = [:]

    static func heard(_ path: String, status: Int, bytes: Int, headers: [String: String]) {
        count(kind(path), fresh: status == 200, same: status == 304, bytes: bytes)
        guard on, let resource = headers["x-ratelimit-resource"], let used = headers["x-ratelimit-used"].flatMap(Int.init),
              let left = headers["x-ratelimit-remaining"].flatMap(Int.init) else { return }
        lock.lock(); rates[resource] = (used, left); lock.unlock()
    }

    static func ran(_ args: [String], ok: Bool, bytes: Int) {
        guard on, args.first == "gh" || args.first == "git" else { return }
        let words = args.dropFirst().prefix(2).map { $0.hasPrefix("repos/") || $0.hasPrefix("-") ? kind($0) : $0 }
        count(([args[0]] + words).joined(separator: " "), fresh: ok, same: false, bytes: bytes)
    }

    static func kind(_ path: String) -> String {
        let bare = String(path.split(separator: "?").first ?? "")
        let parts = bare.split(separator: "/").map(String.init)
        if parts.first == "repos", parts.count > 3 { return parts.dropFirst(3).filter { Int($0) == nil }.joined(separator: "/") }
        if parts.first == "orgs", parts.count > 3 { return parts.dropFirst(2).filter { Int($0) == nil }.joined(separator: "/") }
        return bare
    }

    private static func count(_ kind: String, fresh: Bool, same: Bool, bytes: Int) {
        guard on else { return }
        lock.lock(); defer { lock.unlock() }
        var t = tallies[kind] ?? Tally()
        t.calls += 1; t.bytes += bytes
        if fresh { t.fresh += 1 } else if same { t.same += 1 } else { t.failed += 1 }
        if Date().timeIntervalSince(began) > warmup { t.late += 1 }
        tallies[kind] = t
    }

    static func report(seconds: TimeInterval) -> [String] {
        lock.lock(); let all = tallies; lock.unlock()
        let steady = max(1, seconds - warmup)
        var lines = ["kind | calls | 200/ok | 304 | failed | KB | after \(Int(warmup))s | per hour at that pace"]
        for (k, t) in all.sorted(by: { $0.value.calls > $1.value.calls }) {
            lines.append("\(k) | \(t.calls) | \(t.fresh) | \(t.same) | \(t.failed) | \(t.bytes / 1024) | \(t.late) | \(Int(Double(t.late) * 3600 / steady))")
        }
        let http = all.filter { !$0.key.hasPrefix("gh ") && !$0.key.hasPrefix("git ") }.values
        let calls = http.reduce(0) { $0 + $1.calls }, same = http.reduce(0) { $0 + $1.same }
        lines.append("REST: \(calls) calls, \(calls == 0 ? 0 : same * 100 / calls)% 304")
        lock.lock(); let seen = rates; lock.unlock()
        for (r, v) in seen.sorted(by: { $0.key < $1.key }) { lines.append("last rate headers, \(r): used \(v.used), left \(v.left)") }
        return lines
    }

    struct Limits { var core: (used: Int, left: Int, reset: Int); var graphql: (used: Int, left: Int, reset: Int) }

    static func limits(token: String?) -> Limits? {
        guard let token, let url = URL(string: "https://api.github.com/rate_limit") else { return nil }
        var request = URLRequest(url: url)
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        let done = DispatchSemaphore(value: 0)
        var out: Limits?
        URLSession.shared.dataTask(with: request) { data, _, _ in
            defer { done.signal() }
            guard let data, let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let r = o["resources"] as? [String: Any] else { return }
            func read(_ name: String) -> (Int, Int, Int) {
                let x = r[name] as? [String: Any] ?? [:]
                return (x["used"] as? Int ?? 0, x["remaining"] as? Int ?? 0, x["reset"] as? Int ?? 0)
            }
            out = Limits(core: read("core"), graphql: read("graphql"))
        }.resume()
        done.wait()
        return out
    }

    static func spent(from a: Limits, to b: Limits) -> String {
        func d(_ x: (used: Int, left: Int, reset: Int), _ y: (used: Int, left: Int, reset: Int)) -> String {
            x.reset == y.reset ? "\(y.used - x.used)" : "\(y.used)+ (window reset)"
        }
        return "rate used during the run: core \(d(a.core, b.core)) (left \(b.core.left)), graphql points \(d(a.graphql, b.graphql)) (left \(b.graphql.left))"
    }
}
