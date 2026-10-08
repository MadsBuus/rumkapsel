// Walking the station at a minion's eye height. The camera dives out of the station's view, the borders
// rise into walls under a dome, and the floor is walked by the minions' own rules: the same walkable
// cells, the same doorways, the same props in the way. A click on a minion rides along behind it on a crane.

import AppKit
import SceneKit
import SpriteKit

/// Where the walk's camera is: the point it is on, its height there, turn, tilt, and how far it hangs back.
struct WalkView {
    var focus: SIMD2<Double>
    var height: Double
    var yaw: Double
    var pitch: Double
    var distance: Double
}

/// Whoever walks the station, and what is drawn only while they do.
final class Walker {
    /// A minion's visor: just under the top of a body half a tile tall.
    static let eye = 0.4
    /// Half a body's width, so a shoulder never goes through a wall.
    static let radius = 0.13
    static let pace = 1.4, runPace = 3.0
    static let fieldOfView = 68.0
    static let wallHeight = 0.72
    /// Where the floor is outside, the bay and the pad: a rail you can see space over.
    static let railHeight = 0.16
    static let diveSeconds = 1.8, riseSeconds = 1.3
    /// The crane: how far behind the minion it hangs, and how steeply it looks down by default.
    static let craneReach = 1.5, craneTilt = -0.8

    var station: String
    /// Where you stand, in world x/z; while riding, where the minion stands.
    var pos: SIMD2<Double>
    var yaw: Double
    var pitch = -0.08
    var velocity = SIMD2<Double>(0, 0)
    /// The minion the crane rides behind, while it does.
    var riding: String?
    /// The crane swung round the minion and tilted, by drags.
    var orbit = 0.0, craneTilt = Walker.craneTilt
    /// The camera as shown, eased toward where it should be; seconds left of easing after a change of mode.
    var view: WalkView
    var settling = 0.0
    /// 0 up in the station's view, 1 at eye height; it runs back to 0 on the way out.
    var phase = 0.0
    var leaving = false
    /// The station's view at the top of the dive: where it looked, its turn and tilt, its half-height.
    var top: (focus: SIMD2<Double>, yaw: Double, pitch: Double, scale: Double)
    var stride = 0.0
    var place = ""
    var placeAt = -10.0
    /// The floor the walls were built for, and the offset your station had when last looked at: the fleet
    /// moves a station sideways when another one grows, and you move with it.
    var builtFor = ""
    var anchor: SIMD2<Double>?
    /// How long you have been pushing against something, for the log.
    var pushedFor = 0.0
    let walls = SCNNode()
    let dome = SCNNode()
    let sky: SCNNode
    /// The camera worn while walking, the flight's film look on it; the station's waits until you step out.
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
        // The station is lit far brighter than space: held down, the white suits keep their seams.
        camera.exposureOffset = -0.45
        camera.bloomThreshold = 1.4
        camera.zNear = 0.02
        title.fontSize = 34
        subtitle.fontSize = 14
        subtitle.fontColor = Palette.dim
    }
}

extension StationController {
    /// In or out of the station on foot: `f` and the View menu.
    func toggleWalk() {
        enqueue { [self] in
            if let w = walker { stepOut(w) } else { stepIn() }
        }
    }

