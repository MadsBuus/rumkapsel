import Foundation

enum RuleTests {
    private static var failures = 0
    private static let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private static let g = YardGeometry.classic
    private static let staged = RepoFacts(hasStaging: true, hasCleared: true)

    static func run() -> Never {
        test("a merged crate goes from its office to storage, by the walkway in its home band, said once") {
            var f = Facts()
            apply(&f, [.policy(repo: "web", staged), work("web", 5, .ready, office: true)])
            expect(f.crates[id("web", 5)]?.place == .office("task:web#5"), "packed in its office")
            let fx = apply(&f, [work("web", 5, .stored, office: true)])
            expect(f.crates[id("web", 5)]?.place == .waiting && column(f, "web", 5) == 6, "in storage, column 6: \(String(describing: f.crates[id("web", 5)]))")
            expect(f.homes == ["web": 3], "web's home is the walkway's band: \(f.homes)")
            expect(logs(fx) == ["web #5 to \(Zone.waiting.words)"], "said once: \(logs(fx))")
        }

        test("a first answer is history: placed quietly, nothing said") {
            var f = Facts()
            apply(&f, [.policy(repo: "web", staged)])
            let fx = apply(&f, [work("web", 7, .qa, quiet: true)])
            expect(f.crates[id("web", 7)]?.place == .testing && column(f, "web", 7) == 6, "on the testing rows by the walkway")
            expect(fx == [.quiet(.crate(id("web", 7)))], "quiet, no log: \(fx)")
        }

        test("a staging merge sends every waiting crate across in one line") {
            var f = stored("web", [1, 2, 3, 4])
            let fx = apply(&f, [.staging(repo: "web", .merged(900))] + [1, 2, 3, 4].map { work("web", $0, .qa) })
            expect([1, 2, 3, 4].allSatisfy { f.crates[id("web", $0)]?.place == .testing }, "all four on the testing rows")
            expect([1, 2, 3, 4].map { column(f, "web", $0) ?? -1 } == [6, 7, 14, 15], "in web's band: \([1, 2, 3, 4].map { column(f, "web", $0) })")
            expect(logs(fx).count == 1, "one line: \(logs(fx))")
            expect(f.staging["web"].map { $0.number == 900 && $0.merged && $0.mergedAt == t0 } == true, "the staging release is merged")
        }

        test("the board takes a crate back from testing to storage") {
            var f = stored("web", [1])
            apply(&f, [work("web", 1, .qa)])
            expect(f.crates[id("web", 1)]?.place == .testing, "across on QA")
            apply(&f, [work("web", 1, .stored)])
            expect(f.crates[id("web", 1)]?.place == .waiting && column(f, "web", 1) == 6, "back in storage in its band")
        }

        test("a tick on a buried crate re-columns only the crates above it, top first") {
            var f = Facts()
            apply(&f, [.policy(repo: "web", staged)])
            for n in 1...6 { apply(&f, [work("web", n, .qa, quiet: true)]) }
            expect((1...6).map { column(f, "web", $0) ?? -1 } == [6, 7, 14, 15, 6, 7], "floor, beside, in front, then on top: \((1...6).map { column(f, "web", $0) })")
            expect((1...6).map { level(f, "web", $0) ?? -1 } == [0, 0, 0, 0, 1, 1], "two on top")
            let before = f
            apply(&f, [work("web", 2, .cleared)])
            expect(f.crates[id("web", 2)]?.place == .cleared && column(f, "web", 2) == 6, "#2 to the cleared rows, same band")
            expect(column(f, "web", 6) == 14 && level(f, "web", 6) == 1, "#6 lifted off it onto #3: c\(column(f, "web", 6) ?? -1) L\(level(f, "web", 6) ?? -1)")
            for n in [1, 3, 4, 5] { expect(f.crates[id("web", n)] == before.crates[id("web", n)], "#\(n) untouched") }
        }

        test("without staging crates load from storage; ships on tags waits for the tag; shipped with no tag just goes") {
            var f = Facts()
            apply(&f, [.policy(repo: "ios", RepoFacts(shipsOnTag: true)), work("ios", 1, .stored, quiet: true), work("ios", 2, .stored, quiet: true)])
            apply(&f, [work("ios", 1, .cleared), work("ios", 2, .qa)])
            expect(f.crates[id("ios", 1)]?.place == .waiting && f.crates[id("ios", 2)]?.place == .waiting, "no testing rows: both wait in storage")
            expect(f.crates[id("ios", 1)]?.cleared == true && f.crates[id("ios", 2)]?.cleared == false, "#1 tested, #2 not")
            apply(&f, [.launched(repo: "ios", hotfix: nil)], at: t0 + 60)
            expect([1, 2].allSatisfy { released(f.crates[id("ios", $0)], "ios") }, "the tag takes both aboard")
            apply(&f, [work("ios", 1, .shipped), work("ios", 2, .shipped)], at: t0 + 70)
            expect([1, 2].allSatisfy { released(f.crates[id("ios", $0)], "ios") }, "shipped after the launch changes nothing")
            apply(&f, [work("ios", 3, .stored, quiet: true)])
            apply(&f, [work("ios", 3, .shipped)])
            expect(f.crates[id("ios", 3)] == nil, "shipped with no tag: gone")
            apply(&f, [.tick], at: t0 + 660)
            expect(f.crates.isEmpty && f.rockets.isEmpty, "the launched rocket's crates go with its tombstone: \(f.crates.keys.sorted())")

            var w = Facts()
            apply(&w, [.policy(repo: "web", staged), work("web", 1, .stored, quiet: true), work("web", 2, .qa, quiet: true), work("web", 3, .cleared, quiet: true)])
            apply(&w, [.launched(repo: "web", hotfix: nil)])
            expect(w.crates[id("web", 1)]?.place == .waiting, "with staging, storage stays behind")
            expect([2, 3].allSatisfy { released(w.crates[id("web", $0)], "web") }, "the testing and cleared rows go aboard")
        }

        test("closed unmerged: red at once, gone ten minutes later") {
            var f = stored("web", [1, 2])
            apply(&f, [work("web", 3, .ready, office: true)])
            apply(&f, [work("web", 3, .ready, office: true, closed: true), work("web", 1, .stored, closed: true)])
            expect(f.crates[id("web", 3)]?.closedAt == t0 && f.crates[id("web", 1)]?.closedAt == t0, "closed now")
            apply(&f, [.tick], at: t0 + 300)
            expect(f.crates[id("web", 3)] != nil && f.crates[id("web", 1)] != nil, "still there after five minutes")
            apply(&f, [.tick], at: t0 + 600)
            expect(f.crates[id("web", 3)] == nil && f.crates[id("web", 1)] == nil, "gone after ten")
            expect(column(f, "web", 2) == 7, "#2 stays where it stood")
        }

        test("a bot's crate drops into decon with the hatch; merged it goes to storage tested, closed it is ejected") {
            var f = Facts()
            apply(&f, [.policy(repo: "web", staged)])
            let fx = apply(&f, [.decon(repo: "web", open: [8, 7])])
            expect([7, 8].allSatisfy { f.crates[id("web", $0)]?.place == .decon && f.crates[id("web", $0)]?.alien == true }, "both in decon, alien")
            expect(fx.first == .hatch(repo: "web") && logs(fx).count == 2, "the hatch blinks, a line each: \(fx)")
            expect(column(f, "web", 7) == 0 && column(f, "web", 8) == 1, "side by side on the first tile")
            expect(apply(&f, [.decon(repo: "web", open: [7, 8])]).isEmpty, "the same open list again says nothing")
            apply(&f, [work("web", 7, .stored)])
            expect(f.crates[id("web", 7)]?.place == .waiting && f.crates[id("web", 7)]?.cleared == true, "merged: to storage, tested")
            let out = apply(&f, [.deconClosed(id("web", 8))])
            expect(f.crates[id("web", 8)] == nil && logs(out).count == 1, "closed: ejected, said: \(logs(out))")
        }

        test("a crate renumbered when its issue is learned keeps its place; renumbered onto one already there, it goes") {
            var f = stored("web", [1, 2, 900])
            let before = f.crates[id("web", 900)]
            let fx = apply(&f, [.renumbered(from: id("web", 900), to: id("web", 31))])
            let now = f.crates[id("web", 31)]
            expect(f.crates[id("web", 900)] == nil && now?.place == before?.place && now?.seq == before?.seq && now?.column == before?.column,
                   "same place, same spot: \(String(describing: now))")
            expect(fx == [.renamed(.crate(id("web", 900)), to: .crate(id("web", 31)))], "the picture is told: \(fx)")
            apply(&f, [.renumbered(from: id("web", 2), to: id("web", 1))])
            expect(f.crates[id("web", 2)] == nil && f.crates[id("web", 1)] != nil && f.crates.count == 2, "the other number already stands: the old one goes")
        }

        test("a home band holds in every zone, an overflow takes the nearest free band, a newcomer the first free one") {
            var f = Facts()
            apply(&f, [.policy(repo: "web", staged), .policy(repo: "api", staged)])
            apply(&f, [work("web", 1, .stored, quiet: true), work("web", 2, .qa, quiet: true), work("web", 3, .cleared, quiet: true)])
            expect((1...3).map { column(f, "web", $0) } == [6, 6, 6], "the same column in every zone")
            for n in 10..<23 { apply(&f, [work("web", n, .stored, quiet: true)]) }
            let bands = (10..<23).map { Layout.band(column(f, "web", $0) ?? -1) }
            expect(bands.prefix(11).allSatisfy { $0 == 3 } && bands.suffix(2) == [2, 2], "eleven more fill band 3, two spill next door: \(bands)")
            expect(tallest(f) <= 3, "nothing above three")
            apply(&f, [work("api", 1, .stored, quiet: true)])
            expect(f.homes == ["web": 3, "api": 1] && column(f, "api", 1) == 2, "api takes band 1, not web's spill: \(f.homes)")
        }

        test("a full zone leaves a crate columnless, counted, until room frees") {
            var f = Facts()
            apply(&f, [.policy(repo: "web", staged)])
            for n in 1...49 { apply(&f, [work("web", n, .stored, quiet: true)]) }
            expect(f.count(.waiting) == 49 && column(f, "web", 49) == nil, "the forty-ninth has no column")
            expect(tallest(f) == 3, "forty-eight stand three high")
            apply(&f, [work("web", 1, .qa)])
            expect(column(f, "web", 49) == 6 && level(f, "web", 49) == 2, "it takes the room #1 left: c\(column(f, "web", 49) ?? -1)")
            expect(tallest(f) <= 3, "still nothing above three")
        }

        test("the old yard mess: homes never move, nothing above three, an arrival keeps off the spill, the strays go home") {
            var f = Facts()
            for repo in ["ios", "android", "web", "api"] { apply(&f, [.policy(repo: repo, staged)]) }
            apply(&f, [work("ios", 1, .stored, quiet: true)])
            apply(&f, [work("android", 2, .stored, quiet: true)])
            for n in 100..<115 { apply(&f, [work("web", n, .stored, quiet: true)]) }
            expect(f.homes == ["ios": 3, "android": 1, "web": 2], "homes in band order: \(f.homes)")
            let strays = (100..<115).filter { Layout.band(column(f, "web", $0) ?? -1) != 2 }
            expect(strays == [112, 113, 114] && strays.allSatisfy { Layout.band(column(f, "web", $0) ?? -1) == 0 }, "web spills three into band 0: \(strays)")
            let homes = f.homes
            for n in 200..<206 {
                apply(&f, [work("api", n, .stored, quiet: true)])
                expect(homes.allSatisfy { f.homes[$0.key] == $0.value } && tallest(f) <= 3, "api #\(n): homes \(f.homes), tallest \(tallest(f))")
            }
            expect(f.homes["api"] == 0, "api's home is the free band, where the spill stands")
            expect((200..<203).allSatisfy { column(f, "api", $0) == 9 }, "it piles its pure column first: \((200..<203).map { column(f, "api", $0) })")
            expect(column(f, "api", 203) == column(f, "web", 112) && level(f, "api", 203) == 1, "then it stands on the spill")
            var arrivals = f
            Layout.relayout(&arrivals, yard: g)
            expect(arrivals == f, "nothing has left: a relayout changes nothing")
            apply(&f, [108, 109, 110].map { work("web", $0, .qa) })
            expect(Layout.band(column(f, "web", 112) ?? -1) == 2, "room at home: the first stray goes home")
            expect(level(f, "api", 203) == 0, "and api #203 drops a level")
            expect(Layout.band(column(f, "web", 113) ?? -1) == 0, "one stray an apply")
            apply(&f, [.tick], at: t0 + 1)
            apply(&f, [.tick], at: t0 + 2)
            expect((100..<115).compactMap { column(f, "web", $0) }.allSatisfy { Layout.band($0) == 2 }, "every web crate is home")
            expect(f.homes == homes.merging(["api": 0]) { a, _ in a } && tallest(f) <= 3, "homes as they were, nothing above three: \(f.homes)")
        }

        test("with nothing left since, a relayout gives the same yard") {
            for seed in [UInt64(1), 2] {
                var step = 0
                let run = timeline(seed: seed, steps: 220, departures: false) { _, f in
                    step += 1
                    guard step % 110 == 0 else { return }
                    var r = f
                    Layout.relayout(&r, yard: g)
                    expect(r == f, "seed \(seed), step \(step): relayout moved something")
                }
                var r = run.facts
                Layout.relayout(&r, yard: g)
                expect(r == run.facts, "seed \(seed): relayout(f) == f over \(run.facts.crates.count) crates")
                expect(run.facts.crates.values.contains { $0.onRow && $0.column == nil }, "seed \(seed): the yard filled up enough to leave one columnless")
            }
        }

        test("random timelines: never above three, no shared spot, every stack from the floor, homes stay while a repo has row crates") {
            for seed in [UInt64(11), 12, 13] {
                var problems: [String] = []
                _ = timeline(seed: seed, steps: 400, departures: true) { before, f in problems += invariants(before, f) }
                expect(problems.isEmpty, "seed \(seed): \(problems.count) problems, first: \(problems.first ?? "")")
            }
        }

        test("the same events twice give the same facts, bit for bit") {
            let run = timeline(seed: 7, steps: 400, departures: true) { _, _ in }
            var a = Facts(), b = Facts()
            var fa: [Effect] = [], fb: [Effect] = []
            for (t, events) in run.events { fa += apply(&a, events, at: t) }
            for (t, events) in run.events { fb += apply(&b, events, at: t) }
            expect(a == b && a == run.facts, "same facts")
            expect(fa == fb, "same effects")
        }

        test("an old ledger from a real save becomes facts: every crate placed, none above three") {
            guard let old = try? JSONDecoder().decode(LegacyLedger.self, from: Data(realLedger.utf8)) else { return expect(false, "the save decodes") }
            let f = Facts.migrate(old, yard: g)
            expect(f.crates.count == 35, "all 35 crates came over: \(f.crates.count)")
            expect(f.crates.values.allSatisfy { $0.column != nil }, "every one has a column")
            expect(tallest(f) <= 3, "the old fourth level is gone: tallest \(tallest(f))")
            expect(f.crates[id("tattoodo-web", 14053)]?.place == .testing, "wanted on the deck, untested: testing")
            expect(f.count(.decon) == 8 && f.count(.cleared) == 21 && f.count(.testing) == 4 && f.count(.waiting) == 2, "zones \(Zone.allCases.map { "\($0): \(f.count($0))" })")
            let web = f.crates.values.filter { $0.zone == .cleared && $0.id.repo == "tattoodo-web" }.sorted { $0.seq < $1.seq }
            expect(web.prefix(12).allSatisfy { Layout.band($0.column!) == f.homes["tattoodo-web"] }, "web's first twelve tested stand at home")
            var r = f
            Layout.relayout(&r, yard: g)
            expect(r == f, "migrated facts are already laid out")
        }

        test("the source's first full answer sweeps the rows of what it no longer has, quietly, and nothing else") {
            var f = stored("web", [1, 2, 3, 4, 5, 6])
            apply(&f, [work("web", 9, .ready, office: true), .decon(repo: "web", open: [40])])
            let fx = apply(&f, [.sweep(repo: "web", keep: [1, 3, 5, 6])])
            expect(fx == [.quiet(.crate(id("web", 4))), .quiet(.crate(id("web", 2)))], "no shrinking: the picture snaps: \(fx)")
            expect(Set(f.crates.keys) == Set([1, 3, 5, 6, 9, 40].map { id("web", $0) }), "#2 and #4 gone, the office and decon untouched: \(f.crates.keys.sorted())")
            expect(tallest(f) <= 3 && f.homes["web"] == 3, "still a good yard at home")
            let before = f
            apply(&f, [.sweep(repo: "ios", keep: [])])
            expect(f == before, "another repository's answer touches nothing of web")
        }

        test("each release launch is a rocket of its own: the second takes only what came after the first") {
            var f = stored("web", [1])
            apply(&f, [work("web", 1, .qa), .launched(repo: "web", hotfix: nil)])
            apply(&f, [work("web", 2, .stored, quiet: true), work("web", 2, .qa), .launched(repo: "web", hotfix: nil)], at: t0 + 30)
            guard case .aboard(let first)? = f.crates[id("web", 1)]?.place, case .aboard(let second)? = f.crates[id("web", 2)]?.place else {
                return expect(false, "both aboard")
            }
            expect(first != second && f.rockets.count == 2, "two rockets: \(first), \(second)")
        }

        test("a first answer is never news: decon arrivals and a first policy place crates quietly") {
            var f = Facts()
            let fx = apply(&f, [.decon(repo: "web", open: [7], quiet: true)])
            expect(f.crates[id("web", 7)]?.zone == .decon && fx == [.quiet(.crate(id("web", 7)))], "in decon, no hatch, no line: \(fx)")
            var g = Facts()
            apply(&g, [work("web", 3, .qa, quiet: true)])
            let first = apply(&g, [.policy(repo: "web", staged)])
            expect(g.crates[id("web", 3)]?.zone == .testing && first == [.quiet(.crate(id("web", 3)))], "a first policy re-places quietly: \(first)")
        }

        test("a crate leaving from under a pile keeps the pile's order when there is nowhere else to go") {
            var f = Facts()
            apply(&f, [.policy(repo: "web", staged)])
            for n in 1...12 { apply(&f, [work("web", n, .stored, quiet: true)]) }
            for (k, repo) in ["a", "b", "c"].enumerated() { apply(&f, [.policy(repo: repo, staged)] + (0..<12).map { work(repo, 100 * (k + 1) + $0, .stored, quiet: true) }) }
            let column = column(f, "web", 1)
            let above = f.crates.values.filter { $0.zone == .waiting && $0.column == column && $0.id != id("web", 1) }.sorted { $0.seq < $1.seq }.map(\.id)
            apply(&f, [work("web", 1, .qa)])
            let after = f.crates.values.filter { $0.zone == .waiting && $0.column == column }.sorted { $0.seq < $1.seq }.map(\.id)
            expect(above.count == 2 && after == above, "the two above stay in order: \(above) then \(after)")
        }

        test("aboard a launched rocket, a later word from the source does not bring a crate back to the rows") {
            var f = stored("web", [1])
            apply(&f, [work("web", 1, .qa), .launched(repo: "web", hotfix: nil)])
            apply(&f, [work("web", 1, .qa), work("web", 1, .stored)], at: t0 + 30)
            expect(released(f.crates[id("web", 1)], "web"), "still aboard: \(String(describing: f.crates[id("web", 1)]?.place))")
        }

        test("an office opens by shuttle, its crate packs in it, a rename keeps the crate, and its going takes the crate along") {
            var f = Facts()
            let opened = apply(&f, [.policy(repo: "web", staged), .office(.opened("task:web#5", repo: "web", via: .shuttle(for: "s")))])
            expect(f.offices["task:web#5"]?.via == .shuttle(for: "s") && opened.isEmpty, "known, not news to snap: \(opened)")
            apply(&f, [work("web", 5, .ready, office: true), .office(.status("task:web#5", crate: id("web", 5), merged: false, closedAt: nil))])
            let fx = apply(&f, [.office(.renamed(from: "task:web#5", to: "task:web#5b"))])
            expect(f.offices["task:web#5"] == nil && f.offices["task:web#5b"]?.crate == id("web", 5), "the office and its crate under the new key: \(f.offices.keys.sorted())")
            expect(f.crates[id("web", 5)]?.place == .office("task:web#5b"), "the crate stands in the renamed office")
            expect(fx == [.renamed(.office("task:web#5"), to: .office("task:web#5b"))], "the picture re-keys it: \(fx)")
            let quiet = apply(&f, [.office(.opened("task:web#9", repo: "web", via: .appear))])
            expect(quiet == [.quiet(.office("task:web#9"))], "a first answer appears quietly: \(quiet)")
            apply(&f, [.office(.gone("task:web#5b"))])
            expect(f.offices["task:web#5b"] == nil && f.crates[id("web", 5)] == nil, "gone, and no crate left in an office that is not there")
            let encoded = try? JSONEncoder().encode(f)
            let back = encoded.flatMap { try? JSONDecoder().decode(Facts.self, from: $0) }
            expect(back?.offices["task:web#9"]?.via == .appear && back?.offices.count == 1, "saved without how it came")
        }

        test("a rename the facts already hold under the new key still takes the crate along, and the old key's going drops nothing") {
            var f = Facts()
            apply(&f, [.office(.opened("task:web#5", repo: "web", via: .appear)), .office(.opened("task:web#5b", repo: "web", via: .appear)),
                       .policy(repo: "web", staged), work("web", 5, .ready, office: true)])
            apply(&f, [.office(.renamed(from: "task:web#5", to: "task:web#5b"))])
            expect(f.crates[id("web", 5)]?.place == .office("task:web#5b"), "the crate moved to the new key: \(String(describing: f.crates[id("web", 5)]?.place))")
            apply(&f, [.office(.gone("task:web#5"))])
            expect(f.crates[id("web", 5)] != nil && f.offices.keys.sorted() == ["task:web#5b"], "nothing dropped: \(f.offices.keys.sorted())")
            var g = Facts()
            apply(&g, [.policy(repo: "web", staged), work("web", 6, .ready, office: true)])
            apply(&g, [.office(.renamed(from: "task:web#6", to: "task:web#6b"))])
            expect(g.crates[id("web", 6)]?.place == .office("task:web#6b"), "with no office fact, the crate still follows the rename")
        }

        test("an office ends on its facts: merged and not mine at once, mine and a neighbour's stay, closed after ten minutes") {
            var o = OfficeFact(key: "task:web#5", repo: "web")
            expect(Rules.officeEnds(o, now: t0, mine: false, lan: false) == nil, "open: stays")
            o.merged = true
            expect(Rules.officeEnds(o, now: t0, mine: false, lan: false) == "merged", "merged and not mine: ends at once")
            expect(Rules.officeEnds(o, now: t0, mine: true, lan: false) == nil, "mine: stays")
            expect(Rules.officeEnds(o, now: t0, mine: false, lan: true) == nil, "a neighbour's on the LAN: stays")
            o.merged = false
            o.closedAt = t0
            expect(Rules.officeEnds(o, now: t0 + 540, mine: false, lan: false) == nil, "closed nine minutes: stays")
            expect(Rules.officeEnds(o, now: t0 + 660, mine: false, lan: false) == "closed, not merged", "closed past ten minutes: ends")
            expect(Rules.officeEnds(o, now: t0 + 660, mine: true, lan: false) == nil, "closed but mine: stays")
            var f = Facts()
            apply(&f, [.office(.opened("task:web#5", repo: "web", via: .appear)),
                       .office(.status("task:web#5", crate: id("web", 5), merged: false, closedAt: t0))])
            expect(f.offices["task:web#5"]?.closedAt == t0 && f.offices["task:web#5"]?.crate == id("web", 5), "the status is the source's word")
        }

        test("a production release opens untested: the rocket docks, not go; tested, it is go; closed, the tip stands up again") {
            var f = stored("web", [1, 2])
            apply(&f, [work("web", 1, .qa), work("web", 2, .qa)])
            let fx = apply(&f, [.release(repo: "web", production: true, label: "rocket:x|web · release")])
            guard let r = f.rockets.values.first(where: { $0.repo == "web" }) else { return expect(false, "a rocket for web") }
            expect(r.kind == .release && r.docked && !r.go && r.slot == 0 && !r.launched, "docked on pad 0, held: \(r)")
            expect(logs(fx) == ["web \(Words.current.standingBy)"], "said once: \(logs(fx))")
            let tested = apply(&f, [work("web", 1, .cleared), work("web", 2, .cleared)])
            expect(f.rockets[r.id]?.go == true, "everything it ships is tested: go")
            expect(logs(tested).contains("web \(Words.current.steaming), waiting for the release to merge"), "said: \(logs(tested))")
            apply(&f, [.release(repo: "web", production: nil, label: "rocket:x|web · 2 crates waiting for a release")])
            expect(f.rockets[r.id].map { !$0.docked && !$0.go && $0.slot == 0 } == true, "closed unmerged: the same rocket stands on its pad, not go without its kick stage")
            var q = stored("web", [1])
            apply(&q, [work("web", 1, .qa)])
            let quiet = apply(&q, [.release(repo: "web", production: true, label: "", quiet: true)])
            expect(quiet == q.rockets.keys.map { .quiet(.rocket($0)) }, "a first answer is history: \(quiet)")
        }

        test("a release merged: what it ships goes aboard, the rocket is a tombstone, and a shipped word after changes nothing") {
            var f = stored("web", [1, 2, 3])
            apply(&f, [work("web", 2, .qa), work("web", 3, .cleared), .release(repo: "web", production: true, label: "")])
            guard let rocket = f.rockets.keys.first else { return expect(false, "a rocket") }
            let fx = apply(&f, [.launched(repo: "web")], at: t0 + 60)
            expect(f.rockets[rocket]?.launchedAt == t0 + 60, "the standing rocket launched: \(String(describing: f.rockets[rocket]))")
            expect([2, 3].allSatisfy { f.crates[id("web", $0)]?.place == .aboard(rocket) }, "the testing and cleared rows aboard it")
            expect(f.crates[id("web", 1)]?.place == .waiting, "storage stays behind")
            expect(logs(fx) == ["web: release merged, 2 \(Words.current.crates) \(Words.current.aboard)"], "said what happened: \(logs(fx))")
            let before = f
            apply(&f, [work("web", 2, .shipped), work("web", 3, .shipped), .release(repo: "web", production: nil, label: "")], at: t0 + 70)
            expect(f.crates.mapValues(\.place) == before.crates.mapValues(\.place) && f.rockets == before.rockets, "shipped after the launch changes nothing, and nothing stands up for storage")
            apply(&f, [.tick], at: t0 + 660)
            expect(f.rockets.isEmpty && f.crates.keys.sorted() == [id("web", 1)], "the tombstone goes with its crates: \(f.crates.keys.sorted())")
        }

        test("a repository that ships on merge: each merge is a launched rocket of its own with its crate aboard, and nothing stands") {
            var f = Facts()
            apply(&f, [.policy(repo: "ios", RepoFacts(shipsOnMerge: true, shipsAtOnce: true)), work("ios", 1, .ready, office: true), work("ios", 2, .ready, office: true)])
            let fx = apply(&f, [work("ios", 1, .stored, office: true)])
            apply(&f, [work("ios", 2, .stored, office: true), .release(repo: "ios", production: nil, label: "")], at: t0 + 5)
            guard case .aboard(let a)? = f.crates[id("ios", 1)]?.place, case .aboard(let b)? = f.crates[id("ios", 2)]?.place else {
                return expect(false, "both aboard: \(f.crates.values.map(\.place))")
            }
            expect(a != b && [a, b].allSatisfy { f.rockets[$0].map { $0.kind == .merge && $0.launched && $0.slot != nil } == true }, "two merge rockets on pads: \(f.rockets)")
            expect(f.rockets.count == 2, "no release rocket stands for a repository that ships at once")
            expect(logs(fx) == ["ios: #1 merged, 1 \(Words.current.crate) \(Words.current.aboard)"], "said: \(logs(fx))")
        }

        test("a hotfix: its own rocket and pad beside the release, which keeps its cargo when the hotfix goes up") {
            var f = stored("web", [1, 2])
            apply(&f, [work("web", 1, .qa), work("web", 2, .qa), .release(repo: "web", production: true, label: ""), work("web", 9, .ready, office: true)])
            let fx = apply(&f, [.hotfixes(repo: "web", open: [9: "rocket:x|web · hotfix #9"])])
            guard let release = f.rockets.values.first(where: { $0.kind == .release }), let hot = f.rockets["web|hotfix#9"] else { return expect(false, "two rockets: \(f.rockets)") }
            expect(hot.docked && !hot.go && hot.slot != nil && hot.slot != release.slot, "the express rocket docked on a pad of its own: \(hot)")
            expect(logs(fx) == ["web \(Words.current.standingBy)"], "said: \(logs(fx))")
            apply(&f, [.launched(repo: "web", hotfix: 9, crates: [9]), work("web", 9, .stored, office: true), work("web", 9, .shipped, office: true),
                       .hotfixes(repo: "web", open: [:])], at: t0 + 30)
            expect(f.crates[id("web", 9)]?.place == .aboard(hot.id) && f.rockets[hot.id]?.launched == true, "#9 aboard the launched express rocket")
            expect([1, 2].allSatisfy { f.crates[id("web", $0)]?.zone == .testing } && f.rockets[release.id] == release, "the release rocket and its cargo untouched")
            apply(&f, [.hotfixes(repo: "web", open: [10: ""])])
            apply(&f, [.hotfixes(repo: "web", open: [:])])
            expect(f.rockets["web|hotfix#10"] == nil && f.rockets[hot.id] != nil, "a hotfix closed unmerged takes its rocket away; a launched one stays its time")
        }

        test("pads: an urgent rocket takes the pad of an idle one, and every other rocket keeps its own") {
            var f = Facts()
            let repos = (0..<g.pads).map { "r\($0)" }
            for r in repos { apply(&f, [.policy(repo: r, RepoFacts()), work(r, 1, .stored, quiet: true), .release(repo: r, production: nil, label: r)]) }
            let before = Dictionary(uniqueKeysWithValues: f.rockets.values.map { ($0.id, $0.slot) })
            expect(g.pads >= 2 && Set(before.values.compactMap { $0 }).count == g.pads, "every pad taken: \(before)")
            apply(&f, [.policy(repo: "hot", RepoFacts()), .hotfixes(repo: "hot", open: [7: ""])])
            let hot = f.rockets["hot|hotfix#7"]?.slot
            let evicted = f.rockets.values.filter { $0.slot == nil }.map(\.repo)
            expect(hot != nil && evicted == [repos.last!], "the hotfix took the last idle rocket's pad: \(evicted)")
            expect(f.rockets.values.filter { $0.repo != repos.last! && $0.repo != "hot" }.allSatisfy { before[$0.id] == $0.slot }, "nobody else moved")
            apply(&f, [.release(repo: repos[0], production: true, label: ""), work(repos[1], 2, .stored)])
            expect(f.rockets.values.allSatisfy { $0.repo == repos.last! || $0.repo == "hot" || before[$0.id] == $0.slot } && f.rockets["hot|hotfix#7"]?.slot == hot,
                   "docking and new cargo move no rocket")
            apply(&f, [.hotfixes(repo: "hot", open: [:])])
            expect(f.rockets.values.first { $0.repo == repos.last! }?.slot == hot, "the hotfix closed: the idle rocket gets a pad again")
        }

        test("shipped words in one pass are one launch; nothing aboard, nothing goes up") {
            var f = Facts()
            apply(&f, [.policy(repo: "ios", RepoFacts()), work("ios", 1, .stored, quiet: true), work("ios", 2, .stored, quiet: true), work("ios", 3, .stored, quiet: true),
                       .release(repo: "ios", production: nil, label: "")])
            let events = FactFeed.together([.launched(repo: "ios", crates: [1]), work("ios", 1, .shipped), .launched(repo: "ios", crates: [2]), work("ios", 2, .shipped)])
            let fx = apply(&f, events, at: t0 + 10)
            let launched = f.rockets.values.filter(\.launched)
            expect(launched.count == 1 && f.aboard(launched[0].id).map(\.id.number) == [1, 2], "one rocket with #1 and #2: \(f.rockets)")
            expect(logs(fx).filter { $0.contains("shipped") } == ["ios: #1, #2 shipped, 2 \(Words.current.crates) \(Words.current.aboard)"], "said once: \(logs(fx))")
            apply(&f, [.launched(repo: "ios", crates: [2])], at: t0 + 10)
            expect(f.rockets.values.filter(\.launched).count == 1, "a late word in the same moment joins the same rocket")
            let standing = f.rockets.values.filter { !$0.launched }
            apply(&f, [.launched(repo: "ios", crates: [1, 9])], at: t0 + 20)
            expect(f.rockets.values.filter { !$0.launched } == standing, "crates already aboard or unknown: the standing rocket stays put")
        }

        test("pads: a fresh launch keeps its pad over a standing rocket, then gives it up once its flight is done") {
            var f = Facts()
            let repos = (0..<g.pads).map { "r\($0)" }
            for r in repos { apply(&f, [.policy(repo: r, RepoFacts()), work(r, 1, .stored, quiet: true), .release(repo: r, production: nil, label: r)]) }
            apply(&f, [.launched(repo: repos[0])], at: t0 + 1)
            guard let flying = f.rockets.values.first(where: \.launched) else { return expect(false, "launched") }
            apply(&f, [.policy(repo: "new", RepoFacts()), work("new", 1, .stored, quiet: true), .release(repo: "new", production: nil, label: "")], at: t0 + 2)
            let waiting = f.rockets.values.first { $0.repo == "new" }
            expect(f.rockets[flying.id]?.slot != nil && waiting?.slot == nil, "the launch keeps its pad, the newcomer waits")
            apply(&f, [.tick], at: t0 + 1 + Rules.flightWindow)
            expect(f.rockets[flying.id]?.slot == nil && f.rockets[waiting?.id ?? ""]?.slot == flying.slot, "after the flight the pad goes to the one waiting")
        }

        test("a staging batch settles: never heard of, it is dropped after a while; a deploy with no batch is not kept") {
            var f = Facts()
            apply(&f, [.staging(repo: "web", .opened(7)), .staging(repo: "web", .merged(7))])
            apply(&f, [.tick], at: t0 + Deployments.findWithin - 1)
            expect(f.staging["web"]?.merged == true, "a merged batch waits for its deploy")
            apply(&f, [.tick], at: t0 + Deployments.findWithin + 1)
            expect(f.staging["web"] == nil, "no deploy heard: dropped")
            apply(&f, [.staging(repo: "api", .deploy(.running(since: t0, usual: 60)))], at: t0)
            expect(f.staging["api"]?.underway == true, "a deploy with no batch welds")
            apply(&f, [.staging(repo: "api", .deploy(.live))], at: t0 + 60)
            apply(&f, [.tick], at: t0 + 200)
            expect(f.staging["api"] == nil, "and is gone once live")
        }

        if failures > 0 { print("rules: \(failures) failed"); exit(1) }
        print("rules: all passed")
        exit(0)
    }

