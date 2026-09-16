// The view that takes the input, and the camera it moves: gestures, keys, hover, focus and the remembered view.

import AppKit
import SceneKit

/// SCNView that reports hovers, double-clicks and trackpad gestures.
final class StationView: SCNView {
    var onHover: ((SCNNode?) -> Void)?
    var onDoubleClick: ((SCNNode?) -> Void)?
    var onZoom: ((Double, NSPoint?) -> Void)?
    var onRotate: ((Double, NSPoint?) -> Void)?
    var onPan: ((Double, Double) -> Void)?
    var onTilt: ((Double) -> Void)?
    var onKey: ((String) -> Bool)?
    /// Space held down, and let go: the station runs faster while it is held.
    var onHold: ((Bool) -> Void)?
    private var spaceHeld = false
    private func releaseSpace() { if spaceHeld { spaceHeld = false; onHold?(false) } }
    /// Held WASD keys as a screen-relative direction (x right, y up) and Q/E as a zoom direction (+1 in), zero when none are down.
    var onMove: ((SIMD2<Double>, Double) -> Void)?
    private var heldKeys: Set<String> = []
    var onClick: ((SCNNode?) -> Void)?
    /// The overlay's say on a point first: true when the HUD takes the hover or the click, so the scene under it does not.
    var hudTakesPoint: ((NSPoint) -> Bool)?
    var onHUDClick: ((NSPoint) -> Bool)?
    var onContextMenu: ((SCNNode?, NSEvent) -> Void)?
    private var tracking: NSTrackingArea?
    private var downPoint = NSPoint.zero

    override func keyDown(with event: NSEvent) {
        if event.charactersIgnoringModifiers == " ", event.modifierFlags.intersection([.command, .control, .option]).isEmpty {
            if !spaceHeld { spaceHeld = true; onHold?(true) }
            return
        }
        if let chars = event.charactersIgnoringModifiers?.lowercased(), Self.moveKeys[chars] != nil,
           event.modifierFlags.intersection([.command, .control, .option]).isEmpty {
            if !event.isARepeat { heldKeys.insert(chars); moveChanged() }
            return
        }
        if let chars = event.charactersIgnoringModifiers, onKey?(chars) == true { return }
        super.keyDown(with: event)
    }
    override func keyUp(with event: NSEvent) {
        if event.charactersIgnoringModifiers == " " { releaseSpace(); return }
        if let chars = event.charactersIgnoringModifiers?.lowercased(), heldKeys.remove(chars) != nil { moveChanged(); return }
        super.keyUp(with: event)
    }
    override func flagsChanged(with event: NSEvent) {
        if !event.modifierFlags.intersection([.command, .control, .option]).isEmpty { releaseSpace() }
        // A modifier pressed mid-move would swallow the key-up: let go of everything.
        if !heldKeys.isEmpty, !event.modifierFlags.intersection([.command, .control, .option]).isEmpty { heldKeys = []; moveChanged() }
        super.flagsChanged(with: event)
    }
    override func resignFirstResponder() -> Bool {
        releaseSpace()
        if !heldKeys.isEmpty { heldKeys = []; moveChanged() }
        return super.resignFirstResponder()
    }
    private static let moveKeys: [String: SIMD3<Double>] = ["w": SIMD3(0, 1, 0), "s": SIMD3(0, -1, 0), "a": SIMD3(-1, 0, 0), "d": SIMD3(1, 0, 0),
                                                            "e": SIMD3(0, 0, 1), "q": SIMD3(0, 0, -1)]
    private func moveChanged() {
        var v = SIMD3<Double>(0, 0, 0)
        for k in heldKeys { v += Self.moveKeys[k]! }
        onMove?(SIMD2(v.x, v.y), v.z)
    }
    /// The cursor's view location, or nil when it is outside the view.
    private func cursor(_ event: NSEvent) -> NSPoint? {
        let p = convert(event.locationInWindow, from: nil)
        return bounds.contains(p) ? p : nil
    }
    private var dragAllowed = false

