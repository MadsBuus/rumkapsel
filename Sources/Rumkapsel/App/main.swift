import AppKit
import ServiceManagement
import Sparkle
import SwiftUI

enum WindowPlace {
    static let station = "windowPlace"
    static let playbook = "playbookPlace"

    private static func number(_ screen: NSScreen) -> Int? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.intValue
    }

    static func save(_ w: NSWindow, as key: String = station) {
        guard let screen = w.screen, !w.styleMask.contains(.fullScreen) else { return }
        let f = w.frame, s = screen.frame
        UserDefaults.standard.set(["screen": number(screen) ?? 0, "x": f.minX, "y": f.minY, "w": f.width, "h": f.height,
                                   "sx": s.minX, "sy": s.minY, "sw": s.width, "sh": s.height], forKey: key)
    }

    private static func fromAutosave() -> [String: Any]? {
        guard let text = UserDefaults.standard.string(forKey: "NSWindow Frame RumkapselMain") else { return nil }
        let n = text.split(separator: " ").compactMap { Double($0) }
        guard n.count >= 8 else { return nil }
        return ["x": n[0], "y": n[1], "w": n[2], "h": n[3], "sx": n[4], "sy": n[5], "sw": n[6], "sh": n[7]]
    }

    static func restore(_ w: NSWindow, as key: String = station) -> Bool {
        guard let d = UserDefaults.standard.dictionary(forKey: key) ?? (key == station ? fromAutosave() : nil), let x = d["x"] as? Double, let y = d["y"] as? Double,
              let width = d["w"] as? Double, let height = d["h"] as? Double else { return false }
        let id = d["screen"] as? Int
        let was = NSRect(x: d["sx"] as? Double ?? 0, y: d["sy"] as? Double ?? 0, width: d["sw"] as? Double ?? 0, height: d["sh"] as? Double ?? 0)
        guard let screen = NSScreen.screens.first(where: { number($0) == id }) ?? NSScreen.screens.first(where: { $0.frame == was || $0.visibleFrame == was }) else { return false }
        let room = screen.visibleFrame
        var f = NSRect(x: x, y: y, width: min(width, room.width), height: min(height, room.height))
        f.origin.x = min(max(f.minX, room.minX), room.maxX - f.width)
        f.origin.y = min(max(f.minY, room.minY), room.maxY - f.height)
        w.setFrame(f, display: false)
        return true
    }
}

