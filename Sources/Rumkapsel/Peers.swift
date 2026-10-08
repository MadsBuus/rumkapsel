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
    /// The newest snapshot the scene handed over, sent every beat whether or not the scene is drawing.
    private var latest: PeerSnapshot?
    /// Who is at the far end of each incoming connection, once a snapshot has said.
    private var heard: [ObjectIdentifier: String] = [:]
    var onSnapshot: ((PeerSnapshot) -> Void)?

    /// TCP that notices a station gone without a word: a link that stops answering fails within seconds.
    private static var tcp: NWParameters {
        let t = NWProtocolTCP.Options()
        t.enableKeepalive = true
        t.keepaliveIdle = 5
        t.keepaliveInterval = 2
        t.keepaliveCount = 3
        return NWParameters(tls: nil, tcp: t)
    }

    func start(name: String) {
        stop()
        self.name = name
        since = Date()
        do {
            let l = try NWListener(using: PeerHub.tcp)
            l.service = NWListener.Service(name: name, type: type)
            l.newConnectionHandler = { [weak self] c in self?.accept(c) }
            l.stateUpdateHandler = { _ in }
            l.start(queue: queue)
            listener = l
        } catch { return }
        let b = NWBrowser(for: .bonjour(type: type, domain: nil), using: PeerHub.tcp)
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
        heard = [:]
        latest = nil
        found = [:]
        nearby = []; blocked = false
    }

    private func browsed(_ results: Set<NWBrowser.Result>) {
        found = [:]
        for r in results {
            guard case .service(let n, _, _, _) = r.endpoint, n != name else { continue }
            found[n] = r.endpoint
        }
        // Bonjour on wifi drops a listing for seconds at a time while the station behind it answers on.
        // A connection that is up stays up until TCP itself gives out; only one still dialling is let go.
        for (n, c) in outgoing where found[n] == nil && c.state != .ready { c.cancel(); outgoing[n] = nil }
        dial()
        let names = found.keys.sorted()
        DispatchQueue.main.async { [weak self] in self?.nearby = names }
    }

    /// A connection to every station found that has none. One that cannot get through yet (refused,
    /// or no route) is dropped, so the next beat tries again from scratch.
    private func dial() {
        for (n, endpoint) in found where outgoing[n] == nil {
            let c = NWConnection(to: endpoint, using: PeerHub.tcp)
            var wasUp = false
            c.stateUpdateHandler = { [weak self, weak c] state in
                guard let self, let c else { return }
                switch state {
                case .ready:
                    wasUp = true
                    StationLog.write("peer", "link to \(n) up")
                case .waiting(let e):
                    if wasUp { StationLog.write("peer", "link to \(n) down: \(e)") }
                    c.cancel()
                case .failed(let e):
                    if wasUp { StationLog.write("peer", "link to \(n) down: \(e)") }
                    if outgoing[n] === c { outgoing[n] = nil }
                case .cancelled:
                    if outgoing[n] === c { outgoing[n] = nil }
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
                    if incoming.contains(where: { $0 === c }) {
                        if snap.twoWay == true { answered.insert(ObjectIdentifier(c)) }
                        if heard.updateValue(snap.name, forKey: ObjectIdentifier(c)) == nil { StationLog.write("peer", "link from \(snap.name) up") }
                    }
                    DispatchQueue.main.async { self.onSnapshot?(snap) }
                }
            }
            if done || error != nil {
                if let who = heard.removeValue(forKey: ObjectIdentifier(c)) { StationLog.write("peer", "link from \(who) down: \(error.map { "\($0)" } ?? "closed")") }
                incoming.removeAll { $0 === c }; answered.remove(ObjectIdentifier(c)); c.cancel(); return
            }
            receive(on: c, buffer: buf)
        }
    }

    /// The scene's newest word, built on its own thread from its own state.
    func offer(_ snap: PeerSnapshot) {
        queue.async { self.latest = snap }
    }

    private func broadcast() {
        dial()
        let open = (Array(outgoing.values) + incoming.filter { answered.contains(ObjectIdentifier($0)) }).filter { $0.state == .ready }
        guard !open.isEmpty, let snap = latest, var data = try? JSONEncoder().encode(snap) else { return }
        data.append(UInt8(ascii: "\n"))
        for c in open { c.send(content: data, completion: .contentProcessed { _ in }) }
    }
}
