import AppKit
import SceneKit

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

        test("the holo's sky: a planet per repo, a moon per open piece of work at its stage, nothing shipped or not started") {
            func record(_ id: Int, _ repo: String, _ stage: Stage?) -> WorkBook.Record {
                let r = WorkBook.Record(id: id, repo: repo); r.stage = stage; return r
            }
            let records = [record(1, "web", .working), record(2, "web", .qa), record(3, "web", .shipped), record(4, "web", .inbound),
                           record(5, "api", .cleared), record(6, "api", nil), record(7, "elsewhere", .stored)]
            let sky = HoloSky.make(repos: [("web", RGB(r: 1, g: 0.5, b: 0.4)), ("api", RGB(r: 0.6, g: 0.9, b: 0.2))], records: records,
                                   checks: { $0.id == 2 ? .failed : .none }, commits: { $0.id })
            expect(sky.planets.map(\.repo) == ["web", "api"], "a planet per repo: \(sky.planets.map(\.repo))")
            expect(sky.moons.map(\.id) == [1, 2, 5], "moons for open work only: \(sky.moons.map(\.id))")
            expect(sky.moons.first { $0.id == 2 }?.checks == .failed && sky.moons.first { $0.id == 5 }?.commits == 5, "with its checks and commits")
            expect(HoloSky.orbit(.working) < HoloSky.orbit(.stored) && HoloSky.orbit(.stored) < HoloSky.orbit(.qa) && HoloSky.orbit(.qa) < HoloSky.orbit(.cleared),
                   "further out the further along")
            let moon = HoloSky.Moon(id: 9, repo: "web", stage: .qa, checks: .none, commits: 0, title: "#5770 let studios rent", link: "https://github.com/o/web/pull/1")
            expect(HoloSky.hover(moon) == "link:https://github.com/o/web/pull/1|#5770 let studios rent · testing · click to open", "a moon hovers its work and stage: \(HoloSky.hover(moon))")
            expect(sky.hover(sky.planets[0]).hasSuffix("|web · 2 open"), "a planet hovers its repo and open work: \(sky.hover(sky.planets[0]))")
        }

        test("the holo draws a moon's new commit as a blip, and a moon that leaves falls into its planet") {
            let view = HoloView(root: SCNNode())
            let web = HoloSky.Planet(repo: "web", color: RGB(r: 1, g: 0.5, b: 0.4))
            view.show(HoloSky(planets: [web], moons: [HoloSky.Moon(id: 1, repo: "web", stage: .working, checks: .none, commits: 2)]), clock: 0)
            expect(view.blips.isEmpty, "a first look fires nothing")
            view.show(HoloSky(planets: [web], moons: [HoloSky.Moon(id: 1, repo: "web", stage: .working, checks: .running, commits: 3)]), clock: 1)
            expect(view.blips.count == 1, "one commit, one blip: \(view.blips.count)")
            view.step(clock: 1 + HoloView.blip + 0.1, dt: 0.1)
            expect(view.blips.isEmpty && view.pulses["web"] != nil, "it lands and the planet pulses")
            view.show(HoloSky(planets: [web], moons: []), clock: 2)
            expect(view.moons[1]?.falling != nil, "the moon starts to fall")
            for k in 0..<20 { view.step(clock: 2 + Double(k) * 0.1, dt: 0.1) }
            expect(view.moons.isEmpty, "and is gone into its planet")
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