    /// Down into the station where the view is looking, or onto the crane behind the minion it follows.
    func stepIn() {
        guard walker == nil, let station = cameraNode.camera else { return }
        let focus = SIMD2(Double(rig.position.x), Double(rig.position.z))
        let viewYaw = Double(rig.eulerAngles.y)
        let followed = following.flatMap { minions[$0] }
        var start: (station: Station, pos: SIMD2<Double>, yaw: Double)?
        if let m = followed, let st = fleet.stations[m.station] {
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
        buildWalls(w)
        buildDome(w)
        w.camera.categoryBitMask = station.categoryBitMask
        w.stationCamera = station
        cameraNode.camera = w.camera
        poseWalkCamera(w)
    }

    /// Back up into the station's view, centred on where you got to, at the turn and zoom you left it at.
    func stepOut(_ w: Walker) {
        guard !w.leaving else { return }
        w.leaving = true
        userPan = w.pos - targetFocus
        w.top = (w.pos, viewYaw + userYaw, userPitch, fitScale(half: targetHalf) / userZoom)
    }

    /// Esc: off the crane onto your own feet first, then out.
    func walkEscape() {
        guard let w = walker else { return }
        if w.riding != nil { dismount(w) } else { stepOut(w) }
    }

    /// Onto the crane behind a minion: a click on one while walking.
    func ride(minionId id: String) {
        guard let w = walker, !w.leaving, let m = minions[id] else { return }
        w.riding = m.id
        w.station = m.station
        w.orbit = 0; w.craneTilt = Walker.craneTilt
        w.settling = 1.2
    }

    /// Down off the crane where the minion stands, looking the way the crane looked.
    private func dismount(_ w: Walker) {
        w.riding = nil
        w.yaw = w.view.yaw
        w.pitch = -0.08
        w.velocity = .zero
        w.settling = 1
    }

    private func stepOff(_ w: Walker) {
        for n in [w.sky, w.dome, w.walls] { n.removeFromParentNode() }
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

    /// A few steps out along one of the arms, looking down the hallway at the monolith: the arm whose view
    /// of it turns the camera least. The nearest hallway tile where no arm runs straight.
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

    /// The walk's own frame, in place of the station's view; false when nobody is walking.
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
            if w.riding == nil { stride(w, dt: dt, move: move, turn: turn) }
        }
        ease(w, toward: wantedView(w), dt: dt)
        let floor = floorSignature
        if w.builtFor != floor { w.builtFor = floor; buildWalls(w); buildDome(w) }
        poseWalkCamera(w)
        showPlace(w)
        hidePixelsBehindWalls(w)
        return true
    }

    /// A look from a drag or two fingers, in radians: x turns, y tilts. On the crane it swings round the minion.
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

    /// The line along the bottom while walking: what the keys do here.
    var walkHint: String? {
        guard let w = walker else { return nil }
        if let id = w.riding, let m = minions[id] {
            return "riding along with \(m.home.name) · \(m.words) · wasd to walk from here · esc to let go"
        }
        return "walking · wasd to move, drag to look, shift to run · click a minion to ride along · esc to step out"
    }

    private func wantedView(_ w: Walker) -> WalkView {
        if let id = w.riding, let m = minions[id] {
            return WalkView(focus: w.pos, height: m.headHeight * 0.85, yaw: m.smoothFacing + .pi + w.orbit,
                            pitch: w.craneTilt, distance: Walker.craneReach)
        }
        let moving = min(1, simd_length(w.velocity) / Walker.pace)
        return WalkView(focus: w.pos, height: Walker.eye + abs(sin(w.stride * .pi)) * 0.012 * moving,
                        yaw: w.yaw, pitch: w.pitch, distance: 0)
    }

    /// Your own eyes follow you exactly; a crane lags and swings, and a change between the two is eased.
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
        // One axis at a time, so a walk into a wall at an angle slides along it.
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

    /// What stops you, written to the station log: the wall, the prop or the minion in the way.
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

    /// Whether a body as wide as a minion can stand at `q` (station cells) having come from `from`: every
    /// corner on floor reached through a doorway the minions may use, and no deeper into a prop than before.
    private func fits(_ q: SIMD2<Double>, from: SIMD2<Double>, in st: Station) -> Bool {
        let r = Walker.radius
        let here = Cell(x: Int(from.x.rounded()), y: Int(from.y.rounded()))
        let corners = [SIMD2(0, 0), SIMD2(r, r), SIMD2(r, -r), SIMD2(-r, r), SIMD2(-r, -r)]
        for k in corners {
            let p = q + k
            if !open(from: here, to: Cell(x: Int(p.x.rounded()), y: Int(p.y.rounded())), in: st) { return false }
        }
        func inProps(_ p: SIMD2<Double>) -> Int { corners.filter { st.obstacles.contains(Station.sub(p + $0 * 0.8)) }.count }
        guard inProps(q) <= inProps(from) else { return false }
        // Minions are in the way too: no closer to one already within a shoulder's width.
        for m in minions.values where m.station == st.name && m.opacity > 0.5 {
            let at = SIMD2(Double(m.node.position.x), Double(m.node.position.z)) - st.offset
            let near = r + 0.12
            if simd_length(q - at) < near && simd_length(q - at) < simd_length(from - at) { return false }
        }
        return true
    }

    /// Whether nothing stands between one cell and the next: floor beyond, and no wall on the way. A step
    /// across a corner needs both ways round it open.
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