    override var mouseDownCanMoveWindow: Bool { false }
    override var acceptsFirstResponder: Bool { true }
    /// A key-up never arrives once the window loses focus: let go of space then, so the station is not left running fast.
    private var resignObserver: NSObjectProtocol?
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let o = resignObserver { NotificationCenter.default.removeObserver(o); resignObserver = nil }
        guard let window else { return }
        resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
            self?.releaseSpace()
        }
    }

    override func magnify(with event: NSEvent) { onZoom?(1 + event.magnification, cursor(event)) }
    override func rotate(with event: NSEvent) { onRotate?(Double(event.rotation) * .pi / 180, cursor(event)) }
    override func scrollWheel(with event: NSEvent) {
        // Two fingers slide the view; a mouse wheel reports in lines, so scale it up to feel like pixels.
        let k = event.hasPreciseScrollingDeltas ? 1.0 : 10.0
        if event.modifierFlags.contains(.option) { onZoom?(1 - Double(event.scrollingDeltaY) * 0.01, cursor(event)) }
        else { onPan?(Double(event.scrollingDeltaX) * k, Double(event.scrollingDeltaY) * k) }
    }
    override func mouseDragged(with event: NSEvent) {
        guard dragAllowed else { return }
        onTilt?(Double(event.deltaY))
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(t)
        tracking = t
    }

    /// The named thing under the point: a prop's parts are unnamed, the prop itself carries the name.
    private func node(at p: NSPoint) -> SCNNode? {
        var n = hitTest(p, options: [.boundingBoxOnly: true, .firstFoundOnly: true]).first?.node
        while let here = n, here.name == nil, let up = here.parent { n = up }
        return n
    }

    override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if hudTakesPoint?(p) == true { return }
        onHover?(node(at: p))
    }

    override func mouseExited(with event: NSEvent) { onHover?(nil) }
    override func rightMouseDown(with event: NSEvent) { onContextMenu?(node(at: convert(event.locationInWindow, from: nil)), event) }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        dragAllowed = p.y < bounds.height - 32
        downPoint = p
        if event.clickCount == 2 { onDoubleClick?(node(at: p)) }
        super.mouseDown(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if event.clickCount == 1, hypot(p.x - downPoint.x, p.y - downPoint.y) < 3 {
            if onHUDClick?(p) != true { onClick?(node(at: p)) }
        }
        super.mouseUp(with: event)
    }
}

extension StationController {
    // MARK: kicking