    private static func id(_ repo: String, _ n: Int) -> CrateID { CrateID(repo: repo, number: n) }

    private static func released(_ c: CrateFact?, _ repo: String) -> Bool {
        if case .aboard(let rocket)? = c?.place { return rocket.hasPrefix(repo + "|release#") }
        return false
    }

    private static func work(_ repo: String, _ n: Int, _ stage: Stage, office: Bool = false, quiet: Bool = false, closed: Bool = false) -> Event {
        .work(WorkNews(crate: id(repo, n), office: office ? "task:\(repo)#\(n)" : nil, stage: stage, closed: closed, quiet: quiet))
    }

    @discardableResult
    private static func apply(_ f: inout Facts, _ events: [Event], at t: Date = t0) -> [Effect] { Rules.apply(events, at: t, to: &f, yard: g) }

    private static func logs(_ fx: [Effect]) -> [String] { fx.compactMap { if case .log(let s) = $0 { return s }; return nil } }
    private static func column(_ f: Facts, _ repo: String, _ n: Int) -> Int? { f.crates[id(repo, n)]?.column }
    private static func level(_ f: Facts, _ repo: String, _ n: Int) -> Int? { Layout.spots(f, g)[id(repo, n)]?.level }

    private static func stored(_ repo: String, _ numbers: [Int]) -> Facts {
        var f = Facts()
        apply(&f, [.policy(repo: repo, staged)])
        for n in numbers { apply(&f, [work(repo, n, .stored, quiet: true)]) }
        return f
    }

