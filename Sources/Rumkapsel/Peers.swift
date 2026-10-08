import Foundation
import Network
import dnssd

/// What one app tells the others: its own claim on the shared work station. Only offices it has
/// checked out itself go out, keyed by branch so every app agrees on which office is which.
struct PeerSnapshot: Codable {
    struct Office: Codable {
        var key: String; var name: String; var repo: String; var branch: String?; var color: RGB; var cells: [Cell]
        var pushed: Bool         // the branch exists on the remote: the office is permanent
        var startedAt: Date      // when this checkout appeared here: a fresh one earns a shuttle
        var lastActive: Date
        var boxes: Int; var dim: Bool
        /// The office's pull request, if it has one: number, state, review and checks. Absent from older peers.
        var pull: Int? = nil; var pullState: String? = nil; var review: String? = nil; var checks: String? = nil
    }
    struct Minion: Codable {
        var id: String; var office: String; var asleep: Bool; var busy: Bool
        /// What the session is doing, whether it waits on its person, and how many messages stand as cones.
        var activity: String? = nil; var waiting: Bool? = nil; var cones: Int? = nil
    }
    var version: Int
    var name: String
    var since: Date              // when this app started sharing
    var offices: [Office]
    var minions: [Minion]
    /// Parsed GitHub answers for the shared repositories, sent now and then so one poll serves the room.
    var github: [GitHubResolver.Knowledge]?
    var project: GitHubResolver.ProjectKnowledge?
    /// The sender reads snapshots on the connections it opens, so one sent back that way arrives.
    var twoWay: Bool? = nil
    static let current = 2
}

/// Bonjour on the local network: advertise, browse, and swap snapshots as newline-delimited JSON. Every
/// connection carries snapshots both ways, so two stations talk as long as either can reach the other.
final class PeerHub {
    private let type = "_rumkapsel._tcp"
    private var listener: NWListener?
    private var browser: NWBrowser?
    private var outgoing: [String: NWConnection] = [:]
    /// Every other station Bonjour shows, answering or not; dialled again each beat until one answers.
    private var found: [String: NWEndpoint] = [:]
    private var incoming: [NWConnection] = []
    /// Incoming connections whose far end said it reads what comes back.
    private var answered: Set<ObjectIdentifier> = []
    private let queue = DispatchQueue(label: "rumkapsel.peers")
    private var timer: DispatchSourceTimer?
    private var pathMonitor: NWPathMonitor?
    private(set) var networkUp = true
    /// macOS keeps this app off the local network: Privacy & Security › Local Network has it off.
    private(set) var blocked = false
    /// Names of the stations Bonjour shows, for the main thread.
    private(set) var nearby: [String] = []
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
        b.stateUpdateHandler = { [weak self] state in
            var denied = false
            if case .waiting(let e) = state, case .dns(let code) = e { denied = code == DNSServiceErrorType(kDNSServiceErr_PolicyDenied) }
            if case .failed(let e) = state, case .dns(let code) = e { denied = code == DNSServiceErrorType(kDNSServiceErr_PolicyDenied) }
            DispatchQueue.main.async { self?.blocked = denied }
        }
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
        answered = []
        found = [:]
        nearby = []; blocked = false
    }

    private func browsed(_ results: Set<NWBrowser.Result>) {
        found = [:]
        for r in results {
            guard case .service(let n, _, _, _) = r.endpoint, n != name else { continue }
            found[n] = r.endpoint
        }
        for (n, c) in outgoing where found[n] == nil { c.cancel(); outgoing[n] = nil }
        dial()
        let names = found.keys.sorted()
        DispatchQueue.main.async { [weak self] in self?.nearby = names }
    }

    /// A connection to every station found that has none. One that cannot get through yet (refused,
    /// or no route) is dropped, so the next beat tries again from scratch.
    private func dial() {
        for (n, endpoint) in found where outgoing[n] == nil {
            let c = NWConnection(to: endpoint, using: .tcp)
            c.stateUpdateHandler = { [weak self, weak c] state in
                guard let self, let c else { return }
                switch state {
                case .waiting: c.cancel()
                case .failed, .cancelled: if outgoing[n] === c { outgoing[n] = nil }
                default: break
                }
            }
            c.start(queue: queue)
            outgoing[n] = c
            receive(on: c, buffer: Data())
        }
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
                    if snap.twoWay == true, incoming.contains(where: { $0 === c }) { answered.insert(ObjectIdentifier(c)) }
                    DispatchQueue.main.async { self.onSnapshot?(snap) }
                }
            }
            if done || error != nil { incoming.removeAll { $0 === c }; answered.remove(ObjectIdentifier(c)); c.cancel(); return }
            receive(on: c, buffer: buf)
        }
    }

    private func broadcast() {
        broadcasts += 1
        dial()
        let open = (Array(outgoing.values) + incoming.filter { answered.contains(ObjectIdentifier($0)) }).filter { $0.state == .ready }
        guard !open.isEmpty, let snap = snapshotProvider?(broadcasts % 10 == 1), var data = try? JSONEncoder().encode(snap) else { return }
        data.append(UInt8(ascii: "\n"))
        for c in open { c.send(content: data, completion: .contentProcessed { _ in }) }
    }
}
