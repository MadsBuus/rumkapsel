import Foundation

final class GitHubHTTP {
    struct Answer {
        let data: Data
        let changed: Bool
        var pollInterval: TimeInterval? = nil
    }

    static let tokenWait: TimeInterval = 10

    private let lock = NSLock()
    private let asking = NSLock()
    private let line = DispatchSemaphore(value: 1)
    private var token: String?
    private var askedAt = Date.distantPast
    private var cache: [String: (etag: String, data: Data)] = [:]
    private var gate = RateGate()
    private let session: URLSession
    private let tokenFrom: () -> String?

    init(token tokenFrom: @escaping () -> String?, session: URLSession? = nil) {
        self.tokenFrom = tokenFrom
        self.session = session ?? {
            let c = URLSessionConfiguration.ephemeral
            c.timeoutIntervalForRequest = 15
            c.requestCachePolicy = .reloadIgnoringLocalCacheData
            return URLSession(configuration: c)
        }()
    }

    var hasToken: Bool { lock.lock(); defer { lock.unlock() }; return token != nil }

    var signedIn: Bool? { lock.lock(); defer { lock.unlock() }; return token != nil ? true : askedAt == .distantPast ? nil : false }

    func askToken() { _ = currentToken() }

    var open: Bool { lock.lock(); defer { lock.unlock() }; return gate.open(Date()) }

    var ghOpen: Bool { lock.lock(); defer { lock.unlock() }; return gate.ghOpen(Date()) }

    var stretch: Double { lock.lock(); defer { lock.unlock() }; return gate.stretch }

    func get(_ path: String, key: String? = nil) -> Answer? {
        let key = key ?? path
        guard open, let token = currentToken(), let url = URL(string: "https://api.github.com/" + path) else { return nil }
        var request = URLRequest(url: url)
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        lock.lock(); let held = cache[key]; lock.unlock()
        if let held { request.setValue(held.etag, forHTTPHeaderField: "If-None-Match") }
        line.wait()
        defer { line.signal() }
        let done = DispatchSemaphore(value: 0)
        var result: Answer?
        session.dataTask(with: request) { [self] data, response, _ in
            defer { done.signal() }
            guard let http = response as? HTTPURLResponse else { return }
            let headers = Dictionary(http.allHeaderFields.compactMap { k, v in (k as? String).map { ($0.lowercased(), "\(v)") } }, uniquingKeysWith: { a, _ in a })
            GitHubMeter.heard(path, status: http.statusCode, bytes: data?.count ?? 0, headers: headers)
            let limited = data.flatMap { String(data: $0, encoding: .utf8) }?.lowercased().contains("rate limit") ?? false
            lock.lock(); gate.heard(status: http.statusCode, headers: headers, limited: limited, now: Date()); lock.unlock()
            let poll = headers["x-poll-interval"].flatMap(TimeInterval.init)
            switch http.statusCode {
            case 304:
                if let held { result = Answer(data: held.data, changed: false, pollInterval: poll) }
            case 200:
                guard let data else { return }
                lock.lock()
                if let etag = headers["etag"] { cache[key] = (etag, data) } else { cache[key] = nil }
                lock.unlock()
                result = Answer(data: data, changed: true, pollInterval: poll)
            case 401:
                lock.lock(); self.token = nil; askedAt = Date(); lock.unlock()
            default: break
            }
        }.resume()
        done.wait()
        return result
    }

    func readLimits() {
        guard let a = get("rate_limit"), let o = try? JSONSerialization.jsonObject(with: a.data) as? [String: Any],
              let g = (o["resources"] as? [String: Any])?["graphql"] as? [String: Any],
              let remaining = g["remaining"] as? Int, let reset = g["reset"] as? Double else { return }
        lock.lock(); gate.heard(graphql: remaining, reset: Date(timeIntervalSince1970: reset)); lock.unlock()
    }

    static func ghToken() -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = ["gh", "auth", "token"]
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:" + (env["PATH"] ?? "")
        p.environment = env
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        let ended = DispatchSemaphore(value: 0)
        p.terminationHandler = { _ in ended.signal() }
        do { try p.run() } catch { return nil }
        if ended.wait(timeout: .now() + tokenWait) == .timedOut { p.terminate(); return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        return p.terminationStatus == 0 ? String(data: data, encoding: .utf8) : nil
    }

    private func currentToken() -> String? {
        guard asking.lock(before: Date().addingTimeInterval(GitHubHTTP.tokenWait + 1)) else { return nil }
        defer { asking.unlock() }
        lock.lock()
        if let token { lock.unlock(); return token }
        if Date().timeIntervalSince(askedAt) < 300 { lock.unlock(); return nil }
        askedAt = Date()
        lock.unlock()
        let t = tokenFrom()?.trimmingCharacters(in: .whitespacesAndNewlines)
        lock.lock(); token = (t?.isEmpty ?? true) ? nil : t; lock.unlock()
        return token
    }
}