    private static func tallest(_ f: Facts) -> Int {
        Dictionary(grouping: f.crates.values.filter { $0.onRow && $0.column != nil }) { "\($0.zone!)|\($0.column!)" }.values.map(\.count).max() ?? 0
    }

    private static func invariants(_ before: Facts, _ f: Facts) -> [String] {
        var out: [String] = []
        let spots = Layout.spots(f, g)
        for zone in Zone.allCases {
            let here = f.crates.values.filter { $0.zone == zone }
            let stacks = Dictionary(grouping: here.filter { $0.column != nil }) { $0.column! }
            let (high, columns) = zone.isRow ? (3, 16) : (12, g.deconColumns)
            for (column, stack) in stacks {
                if stack.count > high || !(0..<columns).contains(column) { out.append("\(zone) c\(column) holds \(stack.count)") }
                let levels = stack.compactMap { spots[$0.id]?.level }.sorted()
                if levels != Array(0..<stack.count) { out.append("\(zone) c\(column) levels \(levels)") }
            }
            if here.contains(where: { $0.column == nil }) {
                let full = zone.isRow ? (0..<16).allSatisfy { stacks[$0]?.count == high } : stacks.values.map(\.count).reduce(0, +) >= 12
                if !full { out.append("\(zone) has a columnless crate beside room") }
            }
        }
        if Set(spots.values.map { SIMD3($0.column, $0.level, Zone.allCases.firstIndex(of: $0.zone)!) }).count != spots.count { out.append("two crates share a spot") }
        if Set(spots.values.map { SIMD3<Int>(($0.pos * 1000).rounded(.toNearestOrEven)) }).count != spots.count { out.append("two crates share a position") }
        let onRows = Set(f.crates.values.filter(\.onRow).map(\.id.repo))
        for repo in onRows where f.homes[repo] == nil { out.append("\(repo) has row crates and no home") }
        for repo in f.homes.keys where !onRows.contains(repo) { out.append("\(repo) keeps a home with no row crates") }
        for (repo, home) in before.homes where before.rowCrates(of: repo) > 0 && f.rowCrates(of: repo) > 0 && f.homes[repo] != home {
            out.append("\(repo) moved home \(home) → \(f.homes[repo].map(String.init) ?? "none")")
        }
        return out
    }