    /// The camera along the dive: the station's orthographic view at the top, opened out by a lens that
    /// starts nearly flat and widens as it drops, so the first frame is the view you were looking at.
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
        w.walls.scale.y = max(0.001, ease((t - 0.4) / 0.6))
        w.dome.opacity = ease((t - 0.45) / 0.55)
        let film = ease((t - 0.2) / 0.8)
        camera.vignettingIntensity = 0.6 * film
        camera.colorFringeIntensity = 0.5 * film
        camera.grainIntensity = 0.06 * film
        camera.bloomIntensity = 0.9 * film
    }

    /// The station's own overlay steps back while you walk: the repositories along the top and the log.
    func fadeOverlay() {
        guard let w = walker else { return }
        let k = 1 - min(1, max(0, w.phase / 0.6))
        for n in legendNodes + jobNodes { n.alpha = k }
        for (l, _) in eventLabels { l.alpha *= k }
    }

    // MARK: seeing

    /// Whether a straight look from the camera to a point on a station's floor gets there without crossing a
    /// wall or the monolith. From up over the walls, on the crane, everything is in sight.
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

    /// The bath's pixels are drawn over everything so the body never hides them; while walking, a wall does.
    private func hidePixelsBehindWalls(_ w: Walker) {
        for m in minions.values {
            guard m.bathing, let st = fleet.stations[m.station] else { m.staticSeen = true; continue }
            m.staticSeen = inSight(of: SIMD2(Double(m.node.position.x), Double(m.node.position.z)), in: st)
        }
    }

    /// Whether the one walking is at an airlock door, for it to open: as near as a minion walking up to it.
    func walkerAt(door: SCNNode, in st: Station, half: Double) -> Bool {
        guard let w = walker, w.riding == nil, w.station == st.name else { return false }
        let q = w.pos - st.offset
        return abs(q.x - (Double(door.position.x) - st.offset.x)) < half && abs(q.y - (Double(door.position.z) - st.offset.y)) < 0.9
    }

    // MARK: the walls and the dome

    /// A wall on every edge the minions may not cross, as tall as the hallway needs to feel like one, panelled
    /// with a light strip in the colour of the floor it faces; a rail where the floor is outside.
    private func buildWalls(_ w: Walker) {
        w.walls.childNodes.forEach { $0.removeFromParentNode() }
        let tints = drawnFloor()
        var glows: [String: SCNMaterial] = [:]
        func glow(_ c: NSColor?) -> SCNMaterial {
            let base = c ?? Palette.text
            let key = WallPanel.key(base)
            if let m = glows[key] { return m }
            let m = flat(base.blended(withFraction: 0.55, of: .white) ?? base)
            glows[key] = m
            return m
        }
        let rim = flat(NSColor(rgb: (0.42, 0.44, 0.5)))
        let plain = lit(NSColor(rgb: (0.74, 0.75, 0.79)))
        let post = WallPanel.post
        let postBox = SCNBox(width: 0.1, height: Walker.wallHeight + 0.03, length: 0.1, chamferRadius: 0)
        postBox.materials = [post, post, post, post, rim, post]
        let t = 0.07
        for st in fleet.stations.values.sorted(by: { $0.name < $1.name }) {
            let walk = st.walkable
            let outside = Set(st.hangarCells + st.padCells)
            let root = SCNNode()
            var corners: [Cell: [Bool]] = [:]
            func tint(_ c: Cell) -> NSColor? { tints[Cell(x: Int((st.offset.x + Double(c.x)).rounded()), y: Int((st.offset.y + Double(c.y)).rounded()))] }
            for c in walk.sorted(by: { ($0.y, $0.x) < ($1.y, $1.x) }) {
                for (dx, dy) in [(1, 0), (0, 1), (-1, 0), (0, -1)] {
                    let n = Cell(x: c.x + dx, y: c.y + dy)
                    let floored = walk.contains(n)
                    if floored && (dx < 0 || dy < 0 || st.canStep(from: c, to: n)) { continue }
                    if n == st.plan.monolith { continue }
                    let low = outside.contains(c) && (!floored || outside.contains(n))
                    let h = low ? Walker.railHeight : Walker.wallHeight
                    let across = dx != 0
                    let box = SCNBox(width: across ? t : 1 + t, height: h, length: across ? 1 + t : t, chamferRadius: 0)
                    // SCNBox faces: +z, +x, -z, -x, top, bottom.
                    func side(_ x: Int, _ y: Int) -> Int { x > 0 ? 1 : x < 0 ? 3 : y > 0 ? 0 : 2 }
                    var faces = Array(repeating: plain, count: 6)
                    if !low {
                        faces[side(-dx, -dy)] = WallPanel.material(accent: tint(c), variant: WallPanel.pick(c, dx, dy, st.name))
                        faces[side(dx, dy)] = WallPanel.material(accent: floored ? tint(n) : nil, variant: WallPanel.pick(n, -dx, -dy, st.name))
                    }
                    faces[4] = rim
                    box.materials = faces
                    let wall = SCNNode(geometry: box)
                    let mid = st.offset + SIMD2(Double(c.x) + Double(dx) * 0.5, Double(c.y) + Double(dy) * 0.5)
                    wall.position = v3(mid.x, h / 2, mid.y)
                    root.addChildNode(wall)
                    guard !low else { continue }
                    // Its two ends, in half-tile steps: a post stands where a wall turns or stops.
                    let (px, py) = (dy, dx)
                    corners[Cell(x: 2 * c.x + dx + px, y: 2 * c.y + dy + py), default: []].append(across)
                    corners[Cell(x: 2 * c.x + dx - px, y: 2 * c.y + dy - py), default: []].append(across)
                    // A strip of light along the foot of each tall wall, in the colour of the floor it runs along.
                    for (cell, sign) in [(c, -1.0)] + (floored ? [(n, 1.0)] : []) {
                        let strip = SCNBox(width: across ? 0.012 : 1, height: 0.022, length: across ? 1 : 0.012, chamferRadius: 0)
                        strip.firstMaterial = glow(tint(cell))
                        let s = SCNNode(geometry: strip)
                        let off = (t / 2 + 0.006) * sign
                        s.position = v3(mid.x + (across ? off * Double(dx) : 0), 0.05, mid.y + (across ? 0 : off * Double(dy)))
                        root.addChildNode(s)
                    }
                }
            }
            for (k, ends) in corners where !(ends.count == 2 && ends[0] == ends[1]) {
                let p = SCNNode(geometry: postBox)
                p.position = v3(st.offset.x + Double(k.x) / 2, (Walker.wallHeight + 0.03) / 2, st.offset.y + Double(k.y) / 2)
                root.addChildNode(p)
            }
            let flatWalls = root.flattenedClone()
            flatWalls.categoryBitMask = Pick.scenery
            w.walls.addChildNode(flatWalls)
        }
    }

    /// Everything the walls are built from: each station's place, its walkable floor and its rooms.
    private var floorSignature: String {
        fleet.stations.values.sorted { $0.name < $1.name }.map { st in
            "\(st.name)@\(st.offset.x),\(st.offset.y):\(st.walkable.count)/\(st.dugCount)/\(st.rooms.count)"
        }.joined(separator: " ") + "|\(lastRebuildAt)"
    }

    /// A glass dome over each station, cut in flat panels on a frame, rising from just under the floor's
    /// edge: the sky is still there, seen from inside.
    private func buildDome(_ w: Walker) {
        w.dome.childNodes.forEach { $0.removeFromParentNode() }
        for st in fleet.stations.values {
            let b = st.bounds
            let lo = st.offset + SIMD2(Double(b.min.x) - 0.5, Double(b.min.y) - 0.5)
            let hi = st.offset + SIMD2(Double(b.max.x) + 0.5, Double(b.max.y) + 0.5)
            let centre = (lo + hi) / 2, half = (hi - lo) / 2
            // Wide enough that the footprint's corners are inside the ellipse it stands on.
            let radius = half * 1.45 + SIMD2(1, 1)
            let rise = max(3.5, min(radius.x, radius.y) * 0.55), foot = -0.35
            let around = 28, up = 8
            var vertices: [SCNVector3] = [], normals: [SCNVector3] = [], uvs: [CGPoint] = [], indices: [Int32] = []
            func point(_ i: Int, _ j: Int) -> SIMD3<Double> {
                let a = Double(j) / Double(up) * .pi / 2, l = Double(i) / Double(around) * 2 * .pi
                return SIMD3(centre.x + radius.x * cos(a) * cos(l), foot + rise * sin(a), centre.y + radius.y * cos(a) * sin(l))
            }
            for j in 0..<up {
                for i in 0..<around {
                    let q = [point(i, j), point(i + 1, j), point(i + 1, j + 1), point(i, j + 1)]
                    let n = simd_normalize(simd_cross(q[2] - q[0], q[1] - q[0]))
                    let base = Int32(vertices.count)
                    for (p, uv) in zip(q, [CGPoint(x: 0, y: 1), CGPoint(x: 1, y: 1), CGPoint(x: 1, y: 0), CGPoint(x: 0, y: 0)]) {
                        vertices.append(v3(p.x, p.y, p.z)); normals.append(v3(n.x, n.y, n.z)); uvs.append(uv)
                    }
                    indices += [base, base + 1, base + 2, base, base + 2, base + 3]
                }
            }
            let g = SCNGeometry(sources: [SCNGeometrySource(vertices: vertices), SCNGeometrySource(normals: normals),
                                          SCNGeometrySource(textureCoordinates: uvs)],
                                elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
            g.firstMaterial = WallPanel.glass
            let n = SCNNode(geometry: g)
            n.categoryBitMask = Pick.scenery
            n.renderingOrder = 90
            w.dome.addChildNode(n)
        }
    }

    /// The colour of every floor tile as drawn, by world cell: walls take the colour of the floor they face.
    private func drawnFloor() -> [Cell: NSColor] {
        var out: [Cell: NSColor] = [:]
        staticRoot.enumerateHierarchy { n, _ in
            guard let p = n.geometry as? SCNPlane, p.width == 1, p.height == 1, abs(Double(n.eulerAngles.x) + .pi / 2) < 0.01,
                  let c = p.firstMaterial?.diffuse.contents as? NSColor else { return }
            let at = n.worldPosition
            guard abs(Double(at.y)) < 0.05 else { return }
            out[Cell(x: Int(Double(at.x).rounded()), y: Int(Double(at.z).rounded()))] = c
        }
        return out
    }

    // MARK: where you are

    /// The name of the place you have walked into, large for a moment, the way a game names a level.
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
            default:
                let here = minions.values.filter { $0.station == st.name && $0.place == .room(room.key) && $0.state != .leaving }
                let doing = here.first(where: \.busy).map { $0.words }
                return (room.name, [room.repo, doing].compactMap { $0 }.joined(separator: " · "))
            }
        }
        if st.hangarCells.contains(c) { return ("The bay", "where the shuttles land") }
        if st.airlockCells.contains(c) { return ("The airlock", nil) }
        if st.padCells.contains(c) { return ("The pad", "where releases lift off") }
        if st.storageCells.contains(c) { return ("Storage", "merged work waiting for a release") }
        if st.deconCells.contains(c) { return ("Decon", nil) }
        if st.deckCells.contains(c) { return ("The deck", "work on staging") }
        if st.coreCells.contains(c) { return ("The plaza", nil) }
        return ("The hallway", nil)
    }

    /// Which way an idle minion turns: toward you when you walk near it, toward the camera otherwise.
    func idleFacing(_ m: Minion) -> Double {
        if let w = walker, w.riding == nil, w.phase > 0.5, m.station == w.station {
            let d = w.pos - SIMD2(Double(m.node.position.x), Double(m.node.position.z))
            if simd_length(d) < 4 { return atan2(d.x, d.y) }
        }
        return Double(rig.eulerAngles.y)
    }
}

