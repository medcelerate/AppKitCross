// Sample-rate conversion for the mixer and the player node: a windowed-sinc (Kaiser,
// 32 taps per unit of stretch) polyphase interpolator over a planar history buffer.
// Tables are built when the converter is created (control thread); `produce` runs on the
// render thread without allocating.

import Foundation

final class _RateConverter {
    let channels: Int
    let ratio: Double               // input samples per output sample
    private let taps: Int           // total taps, even
    private let half: Int
    private let phases: Int
    private let table: UnsafeMutablePointer<Float>   // (phases + 1) * taps
    private let history: UnsafeMutablePointer<UnsafeMutablePointer<Float>>
    private let historyCapacity: Int
    private var historyCount = 0
    private var position: Double    // fractional read index into history for the next output
    private var primed = false

    init(channels: Int, inputRate: Double, outputRate: Double, maxOutputFrames: Int) {
        self.channels = channels
        ratio = inputRate / outputRate
        let stretch = max(1, Int(ratio.rounded(.up)))
        half = 16 * stretch
        taps = 2 * half
        phases = 512
        table = .allocate(capacity: (phases + 1) * taps)
        let cutoff = min(1.0, 1.0 / ratio) * 0.95
        let beta = 8.0
        let i0beta = _RateConverter.besselI0(beta)
        for p in 0...phases {
            let frac = Double(p) / Double(phases)
            for k in 0..<taps {
                // Tap k sits at input offset (k - half + 1) from floor(t); frac is t - floor(t).
                let u = Double(k - half + 1) - frac
                let x = u / Double(half)
                var w = 0.0
                if abs(x) < 1 { w = _RateConverter.besselI0(beta * (1 - x * x).squareRoot()) / i0beta }
                let s = u == 0 ? 1.0 : sin(Double.pi * cutoff * u) / (Double.pi * cutoff * u)
                table[p * taps + k] = Float(cutoff * s * w)
            }
        }
        historyCapacity = Int(Double(maxOutputFrames) * ratio) + taps * 2 + 64
        history = .allocate(capacity: channels)
        for c in 0..<channels {
            history[c] = .allocate(capacity: historyCapacity)
            history[c].initialize(repeating: 0, count: historyCapacity)
        }
        // Start with `half` zeros before the first input sample, so the first output's
        // filter reaches into silence rather than garbage.
        historyCount = half
        position = Double(half)
    }

    deinit {
        table.deallocate()
        for c in 0..<channels { history[c].deallocate() }
        history.deallocate()
    }

    private static func besselI0(_ x: Double) -> Double {
        var sum = 1.0, term = 1.0
        let q = x * x / 4
        var k = 1.0
        while term > 1e-12 * sum {
            term *= q / (k * k)
            sum += term
            k += 1
        }
        return sum
    }

    /// Input frames that must be pushed before `outputFrames` outputs can be produced.
    func inputFramesNeeded(for outputFrames: Int) -> Int {
        guard outputFrames > 0 else { return 0 }
        let lastT = position + Double(outputFrames - 1) * ratio
        let needed = Int(lastT.rounded(.down)) + half + 1
        return max(0, needed - historyCount)
    }

    /// Appends input frames (render thread; `frames` must fit, see `inputFramesNeeded`).
    func push(_ planes: UnsafePointer<UnsafeMutablePointer<Float>>, frames: Int) {
        guard frames > 0 else { return }
        let n = min(frames, historyCapacity - historyCount)
        for c in 0..<channels { (history[c] + historyCount).update(from: planes[c], count: n) }
        historyCount += n
    }

    /// Produces `frames` output frames into `out`, then discards history no longer needed.
    func produce(_ out: UnsafePointer<UnsafeMutablePointer<Float>>, frames: Int) {
        var t = position
        for n in 0..<frames {
            let i = Int(t.rounded(.down))
            let frac = t - Double(i)
            let fp = frac * Double(phases)
            let p = Int(fp)
            let pf = Float(fp - Double(p))
            let rowA = table + p * taps
            let rowB = rowA + taps
            let start = i - half + 1
            for c in 0..<channels {
                let x = history[c] + start
                var acc: Float = 0
                var k = 0
                while k < taps {
                    let coef = rowA[k] + (rowB[k] - rowA[k]) * pf
                    acc += x[k] * coef
                    k += 1
                }
                out[c][n] = acc
            }
            t += ratio
        }
        position = t
        // Keep `half` samples before floor(position); drop the rest.
        let keepFrom = Int(position.rounded(.down)) - half
        if keepFrom > 0 {
            let remaining = historyCount - keepFrom
            if remaining > 0 { for c in 0..<channels { history[c].update(from: history[c] + keepFrom, count: remaining) } }
            historyCount = max(0, remaining)
            position -= Double(keepFrom)
        }
    }

