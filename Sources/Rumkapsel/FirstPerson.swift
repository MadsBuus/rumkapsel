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
    /// The jetpack on space: its push up, the station's low gravity pulling back down, the fastest climb or
    /// fall, and the highest it takes you out under open space. Indoors the hull is the ceiling.
    static let thrust = 3.4, gravity = 1.6, climbLimit = 1.3, ceiling = 6.0
    /// The top of your head over your eyes, which the hull stops.
    static let crown = 0.1

    var station: String
    /// Where you stand, in world x/z; while riding, where the minion stands.
    var pos: SIMD2<Double>
    var yaw: Double
    var pitch = -0.08
    var velocity = SIMD2<Double>(0, 0)
    /// The jetpack: firing while space is held, how high your feet are off the floor, and how fast that changes.
    var thrusting = false
    var altitude = 0.0
    var climb = 0.0
    /// The hull over each station, by name, as built with the walls, and which drawing of the walls' skins they had.
    var hulls: [String: StationHull] = [:]
    /// The signs' arrows, rolling.
    var arrows: [Signs.Arrow] = []
    /// The pieces of the hull the station's view draws, faded out as the walk's hull comes in.
    var fragments: [SCNNode] = []
    var skins = -1
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
    var builtFor = 0
    /// When the station's scene was last rebuilt as the floor was read for `builtFor`.
    var readAt = -1.0
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
    /// Down at a point on the floor, given one (a double-click on it), looking the way the view looks.
    func stepIn(at point: SIMD2<Double>? = nil) {
        guard walker == nil, let station = cameraNode.camera else { return }
        let focus = SIMD2(Double(rig.position.x), Double(rig.position.z))
        let viewYaw = Double(rig.eulerAngles.y)
        let followed = point == nil ? following.flatMap { minions[$0] } : nil
        var start: (station: Station, pos: SIMD2<Double>, yaw: Double)?
        if let point, let st = fleet.stations.values.min(by: { simd_distance(point, $0.offset) < simd_distance(point, $1.offset) }),
           let cell = st.nearestFloor(to: point - st.offset) {
            let q = point - st.offset, middle = SIMD2(Double(cell.x), Double(cell.y))
            let onIt = Cell(x: Int(q.x.rounded()), y: Int(q.y.rounded())) == cell && fits(q, from: middle, in: st)
            start = (st, (onIt ? q : middle) + st.offset, viewYaw)
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
        w.altitude = 0; w.climb = 0; w.thrusting = false
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
            if w.riding == nil { fly(w, dt: dt); stride(w, dt: dt, move: move, turn: turn) }
        }
        ease(w, toward: wantedView(w), dt: dt)
        let floor = timed("walk floor") { floorSignature(w) }
        if w.builtFor != floor { w.builtFor = floor; w.skins = Bulkhead.generation; timed("walls") { buildWalls(w) }; timed("dome") { buildDome(w) } }
        else if w.skins != Bulkhead.generation { w.skins = Bulkhead.generation; timed("walls") { buildWalls(w) } }   // the walls' skins are done
        poseWalkCamera(w)
        Signs.roll(w.arrows, at: clock)
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
        return "walking · wasd to move, drag to look, shift to run, space to fly · click a minion to ride along · esc to step out"
    }

    private func wantedView(_ w: Walker) -> WalkView {
        if let id = w.riding, let m = minions[id] {
            return WalkView(focus: w.pos, height: m.headHeight * 0.85, yaw: m.smoothFacing + .pi + w.orbit,
                            pitch: w.craneTilt, distance: Walker.craneReach)
        }
        let moving = w.altitude > 0 ? 0 : min(1, simd_length(w.velocity) / Walker.pace)
        // Under thrust the pack shudders a little.
        let shudder = w.thrusting ? sin(w.stride * 9 + Double(w.altitude) * 40) * 0.004 : 0
        return WalkView(focus: w.pos, height: Walker.eye + w.altitude + abs(sin(w.stride * .pi)) * 0.012 * moving + shudder,
                        yaw: w.yaw, pitch: w.pitch, distance: 0)
    }

    /// The highest your feet may go where you are: under the hull indoors, open space outside.
    private func ceiling(_ w: Walker) -> Double {
        guard let st = fleet.stations[w.station], let hull = w.hulls[w.station],
              let roof = hull.roof(over: w.pos - st.offset, top: w.altitude + Walker.eye + Walker.crown) else { return Walker.ceiling }
        return roof - Walker.eye - Walker.crown
    }

    /// Up on the jetpack while space is held, and back down under the station's low gravity once it is let
    /// go, landing on whatever floor is under you.
    private func fly(_ w: Walker, dt: Double) {
        w.climb += ((w.thrusting ? Walker.thrust : 0) - Walker.gravity) * dt
        w.climb = min(Walker.climbLimit, max(-Walker.climbLimit, w.climb))
        let was = w.altitude
        w.altitude += w.climb * dt
        // Coming down past the tops of the walls where a body cannot stand: held there, and eased over the
        // middle of the tile below until it can.
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
        if w.thrusting { w.stride += dt * 3 }   // what the shudder runs on while hovering still
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
    /// Flown higher than the walls, only the hull and the station's edge stop you: walls, props, minions and the
    /// bare deck pass underneath.
    private func fits(_ q: SIMD2<Double>, from: SIMD2<Double>, in st: Station, high: Bool? = nil) -> Bool {
        let r = Walker.radius
        let here = Cell(x: Int(from.x.rounded()), y: Int(from.y.rounded()))
        let corners = [SIMD2(0, 0), SIMD2(r, r), SIMD2(r, -r), SIMD2(-r, r), SIMD2(-r, -r)]
        // Nobody goes through the hull: indoors your head stays under it, and in from open space is only through a doorway.
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
        // The walls rise out of the floor and fade in as they come, never a flat outline before they start.
        let rising = ease((t - 0.4) / 0.6)
        w.walls.isHidden = rising <= 0
        w.walls.scale.y = max(0.001, rising)
        w.walls.opacity = ease((t - 0.4) / 0.3)
        w.dome.opacity = ease((t - 0.45) / 0.55)
        // The station view's pieces of the hull give way to the whole of it as the view comes down.
        let fragments = 1 - ease(t / 0.5)
        for n in w.fragments { n.opacity = fragments; n.isHidden = fragments <= 0 }
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
        w.arrows = []
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
        let t = 0.07
        let railPost = SCNBox(width: t + 0.02, height: Walker.railHeight + 0.02, length: t + 0.02, chamferRadius: 0)
        railPost.firstMaterial = Bulkhead.steel
        for st in fleet.stations.values.sorted(by: { $0.name < $1.name }) {
            let walk = st.walkable
            let outside = Set(st.hangarCells + st.padCells)
            let styles = Bulkhead.styles(of: st)
            let root = SCNNode()
            var corners: [Cell: [Bool]] = [:], railCorners: [Cell: [Bool]] = [:]
            func tint(_ c: Cell) -> NSColor? { tints[Cell(x: Int((st.offset.x + Double(c.x)).rounded()), y: Int((st.offset.y + Double(c.y)).rounded()))] }
            // Every stretch of wall, by the cell it stands beside and the way out of it.
            var stretches: [(c: Cell, dx: Int, dy: Int)] = []
            for c in walk.sorted(by: { ($0.y, $0.x) < ($1.y, $1.x) }) {
                for (dx, dy) in [(1, 0), (0, 1), (-1, 0), (0, -1)] {
                    let n = Cell(x: c.x + dx, y: c.y + dy)
                    let floored = walk.contains(n)
                    if floored && (dx < 0 || dy < 0 || st.canStep(from: c, to: n)) { continue }
                    if n == st.plan.monolith { continue }
                    stretches.append((c, dx, dy))
                }
            }
            for (c, dx, dy) in stretches {
                do {
                    let n = Cell(x: c.x + dx, y: c.y + dy)
                    let floored = walk.contains(n)
                    let low = outside.contains(c) && (!floored || outside.contains(n))
                    let h = low ? Walker.railHeight : Walker.wallHeight
                    let across = dx != 0
                    // Corner point to corner point, no further: an end then lies inside whatever wall it meets, never in
                    // the plane of one of its faces, where the two would flicker. The posts close the corners.
                    let box = SCNBox(width: across ? t : 1, height: h, length: across ? 1 : t, chamferRadius: 0)
                    // SCNBox faces: +z, +x, -z, -x, top, bottom.
                    func side(_ x: Int, _ y: Int) -> Int { x > 0 ? 1 : x < 0 ? 3 : y > 0 ? 0 : 2 }
                    var faces = Array(repeating: low ? plain : Bulkhead.steel, count: 6)
                    if !low {
                        faces[side(-dx, -dy)] = Bulkhead.material(Bulkhead.pick(c, dx, dy, st.name), style: styles[c] ?? .hallway)
                        faces[side(dx, dy)] = Bulkhead.material(Bulkhead.pick(n, -dx, -dy, st.name), style: styles[n] ?? .hallway)
                    }
                    faces[4] = low ? rim : Bulkhead.steel
                    box.materials = faces
                    let wall = SCNNode(geometry: box)
                    let mid = st.offset + SIMD2(Double(c.x) + Double(dx) * 0.5, Double(c.y) + Double(dy) * 0.5)
                    wall.position = v3(mid.x, h / 2, mid.y)
                    root.addChildNode(wall)
                    let (px, py) = (dy, dx)
                    let ends = [Cell(x: 2 * c.x + dx + px, y: 2 * c.y + dy + py), Cell(x: 2 * c.x + dx - px, y: 2 * c.y + dy - py)]
                    guard !low else { for e in ends { railCorners[e, default: []].append(across) }; continue }
                    let cap = Bulkhead.cap(length: 1, thickness: t, across: across)
                    cap.position = v3(wall.position.x, 0, wall.position.z)
                    root.addChildNode(cap)
                    // Its two ends, in half-tile steps: a post stands where a wall turns or stops.
                    for e in ends { corners[e, default: []].append(across) }
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
                let p = Bulkhead.pilaster(seed: abs(k.x &* 31 &+ k.y &* 17))
                p.position = v3(st.offset.x + Double(k.x) / 2, 0, st.offset.y + Double(k.y) / 2)
                root.addChildNode(p)
            }
            // A rail turns or stops at a short post of its own, unless a wall's post stands there already.
            for (k, ends) in railCorners where !(ends.count == 2 && ends[0] == ends[1]) && corners[k] == nil {
                let p = SCNNode(geometry: railPost)
                p.position = v3(st.offset.x + Double(k.x) / 2, (Walker.railHeight + 0.02) / 2, st.offset.y + Double(k.y) / 2)
                root.addChildNode(p)
            }
            let flatWalls = root.flattenedClone()
            flatWalls.categoryBitMask = Pick.scenery
            w.walls.addChildNode(flatWalls)
            for sign in Signs.plan(st) { w.walls.addChildNode(signNode(sign, in: st, thickness: t, arrows: &w.arrows)) }
        }
    }


    /// A way-finding sign on its wall: a lit panel at eye height, a line for each way, only drawn close by.
    private func signNode(_ sign: Signs.Sign, in st: Station, thickness t: Double, arrows: inout [Signs.Arrow]) -> SCNNode {
        let (n, rolling) = Signs.panel(sign)
        arrows += rolling
        let p = SIMD2(Double(sign.wall.x), Double(sign.wall.y))
        let at = st.offset + SIMD2(Double(sign.cell.x), Double(sign.cell.y)) + p * (0.5 - t / 2 - 0.004)
        n.position = v3(at.x, 0.47, at.y)
        n.eulerAngles.y = CGFloat(atan2(-p.x, -p.y))   // facing back into the junction
        n.categoryBitMask = Pick.scenery
        return n
    }

    /// Everything the walls and the dome are built from: each station's place, its walkable floor, the steps
    /// between its cells and the room each cell is part of. Read again only once the station's scene was rebuilt,
    /// which draws the hull pieces anew too: those are picked up again for the walk to fade.
    private func floorSignature(_ w: Walker) -> Int {
        guard w.readAt != lastRebuildAt else { return w.builtFor }
        w.readAt = lastRebuildAt
        w.fragments = staticRoot.childNodes.filter { $0.name?.hasPrefix("hull:") == true }
        var h = Hasher()
        for st in fleet.stations.values.sorted(by: { $0.name < $1.name }) {
            h.combine(st.name); h.combine(st.offset.x); h.combine(st.offset.y)
            for c in st.walkable.sorted(by: { ($0.y, $0.x) < ($1.y, $1.x) }) {
                h.combine(c.x); h.combine(c.y)
                h.combine(st.canStep(from: c, to: Cell(x: c.x + 1, y: c.y))); h.combine(st.canStep(from: c, to: Cell(x: c.x, y: c.y + 1)))
                if let room = st.room(at: c) { h.combine(room.key); h.combine(room.repo) }
            }
        }
        return h.finalize()
    }

    /// The hull over each station: its own glass vault on a low steel sill, with doorways cut where the gate and
    /// the airlock go through it. The pieces of it the station's view draws
    /// stand in the same place, so they step aside while you walk.
    private func buildDome(_ w: Walker) {
        w.dome.childNodes.forEach { $0.removeFromParentNode() }
        w.hulls = [:]
        w.fragments = staticRoot.childNodes.filter { $0.name?.hasPrefix("hull:") == true }
        let step = 0.25
        for st in fleet.stations.values {
            let hull = StationHull(st)
            w.hulls[st.name] = hull
            // Indoors, every tile is floored: where the station has none of its own, a bare deck plate.
            let bare = SCNNode()
            for c in hull.inside where !st.walkable.contains(c) && c != st.plan.monolith {
                let tile = SCNNode(geometry: WallPanel.bareDeck)
                tile.eulerAngles.x = -.pi / 2
                tile.position = v3(st.offset.x + Double(c.x), -0.002, st.offset.y + Double(c.y))
                bare.addChildNode(tile)
            }
            let flatDeck = bare.flattenedClone()
            flatDeck.categoryBitMask = Pick.scenery
            w.dome.addChildNode(flatDeck)
            var glass = (v: [SCNVector3](), uv: [CGPoint](), i: [Int32]())
            // Heights on the grid's corners, each measured once for the squares that share it.
            let n = Int((1 / step).rounded())
            var heights: [SIMD2<Int>: Double] = [:]
            func height(_ k: SIMD2<Int>) -> Double {
                if let h = heights[k] { return h }
                let h = StationHull.height(atDistance: hull.reach(SIMD2(Double(k.x), Double(k.y)) * step - 0.5).distance)
                heights[k] = h
                return h
            }
            for c in hull.inside {
                let door = hull.nearDoor(c)
                for i in 0..<n {
                    for j in 0..<n {
                        let gx = c.x * n + i, gy = c.y * n + j
                        let x0 = Double(c.x) - 0.5 + Double(i) * step, y0 = Double(c.y) - 0.5 + Double(j) * step
                        let corners = [SIMD2(x0, y0), SIMD2(x0 + step, y0), SIMD2(x0 + step, y0 + step), SIMD2(x0, y0 + step)]
                        let hs = [SIMD2(gx, gy), SIMD2(gx + 1, gy), SIMD2(gx + 1, gy + 1), SIMD2(gx, gy + 1)].map(height)
                        // A doorway: the hull's foot left open across it, as high as a door.
                        if door {
                            let near = hull.reach(SIMD2(x0 + step / 2, y0 + step / 2))
                            if near.door, near.distance < step, hs.max()! < StationHull.doorTop * 1.4 { continue }
                        }
                        let world = zip(corners, hs).map { v3(st.offset.x + $0.0.x, $0.1, st.offset.y + $0.0.y) }
                        let base = Int32(glass.v.count)
                        glass.v += world
                        glass.uv += corners.map { CGPoint(x: $0.x + 0.5, y: $0.y + 0.5) }
                        glass.i += [base, base + 1, base + 2, base, base + 2, base + 3]
                    }
                }
            }
            // The sill the glass stands on, along every stretch of its foot but the doorways.
            let foot = SCNNode()
            for f in hull.feet where !f.door {
                let mid = (f.a + f.b) / 2, along = f.b - f.a
                let across = abs(along.x) < abs(along.y)   // the stretch runs along z
                var inward = across ? SIMD2(1.0, 0) : SIMD2(0, 1.0)
                if !hull.covers(mid + inward * 0.25) { inward = -inward }
                let sill = SCNBox(width: across ? 0.07 : 1, height: 0.06, length: across ? 1 : 0.07, chamferRadius: 0)
                sill.firstMaterial = Bulkhead.steel
                let n = SCNNode(geometry: sill)
                let at = mid + inward * 0.035
                n.position = v3(st.offset.x + at.x, 0.03, st.offset.y + at.y)
                foot.addChildNode(n)
            }
            let flatFoot = foot.flattenedClone()
            flatFoot.categoryBitMask = Pick.scenery
            w.dome.addChildNode(flatFoot)
            if !glass.v.isEmpty {
                let g = SCNGeometry(sources: [SCNGeometrySource(vertices: glass.v), SCNGeometrySource(textureCoordinates: glass.uv)],
                                    elements: [SCNGeometryElement(indices: glass.i, primitiveType: .triangles)])
                g.firstMaterial = WallPanel.hullGlass
                let n = SCNNode(geometry: g)
                n.categoryBitMask = Pick.scenery
                n.renderingOrder = 90
                w.dome.addChildNode(n)
            }
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

/// The walk's materials besides the walls' own (`Bulkhead`): the hull's glass, the bare deck under it, and the
/// key a colour is cached by.
enum WallPanel {
    static func key(_ c: NSColor) -> String {
        guard let s = c.usingColorSpace(.sRGB) else { return "?" }
        return String(format: "%.2f/%.2f/%.2f", s.redComponent, s.greenComponent, s.blueComponent)
    }

    /// The bare deck under the hull where the station has no floor of its own: a tile of the hull's plate, darker.
    static let bareDeck: SCNGeometry = {
        let g = SCNPlane(width: 1, height: 1)
        let m = lit(NSColor(rgb: Props.hullPlate).darker(0.35))
        g.firstMaterial = m
        return g
    }()

    /// The hull's glass: the dome's panes, one to a tile, laid on by where they are.
    static let hullGlass: SCNMaterial = {
        let m = glass.copy() as! SCNMaterial
        m.diffuse.wrapS = .repeat
        m.diffuse.wrapT = .repeat
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
}
