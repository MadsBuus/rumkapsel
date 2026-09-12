// Model-only tests of the crate ledger: `.build/debug/Rumkapsel --ledger-tests`.
//
// No station, no scene, no clock. Facts are fed to a ledger in every order a source and a hand
// can produce them, and after each the ledger must hold: every crate placed in one yard at most,
// a hand landing outranking any older word from the source, and wanted equal to placed as soon as
// the source has said something newer. Exits non-zero if anything failed.

import Foundation

enum LedgerTests {
    private static var failures = 0

    static func run() -> Never {
        let t0 = Date(timeIntervalSince1970: 1_000)
        func at(_ s: Double) -> Date { t0.addingTimeInterval(s) }
        func word(storage: [Int] = [], deck: [Int] = [], cleared: [Int] = [], updated: [Int: Date] = [:]) -> Ledger.Word {
            Ledger.Word(storage: storage, deck: deck, cleared: cleared, updated: updated)
        }

        test("a first answer places every crate where the source says, and disagrees about nothing") {
            var l = Ledger()
            l.adopt(word(storage: [1, 2], deck: [3], updated: [1: at(0), 2: at(0), 3: at(0)]), repo: "web")
            expect(l["web", 1]?.placed == .storage, "#1 in storage")
            expect(l["web", 3]?.placed == .deck, "#3 on the deck")
            expect(l.disagreements(repo: "web").isEmpty, "nothing to reconcile")
            expect(l.counts(in: .storage)["web"] == 2 && l.counts(in: .deck)["web"] == 1, "counts read off placed")
        }

        test("board before release: the board moves a crate, the station carries it, the board agrees") {
            var l = Ledger()
            l.adopt(word(storage: [1], updated: [1: at(0)]), repo: "web")
            l.adopt(word(deck: [1], updated: [1: at(10)]), repo: "web")
            expect(l.disagreements(repo: "web").map(\.number) == [1], "one crate to carry")
            l.order(repo: "web", number: 1, to: .deck)
            expect(l.disagreements(repo: "web").isEmpty, "a crate on its way is not a disagreement")
            l.landed(repo: "web", number: 1, in: .deck, at: at(20))
            expect(l["web", 1]?.placed == .deck && l["web", 1]?.movedAt == nil, "down where the source wanted it: agreed")
            l.adopt(word(deck: [1], updated: [1: at(10)]), repo: "web")
            expect(l.disagreements(repo: "web").isEmpty, "the same answer again changes nothing")
        }

        test("release before board: the hand lands first, the board's older word is stale, its newer word agrees") {
            var l = Ledger()
            l.adopt(word(storage: [1, 2], updated: [1: at(0), 2: at(0)]), repo: "web")
            l.order(repo: "web", number: 1, to: .deck); l.landed(repo: "web", number: 1, in: .deck, at: at(30))
            l.order(repo: "web", number: 2, to: .deck); l.landed(repo: "web", number: 2, in: .deck, at: at(31))
            expect(l.counts(in: .deck)["web"] == 2 && l.counts(in: .storage)["web"] == nil, "both on the deck by hand")
            l.adopt(word(storage: [1, 2], updated: [1: at(0), 2: at(0)]), repo: "web")   // the board still says storage, from before
            expect(l["web", 1]?.placed == .deck && l["web", 2]?.placed == .deck, "a stale answer takes nothing back")
            expect(l.disagreements(repo: "web").isEmpty, "and asks for no carry")
            l.adopt(word(deck: [1, 2], updated: [1: at(40), 2: at(40)]), repo: "web")   // the board catches up
            expect(l.disagreements(repo: "web").isEmpty && l["web", 1]?.movedAt == nil, "wanted equals placed, the hand is history")
        }

        test("stale after fresh: a fresh word, then an older one for the same crate, changes nothing") {
            var l = Ledger()
            l.adopt(word(storage: [1], updated: [1: at(0)]), repo: "web")
            l.landed(repo: "web", number: 1, in: .deck, at: at(50))
            l.adopt(word(deck: [1], updated: [1: at(60)]), repo: "web")
            expect(l.disagreements(repo: "web").isEmpty, "agreed")
            l.adopt(word(storage: [1], updated: [1: at(0)]), repo: "web")   // a peer's older copy of the board
            expect(l["web", 1]?.placed == .deck && l["web", 1]?.wanted == .deck, "an older word is not news")
        }

        test("A then B then A: the source's newer word outranks the hand, agreeing or not") {
            var l = Ledger()
            l.adopt(word(storage: [1], updated: [1: at(0)]), repo: "web")
            l.landed(repo: "web", number: 1, in: .deck, at: at(10))
            l.adopt(word(storage: [1], updated: [1: at(20)]), repo: "web")   // moved back to storage after the landing: news
            expect(l.disagreements(repo: "web").map(\.number) == [1], "a newer disagreement is for the reconciler")
            l.snap(repo: "web", number: 1)
            expect(l["web", 1]?.placed == .storage, "no carry deck to storage: redrawn where the source says")
            l.adopt(word(deck: [1], updated: [1: at(30)]), repo: "web")
            expect(l["web", 1]?.wanted == .deck && l["web", 1]?.placed == .storage, "and back the other way: a carry to come")
        }

        test("a source with no times is believed again when it agrees") {
            var l = Ledger()
            l.adopt(word(storage: [1]), repo: "web")
            l.landed(repo: "web", number: 1, in: .deck, at: at(10))
            l.adopt(word(storage: [1]), repo: "web")
            expect(l["web", 1]?.placed == .deck && l.disagreements(repo: "web").isEmpty, "the station's word stands")
            l.adopt(word(deck: [1]), repo: "web")
            expect(l["web", 1]?.movedAt == nil && l.disagreements(repo: "web").isEmpty, "agreed the moment it says the same")
        }

        test("aboard the rocket: not drawn on the deck again, gone when the source stops counting it") {
            var l = Ledger()
            l.adopt(word(deck: [1], cleared: [1], updated: [1: at(0)]), repo: "web")
            l.order(repo: "web", number: 1, to: .pad); l.landed(repo: "web", number: 1, in: .pad, at: at(10))
            expect(l.counts(in: .deck)["web"] == nil, "off the deck")
            l.adopt(word(deck: [1], cleared: [1], updated: [1: at(0)]), repo: "web")   // the board still says ready to ship
            expect(l["web", 1]?.placed == .pad, "stays aboard")
            l.adopt(word(updated: [:]), repo: "web")   // shipped: the source counts it nowhere
            expect(l["web", 1] == nil, "lifted off with the rocket")
        }

        test("a merged office's package: ordered to storage before the source knows it, then counted") {
            var l = Ledger()
            l.order(repo: "web", number: 9, to: .storage)
            expect(l["web", 9]?.placed == nil && l.holds(.storage, repo: "web").map(\.number) == [9], "storage holds its slot, counts nothing yet")
            l.adopt(word(storage: [], updated: [:]), repo: "web")
            expect(l["web", 9] != nil, "an order is not forgotten by an answer that does not know it")
            l.landed(repo: "web", number: 9, in: .storage, at: at(5))
            expect(l.counts(in: .storage)["web"] == 1, "down: counted")
            l.adopt(word(storage: [9], updated: [9: at(8)]), repo: "web")
            expect(l.disagreements(repo: "web").isEmpty && l["web", 9]?.movedAt == nil, "the source caught up")
        }

        test("every crate is in one yard at most, whatever the order of facts") {
            let words = [word(storage: [1], updated: [1: at(1)]), word(deck: [1], updated: [1: at(2)]), word(storage: [1], updated: [1: at(3)])]
            for order in [[0, 1, 2], [2, 1, 0], [1, 0, 2], [0, 2, 1]] {
                var l = Ledger()
                for i in order { l.adopt(words[i], repo: "web") }
                l.landed(repo: "web", number: 1, in: .deck, at: at(2.5))
                for i in order { l.adopt(words[i], repo: "web") }
                let yards = [Yard.storage, .deck, .pad].filter { l.counts(in: $0)["web"] != nil }
                expect(yards.count == 1, "order \(order): drawn in \(yards.count) yards")
                expect(l["web", 1]?.wanted == .storage, "order \(order): the newest word wins")
            }
        }

        say(failures == 0 ? "ledger: all passed" : "ledger: \(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }

    private static var current = ""
    private static func test(_ name: String, _ body: () -> Void) {
        current = name
        let before = failures
        body()
        say((failures == before ? "PASS  " : "FAIL  ") + name)
    }
    private static func expect(_ ok: Bool, _ what: String) {
        if !ok { failures += 1; say("      not so: \(what)") }
    }
    private static func say(_ text: String) { FileHandle.standardError.write((text + "\n").data(using: .utf8)!) }
}
