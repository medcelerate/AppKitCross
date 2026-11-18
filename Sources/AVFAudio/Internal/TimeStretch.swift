// Time stretching for AVAudioUnitTimePitch (and AVAudioPlayer.rate on top of it): a phase
// vocoder with identity phase locking (Laroche and Dolson 1999), followed by the
// band-limited resampler for the pitch shift. Varispeed is the resampler alone. See
// ADR-0028 for the choice and the quality target.
//
// Streaming model: the render graph asks a time effect how many input frames it wants
// before it can produce `n` output frames, pulls them from upstream (in pieces when the
// stretch is large), pushes them, and asks for the output. The vocoder's output time
// maps to input time with no offset (output frame j comes from input frame j * rate), so
// the first output is not delayed; producing it simply pulls half an FFT frame more input.
// Every buffer is allocated when the state is built (on the control thread); the render
// thread only computes.

import Foundation

/// Render-side processor of an AVAudioUnitTimeEffect.
protocol _TimeEffectState: AnyObject {
    /// Input frames to push before `frames` output frames can be produced (0: ready).
    func inputFramesWanted(forOutput frames: Int) -> Int
    func push(_ planes: UnsafePointer<UnsafeMutablePointer<Float>>, frames: Int)
    func produce(_ out: UnsafePointer<UnsafeMutablePointer<Float>>, frames: Int)
    /// Whether the unit passes its input through untouched this cycle.
    var isBypassed: Bool { get }
    /// The upstream clock: input frames consumed so far (upstream nodes' sample time).
    var inputSampleTime: Int64 { get set }
}

/// One channel group's phase vocoder. `alpha` is output samples per input sample.
final class _PhaseVocoder {
    let channels: Int
    let size: Int
    let hop: Int
    private let bins: Int
    private let fft: _FFT
    private let window: UnsafeMutablePointer<Float>
    private let overlapSum: UnsafeMutablePointer<Float>    // sum of window^2 per output phase
    // Input: absolute index `inStart` is lane[0].
    private let inLanes: UnsafeMutablePointer<UnsafeMutablePointer<Float>>
    private let inCapacity: Int
    private var inStart: Int64 = 0
    private var inCount = 0
    private var nextStart: Double
    private var prevStart: Int64 = 0
    private var framesDone: Int64 = 0
    // Spectral state per channel.
    private let prevPhase: UnsafeMutablePointer<UnsafeMutablePointer<Float>>
    private let synthPhase: UnsafeMutablePointer<UnsafeMutablePointer<Float>>
    // Scratch.
    private let frame: UnsafeMutablePointer<Float>
    private let re: UnsafeMutablePointer<Float>, im: UnsafeMutablePointer<Float>
    private let mag: UnsafeMutablePointer<Float>, phase: UnsafeMutablePointer<Float>
    private let refPhase: UnsafeMutablePointer<Float>
    private let peaks: UnsafeMutablePointer<Int32>
    // Output accumulator (circular), absolute index `outRead` is the next to emit.
    private let outLanes: UnsafeMutablePointer<UnsafeMutablePointer<Float>>
    private let outCapacity: Int
    private var outRead: Int64 = 0
    /// The analysis reference distance used when the analysis hop is too large for the
    /// previous frame's phases to give the instantaneous frequency.
    private let reference: Int

