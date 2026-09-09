import Foundation
import Network

/// What one app tells the others about itself: enough to draw its stations, nothing more.
struct PeerSnapshot: Codable {
    struct Room: Codable { var key: String; var name: String; var color: RGB; var cells: [Cell]; var boxes: Int; var dim: Bool }
    struct Minion: Codable { var id: String; var x: Double; var y: Double; var asleep: Bool; var busy: Bool }
    struct Station: Codable { var name: String; var spine: Int; var hasPad: Bool; var hasHangar: Bool; var rooms: [Room]; var minions: [Minion]; var stored: [String: Int]; var staged: [String: Int] }
    var name: String
    var stations: [Station]
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
    private(set) var name = ""
    var snapshotProvider: (() -> PeerSnapshot?)?
    var onSnapshot: ((PeerSnapshot) -> Void)?

    func start(name: String) {
        stop()
        self.name = name
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
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 2, repeating: 3)
        t.setEventHandler { [weak self] in self?.broadcast() }
        t.resume()
        timer = t
    }

    func stop() {
        timer?.cancel(); timer = nil
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
                if let snap = try? JSONDecoder().decode(PeerSnapshot.self, from: line), snap.name != name {
                    DispatchQueue.main.async { self.onSnapshot?(snap) }
                }
            }
            if done || error != nil { incoming.removeAll { $0 === c }; return }
            receive(on: c, buffer: buf)
        }
    }

    private func broadcast() {
        guard !outgoing.isEmpty, let snap = snapshotProvider?(), var data = try? JSONEncoder().encode(snap) else { return }
        data.append(UInt8(ascii: "\n"))
        for c in outgoing.values where c.state == .ready { c.send(content: data, completion: .contentProcessed { _ in }) }
    }
}