/// The walls' clean panelling, after the starship corridors. Every face has the same light band at the
/// same height, so the strips run unbroken down a corridor; above and below it each face is one of a set
/// of panels — plates, lights, pipes, grilles, screens, lockers, hatches, ribs, button boards — picked by
/// where it stands, so a station looks the same every time it is walked.
enum WallPanel {
    static let size = 192
    private static var made: [String: SCNMaterial] = [:]

    /// The upper and lower panel of each design, the plain plates more often than the busy ones.
    private static let designs: [(upper: Int, lower: Int)] = [(0, 0), (1, 1), (2, 2), (0, 5), (4, 3), (3, 4), (1, 0), (2, 5),
                                                             (0, 1), (4, 2), (3, 0), (0, 4)]
    static var count: Int { designs.count }

    /// The design for the face of `cell`'s wall toward (dx, dy).
    static func pick(_ c: Cell, _ dx: Int, _ dy: Int, _ station: String) -> Int {
        var h = UInt64(bitPattern: Int64(c.x &* 73856093 ^ c.y &* 19349663 ^ (dx + 2) &* 83492791 ^ (dy + 2) &* 2654435761))
        for u in station.utf8 { h = h &* 31 &+ UInt64(u) }
        h ^= h >> 29; h = h &* 0xbf58476d1ce4e5b9; h ^= h >> 32
        return Int(h % UInt64(designs.count))
    }