    init(channels: Int, sampleRate: Double, overlap: Double, maxEmit: Int) {
        self.channels = channels
        size = sampleRate > 100_000 ? 8192 : (sampleRate > 50_000 ? 4096 : 2048)
        let o = max(3, min(32, overlap))
        hop = max(1, Int((Double(size) / o).rounded()))
        bins = size / 2 + 1
        reference = size / 4
        fft = _FFT(size: size)
        window = .allocate(capacity: size)
        for i in 0..<size { window[i] = Float(0.5 - 0.5 * cos(2 * Double.pi * Double(i) / Double(size))) }
        overlapSum = .allocate(capacity: hop)
        for p in 0..<hop {
            var s: Float = 0
            var i = p
            while i < size { s += window[i] * window[i]; i += hop }
            overlapSum[p] = max(s, 1e-6)
        }
        inCapacity = size + reference + 4096
        inLanes = .allocate(capacity: channels)
        outCapacity = size * 2 + hop + maxEmit + 16
        outLanes = .allocate(capacity: channels)
        prevPhase = .allocate(capacity: channels)
        synthPhase = .allocate(capacity: channels)
        for c in 0..<channels {
            inLanes[c] = .allocate(capacity: inCapacity); inLanes[c].initialize(repeating: 0, count: inCapacity)
            outLanes[c] = .allocate(capacity: outCapacity); outLanes[c].initialize(repeating: 0, count: outCapacity)
            prevPhase[c] = .allocate(capacity: bins); prevPhase[c].initialize(repeating: 0, count: bins)
            synthPhase[c] = .allocate(capacity: bins); synthPhase[c].initialize(repeating: 0, count: bins)
        }
        frame = .allocate(capacity: size); frame.initialize(repeating: 0, count: size)
        re = .allocate(capacity: bins); im = .allocate(capacity: bins)
        mag = .allocate(capacity: bins); phase = .allocate(capacity: bins); refPhase = .allocate(capacity: bins)
        peaks = .allocate(capacity: bins)
        nextStart = -Double(size / 2)
    }

    deinit {
        for c in 0..<channels {
            inLanes[c].deallocate(); outLanes[c].deallocate(); prevPhase[c].deallocate(); synthPhase[c].deallocate()
        }
        inLanes.deallocate(); outLanes.deallocate(); prevPhase.deallocate(); synthPhase.deallocate()
        window.deallocate(); overlapSum.deallocate(); frame.deallocate()
        re.deallocate(); im.deallocate(); mag.deallocate(); phase.deallocate(); refPhase.deallocate(); peaks.deallocate()
    }

    func reset() {
        for c in 0..<channels {
            outLanes[c].update(repeating: 0, count: outCapacity)
            prevPhase[c].update(repeating: 0, count: bins)
            synthPhase[c].update(repeating: 0, count: bins)
        }
        inStart = 0; inCount = 0; prevStart = 0; framesDone = 0; outRead = 0
        nextStart = -Double(size / 2)
    }

    private var currentStart: Int64 { Int64(nextStart.rounded(.down)) }
    private var needsReference: Bool { framesDone > 0 && Int(currentStart - prevStart) > reference }

    /// Output frames ready to emit.
    var available: Int { max(0, Int(framesDone * Int64(hop) - Int64(size / 2) - outRead)) }

    /// Whether the next analysis frame's input is all there.
    var hasFrame: Bool { inStart + Int64(inCount) >= currentStart + Int64(size) }

    /// Input frames still missing for the next analysis frame.
    var inputWanted: Int { max(1, Int(currentStart + Int64(size) - (inStart + Int64(inCount)))) }

    /// Appends input, dropping what no future frame reads (all of it when the analysis hop
    /// skips past it).
    func push(_ planes: UnsafePointer<UnsafeMutablePointer<Float>>, offset: Int, frames: Int) {
        let keepFrom = currentStart - Int64(reference)
        if keepFrom > inStart && inCount > 0 {
            let d = Int(min(Int64(inCount), keepFrom - inStart))
            let rest = inCount - d
            if rest > 0 { for c in 0..<channels { inLanes[c].update(from: inLanes[c] + d, count: rest) } }
            inCount = rest
            inStart += Int64(d)
        }
        var skip = 0
        if inCount == 0 && keepFrom > inStart {
            skip = Int(min(Int64(frames), keepFrom - inStart))
            inStart += Int64(skip)
        }
        let n = min(frames - skip, inCapacity - inCount)
        guard n > 0 else { return }
        for c in 0..<channels { (inLanes[c] + inCount).update(from: planes[c] + offset + skip, count: n) }
        inCount += n
    }

    @inline(__always) private func sample(_ lane: UnsafeMutablePointer<Float>, _ absolute: Int64) -> Float {
        if absolute < inStart { return 0 }      // before the first input (negative indices)
        return lane[Int(absolute - inStart)]
    }

