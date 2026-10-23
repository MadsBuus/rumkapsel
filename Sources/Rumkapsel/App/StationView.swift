import AppKit
import SceneKit

final class StationView: SCNView {
    var onHover: ((SCNNode?) -> Void)?
    var onDoubleClick: ((SCNNode?, SIMD2<Double>?) -> Void)?
    var onZoom: ((Double, NSPoint?) -> Void)?
    var onRotate: ((Double, NSPoint?) -> Void)?
    var onPan: ((Double, Double) -> Void)?
    var onTilt: ((Double) -> Void)?
    var onLook: ((Double, Double) -> Bool)?
    var onKey: ((String) -> Bool)?
    var onHold: ((Bool) -> Void)?
    private var spaceHeld = false
    private func releaseSpace() { if spaceHeld { spaceHeld = false; onHold?(false) } }
    var onMove: ((SIMD2<Double>, Double) -> Void)?
    private var heldKeys: Set<String> = []
    var onClick: ((SCNNode?) -> Void)?
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
    private func cursor(_ event: NSEvent) -> NSPoint? {
        let p = convert(event.locationInWindow, from: nil)
        return bounds.contains(p) ? p : nil
    }
    private var dragAllowed = false

    override var mouseDownCanMoveWindow: Bool { false }
    override var acceptsFirstResponder: Bool { true }
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
        let k = event.hasPreciseScrollingDeltas ? 1.0 : 10.0
        if event.modifierFlags.contains(.option) { onZoom?(1 - Double(event.scrollingDeltaY) * 0.01, cursor(event)) }
        else { onPan?(Double(event.scrollingDeltaX) * k, Double(event.scrollingDeltaY) * k) }
    }
    override func mouseDragged(with event: NSEvent) {
        guard dragAllowed else { return }
        if onLook?(Double(event.deltaX), Double(event.deltaY)) == true { return }
        onTilt?(Double(event.deltaY))
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = tracking { removeTrackingArea(t) }
        let t = NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(t)
        tracking = t
    }

    private func node(at p: NSPoint) -> SCNNode? {
        var n = hitTest(p, options: [.boundingBoxOnly: true, .firstFoundOnly: true, .categoryBitMask: Pick.normal]).first?.node
        while let here = n, here.name == nil, let up = here.parent { n = up }
        return n
    }

    override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if hudTakesPoint?(p) == true { return }
        onHover?(node(at: p))
    }

    override func mouseExited(with event: NSEvent) { onHover?(nil) }

    private func floorPoint(at p: NSPoint) -> SIMD2<Double>? {
        let near = unprojectPoint(SCNVector3(p.x, p.y, 0)), far = unprojectPoint(SCNVector3(p.x, p.y, 1))
        let a = SIMD3(Double(near.x), Double(near.y), Double(near.z)), b = SIMD3(Double(far.x), Double(far.y), Double(far.z))
        guard abs(b.y - a.y) > 1e-9 else { return nil }
        let t = -a.y / (b.y - a.y)
        guard t >= 0 else { return nil }
        let hit = a + (b - a) * t
        return SIMD2(hit.x, hit.z)
    }
    override func rightMouseDown(with event: NSEvent) { onContextMenu?(node(at: convert(event.locationInWindow, from: nil)), event) }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        dragAllowed = p.y < bounds.height - 32
        downPoint = p
        if event.clickCount == 2 { onDoubleClick?(node(at: p), floorPoint(at: p)) }
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

    func showContextMenu(for name: String?, event: NSEvent) {
        guard let name, name.hasPrefix("room:") || name.hasPrefix("box:") else { return }
        let key = String(name.dropFirst(name.hasPrefix("room:") ? 5 : 4))
        let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2, let station = fleet.stations[parts[0]], let room = station.rooms[parts[1]], !room.key.hasPrefix("kind:") else { return }
        let menu = NSMenu()
        let github = NSMenuItem(title: "Open on GitHub", action: #selector(openOffice(_:)), keyEquivalent: "")
        github.target = self
        github.representedObject = name
        menu.addItem(github)
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

    func resetColors() {
        enqueue { [self] in
            fleet.resetColors()
            fleet.save()
            legendSignature = ""
            handle([.layoutChanged, .markersChanged])
            flushScene()
        }
    }

    func resetOfficeLayout() {
        let alert = NSAlert()
        alert.messageText = "Lay out every office afresh?"
        alert.informativeText = "Each office moves to where the station would put it today, in the order they opened. Offices a neighbour placed first go back where the neighbour has them."
        alert.addButton(withTitle: "Lay Out Afresh")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        enqueue { [self] in
            for station in fleet.stations.values { station.relayOffices(); world.touch(station) }
            fleet.save()
            handle([.layoutChanged])
            flushScene()
        }
    }

    @objc private func openOffice(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        enqueue { [self] in open(named: name) }
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

    func poke(minionId: String) {
        guard let m = minions[minionId], let station = fleet.stations[m.station] else { return }
        let room = station.rooms[m.home.key]
        let root = room?.repoRoot ?? world.repoRoots.first { $0.value.repo == m.home.repo }?.key
        guard let root else { return }
        github.invalidate(repoRoot: root)
        for r in station.rooms.values where r.repoRoot == root {
            if let b = r.branch { github.pulls.refresh(branch: b, repoRoot: root) }
            if let w = r.worktree { github.git.refreshCommits(worktree: w) }
        }
        github.releases.refresh(repoRoot: root)
        logEvent("asking github about \(m.home.repo)…")
        m.node.runAction(.sequence([.moveBy(x: 0, y: 0.25, z: 0, duration: 0.12), .moveBy(x: 0, y: -0.25, z: 0, duration: 0.12)]))
    }

    func resetView() {
        enqueue { [self] in userZoom = 1; userYaw = 0; userPitch = -.pi / 6; userPan = .zero; focused = nil }
    }

    func pan(byPixels dx: Double, _ dy: Double) {
        focused = nil
        following = nil
        userDriving = 0.5
        userTookView = true
        let yaw = viewYaw + userYaw
        let unitsPerPixel = 2 * cameraNode.camera!.orthographicScale / Double(max(1, viewSize.height))
        let right = SIMD2(cos(yaw), -sin(yaw))
        let forward = SIMD2(-sin(yaw), -cos(yaw))
        userPan -= (right * dx - forward * dy) * unitsPerPixel
    }

    func groundPoint(at p: NSPoint) -> SIMD2<Double>? {
        let near = view.unprojectPoint(SCNVector3(p.x, p.y, 0))
        let far = view.unprojectPoint(SCNVector3(p.x, p.y, 1))
        let dy = Double(far.y - near.y)
        guard abs(dy) > 1e-6 else { return nil }
        let t = -Double(near.y) / dy
        return SIMD2(Double(near.x) + Double(far.x - near.x) * t, Double(near.z) + Double(far.z - near.z) * t)
    }

    func frame(for stations: [Station]) -> (focus: SIMD2<Double>, half: SIMD2<Double>) {
        let yaw = viewYaw
        var lo = SIMD2<Double>(.infinity, .infinity), hi = SIMD2<Double>(-.infinity, -.infinity)
        if floorSettling, let st = stations.min(by: { $0.name < $1.name }) {
            let c = st.coreCenter
            return (SIMD2(st.offset.x + Double(c.x), st.offset.y + Double(c.y)), settlingHalf)
        }
        for st in stations {
            let b = st.bounds
            for (x, z) in [(Double(b.min.x), Double(b.min.y)), (Double(b.max.x) + 1, Double(b.min.y)),
                           (Double(b.min.x), Double(b.max.y) + 1), (Double(b.max.x) + 1, Double(b.max.y) + 1)] {
                let wx = x + st.offset.x, wz = z + st.offset.y
                let u = wx * cos(yaw) - wz * sin(yaw), v = wx * sin(yaw) + wz * cos(yaw)
                lo = pointwiseMin(lo, SIMD2(u, v)); hi = pointwiseMax(hi, SIMD2(u, v))
            }
        }
        guard lo.x.isFinite else { return (SIMD2(0, 0), settlingHalf) }
        let c = (lo + hi) / 2
        return (SIMD2(c.x * cos(yaw) + c.y * sin(yaw), -c.x * sin(yaw) + c.y * cos(yaw)), (hi - lo) / 2)
    }

    func fitScale(half: SIMD2<Double>) -> Double {
        let aspect = max(0.6, Double(viewSize.width / max(1, viewSize.height)))
        let pitch = -Double.pi / 6
        return max(half.y * abs(sin(pitch)) + 3.0, (half.x + 1.5) / aspect)
    }

    func focus(on stationName: String?) {
        enqueue { [self] in focusNow(on: stationName) }
    }

    func focus(onIndex i: Int) {
        enqueue { [self] in
            let names = fleet.ordered.map(\.name)
            guard names.indices.contains(i) else { return }
            focusNow(on: names[i])
        }
    }

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

    func look(at roomName: String, in stationName: String, zoom: Double) {
        enqueue { [self] in
            guard let station = fleet.stations[stationName] else { return }
            let areas: [String: [Cell]] = ["bay": station.hangarCells, "pad": station.hall.padCells, "deck": station.hall.deckCells,
                                           "hall": station.hall.cells, "yard": station.hall.cells + station.hall.padCells,
                                           "storage": station.hall.storageCells, "decon": station.hall.deconCells]
            if roomName == "gate", let field = station.hall.padField {
                focused = nil
                let mid = (field.from + field.to) / 2 + station.offset
                userPan = SIMD2(mid.x, mid.y - 0.6) - targetFocus
                userZoom = zoom
                userZoomChanged = true
                return
            }
            guard let cells = areas[roomName] ?? (station.rooms[roomName] ?? station.rooms["kind:" + roomName])?.cells,
                  !cells.isEmpty else { return }
            let cx = cells.map { Double($0.x) + 0.5 }.reduce(0, +) / Double(cells.count)
            let cz = cells.map { Double($0.y) + 0.5 }.reduce(0, +) / Double(cells.count)
            focused = nil
            userPan = SIMD2(cx + station.offset.x, cz + station.offset.y) - targetFocus
            userZoom = zoom
            userZoomChanged = true
        }
    }

    func follow(minionId id: String, zoom: Double? = nil) {
        guard minions[id] != nil else { return }
        following = id
        focused = nil
        if let zoom { userZoom = zoom; userZoomChanged = true }
        else if userZoom < 2.5 { userZoom = 3; userZoomChanged = true }
    }

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
        let at = targetFocus + userPan
        d.set(at.x, forKey: "view.x"); d.set(at.y, forKey: "view.z"); d.set(fitScale(half: targetHalf) / userZoom, forKey: "view.scale")
    }

    func restoreView() {
        let d = UserDefaults.standard
        guard d.object(forKey: "view.zoom") != nil else { return }
        if d.integer(forKey: "view.layout") != 21 {
            d.set(21, forKey: "view.layout"); d.removeObject(forKey: "view.panx"); d.removeObject(forKey: "view.pany")
        }
        userYaw = d.double(forKey: "view.yaw"); userPitch = d.double(forKey: "view.pitch")
        rig.eulerAngles.y = viewYaw + userYaw; pitchNode.eulerAngles.x = userPitch
        let f = d.string(forKey: "view.focus") ?? ""
        if !f.isEmpty, fleet.stations[f] != nil {
            focusNow(on: f)
        } else {
            if d.double(forKey: "view.scale") > 0 {
                userPan = SIMD2(d.double(forKey: "view.x"), d.double(forKey: "view.z")) - targetFocus
                userZoom = min(6, max(0.4, fitScale(half: targetHalf) / d.double(forKey: "view.scale")))
            } else {
                userZoom = d.double(forKey: "view.zoom"); userPan = SIMD2(d.double(forKey: "view.panx"), d.double(forKey: "view.pany"))
            }
            let b = fleet.worldBounds
            let p = targetFocus + userPan
            if p.x < b.min.x - 4 || p.x > b.max.x + 4 || p.y < b.min.y - 4 || p.y > b.max.y + 4 { userPan = .zero }
            userTookView = true
        }
        cameraNode.camera!.orthographicScale = fitScale(half: targetHalf) / userZoom
        rig.position.x = targetFocus.x + userPan.x; rig.position.z = targetFocus.y + userPan.y
    }
}
