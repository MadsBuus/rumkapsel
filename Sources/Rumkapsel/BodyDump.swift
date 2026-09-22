// What every body is doing and why it is standing there: `rumkapsel --dump-bodies [seconds] [station]`.
//
// A body's place on the floor is decided in three steps, and a body standing somewhere odd has come
// off one of them: the place it was sent to, the spot within that place its fixture gives it, and the
// pose it holds there. A bunk is the hardest of the three, because the bed is a cell, the walk aims at
// that cell, and only a body that is resting *and* asleep is ever moved off it onto the mattress.
//
// This prints all three per body, with every gate that decides them, so five bodies in five different
// states can be read rather than guessed at from a picture.

import AppKit

extension StationController {
    func dumpBodies(only station: String?) {
        func say(_ s: String) { FileHandle.standardError.write((s + "\n").data(using: .utf8)!) }
        func pad(_ s: String, _ n: Int) -> String { s.padding(toLength: max(n, s.count), withPad: " ", startingAt: 0) }
        func num(_ d: Double) -> String { d == 0 ? "-" : String(format: "%.1f", d - clock) }

        for st in fleet.stations.values.sorted(by: { $0.name < $1.name }) where station == nil || st.name == station {
            let here = minions.values.filter { $0.station == st.name }.sorted { $0.home.name < $1.home.name }
            say("station \(st.name): \(here.count) bodies · \(st.beds.count) beds · clock \(String(format: "%.1f", clock))")
            say("  who              place        activity      cmd        rest job crew  bed  down  bedIn  riseIn lying bench pose")
            for m in here {
                // The pose the scene will draw this instant, by the same call the scene makes.
                let pose: String
                switch m.currentPose(at: clock) {
                case .standing: pose = "standing"
                case .seated(let h, _): pose = String(format: "seated %.2f", h)
                case .flat(let h): pose = String(format: "flat %.2f", h)
                }
                let cmd: String
                if let c = m.current { cmd = String(describing: c.kind).prefix(9).description } else { cmd = "-" }
                say("  " + [pad(m.home.name.prefix(16).description, 16), pad(String(describing: m.place).prefix(12).description, 12),
                            pad(m.activity.label.prefix(13).description, 13), pad(cmd, 10),
                            pad(m.isResting ? "yes" : "no", 4), pad(m.onJob ? "yes" : "no", 3),
                            pad(m.isCrew ? "yes" : m.isSubagent ? "sub" : "no", 5),
                            pad(m.bed.map(String.init) ?? "-", 4), pad(m.beddedDown ? "yes" : "no", 5),
                            pad(num(m.beddingUntil), 6), pad(num(m.risingUntil), 6),
                            pad(m.lying ? "yes" : "no", 5), pad(m.onBench ? "yes" : "no", 5), pose].joined(separator: " "))
            }
            // Where each body actually is against where its bunk is: a body on the mattress and a body a
            // shin's reach off it are a hand apart on the floor and unmistakable in a picture.
            let inBed = here.filter { $0.bed != nil }
            if !inBed.isEmpty {
                say("  bunks: index  bedAt            bodyAt           off")
                for m in inBed {
                    guard let b = m.bed, b < st.beds.count else {
                        say("  " + pad(m.home.name.prefix(16).description, 16) + " bed \(m.bed.map(String.init) ?? "-") — no such bunk on this floor")
                        continue
                    }
                    let spot = st.beds[b].pos
                    let off = ((m.pos.x - spot.x) * (m.pos.x - spot.x) + (m.pos.y - spot.y) * (m.pos.y - spot.y)).squareRoot()
                    say("  " + [pad(m.home.name.prefix(16).description, 16), pad(String(b), 6),
                                pad(String(format: "%.2f,%.2f", spot.x, spot.y), 16),
                                pad(String(format: "%.2f,%.2f", m.pos.x, m.pos.y), 16),
                                String(format: "%.2f", off)].joined(separator: " "))
                }
                // Two bodies holding the same bunk is its own answer.
                let taken = Dictionary(grouping: inBed, by: { $0.bed! }).filter { $0.value.count > 1 }
                for (b, who) in taken.sorted(by: { $0.key < $1.key }) {
                    say("  bunk \(b) is held by \(who.count): \(who.map { $0.home.name }.joined(separator: ", "))")
                }
            }
            say("")
        }
    }
}
