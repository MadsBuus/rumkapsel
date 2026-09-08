import AVFoundation
import Foundation

/// A slow, procedurally generated ambient pad. No samples, just oscillators and a big hall.
final class Drone: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let reverb = AVAudioUnitReverb()
    private var source: AVAudioSourceNode!
    private let lock = NSLock()

    private let sampleRate: Double
    private var phases: [Double]
    private var detunePhases: [Double]
    private var freqs: [Double]
    private var targetFreqs: [Double]
    private var lfoPhases: [Double]
    private var chordIndex = 0
    private var chordClock = 0.0
    private var filterState = 0.0
    private var swell = 0.0
    private var masterTarget = 1.0
    private var master = 0.0

    private struct Bell { var freq: Double; var t: Double }
    private var bells: [Bell] = []

    // Voicings in MIDI note numbers. D minor colour throughout, never resolving too hard.
    private static let chords: [[Int]] = [
        [38, 45, 53, 60, 64],   // D m9
        [34, 41, 53, 57, 62],   // Bb maj7
        [41, 48, 57, 60, 67],   // F add9
        [36, 43, 52, 62, 67],   // C add9
        [38, 45, 50, 57, 65],   // D m (open)
        [43, 50, 53, 62, 69],   // G m9
    ]
    private static let pentatonic: [Int] = [74, 77, 79, 81, 84, 86, 89, 91]

    var isEnabled: Bool {
        get { masterTarget > 0 }
        set { masterTarget = newValue ? 1 : 0 }
    }

    init() {
        let out = engine.outputNode
        sampleRate = out.outputFormat(forBus: 0).sampleRate
        let n = Drone.chords[0].count
        phases = (0..<n).map { _ in Double.random(in: 0..<1) }
        detunePhases = (0..<n).map { _ in Double.random(in: 0..<1) }
        lfoPhases = (0..<n).map { _ in Double.random(in: 0..<1) }
        freqs = Drone.chords[0].map(Drone.hz)
        targetFreqs = freqs

        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        source = AVAudioSourceNode(format: format) { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
            guard let self else { return noErr }
            let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
            guard let left = abl[0].mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            self.render(into: left, frames: Int(frameCount))
            if abl.count > 1, let right = abl[1].mData?.assumingMemoryBound(to: Float.self) {
                right.update(from: left, count: Int(frameCount))
            }
            return noErr
        }
        engine.attach(source)
        engine.attach(reverb)
        reverb.loadFactoryPreset(.largeHall2)
        reverb.wetDryMix = 62
        engine.connect(source, to: reverb, format: format)
        engine.connect(reverb, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 0.35
    }

    func start() {
        engine.prepare()
        try? engine.start()
    }

    /// A soft bell: one note of the D pentatonic, chosen from a seed so the same agent rings the same way.
    func ping(seed: Int) {
        lock.lock(); defer { lock.unlock() }
        guard bells.count < 8 else { return }
        let note = Drone.pentatonic[abs(seed) % Drone.pentatonic.count]
        bells.append(Bell(freq: Drone.hz(note), t: 0))
    }

    private static func hz(_ midi: Int) -> Double { 440 * pow(2, Double(midi - 69) / 12) }

    private func render(into buf: UnsafeMutablePointer<Float>, frames: Int) {
        let dt = 1.0 / sampleRate
        let chordLength = 28.0
        let glide = 1.0 - exp(-dt / 2.5)      // a few seconds of portamento between chords
        let cutoff = 1.0 - exp(-2 * .pi * 700 * dt)
        let masterRamp = 1.0 - exp(-dt / 1.5)

        lock.lock()
        var localBells = bells
        bells.removeAll()
        lock.unlock()

        for i in 0..<frames {
            chordClock += dt
            if chordClock >= chordLength {
                chordClock = 0
                chordIndex = (chordIndex + 1) % Drone.chords.count
                targetFreqs = Drone.chords[chordIndex].map(Drone.hz)
            }
            // the pad breathes: a slow swell over the length of each chord
            swell = 0.55 + 0.45 * sin((chordClock / chordLength) * .pi)

            var s = 0.0
            for v in 0..<freqs.count {
                freqs[v] += (targetFreqs[v] - freqs[v]) * glide
                let f = freqs[v]
                phases[v] += f * dt; if phases[v] >= 1 { phases[v] -= 1 }
                detunePhases[v] += f * 1.0035 * dt; if detunePhases[v] >= 1 { detunePhases[v] -= 1 }
                lfoPhases[v] += (0.04 + Double(v) * 0.013) * dt; if lfoPhases[v] >= 1 { lfoPhases[v] -= 1 }
                let lfo = 0.6 + 0.4 * sin(lfoPhases[v] * 2 * .pi)
                let p = phases[v] * 2 * .pi, q = detunePhases[v] * 2 * .pi
                let tone = sin(p) + 0.6 * sin(q) + 0.18 * sin(2 * p) + 0.06 * sin(3 * q)
                let weight = v == 0 ? 0.9 : 0.55
                s += tone * lfo * weight
            }
            s *= 0.11 * swell

            var b = 0.0
            for k in localBells.indices {
                let t = localBells[k].t
                let env = exp(-t * 1.6)
                let w = localBells[k].freq * 2 * .pi * t
                b += (sin(w) + 0.35 * sin(2 * w) * exp(-t * 3) + 0.12 * sin(3.01 * w) * exp(-t * 5)) * env
                localBells[k].t = t + dt
            }
            s += b * 0.07

            filterState += (s - filterState) * cutoff
            master += (masterTarget - master) * masterRamp
            buf[i] = Float(filterState * master)
        }

        localBells.removeAll { $0.t > 6 }
        lock.lock()
        bells = localBells + bells
        lock.unlock()
    }
}
