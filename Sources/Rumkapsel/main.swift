import AppKit
import ServiceManagement
import Sparkle
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, SPUUpdaterDelegate {
    var window: NSWindow!
    var controller: StationController!
    var musicItem: NSMenuItem!
    var floatItem: NSMenuItem!
    var updater: SPUStandardUpdaterController!
    var settingsWindow: NSWindow?
    var notesWindow: NSWindow?
    var galleryWindow: NSWindow?
    var gallery: GalleryController?
    var simulatorWindow: NSWindow?
    var simulator: SimulatorController?
    /// A scripted run's heartbeat: see below.
    private var frameBeat: Timer?
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

        buildMenu()
        ConfigStore.shared.onChange = { [weak self] _ in self?.controller.applyConfigChange() }

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

        if !window.setFrameUsingName("RumkapselMain"), let screen = NSScreen.main {
            let f = screen.visibleFrame
            window.setFrameOrigin(NSPoint(x: f.maxX - size.width - 24, y: f.minY + 24))
        }
        window.setFrameAutosaveName("RumkapselMain")
        if !simulatorOnly {
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(controller.view)
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
            DispatchQueue.main.asyncAfter(deadline: .now() + (num("--delay") ?? 4)) { [self] in
                if galleryMode { gallery?.snapshot(to: path) }
                else if let sim = simulator {
                    sim.snapshot(to: path)
                    // The scripted run's whole story, so a check can read it rather than the picture.
                    FileHandle.standardError.write(("--- simulator log ---\n" + sim.model.logText + "\n").data(using: .utf8)!)
                }
                else { controller.snapshot(to: path) }
                FileHandle.standardError.write("snapshot written\n".data(using: .utf8)!)
                NSApp.terminate(nil)
            }
        }
    }

    private func buildMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let app = NSMenu()
        app.addItem(withTitle: "About rumkapsel", action: #selector(about), keyEquivalent: "")
        let check = NSMenuItem(title: "Check for Updates…", action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)), keyEquivalent: "u")
        check.target = updater
        app.addItem(check)
        if Bundle.main.url(forResource: "WhatsNew", withExtension: "md") != nil {
            let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
            app.addItem(withTitle: "What's New in \(v)…", action: #selector(openWhatsNew), keyEquivalent: "")
        }
        app.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        let g = app.addItem(withTitle: "Graphics Gallery", action: #selector(openGallery), keyEquivalent: "g")
        g.keyEquivalentModifierMask = [.command, .shift]
        let sim = app.addItem(withTitle: "Simulator…", action: #selector(openSimulator), keyEquivalent: "s")
        sim.keyEquivalentModifierMask = [.command, .shift]
        app.addItem(withTitle: "Request a Feature…", action: #selector(requestFeature), keyEquivalent: "")
        app.addItem(withTitle: "Report a Bug…", action: #selector(reportBug), keyEquivalent: "")
        app.addItem(.separator())
        musicItem = app.addItem(withTitle: "Music", action: #selector(toggleMusic), keyEquivalent: "m")
        floatItem = app.addItem(withTitle: "Float on Top", action: #selector(toggleFloat), keyEquivalent: "f")
        floatItem.state = UserDefaults.standard.bool(forKey: "float") ? .on : .off
        app.addItem(withTitle: "Reset View", action: #selector(resetView), keyEquivalent: "r")
        app.addItem(withTitle: "Refresh GitHub", action: #selector(refreshGitHub), keyEquivalent: "g")
        for (title, key) in [("Focus All", "0"), ("Focus Station 1", "1"), ("Focus Station 2", "2"), ("Focus Station 3", "3"), ("Focus Station 4", "4")] {
            let item = app.addItem(withTitle: title, action: #selector(focusStation(_:)), keyEquivalent: key)
            item.keyEquivalentModifierMask = []
        }
        app.addItem(.separator())
        app.addItem(withTitle: "Hide", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        app.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = app
        NSApp.mainMenu = main
    }

    @objc func about() {
        let alert = NSAlert()
        alert.messageText = "rumkapsel"
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
        simulatorWindow?.makeKeyAndOrderFront(nil)
        simulatorWindow?.makeFirstResponder(simulator?.station.view)
        NSApp.activate(ignoringOtherApps: true)
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
        settingsModel.knownLogins = Array(Set(controller.seenLogins).union(settingsModel.config.crewNames.keys)).sorted()
        settingsModel.launchAtLogin = SMAppService.mainApp.status == .enabled
        settingsModel.musicOn = controller.drone.isEnabled
        settingsModel.floatOn = window.level == .floating
        if settingsWindow == nil {
            let view = SettingsView(model: settingsModel,
                                    onMusic: { [weak self] on in self?.setMusic(on) },
                                    onFloat: { [weak self] on in self?.setFloat(on) },
                                    onLaunchAtLogin: { on in
                                        if on { try? SMAppService.mainApp.register() } else { try? SMAppService.mainApp.unregister() }
                                    },
                                    onCheckUpdates: { [weak self] in self?.updater.checkForUpdates(nil) })
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
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
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
        if let n = Int(sender.keyEquivalent), n > 0 { controller.focus(onIndex: n - 1) } else { controller.focus(on: nil) }
    }

    @objc func toggleMusic() { setMusic(!controller.drone.isEnabled) }
    @objc func toggleFloat() { setFloat(window.level != .floating) }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    app.run()
}