    /// Right-click on an office that a peer or GitHub put here: offer to kick it.
    func showContextMenu(for name: String?, event: NSEvent) {
        guard let name, name.hasPrefix("room:") || name.hasPrefix("box:") else { return }
        let key = String(name.dropFirst(name.hasPrefix("room:") ? 5 : 4))
        let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2, let station = fleet.stations[parts[0]], let room = station.rooms[parts[1]], !room.key.hasPrefix("kind:") else { return }
        let menu = NSMenu()
        if room.worktree == nil {
            let item = NSMenuItem(title: "Kick \(room.name)", action: #selector(kickOffice(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = key
            menu.addItem(item)
        } else {
            menu.addItem(withTitle: "\(room.name) is your own checkout", action: nil, keyEquivalent: "")
        }
        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }

    @objc private func kickOffice(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        enqueue { [self] in
            let roomKey = key.split(separator: "|", maxSplits: 1).map(String.init).last ?? ""
            for m in minions.values where m.isCrew && m.home.key == roomKey { m.activity = .sleeping; m.busy = false; send(m, to: .quarters) }
            handle(world.kick(roomKey: key))
            flushScene()
        }
    }

    func setView(yawDegrees: Double, pitchDegrees: Double, zoom: Double) {
        viewPinned = true
        enqueue { [self] in
            userYaw = yawDegrees * .pi / 180; userPitch = pitchDegrees * .pi / 180; userZoom = zoom
            rig.eulerAngles.y = viewYaw + userYaw; pitchNode.eulerAngles.x = userPitch
        }
    }

    /// Clicking a minion re-asks GitHub about its repo: its branch's PR, commits and releases.
    func poke(minionId: String) {
        guard let m = minions[minionId], let station = fleet.stations[m.station] else { return }
        let room = station.rooms[m.home.key]
        let root = room?.repoRoot ?? world.repoRoots.first { $0.value.repo == m.home.repo }?.key
        guard let root else { return }
        github.invalidate(repoRoot: root)
        for r in station.rooms.values where r.repoRoot == root {
            if let b = r.branch { github.refresh(branch: b, repoRoot: root) }
            if let w = r.worktree { github.refreshCommits(worktree: w) }
        }
        github.refreshReleases(repoRoot: root)
        logEvent("asking github about \(m.home.repo)…")
        // A little hop so the click feels acknowledged.
        m.node.runAction(.sequence([.moveBy(x: 0, y: 0.25, z: 0, duration: 0.12), .moveBy(x: 0, y: -0.25, z: 0, duration: 0.12)]))
    }

    func resetView() {
        enqueue { [self] in userZoom = 1; userYaw = 0; userPitch = -.pi / 6; userPan = .zero; focused = nil }
    }

    /// Slides the view by a screen offset: dx to the right, dy down (as drags and scrolls report it).
    func pan(byPixels dx: Double, _ dy: Double) {
        focused = nil
        following = nil
        userDriving = 0.5
        let yaw = viewYaw + userYaw
        let unitsPerPixel = 2 * cameraNode.camera!.orthographicScale / Double(max(1, viewSize.height))
        let right = SIMD2(cos(yaw), -sin(yaw))
        let forward = SIMD2(-sin(yaw), -cos(yaw))
        userPan -= (right * dx - forward * dy) * unitsPerPixel
    }

    /// The point on the floor plane under a view location, in world x/z.
    func groundPoint(at p: NSPoint) -> SIMD2<Double>? {
        let near = view.unprojectPoint(SCNVector3(p.x, p.y, 0))
        let far = view.unprojectPoint(SCNVector3(p.x, p.y, 1))
        let dy = Double(far.y - near.y)
        guard abs(dy) > 1e-6 else { return nil }
        let t = -Double(near.y) / dy
        return SIMD2(Double(near.x) + Double(far.x - near.x) * t, Double(near.z) + Double(far.z - near.z) * t)
    }

    /// Orthographic half-height that fits a footprint of the given span at the current aspect.
    /// Where the default isometric camera should look to centre these stations, and the half-extent
    /// they cover on screen (in ground units across, and along the view before the tilt foreshortens it).
    /// Each station's own footprint is projected, so an L-shaped fleet isn't framed by its empty corner.
    func frame(for stations: [Station]) -> (focus: SIMD2<Double>, half: SIMD2<Double>) {
        let yaw = viewYaw
        var lo = SIMD2<Double>(.infinity, .infinity), hi = SIMD2<Double>(-.infinity, -.infinity)
        for st in stations {
            let b = st.bounds
            for (x, z) in [(Double(b.min.x), Double(b.min.y)), (Double(b.max.x) + 1, Double(b.min.y)),
                           (Double(b.min.x), Double(b.max.y) + 1), (Double(b.max.x) + 1, Double(b.max.y) + 1)] {
                let wx = x + st.offset.x, wz = z + st.offset.y
                let u = wx * cos(yaw) - wz * sin(yaw), v = wx * sin(yaw) + wz * cos(yaw)
                lo = pointwiseMin(lo, SIMD2(u, v)); hi = pointwiseMax(hi, SIMD2(u, v))
            }
        }
        guard lo.x.isFinite else { return (SIMD2(0, 0), SIMD2(6, 6)) }
        let c = (lo + hi) / 2
        return (SIMD2(c.x * cos(yaw) + c.y * sin(yaw), -c.x * sin(yaw) + c.y * cos(yaw)), (hi - lo) / 2)
    }

    /// Orthographic half-height that fits a projected half-extent at the default tilt.
    func fitScale(half: SIMD2<Double>) -> Double {
        let aspect = max(0.6, Double(viewSize.width / max(1, viewSize.height)))
        let pitch = -Double.pi / 6
        return max(half.y * abs(sin(pitch)) + 3.0, (half.x + 1.5) / aspect)
    }

    /// Pans and zooms onto one station, or back to the whole fleet.
    func focus(on stationName: String?) {
        enqueue { [self] in focusNow(on: stationName) }
    }

    /// Focuses the Nth station: your own in fleet order, then peers' as they sit in the void.
    func focus(onIndex i: Int) {
        enqueue { [self] in
            let names = fleet.ordered.map(\.name)
            guard names.indices.contains(i) else { return }
            focusNow(on: names[i])
        }
    }

    /// The stations the camera frames: the whole fleet.
    var shownStations: [Station] { Array(fleet.stations.values) }

    func focusNow(on stationName: String?) {
        focused = stationName
        guard let name = stationName, let station = fleet.stations[name] else {
            userPan = .zero; userZoom = 1; userZoomChanged = true; return
        }
        let (center, half) = frame(for: [station])
        userPan = center - targetFocus
        userZoom = min(6, max(0.4, fitScale(half: targetHalf) / fitScale(half: half)))
        userZoomChanged = true
    }

    /// Pans onto one room of one station and holds a zoom there: for a picture of the bath, say.
    /// The room is named by key (`kind:bath`) or by the word after `kind:`.
    func look(at roomName: String, in stationName: String, zoom: Double) {
        enqueue { [self] in
            guard let station = fleet.stations[stationName],
                  let room = station.rooms[roomName] ?? station.rooms["kind:" + roomName] else { return }
            let cx = room.cells.map { Double($0.x) + 0.5 }.reduce(0, +) / Double(room.cells.count)
            let cz = room.cells.map { Double($0.y) + 0.5 }.reduce(0, +) / Double(room.cells.count)
            focused = nil
            userPan = SIMD2(cx + station.offset.x, cz + station.offset.y) - targetFocus
            userZoom = zoom
            userZoomChanged = true
        }
    }

    /// The camera goes with one minion: near enough to see what it is up to, not on top of it. Zooming
    /// and turning still work while it does; a pan, Esc or a click on the floor lets go.
    func follow(minionId id: String, zoom: Double? = nil) {
        guard minions[id] != nil else { return }
        following = id
        focused = nil
        if let zoom { userZoom = zoom; userZoomChanged = true }
        else if userZoom < 2.5 { userZoom = 3; userZoomChanged = true }
    }

    /// Follow by name, for the command line: the minion's id, the word after its colon, or its home's name.
    func follow(named name: String, zoom: Double? = nil) {
        enqueue { [self] in
            let want = name.lowercased()
            let exact = minions.values.first { $0.id == name || $0.id.hasSuffix(":" + name) || $0.home.name == name }
            let loose = minions.values.sorted { $0.id < $1.id }.first { $0.id.lowercased().contains(want) || $0.home.name.lowercased().contains(want) }
            if let m = exact ?? loose { follow(minionId: m.id, zoom: zoom) }
        }
    }

    func saveView() {
        let d = UserDefaults.standard
        d.set(userYaw, forKey: "view.yaw"); d.set(userPitch, forKey: "view.pitch"); d.set(userZoom, forKey: "view.zoom")
        d.set(userPan.x, forKey: "view.panx"); d.set(userPan.y, forKey: "view.pany")
        d.set(focused ?? "", forKey: "view.focus")
    }

    func restoreView() {
        let d = UserDefaults.standard
        guard d.object(forKey: "view.zoom") != nil else { return }
        if d.integer(forKey: "view.layout") != 21 {   // the fleet was laid out differently: forget the old pan
            d.set(21, forKey: "view.layout"); d.removeObject(forKey: "view.panx"); d.removeObject(forKey: "view.pany")
        }
        userYaw = d.double(forKey: "view.yaw"); userPitch = d.double(forKey: "view.pitch")
        rig.eulerAngles.y = viewYaw + userYaw; pitchNode.eulerAngles.x = userPitch
        let f = d.string(forKey: "view.focus") ?? ""
        if !f.isEmpty, fleet.stations[f] != nil {
            focusNow(on: f)
        } else {
            userZoom = d.double(forKey: "view.zoom"); userPan = SIMD2(d.double(forKey: "view.panx"), d.double(forKey: "view.pany"))
            // A remembered pan from an older layout can point at empty space: drop it if it left the fleet.
            let b = fleet.worldBounds
            let p = targetFocus + userPan
            if p.x < b.min.x - 4 || p.x > b.max.x + 4 || p.y < b.min.y - 4 || p.y > b.max.y + 4 { userPan = .zero }
        }
        cameraNode.camera!.orthographicScale = fitScale(half: targetHalf) / userZoom
        rig.position.x = targetFocus.x + userPan.x; rig.position.z = targetFocus.y + userPan.y
    }
}