    private func analyze(_ lane: UnsafeMutablePointer<Float>, start: Int64, intoPhase phaseOut: UnsafeMutablePointer<Float>, magnitude: Bool) {
        for i in 0..<size { frame[i] = sample(lane, start + Int64(i)) * window[i] }
        fft.forward(frame, re: re, im: im)
        for k in 0..<bins {
            if magnitude { mag[k] = (re[k] * re[k] + im[k] * im[k]).squareRoot() }
            phaseOut[k] = atan2(im[k], re[k])
        }
    }

    @inline(__always) private func wrap(_ x: Float) -> Float {
        let twoPi = Float.pi * 2
        return x - twoPi * (x / twoPi).rounded()
    }

    /// Analyses the next frame and overlap-adds its resynthesis; then advances the
    /// analysis position by `hop / alpha` input frames.
    func processFrame(alpha: Double) {
        let start = currentStart
        let first = framesDone == 0
        let useReference = needsReference
        let dt = first ? Float(hop) : Float(useReference ? reference : Int(start - prevStart))
        let synthHop = Float(hop)
        let outBase = framesDone * Int64(hop) - Int64(size / 2)
        for c in 0..<channels {
            let lane = inLanes[c]
            if useReference {
                analyze(lane, start: start - Int64(reference), intoPhase: refPhase, magnitude: false)
            }
            analyze(lane, start: start, intoPhase: phase, magnitude: true)
            let prev = useReference ? refPhase : prevPhase[c]
            let synth = synthPhase[c]
            if first || dt <= 0 {
                for k in 0..<bins { synth[k] = phase[k] }
            } else {
                // Peaks: local maxima over two neighbours on each side.
                var peakCount = 0
                var k = 2
                while k < bins - 2 {
                    let m = mag[k]
                    if m > mag[k - 1] && m >= mag[k + 1] && m > mag[k - 2] && m >= mag[k + 2] && m > 1e-9 {
                        peaks[peakCount] = Int32(k); peakCount += 1
                    }
                    k += 1
                }
                let omegaScale = 2 * Float.pi / Float(size)
                if peakCount == 0 {
                    for k in 0..<bins {
                        let omega = omegaScale * Float(k)
                        let inst = omega + wrap(phase[k] - prev[k] - omega * dt) / dt
                        synth[k] = wrap(synth[k] + inst * synthHop)
                    }
                } else {
                    // Advance each peak's phase by its instantaneous frequency, then lock
                    // the bins of its region of influence to it (identity phase locking).
                    var regionStart = 0
                    for p in 0..<peakCount {
                        let kp = Int(peaks[p])
                        let regionEnd = p + 1 < peakCount ? (kp + Int(peaks[p + 1])) / 2 : bins - 1
                        let omega = omegaScale * Float(kp)
                        let inst = omega + wrap(phase[kp] - prev[kp] - omega * dt) / dt
                        let peakSynth = wrap(synth[kp] + inst * synthHop)
                        let delta = peakSynth - phase[kp]
                        var j = regionStart
                        while j <= regionEnd { synth[j] = phase[j] + delta; j += 1 }
                        regionStart = regionEnd + 1
                    }
                }
            }
            for k in 0..<bins { prevPhase[c][k] = phase[k] }
            for k in 0..<bins { re[k] = mag[k] * cos(synth[k]); im[k] = mag[k] * sin(synth[k]) }
            im[0] = 0; im[bins - 1] = 0
            fft.inverse(re: re, im: im, output: frame)
            let out = outLanes[c]
            for i in 0..<size {
                let o = outBase + Int64(i)
                if o < outRead { continue }
                let slot = Int(o % Int64(outCapacity))
                out[slot] += frame[i] * window[i]
            }
        }
        prevStart = start
        framesDone += 1
        nextStart += Double(hop) / max(1e-6, alpha)
    }