enum Scripted {
    static let run = CommandLine.arguments.contains { $0 == "--scenarios" || $0 == "--snapshot" || $0 == "--dump-floor" || $0 == "--dump-colors" || $0 == "--dump-facts" || $0 == "--dump-bodies" || $0 == "--replay" || $0.hasSuffix("-tests") }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, SPUUpdaterDelegate, NSMenuDelegate {
    var window: NSWindow!
    var controller: StationController!
    private var dumpSignal: DispatchSourceSignal?
    var musicItem: NSMenuItem!
    var floatItem: NSMenuItem!
    var viewMenu: NSMenu!
    var updater: SPUStandardUpdaterController!
    var settingsWindow: NSWindow?
    var notesWindow: NSWindow?
    var galleryWindow: NSWindow?
    var gallery: GalleryController?
    var playbookWindow: NSWindow?
    var playbook: PlaybookController?
    var simulatorWindow: NSWindow?
    var simulator: SimulatorController?
    private var frameBeat: Timer?
    private var scenarios: ScenarioRunner?
    let settingsModel = SettingsModel()
    static let feedbackRepo = "MadsBuus/rumkapsel"

    func applicationDidFinishLaunching(_ notification: Notification) {
        let inBundle = Bundle.main.bundleURL.pathExtension == "app"
        let headless = CommandLine.arguments.contains("--snapshot") || CommandLine.arguments.contains("--demo")
        updater = SPUStandardUpdaterController(startingUpdater: inBundle && !headless, updaterDelegate: self, userDriverDelegate: nil)
        let args = CommandLine.arguments
        let demo = args.contains("--demo")
        let simulatorOnly = args.contains("--simulator")
        let playbookOnly = args.contains("--playbook")
        let snapshotPath = args.firstIndex(of: "--snapshot").flatMap { args.count > $0 + 1 ? args[$0 + 1] : nil }

        if args.contains(where: { $0 == "--scenarios" || $0.hasSuffix("-tests") }) { Words.pinned = Vocabulary() }
        if args.contains("--rule-tests") { RuleTests.run() }
        if args.contains("--work-tests") { WorkTests.run() }
        if args.contains("--deploy-tests") { DeployTests.run() }
        if args.contains("--github-tests") { GitHubTests.run() }
        if args.contains("--pipeline-tests") { PipelineTests.run() }
        if args.contains("--setup-tests") { SetupTests.run() }
        if args.contains("--layout-tests") { LayoutTests.run() }
        if args.contains("--spacelog-tests") { SpaceLogTests.run() }
        if args.contains("--look-tests") { LookTests.run() }
        if args.contains("--dump-colors") { ColorDump.run() }
        if args.contains("--bake-plating") { Plating.bake(FlightCraft.Materials.families) }
        if args.contains("--bake-walls") { Bulkhead.bake() }
        if args.contains("--bake-detail") { Detail.bake() }
        if args.contains("--bake-suits") { Suit.bake() }
        if let i = args.firstIndex(of: "--look-dev"), args.count > i + 1 { LookDev.run(out: args[i + 1], shot: args.count > i + 2 ? args[i + 2] : "hull") }
        if let i = args.firstIndex(of: "--dump-floor") { FloorDump.run(theme: args.count > i + 1 ? args[i + 1] : "classic") }
        if args.contains("--idle-tests") { IdleTests.run() }
        if args.contains("--walk-tests") { WalkTests.run() }
        if args.contains("--sim-tests") { SimulationTests.run() }
        if args.contains("--playback-tests") { PlaybackTests.run() }
        if args.contains("--intake-tests") { IntakeTests.run() }
        if args.contains("--log-tests") { LogTests.run() }
        if let i = args.firstIndex(of: "--replay"), args.count > i + 1 {
            Replay.run(args[i + 1], crate: args.firstIndex(of: "--crate").flatMap { args.count > $0 + 1 ? args[$0 + 1] : nil })
        }
        if let i = args.firstIndex(of: "--watch-diag") { GitHubDiag.watch(seconds: args.count > i + 1 ? Double(args[i + 1]) ?? 300 : 300) }
        if let i = args.firstIndex(of: "--github-diag") {
            let seconds = args.count > i + 1 ? Double(args[i + 1]) ?? 120 : 120
            let only = args.firstIndex(of: "--repo").flatMap { args.count > $0 + 1 ? args[$0 + 1] : nil }
            GitHubDiag.run(seconds: seconds, only: only)
        }
        if let i = args.firstIndex(of: "--scenarios") {
            let next = args.count > i + 1 ? args[i + 1] : nil
            let filter = (next?.hasPrefix("--") ?? true) ? nil : next
            scenarios = ScenarioRunner(filter: filter, verbose: args.contains("--scenarios-verbose"))
            scenarios?.run()
            return
        }

        buildMenu()
        ConfigStore.shared.onChange = { [weak self] old, new in self?.controller.applyConfigChange(from: old, to: new) }
        signal(SIGUSR1, SIG_IGN)
        dumpSignal = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
        dumpSignal?.setEventHandler { [weak self] in self?.controller.dumpState() }
        dumpSignal?.resume()

        let size = NSSize(width: 640, height: 440)
        window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
        window.title = "rumkapsel"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = false
        window.backgroundColor = Palette.void
        window.minSize = NSSize(width: 320, height: 240)
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let floatOn = UserDefaults.standard.bool(forKey: "float")
        window.level = floatOn ? .floating : .normal
        window.isReleasedWhenClosed = false

        controller = StationController(frame: NSRect(origin: .zero, size: size), demo: demo, simulated: simulatorOnly || playbookOnly)
        controller.onChangeRepo = { [weak self] repo in self?.showSettings(repo: repo) }
        window.contentView = controller.view
        if !Scripted.run { DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in self?.controller.prepareFlight() } }
        controller.viewSize = controller.view.bounds.size
        NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: controller.view, queue: .main) { [weak self] _ in
            guard let self else { return }
            controller.viewSize = controller.view.bounds.size
        }
        controller.view.postsFrameChangedNotifications = true
        menuNeedsUpdate(viewMenu)

