import Foundation

protocol Intake: AnyObject {
    var name: String { get }
    func checks() -> [Watch.Check]
    func reports() -> [Report]
}

final class Watch {
    struct Check {
        let key: String
        let detector: Detector
        let run: () -> Void
        init(_ key: String, _ detector: Detector, _ run: @escaping () -> Void) { self.key = key; self.detector = detector; self.run = run }
    }

    let http: GitHubHTTP
    private let lock = NSLock()
    private var detectors: [String: Detector] = [:]
    private var asking = Set<String>()
    private var ticker: DispatchSourceTimer?
    private var sources: [() -> [Check]] = []
    private let queue = DispatchQueue(label: "rumkapsel.watch", qos: .utility, attributes: .concurrent)
    private var isFront = false
    private var lastWork = Date.distantPast
    private var pinned: Pace?
    var trace: (String) -> Void = { _ in }

    init(http: GitHubHTTP) { self.http = http }

    func add(_ checks: @escaping () -> [Check]) {
        lock.lock(); sources.append(checks); lock.unlock()
    }

    func start() {
        lock.lock(); defer { lock.unlock() }
        guard ticker == nil else { return }
        let t = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "rumkapsel.watch.tick"))
        t.schedule(deadline: .now() + .milliseconds(Int.random(in: 0...1000)), repeating: 1)
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume()
        ticker = t
    }

    var front: Bool {
        get { lock.lock(); defer { lock.unlock() }; return isFront }
        set { lock.lock(); isFront = newValue; lock.unlock() }
    }
    var worked: Date {
        get { lock.lock(); defer { lock.unlock() }; return lastWork }
        set { lock.lock(); lastWork = newValue; lock.unlock() }
    }
    var pace: Pace {
        get { lock.lock(); defer { lock.unlock() }; return paceLocked(Date()) }
        set { lock.lock(); pinned = newValue; lock.unlock() }
    }
    private func paceLocked(_ now: Date) -> Pace { pinned ?? .of(front: isFront, worked: lastWork, now: now) }

    private func tick() {
        let now = Date()
        guard http.open else { return }
        lock.lock(); let all = sources; lock.unlock()
        let checks = all.flatMap { $0() }
        let stretch = http.stretch
        lock.lock()
        let pace = paceLocked(now)
        var due: [Check] = []
        for c in checks {
            var d = detectors[c.key] ?? c.detector
            if detectors[c.key] == nil { d.start(now, pace: pace, jitter: .random(in: 0...3)) }
            guard d.due(now, pace: pace, stretch: stretch), !asking.contains(c.key) else { detectors[c.key] = d; continue }
            d.asking(now)
            detectors[c.key] = d
            asking.insert(c.key)
            due.append(c)
        }
        lock.unlock()
        for c in due { queue.async { [self] in c.run(); lock.lock(); asking.remove(c.key); lock.unlock() } }
    }

    func ask(_ key: String, _ path: String, cache: String? = nil) -> GitHubHTTP.Answer? {
        let answer = http.get(path, key: cache)
        let failed = answer == nil && http.open
        tune(key) { if let answer { $0.heard(pollInterval: answer.pollInterval) } else if failed { $0.failed() } }
        if failed { trace("\(key): no answer, next try in \(Int(detector(key)?.backoff ?? 0))s") }
        return answer
    }

    func detector(_ key: String) -> Detector? { lock.lock(); defer { lock.unlock() }; return detectors[key] }

    func tune(_ key: String, _ change: (inout Detector) -> Void) {
        lock.lock(); defer { lock.unlock() }
        guard var d = detectors[key] else { return }
        change(&d)
        detectors[key] = d
    }

    func ring(repoRoot: String?) {
        let now = Date()
        lock.lock(); defer { lock.unlock() }
        for k in detectors.keys where repoRoot.map({ k.hasPrefix($0 + "#watch:") }) ?? true {
            detectors[k]?.ring()
            if k.hasSuffix("#watch:pulls") || k.hasSuffix("#watch:runs") { detectors[k]?.heat(for: 30, now) }
        }
        detectors["watch:board"]?.heat(for: 120, now)
    }
}