    static func key(_ c: NSColor) -> String {
        guard let s = c.usingColorSpace(.sRGB) else { return "?" }
        return String(format: "%.2f/%.2f/%.2f", s.redComponent, s.greenComponent, s.blueComponent)
    }

    /// The panel for a wall face, its strip and screens lit in `accent`; unlit for a face onto nothing. The
    /// designs are drawn once in grey; the room's colour goes onto the strip on the GPU, through a mask.
    static func material(accent: NSColor?, variant: Int) -> SCNMaterial {
        let k = (accent.map(key) ?? "none") + "#\(variant)"
        if let m = made[k] { return m }
        let skin = skins[variant]
        let m = SCNMaterial()
        m.lightingModel = .blinn
        m.diffuse.contents = skin.diffuse
        m.emission.contents = skin.lamps
        m.normal.contents = skin.normal
        m.normal.intensity = 0.9
        m.specular.contents = NSColor(white: 0.35, alpha: 1)
        m.shininess = 0.35
        for p in [m.diffuse, m.emission, m.normal] { p.mipFilter = .linear }
        let mask = SCNMaterialProperty(contents: skin.mask)
        mask.mipFilter = .linear
        let a = (accent?.blended(withFraction: 0.3, of: .white) ?? NSColor(white: 0.35, alpha: 1)).usingColorSpace(.deviceRGB)!
        m.setValue(mask, forKey: "accentMask")
        m.setValue(NSValue(scnVector3: SCNVector3(a.redComponent, a.greenComponent, a.blueComponent)), forKey: "accent")
        m.setValue(NSNumber(value: accent == nil ? 0 : 1), forKey: "glow")
        m.shaderModifiers = [.surface: tint]
        made[k] = m
        return m
    }

