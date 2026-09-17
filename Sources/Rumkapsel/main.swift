import AppKit
import ServiceManagement
import Sparkle
import SwiftUI

/// Whether this run was started by a script rather than by somebody at the keyboard: the scenario
/// suite, every model-only test, and a snapshot render. Such a run never takes the front: it has no
/// dock icon, and the windows it opens are ordered in behind whatever the person is actually doing.
enum Scripted {
    static let run = CommandLine.arguments.contains { $0 == "--scenarios" || $0 == "--snapshot" || $0 == "--dump-floor" || $0 == "--dump-colors" || $0.hasSuffix("-tests") }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, SPUUpdaterDelegate, NSMenuDelegate {
    var window: NSWindow!
    var controller: StationController!
    private var dumpSignal: DispatchSourceSignal?
    var musicItem: NSMenuItem!
    var floatItem: NSMenuItem!
    /// The View menu, kept so its focus lines can be laid out again whenever the fleet changes.
    var viewMenu: NSMenu!
    var updater: SPUStandardUpdaterController!
    var settingsWindow: NSWindow?
    var notesWindow: NSWindow?
    var galleryWindow: NSWindow?
    var gallery: GalleryController?
    var simulatorWindow: NSWindow?
    var simulator: SimulatorController?
    /// A scripted run's heartbeat: see below.
    private var frameBeat: Timer?
    /// The `--scenarios` suite, when that is what this run is.
    private var scenarios: ScenarioRunner?
    let settingsModel = SettingsModel()
    static let feedbackRepo = "MadsBuus/rumkapsel"

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Sparkle needs a real .app bundle; skip it for bare debug binaries, demos and snapshots.
        let inBundle = Bundle.main.bundleURL.pathExtension == "app"
        let headless = CommandLine.arguments.contains("--snapshot") || CommandLine.arguments.contains("--demo")
        updater = SPUStandardUpdaterController(startingUpdater: inBundle && !headless, updaterDelegate: self, userDriverDelegate: nil)
        let args = CommandLine.arguments
        let demo = args.contains("--demo")
        let simulatorOnly = args.contains("--simulator")
        let snapshotPath = args.firstIndex(of: "--snapshot").flatMap { args.count > $0 + 1 ? args[$0 + 1] : nil }

        // Every test run reads the log in Classic's words, whatever theme is picked: scenarios expect lines by their words.
        if args.contains(where: { $0 == "--scenarios" || $0.hasSuffix("-tests") }) { Words.pinned = Vocabulary() }
        // The crate ledger on its own: facts in every order, no station.
        if args.contains("--ledger-tests") { LedgerTests.run() }
        // Pipeline detection on its own: histories shaped like the real repositories'.
        if args.contains("--pipeline-tests") { PipelineTests.run() }
        if args.contains("--layout-tests") { LayoutTests.run() }
        if args.contains("--dump-colors") { ColorDump.run() }
        if let i = args.firstIndex(of: "--dump-floor") { FloorDump.run(theme: args.count > i + 1 ? args[i + 1] : "classic") }
        // A lounger's idle clock and pick on their own: a clock stepped by hand, rolls chosen on purpose.
        if args.contains("--idle-tests") { IdleTests.run() }
        // The walk step on its own: made-up bodies meeting on a made-up floor.
        if args.contains("--walk-tests") { WalkTests.run() }
        // The simulation on its own: a body sent about a station of the fleet's making, no scene.
        if args.contains("--sim-tests") { SimulationTests.run() }
        // The GitHub poller on its own, against the real configuration: what it asks and when, for a while.
        if let i = args.firstIndex(of: "--github-diag") {
            let seconds = args.count > i + 1 ? Double(args[i + 1]) ?? 120 : 120
            GitHubDiag.run(seconds: seconds)
        }
        // The scripted regression suite: no window, no station of its own, one after another.
        if let i = args.firstIndex(of: "--scenarios") {
            let next = args.count > i + 1 ? args[i + 1] : nil
            let filter = (next?.hasPrefix("--") ?? true) ? nil : next
            scenarios = ScenarioRunner(filter: filter, verbose: args.contains("--scenarios-verbose"))
            scenarios?.run()
            return
        }

        buildMenu()
        ConfigStore.shared.onChange = { [weak self] _ in self?.controller.applyConfigChange() }
        // `kill -USR1 <pid>` writes everything the station is doing to station.log.
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

        controller = StationController(frame: NSRect(origin: .zero, size: size), demo: demo, simulated: simulatorOnly)
        window.contentView = controller.view
        controller.viewSize = controller.view.bounds.size
        NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: controller.view, queue: .main) { [weak self] _ in
            guard let self else { return }
            controller.viewSize = controller.view.bounds.size
        }
        controller.view.postsFrameChangedNotifications = true
        menuNeedsUpdate(viewMenu)