    private struct Dice {
        var state: UInt64
        mutating func roll(_ n: Int) -> Int {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return Int((z ^ (z >> 31)) % UInt64(max(n, 1)))
        }
    }

    private static let repos: [(String, RepoFacts)] = [
        ("web", staged), ("api", staged), ("ios", RepoFacts(shipsOnTag: true)), ("android", staged), ("bot", RepoFacts()),
    ]

    private static func timeline(seed: UInt64, steps: Int, departures: Bool,
                                 each: (Facts, Facts) -> Void) -> (facts: Facts, events: [(Date, [Event])]) {
        var dice = Dice(state: seed)
        var f = Facts()
        var t = t0
        var next = 1
        var out: [(Date, [Event])] = [(t, repos.map { .policy(repo: $0.0, $0.1) })]
        apply(&f, out[0].1, at: t)
        func any(_ keep: (CrateFact) -> Bool) -> CrateFact? {
            let pool = f.crates.values.filter(keep).sorted { $0.id < $1.id }
            return pool.isEmpty ? nil : pool[dice.roll(pool.count)]
        }
        func news(_ c: CrateFact, _ stage: Stage, closed: Bool = false) -> Event {
            var office: String?
            if case .office(let key) = c.place { office = key }
            return .work(WorkNews(crate: c.id, office: office, stage: stage, closed: closed))
        }
        for _ in 0..<steps {
            let repo = repos[dice.roll(repos.count)].0
            var events: [Event] = []
            let ops = departures ? [0, 1, 1, 1, 1, 2, 2, 2, 3, 4, 4, 5, 5, 6, 7, 8, 9, 10, 11, 12, 13] : [0, 1, 2, 3]
            switch ops[dice.roll(ops.count)] {
            case 0:
                events = [work(repo, next, .ready, office: true)]; next += 1
            case 1:
                events = [work(repo, next, [.stored, .qa, .cleared][dice.roll(3)], quiet: true)]; next += 1
            case 2:
                if let c = any({ if case .office = $0.place { return true }; return false }) { events = [news(c, .stored)] }
            case 3:
                events = [.decon(repo: repo, open: Array(next..<next + 1 + dice.roll(departures ? 2 : 1)))]; next += 2
            case 4:
                if let c = any({ $0.zone == .waiting && $0.stage != nil }) { events = [news(c, .qa)] }
            case 5:
                if let c = any({ $0.zone == .testing }) { events = [news(c, .cleared)] }
            case 6:
                if let c = any({ $0.zone == .testing }) { events = [news(c, .stored)] }
            case 7:
                if let c = any({ $0.stage != nil && $0.closedAt == nil }), let stage = c.stage { events = [news(c, stage, closed: true)] }
            case 8:
                if let c = any({ ($0.zone == .waiting || $0.zone == .cleared) && $0.stage != nil }) { events = [news(c, .shipped)] }
            case 9:
                events = [.launched(repo: repo, hotfix: nil)]
            case 10:
                if let c = any({ $0.zone == .decon }) { events = [.work(WorkNews(crate: c.id, stage: .stored))] }
            case 11:
                if let c = any({ $0.zone == .decon }) { events = [.deconClosed(c.id)] }
            case 12:
                t += Double(60 + dice.roll(840)); events = [.tick]
            default:
                let waiting = f.crates.values.filter { $0.id.repo == repo && $0.zone == .waiting && $0.stage != nil }.sorted { $0.id < $1.id }
                events = [.staging(repo: repo, .merged(next))] + waiting.map { news($0, .qa) }; next += 1
            }
            guard !events.isEmpty else { continue }
            let before = f
            apply(&f, events, at: t)
            out.append((t, events))
            each(before, f)
        }
        return (f, out)
    }

