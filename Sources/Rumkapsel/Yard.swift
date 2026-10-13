import Foundation
import simd

struct YardSlot {
    let repo: String
    let number: Int
    let index: Int
    let cleared: Bool
    let alien: Bool
    let group: Int
    let column: Int
    let level: Int
    let cell: Cell
    let pos: SIMD3<Double>
    let yaw: Double
    let carried: Bool

    func lowered(to level: Int) -> YardSlot {
        YardSlot(repo: repo, number: number, index: index, cleared: cleared, alien: alien, group: group, column: column,
                 level: level, cell: cell, pos: SIMD3(pos.x, Double(level) * Hands.level, pos.z), yaw: yaw, carried: carried)
    }
}

extension Station {
    func layout(of yard: Yard, stillUntested: Int? = nil, aside: [String: Int] = [:]) -> [YardSlot] {
        let rows = yardRows(yard)
        guard !rows(0).isEmpty else { return [] }

        struct Entry { let crate: Ledger.Crate; let group: Int; let cleared: Bool; let carried: Bool; let index: Int; var slot: Ledger.Slot? }
        var entries: [Entry] = []
        for repo in Set(ledger.crates.values.map(\.repo)).sorted() {
            let here = ledger.crates(of: repo).filter { $0.stands(in: yard) || $0.heading == yard }.prefix(48)
            for (k, c) in here.enumerated() {
                let carried = !c.stands(in: yard)
                let cleared = yard == .deck && c.cleared && c.number != stillUntested
                let group = yard == .deck && !cleared ? 1 : 0
                var slot = carried ? c.bound : c.slot
                if let s = slot, s.yard != yard || s.group != group { slot = nil }
                if aside["\(repo)#\(c.number)"] != nil { slot = nil }
                entries.append(Entry(crate: c, group: group, cleared: cleared, carried: carried, index: k, slot: slot))
            }
        }
        if yard == .decon { entries = Array(entries.sorted { $0.crate.number < $1.crate.number }.prefix(12)) }
        var held: [(repo: String, slot: Ledger.Slot)] = entries.compactMap { e in e.slot.map { (e.crate.repo, $0) } }
        for i in entries.indices where entries[i].slot == nil {
            let e = entries[i]
            let slot = Ledger.place(repo: e.crate.repo, in: yard, group: e.group, among: held, cap: rows(e.group).count * 2,
                                    avoiding: aside["\(e.crate.repo)#\(e.crate.number)"], tall: yard == .decon)
            entries[i].slot = slot
            held.append((e.crate.repo, slot))
            if e.carried { ledger.setBound(repo: e.crate.repo, number: e.crate.number, slot) }
            else { ledger.setSlot(repo: e.crate.repo, number: e.crate.number, slot) }
        }
        return entries.map { e in
            let s = e.slot!
            let level = held.filter { $0.slot.group == s.group && $0.slot.column == s.column && $0.slot.order < s.order }.count
            let row = rows(s.group)
            let paired = held.contains { $0.slot.group == s.group && $0.slot.column == s.column ^ 1 }
            let cell = row[min(s.column / 2, row.count - 1)]
            let side = paired ? (s.column % 2 == 0 ? -0.25 : 0.25) : 0
            let (jx, jz, yaw) = yard == .storage ? Station.jitter(repo: e.crate.repo, number: e.crate.number) : (0, 0, 0)
            let pos = SIMD3(offset.x + Double(cell.x) + side + jx, Double(level) * Hands.level, offset.y + Double(cell.y) + jz)
            return YardSlot(repo: e.crate.repo, number: e.crate.number, index: e.index, cleared: e.cleared, alien: e.crate.alien,
                            group: s.group, column: s.column, level: level, cell: cell, pos: pos, yaw: yaw, carried: e.carried)
        }
    }

    func spot(for crate: CrateRef, toward yard: Yard) -> Spot {
        let layout = layout(of: yard)
        guard let s = layout.first(where: { $0.repo == crate.repo && $0.number == crate.number }) else {
            let cell = yardRows(yard)(0).first ?? Cell(x: 0, y: 0)
            return Spot(area: Station.area(yard, cleared: false), station: name, owner: crate.repo, label: crate.repo, cell: cell,
                        pos: SIMD3(offset.x + Double(cell.x), 0, offset.y + Double(cell.y)))
        }
        return standing(grounded(s, in: layout), in: yard)
    }

    func carryToDeck(repo: String, numbers: [Int]) -> [Command] {
        let wanted = Set(numbers)
        let standing = layout(of: .storage).filter { $0.repo == repo && !$0.carried }
        let going = standing.filter { wanted.contains($0.number) }.sorted { ($0.level, $0.index) > ($1.level, $1.index) }
        guard !going.isEmpty else { return [] }
        var out: [Command] = []
        var above: [Int: Int] = [:]
        var landed: [String: Int] = [:]
        for slot in going { out += aside(in: .storage, above: slot, going: wanted, standing: standing, after: &above) }
        for slot in going {
            let crate = CrateRef(station: name, repo: repo, number: slot.number)
            ledger.order(repo: repo, number: slot.number, to: .deck)
            let to = spot(for: crate, toward: .deck)
            let column = "\(Int((to.pos.x * 100).rounded()))|\(Int((to.pos.z * 100).rounded()))"
            var waits: [Int] = []
            if let clear = above[slot.column] { waits.append(clear) }
            if to.level > 0, let under = landed["\(column)|\(to.level - 1)"] { waits.append(under) }
            let command = Command.carry(crate, from: self.standing(slot, in: .storage), to: .deck, after: waits)
            above[slot.column] = command.id
            landed["\(column)|\(to.level)"] = command.id
            out.append(command)
        }
        return out
    }

