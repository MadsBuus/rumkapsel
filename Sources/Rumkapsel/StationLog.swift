// The station's log on disk: every event, command, give-up and GitHub ask, one line each, so what
// the running app is doing can be read from outside it. `station.log` in Application Support, rolled
// to `station.log.1` past a few megabytes.

import Foundation

enum StationLog {
    static var url: URL { AppSupport.root.appendingPathComponent("Rumkapsel", isDirectory: true).appendingPathComponent("station.log") }
    private static let queue = DispatchQueue(label: "station.log")
    private static let clock: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f }()
    private static var handle: FileHandle?
    private static var written = 0
    /// The noise: ticks that say nothing about what changed.
    private static let quiet: Set<String> = ["markersChanged", "crewRoster", "layoutChanged"]

    static func write(_ kind: String, _ text: String) {
        if quiet.contains(where: { text.hasPrefix($0) }) { return }
        let line = "\(clock.string(from: Date()))  \(kind.padding(toLength: 8, withPad: " ", startingAt: 0))\(text)\n"
        queue.async {
            if handle == nil { open() }
            guard let data = line.data(using: .utf8) else { return }
            handle?.write(data)
            written += data.count
            if written > 4_000_000 { roll() }
        }
    }

    private static func open() {
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(atPath: url.path, contents: nil) }
        handle = try? FileHandle(forWritingTo: url)
        handle?.seekToEndOfFile()
        written = Int((try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0)
        if written > 4_000_000 { roll() }
    }

    private static func roll() {
        try? handle?.close(); handle = nil
        let old = url.deletingPathExtension().appendingPathExtension("log.1")
        try? FileManager.default.removeItem(at: old)
        try? FileManager.default.moveItem(at: url, to: old)
        written = 0
        open()
    }
}
