import Foundation

enum Pace: Int {
    case focused, active, idle

    static func of(front: Bool, worked: Date, now: Date) -> Pace {
        front ? .focused : now.timeIntervalSince(worked) < 600 ? .active : .idle
    }
}

struct Detector {
    static let longest: TimeInterval = 300

    let every: [TimeInterval]
    var hot: TimeInterval = 5
    var floor: TimeInterval = 0
    var backoff: TimeInterval = 0
    var asked = Date.distantPast
    var hotUntil = Date.distantPast
    var rung = false

    static let pulls = Detector(every: [5, 10, 60])
    static let runs = Detector(every: [30, 60, 120])
    static let feed = Detector(every: [60, 60, 180])
    static let board = Detector(every: [10, 20, 60])

    func wait(_ now: Date, pace: Pace, stretch: Double = 1) -> TimeInterval {
        if rung { return max(floor, backoff) }
        return max((now < hotUntil ? hot : every[pace.rawValue]) * stretch, floor, backoff)
    }

    func due(_ now: Date, pace: Pace, stretch: Double = 1) -> Bool { now.timeIntervalSince(asked) >= wait(now, pace: pace, stretch: stretch) }

    mutating func start(_ now: Date, pace: Pace, jitter: TimeInterval) { asked = now.addingTimeInterval(jitter - wait(now, pace: pace)) }

    mutating func asking(_ now: Date) { asked = now; rung = false }

    mutating func heard(pollInterval: TimeInterval?) {
        backoff = 0
        if let pollInterval { floor = pollInterval }
    }

    mutating func failed() { backoff = min(Detector.longest, max(10, backoff * 2)) }

    mutating func ring() { rung = true }

    mutating func heat(for seconds: TimeInterval, _ now: Date) { hotUntil = max(hotUntil, now.addingTimeInterval(seconds)) }

    mutating func cool() { hotUntil = .distantPast }
}

struct RateGate {
    static let reserve = 200
    static let longest: TimeInterval = 960

    var until = Date.distantPast
    var graphUntil = Date.distantPast
    var penalty: TimeInterval = 0
    var stretch: Double = 1

    func open(_ now: Date) -> Bool { now >= until }

    func ghOpen(_ now: Date) -> Bool { now >= until && now >= graphUntil }

    mutating func heard(status: Int, headers: [String: String], limited: Bool = false, now: Date,
                        jitter: TimeInterval = .random(in: 0...5)) {
        let reset = headers["x-ratelimit-reset"].flatMap(Double.init).map { Date(timeIntervalSince1970: $0) }
        let remaining = headers["x-ratelimit-remaining"].flatMap(Int.init)
        if let remaining { stretch = remaining < RateGate.reserve / 4 ? 8 : remaining < RateGate.reserve ? 4 : 1 }
        guard status == 403 || status == 429 else {
            if status < 400 { penalty = 0 }
            return
        }
        if let after = headers["retry-after"].flatMap(Double.init) {
            close(now.addingTimeInterval(after + jitter))
        } else if remaining == 0 {
            close((reset ?? now.addingTimeInterval(60)).addingTimeInterval(jitter))
        } else if status == 429 || limited {
            penalty = min(RateGate.longest, penalty == 0 ? 60 : penalty * 2)
            close(now.addingTimeInterval(penalty + jitter))
        }
    }

    mutating func heard(graphql remaining: Int, reset: Date) { graphUntil = remaining < RateGate.reserve ? reset : .distantPast }

    private mutating func close(_ at: Date) { until = max(until, at) }
}

struct FollowUps {
    static let after: TimeInterval = 15

    struct Pull: Hashable { let number: Int; let branch: String }

    struct Due: Equatable {
        var pulls: Set<Pull> = []
        var team = false
        var releasing = false
        var all = false
    }

    private var due: [String: Due] = [:]

    mutating func note(_ root: String, _ d: Due) -> Bool {
        let first = due[root] == nil
        var sum = due[root] ?? Due()
        sum.pulls.formUnion(d.pulls)
        sum.team = sum.team || d.team
        sum.releasing = sum.releasing || d.releasing
        sum.all = sum.all || d.all
        due[root] = sum
        return first
    }

    mutating func take(_ root: String) -> Due? { due.removeValue(forKey: root) }
}
