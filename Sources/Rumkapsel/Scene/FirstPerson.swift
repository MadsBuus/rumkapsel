import AppKit
import SceneKit
import SpriteKit

struct WalkView {
    var focus: SIMD2<Double>
    var height: Double
    var yaw: Double
    var pitch: Double
    var distance: Double
}

final class Walker {
    static let eye = 0.4
    static let radius = 0.13
    static let pace = 1.4, runPace = 3.0
    static let fieldOfView = 68.0
    static let wallHeight = 0.72
    static let railHeight = 0.16
    static let diveSeconds = 1.8, riseSeconds = 1.3
    static let craneReach = 1.5, craneTilt = -0.8
    static let thrust = 3.4, gravity = 1.6, climbLimit = 1.3, ceiling = 6.0
    static let crown = 0.1

    var station: String
    var pos: SIMD2<Double>
    var yaw: Double
    var pitch = -0.08
    var velocity = SIMD2<Double>(0, 0)
    var thrusting = false
    var altitude = 0.0
    var climb = 0.0
    var hulls: [String: StationHull] = [:]
    var arrows: [Signs.Arrow] = []
    var fragments: [SCNNode] = []
    var skins = -1
    var riding: String?
    var orbit = 0.0, craneTilt = Walker.craneTilt
    var view: WalkView
    var settling = 0.0
    var phase = 0.0
    var leaving = false
    var top: (focus: SIMD2<Double>, yaw: Double, pitch: Double, scale: Double)
    var stride = 0.0
    var place = ""
    var placeAt = -10.0
    var builtFor = 0
    var readAt = -1.0
    var anchor: SIMD2<Double>?
    var pushedFor = 0.0
    let walls = SCNNode()
    let dome = SCNNode()
    let sky: SCNNode
    let camera = SCNCamera()
    var stationCamera: SCNCamera?
    let title = SKLabelNode(fontNamed: "HelveticaNeue-Light")
    let subtitle = SKLabelNode(fontNamed: "HelveticaNeue-LightItalic")

    init(station: String, pos: SIMD2<Double>, yaw: Double, top: (focus: SIMD2<Double>, yaw: Double, pitch: Double, scale: Double)) {
        self.station = station; self.pos = pos; self.yaw = yaw; self.top = top
        view = WalkView(focus: pos, height: Walker.eye, yaw: yaw, pitch: -0.08, distance: 0)
        sky = FlightCraft.stars()
        sky.name = "walk stars"
        sky.categoryBitMask = Pick.scenery
        for n in [walls, dome] { n.categoryBitMask = Pick.scenery }
        for l in [title, subtitle] {
            l.horizontalAlignmentMode = .center
            l.verticalAlignmentMode = .baseline
            l.fontColor = Palette.text
            l.alpha = 0
        }
        FlightCraft.film(camera)
        camera.exposureOffset = -0.45
        camera.bloomThreshold = 1.4
        camera.zNear = 0.02
        title.fontSize = 34
        subtitle.fontSize = 14
        subtitle.fontColor = Palette.dim
    }
}

extension StationController {
    func toggleWalk() {
        enqueue { [self] in
            if let w = walker { stepOut(w) } else { stepIn() }
        }
    }

    func toggleMission() {
        enqueue { [self] in
            if let w = walker { stepOut(w); return }
            guard let st = fleet.stations.values.sorted(by: { $0.name < $1.name }).first(where: { !$0.fixtures(in: "kind:mission").isEmpty }),
                  let origin = st.roomOrigin("kind:mission") else { return }
            stepIn(at: st.offset + origin + SIMD2(2.5, 2.6), yaw: 0)
        }
    }

