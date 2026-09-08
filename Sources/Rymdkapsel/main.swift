import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var controller: StationController!
    var musicItem: NSMenuItem!
    var floatItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        FileHandle.standardError.write("launched\n".data(using: .utf8)!)
        let args = CommandLine.arguments
        let demo = args.contains("--demo")
        let snapshotPath = args.firstIndex(of: "--snapshot").flatMap { args.count > $0 + 1 ? args[$0 + 1] : nil }

        buildMenu()

        let size = NSSize(width: 640, height: 440)
        window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
        window.title = "rymdkapsel"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = false
        window.backgroundColor = Palette.void
        window.minSize = NSSize(width: 320, height: 240)
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.level = .floating
        window.isReleasedWhenClosed = false

        controller = StationController(frame: NSRect(origin: .zero, size: size), demo: demo)
        window.contentView = controller.view
        controller.viewSize = controller.view.bounds.size
        NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: controller.view, queue: .main) { [weak self] _ in
            guard let self else { return }
            controller.viewSize = controller.view.bounds.size
        }
        controller.view.postsFrameChangedNotifications = true

        if !window.setFrameUsingName("RymdkapselMain"), let screen = NSScreen.main {
            let f = screen.visibleFrame
            window.setFrameOrigin(NSPoint(x: f.maxX - size.width - 24, y: f.minY + 24))
        }
        window.setFrameAutosaveName("RymdkapselMain")
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(controller.view)
        NSApp.activate(ignoringOtherApps: true)

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
        if let path = snapshotPath {
            FileHandle.standardError.write("snapshot scheduled -> \(path)\n".data(using: .utf8)!)
            DispatchQueue.main.asyncAfter(deadline: .now() + (num("--delay") ?? 4)) { [self] in
                controller.snapshot(to: path)
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
        app.addItem(withTitle: "About rymdkapsel", action: #selector(about), keyEquivalent: "")
        app.addItem(.separator())
        musicItem = app.addItem(withTitle: "Music", action: #selector(toggleMusic), keyEquivalent: "m")
        floatItem = app.addItem(withTitle: "Float on Top", action: #selector(toggleFloat), keyEquivalent: "f")
        floatItem.state = .on
        app.addItem(withTitle: "Reset View", action: #selector(resetView), keyEquivalent: "r")
        app.addItem(withTitle: "Refresh GitHub", action: #selector(refreshGitHub), keyEquivalent: "g")
        for (title, key) in [("Focus Work", "1"), ("Focus Private", "2"), ("Focus Both", "3")] {
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
        alert.messageText = "rymdkapsel"
        alert.informativeText = "Each station is a repository. Minions are live Claude sessions: they research at the core, code in the area rooms, test in the reactor, ship from the hangar, cook up skills in the kitchen and rest in quarters while waiting for you.\n\nA love letter to the real rymdkapsel by Grapefrukt."
        alert.runModal()
    }

    @objc func resetView() { controller.resetView() }
    @objc func refreshGitHub() { controller.refreshGitHub() }

    @objc func focusStation(_ sender: NSMenuItem) {
        switch sender.keyEquivalent {
        case "1": controller.focus(on: "work")
        case "2": controller.focus(on: "private")
        default: controller.focus(on: nil)
        }
    }

    @objc func toggleMusic() {
        let on = !controller.drone.isEnabled
        controller.drone.isEnabled = on
        musicItem.state = on ? .on : .off
        UserDefaults.standard.set(on, forKey: "music")
    }

    @objc func toggleFloat() {
        let on = window.level != .floating
        window.level = on ? .floating : .normal
        floatItem.state = on ? .on : .off
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.regular)
    app.run()
}