        if !window.setFrameUsingName("RumkapselMain"), let screen = NSScreen.main {
            let f = screen.visibleFrame
            window.setFrameOrigin(NSPoint(x: f.maxX - size.width - 24, y: f.minY + 24))
        }
        window.setFrameAutosaveName("RumkapselMain")
        if !simulatorOnly {
            if Scripted.run {
                window.orderBack(nil)   // a render still needs the window drawn, just not in front
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
        let galleryMode = args.contains("--gallery")
        if galleryMode { openGallery() }
        if simulatorOnly { openSimulator() }
        // The simulator runs its own station, so the view flags have to reach that one too.
        if let sim = simulator {
            if num("--yaw") != nil || num("--pitch") != nil || num("--zoom") != nil {
                sim.station.setView(yawDegrees: num("--yaw") ?? 0, pitchDegrees: num("--pitch") ?? -30, zoom: num("--zoom") ?? 1)
            }
            if let i = args.firstIndex(of: "--focus"), args.count > i + 1 {
                let name = args[i + 1]
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { sim.station.focus(on: name) }
            }
        }
        // `--look bath` (with `--focus` naming the station) pans onto that room after the focus has settled.
        if let i = args.firstIndex(of: "--look"), args.count > i + 1, let f = args.firstIndex(of: "--focus"), args.count > f + 1 {
            let room = args[i + 1], stationName = args[f + 1], zoom = num("--zoom") ?? 3
            // Once after the focus has settled, and again shortly before the picture in case anything moved the view.
            for at in [1.0, max(1.5, (num("--delay") ?? 4) - 3)] {
                DispatchQueue.main.asyncAfter(deadline: .now() + at) { [weak self] in
                    (self?.simulator?.station ?? self?.controller)?.look(at: room, in: stationName, zoom: zoom)
                }
            }
        }
        // `--follow leo`: the camera goes with that minion, applied after the focus and again before the picture.
        if let i = args.firstIndex(of: "--follow"), args.count > i + 1 {
            let who = args[i + 1]
            for at in [1.0, max(1.5, (num("--delay") ?? 4) - 3)] {
                DispatchQueue.main.asyncAfter(deadline: .now() + at) { [weak self] in
                    (self?.simulator?.station ?? self?.controller)?.follow(named: who, zoom: num("--zoom"))
                }
            }
        }
        // A scripted run: presses the named buttons in order, two seconds apart.
        if let i = args.firstIndex(of: "--simulate"), args.count > i + 1 {
            if !simulatorOnly { openSimulator() }
            let names = args[i + 1].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            for (k, n) in names.enumerated() {
                DispatchQueue.main.asyncAfter(deadline: .now() + 4 + Double(k) * 2) { [weak self] in self?.simulator?.model.press(n) }
            }
        }
        if let path = snapshotPath {
            FileHandle.standardError.write("snapshot scheduled -> \(path)\n".data(using: .utf8)!)
            // Off screen nothing asks SceneKit for a frame, so a scripted run would never tick.
            // Ask for one thirty times a second and the station lives while the script plays.
            frameBeat = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { _ = (self?.simulator?.station.view ?? self?.controller.view)?.snapshot() }
            }
            // `--frames N --every S` takes N pictures S seconds apart from the delay on, numbered before
            // the extension, for a strip or a gif; one picture otherwise.
            let frames = max(1, Int(num("--frames") ?? 1)), every = num("--every") ?? 0.5
            func shot(_ k: Int) {
                let url = URL(fileURLWithPath: path)
                let name = frames == 1 ? path : url.deletingPathExtension().path + String(format: "-%03d.", k) + url.pathExtension
                if galleryMode { gallery?.snapshot(to: name) }
                else if let sim = simulator { sim.snapshot(to: name) }
                else { controller.snapshot(to: name) }
                guard k + 1 == frames else { return }
                if let sim = simulator {
                    sim.station.dumpState()   // every body and order at this moment, to station.log beside the picture
                    // The scripted run's whole story, so a check can read it rather than the picture.
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

        /// A top-level menu, in the bar and ready to be filled.
        func menu(_ title: String) -> NSMenu {
            let item = NSMenuItem()
            let sub = NSMenu(title: title)
            item.submenu = sub
            main.addItem(item)
            return sub
        }

        // The application's own: what it is, keeping it current, and getting out.
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

        // The standard editing keys. Settings has fields to type organisations and a name into, and
        // without these in the bar the system does not give them copy and paste.
        let edit = menu("Edit")
        for (title, selector, key) in [("Undo", "undo:", "z"), ("Redo", "redo:", "Z")] {
            edit.addItem(withTitle: title, action: Selector(selector), keyEquivalent: key)
        }
        edit.addItem(.separator())
        for (title, selector, key) in [("Cut", "cut:", "x"), ("Copy", "copy:", "c"), ("Paste", "paste:", "v"),
                                       ("Select All", "selectAll:", "a")] {
            edit.addItem(withTitle: title, action: Selector(selector), keyEquivalent: key)
        }

        // What the station looks like from here: where the camera is pointed, and the two toggles
        // worth reaching for often enough to want a key.
        let view = menu("View")
        viewMenu = view
        view.delegate = self   // the stations it can point at are only known once there is a fleet
        view.addItem(withTitle: "Reset View", action: #selector(resetView), keyEquivalent: "r")
        floatItem = view.addItem(withTitle: "Float on Top", action: #selector(toggleFloat), keyEquivalent: "f")
        floatItem.state = UserDefaults.standard.bool(forKey: "float") ? .on : .off
        musicItem = view.addItem(withTitle: "Music", action: #selector(toggleMusic), keyEquivalent: "m")

        // The station's dealings with the outside.
        let station = menu("Station")
        let refresh = station.addItem(withTitle: "Refresh GitHub", action: #selector(refreshGitHub), keyEquivalent: "r")
        refresh.keyEquivalentModifierMask = [.command, .shift]

        // The tools for working on rumkapsel itself, out of the way of the ordinary path.
        let develop = menu("Develop")
        let g = develop.addItem(withTitle: "Graphics Gallery", action: #selector(openGallery), keyEquivalent: "g")
        g.keyEquivalentModifierMask = [.command, .shift]
        let sim = develop.addItem(withTitle: "Simulator…", action: #selector(openSimulator), keyEquivalent: "s")
        sim.keyEquivalentModifierMask = [.command, .shift]

        let help = menu("Help")
        help.addItem(withTitle: "Request a Feature…", action: #selector(requestFeature), keyEquivalent: "")
        help.addItem(withTitle: "Report a Bug…", action: #selector(reportBug), keyEquivalent: "")

        NSApp.mainMenu = main
    }

    /// The View menu's stations, laid out again whenever it is opened: one line per station the fleet
    /// actually has, named rather than numbered, above the rest of the menu. Where there is only one
    /// station there is nothing to choose between, so no line is put there at all — and that is the
    /// whole of it when the stations become rooms of a single one.
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

    /// A station driven by hand: synthetic facts in, every event and command in the log.
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

    /// The release notes bundled with this build, in a small scrollable window.
    @objc func openWhatsNew() {
        if notesWindow == nil {
            guard let url = Bundle.main.url(forResource: "WhatsNew", withExtension: "md"), let md = try? String(contentsOf: url, encoding: .utf8) else { return }
            let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
            // Headings become bold lines; the rest is inline markdown with its line breaks kept.
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

    @objc func openSettings() {
        settingsModel.config = ConfigStore.shared.current
        settingsModel.knownRepos = controller.knownRepos
        settingsModel.pipelines = controller.pipelineRows
        settingsModel.knownLogins = Array(Set(controller.seenLogins).union(settingsModel.config.crewNames.keys)).sorted()
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
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    // A scripted suite has no window and wants no dock icon in the way.
    app.setActivationPolicy(Scripted.run ? .accessory : .regular)
    app.run()
}
