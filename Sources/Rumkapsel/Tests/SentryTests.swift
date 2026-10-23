import Foundation

enum SentryTests {
    private static var failures = 0

    static func run() -> Never {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        func issue(_ id: String, age: TimeInterval, count: Int = 3, level: String = "error") -> SentryIssue {
            SentryIssue(id: id, title: "TypeError \(id)", level: level, count: count, firstSeen: now.addingTimeInterval(-age), lastSeen: now)
        }

        test("an issue reads from Sentry's API, the count a string and the dates with or without fractions") {
            let api: [String: Any] = ["id": "42", "title": "TypeError: x is undefined", "level": "error", "count": "37",
                                      "firstSeen": "2026-10-22T09:15:02.123456Z", "lastSeen": "2026-10-22T10:01:00Z", "permalink": "https://sentry.io/i/42/"]
            let i = SentryIssue(api: api)
            expect(i?.count == 37 && i?.title == "TypeError: x is undefined" && i?.link == "https://sentry.io/i/42/", "read: \(String(describing: i))")
            expect(i.map { $0.lastSeen.timeIntervalSince($0.firstSeen) > 2700 } == true, "both dates read")
            expect(SentryIssue(api: ["id": "1", "title": "no dates"]) == nil, "an issue without its dates is not one")
        }

        test("a repository's errors are calm, rising or spiking: the last hour against the hours before, and new issues count") {
            func steady(_ id: String, per hour: Int, last: Int) -> SentryIssue {
                SentryIssue(id: id, title: id, count: 100, firstSeen: now.addingTimeInterval(-86400 * 3), lastSeen: now, hourly: Array(repeating: hour, count: 23) + [last])
            }
            expect(Sentry.trend([], at: now).level == .calm, "nothing: calm")
            expect(Sentry.trend([steady("a", per: 10, last: 11)], at: now).level == .calm, "as usual: calm")
            expect(Sentry.trend([steady("a", per: 4, last: 12)], at: now).level == .rising, "three times the usual: rising")
            expect(Sentry.trend([steady("a", per: 3, last: 60)], at: now).level == .spiking, "twenty times the usual: spiking")
            expect(Sentry.trend([steady("a", per: 0, last: 6)], at: now).level == .rising, "a handful out of nothing rises, but is no spike")
            expect(Sentry.trend([issue("a", age: 600)], at: now).level == .rising, "a brand new issue: rising")
            expect(Sentry.trend([issue("a", age: 600, count: 1, level: "fatal")], at: now).level == .spiking, "a new fatal: spiking")
            let t = Sentry.trend([steady("a", per: 2, last: 5), steady("b", per: 1, last: 40)], at: now)
            expect(t.hourly.count == 24 && t.lastHour == 45 && t.worst?.id == "b", "the hours add up across issues, and the worst is the busiest last hour: \(t.lastHour) \(t.worst?.id ?? "-")")
        }

        test("a Sentry project is matched to the repository it shares the longest name start with, or to none, and staging is left out") {
            let repos = ["api-node-nest", "backend-api", "tattoodo-web", "app-ios"]
            expect(Sentry.guess(project: "api-node-production", repos: repos) == "api-node-nest", "api-node")
            expect(Sentry.guess(project: "backend-api-production", repos: repos) == "backend-api", "backend-api")
            expect(Sentry.guess(project: "api-node-staging", repos: repos) == nil, "a staging project lights no lamp unless chosen")
            expect(Sentry.guess(project: "tattoodo-web-node-express", repos: repos) == "tattoodo-web", "tattoodo-web")
            expect(Sentry.guess(project: "payments", repos: repos) == nil, "no likeness: none")
        }

        test("the station says so when a repository's errors climb a level, not on the first read and not while they hold") {
            let world = World(demo: true)
            world.clock = { now }
            func read(_ last: Int) -> [String] {
                let issue = SentryIssue(id: "a", title: "a", count: 100, firstSeen: now.addingTimeInterval(-86400), lastSeen: now, hourly: Array(repeating: 3, count: 23) + [last])
                return world.hear([.errors(repo: "web", project: "web-prod", issues: [issue])]).compactMap { e in
                    if case .errorsClimbed(let repo, let level, let n) = e { return "\(repo) \(level.words) \(n)" }
                    return nil
                }
            }
            expect(read(60).isEmpty, "the first read only says what is so")
            expect(world.errors(repo: "web")?.count == 1 && world.errors(repo: "api") == nil, "web's errors are known, api has no project")
            expect(read(3).isEmpty, "calming down is not news")
            expect(read(12) == ["web rising 12"], "rising: \(read(12))")
            expect(read(12).isEmpty, "and holding is not news either")
            expect(read(80) == ["web spiking 80"], "spiking")
        }

        say(failures == 0 ? "sentry: all passed" : "sentry: \(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }

    private static func test(_ name: String, _ body: () -> Void) {
        let before = failures
        body()
        say((failures == before ? "PASS  " : "FAIL  ") + name)
    }
    private static func expect(_ ok: Bool, _ what: String) {
        if !ok { failures += 1; say("      not so: \(what)") }
    }
    private static func say(_ text: String) { FileHandle.standardError.write((text + "\n").data(using: .utf8)!) }
}