    private static let tint = """
    #pragma arguments
    texture2d<float> accentMask;
    float3 accent;
    float glow;
    #pragma body
    constexpr sampler maskSampler(filter::linear, mip_filter::linear, address::repeat);
    float k = accentMask.sample(maskSampler, _surface.diffuseTexcoord).r;
    _surface.diffuse.rgb = mix(_surface.diffuse.rgb, accent, min(1.0, k * 4.0));
    _surface.emission.rgb += accent * k * glow;
    """

    /// Draws every design ahead of the first walk, off the main thread, so stepping in never waits on it.
    static func prepare() { DispatchQueue.global(qos: .utility).async { _ = skins } }

    static let post: SCNMaterial = {
        let m = lit(NSColor(rgb: (0.62, 0.64, 0.69)))
        m.lightingModel = .blinn
        m.specular.contents = NSColor(white: 0.3, alpha: 1)
        return m
    }()

    /// The dome's glass: a faint tint on each pane and a light frame round it.
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

    /// What a texel is: plate, the room's light strip, a lamp of some colour, or a screen and its lines.
    private enum Kind: UInt8 { case plate, strip, white, red, green, amber, screen, trace }

    private struct Layout {
        var grey: [Float], height: [Float], kind: [Kind]
    }

    /// One design laid out, as fractions down and across the face.
    private static func layout(_ variant: Int) -> Layout {
        let n = size
        let (upper, lower) = designs[variant]
        var r = Textures.Seeded(s: UInt64(variant * 977 + 13))
        let tone = Float(0.78 + r.next() * 0.08)
        var l = Layout(grey: [Float](repeating: tone, count: n * n), height: [Float](repeating: 0.6, count: n * n),
                       kind: [Kind](repeating: .plate, count: n * n))
        func fill(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, grey g: Float? = nil, height h: Float? = nil, kind k: Kind? = nil) {
            for y in max(0, Int(y0 * Double(n)))..<min(n, Int(y1 * Double(n))) {
                for x in max(0, Int(x0 * Double(n)))..<min(n, Int(x1 * Double(n))) {
                    let i = y * n + x
                    if let g { l.grey[i] = g }; if let h { l.height[i] = h }; if let k { l.kind[i] = k }
                }
            }
        }
        /// A pipe along x: rounded in height and shade across its width.
        func pipe(_ y0: Double, _ y1: Double, grey g: Float) {
            let rows = max(1, Int((y1 - y0) * Double(n)))
            for k in 0..<rows {
                let t = (Double(k) + 0.5) / Double(rows), bulge = Float(sin(t * .pi))
                let y = y0 + (y1 - y0) * Double(k) / Double(rows)
                fill(0, y, 1, y + 1 / Double(n) + 0.0001, grey: g * (0.75 + 0.35 * bulge), height: 0.55 + 0.4 * bulge)
            }
        }
        func lamps(_ y0: Double, _ y1: Double, from x0: Double, to x1: Double, count: Int) {
            let kinds: [Kind] = [.white, .red, .green, .amber, .white, .green]
            let step = (x1 - x0) / Double(count)
            for i in 0..<count {
                let x = x0 + step * Double(i) + step * 0.2
                fill(x, y0, x + step * 0.6, y1, grey: 0.9, height: 0.7, kind: kinds[Int(r.next() * Double(kinds.count)) % kinds.count])
            }
        }

        fill(0, 0, 1, 0.05, grey: tone + 0.08, height: 0.8)
        switch upper {
        case 1:
            fill(0.06, 0.08, 0.94, 0.27, grey: tone - 0.06, height: 0.45)
            lamps(0.15, 0.2, from: 0.66, to: 0.9, count: 3)
        case 2:
            fill(0, 0.07, 1, 0.29, grey: tone - 0.2, height: 0.35)
            pipe(0.08, 0.15, grey: 0.82); pipe(0.16, 0.21, grey: 0.7); pipe(0.22, 0.28, grey: 0.86)
            for x in [0.18, 0.55, 0.85] { fill(x, 0.07, x + 0.04, 0.29, grey: 0.5, height: 0.75) }
        case 3:
            fill(0.06, 0.08, 0.94, 0.27, grey: tone - 0.04, height: 0.48)
            for x in [0.22, 0.74] { fill(x, 0.1, x + 0.04, 0.25, grey: 0.95, height: 0.4, kind: .white) }
        case 4:
            fill(0.05, 0.08, 0.95, 0.27, grey: tone - 0.1, height: 0.42)
            var y = 0.1
            while y < 0.25 { fill(0.07, y, 0.93, y + 0.012, grey: 0.22, height: 0.25); y += 0.026 }
        default:
            for (x0, x1) in [(0.06, 0.47), (0.53, 0.94)] { fill(x0, 0.08, x1, 0.27, grey: tone - 0.05, height: 0.45) }
        }
        // The band: the same height on every face, so its light strip runs on round the corridor.
        fill(0, 0.31, 1, 0.43, grey: 0.3, height: 0.2)
        var x = 0.03
        while x < 0.95 {
            let wide = 0.03 + r.next() * 0.08, tall = 0.03 + r.next() * 0.035
            if r.next() > 0.3 { fill(x, 0.385, min(0.97, x + wide), min(0.425, 0.385 + tall), grey: Float(0.5 + r.next() * 0.25), height: 0.38) }
            x += wide + 0.02 + r.next() * 0.04
        }
        fill(0.0, 0.345, 1.0, 0.365, grey: 0.95, height: 0.3, kind: .strip)
        switch lower {
        case 1:
            fill(0.08, 0.48, 0.92, 0.82, grey: tone - 0.05, height: 0.47)
            fill(0.14, 0.52, 0.66, 0.77, grey: 0.12, height: 0.3, kind: .screen)
            var y = 0.55
            while y < 0.74 {
                let w = 0.1 + r.next() * 0.38
                fill(0.17, y, 0.17 + w, y + 0.012, kind: .trace); y += 0.03
            }
            lamps(0.55, 0.59, from: 0.72, to: 0.88, count: 2)
            lamps(0.64, 0.68, from: 0.72, to: 0.88, count: 2)
        case 2:
            for (x0, x1) in [(0.06, 0.48), (0.52, 0.94)] {
                fill(x0, 0.46, x1, 0.84, grey: tone - 0.03, height: 0.5)
                fill(x1 - 0.08, 0.6, x1 - 0.05, 0.72, grey: 0.35, height: 0.85)
                fill(x0 + 0.06, 0.5, x0 + 0.2, 0.53, grey: 0.92, height: 0.6)
                var y = 0.76
                while y < 0.82 { fill(x0 + 0.05, y, x1 - 0.12, y + 0.008, grey: 0.3, height: 0.35); y += 0.018 }
            }
        case 3:
            fill(0.18, 0.47, 0.82, 0.84, grey: 0.36, height: 0.4)
            fill(0.21, 0.5, 0.79, 0.81, grey: tone - 0.02, height: 0.5)
            var k = 0
            var s = 0.18
            while s < 0.82 {
                fill(s, 0.47, min(0.82, s + 0.045), 0.49, grey: k % 2 == 0 ? 0.92 : 0.2, height: 0.42)
                fill(s, 0.82, min(0.82, s + 0.045), 0.84, grey: k % 2 == 0 ? 0.92 : 0.2, height: 0.42)
                s += 0.045; k += 1
            }
            for (bx, by) in [(0.25, 0.54), (0.75, 0.54), (0.25, 0.77), (0.75, 0.77)] { fill(bx - 0.015, by - 0.01, bx + 0.015, by + 0.01, grey: 0.5, height: 0.8) }
        case 4:
            for i in 0..<5 {
                let x0 = 0.06 + Double(i) * 0.19
                fill(x0, 0.45, x0 + 0.07, 0.85, grey: tone + 0.05, height: 0.85)
                fill(x0 + 0.07, 0.45, x0 + 0.19, 0.85, grey: tone - 0.12, height: 0.4)
            }
        case 5:
            fill(0.1, 0.47, 0.9, 0.83, grey: 0.4, height: 0.42)
            fill(0.13, 0.5, 0.87, 0.8, grey: 0.55, height: 0.5)
            for row in 0..<4 { lamps(0.54 + Double(row) * 0.065, 0.58 + Double(row) * 0.065, from: 0.16, to: 0.84, count: 7) }
        default:
            fill(0.08, 0.48, 0.92, 0.81, grey: tone - 0.04, height: 0.47)
            var y = 0.53
            while y < 0.77 { fill(0.6, y, 0.87, y + 0.013, grey: 0.24, height: 0.3); y += 0.034 }
            fill(0.14, 0.53, 0.3, 0.6, grey: 0.62, height: 0.4)
        }
        fill(0, 0.86, 1, 1, grey: 0.28, height: 0.4)
        fill(0, 0, 0.012, 1, grey: 0.45, height: 0.3)
        fill(0.988, 0, 1, 1, grey: 0.45, height: 0.3)
        return l
    }

