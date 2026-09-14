// Model-only tests of the walk step: `.build/debug/Rumkapsel --walk-tests`.
//
// A made-up floor, made-up bodies, no station controller: a clear line is walked straight; someone
// in the way is passed on the side away from them; where no side is walkable the line is kept.

import Foundation

enum WalkTests {
    private static var failures = 0

    static func run() -> Never {
        let station = Station(name: "work")   // the bare corridor cross is walkable
        func body(_ id: String, _ x: Double, _ y: Double) -> Body {
            let b = Body(id: id, station: "work", home: Home(key: "k", name: id, repo: "r", issue: nil), cwd: "", toolCount: 0, isSubagent: false, start: Cell(x: 0, y: 0))
            b.pos = SIMD2(x, y); b.opacity = 1; b.state = .settled
            return b
        }

        test("a clear line is walked straight, and the waypoint is popped on arrival") {
            let m = body("a", 0, 0); m.path = [SIMD2(1, 0)]
            for _ in 0..<60 { _ = Walk.step(m, speed: 1.4, dt: 1.0 / 30, others: []) }
            expect(m.path.isEmpty && m.pos == SIMD2(1, 0) && m.lean == .zero, "there, straight: \(m.pos)")
        }

        test("someone close ahead is passed with a lean to the walker's own right, facing them; behind is nobody's business") {
            let m = body("a", 0.6, 0), o = body("b", 1, 0); m.path = [SIMD2(1, 0), SIMD2(2, 0)]
            var near: Body?
            for _ in 0..<12 { near = Walk.step(m, speed: 1.4, dt: 1.0 / 30, others: [o]) }   // closer than the lean gap now
            expect(near?.id == "b" && m.lean.y < 0 && abs(m.lean.y) > Walk.sidestep * 0.5, "leaning right after the turn: \(m.lean)")
            expect(abs(m.facing - atan2(0.0, 1.0)) < 1e-9, "turned side-on, a quarter turn to its left: \(m.facing)")
            let back = body("c", 0, 0); back.path = [SIMD2(1, 0)]
            expect(Walk.step(back, speed: 1.4, dt: 1.0 / 30, others: [body("d", -0.3, 0)]) == nil && back.lean == .zero, "behind: no lean")
        }

        test("the pass never moves the body off its line: two head-on both arrive exactly") {
            let a = body("a", 0, 0), b = body("b", 2, 0); a.path = [SIMD2(1, 0), SIMD2(2, 0)]; b.path = [SIMD2(1, 0), SIMD2(0, 0)]
            var leaned = false
            for _ in 0..<300 {
                _ = Walk.step(a, speed: 1.4, dt: 1.0 / 30, others: [b]); _ = Walk.step(b, speed: 1.4, dt: 1.0 / 30, others: [a])
                if a.lean != .zero && b.lean != .zero && a.lean.y * b.lean.y < 0 { leaned = true }
                expect(a.pos.y == 0 && b.pos.y == 0, "on the line")
            }
            expect(leaned, "they leaned to opposite sides as they met")
            expect(a.path.isEmpty && a.pos == SIMD2(2, 0) && b.path.isEmpty && b.pos == SIMD2(0, 0), "both exactly there: \(a.pos) \(b.pos)")
        }

        test("a walk that ends beside someone ends straight, lean gone, facing the way it came") {
            let m = body("a", 0.5, 0), o = body("b", 1.2, 0); m.path = [SIMD2(1, 0)]
            for _ in 0..<200 { _ = Walk.step(m, speed: 1.4, dt: 1.0 / 30, others: [o]) }
            expect(m.path.isEmpty && m.lean == .zero && abs(m.facing - atan2(1.0, 0.0)) < 1e-9, "square at the end: lean \(m.lean) facing \(m.facing)")
        }

        say(failures == 0 ? "walk: all passed" : "walk: \(failures) failed")
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
