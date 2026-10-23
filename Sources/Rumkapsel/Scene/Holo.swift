import AppKit
import SceneKit

struct HoloSky: Equatable {
    enum Checks: Equatable { case none, running, passed, failed }
    struct Planet: Equatable { let repo: String; let color: RGB }
    struct Moon: Equatable { let id: Int; let repo: String; let stage: Stage; let checks: Checks; let commits: Int }

    var planets: [Planet] = []
    var moons: [Moon] = []

    static let open: [Stage] = [.working, .ready, .stored, .qa, .cleared]

    static func make(repos: [(repo: String, color: RGB)], records: [WorkBook.Record],
                     checks: (WorkBook.Record) -> Checks, commits: (WorkBook.Record) -> Int) -> HoloSky {
        let names = Set(repos.map(\.repo))
        var sky = HoloSky(planets: repos.map { Planet(repo: $0.repo, color: $0.color) })
        sky.moons = records.filter { names.contains($0.repo) && $0.stage.map(open.contains) == true }
            .sorted { $0.id < $1.id }
            .map { Moon(id: $0.id, repo: $0.repo, stage: $0.stage!, checks: checks($0), commits: commits($0)) }
        return sky
    }

    static func orbit(_ stage: Stage) -> Double {
        switch stage {
        case .inbound, .working, .ready: return 0.055
        case .stored: return 0.067
        case .qa: return 0.079
        case .cleared, .shipped: return 0.091
        }
    }
}

final class HoloView {
    final class MoonNode {
        let node: SCNNode
        let ring: SCNNode
        var moon: HoloSky.Moon
        var radius: Double
        var passedAt: Double?
        var falling: Double?
        init(node: SCNNode, ring: SCNNode, moon: HoloSky.Moon) {
            self.node = node; self.ring = ring; self.moon = moon; radius = HoloSky.orbit(moon.stage)
        }
    }

    struct Blip { let node: SCNNode; let moon: Int; let born: Double }

    let root: SCNNode
    var shown: HoloSky?
    var planets: [String: SCNNode] = [:]
    var pulses: [String: Double] = [:]
    var moons: [Int: MoonNode] = [:]
    var blips: [Blip] = []

    static let centre = 0.13, inner = 0.13, outer = 0.42, reach = 0.49, speed = 0.07, planet = 0.042, moon = 0.012, blip = 0.7

    init(root: SCNNode) { self.root = root }

