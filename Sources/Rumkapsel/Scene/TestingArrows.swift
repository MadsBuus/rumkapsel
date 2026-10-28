import AppKit
import SceneKit

final class TestingArrow {
    static let chevrons = 3, pace = 0.45, run = 0.8

    let node = SCNNode()
    var repos: [String] = []
    var marks: [SCNNode] = []

    init() {
        for _ in 0..<TestingArrow.chevrons {
            let mark = SCNNode(geometry: TestingArrow.chevron())
            mark.eulerAngles.x = -.pi / 2
            mark.castsShadow = false
            mark.categoryBitMask = Pick.scenery
            node.addChildNode(mark)
            marks.append(mark)
        }
    }

    private static func chevron() -> SCNGeometry {
        let w = 0.5, d = 0.2, t = 0.09
        let path = NSBezierPath()
        path.move(to: NSPoint(x: -w / 2, y: -d / 2))
        path.line(to: NSPoint(x: 0, y: d / 2))
        path.line(to: NSPoint(x: w / 2, y: -d / 2))
        path.line(to: NSPoint(x: w / 2, y: -d / 2 - t))
        path.line(to: NSPoint(x: 0, y: d / 2 - t))
        path.line(to: NSPoint(x: -w / 2, y: -d / 2 - t))
        path.close()
        return SCNShape(path: path, extrusionDepth: 0)
    }
}

extension StationController {
    func drawTestingArrows() {
        var want: [String: (at: SIMD2<Double>, repos: Set<String>)] = [:]
        for st in fleet.stations.values {
            var waiting = Set<String>()
            for (_, r) in simulation.shownRockets(st) where r.kind == .release && r.climbing == nil && r.leaving == nil {
                waiting.insert(r.repo)
            }
            guard !waiting.isEmpty, let crossing = st.hall.clearingAisle.first?.y else { continue }
            for (id, at) in simulation.shown[st.name]?.crates ?? [:] {
                guard case .row(let s) = at, s.zone == .testing, st.facts.crates[id]?.zone == .testing,
                      waiting.contains(id.repo) else { continue }
                let at: SIMD2<Double> = st.offset + SIMD2(Double(s.cell.x), Double(crossing))
                want[st.name + "|\(s.cell.x)", default: (at, [])].repos.insert(id.repo)
            }
        }
        for (key, arrow) in testingArrows where want[key] == nil {
            arrow.node.removeFromParentNode()
            testingArrows[key] = nil
        }
        for (key, w) in want {
            let arrow = testingArrows[key] ?? {
                let made = TestingArrow()
                made.node.position = v3(w.at.x, 0.014, w.at.y)
                propRoot.addChildNode(made.node)
                testingArrows[key] = made
                return made
            }()
            arrow.repos = w.repos.sorted { (fleet.repoColors[$0] ?? .max, $0) < (fleet.repoColors[$1] ?? .max, $1) }
            roll(arrow)
        }
    }

    private func roll(_ arrow: TestingArrow) {
        for (i, mark) in arrow.marks.enumerated() {
            let wave = clock * TestingArrow.pace + Double(i) / Double(TestingArrow.chevrons)
            let s = wave.truncatingRemainder(dividingBy: 1)
            mark.position.z = CGFloat(TestingArrow.run * (0.5 - s))
            mark.opacity = CGFloat(sin(s * .pi))
            let repo = arrow.repos[Int(wave.rounded(.down)) % arrow.repos.count]
            if mark.geometry?.firstMaterial?.name != repo {
                let m = Props.glowing(NSColor(fleet.color(forRepo: repo)), alpha: 0.85)
                m.name = repo
                mark.geometry?.firstMaterial = m
            }
        }
    }
}
