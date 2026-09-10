import Foundation
import Network

/// What one app tells the others: its own claim on the shared work station. Only offices it has
/// checked out itself go out, keyed by branch so every app agrees on which office is which.
struct PeerSnapshot: Codable {
    struct Office: Codable {
        var key: String; var name: String; var repo: String; var branch: String?; var color: RGB; var cells: [Cell]
        var pushed: Bool         // the branch exists on the remote: the office is permanent
        var startedAt: Date      // when this checkout appeared here: a fresh one earns a shuttle
        var lastActive: Date
        var boxes: Int; var dim: Bool
    }
    struct Minion: Codable { var id: String; var office: String; var asleep: Bool; var busy: Bool }
    var version: Int
    var name: String
    var since: Date              // when this app started sharing
    var offices: [Office]
    var minions: [Minion]
    /// Parsed GitHub answers for the shared repositories, sent now and then so one poll serves the room.
    var github: [GitHubResolver.Knowledge]?
    var project: GitHubResolver.ProjectKnowledge?
    static let current = 2
}

/// Bonjour on the local network: advertise, browse, and swap snapshots as newline-delimited JSON.
final class PeerHub {
    private let type = "_rumkapsel._tcp"
    private var listener: NWListener?
    private var browser: NWBrowser?
    private var outgoing: [String: NWConnection] = [:]
    private var incoming: [NWConnection] = []
    private let queue = DispatchQueue(label: "rumkapsel.peers")
    private var timer: DispatchSourceTimer?
    private var pathMonitor: NWPathMonitor?
    private(set) var networkUp = true
    /// Peers we are actually talking to right now.
    var connectedCount: Int { queue.sync { outgoing.values.filter { $0.state == .ready }.count } }
    private(set) var name = ""
    private(set) var since = Date()
    var isRunning: Bool { listener != nil }
    var peerCount: Int { queue.sync { outgoing.count } }
    var snapshotProvider: ((_ withGitHub: Bool) -> PeerSnapshot?)?
    private var broadcasts = 0
    var onSnapshot: ((PeerSnapshot) -> Void)?

    func start(name: String) {
        stop()
        self.name = name
        since = Date()
        do {
            let l = try NWListener(using: .tcp)
            l.service = NWListener.Service(name: name, type: type)
            l.newConnectionHandler = { [weak self] c in self?.accept(c) }
            l.stateUpdateHandler = { _ in }
            l.start(queue: queue)
            listener = l
        } catch { return }
        let b = NWBrowser(for: .bonjour(type: type, domain: nil), using: .tcp)
        b.browseResultsChangedHandler = { [weak self] results, _ in self?.browsed(results) }
        b.start(queue: queue)
        browser = b
        let pm = NWPathMonitor()
        pm.pathUpdateHandler = { [weak self] path in self?.networkUp = path.status == .satisfied }
        pm.start(queue: queue)
        pathMonitor = pm
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 2, repeating: 3)
        t.setEventHandler { [weak self] in self?.broadcast() }
        t.resume()
        timer = t
    }

    func stop() {
        timer?.cancel(); timer = nil
        pathMonitor?.cancel(); pathMonitor = nil
        listener?.cancel(); listener = nil
        browser?.cancel(); browser = nil
        outgoing.values.forEach { $0.cancel() }; outgoing = [:]
        incoming.forEach { $0.cancel() }; incoming = []
    }

    private func browsed(_ results: Set<NWBrowser.Result>) {
        var seen = Set<String>()
        for r in results {
            guard case .service(let n, _, _, _) = r.endpoint, n != name else { continue }
            seen.insert(n)
            if outgoing[n] == nil {
                let c = NWConnection(to: r.endpoint, using: .tcp)
                c.stateUpdateHandler = { [weak self] state in
                    if case .failed = state { self?.outgoing[n] = nil }
                    if case .cancelled = state { self?.outgoing[n] = nil }
                }
                c.start(queue: queue)
                outgoing[n] = c
            }
        }
        for (n, c) in outgoing where !seen.contains(n) { c.cancel(); outgoing[n] = nil }
    }

    private func accept(_ c: NWConnection) {
        incoming.append(c)
        c.start(queue: queue)
        receive(on: c, buffer: Data())
    }

    private func receive(on c: NWConnection, buffer: Data) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 256 * 1024) { [weak self] data, _, done, error in
            guard let self else { return }
            var buf = buffer
            if let data { buf.append(data) }
            while let nl = buf.firstIndex(of: UInt8(ascii: "\n")) {
                let line = buf[buf.startIndex..<nl]
                buf.removeSubrange(buf.startIndex...nl)
                if let snap = try? JSONDecoder().decode(PeerSnapshot.self, from: line), snap.version == PeerSnapshot.current, snap.name != name {
                    DispatchQueue.main.async { self.onSnapshot?(snap) }
                }
            }
            if done || error != nil { incoming.removeAll { $0 === c }; return }
            receive(on: c, buffer: buf)
        }
    }

    private func broadcast() {
        broadcasts += 1
        guard !outgoing.isEmpty, let snap = snapshotProvider?(broadcasts % 10 == 1), var data = try? JSONEncoder().encode(snap) else { return }
        data.append(UInt8(ascii: "\n"))
        for c in outgoing.values where c.state == .ready { c.send(content: data, completion: .contentProcessed { _ in }) }
    }
}
