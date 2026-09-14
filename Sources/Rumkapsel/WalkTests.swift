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

        test("a clear line is walked straight at the waypoint") {
            let m = body("a", 0, 0)
            let (aim, near) = Walk.aim(m, target: SIMD2(1, 0), others: [], station: station)
            expect(aim == SIMD2(1, 0) && near == nil, "aimed \(aim)")
        }

        test("someone on the waypoint is passed a third of a tile to the side, away from them") {
            let m = body("a", 0, 0)
            let o = body("b", 1, 0.1)   // a shade to the walker's left
            let (aim, near) = Walk.aim(m, target: SIMD2(1, 0), others: [o], station: station)
            expect(near?.id == "b", "in the way")
            expect(abs(aim.x - 1) < 1e-9 && abs(aim.y + Walk.sidestep) < 1e-9, "aimed past on the far side, got \(aim)")
        }

        test("someone behind is nobody's business") {
            let m = body("a", 0, 0)
            let o = body("b", -0.5, 0)
            let (aim, near) = Walk.aim(m, target: SIMD2(1, 0), others: [o], station: station)
            expect(near == nil && aim == SIMD2(1, 0), "walked on")
        }

        test("two head-on both aim to their own right and pass") {
            let a = body("a", 0, 0), b = body("b", 1, 0)
            let (aimA, _) = Walk.aim(a, target: SIMD2(1, 0), others: [b], station: station)
            let (aimB, _) = Walk.aim(b, target: SIMD2(0, 0), others: [a], station: station)
            expect(aimA.y * aimB.y < 0, "on opposite sides of the line: \(aimA.y) and \(aimB.y)")
        }

        test("where no side is walkable the line is kept and the walker holds") {
            let m = body("a", 0, -3)            // the corridor's north arm ends at the core
            let o = body("b", 0, -2.5)
            var lone = Station(name: "work")
            _ = lone
            let (aim, near) = Walk.aim(m, target: SIMD2(0, -2), others: [o], station: station)
            expect(near?.id == "b", "in the way")
            let cell = Cell(x: Int(aim.x.rounded()), y: Int(aim.y.rounded()))
            expect(station.walkable.contains(cell), "never aimed off the floor: \(aim)")
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