    static func glow(_ color: NSColor) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.blendMode = .alpha
        m.transparency = 0.99
        m.diffuse.contents = NSColor.black
        m.shaderModifiers = [.fragment: """
            #pragma arguments
            float3 tint;
            #pragma body
            float rim = 1.0 - saturate(dot(normalize(_surface.normal), normalize(_surface.view)));
            float band = 0.82 + 0.18 * step(0.5, fract(_surface.position.y * 90.0 - scn_frame.time * 0.8));
            _output.color = float4(saturate(tint * (0.8 + 0.6 * pow(rim, 1.4)) * band), 1.0);
            """]
        let c = color.usingColorSpace(.deviceRGB) ?? color
        m.setValue(SCNVector3(c.redComponent, c.greenComponent, c.blueComponent), forKey: "tint")
        return m
    }

    struct Orbit { let a: Double, e: Double, tilt: Double, node: Double, phase: Double }

    var orbitLines: SCNNode?
    var count: Int { max(1, shown?.planets.count ?? 1) }
    var scale: Double { min(1, 6 / Double(count)).squareRoot() }

    func slot(_ repo: String) -> Int { shown?.planets.firstIndex { $0.repo == repo } ?? 0 }

    func orbit(_ repo: String) -> Orbit {
        let k = Double(slot(repo)), n = Double(count)
        let s = Double(Planets.seed(repo) % 1000) / 1000
        let e = 0.04 + 0.08 * s
        let a = min(count == 1 ? (Self.inner + Self.outer) / 2 : Self.inner + k / (n - 1) * (Self.outer - Self.inner), Self.reach / (1 + e))
        return Orbit(a: a, e: e, tilt: (s - 0.5) * 0.45, node: s * .pi * 6, phase: k * 2.39996)
    }

    func along(_ o: Orbit, _ angle: Double) -> SIMD3<Double> {
        let b = o.a * (1 - o.e * o.e).squareRoot()
        let x = o.a * (cos(angle) - o.e), z = b * sin(angle)
        let y = z * sin(o.tilt), zt = z * cos(o.tilt)
        return SIMD3(x * cos(o.node) + zt * sin(o.node), Self.centre + y, -x * sin(o.node) + zt * cos(o.node))
    }

    func planetAt(_ repo: String, clock: Double) -> SIMD3<Double> {
        let o = orbit(repo)
        return along(o, o.phase + clock * Self.speed * pow(Self.inner / o.a, 1.5))
    }

    private func drawOrbits() {
        orbitLines?.removeFromParentNode()
        let n = SCNNode()
        for p in shown?.planets ?? [] {
            let o = orbit(p.repo)
            let points = (0..<96).map { k -> SCNVector3 in let q = along(o, Double(k) / 96 * .pi * 2); return SCNVector3(q.x, q.y, q.z) }
            let idx = (0..<96).flatMap { [Int32($0), Int32(($0 + 1) % 96)] }
            let g = SCNGeometry(sources: [SCNGeometrySource(vertices: points)], elements: [SCNGeometryElement(indices: idx, primitiveType: .line)])
            g.firstMaterial = MissionRoom.holo(NSColor(p.color).lighter(0.3), 0.14)
            n.addChildNode(SCNNode(geometry: g))
        }
        root.addChildNode(n)
        orbitLines = n
    }

    func moonAt(_ m: MoonNode, clock: Double) -> SIMD3<Double> {
        let p = planetAt(m.moon.repo, clock: clock)
        let phase = Double(m.moon.id % 97) / 97 * .pi * 2
        let a = phase + clock * 0.22 * (0.05 / max(0.03, m.radius))
        let r = m.radius * scale * (1 - (m.falling ?? 0))
        return p + SIMD3(sin(a) * r, 0, cos(a) * r)
    }

    func show(_ sky: HoloSky, clock: Double) {
        let was = shown
        shown = sky
        for p in sky.planets where planets[p.repo] == nil {
            let n = SCNNode(geometry: SCNSphere(radius: Self.planet))
            n.geometry!.firstMaterial = Self.glow(NSColor(p.color))
            root.addChildNode(n)
            planets[p.repo] = n
        }
        for (repo, n) in planets where !sky.planets.contains(where: { $0.repo == repo }) {
            n.removeFromParentNode()
            planets[repo] = nil
        }
        if was?.planets != sky.planets || orbitLines == nil { drawOrbits() }
        for m in sky.moons {
            let color = NSColor(sky.planets.first { $0.repo == m.repo }?.color ?? RGB(r: 0.4, g: 0.9, b: 1))
            if let shownMoon = moons[m.id] {
                if m.commits > shownMoon.moon.commits, was != nil { fire(from: shownMoon, clock: clock) }
                if m.checks == .passed, shownMoon.moon.checks != .passed { shownMoon.passedAt = clock }
                if m.checks != shownMoon.moon.checks { paint(shownMoon.ring, m.checks) }
                shownMoon.moon = m
                shownMoon.falling = nil
                continue
            }
            let node = SCNNode(geometry: SCNSphere(radius: Self.moon))
            node.geometry!.firstMaterial = Self.glow(color.lighter(0.25))
            let ring = SCNNode(geometry: SCNTorus(ringRadius: Self.moon * 2, pipeRadius: 0.0025))
            node.addChildNode(ring)
            paint(ring, m.checks)
            root.addChildNode(node)
            let made = MoonNode(node: node, ring: ring, moon: m)
            if m.checks == .passed { made.passedAt = clock - 10 }
            moons[m.id] = made
        }
        for (id, m) in moons where m.falling == nil && !sky.moons.contains(where: { $0.id == id }) { m.falling = 0 }
    }

    private func paint(_ ring: SCNNode, _ checks: HoloSky.Checks) {
        switch checks {
        case .none: ring.isHidden = true
        case .running: ring.isHidden = false; ring.geometry!.firstMaterial = MissionRoom.holo(NSColor(rgb: (1, 0.85, 0.4)), 0.8)
        case .passed: ring.isHidden = false; ring.geometry!.firstMaterial = MissionRoom.holo(NSColor(rgb: (0.4, 1, 0.55)), 0.8)
        case .failed: ring.isHidden = false; ring.geometry!.firstMaterial = MissionRoom.holo(NSColor(rgb: (1, 0.3, 0.25)), 0.95)
        }
    }

    private func fire(from m: MoonNode, clock: Double) {
        let n = SCNNode(geometry: SCNSphere(radius: 0.008))
        n.geometry!.firstMaterial = MissionRoom.holo(NSColor.white, 1)
        root.addChildNode(n)
        blips.append(Blip(node: n, moon: m.moon.id, born: clock))
    }

    func step(clock: Double, dt: Double) {
        for (repo, n) in planets {
            let p = planetAt(repo, clock: clock)
            n.simdPosition = SIMD3(Float(p.x), Float(p.y), Float(p.z))
            let pulse = pulses[repo].map { max(0, 1 - (clock - $0) / 0.6) } ?? 0
            let s = scale * (1 + pulse * 0.35)
            n.scale = SCNVector3(s, s, s)
        }
        for (id, m) in moons {
            let target = HoloSky.orbit(m.moon.stage)
            m.radius += (target - m.radius) * min(1, dt * 1.5)
            if let f = m.falling {
                m.falling = f + dt / 1.2
                if f >= 1 {
                    m.node.removeFromParentNode()
                    moons[id] = nil
                    pulses[m.moon.repo] = clock
                    continue
                }
            }
            let p = moonAt(m, clock: clock)
            m.node.simdPosition = SIMD3(Float(p.x), Float(p.y), Float(p.z))
            m.node.scale = SCNVector3(scale, scale, scale)
            switch m.moon.checks {
            case .running: m.ring.eulerAngles = SCNVector3(clock * 2.2, clock * 1.3, 0)
            case .passed:
                let fade = m.passedAt.map { max(0, 1 - (clock - $0) / 3) } ?? 0
                m.ring.isHidden = fade <= 0
                m.ring.opacity = CGFloat(fade)
            default: break
            }
        }
        blips.removeAll { b in
            guard let m = moons[b.moon] else { b.node.removeFromParentNode(); return true }
            let t = (clock - b.born) / Self.blip
            if t >= 1 {
                b.node.removeFromParentNode()
                pulses[m.moon.repo] = clock
                return true
            }
            let from = moonAt(m, clock: clock), to = planetAt(m.moon.repo, clock: clock)
            let e = t * t * (3 - 2 * t)
            let p = from + (to - from) * e + SIMD3(0, sin(t * .pi) * 0.03, 0)
            b.node.simdPosition = SIMD3(Float(p.x), Float(p.y), Float(p.z))
            return false
        }
    }
}

