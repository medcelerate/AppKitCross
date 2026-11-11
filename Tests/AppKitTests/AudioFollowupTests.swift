// AVFAudio follow-ups (ADR-0028): time effects, the converter, source and sink nodes,
// streamed file scheduling, CAF, input capture, the recorder and device changes. As in
// AudioTests, everything that runs offline is checked against Apple's AVFAudio on macOS
// too; the real-time and device checks need the port's null backend.

import XCTest
import Foundation
import AVFoundation
#if APPKITWIN_AVFAUDIO
@testable import AVFAudio
#endif

final class AudioFollowupTests: XCTestCase, @unchecked Sendable {

    private func temporaryURL(_ name: String) -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("AudioFollowupTests-\(ProcessInfo.processInfo.processIdentifier)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: url)
        return url
    }

    private func sine(frequency: Double, amplitude: Float, rate: Double, channels: AVAudioChannelCount, frames: Int) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: channels)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
        buffer.frameLength = AVAudioFrameCount(frames)
        for c in 0..<Int(channels) {
            for i in 0..<frames { buffer.floatChannelData![c][i] = amplitude * Float(sin(2 * Double.pi * frequency * Double(i) / rate)) }
        }
        return buffer
    }

    private func renderAll(_ engine: AVAudioEngine, frames: Int) throws -> AVAudioPCMBuffer {
        let format = engine.manualRenderingFormat
        let chunk = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: engine.manualRenderingMaximumFrameCount)!
        let all = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
        var done = 0
        while done < frames {
            let n = AVAudioFrameCount(min(frames - done, Int(engine.manualRenderingMaximumFrameCount)))
            let status = try engine.renderOffline(n, to: chunk)
            XCTAssertEqual(status, .success)
            let got = Int(chunk.frameLength)
            for c in 0..<Int(format.channelCount) { (all.floatChannelData![c] + done).update(from: chunk.floatChannelData![c], count: got) }
            done += got
            if got == 0 { break }
        }
        all.frameLength = AVAudioFrameCount(done)
        return all
    }

    /// Frequency by counting rising zero crossings in `range` (interpolated, so a fraction
    /// of a period at either end does not bias it).
    private func frequency(_ data: UnsafePointer<Float>, range: Range<Int>, rate: Double) -> Double {
        var first: Double?, last = 0.0, count = 0
        for i in (range.lowerBound + 1)..<range.upperBound where data[i - 1] < 0 && data[i] >= 0 {
            let t = Double(i - 1) + Double(-data[i - 1] / (data[i] - data[i - 1]))
            if first == nil { first = t } else { count += 1 }
            last = t
        }
        guard let first, count > 0 else { return 0 }
        return Double(count) / ((last - first) / rate)
    }

    private func rms(_ data: UnsafePointer<Float>, range: Range<Int>) -> Double {
        var e = 0.0
        for i in range { e += Double(data[i] * data[i]) }
        return (e / Double(range.count)).squareRoot()
    }

    /// Signal-to-residual ratio in dB of the best-fitting sine at `frequency` over `range`
    /// (how clean a stretched tone is: phasiness and frame artefacts land in the residual).
    private func toneSNR(_ data: UnsafePointer<Float>, range: Range<Int>, frequency: Double, rate: Double) -> Double {
        var ss = 0.0, sc = 0.0, s2 = 0.0, c2 = 0.0, sxc = 0.0
        for i in range {
            let w = 2 * Double.pi * frequency * Double(i) / rate
            let x = Double(data[i])
            ss += x * sin(w); sc += x * cos(w); s2 += sin(w) * sin(w); c2 += cos(w) * cos(w); sxc += sin(w) * cos(w)
        }
        let det = s2 * c2 - sxc * sxc
        let a = (ss * c2 - sc * sxc) / det, b = (sc * s2 - ss * sxc) / det
        var signal = 0.0, residual = 0.0
        for i in range {
            let w = 2 * Double.pi * frequency * Double(i) / rate
            let fit = a * sin(w) + b * cos(w)
            signal += fit * fit
            let r = Double(data[i]) - fit
            residual += r * r
        }
        return 10 * log10(signal / max(residual, 1e-20))
    }

    /// The last frame louder than `threshold` (the end of the audible output).
    private func audibleEnd(_ data: UnsafePointer<Float>, frames: Int, threshold: Float = 0.05) -> Int {
        var i = frames - 1
        while i > 0 && abs(data[i]) < threshold { i -= 1 }
        return i
    }

    /// A one-channel 48 kHz engine: player -> unit -> main mixer -> output, offline.
    private func timeEffectEngine(_ unit: AVAudioNode, input: AVAudioPCMBuffer) throws -> (AVAudioEngine, AVAudioPlayerNode) {
        let engine = AVAudioEngine()
        let format = input.format
        let player = AVAudioPlayerNode()
        engine.attach(player); engine.attach(unit)
        engine.connect(player, to: unit, format: format)
        engine.connect(unit, to: engine.mainMixerNode, format: format)
        engine.connect(engine.mainMixerNode, to: engine.outputNode, format: format)
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 1024)
        player.scheduleBuffer(input, completionHandler: nil)
        try engine.start()
        player.play()
        return (engine, player)
    }

    // MARK: Time effects

    func testTimePitchRateKeepsThePitch() throws {
        let rate = 48000.0
        let unit = AVAudioUnitTimePitch()
        XCTAssertEqual(unit.rate, 1); XCTAssertEqual(unit.pitch, 0); XCTAssertEqual(unit.overlap, 8)
        unit.rate = 2
        let (engine, _) = try timeEffectEngine(unit, input: sine(frequency: 440, amplitude: 0.5, rate: rate, channels: 1, frames: 24000))
        let out = try renderAll(engine, frames: 24000)
        let data = out.floatChannelData![0]
        let f = frequency(data, range: 2400..<9600, rate: rate)
        XCTAssertEqual(f, 440, accuracy: 440 * 0.01, "a rate of 2 keeps the pitch (measured \(f) Hz)")
        XCTAssertEqual(rms(data, range: 2400..<9600), 0.5 / 2.0.squareRoot(), accuracy: 0.06, "the level survives the stretch")
        let snr = toneSNR(data, range: 2400..<9600, frequency: f, rate: rate)
        XCTAssertGreaterThan(snr, 20, "the stretched tone is clean (\(snr) dB)")
        let end = audibleEnd(data, frames: 24000)
        print("time pitch rate 2: \(f) Hz, rms \(rms(data, range: 2400..<9600)), SNR \(snr) dB, end \(end)")
        XCTAssertEqual(Double(end), 12000, accuracy: 2400, "0.5 s at rate 2 lasts 0.25 s (ended at frame \(end))")
        engine.stop()
    }

    func testTimePitchSlowsDown() throws {
        let rate = 48000.0
        let unit = AVAudioUnitTimePitch()
        unit.rate = 0.5
        let (engine, _) = try timeEffectEngine(unit, input: sine(frequency: 440, amplitude: 0.5, rate: rate, channels: 1, frames: 12000))
        let out = try renderAll(engine, frames: 31200)
        let data = out.floatChannelData![0]
        let f = frequency(data, range: 4800..<19200, rate: rate)
        XCTAssertEqual(f, 440, accuracy: 440 * 0.01, "a rate of 0.5 keeps the pitch (measured \(f) Hz)")
        let snr = toneSNR(data, range: 4800..<19200, frequency: f, rate: rate)
        XCTAssertGreaterThan(snr, 20, "the stretched tone is clean (\(snr) dB)")
        let end = audibleEnd(data, frames: 31200)
        print("time pitch rate 0.5: \(f) Hz, rms \(rms(data, range: 4800..<19200)), SNR \(snr) dB, end \(end)")
        XCTAssertEqual(Double(end), 24000, accuracy: 2400, "0.25 s at rate 0.5 lasts 0.5 s (ended at frame \(end))")
        engine.stop()
    }

    func testTimePitchShiftsPitchAndKeepsTheLength() throws {
        let rate = 48000.0
        let unit = AVAudioUnitTimePitch()
        unit.pitch = 1200
        let (engine, _) = try timeEffectEngine(unit, input: sine(frequency: 440, amplitude: 0.5, rate: rate, channels: 1, frames: 19200))
        let out = try renderAll(engine, frames: 28800)
        let data = out.floatChannelData![0]
        let f = frequency(data, range: 4800..<14400, rate: rate)
        XCTAssertEqual(f, 880, accuracy: 880 * 0.01, "+1200 cents is an octave up (measured \(f) Hz)")
        let snr = toneSNR(data, range: 4800..<14400, frequency: f, rate: rate)
        XCTAssertGreaterThan(snr, 20, "the shifted tone is clean (\(snr) dB)")
        let end = audibleEnd(data, frames: 28800)
        print("time pitch +1200: \(f) Hz, rms \(rms(data, range: 4800..<14400)), SNR \(snr) dB, end \(end)")
        XCTAssertEqual(Double(end), 19200, accuracy: 2400, "the length stays 0.4 s (ended at frame \(end))")
        engine.stop()
    }

    func testVarispeedChangesRateAndPitchTogether() throws {
        let rate = 48000.0
        let unit = AVAudioUnitVarispeed()
        XCTAssertEqual(unit.rate, 1)
        unit.rate = 2
        let (engine, _) = try timeEffectEngine(unit, input: sine(frequency: 440, amplitude: 0.5, rate: rate, channels: 1, frames: 24000))
        let out = try renderAll(engine, frames: 24000)
        let data = out.floatChannelData![0]
        let f = frequency(data, range: 1200..<9600, rate: rate)
        XCTAssertEqual(f, 880, accuracy: 880 * 0.005, "varispeed 2 doubles the frequency (measured \(f) Hz)")
        XCTAssertEqual(rms(data, range: 1200..<9600), 0.5 / 2.0.squareRoot(), accuracy: 0.02)
        let end = audibleEnd(data, frames: 24000)
        XCTAssertEqual(Double(end), 12000, accuracy: 1200, "0.5 s at rate 2 lasts 0.25 s (ended at frame \(end))")
        engine.stop()
    }

    func testTimePitchBypassPassesThrough() throws {
        let unit = AVAudioUnitTimePitch()
        unit.rate = 2
        unit.bypass = true
        let input = sine(frequency: 440, amplitude: 0.5, rate: 48000, channels: 1, frames: 4800)
        let (engine, _) = try timeEffectEngine(unit, input: input)
        let out = try renderAll(engine, frames: 4800)
        var maxError: Float = 0
        for i in 0..<4800 { maxError = max(maxError, abs(out.floatChannelData![0][i] - input.floatChannelData![0][i])) }
        XCTAssertLessThan(maxError, 1e-6, "a bypassed unit passes its input through untouched")
        engine.stop()
    }

    // MARK: AVAudioConverter

    func testConverterSampleFormatsAndInterleaving() throws {
        let rate = 44100.0
        let source = sine(frequency: 1000, amplitude: 0.7, rate: rate, channels: 2, frames: 4410)
        for common in [AVAudioCommonFormat.pcmFormatInt16, .pcmFormatInt32, .pcmFormatFloat64, .pcmFormatFloat32] {
            for interleaved in [true, false] {
                let mid = AVAudioFormat(commonFormat: common, sampleRate: rate, channels: 2, interleaved: interleaved)!
                let there = try XCTUnwrap(AVAudioConverter(from: source.format, to: mid))
                let back = try XCTUnwrap(AVAudioConverter(from: mid, to: source.format))
                XCTAssertEqual(there.inputFormat, source.format)
                XCTAssertEqual(there.outputFormat, mid)
                let middle = AVAudioPCMBuffer(pcmFormat: mid, frameCapacity: 4410)!
                let result = AVAudioPCMBuffer(pcmFormat: source.format, frameCapacity: 4410)!
                try there.convert(to: middle, from: source)
                XCTAssertEqual(middle.frameLength, 4410)
                try back.convert(to: result, from: middle)
                XCTAssertEqual(result.frameLength, 4410)
                let tolerance: Float = common == .pcmFormatInt16 ? 1.0 / 32768 + 1e-6 : 1e-6
                var maxError: Float = 0
                for c in 0..<2 { for i in 0..<4410 { maxError = max(maxError, abs(result.floatChannelData![c][i] - source.floatChannelData![c][i])) } }
                XCTAssertLessThanOrEqual(maxError, tolerance, "round trip through \(common.rawValue) interleaved \(interleaved)")
            }
        }
        // Int16 scaling: 0.5 is 16384.
        let int16 = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: rate, channels: 1, interleaved: false)!
        let half = AVAudioPCMBuffer(pcmFormat: AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!, frameCapacity: 4)!
        half.frameLength = 4
        for i in 0..<4 { half.floatChannelData![0][i] = [0.5, -0.5, 1.0, -1.0][i] }
        let ints = AVAudioPCMBuffer(pcmFormat: int16, frameCapacity: 4)!
        try AVAudioConverter(from: half.format, to: int16)!.convert(to: ints, from: half)
        XCTAssertEqual(Array(UnsafeBufferPointer(start: ints.int16ChannelData![0], count: 4)), [16384, -16384, 32767, -32768])
    }

    func testConverterChannelMapping() throws {
        let rate = 48000.0
        let mono = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
        let stereo = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2)!
        let m = AVAudioPCMBuffer(pcmFormat: mono, frameCapacity: 8)!
        m.frameLength = 8
        for i in 0..<8 { m.floatChannelData![0][i] = Float(i) / 10 }
        let up = AVAudioPCMBuffer(pcmFormat: stereo, frameCapacity: 8)!
        try AVAudioConverter(from: mono, to: stereo)!.convert(to: up, from: m)
        for i in 0..<8 {
            XCTAssertEqual(up.floatChannelData![0][i], Float(i) / 10, accuracy: 1e-6, "mono goes to the left")
            XCTAssertEqual(up.floatChannelData![1][i], Float(i) / 10, accuracy: 1e-6, "and to the right")
        }
        // An explicit channel map: swap left and right.
        let s = AVAudioPCMBuffer(pcmFormat: stereo, frameCapacity: 8)!
        s.frameLength = 8
        for i in 0..<8 { s.floatChannelData![0][i] = 0.25; s.floatChannelData![1][i] = -0.5 }
        let swap = AVAudioConverter(from: stereo, to: stereo)!
        swap.channelMap = [1, 0]
        let swapped = AVAudioPCMBuffer(pcmFormat: stereo, frameCapacity: 8)!
        try swap.convert(to: swapped, from: s)
        XCTAssertEqual(swapped.floatChannelData![0][3], -0.5, accuracy: 1e-6)
        XCTAssertEqual(swapped.floatChannelData![1][3], 0.25, accuracy: 1e-6)
        // Stereo to mono with downmix mixes both channels.
        let down = AVAudioConverter(from: stereo, to: mono)!
        down.downmix = true
        XCTAssertTrue(down.downmix)
        let mixed = AVAudioPCMBuffer(pcmFormat: mono, frameCapacity: 8)!
        try down.convert(to: mixed, from: s)
        XCTAssertNotEqual(mixed.floatChannelData![0][3], 0.25, "the right channel contributes")
        XCTAssertLessThan(mixed.floatChannelData![0][3], 0, "0.25 and -0.5 mix to a negative sample")
    }

    func testConverterSampleRateRoundTrip() throws {
        let inRate = 44100.0, outRate = 48000.0
        let source = sine(frequency: 1000, amplitude: 0.5, rate: inRate, channels: 1, frames: 44100)
        let up = try XCTUnwrap(AVAudioConverter(from: source.format, to: AVAudioFormat(standardFormatWithSampleRate: outRate, channels: 1)!))
        XCTAssertThrowsError(try up.convert(to: AVAudioPCMBuffer(pcmFormat: up.outputFormat, frameCapacity: 48000)!, from: source),
                             "the simple conversion does not change the sample rate")
        let converted = try convertStream(up, input: source, chunk: 1000, capacity: 60000)
        XCTAssertEqual(Double(converted.frameLength), 48000, accuracy: 2, "one second stays one second")
        let data = converted.floatChannelData![0]
        let f = frequency(data, range: 4800..<43200, rate: outRate)
        XCTAssertEqual(f, 1000, accuracy: 0.5, "the tone stays at 1 kHz (measured \(f) Hz)")
        XCTAssertEqual(rms(data, range: 4800..<43200), 0.5 / 2.0.squareRoot(), accuracy: 0.005)
        // Back to 44.1 kHz: the middle matches the original (allowing for the converter's
        // alignment).
        let down = try XCTUnwrap(AVAudioConverter(from: converted.format, to: source.format))
        let back = try convertStream(down, input: converted, chunk: 777, capacity: 50000)
        XCTAssertEqual(Double(back.frameLength), 44100, accuracy: 4)
        let lag = bestLag(back.floatChannelData![0], source.floatChannelData![0], range: 4410..<39690, maxLag: 200)
        var maxError: Float = 0
        for i in 4410..<39690 { maxError = max(maxError, abs(back.floatChannelData![0][i + lag] - source.floatChannelData![0][i])) }
        XCTAssertLessThan(maxError, 0.01, "44.1 -> 48 -> 44.1 kHz preserves the signal (lag \(lag))")
        #if APPKITWIN_AVFAUDIO
        XCTAssertEqual(lag, 0, "the port's converter adds no delay")
        #endif
    }

    /// Feeds `input` to `converter` in chunks of `chunk` frames through the block API.
    private func convertStream(_ converter: AVAudioConverter, input: AVAudioPCMBuffer, chunk: Int, capacity: Int) throws -> AVAudioPCMBuffer {
        final class Feed: @unchecked Sendable { var offset = 0; let input: AVAudioPCMBuffer; init(_ b: AVAudioPCMBuffer) { input = b } }
        let feed = Feed(input)
        let total = Int(input.frameLength)
        let out = AVAudioPCMBuffer(pcmFormat: converter.outputFormat, frameCapacity: AVAudioFrameCount(capacity))!
        let piece = AVAudioPCMBuffer(pcmFormat: converter.outputFormat, frameCapacity: 4096)!
        var produced = 0
        for _ in 0..<1000 {
            var error: NSError?
            let status = converter.convert(to: piece, error: &error) { _, outStatus in
                if feed.offset >= total { outStatus.pointee = .endOfStream; return nil }
                let n = min(chunk, total - feed.offset)
                let input = feed.input
                let b = AVAudioPCMBuffer(pcmFormat: input.format, frameCapacity: AVAudioFrameCount(n))!
                b.frameLength = AVAudioFrameCount(n)
                for c in 0..<Int(input.format.channelCount) { b.floatChannelData![c].update(from: input.floatChannelData![c] + feed.offset, count: n) }
                feed.offset += n
                outStatus.pointee = .haveData
                return b
            }
            XCTAssertNil(error)
            XCTAssertNotEqual(status, .error)
            let n = Int(piece.frameLength)
            for c in 0..<Int(out.format.channelCount) { (out.floatChannelData![c] + produced).update(from: piece.floatChannelData![c], count: min(n, capacity - produced)) }
            produced = min(capacity, produced + n)
            if status == .endOfStream { break }
        }
        out.frameLength = AVAudioFrameCount(produced)
        return out
    }

    private func bestLag(_ a: UnsafePointer<Float>, _ b: UnsafePointer<Float>, range: Range<Int>, maxLag: Int) -> Int {
        var best = 0, bestError = Double.infinity
        for lag in -maxLag...maxLag {
            var e = 0.0
            var i = range.lowerBound
            while i < range.upperBound { let d = Double(a[i + lag] - b[i]); e += d * d; i += 7 }
            if e < bestError { bestError = e; best = lag }
        }
        return best
    }

    // MARK: Source node

    func testSourceNodeRendersItsBlock() throws {
        final class Counter: @unchecked Sendable { var frames = 0; var calls = 0 }
        let counter = Counter()
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        let source = AVAudioSourceNode { _, _, frameCount, list in
            let abl = UnsafeMutableAudioBufferListPointer(list)
            for (c, buffer) in abl.enumerated() {
                let p = buffer.mData!.assumingMemoryBound(to: Float.self)
                for i in 0..<Int(frameCount) { p[i] = c == 0 ? 0.25 : -0.25 }
            }
            counter.frames += Int(frameCount); counter.calls += 1
            return noErr
        }
        let engine = AVAudioEngine()
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: format)
        engine.connect(engine.mainMixerNode, to: engine.outputNode, format: format)
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 512)
        source.volume = 0.5
        try engine.start()
        let out = try renderAll(engine, frames: 2048)
        XCTAssertEqual(out.floatChannelData![0][100], 0.125, accuracy: 1e-6, "the block's 0.25 at volume 0.5")
        XCTAssertEqual(out.floatChannelData![1][2047], -0.125, accuracy: 1e-6)
        XCTAssertEqual(counter.frames, 2048, "the block is asked for every rendered frame")
        XCTAssertGreaterThanOrEqual(counter.calls, 4)
        engine.stop()
    }

    func testSourceNodeConvertsItsBlockFormat() throws {
        // The block renders interleaved Int16 at 24 kHz; the connection is 48 kHz Float32.
        let blockFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 24000, channels: 1, interleaved: true)!
        final class Phase: @unchecked Sendable { var n = 0 }
        let phase = Phase()
        let source = AVAudioSourceNode(format: blockFormat) { _, _, frameCount, list in
            let p = UnsafeMutableAudioBufferListPointer(list)[0].mData!.assumingMemoryBound(to: Int16.self)
            for i in 0..<Int(frameCount) {
                p[i] = Int16(16384 * sin(2 * Double.pi * 500 * Double(phase.n) / 24000)); phase.n += 1
            }
            return noErr
        }
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1)!
        let engine = AVAudioEngine()
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: format)
        engine.connect(engine.mainMixerNode, to: engine.outputNode, format: format)
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 1024)
        try engine.start()
        let out = try renderAll(engine, frames: 24000)
        let f = frequency(out.floatChannelData![0], range: 4800..<24000, rate: 48000)
        XCTAssertEqual(f, 500, accuracy: 1, "a 500 Hz tone at 24 kHz is 500 Hz at 48 kHz (measured \(f))")
        XCTAssertEqual(rms(out.floatChannelData![0], range: 4800..<24000), 0.5 / 2.0.squareRoot(), accuracy: 0.01)
        engine.stop()
    }

    // MARK: Input node in manual rendering mode

    func testManualRenderingInputBlock() throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1)!
        let engine = AVAudioEngine()
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 512)
        let inputBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 512)!
        inputBuffer.frameLength = 512
        inputBuffer.floatChannelData![0].update(repeating: 0.375, count: 512)
        final class Count: @unchecked Sendable { var frames = 0 }
        let count = Count()
        XCTAssertTrue(engine.inputNode.setManualRenderingInputPCMFormat(format) { frames in
            count.frames += Int(frames)
            inputBuffer.frameLength = frames
            return inputBuffer.audioBufferList
        })
        engine.connect(engine.inputNode, to: engine.mainMixerNode, format: format)
        engine.connect(engine.mainMixerNode, to: engine.outputNode, format: format)
        try engine.start()
        let out = try renderAll(engine, frames: 1024)
        XCTAssertEqual(out.floatChannelData![0][0], 0.375, accuracy: 1e-6)
        XCTAssertEqual(out.floatChannelData![0][1023], 0.375, accuracy: 1e-6)
        XCTAssertEqual(count.frames, 1024)
        engine.stop()
    }

    // MARK: Files

    func testCAFRoundTrips() throws {
        for (bits, isFloat) in [(16, false), (24, false), (32, true)] {
            let url = temporaryURL("round-\(bits)\(isFloat ? "f" : "").caf")
            let source = sine(frequency: 440, amplitude: 0.5, rate: 44100, channels: 2, frames: 4410)
            do {
                let file = try AVAudioFile(forWriting: url, settings: [AVFormatIDKey: Int(kAudioFormatLinearPCM), AVSampleRateKey: 44100.0, AVNumberOfChannelsKey: 2, AVLinearPCMBitDepthKey: bits, AVLinearPCMIsFloatKey: isFloat])
                try file.write(from: source)
            }
            let head = try Data(contentsOf: url).prefix(4)
            XCTAssertEqual(String(decoding: head, as: UTF8.self), "caff")
            let read = try AVAudioFile(forReading: url)
            XCTAssertEqual(read.length, 4410)
            XCTAssertEqual(read.fileFormat.sampleRate, 44100)
            XCTAssertEqual(read.fileFormat.channelCount, 2)
            XCTAssertEqual(read.fileFormat.streamDescription.pointee.mBitsPerChannel, UInt32(bits))
            let buffer = AVAudioPCMBuffer(pcmFormat: read.processingFormat, frameCapacity: 4410)!
            try read.read(into: buffer)
            XCTAssertEqual(buffer.frameLength, 4410)
            var maxError: Float = 0
            for c in 0..<2 { for i in 0..<4410 { maxError = max(maxError, abs(buffer.floatChannelData![c][i] - source.floatChannelData![c][i])) } }
            XCTAssertLessThanOrEqual(maxError, bits == 16 ? 1.0 / 32768 + 1e-6 : 1e-6, "CAF \(bits)-bit\(isFloat ? " float" : "")")
        }
    }

    /// A segment scheduled from a long file renders exactly what decoding the whole file
    /// gives (the port streams it from disk in chunks).
    func testScheduledFileMatchesWholeFileDecode() throws {
        let url = temporaryURL("long.wav")
        let frames = 48000 * 3 + 123
        do {
            let file = try AVAudioFile(forWriting: url, settings: [AVFormatIDKey: Int(kAudioFormatLinearPCM), AVSampleRateKey: 48000.0, AVNumberOfChannelsKey: 2, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false])
            let b = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(frames))!
            b.frameLength = AVAudioFrameCount(frames)
            for i in 0..<frames {
                b.floatChannelData![0][i] = Float(sin(Double(i) * 0.01)) * 0.5
                b.floatChannelData![1][i] = Float((i % 1000)) / 2000 - 0.25
            }
            try file.write(from: b)
        }
        let reader = try AVAudioFile(forReading: url)
        let whole = AVAudioPCMBuffer(pcmFormat: reader.processingFormat, frameCapacity: AVAudioFrameCount(frames))!
        try reader.read(into: whole)
        XCTAssertEqual(Int(whole.frameLength), frames)

        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        engine.connect(engine.mainMixerNode, to: engine.outputNode, format: format)
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096)
        let done = expectation(description: "file consumed")
        let start: AVAudioFramePosition = 1000
        let count = AVAudioFrameCount(frames - 2000)
        player.scheduleSegment(try AVAudioFile(forReading: url), startingFrame: start, frameCount: count, at: nil) { done.fulfill() }
        try engine.start()
        player.play()
        let out = try renderAll(engine, frames: Int(count) + 4800)
        var mismatches = 0
        for c in 0..<2 {
            for i in 0..<Int(count) where abs(out.floatChannelData![c][i] - whole.floatChannelData![c][i + Int(start)]) > 1e-6 { mismatches += 1 }
        }
        XCTAssertEqual(mismatches, 0, "the streamed segment equals the decoded file")
        XCTAssertEqual(out.floatChannelData![0][Int(count) + 10], 0, "silence after the segment")
        wait(for: [done], timeout: 5)
        engine.stop()
    }

    // MARK: Port-only: real-time input, recorder, devices, AVAudioPlayer.rate

    #if APPKITWIN_AVFAUDIO
    private func waitUntil(_ seconds: Double = 3, _ condition: () -> Bool) {
        let deadline = Date(timeIntervalSinceNow: seconds)
        while !condition() && Date() < deadline { Thread.sleep(forTimeInterval: 0.005) }
    }

    private func withNullBackend(_ body: (NullAudioBackend) throws -> Void) rethrows {
        let previous = PlatformAudio.backend
        let null = NullAudioBackend()
        PlatformAudio.backend = null
        defer { PlatformAudio.backend = previous }
        try body(null)
    }

    func testInputNodeTapAndSinkNode() throws {
        try withNullBackend { _ in
            final class Received: @unchecked Sendable {
                let lock = NSLock(); var samples: [Float] = []; var sinkFrames = 0
            }
            let received = Received()
            let engine = AVAudioEngine()
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            XCTAssertEqual(format.sampleRate, 48000)
            XCTAssertEqual(format.channelCount, 1)
            let sink = AVAudioSinkNode { _, frames, list in
                received.lock.lock(); received.sinkFrames += Int(frames); received.lock.unlock()
                _ = list
                return noErr
            }
            engine.attach(sink)
            engine.connect(input, to: sink, format: format)
            input.installTap(onBus: 0, bufferSize: 1024, format: nil) { buffer, _ in
                received.lock.lock()
                received.samples.append(contentsOf: UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
                received.lock.unlock()
            }
            _ = engine.mainMixerNode
            try engine.start()
            waitUntil { received.lock.lock(); defer { received.lock.unlock() }; return received.samples.count > 9600 && received.sinkFrames > 9600 }
            engine.stop()
            received.lock.lock(); let samples = received.samples; let sinkFrames = received.sinkFrames; received.lock.unlock()
            XCTAssertGreaterThan(sinkFrames, 9600, "the sink node is pulled every cycle")
            XCTAssertGreaterThan(samples.count, 9600, "the input tap delivers")
            // The null input captures a 440 Hz sine at 0.25 (after a possible lead-in of
            // silence while the capture thread starts).
            let lead = samples.firstIndex { abs($0) > 0.01 } ?? 0
            let window = Array(samples[lead..<min(samples.count, lead + 4800)])
            XCTAssertEqual(window.map { abs($0) }.max() ?? 0, 0.25, accuracy: 0.01)
            let f = window.withUnsafeBufferPointer { frequency($0.baseAddress!, range: 0..<window.count, rate: 48000) }
            XCTAssertEqual(f, 440, accuracy: 10, "captured tone (measured \(f) Hz)")
        }
    }

    final class RecorderDelegate: NSObject, AVAudioRecorderDelegate, @unchecked Sendable {
        let finished = XCTestExpectation(description: "recorder finished")
        var flag = false
        func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
            self.flag = flag
            finished.fulfill()
        }
    }

    func testRecorderWritesAReadableFile() throws {
        for ext in ["wav", "caf"] {
            try withNullBackend { _ in
                let url = temporaryURL("recording.\(ext)")
                let recorder = try AVAudioRecorder(url: url, settings: [AVFormatIDKey: Int(kAudioFormatLinearPCM), AVSampleRateKey: 44100.0, AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false])
                XCTAssertEqual(recorder.url, url)
                XCTAssertFalse(recorder.isRecording)
                let delegate = RecorderDelegate()
                recorder.delegate = delegate
                recorder.isMeteringEnabled = true
                XCTAssertTrue(recorder.prepareToRecord())
                XCTAssertTrue(recorder.record())
                XCTAssertTrue(recorder.isRecording)
                waitUntil { recorder.currentTime > 0.25 }
                XCTAssertGreaterThan(recorder.currentTime, 0.25)
                recorder.updateMeters()
                XCTAssertGreaterThan(recorder.averagePower(forChannel: 0), -20, "a 0.25 sine meters near -15 dB")
                XCTAssertLessThan(recorder.peakPower(forChannel: 0), -10)
                recorder.pause()
                XCTAssertFalse(recorder.isRecording)
                let paused = recorder.currentTime
                Thread.sleep(forTimeInterval: 0.1)
                XCTAssertEqual(recorder.currentTime, paused, accuracy: 0.03, "pause stops the clock")
                XCTAssertTrue(recorder.record())
                waitUntil { recorder.currentTime > paused + 0.2 }
                recorder.stop()
                XCTAssertFalse(recorder.isRecording)
                wait(for: [delegate.finished], timeout: 5)
                XCTAssertTrue(delegate.flag)
                let file = try AVAudioFile(forReading: url)
                XCTAssertEqual(file.fileFormat.sampleRate, 44100)
                XCTAssertEqual(file.fileFormat.channelCount, 1)
                XCTAssertGreaterThan(file.length, AVAudioFramePosition(0.4 * 44100), "both takes are in the file")
                let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
                try file.read(into: buffer)
                let n = Int(buffer.frameLength)
                let f = frequency(buffer.floatChannelData![0], range: (n / 4)..<(n / 2), rate: 44100)
                XCTAssertEqual(f, 440, accuracy: 10, "the recording holds the 440 Hz input, resampled to 44.1 kHz (\(f) Hz)")
                XCTAssertTrue(recorder.deleteRecording())
                XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
            }
        }
    }

    func testDeviceSelectionAndConfigurationChange() throws {
        try withNullBackend { null in
            let engine = AVAudioEngine()
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: nil)
            engine._outputDeviceUID = "null-2"
            try engine.start()
            XCTAssertEqual(engine._currentOutputDeviceUID, "null-2")
            XCTAssertEqual(engine.outputNode.outputFormat(forBus: 0).sampleRate, 44100, "the second null device runs at 44.1 kHz")
            // Moving while running reopens on the other device and keeps running.
            engine._outputDeviceUID = nil
            XCTAssertTrue(engine.isRunning)
            XCTAssertEqual(engine._currentOutputDeviceUID, "null")
            XCTAssertEqual(engine.outputNode.outputFormat(forBus: 0).sampleRate, 48000)

            // The default changing under an engine that follows it stops the engine and
            // posts the notification; start() reopens.
            let changed = expectation(forNotification: .AVAudioEngineConfigurationChange, object: engine)
            null.simulate(.defaultDeviceChanged(isInput: false, id: "null-2"))
            wait(for: [changed], timeout: 5)
            XCTAssertFalse(engine.isRunning, "the engine stops itself on a configuration change")
            try engine.start()
            XCTAssertTrue(engine.isRunning)

            // Unplugging the selected device: notified, and start() falls back to the default.
            engine._outputDeviceUID = "null-2"
            XCTAssertEqual(engine._currentOutputDeviceUID, "null-2")
            let unplugged = expectation(forNotification: .AVAudioEngineConfigurationChange, object: engine)
            null.simulate(.deviceRemoved(id: "null-2"))
            wait(for: [unplugged], timeout: 5)
            XCTAssertFalse(engine.isRunning)
            try engine.start()
            XCTAssertEqual(engine._currentOutputDeviceUID, "null", "a vanished selection falls back to the default")
            // A change that concerns another device is ignored.
            let ignored = expectation(forNotification: .AVAudioEngineConfigurationChange, object: engine)
            ignored.isInverted = true
            null.simulate(.deviceAdded(id: "null-2"))
            wait(for: [ignored], timeout: 0.3)
            XCTAssertTrue(engine.isRunning)
            engine.stop()
        }
    }

    final class FinishDelegate: NSObject, AVAudioPlayerDelegate {
        let finished = XCTestExpectation(description: "finished")
        func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) { finished.fulfill() }
    }

    func testAVAudioPlayerRate() throws {
        let url = temporaryURL("rate.wav")
        do {
            let writer = try AVAudioFile(forWriting: url, settings: [AVFormatIDKey: Int(kAudioFormatLinearPCM), AVSampleRateKey: 48000.0, AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false])
            try writer.write(from: sine(frequency: 440, amplitude: 0.5, rate: 48000, channels: 1, frames: 19200))   // 0.4 s
        }
        try withNullBackend { _ in
            let player = try AVAudioPlayer(contentsOf: url)
            XCTAssertFalse(player.enableRate)
            player.enableRate = true
            player.rate = 2
            XCTAssertEqual(player.rate, 2)
            player.rate = 5
            XCTAssertEqual(player.rate, 2, "the rate is clamped to 0.5 ... 2")
            player.rate = 2
            let delegate = FinishDelegate()
            player.delegate = delegate
            let started = Date()
            XCTAssertTrue(player.play())
            waitUntil { player.currentTime > 0.1 }
            XCTAssertGreaterThan(player.currentTime, 0.1)
            wait(for: [delegate.finished], timeout: 5)
            let elapsed = Date().timeIntervalSince(started)
            print("0.4 s at rate 2 finished after \(elapsed) s")
            XCTAssertFalse(player.isPlaying)
            XCTAssertEqual(player.currentDevice, "null", "the player reports the device it plays on")
        }
    }
    #endif
}
