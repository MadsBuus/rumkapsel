// Model-only tests of the doorway lanes: `.build/debug/Rumkapsel --lane-tests`.
//
// No station, no scene: made-up doors, made-up walkers and a clock stepped by hand. A lane is
// claimed before it is stepped into, renewed while stood on, released once left; anyone else
// waits outside; a claim lapses unless renewed; a walker who is gone holds nothing; the tile
// outside a room's door is the lane's only for those going in or coming out.

import Foundation

enum LaneTests {
    private static var failures = 0

    static func run() -> Never {
        let door = Cell(x: 3, y: 1), outside = Cell(x: 3, y: 0), corridor = Cell(x: 4, y: 0), inside = Cell(x: 3, y: 2)
        let lanes = DoorLanes(station: "work", doors: [.init(room: "task:web#1", cell: door, outside: outside)],
                              yardDoorways: [(Cell(x: 8, y: 0), Cell(x: 8, y: -1))])
        let alive: (String) -> Bool = { _ in true }

        test("the door tile is the lane for everyone; the tile outside only for those going in or out") {
            expect(lanes.lane(at: door, inRoom: nil, headedTo: nil) == "work|door:task:web#1", "the door tile")
            expect(lanes.lane(at: outside, inRoom: nil, headedTo: nil) == nil, "walking past claims nothing")
            expect(lanes.lane(at: outside, inRoom: nil, headedTo: "task:web#1") == "work|door:task:web#1", "going in")
            expect(lanes.lane(at: outside, inRoom: "task:web#1", headedTo: nil) == "work|door:task:web#1", "coming out")
            expect(lanes.lane(at: corridor, inRoom: nil, headedTo: "task:web#1") == nil, "a corridor tile is nobody's")
            expect(lanes.touches(outside) && lanes.touches(door) && !lanes.touches(corridor), "nobody steps aside onto a lane")
        }

        test("a yard doorway is one lane over both its tiles") {
            let a = lanes.lane(at: Cell(x: 8, y: 0), inRoom: nil, headedTo: nil), b = lanes.lane(at: Cell(x: 8, y: -1), inRoom: nil, headedTo: nil)
            expect(a != nil && a == b, "one id for the pair, got \(a ?? "nil") and \(b ?? "nil")")
        }

        test("claim before stepping in, renew while on it, release once off it") {
            var claims = LaneClaims()
            var held: String?
            let lane = "work|door:task:web#1"
            expect(!claims.step(walker: "a", from: nil, to: lane, held: &held, at: 0, alive: alive), "a free lane is taken, not waited for")
            expect(held == lane && claims[lane]?.holder == "a" && claims[lane]?.until == LaneClaims.hold, "claimed until the hold runs out")
            expect(!claims.step(walker: "a", from: lane, to: lane, held: &held, at: 2, alive: alive), "on the lane: no wait")
            expect(claims[lane]?.until == 2 + LaneClaims.hold, "renewed from now")
            expect(!claims.step(walker: "a", from: nil, to: nil, held: &held, at: 3, alive: alive), "off it")
            expect(held == nil && claims[lane] == nil, "released")
        }

        test("anyone else waits outside while the lane is held, and goes once it is free") {
            var claims = LaneClaims()
            var a: String?, b: String?
            let lane = "work|door:task:web#1"
            _ = claims.step(walker: "a", from: nil, to: lane, held: &a, at: 0, alive: alive)
            expect(claims.step(walker: "b", from: nil, to: lane, held: &b, at: 1, alive: alive), "b waits")
            expect(b == nil && claims[lane]?.holder == "a", "and holds nothing")
            _ = claims.step(walker: "a", from: nil, to: nil, held: &a, at: 2, alive: alive)
            expect(!claims.step(walker: "b", from: nil, to: lane, held: &b, at: 2, alive: alive), "then goes")
            expect(claims[lane]?.holder == "b", "and holds it")
        }

        test("a claim lapses a few seconds after it was last renewed: a stuck walker cannot lock a door") {
            var claims = LaneClaims()
            var a: String?, b: String?
            let lane = "work|door:task:web#1"
            _ = claims.step(walker: "a", from: nil, to: lane, held: &a, at: 0, alive: alive)
            expect(claims.step(walker: "b", from: nil, to: lane, held: &b, at: LaneClaims.hold - 0.1, alive: alive), "still held just before")
            expect(!claims.step(walker: "b", from: nil, to: lane, held: &b, at: LaneClaims.hold, alive: alive), "lapsed on the hold")
            expect(claims[lane]?.holder == "b", "b took it over")
            claims.prune(at: 100)
            expect(claims[lane] == nil, "pruning drops what has lapsed")
        }

        test("a holder who is gone holds nothing") {
            var claims = LaneClaims()
            var a: String?, b: String?
            let lane = "work|door:task:web#1"
            _ = claims.step(walker: "a", from: nil, to: lane, held: &a, at: 0, alive: alive)
            expect(!claims.step(walker: "b", from: nil, to: lane, held: &b, at: 1, alive: { $0 != "a" }), "a left the station: b goes")
        }

        test("stepping from one lane straight onto another claims the next and keeps the first renewed") {
            var claims = LaneClaims()
            var a: String?
            expect(!claims.step(walker: "a", from: "x", to: "y", held: &a, at: 5, alive: alive), "free")
            expect(a == "y" && claims["y"]?.holder == "a", "the next lane is held")
            expect(claims["x"] == nil, "a lane never claimed is not invented")
        }

        say(failures == 0 ? "lanes: all passed" : "lanes: \(failures) failed")
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