extension StationController {
    func holoSky(_ station: Station) -> HoloSky {
        let repos = Set(world.repoRoots.values.filter { $0.station == station.name }.map(\.repo))
            .sorted { (fleet.repoColors[$0] ?? .max, $0) < (fleet.repoColors[$1] ?? .max, $1) }
        let roots = Dictionary(world.repoRoots.filter { $0.value.station == station.name }.map { ($0.value.repo, $0.key) }, uniquingKeysWith: { a, _ in a })
        return HoloSky.make(repos: repos.map { ($0, fleet.color(forRepo: $0)) }, records: repos.flatMap { world.works.records(repo: $0) },
            checks: { r in
                guard let root = roots[r.repo], let n = r.pulls.filter({ $0.value == "OPEN" }).keys.min(),
                      let pr = self.github.pulls.pull(number: n, repoRoot: root) else { return .none }
                switch pr.checks {
                case "pending": return .running
                case "failure": return .failed
                case "success": return .passed
                default: return .none
                }
            },
            commits: { r in
                r.officeKeys.lazy.compactMap { station.rooms[$0]?.worktree }.compactMap { self.github.git.commitsAhead(worktree: $0) }.first ?? 0
            })
    }

    func tendHolos() {
        for (name, view) in holos {
            guard let station = fleet.stations[name] else { continue }
            let sky = holoSky(station)
            if sky != view.shown { view.show(sky, clock: clock) }
        }
    }

    func stepHolos(dt: Double) {
        for view in holos.values { view.step(clock: clock, dt: dt) }
    }
}