        let remembers = !Scripted.run && !simulatorOnly && !playbookOnly
        if !(remembers && WindowPlace.restore(window)), let screen = NSScreen.main {
            let f = screen.visibleFrame
            window.setFrameOrigin(NSPoint(x: f.maxX - window.frame.width - 24, y: f.minY + 24))
        }
        if remembers {
            for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification, NSWindow.didChangeScreenNotification] {
                NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    if let w = self?.window { WindowPlace.save(w) }
                }
            }
        }
        if !simulatorOnly && !playbookOnly {
            if Scripted.run {
                window.orderBack(nil)
            } else {
                window.makeKeyAndOrderFront(nil)
                window.makeFirstResponder(controller.view)
            }
        }

        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.controller.refreshGitHub()
        }
        let musicOn = UserDefaults.standard.object(forKey: "music") as? Bool ?? false
        controller.drone.isEnabled = musicOn && snapshotPath == nil
        musicItem.state = musicOn ? .on : .off
        controller.drone.start()

        func num(_ flag: String) -> Double? { args.firstIndex(of: flag).flatMap { args.count > $0 + 1 ? Double(args[$0 + 1]) : nil } }
        if num("--yaw") != nil || num("--pitch") != nil || num("--zoom") != nil {
            controller.setView(yawDegrees: num("--yaw") ?? 0, pitchDegrees: num("--pitch") ?? -30, zoom: num("--zoom") ?? 1)
        }
        if let i = args.firstIndex(of: "--focus"), args.count > i + 1 {
            let name = args[i + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [self] in controller.focus(on: name) }
        }
        if let i = args.firstIndex(of: "--share-as"), args.count > i + 1 {
            controller.peers.start(name: args[i + 1])
        }
        if args.contains("--log") {
            DispatchQueue.main.asyncAfter(deadline: .now() + max(1, (num("--delay") ?? 4) - 3)) { [self] in controller.toggleSpaceLog() }
        }
        if let i = args.firstIndex(of: "--story"), args.count > i + 1, let id = try? CrateID(text: args[i + 1]) {
            DispatchQueue.main.asyncAfter(deadline: .now() + max(1, (num("--delay") ?? 4) - 1)) { [weak self] in
                guard let station = self?.simulator?.station ?? self?.controller else { return }
                station.enqueue { station.openStory(id) }
            }
        }
        if let i = args.firstIndex(of: "--card"), args.count > i + 1 {
            let names = args[i + 1].split(separator: ",").map(String.init)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                guard let station = self?.simulator?.station ?? self?.controller else { return }
                station.enqueue { station.world.announce(new: names) }
            }
        }
        if let i = args.firstIndex(of: "--settings"), args.count > i + 1 {
            let repo = args[i + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + max(1, (num("--delay") ?? 4) - 2)) { [weak self] in self?.showSettings(repo: repo) }
        }
        let galleryMode = args.contains("--gallery")
        if galleryMode { openGallery() }
        let playbookMode = args.contains("--playbook")
        if playbookMode {
            if args.contains("--entries") {
                for e in Playbook.entries { print(e.name) }
                exit(0)
            }
            openPlaybook(activating: false)
            let wanted = args.firstIndex(of: "--entry").flatMap { args.count > $0 + 1 ? Playbook.find(args[$0 + 1]) : nil }
            playbook?.model.play(wanted ?? 0)
        }
        if simulatorOnly { openSimulator() }
        if let sim = simulator {
            if num("--yaw") != nil || num("--pitch") != nil || num("--zoom") != nil {
                sim.station.setView(yawDegrees: num("--yaw") ?? 0, pitchDegrees: num("--pitch") ?? -30, zoom: num("--zoom") ?? 1)
            }
            if let i = args.firstIndex(of: "--focus"), args.count > i + 1 {
                let name = args[i + 1]
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { sim.station.focus(on: name) }
            }
        }
        if let i = args.firstIndex(of: "--look"), args.count > i + 1, let f = args.firstIndex(of: "--focus"), args.count > f + 1 {
            let room = args[i + 1], stationName = args[f + 1], zoom = num("--zoom") ?? 3
            for at in [1.0, max(1.5, (num("--delay") ?? 4) - 3)] {
                DispatchQueue.main.asyncAfter(deadline: .now() + at) { [weak self] in
                    (self?.simulator?.station ?? self?.controller)?.look(at: room, in: stationName, zoom: zoom)
                }
            }
        }
        if let i = args.firstIndex(of: "--follow"), args.count > i + 1 {
            let who = args[i + 1]
            for at in [1.0, max(1.5, (num("--delay") ?? 4) - 3)] {
                DispatchQueue.main.asyncAfter(deadline: .now() + at) { [weak self] in
                    (self?.simulator?.station ?? self?.controller)?.follow(named: who, zoom: num("--zoom"))
                }
            }
        }
        if let at = num("--walk") {
            DispatchQueue.main.asyncAfter(deadline: .now() + at) { [weak self] in (self?.simulator?.station ?? self?.controller)?.toggleWalk() }
        }
        if let i = args.firstIndex(of: "--simulate"), args.count > i + 1 {
            if !simulatorOnly { openSimulator() }
            let names = args[i + 1].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            for (k, n) in names.enumerated() {
                DispatchQueue.main.asyncAfter(deadline: .now() + 4 + Double(k) * 2) { [weak self] in self?.simulator?.model.press(n) }
            }
        }
        if let i = args.firstIndex(of: "--dump-bodies") {
            let next = args.count > i + 1 ? args[i + 1] : nil
            let seconds = next.flatMap(Double.init) ?? 20
            let only = next.flatMap { Double($0) == nil ? $0 : nil } ?? (args.count > i + 2 ? args[i + 2] : nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
                FileHandle.standardError.write((self!.controller.bodiesReport(only: only) + "\n").data(using: .utf8)!)
                exit(0)
            }
        }
        if let i = args.firstIndex(of: "--dump-facts") {
            let next = args.count > i + 1 ? args[i + 1] : nil
            let seconds = next.flatMap(Double.init) ?? 25
            let only = next.flatMap { Double($0) == nil ? $0 : nil } ?? (args.count > i + 2 ? args[i + 2] : nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
                FileHandle.standardError.write((self!.controller.factsReport(only: only) + "\n").data(using: .utf8)!)
                exit(0)
            }
        }
        if let path = snapshotPath {
            FileHandle.standardError.write("snapshot scheduled -> \(path)\n".data(using: .utf8)!)
            frameBeat = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { _ = (self?.simulator?.station.view ?? self?.controller.view)?.snapshot() }
            }
            let frames = max(1, Int(num("--frames") ?? 1)), every = num("--every") ?? 0.5
            func shot(_ k: Int) {
                let url = URL(fileURLWithPath: path)
                let name = frames == 1 ? path : url.deletingPathExtension().path + String(format: "-%03d.", k) + url.pathExtension
                if galleryMode { gallery?.snapshot(to: name) }
                else if playbookMode { playbook?.snapshot(to: name) }
                else if let sim = simulator { sim.snapshot(to: name) }
                else { controller.snapshot(to: name) }
                if let view = settingsWindow?.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                    view.cacheDisplay(in: view.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: url.deletingPathExtension().path + "-settings.png"))
                }
                guard k + 1 == frames else { return }
                if let sim = simulator {
                    FileHandle.standardError.write(("--- board ---\n" + sim.model.boardLines.joined(separator: "\n") + "\n").data(using: .utf8)!)
                    sim.station.dumpState()
                    FileHandle.standardError.write(("--- simulator log ---\n" + sim.model.logText + "\n").data(using: .utf8)!)
                }
                let nodes = (self.simulator?.station ?? self.controller).scene.rootNode.childNodes(passingTest: { n, _ in n.geometry != nil }).count
                FileHandle.standardError.write("snapshot written; \(nodes) nodes with geometry in the scene\n".data(using: .utf8)!)
                NSApp.terminate(nil)
            }
            for k in 0..<frames {
                DispatchQueue.main.asyncAfter(deadline: .now() + (num("--delay") ?? 4) + Double(k) * every) { shot(k) }
            }
        }
    }

    private func buildMenu() {
        let main = NSMenu()

        func menu(_ title: String) -> NSMenu {
            let item = NSMenuItem()
            let sub = NSMenu(title: title)
            item.submenu = sub
            main.addItem(item)
            return sub
        }

        let app = menu("rumkapsel")
        app.addItem(withTitle: "About rumkapsel", action: #selector(about), keyEquivalent: "")
        let check = NSMenuItem(title: "Check for Updates…", action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)), keyEquivalent: "u")
        check.target = updater
        app.addItem(check)
        if Bundle.main.url(forResource: "WhatsNew", withExtension: "md") != nil {
            let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
            app.addItem(withTitle: "What's New in \(v)…", action: #selector(openWhatsNew), keyEquivalent: "")
        }
        app.addItem(.separator())
        app.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        app.addItem(.separator())
        app.addItem(withTitle: "Hide", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        app.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let edit = menu("Edit")
        for (title, selector, key) in [("Undo", "undo:", "z"), ("Redo", "redo:", "Z")] {
            edit.addItem(withTitle: title, action: Selector(selector), keyEquivalent: key)
        }
        edit.addItem(.separator())
        for (title, selector, key) in [("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"),
                                       ("Select All", "selectAll:", "a")] {
            edit.addItem(withTitle: title, action: Selector(selector), keyEquivalent: key)
        }

        let view = menu("View")
        viewMenu = view
        view.delegate = self
        view.addItem(withTitle: "Reset View", action: #selector(resetView), keyEquivalent: "r")
        let walk = view.addItem(withTitle: "Walk the Station", action: #selector(walk), keyEquivalent: "f")
        walk.keyEquivalentModifierMask = [.command, .shift]
        floatItem = view.addItem(withTitle: "Float on Top", action: #selector(toggleFloat), keyEquivalent: "f")
        floatItem.state = UserDefaults.standard.bool(forKey: "float") ? .on : .off
        musicItem = view.addItem(withTitle: "Music", action: #selector(toggleMusic), keyEquivalent: "m")

        let station = menu("Station")
        let refresh = station.addItem(withTitle: "Refresh GitHub", action: #selector(refreshGitHub), keyEquivalent: "r")
        refresh.keyEquivalentModifierMask = [.command, .shift]
        station.addItem(withTitle: "Station Log", action: #selector(toggleSpaceLog), keyEquivalent: "l")
        station.addItem(withTitle: "Neighbours", action: #selector(toggleNeighbours), keyEquivalent: "")
        station.addItem(.separator())
        station.addItem(withTitle: "Reset Colours", action: #selector(resetColors), keyEquivalent: "")
        station.addItem(withTitle: "Reset Office Layout…", action: #selector(resetOfficeLayout), keyEquivalent: "")

        let develop = menu("Develop")
        let g = develop.addItem(withTitle: "Graphics Gallery", action: #selector(openGallery), keyEquivalent: "g")
        g.keyEquivalentModifierMask = [.command, .shift]
        let play = develop.addItem(withTitle: "Playbook…", action: #selector(openPlaybook as () -> Void), keyEquivalent: "p")
        play.keyEquivalentModifierMask = [.command, .shift]
        develop.addItem(.separator())
        let bodies = develop.addItem(withTitle: "Copy Body Report", action: #selector(copyBodies), keyEquivalent: "b")
        bodies.keyEquivalentModifierMask = [.command, .shift]
        let facts = develop.addItem(withTitle: "Copy Facts Report", action: #selector(copyFacts), keyEquivalent: "l")
        facts.keyEquivalentModifierMask = [.command, .shift]
        develop.addItem(withTitle: "Restack the Yard", action: #selector(restackYard), keyEquivalent: "")
        develop.addItem(withTitle: "Skip to the Facts", action: #selector(skipToFacts), keyEquivalent: "")
        develop.addItem(.separator())
        develop.addItem(withTitle: "Rehearse Launch", action: #selector(rehearseLaunch), keyEquivalent: "")
        develop.addItem(withTitle: "Rehearse Failed Launch", action: #selector(rehearseFailedLaunch), keyEquivalent: "")

        let help = menu("Help")
        help.addItem(withTitle: "Request a Feature…", action: #selector(requestFeature), keyEquivalent: "")
        help.addItem(withTitle: "Report a Bug…", action: #selector(reportBug), keyEquivalent: "")

        NSApp.mainMenu = main
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === viewMenu else { return }
        for item in menu.items where item.representedObject as? String == "focus" { menu.removeItem(item) }
        let names = controller?.fleet.ordered.map(\.name) ?? []
        guard names.count > 1 else { return }
        var at = 0
        func put(_ item: NSMenuItem) {
            item.representedObject = "focus"
            menu.insertItem(item, at: at)
            at += 1
        }
        let all = NSMenuItem(title: "All Stations", action: #selector(focusStation(_:)), keyEquivalent: "0")
        all.tag = 0
        put(all)
        for (i, name) in names.enumerated() where i < 9 {
            let item = NSMenuItem(title: name, action: #selector(focusStation(_:)), keyEquivalent: "\(i + 1)")
            item.tag = i + 1
            put(item)
        }
        put(.separator())
    }

    @objc func about() {
        let alert = NSAlert()
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        let b = Bundle.main.infoDictionary?["RKBuild"] as? String ?? ""
        alert.messageText = "rumkapsel \(v)" + (b.isEmpty ? "" : "\nbuild \(b)")
        alert.informativeText = "Your Claude sessions and Conductor workspaces as a space station: offices per branch, commits as boxes, pull requests as colours, releases as rockets, and your crew next door.\n\nA homage to rymdkapsel by Grapefrukt."
        alert.runModal()
    }

    @objc func resetView() { controller.resetView() }
    @objc func restackYard() { controller.restackYard() }
    @objc func skipToFacts() { controller.simulation.skip() }
    @objc func walk() { controller.toggleWalk() }
    @objc func toggleSpaceLog() { controller.toggleSpaceLog() }
    @objc func toggleNeighbours() { controller.toggleNeighbours() }
    @objc func resetColors() { controller.resetColors() }
    @objc func resetOfficeLayout() { controller.resetOfficeLayout() }

    @objc func openGallery() {
        if galleryWindow == nil {
            let size = NSSize(width: 900, height: 620)
            let gc = GalleryController(frame: NSRect(origin: .zero, size: size))
            let w = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            w.title = "rumkapsel gallery"
            w.contentView = gc.view
            w.isReleasedWhenClosed = false
            w.center()
            gallery = gc
            galleryWindow = w
        }
        galleryWindow?.makeKeyAndOrderFront(nil)
        galleryWindow?.makeFirstResponder(gallery?.view)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func copy(_ text: String, what: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        FileHandle.standardError.write((text + "\n").data(using: .utf8)!)
        controller.logEvent("\(what) copied")
    }

    @objc func copyBodies() { copy(controller.bodiesReport(only: nil), what: "body report") }
    @objc func copyFacts() { copy(controller.factsReport(only: nil), what: "facts report") }
    @objc func rehearseLaunch() { controller.rehearseLaunch(.live) }
    @objc func rehearseFailedLaunch() { controller.rehearseLaunch(.failed) }

    @objc func openPlaybook() { openPlaybook(activating: true) }

    func openPlaybook(activating: Bool) {
        if playbookWindow == nil {
            let size = NSSize(width: 1100, height: 720)
            let sc = PlaybookController(frame: NSRect(origin: .zero, size: size))
            let w = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            w.title = "rumkapsel playbook"
            w.contentView = sc.view
            w.isReleasedWhenClosed = false
            if Scripted.run || !WindowPlace.restore(w, as: WindowPlace.playbook) { w.center() }
            if !Scripted.run {
                for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification, NSWindow.didChangeScreenNotification] {
                    NotificationCenter.default.addObserver(forName: name, object: w, queue: .main) { _ in WindowPlace.save(w, as: WindowPlace.playbook) }
                }
            }
            playbook = sc
            playbookWindow = w
        }
        if Scripted.run {
            playbookWindow?.orderBack(nil)
        } else if activating {
            playbookWindow?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            playbookWindow?.orderFrontRegardless()
        }
    }

    @objc func openSimulator() {
        if simulatorWindow == nil {
            let size = NSSize(width: 1060, height: 700)
            let sc = SimulatorController(frame: NSRect(origin: .zero, size: size))
            let w = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            w.title = "rumkapsel simulator"
            w.contentView = sc.view
            w.isReleasedWhenClosed = false
            w.center()
            simulator = sc
            simulatorWindow = w
            sc.onReset = { [weak self] in
                guard let self else { return }
                simulatorWindow?.close(); simulatorWindow = nil; simulator = nil
                openSimulator()
            }
        }
        if Scripted.run {
            simulatorWindow?.orderBack(nil)
        } else {
            simulatorWindow?.makeKeyAndOrderFront(nil)
            simulatorWindow?.makeFirstResponder(simulator?.station.view)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    @objc func openWhatsNew() {
        if notesWindow == nil {
            guard let url = Bundle.main.url(forResource: "WhatsNew", withExtension: "md"), let md = try? String(contentsOf: url, encoding: .utf8) else { return }
            let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
            let prepared = md.split(separator: "\n", omittingEmptySubsequences: false)
                .map { $0.hasPrefix("## ") ? "**" + $0.dropFirst(3) + "**" : $0.hasPrefix("- ") ? "•  " + $0.dropFirst(2) : String($0) }.joined(separator: "\n")
            let text: NSAttributedString
            if let a = try? AttributedString(markdown: prepared, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
                var styled = a
                styled.font = .systemFont(ofSize: 13)
                styled.foregroundColor = .labelColor
                text = NSAttributedString(styled)
            } else { text = NSAttributedString(string: md) }
            let scroll = NSTextView.scrollableTextView()
            let tv = scroll.documentView as! NSTextView
            tv.isEditable = false
            tv.textContainerInset = NSSize(width: 16, height: 14)
            tv.textStorage?.setAttributedString(text)
            tv.backgroundColor = .textBackgroundColor
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 400), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            w.contentView = scroll
            w.title = "What's new in rumkapsel \(v)"
            w.isReleasedWhenClosed = false
            w.center()
            notesWindow = w
        }
        notesWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func openSettings() { showSettings(repo: nil) }

    func showSettings(repo: String?) {
        settingsModel.config = ConfigStore.shared.current
        settingsModel.knownRepos = controller.knownRepos
        settingsModel.details = controller.repoDetails
        settingsModel.people = controller.seenPeople
        settingsModel.problems = controller.setupProblems
        let roots = settingsModel.details.compactMap { name, d in d.path.map { (name, $0) } }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let counts = roots.map { ($0.0, Discovery.worktrees(of: $0.1).count) }
            DispatchQueue.main.async { for (name, n) in counts { self?.settingsModel.details[name]?.worktrees = n } }
        }
        if let repo { settingsModel.tab = 1; settingsModel.selected = repo }
        settingsModel.launchAtLogin = SMAppService.mainApp.status == .enabled
        if settingsWindow == nil {
            let view = SettingsView(model: settingsModel,
                                    onLaunchAtLogin: { on in
                                        if on { try? SMAppService.mainApp.register() } else { try? SMAppService.mainApp.unregister() }
                                    })
            let w = NSWindow(contentViewController: NSHostingController(rootView: view))
            w.title = "rumkapsel settings"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            settingsWindow = w
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func setMusic(_ on: Bool) {
        controller.drone.isEnabled = on
        musicItem.state = on ? .on : .off
        UserDefaults.standard.set(on, forKey: "music")
    }

    private func setFloat(_ on: Bool) {
        window.level = on ? .floating : .normal
        floatItem.state = on ? .on : .off
        UserDefaults.standard.set(on, forKey: "float")
    }

    private func openIssue(kind: String, label: String) {
        var version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        if let b = Bundle.main.infoDictionary?["RKBuild"] as? String { version += " (\(b))" }
        var c = URLComponents(string: "https://github.com/\(AppDelegate.feedbackRepo)/issues/new")!
        c.queryItems = [
            URLQueryItem(name: "labels", value: label),
            URLQueryItem(name: "title", value: "\(kind): "),
            URLQueryItem(name: "body", value: "\n\n---\nrumkapsel \(version) · macOS \(ProcessInfo.processInfo.operatingSystemVersionString)"),
        ]
        if let url = c.url { NSWorkspace.shared.open(url) }
    }

    @objc func requestFeature() { openIssue(kind: "Feature", label: "enhancement") }
    @objc func reportBug() { openIssue(kind: "Bug", label: "bug") }

    // MARK: Sparkle

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        controller.announce("update available: rumkapsel \(item.displayVersionString) · press U")
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        controller.announce("you are on the latest version")
    }
    @objc func refreshGitHub() { controller.refreshGitHub() }

    @objc func focusStation(_ sender: NSMenuItem) {
        if sender.tag > 0 { controller.focus(onIndex: sender.tag - 1) } else { controller.focus(on: nil) }
    }

    @objc func toggleMusic() { setMusic(!controller.drone.isEnabled) }
    @objc func toggleFloat() { setFloat(window.level != .floating) }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        guard let world = controller?.world else { return }
        world.fleet.save()
        Fleet.writing.sync {}
        world.log.flush()
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(Scripted.run ? .accessory : .regular)
    app.run()
}
