// Model-only tests of a lounger's idle life: `.build/debug/Rumkapsel --idle-tests`.
//
// No station, no scene: a clock stepped by hand and rolls chosen on purpose. One idle clock per
// lounger, armed on the couch, kept while away, dropped by work; a pick by weight, with nowhere to
// go turning into a look round the station; roamers keeping apart except when there is company.

import Foundation

enum IdleTests {
    private static var failures = 0

    static func run() -> Never {
        let span = { 200.0 }

        test("the clock arms on the couch and runs out once, on the station clock") {
            var c = IdleClock()
            expect(!c.armed, "unarmed to begin with")
            expect(!c.tick(at: 10, lounging: true, busy: false, span: span), "arming is not running out")
            expect(c.armed && c.dueAt == 210, "due two hundred seconds on")
            expect(!c.tick(at: 209, lounging: true, busy: false, span: span), "not yet")
            expect(c.tick(at: 210, lounging: true, busy: false, span: span), "now")
            expect(!c.armed, "and disarmed until the lounger is back")
            expect(!c.tick(at: 210.1, lounging: true, busy: false, span: span) && c.dueAt == 410.1, "the next visit arms afresh")
        }

        test("leaving the lounge does not reset it: it runs out on the return") {
            var c = IdleClock()
            _ = c.tick(at: 0, lounging: true, busy: false, span: span)
            for t in stride(from: 1.0, through: 300, by: 1) { expect(!c.tick(at: t, lounging: false, busy: false, span: span), "away at \(t): nothing picked") }
            expect(c.dueAt == 200, "still due at 200")
            expect(c.tick(at: 301, lounging: true, busy: false, span: span), "back, and overdue: picked at once")
        }

        test("work drops the clock; rest arms it again from scratch") {
            var c = IdleClock()
            _ = c.tick(at: 0, lounging: true, busy: false, span: span)
            expect(!c.tick(at: 50, lounging: false, busy: true, span: span) && !c.armed, "busy: dropped")
            expect(!c.tick(at: 250, lounging: true, busy: false, span: span) && c.dueAt == 450, "armed afresh on the couch, not overdue")
        }

        test("the span is two to five minutes") {
            expect(IdleClock.span == 120.0...300.0, "got \(IdleClock.span)")
            var c = IdleClock()
            _ = c.tick(at: 0, lounging: true, busy: false)
            expect(IdleClock.span.contains(c.dueAt), "a random span lands in it: \(c.dueAt)")
        }

        test("one thing by weight: a look round most often, then the gym, the bath, and now and then a book") {
            func pick(_ roll: Double) -> IdlePick { IdlePick.pick(roll: roll, night: false, crew: false, gymFree: true, bath: true, shower: true) }
            expect(pick(0) == .roam && pick(0.39) == .roam, "under 0.40: a look round")
            expect(pick(0.40) == .gym && pick(0.64) == .gym, "to 0.65: the gym")
            expect(pick(0.65) == .bath(shower: true) && pick(0.84) == .bath(shower: true), "to 0.85: the bath")
            expect(pick(0.85) == .read && pick(0.999) == .read, "the rest: a book")
            let weights = [IdlePick.roamBelow, IdlePick.gymBelow - IdlePick.roamBelow, IdlePick.bathBelow - IdlePick.gymBelow, 1 - IdlePick.bathBelow]
            expect(weights.max()! < 0.8, "no one thing takes over: \(weights)")
        }

        test("the gym only by day, never for the crew, only when a fixture is free; otherwise a look round") {
            expect(IdlePick.pick(roll: 0.5, night: true, crew: false, gymFree: true, bath: true, shower: false) == .roam, "night")
            expect(IdlePick.pick(roll: 0.5, night: false, crew: true, gymFree: true, bath: true, shower: false) == .roam, "crew")
            expect(IdlePick.pick(roll: 0.5, night: false, crew: false, gymFree: false, bath: true, shower: false) == .roam, "every fixture taken")
            expect(IdlePick.pick(roll: 0.5, night: false, crew: false, gymFree: true, bath: true, shower: false) == .gym, "by day, free")
        }

        test("the bath only where there is one, a shower or the toilet as rolled") {
            expect(IdlePick.pick(roll: 0.7, night: true, crew: true, gymFree: false, bath: false, shower: true) == .roam, "no bath: a look round")
            expect(IdlePick.pick(roll: 0.7, night: true, crew: true, gymFree: false, bath: true, shower: false) == .bath(shower: false), "the toilet")
        }

        test("roamers keep apart, except when there is company to keep, or nowhere else to stand") {
            let clear = [Cell(x: 0, y: 0), Cell(x: 1, y: 0), Cell(x: 5, y: 0)]
            let first = { (cells: [Cell]) -> Cell? in cells.first }
            expect(RoamSpots.choose(clear: clear, taken: [Cell(x: 0, y: 1)], company: false, random: first) == Cell(x: 5, y: 0), "three tiles from anyone")
            expect(RoamSpots.choose(clear: clear, taken: [Cell(x: 0, y: 1)], company: true, random: first) == Cell(x: 0, y: 0), "a steaming rocket: company is fine")
            expect(RoamSpots.choose(clear: clear, taken: [Cell(x: 0, y: 1), Cell(x: 5, y: 1)], company: false, random: first) == Cell(x: 0, y: 0), "nowhere apart: anywhere clear")
            expect(RoamSpots.choose(clear: [], taken: [], company: false, random: first) == nil, "nowhere clear: nowhere")
        }

        say(failures == 0 ? "idle: all passed" : "idle: \(failures) failed")
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