    func stepIn(at point: SIMD2<Double>? = nil, yaw: Double? = nil) {
        guard walker == nil, let station = cameraNode.camera else { return }
        let focus = SIMD2(Double(rig.position.x), Double(rig.position.z))
        let viewYaw = Double(rig.eulerAngles.y)
        let followed = point == nil ? following.flatMap { minions[$0] } : nil
        var start: (station: Station, pos: SIMD2<Double>, yaw: Double)?
        if let point, let st = fleet.stations.values.min(by: { simd_distance(point, $0.offset) < simd_distance(point, $1.offset) }),
           let cell = st.nearestFloor(to: point - st.offset) {
            let q = point - st.offset, middle = SIMD2(Double(cell.x), Double(cell.y))
            let onIt = Cell(x: Int(q.x.rounded()), y: Int(q.y.rounded())) == cell && fits(q, from: middle, in: st)
            start = (st, (onIt ? q : middle) + st.offset, yaw ?? viewYaw)
        } else if let m = followed, let st = fleet.stations[m.station] {
            start = (st, SIMD2(Double(m.node.position.x), Double(m.node.position.z)), m.smoothFacing + .pi)
        } else {
            start = hallwayStart(near: focus, facing: viewYaw)
        }
        guard let start else { return }
        let w = Walker(station: start.station.name, pos: start.pos, yaw: start.yaw,
                       top: (focus, viewYaw, Double(pitchNode.eulerAngles.x), Double(station.orthographicScale)))
        w.riding = followed?.id
        w.view = wantedView(w)
        following = nil
        walker = w
        for n in [w.sky, w.dome, w.walls] { scene.rootNode.addChildNode(n) }
        hud.addChild(w.title); hud.addChild(w.subtitle)
        walkAskedAt = CACurrentMediaTime()
        let signature = walkSignature()
        if let p = walkPieces, p.signature == signature, p.skins == Bulkhead.generation {
            wear(p, on: w)
        } else {
            let floors = fleet.stations.values.map(WalkFloor.init), tints = drawnFloor(), skins = Bulkhead.generation
            let p = timed("walk.build") { WalkPieces.queue.sync { WalkPieces.build(floors, tints: tints, signature: signature, skins: skins) } }
            walkPieces = p
            wear(p, on: w)
        }
        w.camera.categoryBitMask = station.categoryBitMask
        w.stationCamera = station
        cameraNode.camera = w.camera
        poseWalkCamera(w)
    }

    func stepOut(_ w: Walker) {
        guard !w.leaving else { return }
        w.leaving = true
        userPan = w.pos - targetFocus
        w.top = (w.pos, viewYaw + userYaw, userPitch, fitScale(half: targetHalf) / userZoom)
    }

    func walkEscape() {
        guard let w = walker else { return }
        if w.riding != nil { dismount(w) } else { stepOut(w) }
    }

    func ride(minionId id: String) {
        guard let w = walker, !w.leaving, let m = minions[id] else { return }
        w.riding = m.id
        w.station = m.station
        w.orbit = 0; w.craneTilt = Walker.craneTilt
        w.altitude = 0; w.climb = 0; w.thrusting = false
        w.settling = 1.2
    }

    private func dismount(_ w: Walker) {
        w.riding = nil
        w.yaw = w.view.yaw
        w.pitch = -0.08
        w.velocity = .zero
        w.settling = 1
    }

    private func stepOff(_ w: Walker) {
        for n in [w.sky, w.dome, w.walls] { n.removeFromParentNode() }
        for n in w.fragments { n.opacity = 1; n.isHidden = false }
        w.title.removeFromParent(); w.subtitle.removeFromParent()
        walker = nil
        for n in legendNodes + jobNodes { n.alpha = 1 }
        for m in minions.values { m.staticSeen = true }
        guard let camera = w.stationCamera else { return }
        cameraNode.camera = camera
        camera.orthographicScale = w.top.scale
        cameraNode.position = v3(0, 0, 120)
        rig.position = v3(w.top.focus.x, 0, w.top.focus.y)
        rig.eulerAngles = v3(0, w.top.yaw, 0)
        pitchNode.eulerAngles.x = w.top.pitch
    }

