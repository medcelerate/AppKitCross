// A band-limited resampler whose ratio may change from one call to the next (Smith's
// "bandlimited interpolation": one Kaiser-windowed sinc prototype, sampled densely, read
// at `t / s` for a stretch `s = max(1, ratio)` so the cutoff follows the lower of the two
// rates). Varispeed, the time-pitch unit's pitch stage and AVAudioConverter's sample-rate
// conversion run on it. Everything is allocated at construction; `produce` runs on the
// render thread.

import Foundation

final class _Resampler {
    let channels: Int
    /// Input frames consumed per output frame; may change between `produce` calls within
    /// `1 / maxStretch ... maxStretch`.
    var ratio: Double
    private let maxStretch: Double
    private static let zeroCrossings = 16
    private static let resolution = 256                 // table entries per zero crossing
    private static let prototype: UnsafeMutablePointer<Float> = {
        let n = zeroCrossings * resolution
        let table = UnsafeMutablePointer<Float>.allocate(capacity: n + 2)
        let cutoff = 0.95, beta = 8.0
        let i0beta = besselI0(beta)
        for i in 0...(n + 1) {
            let u = Double(i) / Double(resolution)        // in input samples at stretch 1
            let x = u / Double(zeroCrossings)
            var w = 0.0
            if x < 1 { w = besselI0(beta * (1 - x * x).squareRoot()) / i0beta }
            let s = u == 0 ? 1.0 : sin(Double.pi * cutoff * u) / (Double.pi * cutoff * u)
            table[i] = Float(cutoff * s * w)
        }
        return table
    }()
    private let history: UnsafeMutablePointer<UnsafeMutablePointer<Float>>
    private let historyCapacity: Int
    private var historyCount: Int
    private var position: Double        // fractional index of the next output in `history`
    private let lead: Int               // zeros kept before the first input sample

    /// `maxOutputFrames` bounds one `produce` call; `maxStretch` the largest ratio (or its
    /// inverse) the resampler will be asked for.
    init(channels: Int, ratio: Double, maxStretch: Double, maxOutputFrames: Int) {
        self.channels = channels
        self.ratio = ratio
        self.maxStretch = max(1, maxStretch)
        lead = Int((Double(_Resampler.zeroCrossings) * self.maxStretch).rounded(.up)) + 1
        historyCapacity = Int(Double(maxOutputFrames) * self.maxStretch) + 4 * lead + 64
        history = .allocate(capacity: channels)
        for c in 0..<channels {
            history[c] = .allocate(capacity: historyCapacity)
            history[c].initialize(repeating: 0, count: historyCapacity)
        }
        historyCount = lead
        position = Double(lead)
    }

    deinit {
        for c in 0..<channels { history[c].deallocate() }
        history.deallocate()
    }

    private static func besselI0(_ x: Double) -> Double {
        var sum = 1.0, term = 1.0, k = 1.0
        let q = x * x / 4
        while term > 1e-12 * sum { term *= q / (k * k); sum += term; k += 1 }
        return sum
    }

    private var stretch: Double { max(1, ratio) }
    private var reach: Int { Int((Double(_Resampler.zeroCrossings) * stretch).rounded(.up)) }

    /// Input frames to push before `outputFrames` frames can be produced at the current ratio.
    func inputFramesNeeded(for outputFrames: Int) -> Int {
        guard outputFrames > 0 else { return 0 }
        let last = position + Double(outputFrames - 1) * ratio
        let needed = Int(last.rounded(.down)) + reach + 2
        return max(0, needed - historyCount)
    }

    /// Room for more input (frames).
    var freeSpace: Int { historyCapacity - historyCount }

    /// Appends input frames (at most `freeSpace`).
    func push(_ planes: UnsafePointer<UnsafeMutablePointer<Float>>, offset: Int = 0, frames: Int) {
        let n = min(frames, historyCapacity - historyCount)
        guard n > 0 else { return }
        for c in 0..<channels { (history[c] + historyCount).update(from: planes[c] + offset, count: n) }
        historyCount += n
    }

    /// Appends silence.
    func pushSilence(frames: Int) {
        let n = min(frames, historyCapacity - historyCount)
        guard n > 0 else { return }
        for c in 0..<channels { (history[c] + historyCount).update(repeating: 0, count: n) }
        historyCount += n
    }

    /// Produces `frames` frames into `out` (at `offset`); the input must already be there.
    func produce(_ out: UnsafePointer<UnsafeMutablePointer<Float>>, offset: Int = 0, frames: Int) {
        var t = position
        let s = stretch
        let reach = self.reach
        let table = _Resampler.prototype
        let res = Double(_Resampler.resolution)
        let limit = _Resampler.zeroCrossings * _Resampler.resolution
        if ratio == 1 && t == t.rounded(.down) {
            // Exact pass-through: no filtering at unity with an integral position.
            let i = Int(t)
            for c in 0..<channels { (out[c] + offset).update(from: history[c] + i, count: frames) }
            t += Double(frames)
        } else {
            let step = res / s           // table entries per input sample
            let gain = Float(1 / s)
            for n in 0..<frames {
                let i = Int(t.rounded(.down))
                let first = i - reach + 1, last = i + reach
                for c in 0..<channels {
                    let x = history[c]
                    var acc: Float = 0
                    var k = first
                    while k <= last {
                        let u = abs(Double(k) - t) * step
                        let j = Int(u)
                        if j < limit {
                            let f = Float(u - Double(j))
                            acc += x[k] * (table[j] + (table[j + 1] - table[j]) * f)
                        }
                        k += 1
                    }
                    out[c][offset + n] = acc * gain
                }
                t += ratio
            }
        }
        position = t
        // Keep `reach` (at the largest stretch) frames before floor(position).
        let keepFrom = Int(position.rounded(.down)) - lead
        if keepFrom > 0 {
            let remaining = historyCount - keepFrom
            if remaining > 0 { for c in 0..<channels { history[c].update(from: history[c] + keepFrom, count: remaining) } }
            historyCount = max(0, remaining)
            position -= Double(keepFrom)
        }
    }

    /// Forgets all input (silence precedes the next).
    func reset() {
        for c in 0..<channels { history[c].update(repeating: 0, count: historyCapacity) }
        historyCount = lead
        position = Double(lead)
    }
}
