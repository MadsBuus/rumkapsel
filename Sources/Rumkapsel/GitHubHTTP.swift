import Foundation

final class GitHubHTTP {
    struct Answer {
        let data: Data
        let changed: Bool
    }

    private let lock = NSLock()
    private var token: String?
    private var askedToken = false
    private var askedAt = Date.distantPast
    private var cache: [String: (etag: String, data: Data)] = [:]
    private let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 15
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: c)
    }()
    private let tokenFrom: () -> String?

    init(token tokenFrom: @escaping () -> String?) { self.tokenFrom = tokenFrom }

    var hasToken: Bool { lock.lock(); defer { lock.unlock() }; return token != nil }

    func get(_ path: String) -> Answer? {
        guard let token = currentToken(), let url = URL(string: "https://api.github.com/" + path) else { return nil }
        var request = URLRequest(url: url)
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        lock.lock(); let held = cache[path]; lock.unlock()
        if let held { request.setValue(held.etag, forHTTPHeaderField: "If-None-Match") }
        let done = DispatchSemaphore(value: 0)
        var result: Answer?
        session.dataTask(with: request) { [self] data, response, _ in
            defer { done.signal() }
            guard let http = response as? HTTPURLResponse else { return }
            switch http.statusCode {
            case 304:
                if let held { result = Answer(data: held.data, changed: false) }
            case 200:
                guard let data else { return }
                if let etag = http.value(forHTTPHeaderField: "ETag") { lock.lock(); cache[path] = (etag, data); lock.unlock() }
                result = Answer(data: data, changed: true)
            case 401:
                lock.lock(); self.token = nil; askedToken = false; lock.unlock()
            default: break
            }
        }.resume()
        done.wait()
        return result
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
        do { try p.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return p.terminationStatus == 0 ? String(data: data, encoding: .utf8) : nil
    }

    private func currentToken() -> String? {
        lock.lock()
        if let token { lock.unlock(); return token }
        if askedToken, Date().timeIntervalSince(askedAt) < 300 { lock.unlock(); return nil }
        askedToken = true; askedAt = Date()
        lock.unlock()
        let t = tokenFrom()?.trimmingCharacters(in: .whitespacesAndNewlines)
        lock.lock(); token = (t?.isEmpty ?? true) ? nil : t; lock.unlock()
        return token
    }
}