    private func hallwayStart(near p: SIMD2<Double>, facing: Double) -> (station: Station, pos: SIMD2<Double>, yaw: Double)? {
        func world(_ st: Station, _ c: Cell) -> SIMD2<Double> { st.offset + SIMD2(Double(c.x), Double(c.y)) }
        guard let st = fleet.stations.values.min(by: {
            (simd_length_squared(world($0, $0.plan.monolith) - p), $0.name) < (simd_length_squared(world($1, $1.plan.monolith) - p), $1.name)
        }) else { return nil }
        let walk = st.walkable, mono = st.plan.monolith
        var best: (cell: Cell, yaw: Double, score: Double)?
        for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
            var reach = 0, at = Cell(x: mono.x + dx, y: mono.y + dy)
            while reach < 4 {
                let n = Cell(x: at.x + dx, y: at.y + dy)
                guard walk.contains(n), st.canStep(from: at, to: n) else { break }
                reach += 1; at = n
            }
            guard reach >= 2 else { continue }
            let yaw = atan2(Double(dx), Double(dy))
            let score = Double(reach) * 0.3 - abs(atan2(sin(yaw - facing), cos(yaw - facing)))
            if best == nil || score > best!.score { best = (at, yaw, score) }
        }
        if let best { return (st, world(st, best.cell), best.yaw) }
        guard let c = walk.min(by: { (simd_length_squared(world(st, $0) - p), $0.x, $0.y) < (simd_length_squared(world(st, $1) - p), $1.x, $1.y) }) else { return nil }
        return (st, world(st, c), facing)
    }

    func tickWalk(dt: Double, move: SIMD2<Double>, turn: Double) -> Bool {
        guard let w = walker else { return false }
        if w.leaving {
            w.phase -= dt / Walker.riseSeconds
            if w.phase <= 0 { stepOff(w); return true }
        } else {
            w.phase = min(1, w.phase + dt / Walker.diveSeconds)
        }
        if let st = fleet.stations[w.station] {
            if let was = w.anchor, was != st.offset {
                let moved = st.offset - was
                w.pos += moved; w.view.focus += moved; w.top.focus += moved
            }
            w.anchor = st.offset
        }
        if let id = w.riding {
            if let m = minions[id], m.state != .leaving || m.opacity > 0.05 {
                w.station = m.station
                w.pos = SIMD2(Double(m.node.position.x), Double(m.node.position.z))
            } else { dismount(w) }
        }
        if w.phase >= 1, !w.leaving {
            if w.riding != nil, move != .zero { dismount(w) }
            if w.riding == nil { fly(w, dt: dt); stride(w, dt: dt, move: move, turn: turn) }
        }
        ease(w, toward: wantedView(w), dt: dt)
        if let p = walkPieces, p.signature != w.builtFor || p.skins != w.skins, p.signature == walkSignature() { wear(p, on: w) }
        poseWalkCamera(w)
        Signs.roll(w.arrows, at: clock)
        showPlace(w)
        hidePixelsBehindWalls(w)
        return true
    }

    func walkLook(_ d: SIMD2<Double>) {
        guard let w = walker, w.phase >= 1, !w.leaving else { return }
        if w.riding != nil {
            w.orbit += d.x
            w.craneTilt = min(-0.08, max(-1.3, w.craneTilt + d.y))
        } else {
            w.yaw += d.x
            w.pitch = min(1.25, max(-1.25, w.pitch + d.y))
        }
    }

    var walkHint: String? {
        guard let w = walker else { return nil }
        if let id = w.riding, let m = minions[id] {
            return "riding along with \(m.home.name) · \(m.words) · wasd to walk from here · esc to let go"
        }
        return "walking · wasd to move, drag to look, shift to run, space to fly · click a minion to ride along · esc to step out"
    }

    private func wantedView(_ w: Walker) -> WalkView {
        if let id = w.riding, let m = minions[id] {
            return WalkView(focus: w.pos, height: m.headHeight * 0.85, yaw: m.smoothFacing + .pi + w.orbit,
                            pitch: w.craneTilt, distance: Walker.craneReach)
        }
        let moving = w.altitude > 0 ? 0 : min(1, simd_length(w.velocity) / Walker.pace)
        let shudder = w.thrusting ? sin(w.stride * 9 + Double(w.altitude) * 40) * 0.004 : 0
        return WalkView(focus: w.pos, height: Walker.eye + w.altitude + abs(sin(w.stride * .pi)) * 0.012 * moving + shudder,
                        yaw: w.yaw, pitch: w.pitch, distance: 0)
    }

    private func ceiling(_ w: Walker) -> Double {
        guard let st = fleet.stations[w.station], let hull = w.hulls[w.station],
              let roof = hull.roof(over: w.pos - st.offset, top: w.altitude + Walker.eye + Walker.crown) else { return Walker.ceiling }
        return roof - Walker.eye - Walker.crown
    }

    private func fly(_ w: Walker, dt: Double) {
        w.climb += ((w.thrusting ? Walker.thrust : 0) - Walker.gravity) * dt
        w.climb = min(Walker.climbLimit, max(-Walker.climbLimit, w.climb))
        let was = w.altitude
        w.altitude += w.climb * dt
        if was > Walker.wallHeight, w.altitude <= Walker.wallHeight, let st = fleet.stations[w.station] {
            let q = w.pos - st.offset
            if !fits(q, from: q, in: st, high: false) {
                w.altitude = Walker.wallHeight + 0.001
                w.climb = 0
                let middle = SIMD2(q.x.rounded(), q.y.rounded())
                w.pos += (middle - q) * min(1, dt * 4)
            }
        }
        if w.altitude <= 0 { w.altitude = 0; w.climb = max(0, w.climb) }
        if w.altitude >= ceiling(w) { w.altitude = max(0, ceiling(w)); w.climb = min(0, w.climb) }
        if w.thrusting { w.stride += dt * 3 }
    }

    private func ease(_ w: Walker, toward want: WalkView, dt: Double) {
        guard w.riding != nil || w.settling > 0 else { w.view = want; return }
        w.settling = max(0, w.settling - dt)
        let k = 1 - exp(-dt * (w.riding != nil ? 6 : 7)), turn = 1 - exp(-dt * (w.riding != nil ? 2.2 : 7))
        var v = w.view
        v.focus += (want.focus - v.focus) * k
        v.height += (want.height - v.height) * k
        v.distance += (want.distance - v.distance) * k
        v.pitch += (want.pitch - v.pitch) * k
        v.yaw += atan2(sin(want.yaw - v.yaw), cos(want.yaw - v.yaw)) * turn
        w.view = v
    }

    private func stride(_ w: Walker, dt: Double, move: SIMD2<Double>, turn: Double) {
        guard let st = fleet.stations[w.station] else { return }
        w.yaw -= turn * dt * 2
        let forward = SIMD2(-sin(w.yaw), -cos(w.yaw)), right = SIMD2(cos(w.yaw), -sin(w.yaw))
        var dir = forward * move.y + right * move.x
        if simd_length(dir) > 0 { dir = simd_normalize(dir) }
        let pace = NSEvent.modifierFlags.contains(.shift) ? Walker.runPace : Walker.pace
        w.velocity += (dir * pace - w.velocity) * (1 - exp(-dt * 9))
        let step = w.velocity * dt
        var q = w.pos - st.offset
        for axis in [SIMD2<Double>(1, 0), SIMD2<Double>(0, 1)] {
            let next = q + axis * simd_dot(step, axis)
            if fits(next, from: q, in: st) { q = next }
        }
        let moved = simd_length(q - (w.pos - st.offset))
        if simd_length(dir) > 0, moved < pace * dt * 0.1 {
            w.pushedFor += dt
            if w.pushedFor > 0.6 { w.pushedFor = -3; logBlocked(at: q, toward: dir, in: st) }
        } else if w.pushedFor > 0 { w.pushedFor = 0 }
        w.pos = q + st.offset
        w.stride += moved * 2.4
    }

    private func logBlocked(at q: SIMD2<Double>, toward dir: SIMD2<Double>, in st: Station) {
        let here = Cell(x: Int(q.x.rounded()), y: Int(q.y.rounded()))
        let ahead = q + dir * (Walker.radius + 0.05)
        let there = Cell(x: Int(ahead.x.rounded()), y: Int(ahead.y.rounded()))
        var why: [String] = []
        if !st.walkable.contains(here) { why.append("standing off the floor") }
        if !open(from: here, to: there, in: st) { why.append(st.walkable.contains(there) ? "no doorway" : "no floor beyond") }
        if st.obstacles.contains(Station.sub(ahead)) { why.append("a prop") }
        let near = minions.values.filter { $0.station == st.name && simd_length(SIMD2(Double($0.node.position.x), Double($0.node.position.z)) - st.offset - q) < Walker.radius + 0.15 }
        if !near.isEmpty { why.append("minion " + near.map(\.id).joined(separator: ", ")) }
        StationLog.write("walk", "blocked at \(here.x),\(here.y) toward \(there.x),\(there.y) on \(st.name): \(why.isEmpty ? "nothing found" : why.joined(separator: "; "))")
    }

    private func fits(_ q: SIMD2<Double>, from: SIMD2<Double>, in st: Station, high: Bool? = nil) -> Bool {
        let r = Walker.radius
        let here = Cell(x: Int(from.x.rounded()), y: Int(from.y.rounded()))
        let corners = [SIMD2(0, 0), SIMD2(r, r), SIMD2(r, -r), SIMD2(-r, r), SIMD2(-r, -r)]
        if let w = walker, let hull = w.hulls[st.name] {
            let top = w.altitude + Walker.eye + Walker.crown
            for k in corners { if let roof = hull.roof(over: q + k, top: top), roof < top { return false } }
        }
        if high ?? ((walker?.altitude ?? 0) > Walker.wallHeight) {
            let under = walker?.hulls[st.name]?.inside ?? []
            return corners.allSatisfy { k in
                let c = Cell(x: Int((k + q).x.rounded()), y: Int((k + q).y.rounded()))
                return st.walkable.contains(c) || under.contains(c)
            }
        }
        for k in corners {
            let p = q + k
            if !open(from: here, to: Cell(x: Int(p.x.rounded()), y: Int(p.y.rounded())), in: st) { return false }
        }
        func inProps(_ p: SIMD2<Double>) -> Int { corners.filter { st.obstacles.contains(Station.sub(p + $0 * 0.8)) }.count }
        guard inProps(q) <= inProps(from) else { return false }
        for m in minions.values where m.station == st.name && m.opacity > 0.5 {
            let at = SIMD2(Double(m.node.position.x), Double(m.node.position.z)) - st.offset
            let near = r + 0.12
            if simd_length(q - at) < near && simd_length(q - at) < simd_length(from - at) { return false }
        }
        return true
    }

    private func open(from a: Cell, to b: Cell, in st: Station) -> Bool {
        if a == b { return true }
        let walk = st.walkable
        guard walk.contains(b) else { return false }
        if a.x != b.x && a.y != b.y {
            let p = Cell(x: b.x, y: a.y), q = Cell(x: a.x, y: b.y)
            return walk.contains(p) && st.canStep(from: a, to: p) && st.canStep(from: p, to: b)
                && walk.contains(q) && st.canStep(from: a, to: q) && st.canStep(from: q, to: b)
        }
        return abs(a.x - b.x) + abs(a.y - b.y) == 1 && st.canStep(from: a, to: b)
    }

    private func poseWalkCamera(_ w: Walker) {
        let camera = w.camera, v = w.view
        func ease(_ x: Double) -> Double { let t = min(1, max(0, x)); return t * t * t * (t * (t * 6 - 15) + 10) }
        let t = w.phase
        let focus = w.top.focus + (v.focus - w.top.focus) * ease(t / 0.7)
        let yaw = w.top.yaw + atan2(sin(v.yaw - w.top.yaw), cos(v.yaw - w.top.yaw)) * ease(t / 0.8)
        let pitch = w.top.pitch + (v.pitch - w.top.pitch) * ease((t - 0.35) / 0.65)
        let lens = exp(log(1.5) + (log(Walker.fieldOfView) - log(1.5)) * ease(t)) * .pi / 180
        let distance = w.top.scale / tan(lens / 2) * (1 - ease(t)) + v.distance * ease(t)
        let moving = w.riding == nil ? min(1, simd_length(w.velocity) / Walker.pace) : 0
        camera.fieldOfView = CGFloat(lens * 180 / .pi)
        camera.zNear = max(0.02, distance * 0.01)
        camera.zFar = distance + 600
        cameraNode.position = v3(0, 0, distance)
        rig.position = v3(focus.x, v.height * ease(t), focus.y)
        rig.eulerAngles.y = yaw
        rig.eulerAngles.z = cos(w.stride * .pi) * 0.004 * moving
        pitchNode.eulerAngles.x = pitch
        w.sky.position = cameraNode.worldPosition
        w.sky.opacity = ease((t - 0.3) / 0.6)
        let rising = ease((t - 0.4) / 0.6)
        w.walls.isHidden = rising <= 0
        w.walls.scale.y = max(0.001, rising)
        w.walls.opacity = ease((t - 0.4) / 0.3)
        w.dome.opacity = ease((t - 0.45) / 0.55)
        let fragments = 1 - ease(t / 0.5)
        for n in w.fragments { n.opacity = fragments; n.isHidden = fragments <= 0 }
        let film = ease((t - 0.2) / 0.8)
        camera.vignettingIntensity = 0.6 * film
        camera.colorFringeIntensity = 0.5 * film
        camera.grainIntensity = 0.06 * film
        camera.bloomIntensity = 0.9 * film
    }

    func fadeOverlay() {
        guard let w = walker else { return }
        let k = 1 - min(1, max(0, w.phase / 0.6))
        for n in legendNodes + jobNodes { n.alpha = k }
        for (l, _) in eventLabels { l.alpha *= k }
    }

    // MARK: seeing

    private func inSight(of target: SIMD2<Double>, in st: Station) -> Bool {
        let eye = cameraNode.worldPosition
        guard Double(eye.y) < Walker.wallHeight else { return true }
        let a = SIMD2(Double(eye.x), Double(eye.z)) - st.offset, b = target - st.offset
        var at = Cell(x: Int(a.x.rounded()), y: Int(a.y.rounded()))
        let steps = Int(simd_length(b - a) / 0.1) + 1
        for i in 1...steps {
            let p = a + (b - a) * (Double(i) / Double(steps))
            let c = Cell(x: Int(p.x.rounded()), y: Int(p.y.rounded()))
            guard c != at else { continue }
            if c == st.plan.monolith || !open(from: at, to: c, in: st) { return false }
            at = c
        }
        return true
    }

    private func hidePixelsBehindWalls(_ w: Walker) {
        for m in minions.values {
            guard m.bathing, let st = fleet.stations[m.station] else { m.staticSeen = true; continue }
            m.staticSeen = inSight(of: SIMD2(Double(m.node.position.x), Double(m.node.position.z)), in: st)
        }
    }

    func walkerAt(door: SCNNode, in st: Station, half: Double) -> Bool {
        guard let w = walker, w.riding == nil, w.station == st.name else { return false }
        let q = w.pos - st.offset
        return abs(q.x - (Double(door.position.x) - st.offset.x)) < half && abs(q.y - (Double(door.position.z) - st.offset.y)) < 0.9
    }

    // MARK: the walls and the dome

    func walkSignature() -> Int {
        if walkSignatureAt == lastRebuildAt, let known = walkSignatureKnown { return known }
        var h = Hasher()
        for st in fleet.stations.values.sorted(by: { $0.name < $1.name }) {
            h.combine(st.name); h.combine(st.offset.x); h.combine(st.offset.y)
            for c in st.walkable.sorted(by: { ($0.y, $0.x) < ($1.y, $1.x) }) {
                h.combine(c.x); h.combine(c.y)
                h.combine(st.canStep(from: c, to: Cell(x: c.x + 1, y: c.y))); h.combine(st.canStep(from: c, to: Cell(x: c.x, y: c.y + 1)))
                if let room = st.room(at: c) { h.combine(room.key); h.combine(room.repo) }
            }
        }
        walkSignatureAt = lastRebuildAt
        walkSignatureKnown = h.finalize()
        return walkSignatureKnown!
    }

    private func wear(_ p: WalkPieces, on w: Walker) {
        w.walls.childNodes.forEach { $0.removeFromParentNode() }
        w.dome.childNodes.forEach { $0.removeFromParentNode() }
        w.walls.addChildNode(p.walls)
        w.dome.addChildNode(p.dome)
        w.arrows = p.arrows
        w.hulls = p.hulls
        w.fragments = statics.tagged("hull")
        w.builtFor = p.signature
        w.skins = p.skins
    }

    func prepareWalk() {
        guard walkPiecesFor == nil, CACurrentMediaTime() - lastRebuildAt >= 1.5 || walkPieces == nil else { return }
        let signature = walkSignature(), skins = Bulkhead.generation
        guard walkPieces?.signature != signature || walkPieces?.skins != skins else { return }
        walkPiecesFor = signature
        let floors = fleet.stations.values.map(WalkFloor.init), tints = drawnFloor()
        WalkPieces.queue.async { [weak self] in
            let p = WalkPieces.build(floors, tints: tints, signature: signature, skins: skins)
            self?.view.prepare([p.walls, p.dome]) { _ in
                self?.enqueue { self?.walkPieces = p; self?.walkPiecesFor = nil }
            }
        }
    }

    private func drawnFloor() -> [Cell: NSColor] {
        var out: [Cell: NSColor] = [:]
        statics.enumerate { n in
            guard let p = n.geometry as? SCNPlane, p.width == 1, p.height == 1, abs(Double(n.eulerAngles.x) + .pi / 2) < 0.01,
                  let c = p.firstMaterial?.diffuse.contents as? NSColor else { return }
            let at = n.worldPosition
            guard abs(Double(at.y)) < 0.05 else { return }
            out[Cell(x: Int(Double(at.x).rounded()), y: Int(Double(at.z).rounded()))] = c
        }
        return out
    }

    // MARK: where you are

    private func showPlace(_ w: Walker) {
        if let st = fleet.stations[w.station], w.phase >= 1 {
            let q = w.pos - st.offset
            let (name, detail) = placeName(st, Cell(x: Int(q.x.rounded()), y: Int(q.y.rounded())))
            if name != w.place {
                w.place = name; w.placeAt = clock
                w.title.text = name; w.subtitle.text = detail ?? ""
            }
        }
        let age = clock - w.placeAt
        let alpha = w.leaving ? 0 : min(1, age / 0.35) * min(1, max(0, (3.2 - age) / 0.8))
        w.title.alpha = alpha; w.subtitle.alpha = alpha
        w.title.position = CGPoint(x: hud.size.width / 2, y: hud.size.height * 0.62)
        w.subtitle.position = CGPoint(x: hud.size.width / 2, y: hud.size.height * 0.62 - 24)
    }

    private func placeName(_ st: Station, _ c: Cell) -> (String, String?) {
        if let room = st.room(at: c) {
            switch room.key {
            case "kind:lounge": return ("The lounge", nil)
            case "kind:quarters": return ("The quarters", nil)
            case "kind:bath": return ("The bath", nil)
            case "kind:gym": return ("The gym", nil)
            case "kind:galley": return ("The galley", "coffee, and a bite now and then")
            default:
                let here = minions.values.filter { $0.station == st.name && $0.place == .room(room.key) && $0.state != .leaving }
                let doing = here.first(where: \.busy).map { $0.words }
                return (room.name, [room.repo, doing].compactMap { $0 }.joined(separator: " · "))
            }
        }
        if st.hangarCells.contains(c) { return ("The bay", "where the shuttles land") }
        if st.hall.padCells.contains(c) { return ("The pad", "where releases lift off") }
        if st.hall.storageCells.contains(c) { return ("Storage", "merged work waiting for a release") }
        if st.hall.deconCells.contains(c) { return ("Decon", nil) }
        if st.hall.deckCells.contains(c) { return ("The deck", "work on staging") }
        if st.coreCells.contains(c) { return ("The plaza", nil) }
        return ("The hallway", nil)
    }

    func idleFacing(_ m: Minion) -> Double {
        if let w = walker, w.riding == nil, w.phase > 0.5, m.station == w.station {
            let d = w.pos - SIMD2(Double(m.node.position.x), Double(m.node.position.z))
            if simd_length(d) < 4 { return atan2(d.x, d.y) }
        }
        return Double(rig.eulerAngles.y)
    }
}