    func carryToTested(repo: String, number: Int) -> [Command] {
        guard ledger[repo, number]?.isCarried != true else { return [] }
        let standing = layout(of: .deck, stillUntested: number).filter { !$0.carried }
        guard let here = standing.first(where: { $0.repo == repo && $0.number == number }) else { return [] }
        var above: [Int: Int] = [:]
        var out = aside(in: .deck, above: here, going: [number], standing: standing, after: &above)
        ledger.order(repo: repo, number: number, to: .deck)
        out.append(.carry(CrateRef(station: name, repo: repo, number: number), from: self.standing(here, in: .deck), to: .deck,
                          after: above[here.column].map { [$0] } ?? []))
        return out
    }

    func carryToStorage(room: Room, repo: String, number: Int) -> Command {
        ledger.order(repo: repo, number: number, to: .storage)
        let door = doorCell(of: room.key) ?? room.cells.first ?? Cell(x: 0, y: 0)
        let from = Spot(area: .office, station: name, owner: room.key, label: room.name, cell: door,
                        pos: SIMD3(offset.x + Double(door.x), 0, offset.y + Double(door.y)))
        return .carry(CrateRef(station: name, repo: repo, number: number), from: from, to: .storage)
    }

    func carryFromDecon(repo: String, number: Int) -> Command? {
        guard let here = layout(of: .decon).first(where: { $0.repo == repo && $0.number == number && !$0.carried }) else { return nil }
        ledger.order(repo: repo, number: number, to: .storage)
        return .carry(CrateRef(station: name, repo: repo, number: number), from: standing(here, in: .decon), to: .storage)
    }

    func standing(_ s: YardSlot, in yard: Yard) -> Spot {
        Spot(area: Station.area(yard, cleared: s.cleared), station: name, owner: s.repo, label: s.repo, cell: s.cell, pos: s.pos,
             level: s.level, yaw: s.yaw)
    }

    private static func area(_ yard: Yard, cleared: Bool) -> Spot.Area {
        switch yard {
        case .storage: return .storage
        case .deck: return cleared ? .tested : .deck
        case .decon: return .decon
        case .pad: return .pad
        }
    }

    private func yardRows(_ yard: Yard) -> (Int) -> [Cell] {
        switch yard {
        case .deck: return { $0 == 0 ? self.hall.clearedCells : self.hall.stagedCells }
        case .decon:
            let back = hall.deconCells.map(\.y).max()
            let row = hall.deconCells.filter { $0.y == back }.sorted { $0.x < $1.x }
            return { _ in row }
        case .storage: return { _ in self.hall.storageCells }
        case .pad: return { _ in [] }
        }
    }

    private func aside(in yard: Yard, above slot: YardSlot, going: Set<Int>, standing: [YardSlot], after: inout [Int: Int]) -> [Command] {
        let blockers = standing.filter { $0.group == slot.group && $0.column == slot.column && $0.level > slot.level && !going.contains($0.number) }
            .sorted { $0.level > $1.level }
        guard !blockers.isEmpty else { return [] }
        let moved = layout(of: yard, aside: Dictionary(uniqueKeysWithValues: blockers.map { ("\($0.repo)#\($0.number)", $0.column) }))
        var out: [Command] = []
        for b in blockers where moved.contains(where: { $0.repo == b.repo && $0.number == b.number }) {
            ledger.order(repo: b.repo, number: b.number, to: yard)
            let command = Command.carry(CrateRef(station: name, repo: b.repo, number: b.number), from: self.standing(b, in: yard), to: yard,
                                        after: after[b.column].map { [$0] } ?? [])
            after[b.column] = command.id
            out.append(command)
        }
        return out
    }

    private func grounded(_ slot: YardSlot, in layout: [YardSlot]) -> YardSlot {
        let taken = Set(layout.filter { $0.group == slot.group && $0.column == slot.column && $0.number != slot.number && !$0.carried }.map(\.level))
        var level = slot.level
        while level > 0 && !taken.contains(level - 1) { level -= 1 }
        while taken.contains(level) { level += 1 }
        return level == slot.level ? slot : slot.lowered(to: level)
    }

    private static func jitter(repo: String, number: Int) -> (Double, Double, Double) {
        var seed = stableHash("\(repo)#\(number)") | 1
        func rnd() -> Double { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Double(seed >> 11) / Double(1 << 53) }
        return ((rnd() - 0.5) * 0.22, (rnd() - 0.5) * 0.3, (rnd() - 0.5) * 0.7)
    }
}