    /// Each design drawn: its plates in grey, its lamps lit, where the room's colour goes, and its relief.
    private static let skins: [(diffuse: NSImage, lamps: NSImage, mask: NSImage, normal: NSImage)] = (0..<designs.count).map { v in
        let n = size, l = layout(v)
        var px = [UInt8](repeating: 255, count: n * n * 4), lit = [UInt8](repeating: 0, count: n * n * 4)
        var mask = [UInt8](repeating: 0, count: n * n * 4)
        func byte(_ v: Float) -> UInt8 { UInt8(max(0, min(255, v * 255))) }
        for i in 0..<(n * n) {
            let g = l.grey[i]
            var c = (g * 0.98, g, g * 1.05), e: (Float, Float, Float) = (0, 0, 0), k: Float = 0
            switch l.kind[i] {
            case .plate: break
            case .strip: c = (0.9, 0.9, 0.9); k = 1
            case .white: c = (0.95, 0.96, 1); e = (0.9, 0.92, 1)
            case .red: c = (0.95, 0.25, 0.2); e = c
            case .green: c = (0.35, 0.95, 0.5); e = c
            case .amber: c = (1, 0.72, 0.25); e = c
            case .screen: c = (0.04, 0.06, 0.09); k = 0.04
            case .trace: c = (0.3, 0.35, 0.4); k = 0.85
            }
            px[i * 4] = byte(c.0); px[i * 4 + 1] = byte(c.1); px[i * 4 + 2] = byte(c.2)
            lit[i * 4] = byte(e.0); lit[i * 4 + 1] = byte(e.1); lit[i * 4 + 2] = byte(e.2)
            mask[i * 4] = byte(k); mask[i * 4 + 1] = byte(k); mask[i * 4 + 2] = byte(k)
        }
        var h = l.height, out = h
        for y in 0..<n { for x in 0..<n {
            var acc: Float = 0
            for dy in -1...1 { for dx in -1...1 { acc += h[((y + dy + n) % n) * n + (x + dx + n) % n] } }
            out[y * n + x] = acc / 9
        } }
        h = out
        return (bitmap(px, n), bitmap(lit, n), bitmap(mask, n), Plating.normalMap(h, size: n, strength: 5))
    }

    private static func bitmap(_ px: [UInt8], _ n: Int) -> NSImage {
        var data = px
        let cs = CGColorSpaceCreateDeviceRGB()
        let made: CGImage? = data.withUnsafeMutableBytes {
            CGContext(data: $0.baseAddress, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4, space: cs,
                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)?.makeImage()
        }
        guard let image = made else { return NSImage() }
        return NSImage(cgImage: image, size: NSSize(width: n, height: n))
    }
}