enum WallPanel {
    static func key(_ c: NSColor) -> String {
        guard let s = c.usingColorSpace(.sRGB) else { return "?" }
        return String(format: "%.2f/%.2f/%.2f", s.redComponent, s.greenComponent, s.blueComponent)
    }

    static let bareDeck: SCNGeometry = {
        let g = SCNPlane(width: 1, height: 1)
        let m = lit(NSColor(rgb: Props.hullPlate).darker(0.35))
        g.firstMaterial = m
        return g
    }()

    static let hullGlass: SCNMaterial = {
        let n = 128
        let image = Textures.draw(n, n) { ctx, w, h in
            ctx.setFillColor(NSColor(rgb: (0.55, 0.68, 0.85), alpha: 0.03).cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
            ctx.setStrokeColor(NSColor(rgb: (0.7, 0.74, 0.82), alpha: 0.28).cgColor)
            ctx.setLineWidth(2)
            ctx.stroke(CGRect(x: 0, y: 0, width: w, height: h))
        }
        let m = glass.copy() as! SCNMaterial
        m.diffuse.contents = image
        m.diffuse.wrapS = .repeat
        m.diffuse.wrapT = .repeat
        return m
    }()

    static let glass: SCNMaterial = {
        let n = 128
        let image = Textures.draw(n, n) { ctx, w, h in
            ctx.setFillColor(NSColor(rgb: (0.55, 0.68, 0.85), alpha: 0.07).cgColor)
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
            ctx.setStrokeColor(NSColor(rgb: (0.78, 0.8, 0.86), alpha: 0.85).cgColor)
            ctx.setLineWidth(5)
            ctx.stroke(CGRect(x: 0, y: 0, width: w, height: h))
            ctx.setStrokeColor(NSColor(rgb: (0.78, 0.8, 0.86), alpha: 0.25).cgColor)
            ctx.setLineWidth(1.5)
            ctx.stroke(CGRect(x: 9, y: 9, width: w - 18, height: h - 18))
        }
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = image
        m.diffuse.mipFilter = .linear
        m.transparencyMode = .aOne
        m.isDoubleSided = true
        m.writesToDepthBuffer = false
        return m
    }()
}