    private static func test(_ name: String, _ body: () -> Void) {
        let before = failures
        body()
        print(failures == before ? "PASS  \(name)" : "FAIL  \(name)")
    }

    private static func expect(_ ok: Bool, _ what: String) {
        if !ok { failures += 1; print("  not so: \(what)") }
    }

    private static let realLedger = """
        {"crates": {
            "api-node-nest|5341": {"repo":"api-node-nest","number":5341,"wanted":"decon","placed":"decon","cleared":true,"alien":true,"slot":{"yard":"decon","group":0,"column":4,"order":0}},
            "api-node-nest|5344": {"repo":"api-node-nest","number":5344,"wanted":"decon","placed":"decon","cleared":true,"alien":true,"slot":{"yard":"decon","group":0,"column":5,"order":0}},
            "api-node-nest|5621": {"repo":"api-node-nest","number":5621,"wanted":"decon","placed":"decon","cleared":true,"alien":true,"slot":{"yard":"decon","group":0,"column":4,"order":1}},
            "api-node-nest|5622": {"repo":"api-node-nest","number":5622,"wanted":"decon","placed":"decon","cleared":true,"alien":true,"slot":{"yard":"decon","group":0,"column":5,"order":1}},
            "api-node-nest|5679": {"repo":"api-node-nest","number":5679,"wanted":"deck","placed":"deck","cleared":false,"alien":false,"slot":{"yard":"deck","group":1,"column":7,"order":0}},
            "api-node-nest|5686": {"repo":"api-node-nest","number":5686,"wanted":"storage","placed":"storage","cleared":false,"alien":false,"slot":{"yard":"storage","group":0,"column":6,"order":0}},
            "api-node-nest|5691": {"repo":"api-node-nest","number":5691,"wanted":"deck","placed":"deck","cleared":true,"alien":false,"slot":{"yard":"deck","group":0,"column":6,"order":3}},
            "api-node-nest|5693": {"repo":"api-node-nest","number":5693,"wanted":"deck","placed":"deck","cleared":true,"alien":false,"slot":{"yard":"deck","group":0,"column":7,"order":3}},
            "app-android|2623": {"repo":"app-android","number":2623,"wanted":"storage","placed":"storage","cleared":false,"alien":false,"slot":{"yard":"storage","group":0,"column":2,"order":0}},
            "app-ios|2777": {"repo":"app-ios","number":2777,"wanted":"decon","placed":"decon","cleared":true,"alien":true,"slot":{"yard":"decon","group":0,"column":2,"order":0}},
            "app-ios|2784": {"repo":"app-ios","number":2784,"wanted":"deck","placed":"deck","cleared":true,"alien":false,"slot":{"yard":"deck","group":0,"column":0,"order":0}},
            "app-ios|2787": {"repo":"app-ios","number":2787,"wanted":"decon","placed":"decon","cleared":true,"alien":true,"slot":{"yard":"decon","group":0,"column":3,"order":0}},
            "release-note-bot|74": {"repo":"release-note-bot","number":74,"wanted":"decon","placed":"decon","cleared":true,"alien":true,"slot":{"yard":"decon","group":0,"column":0,"order":0}},
            "tattoodo-web|13994": {"repo":"tattoodo-web","number":13994,"wanted":"deck","placed":"deck","cleared":true,"alien":false,"slot":{"yard":"deck","group":0,"column":6,"order":0}},
            "tattoodo-web|14010": {"repo":"tattoodo-web","number":14010,"wanted":"deck","placed":"deck","cleared":true,"alien":false,"slot":{"yard":"deck","group":0,"column":7,"order":0}},
            "tattoodo-web|14011": {"repo":"tattoodo-web","number":14011,"wanted":"deck","placed":"deck","cleared":true,"alien":false,"slot":{"yard":"deck","group":0,"column":14,"order":0}},
            "tattoodo-web|14013": {"repo":"tattoodo-web","number":14013,"wanted":"deck","placed":"deck","cleared":true,"alien":false,"slot":{"yard":"deck","group":0,"column":15,"order":0}},
            "tattoodo-web|14024": {"repo":"tattoodo-web","number":14024,"wanted":"deck","placed":"deck","cleared":true,"alien":false,"slot":{"yard":"deck","group":0,"column":6,"order":1}},
            "tattoodo-web|14027": {"repo":"tattoodo-web","number":14027,"wanted":"deck","placed":"deck","cleared":true,"alien":false,"slot":{"yard":"deck","group":0,"column":7,"order":1}},
            "tattoodo-web|14031": {"repo":"tattoodo-web","number":14031,"wanted":"deck","placed":"deck","cleared":true,"alien":false,"slot":{"yard":"deck","group":0,"column":14,"order":1}},
            "tattoodo-web|14036": {"repo":"tattoodo-web","number":14036,"wanted":"decon","placed":"decon","cleared":true,"alien":true,"slot":{"yard":"decon","group":0,"column":6,"order":0}},
            "tattoodo-web|14037": {"repo":"tattoodo-web","number":14037,"wanted":"deck","placed":"deck","cleared":true,"alien":false,"slot":{"yard":"deck","group":0,"column":15,"order":1}},
            "tattoodo-web|14038": {"repo":"tattoodo-web","number":14038,"wanted":"deck","placed":"deck","cleared":true,"alien":false,"slot":{"yard":"deck","group":0,"column":6,"order":2}},
            "tattoodo-web|14044": {"repo":"tattoodo-web","number":14044,"wanted":"deck","placed":"deck","cleared":true,"alien":false,"slot":{"yard":"deck","group":0,"column":7,"order":2}},
            "tattoodo-web|14045": {"repo":"tattoodo-web","number":14045,"wanted":"deck","placed":"deck","cleared":true,"alien":false,"slot":{"yard":"deck","group":0,"column":14,"order":2}},
            "tattoodo-web|14050": {"repo":"tattoodo-web","number":14050,"wanted":"deck","placed":"deck","cleared":true,"alien":false,"slot":{"yard":"deck","group":0,"column":12,"order":0}},
            "tattoodo-web|14053": {"repo":"tattoodo-web","number":14053,"wanted":"deck","placed":"storage","cleared":false,"alien":false,"slot":{"yard":"storage","group":0,"column":7,"order":0}},
            "tattoodo-web|14054": {"repo":"tattoodo-web","number":14054,"wanted":"deck","placed":"deck","cleared":true,"alien":false,"slot":{"yard":"deck","group":0,"column":15,"order":2}},
            "tattoodo-web|14056": {"repo":"tattoodo-web","number":14056,"wanted":"deck","placed":"deck","cleared":true,"alien":false,"slot":{"yard":"deck","group":0,"column":4,"order":0}},
            "tattoodo-web|14059": {"repo":"tattoodo-web","number":14059,"wanted":"deck","placed":"deck","cleared":true,"alien":false,"slot":{"yard":"deck","group":0,"column":5,"order":0}},
            "tattoodo-web|14062": {"repo":"tattoodo-web","number":14062,"wanted":"deck","placed":"deck","cleared":true,"alien":false,"slot":{"yard":"deck","group":0,"column":5,"order":1}},
            "tattoodo-web|14066": {"repo":"tattoodo-web","number":14066,"wanted":"deck","placed":"deck","cleared":true,"alien":false,"slot":{"yard":"deck","group":0,"column":13,"order":0}},
            "tattoodo-web|14067": {"repo":"tattoodo-web","number":14067,"wanted":"deck","placed":"deck","cleared":true,"alien":false,"slot":{"yard":"deck","group":0,"column":4,"order":1}},
            "tattoodo-web|14072": {"repo":"tattoodo-web","number":14072,"wanted":"deck","placed":"deck","cleared":false,"alien":false,"slot":{"yard":"deck","group":1,"column":14,"order":0}},
            "tattoodo-web|14073": {"repo":"tattoodo-web","number":14073,"wanted":"deck","placed":"deck","cleared":false,"alien":false,"slot":{"yard":"deck","group":1,"column":7,"order":1}}
        }}
        """
}
