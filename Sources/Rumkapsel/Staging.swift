import Foundation
import simd

final class StagingBatch {
    let number: Int
    var merged = false
    var deploy = Deploy.unheard
    var deployUsual = Deployments.fallback
    var deploySince = 0.0
    var mergedAt = 0.0

    enum Deploy { case unheard, running, live, failed }

    init(number: Int) { self.number = number }
}

extension Simulation {
    func stagingOpened(station: String, repo: String, number: Int) {
        let key = station + "|" + repo
        if staging[key]?.number != number { staging[key] = StagingBatch(number: number) }
        onLog("\(repo): staging release #\(number) open")
    }

    func stagingMerged(station: String, repo: String, number: Int) {
        let key = station + "|" + repo
        let batch = staging[key].flatMap { $0.number == number ? $0 : nil } ?? StagingBatch(number: number)
        batch.merged = true
        batch.mergedAt = clock
        staging[key] = batch
    }

    func stagingClosed(station: String, repo: String, number: Int) {
        let key = station + "|" + repo
        if staging[key]?.number == number { staging[key] = nil }
    }

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
}