    /// Moves up to `frames` finished output frames into `planes` (normalized).
    func emit(into planes: UnsafePointer<UnsafeMutablePointer<Float>>, frames: Int) -> Int {
        let n = min(frames, available)
        guard n > 0 else { return 0 }
        let half = Int64(size / 2)
        for c in 0..<channels {
            let out = outLanes[c], dst = planes[c]
            for i in 0..<n {
                let o = outRead + Int64(i)
                let slot = Int(o % Int64(outCapacity))
                let p = Int((o + half) % Int64(hop))
                dst[i] = out[slot] / overlapSum[p]
                out[slot] = 0
            }
        }
        outRead += Int64(n)
        return n
    }
}

/// AVAudioUnitTimePitch's processor: vocoder (time scale `pitch / rate`), then the
/// resampler (ratio `pitch`), so the output lasts `input / rate` at `pitch` times the
/// frequency.
final class _TimePitchState: _TimeEffectState {
    private let unit: AVAudioUnitTimePitch
    private let vocoder: _PhaseVocoder
    private let resampler: _Resampler
    private let scratch: UnsafeMutablePointer<UnsafeMutablePointer<Float>>
    private let scratchCapacity = 1024
    private let channels: Int
    var inputSampleTime: Int64 = 0

    init(unit: AVAudioUnitTimePitch, channels: Int, rate: Double, maxFrames: Int) {
        self.unit = unit
        self.channels = channels
        vocoder = _PhaseVocoder(channels: channels, sampleRate: rate, overlap: Double(unit._overlap.value), maxEmit: scratchCapacity)
        resampler = _Resampler(channels: channels, ratio: 1, maxStretch: 4, maxOutputFrames: maxFrames)
        scratch = .allocate(capacity: channels)
        for c in 0..<channels { scratch[c] = .allocate(capacity: scratchCapacity) }
    }

    deinit {
        for c in 0..<channels { scratch[c].deallocate() }
        scratch.deallocate()
    }

    var isBypassed: Bool { unit._bypass.value }

    private var pitchRatio: Double { pow(2, Double(max(-2400, min(2400, unit._pitch.value))) / 1200) }
    private var rate: Double { Double(max(1.0 / 32, min(32, unit._rate.value))) }

    func inputFramesWanted(forOutput frames: Int) -> Int {
        let rho = pitchRatio
        resampler.ratio = rho
        let alpha = rho / rate
        while true {
            let need = resampler.inputFramesNeeded(for: frames)
            if need <= 0 { return 0 }
            if vocoder.available > 0 {
                let n = vocoder.emit(into: UnsafePointer(scratch), frames: min(need, scratchCapacity, resampler.freeSpace))
                if n <= 0 { return 0 }
                resampler.push(UnsafePointer(scratch), frames: n)
                continue
            }
            if vocoder.hasFrame { vocoder.processFrame(alpha: alpha); continue }
            return vocoder.inputWanted
        }
    }

    func push(_ planes: UnsafePointer<UnsafeMutablePointer<Float>>, frames: Int) {
        vocoder.push(planes, offset: 0, frames: frames)
    }

    func produce(_ out: UnsafePointer<UnsafeMutablePointer<Float>>, frames: Int) {
        resampler.produce(out, frames: frames)
    }
}

/// AVAudioUnitVarispeed's processor: the resampler at ratio `rate`.
final class _VarispeedState: _TimeEffectState {
    private let unit: AVAudioUnitVarispeed
    private let resampler: _Resampler
    var inputSampleTime: Int64 = 0

    init(unit: AVAudioUnitVarispeed, channels: Int, maxFrames: Int) {
        self.unit = unit
        resampler = _Resampler(channels: channels, ratio: 1, maxStretch: 4, maxOutputFrames: maxFrames)
    }

    var isBypassed: Bool { unit._bypass.value }

    func inputFramesWanted(forOutput frames: Int) -> Int {
        resampler.ratio = Double(max(0.25, min(4, unit._rate.value)))
        return min(resampler.inputFramesNeeded(for: frames), resampler.freeSpace)
    }

    func push(_ planes: UnsafePointer<UnsafeMutablePointer<Float>>, frames: Int) { resampler.push(planes, frames: frames) }
    func produce(_ out: UnsafePointer<UnsafeMutablePointer<Float>>, frames: Int) { resampler.produce(out, frames: frames) }
}
