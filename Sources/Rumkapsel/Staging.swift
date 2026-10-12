// A repository's staging release as the station follows it: opened, merged, and the deploy that puts it on
// staging. The crates move by the yard's ordinary carries (the board's word, or the merge where there is no
// board); this is what their lights and the rocket's tip are read from. No SceneKit.

import Foundation
import simd

/// One open or merged staging release, per "station|repo".
final class StagingBatch {
    let number: Int
    /// Merged into the staging branch: its crates belong in the staged rows.
    var merged = false
    var deploy = Deploy.unheard
    /// How long the repository's staging deploys usually take, and when this one began.
    var deployUsual = Deployments.fallback
    var deploySince = 0.0
    /// When it merged, for how long a deploy that never shows is waited for.
    var mergedAt = 0.0

    enum Deploy { case unheard, running, live, failed }

    init(number: Int) { self.number = number }
}

/// What a crate's light says about where it is in the line.
enum CrateLight {
    /// In storage: not on staging yet.
    case off
    /// Staged while its staging deploy runs: not testable yet.
    case deploying
    /// Staged and live on staging, waiting for a tester.
    case waiting
    /// Tested.
    case passed
    /// Staged while its staging deploy has failed.
    case failed
}

extension Simulation {
    /// A staging release opened: the station knows the batch from now, its crates still in storage.
    func stagingOpened(station: String, repo: String, number: Int) {
        let key = station + "|" + repo
        if staging[key]?.number != number { staging[key] = StagingBatch(number: number) }
        onLog("\(repo): staging release #\(number) open")
    }

    /// A staging release merged: its deploy is on its way, and its crates go to the staged rows.
    func stagingMerged(station: String, repo: String, number: Int) {
        let key = station + "|" + repo
        let batch = staging[key].flatMap { $0.number == number ? $0 : nil } ?? StagingBatch(number: number)
        batch.merged = true
        batch.mergedAt = clock
        staging[key] = batch
    }

    /// A staging release closed unmerged: nothing went to staging.
    func stagingClosed(station: String, repo: String, number: Int) {
        let key = station + "|" + repo
        if staging[key]?.number == number { staging[key] = nil }
    }

    /// A staging deploy started or ended for a repository. Heard before or after the merge: the deploy
    /// watcher and the release poll answer in either order.
    func stagingDeploy(station name: String, repo: String, outcome: DeployOutcome?, usual: TimeInterval = Deployments.fallback, elapsed: TimeInterval = 0) {
        let key = name + "|" + repo
        let batch = staging[key] ?? {
            let b = StagingBatch(number: 0)
            b.merged = true
            b.mergedAt = clock
            staging[key] = b
            return b
        }()
        switch outcome {
        case nil: batch.deploy = .running; batch.deployUsual = usual; batch.deploySince = clock - elapsed
        case .live?: batch.deploy = .live
        default: batch.deploy = .failed
        }
        if let outcome { onLog("\(repo): staging deploy \(outcome == .live ? "is live" : "\(outcome)")") }
    }

    /// The light on a crate standing in the yard.
    func light(of crate: Ledger.Crate, station: String) -> CrateLight {
        guard crate.placed == .deck || crate.heading == .deck else { return .off }
        if crate.cleared { return .passed }
        switch staging[station + "|" + crate.repo]?.deploy {
        case .running?: return .deploying
        case .failed?: return .failed
        case .unheard? where (staging[station + "|" + crate.repo]?.merged ?? false)
            && clock - (staging[station + "|" + crate.repo]?.mergedAt ?? 0) < Deployments.findWithin: return .deploying
        default: return .waiting
        }
    }

    /// Where a repository's rocket stands on the pad, in the station's own coordinates.
    func rocketSpot(station: Station, repo: String) -> SIMD2<Double>? {
        guard let slot = world.padSlotOf[station.name + "|" + repo], !station.padSlots.isEmpty else { return nil }
        return station.padSlots[slot % station.padSlots.count]
    }

    /// Every tip wanting welding while its staging deploy runs. The weld creeps up the hull ring by ring at
    /// the pace the repository's deploys usually take, the last panel held back until the deploy is live: a
    /// new tip gains its panels as it goes, a whole one is welded over afresh from the bottom ring. A tip with
    /// no merged staging release is whole. A drone does the welding (`Drones.swift`) and says where its torch is.
    func stepTips(dt: Double) {
        let full = Double(RocketGeometry.panels)
        for r in rockets.values {
            let b = staging[r.key].flatMap { $0.merged ? $0 : nil }
            let running = b?.deploy == .running
            let live = b?.deploy == .live
            let pace = (full - 1) / max(20, (b?.deployUsual ?? Deployments.fallback) * 0.85)
            // A deploy seen starting: the weld starts where it has got to, a whole tip from bare.
            if running, !r.deployRunning, let b { r.welded = max(r.fresh ? r.welded : 0, min(full - 1, (clock - b.deploySince) * pace)) }
            r.deployRunning = running
            if b == nil { r.welded = full }
            else if running, r.welded < full - 1 { r.welded = min(full - 1, r.welded + dt * pace) }
            else if live { r.welded = min(full, r.welded + dt * 6) }
            if r.welded >= full { r.fresh = false }
            r.panels = r.fresh ? Int(r.welded) : RocketGeometry.panels
            r.welding = b != nil && (running || (live && r.welded < full))
        }
    }
}
