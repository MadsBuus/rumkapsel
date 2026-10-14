import Foundation
import Network
import dnssd

struct PeerSnapshot: Codable {
    struct Office: Codable {
        var key: String; var name: String; var repo: String; var branch: String?; var color: RGB; var cells: [Cell]
        var pushed: Bool
        var startedAt: Date
        var lastActive: Date
        var boxes: Int; var dim: Bool
        var pull: Int? = nil; var pullState: String? = nil; var review: String? = nil; var checks: String? = nil
    }
    struct Minion: Codable {
        var id: String; var office: String; var asleep: Bool; var busy: Bool
        var activity: String? = nil; var waiting: Bool? = nil; var cones: Int? = nil
        var doing: String? = nil
        var callsign: String? = nil
    }
    var version: Int
    var name: String
    var since: Date
    var offices: [Office]
    var minions: [Minion]
    var github: [GitHubResolver.Knowledge]?
    var project: GitHubResolver.ProjectKnowledge?
    var twoWay: Bool? = nil
    var sentAt: Date? = nil
    var colors: [String: Int]? = nil
    static let current = 2
}

final class PeerHub {
    private let type = "_rumkapsel._tcp"
    private var listener: NWListener?
    private var browser: NWBrowser?
    private var outgoing: [String: NWConnection] = [:]
    private var found: [String: NWEndpoint] = [:]
    private var incoming: [NWConnection] = []
    private var answered: Set<ObjectIdentifier> = []
    private let queue = DispatchQueue(label: "rumkapsel.peers")
    private var timer: DispatchSourceTimer?
    private var pathMonitor: NWPathMonitor?
    private(set) var networkUp = true
    private(set) var blocked = false
    private(set) var nearby: [String] = []
    var connectedCount: Int { queue.sync { outgoing.values.filter { $0.state == .ready }.count } }
    private(set) var name = ""
    private(set) var since = Date()
    var isRunning: Bool { listener != nil }
    var peerCount: Int { queue.sync { outgoing.count } }
    private var latest: PeerSnapshot?
    private var latestBody: Data?
    private var sentBody: Data?
    private var sentAt = Date.distantPast
    private var heard: [ObjectIdentifier: String] = [:]
    private var arrivals: [String: Arrival] = [:]
    private var comings: [(at: Date, words: String)] = []
    var onSnapshot: ((PeerSnapshot) -> Void)?

    struct Arrival { var at: Date; var gap: TimeInterval?; var lag: TimeInterval?; var count: Int }
    struct Status {
        var reaching: Set<String>
        var reachedBy: Set<String>
        var arrivals: [String: Arrival]
        var comings: [(at: Date, words: String)]
    }
    static let heartbeat: TimeInterval = 3

    var status: Status {
        queue.sync {
            Status(reaching: Set(outgoing.filter { $0.value.state == .ready }.keys), reachedBy: Set(heard.values),
                   arrivals: arrivals, comings: comings)
        }
    }

    private func note(_ words: String) {
        StationLog.write("peer", words)
        comings.append((Date(), words))
        if comings.count > 30 { comings.removeFirst(comings.count - 30) }
    }

    private static func reason(_ error: Error?) -> String {
        guard let error else { return "closed" }
        let text = "\(error)"
        return text.split(separator: ":", maxSplits: 1).last.map { $0.trimmingCharacters(in: .whitespaces).lowercased() } ?? text
    }

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
        t.schedule(deadline: .now() + 2, repeating: 1)
        t.setEventHandler { [weak self] in
            guard let self, Date().timeIntervalSince(self.sentAt) >= PeerHub.heartbeat - 0.05 else { return }
            self.broadcast()
        }
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
        latest = nil; latestBody = nil; sentBody = nil
        arrivals = [:]; comings = []
        found = [:]
        nearby = []; blocked = false
    }

    private func browsed(_ results: Set<NWBrowser.Result>) {
        found = [:]
        for r in results {
            guard case .service(let n, _, _, _) = r.endpoint, n != name else { continue }
            found[n] = r.endpoint
        }
        for (n, c) in outgoing where found[n] == nil && c.state != .ready { c.cancel(); outgoing[n] = nil }
        dial()
        let names = found.keys.sorted()
        DispatchQueue.main.async { [weak self] in self?.nearby = names }
    }

    private func dial() {
        for (n, endpoint) in found where outgoing[n] == nil {
            let c = NWConnection(to: endpoint, using: PeerHub.tcp)
            var wasUp = false
            c.stateUpdateHandler = { [weak self, weak c] state in
                guard let self, let c else { return }
                switch state {
                case .ready:
                    wasUp = true
                    self.note("reached \(n)")
                case .waiting(let e):
                    if wasUp { self.note("lost \(n): \(PeerHub.reason(e))") }
                    c.cancel()
                case .failed(let e):
                    if wasUp { self.note("lost \(n): \(PeerHub.reason(e))") }
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
                        if heard.updateValue(snap.name, forKey: ObjectIdentifier(c)) == nil { note("\(snap.name) reached us") }
                    }
                    let now = Date()
                    let before = arrivals[snap.name]
                    arrivals[snap.name] = Arrival(at: now, gap: before.map { now.timeIntervalSince($0.at) },
                                                  lag: snap.sentAt.map { now.timeIntervalSince($0) }, count: (before?.count ?? 0) + 1)
                    DispatchQueue.main.async { self.onSnapshot?(snap) }
                }
            }
            if done || error != nil {
                if let who = heard.removeValue(forKey: ObjectIdentifier(c)) { note("\(who) left us: \(PeerHub.reason(error))") }
                incoming.removeAll { $0 === c }; answered.remove(ObjectIdentifier(c)); c.cancel(); return
            }
            receive(on: c, buffer: buf)
        }
    }

    func offer(_ snap: PeerSnapshot) {
        let body = try? JSONEncoder().encode(snap)
        queue.async {
            self.latest = snap
            self.latestBody = body
            if body != self.sentBody { self.broadcast() }
        }
    }

    private func broadcast() {
        dial()
        let open = (Array(outgoing.values) + incoming.filter { answered.contains(ObjectIdentifier($0)) }).filter { $0.state == .ready }
        guard !open.isEmpty, var snap = latest else { return }
        snap.sentAt = Date()
        guard var data = try? JSONEncoder().encode(snap) else { return }
        data.append(UInt8(ascii: "\n"))
        for c in open { c.send(content: data, completion: .contentProcessed { _ in }) }
        sentBody = latestBody
        sentAt = Date()
    }
}
