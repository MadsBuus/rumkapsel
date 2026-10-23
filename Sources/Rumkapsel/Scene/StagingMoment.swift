import AppKit
import SceneKit

struct StagingBeat {
    let at: Double
    let live: Bool
    static let flash = 1.5, glow = 6.0, hold = 5.0
}

extension StationController {
    func stagingStarted(station: String, repo: String, expected: Double, elapsed: Double) {
        stagingRuns[station + "|" + repo] = (clock - elapsed, expected)
        stagingBeats[station + "|" + repo] = nil
    }

    func stagingEnded(station: String, repo: String, outcome: DeployOutcome) {
        let key = station + "|" + repo, live = outcome == .live
        let run = stagingRuns.removeValue(forKey: key)
        let took = run.map { clock - $0.started }
        if live {
            let pace = run.flatMap { r in took.map { $0 < r.usual * 0.9 ? ", quicker than usual" : $0 > r.usual * 1.15 ? ", slower than usual" : "" } } ?? ""
            stagingDue[key] = "\(repo) is live on staging" + (took.map { " · " + Mission.duration($0) + pace } ?? "")
            if rocketView(station: station, repo: repo) == nil { celebrate(station: station, repo: repo, nil) }
        } else {
            stagingDue[key] = nil
            stagingBeats[key] = StagingBeat(at: clock, live: false)
            logEvent("\(repo)'s staging build failed" + (took.map { " after " + Mission.duration($0) } ?? ""))
            drone.thud()
            guard let v = rocketView(station: station, repo: repo) else { return }
            burst(v, count: 10, out: 0.4, rise: 0.5, life: 2, grow: 2)
            hold(station, on: v)
        }
    }

    func stagingWhole(_ st: Station, _ r: ShownRocket, _ v: RocketView) {
        guard r.kind == .release, !r.welding, stagingDue[st.name + "|" + r.repo] != nil else { return }
        celebrate(station: st.name, repo: r.repo, v)
    }

    private func celebrate(station: String, repo: String, _ v: RocketView?) {
        let key = station + "|" + repo
        guard let line = stagingDue.removeValue(forKey: key) else { return }
        stagingBeats[key] = StagingBeat(at: clock, live: true)
        logEvent(line)
        for (k, seed) in [0, 2, 4, 7].enumerated() { after(Double(k) * 0.14) { [weak self] in self?.drone.ping(seed: seed) } }
        for m in minions.values where m.station == station && m.state == .settled {
            let atTable = m.using?.room == "kind:mission" && m.sittingOn == nil
            let tester: Bool = { if case .qa = m.current?.kind { return true }; return false }()
            if atTable || tester { play(.hop(m.id)) }
        }
        guard let v else { return }
        burst(v, count: 24, out: 1.1, rise: 0.08, life: 1.3, grow: 3.5)
        if Looks.current.workSparks {
            let base = v.node.presentation.worldPosition
            throwSparks(at: SCNVector3(base.x, base.y + CGFloat(v.node.boundingBox.max.y) * 0.8, base.z), from: v.node, count: 24)
        }
        hold(station, on: v)
    }

    private func rocketView(station: String, repo: String) -> RocketView? {
        rocketViews.first { k, _ in
            let p = RocketKey.parts(k)
            return p.station == station && p.repo == repo && p.hotfix == nil
        }?.value
    }

    private func burst(_ v: RocketView, count: Int, out: Double, rise: Double, life: Double, grow: Double) {
        let base = v.node.presentation.worldPosition
        let at = SIMD3(Double(base.x), Double(base.y) + RocketGeometry.hullBase, Double(base.z))
        for k in 0..<count {
            let a = Double(k) / Double(count) * 2 * .pi
            emitPuff(at: at + SIMD3(sin(a), 0, cos(a)) * RocketGeometry.radius, vel: SIMD3(sin(a), rise, cos(a)) * out, life: life, grow: grow)
        }
    }

    private func hold(_ station: String, on v: RocketView) {
        let base = v.node.presentation.worldPosition
        feedHolds[station] = (SIMD3(Double(base.x), Double(base.y), Double(base.z)), clock + StagingBeat.hold)
    }

    func stagingBeat(station: String, repo: String) -> StagingBeat? {
        guard let b = stagingBeats[station + "|" + repo], clock - b.at < (b.live ? StagingBeat.glow : .infinity) else { return nil }
        return b
    }

    func noseLamp(_ st: Station, _ r: ShownRocket, _ v: RocketView, progress: Double?) {
        let beat = r.kind == .release ? stagingBeat(station: st.name, repo: r.repo) : nil
        let failed = r.kind == .release && st.facts.staging[r.repo]?.deploy == .failed
        let color: NSColor?
        if let p = progress {
            let rate = p > StagingFact.late ? 3.0 : 1.0
            color = (clock * rate).truncatingRemainder(dividingBy: 1) < 0.5 ? Props.amberLamp : Props.amberLampOff
        } else if beat?.live == true {
            color = Props.passedGreen
        } else if failed {
            color = Props.failRed
        } else {
            color = nil
        }
        let lamp = v.node.childNode(withName: "noseLamp", recursively: false) ?? {
            let n = SCNNode(geometry: SCNSphere(radius: 0.035))
            n.geometry!.firstMaterial = flat(.black)
            n.name = "noseLamp"
            n.position = v3(0, Double(v.node.boundingBox.max.y) + 0.025, 0)
            v.node.addChildNode(n)
            return n
        }()
        lamp.isHidden = color == nil
        if let color {
            lamp.geometry?.firstMaterial?.diffuse.contents = color
            lamp.geometry?.firstMaterial?.emission.contents = color
        }
    }
}
