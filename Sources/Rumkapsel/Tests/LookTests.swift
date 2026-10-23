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
        do {
            let t0 = Date()
            let img = Planets.image("mars", color: NSColor(rgb: (0.9, 0.2, 0.2)))
            let spent = Date().timeIntervalSince(t0)
            var ok = false, detail = false
            if let img, let data = img.dataProvider?.data as Data? {
                let w = img.width, h = img.height, row = img.bytesPerRow
                var lums = Set<Int>(), red = 0, n = 0
                for y in stride(from: h / 4, to: h * 3 / 4, by: max(1, h / 20)) {
                    for x in stride(from: 0, to: w, by: max(1, w / 20)) {
                        let i = y * row + x * 4
                        let r = Int(data[i]), g = Int(data[i + 1]), b = Int(data[i + 2])
                        if r > g && r > b { red += 1 }
                        lums.insert((r + g + b) / 12); n += 1
                    }
                }
                ok = red * 10 >= n * 9
                detail = lums.count > 5
            }
            if !(ok && detail) || spent > 3 { failures += 1 }
            say((ok && detail && spent <= 3 ? "PASS  " : "FAIL  ") + String(format: "a planet's texture is tinted into its repository's colour, keeping its detail, in %.2fs", spent))
        }
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
            test("\(theme.title) furniture stands where the station says it does") {
                let rooms = station.rooms.values.filter { !$0.key.hasPrefix("kind:") }.sorted { $0.key < $1.key }
                let drawn = furniture(station, offices: rooms), said = station.furniture(theme, offices: rooms)
                expect(drawn == said, "drawn but not said \(drawn.subtracting(said).sorted { ($0.x, $0.y) < ($1.x, $1.y) }.prefix(8)), said but not drawn \(said.subtracting(drawn).sorted { ($0.x, $0.y) < ($1.x, $1.y) }.prefix(8))")
            }
            test("\(theme.title) cones stand where the station says they do") {
                let look = Looks.current
                let node = look.message(color: .white, floor: .white) ?? Props.pyramid(color: .white, size: 0.32, floor: .white)
                let c = Cell(x: 3, y: -2)
                node.position = v3(Double(c.x), 0, Double(c.y))
                expect(cells([node], offset: .zero) == Set(Footprint.cone(c).cells), "the cone's footprint is \(cells([node], offset: .zero).count) sub-cells")
            }
            test("\(theme.title) letters its floor: \(claim.letters)") {
                expect(Looks.current.writesOnFloor == claim.letters, "writesOnFloor is \(Looks.current.writesOnFloor)")
            }
            test("\(theme.title) launches within the climb: gone from the pad view when the shown rocket goes") {
                let end = Looks.current.launch(at: ShownRocket.climbSeconds)
                expect(ShownRocket.climbSeconds >= Looks.current.launchSeconds && end.opacity <= 0.001,
                       "climb \(ShownRocket.climbSeconds) s, launch \(Looks.current.launchSeconds) s, opacity at the end \(end.opacity)")
                expect(!theme.kickRises || RocketGeometry.clearing < ShownRocket.climbSeconds, "the rocket clears the pad lift before it goes: \(RocketGeometry.clearing) s")
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

    private static func furniture(_ st: Station, offices: [Room]) -> Set<Cell> {
        let look = Looks.current
        var out: Set<Cell> = []
        func place(_ room: Room?, _ nodes: [SCNNode], local: Bool = false, long: Bool = false) {
            guard let room else { return }
            let floor = Set(room.cells)
            out.formUnion(cells(nodes, offset: local ? .zero : st.offset, long: long).filter { floor.contains(Station.cell(ofSub: $0)) })
        }
        place(st.rooms["kind:lounge"], st.rooms["kind:lounge"].map { look.furnishLounge($0, in: st).props } ?? [])
        place(st.rooms["kind:bath"], st.rooms["kind:bath"].map { look.furnishBath($0, in: st).props } ?? [])
        place(st.rooms["kind:gym"], st.rooms["kind:gym"].map { look.furnishGym($0, in: st).props } ?? [])
        place(st.rooms["kind:galley"], st.rooms["kind:galley"].map { look.furnishGalley($0, in: st).props } ?? [])
        place(st.rooms["kind:mission"], st.rooms["kind:mission"].map { look.furnishMission($0, in: st).props } ?? [])
        place(st.rooms["kind:quarters"], st.fixtures(in: "kind:quarters").map { b in
            let n = look.bed()
            n.position.x += b.at.x; n.position.z += b.at.y
            n.eulerAngles.y = CGFloat(b.yaw)
            return n
        }, local: true, long: true)
        for room in offices {
            let sign = OfficeSign(number: 101, who: "mads", name: room.name)
            place(room, look.dress(office: room, in: st, sign: sign).map { [$0] } ?? [], local: true)
        }
        return out
    }

    private static func cells(_ nodes: [SCNNode], offset: SIMD2<Double>, long: Bool = false) -> Set<Cell> {
        var out: Set<Cell> = []
        for n in nodes where !(n.geometry is SCNPlane) {
            let (lo, hi) = n.boundingBox
            guard Double(hi.y - lo.y) * Double(n.scale.y) > 0.03 else { continue }
            let at = SIMD2(Double(n.position.x) - offset.x, Double(n.position.z) - offset.y)
            if long {
                out.formUnion(Footprint(at: at, size: SIMD2(Double(hi.x - lo.x), Double(hi.z - lo.z)) * Double(n.scale.x), yaw: Double(n.eulerAngles.y)).cells)
                continue
            }
            let r = Double(max(hi.x - lo.x, hi.z - lo.z)) / 2 * 0.8 * Double(n.scale.x)
            out.formUnion(Footprint(at: at, radius: r).cells)
        }
        return out
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
