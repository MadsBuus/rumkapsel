import AppKit
import Foundation
import SceneKit

enum LookTests {
    private static var failures = 0

    private struct Claim {
        var drawn: [String] = []
        var classic: [String] = []
        var letters = true
        var rims = true
    }

    private static let claims: [Theme: Claim] = [
        .classic: Claim(classic: ["input", "output", "crate", "hold", "tool", "message",
                                  "office", "station", "figure", "drone", "jetpack"]),
        .kenney: Claim(drawn: ["input", "output", "office", "station", "figure", "crate", "hold"],
                       classic: ["tool", "message", "drone", "jetpack"], rims: false),
        .kingdom: Claim(drawn: ["input", "output", "office", "station", "figure", "crate", "hold",
                                "tool", "message"],
                        classic: ["drone", "jetpack"], letters: false, rims: false),
    ]

    static func run() -> Never {
        for theme in Theme.allCases {
            guard let claim = claims[theme] else {
                failures += 1
                say("FAIL  \(theme.title): says nothing about what it draws. Add it to LookTests.claims.")
                continue
            }
            Theme.pinnedForPlan = theme
            Looks.use(theme)
            let station = fresh()
            for i in 0..<6 { _ = station.ensureRoom(key: "task:repo\(i)#\(100 + i)", name: "#\(100 + i) work", repo: "r",
                                                    color: Colors.repos[i % Colors.repos.count],
                                                    lastActive: Date(timeIntervalSince1970: 0)) }
            let drawn = made(on: station)
            for piece in claim.drawn {
                test("\(theme.title) draws its own \(piece)") {
                    expect(drawn[piece] == true, "the look's \(piece) came back empty, so the scene is using the classic piece")
                }
            }
            for piece in claim.classic {
                test("\(theme.title) leaves the \(piece) to the classic piece") {
                    expect(drawn[piece] == false, "the look drew a \(piece) it says nothing about")
                }
            }
            test("\(theme.title) letters its floor: \(claim.letters)") {
                expect(Looks.current.writesOnFloor == claim.letters, "writesOnFloor is \(Looks.current.writesOnFloor)")
            }
            test("\(theme.title) rims its offices: \(claim.rims)") {
                expect(Looks.current.rimsOffices == claim.rims, "rimsOffices is \(Looks.current.rimsOffices)")
            }
        }
        Theme.pinnedForPlan = .classic
        Looks.use(.classic)
        say(failures == 0 ? "looks: all passed" : "looks: \(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }

    private static func made(on station: Station) -> [String: Bool] {
        let look = Looks.current
        let office = station.rooms.values.first { !$0.key.hasPrefix("kind:") }
        let sign = OfficeSign(number: 101, who: "mads", name: "#101 work")
        return [
            "input": look.input(station) != nil,
            "output": look.output(station, deckInUse: true) != nil,
            "crate": look.crate(color: .white) != nil,
            "hold": look.hold(tall: true) != nil,
            "jetpack": look.jetpack(height: 0.5, depth: 0.11) != nil,
            "drone": look.padDrone() != nil,
            "tool": look.tool(.hammer, height: 0.5, depth: 0.3) != nil,
            "message": look.message(color: .white, floor: .white) != nil,
            "office": office.flatMap { look.dress(office: $0, in: station, sign: sign) } != nil,
            "station": !look.dress(station: station).isEmpty,
            "figure": look.figure(id: "a", crew: false, height: 0.5) != nil,
        ]
    }

    private static func fresh() -> Station {
        let world = World(demo: true)
        return world.fleet.station("work")
    }

    private static func test(_ name: String, _ body: () -> Void) {
        let before = failures
        body()
        if failures == before { say("PASS  \(name)") }
    }

    private static func expect(_ ok: Bool, _ detail: @autoclosure () -> String) {
        guard !ok else { return }
        failures += 1
        say("FAIL  \(detail())")
    }

    private static func say(_ line: String) {
        FileHandle.standardError.write((line + "\n").data(using: .utf8)!)
    }
}
