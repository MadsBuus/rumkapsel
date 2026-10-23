import AppKit

enum SceneTests {
    private static var failures = 0

    static func run() -> Never {
        let c = StationController(frame: NSRect(x: 0, y: 0, width: 640, height: 400), demo: false, simulated: true)
        let station = c.world.fleet.station("work")

        test("the first build makes every piece of the station") {
            c.rebuildStatic()
            let built = Set(c.statics.rebuilt)
            for id in ["floor:work", "hall:work", "room:work|kind:lounge", "room:work|kind:gym", "office:work|kind:lounge"] {
                expect(built.contains(id), "\(id) was built: \(built.sorted())")
            }
        }

        test("a rebuild with nothing changed rebuilds nothing") {
            c.rebuildStatic()
            expect(c.statics.rebuilt.isEmpty, "rebuilt anyway: \(c.statics.rebuilt.sorted())")
        }

        test("a room that changes rebuilds that room, and nothing else") {
            guard let lounge = station.rooms["kind:lounge"] else { return expect(false, "a lounge on the station") }
            lounge.color = RGB(r: 0.9, g: 0.3, b: 0.6)
            c.rebuildStatic()
            expect(Set(c.statics.rebuilt) == ["office:work|kind:lounge", "room:work|kind:lounge"], "rebuilt: \(c.statics.rebuilt.sorted())")
            c.rebuildStatic()
            expect(c.statics.rebuilt.isEmpty, "and once is enough: \(c.statics.rebuilt.sorted())")
        }

        say(failures == 0 ? "scene: all passed" : "scene: \(failures) failed")
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