    /// Forgets all history (silence precedes the next input).
    func reset() {
        for c in 0..<channels { history[c].update(repeating: 0, count: historyCapacity) }
        historyCount = half
        position = Double(half)
    }

    /// Converts a whole buffer at once (control thread): used by file scheduling.
    static func convert(_ input: AVAudioPCMBuffer, to outputRate: Double) -> AVAudioPCMBuffer? {
        let inRate = input.format.sampleRate
        let channels = Int(input.format.channelCount)
        let frames = Int(input.frameLength)
        guard inRate > 0, outputRate > 0, channels > 0, let outFormat = AVAudioFormat(standardFormatWithSampleRate: outputRate, channels: AVAudioChannelCount(channels)) else { return nil }
        if inRate == outputRate {
            guard input.format.commonFormat == .pcmFormatFloat32 && !input.format.isInterleaved else {
                guard let out = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: AVAudioFrameCount(max(1, frames))) else { return nil }
                for c in 0..<channels { input._readFloats(channel: c, frame: 0, count: frames, into: out.floatChannelData![c]) }
                out.frameLength = AVAudioFrameCount(frames)
                return out
            }
            return input
        }
        let outFrames = Int((Double(frames) * outputRate / inRate).rounded(.down))
        guard let out = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: AVAudioFrameCount(max(1, outFrames))) else { return nil }
        let chunk = 1024
        let conv = _RateConverter(channels: channels, inputRate: inRate, outputRate: outputRate, maxOutputFrames: chunk)
        let inPlanes = UnsafeMutablePointer<UnsafeMutablePointer<Float>>.allocate(capacity: channels)
        for c in 0..<channels { inPlanes[c] = .allocate(capacity: frames + 1) ; input._readFloats(channel: c, frame: 0, count: frames, into: inPlanes[c]) }
        let outPlanes = UnsafeMutablePointer<UnsafeMutablePointer<Float>>.allocate(capacity: channels)
        for c in 0..<channels { outPlanes[c] = .allocate(capacity: chunk) }
        let tail = UnsafeMutablePointer<UnsafeMutablePointer<Float>>.allocate(capacity: channels)
        let tailLength = conv.taps
        for c in 0..<channels { tail[c] = .allocate(capacity: tailLength); tail[c].initialize(repeating: 0, count: tailLength) }
        defer {
            for c in 0..<channels { inPlanes[c].deallocate(); outPlanes[c].deallocate(); tail[c].deallocate() }
            inPlanes.deallocate(); outPlanes.deallocate(); tail.deallocate()
        }
        var consumed = 0, produced = 0
        let pushPlanes = UnsafeMutablePointer<UnsafeMutablePointer<Float>>.allocate(capacity: channels)
        defer { pushPlanes.deallocate() }
        while produced < outFrames {
            let n = min(chunk, outFrames - produced)
            var need = conv.inputFramesNeeded(for: n)
            while need > 0 {
                let avail = frames - consumed
                if avail > 0 {
                    let take = min(need, avail)
                    for c in 0..<channels { pushPlanes[c] = inPlanes[c] + consumed }
                    conv.push(UnsafePointer(pushPlanes), frames: take)
                    consumed += take
                    need -= take
                } else {
                    let take = min(need, tailLength)
                    conv.push(UnsafePointer(tail), frames: take)
                    need -= take
                }
            }
            conv.produce(UnsafePointer(outPlanes), frames: n)
            for c in 0..<channels { (out.floatChannelData![c] + produced).update(from: outPlanes[c], count: n) }
            produced += n
        }
        out.frameLength = AVAudioFrameCount(outFrames)
        return out
    }
}
