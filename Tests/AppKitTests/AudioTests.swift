// AVFAudio (ADR-0014): on macOS these run against Apple's AVFAudio, on Windows and Linux
// (and on macOS with APPKITWIN_HOST_AVFAUDIO=1) against Sources/AVFAudio. Same source
// either way; the APPKITWIN_AVFAUDIO define marks the few checks that need our internals
// (the null output backend, the converter's exact alignment).

import XCTest
import Foundation
import AVFoundation
#if APPKITWIN_AVFAUDIO
@testable import AVFAudio
#endif

final class AudioTests: XCTestCase, @unchecked Sendable {

    private func temporaryURL(_ name: String) -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("AudioTests-\(ProcessInfo.processInfo.processIdentifier)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(name)
    }

    /// A sine of `frequency` Hz, `amplitude`, in a standard-format buffer.
    private func sine(frequency: Double, amplitude: Float, rate: Double, channels: AVAudioChannelCount, frames: Int) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: channels)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
        buffer.frameLength = AVAudioFrameCount(frames)
        for c in 0..<Int(channels) {
            for i in 0..<frames { buffer.floatChannelData![c][i] = amplitude * Float(sin(2 * Double.pi * frequency * Double(i) / rate)) }
        }
        return buffer
    }

    private func constant(_ values: [Float], rate: Double, frames: Int) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: AVAudioChannelCount(values.count))!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
        buffer.frameLength = AVAudioFrameCount(frames)
        for (c, v) in values.enumerated() { buffer.floatChannelData![c].update(repeating: v, count: frames) }
        return buffer
    }

    /// Renders `frames` frames of an engine in manual rendering mode into one buffer.
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

    // MARK: Formats, buffers, time

    func testFormatSemantics() {
        let standard = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        XCTAssertEqual(standard.commonFormat, .pcmFormatFloat32)
        XCTAssertFalse(standard.isInterleaved)
        XCTAssertTrue(standard.isStandard)
        XCTAssertEqual(standard.channelCount, 2)
        XCTAssertEqual(standard.sampleRate, 48000)
        let d = standard.streamDescription.pointee
        XCTAssertEqual(d.mFormatID, kAudioFormatLinearPCM)
        XCTAssertEqual(d.mBytesPerFrame, 4)
        XCTAssertEqual(d.mBitsPerChannel, 32)
        XCTAssertEqual(d.mFramesPerPacket, 1)
        XCTAssertNotEqual(d.mFormatFlags & kAudioFormatFlagIsNonInterleaved, 0)
        XCTAssertEqual(standard.settings[AVLinearPCMIsNonInterleaved] as? Bool, true)
        XCTAssertEqual(standard.settings[AVLinearPCMBitDepthKey] as? Int, 32)
        XCTAssertEqual((standard.settings[AVSampleRateKey] as? NSNumber)?.doubleValue, 48000)

        let int16 = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 44100, channels: 2, interleaved: true)!
        XCTAssertEqual(int16.streamDescription.pointee.mBytesPerFrame, 4)
        XCTAssertEqual(int16.streamDescription.pointee.mFormatFlags, kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked)
        XCTAssertFalse(int16.isStandard)
        XCTAssertEqual(int16.settings[AVLinearPCMIsFloatKey] as? Bool, false)
        XCTAssertEqual(int16.settings[AVNumberOfChannelsKey] as? Int, 2)

        // Degenerate arguments give degenerate objects, not nil; more than two channels
        // without a layout gives nil.
        let zero = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 0)
        XCTAssertEqual(zero?.channelCount, 0)
        XCTAssertEqual(zero?.streamDescription.pointee.mBytesPerFrame, 4, "one lane's worth, as Apple reports")
        let other = AVAudioFormat(commonFormat: .otherFormat, sampleRate: 48000, channels: 2, interleaved: false)
        XCTAssertEqual(other?.commonFormat, .otherFormat)
        XCTAssertEqual(other?.channelCount, 0)
        XCTAssertEqual(other?.sampleRate, 0)
        XCTAssertNil(AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 48000, channels: 3, interleaved: true))
        let defaults = AVAudioFormat(settings: [AVSampleRateKey: 44100.0])
        XCTAssertEqual(defaults?.channelCount, 1)
        XCTAssertEqual(defaults?.commonFormat, .pcmFormatInt16)
        let same = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        XCTAssertEqual(standard, same)
        XCTAssertNotEqual(standard, int16)

        let fromSettings = AVAudioFormat(settings: [AVFormatIDKey: Int(kAudioFormatLinearPCM), AVSampleRateKey: 22050.0, AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false])!
        XCTAssertEqual(fromSettings.commonFormat, .pcmFormatInt16)
        XCTAssertEqual(fromSettings.sampleRate, 22050)
        XCTAssertTrue(fromSettings.isInterleaved)
        XCTAssertEqual(fromSettings.channelLayout, nil)

        let layout = AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_Stereo)!
        XCTAssertEqual(layout.channelCount, 2)
        let withLayout = AVAudioFormat(standardFormatWithSampleRate: 48000, channelLayout: layout)
        XCTAssertEqual(withLayout.channelCount, 2)
        XCTAssertEqual(withLayout.channelLayout?.layoutTag, kAudioChannelLayoutTag_Stereo)
    }

    func testPCMBufferSemantics() {
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 100)!
        XCTAssertEqual(buffer.frameCapacity, 100)
        XCTAssertEqual(buffer.frameLength, 0)
        XCTAssertEqual(buffer.stride, 1)
        buffer.frameLength = 10
        let list = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        XCTAssertEqual(list.count, 2)
        XCTAssertEqual(list[0].mDataByteSize, 40)
        XCTAssertEqual(list[0].mNumberChannels, 1)
        XCTAssertNil(buffer.int16ChannelData)
        buffer.floatChannelData![1][3] = 0.5
        XCTAssertEqual(list[1].mData!.assumingMemoryBound(to: Float.self)[3], 0.5)

        let interleaved = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 48000, channels: 2, interleaved: true)!
        let ib = AVAudioPCMBuffer(pcmFormat: interleaved, frameCapacity: 4)!
        XCTAssertEqual(ib.stride, 2)
        ib.frameLength = 4
        XCTAssertEqual(UnsafeMutableAudioBufferListPointer(ib.mutableAudioBufferList).count, 1)
        XCTAssertEqual(UnsafeMutableAudioBufferListPointer(ib.mutableAudioBufferList)[0].mDataByteSize, 16)
        ib.int16ChannelData![1][2 * ib.stride] = 1234
        XCTAssertEqual(ib.int16ChannelData![0][2 * ib.stride + 1], 1234, "channel pointers of an interleaved buffer are offsets into one lane")
        XCTAssertNil(ib.floatChannelData)

        let copy = buffer.copy() as! AVAudioPCMBuffer
        XCTAssertEqual(copy.frameLength, 10)
        XCTAssertEqual(copy.floatChannelData![1][3], 0.5)
    }

    func testAudioTime() {
        let t = AVAudioTime(sampleTime: 4800, atRate: 48000)
        XCTAssertTrue(t.isSampleTimeValid)
        XCTAssertFalse(t.isHostTimeValid)
        XCTAssertEqual(t.sampleRate, 48000)
        let anchor = AVAudioTime(hostTime: AVAudioTime.hostTime(forSeconds: 10), sampleTime: 0, atRate: 48000)
        let extrapolated = t.extrapolateTime(fromAnchor: anchor)!
        XCTAssertTrue(extrapolated.isHostTimeValid)
        XCTAssertEqual(AVAudioTime.seconds(forHostTime: extrapolated.hostTime), 10.1, accuracy: 0.001)
        XCTAssertEqual(extrapolated.sampleTime, 4800)
        let h = AVAudioTime(hostTime: AVAudioTime.hostTime(forSeconds: 10.5))
        XCTAssertNil(h.extrapolateTime(fromAnchor: anchor), "only sample-only times extrapolate")
        XCTAssertNil(t.extrapolateTime(fromAnchor: AVAudioTime(sampleTime: 1, atRate: 48000)), "the anchor needs both halves")
        let same = anchor.extrapolateTime(fromAnchor: anchor)
        XCTAssertEqual(same?.hostTime, anchor.hostTime)
        XCTAssertEqual(same?.sampleTime, anchor.sampleTime)
        XCTAssertEqual(AVAudioTime.seconds(forHostTime: AVAudioTime.hostTime(forSeconds: 2.5)), 2.5, accuracy: 1e-6)
    }

    // MARK: Files

    private func roundTrip(name: String, settings: [String: Any], tolerance: Float, file: StaticString = #filePath, line: UInt = #line) throws {
        let url = temporaryURL(name)
        try? FileManager.default.removeItem(at: url)
        let rate = (settings[AVSampleRateKey] as! NSNumber).doubleValue
        let channels = AVAudioChannelCount((settings[AVNumberOfChannelsKey] as! NSNumber).intValue)
        let source = sine(frequency: 440, amplitude: 0.8, rate: rate, channels: channels, frames: 2000)
        if channels == 2 { for i in 0..<2000 { source.floatChannelData![1][i] = Float(i % 50) / 100 - 0.25 } }
        do {
            let writer = try AVAudioFile(forWriting: url, settings: settings)
            XCTAssertEqual(writer.processingFormat.sampleRate, rate, file: file, line: line)
            XCTAssertEqual(writer.fileFormat.channelCount, channels, file: file, line: line)
            try writer.write(from: source)
            XCTAssertEqual(writer.length, 2000, file: file, line: line)
        }
        let reader = try AVAudioFile(forReading: url)
        XCTAssertEqual(reader.length, 2000, file: file, line: line)
        XCTAssertEqual(reader.fileFormat.sampleRate, rate, file: file, line: line)
        XCTAssertEqual(reader.fileFormat.channelCount, channels, file: file, line: line)
        XCTAssertEqual(reader.fileFormat.streamDescription.pointee.mBitsPerChannel, UInt32((settings[AVLinearPCMBitDepthKey] as! NSNumber).intValue), file: file, line: line)
        XCTAssertEqual(reader.processingFormat.commonFormat, .pcmFormatFloat32, file: file, line: line)
        XCTAssertFalse(reader.processingFormat.isInterleaved, file: file, line: line)
        let back = AVAudioPCMBuffer(pcmFormat: reader.processingFormat, frameCapacity: 4096)!
        try reader.read(into: back)
        XCTAssertEqual(back.frameLength, 2000, file: file, line: line)
        var maxError: Float = 0
        for c in 0..<Int(channels) { for i in 0..<2000 { maxError = max(maxError, abs(back.floatChannelData![c][i] - source.floatChannelData![c][i])) } }
        XCTAssertLessThanOrEqual(maxError, tolerance, "\(name): max error \(maxError)", file: file, line: line)
        // Seeking and partial reads.
        reader.framePosition = 1990
        let tail = AVAudioPCMBuffer(pcmFormat: reader.processingFormat, frameCapacity: 100)!
        try reader.read(into: tail)
        XCTAssertEqual(tail.frameLength, 10, file: file, line: line)
        XCTAssertEqual(tail.floatChannelData![0][0], back.floatChannelData![0][1990], file: file, line: line)
        reader.framePosition = 0
        try reader.read(into: tail, frameCount: 7)
        XCTAssertEqual(tail.frameLength, 7, file: file, line: line)
        XCTAssertEqual(reader.framePosition, 7, file: file, line: line)
    }

    func testWAVRoundTrips() throws {
        try roundTrip(name: "int16.wav", settings: [AVFormatIDKey: Int(kAudioFormatLinearPCM), AVSampleRateKey: 44100.0, AVNumberOfChannelsKey: 2, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false], tolerance: 1.0 / 32768)
        try roundTrip(name: "int24.wav", settings: [AVFormatIDKey: Int(kAudioFormatLinearPCM), AVSampleRateKey: 48000.0, AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 24, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false], tolerance: 1.0 / 8388608)
        try roundTrip(name: "float32.wav", settings: [AVFormatIDKey: Int(kAudioFormatLinearPCM), AVSampleRateKey: 48000.0, AVNumberOfChannelsKey: 2, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true, AVLinearPCMIsBigEndianKey: false], tolerance: 0)
    }

    func testAIFFRoundTrips() throws {
        try roundTrip(name: "int16.aiff", settings: [AVFormatIDKey: Int(kAudioFormatLinearPCM), AVSampleRateKey: 44100.0, AVNumberOfChannelsKey: 2, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: true], tolerance: 1.0 / 32768)
        try roundTrip(name: "int24.aif", settings: [AVFormatIDKey: Int(kAudioFormatLinearPCM), AVSampleRateKey: 22050.0, AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 24, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: true], tolerance: 1.0 / 8388608)
    }

    func testFileErrors() {
        let missing = temporaryURL("missing.wav")
        XCTAssertThrowsError(try AVAudioFile(forReading: missing))
        let garbage = temporaryURL("garbage.wav")
        try? Data(repeating: 0x41, count: 100).write(to: garbage)
        XCTAssertThrowsError(try AVAudioFile(forReading: garbage)) { error in
            XCTAssertEqual((error as NSError).domain, "com.apple.coreaudio.avfaudio")
        }
        XCTAssertThrowsError(try AVAudioFile(forReading: missing)) { error in
            XCTAssertEqual((error as NSError).code, 2003334207, "'wht?' for a file that does not exist")
        }
        let wrongFormat = temporaryURL("wrong.wav")
        XCTAssertThrowsError(try AVAudioFile(forWriting: wrongFormat, settings: [AVFormatIDKey: 0x61616320, AVSampleRateKey: 44100.0, AVNumberOfChannelsKey: 2]))
    }

    // MARK: Engine, offline

    func testOfflineMixTwoPlayersGainsAndPan() throws {
        let engine = AVAudioEngine()
        let out = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        let stereo = AVAudioPlayerNode(), mono = AVAudioPlayerNode()
        engine.attach(stereo); engine.attach(mono)
        engine.connect(stereo, to: engine.mainMixerNode, format: AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2))
        engine.connect(mono, to: engine.mainMixerNode, format: AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1))
        engine.connect(engine.mainMixerNode, to: engine.outputNode, format: out)
        try engine.enableManualRenderingMode(.offline, format: out, maximumFrameCount: 512)
        XCTAssertTrue(engine.isInManualRenderingMode)
        XCTAssertEqual(engine.manualRenderingFormat, out)
        stereo.volume = 0.5; stereo.pan = 0
        mono.volume = 1; mono.pan = 0.5
        engine.mainMixerNode.outputVolume = 0.8
        stereo.scheduleBuffer(constant([1.0, 0.5], rate: 48000, frames: 4800), completionHandler: nil)
        mono.scheduleBuffer(constant([1.0], rate: 48000, frames: 4800), completionHandler: nil)
        try engine.start()
        XCTAssertTrue(engine.isRunning)
        stereo.play(); mono.play()
        let mix = try renderAll(engine, frames: 2048)
        XCTAssertEqual(mix.frameLength, 2048)
        // Stereo pan is a balance (left * 1, right * 1 at pan 0); mono at pan 0.5 is
        // cos/sin(3pi/8) into left/right; the mixer's outputVolume scales the sum.
        let a = (0.5 + 1) * Double.pi / 4
        let expectedL = Float((1.0 * 0.5 + cos(a)) * 0.8), expectedR = Float((0.5 * 0.5 + sin(a)) * 0.8)
        for i in 0..<2048 {
            XCTAssertEqual(mix.floatChannelData![0][i], expectedL, accuracy: 1e-5, "left frame \(i)")
            XCTAssertEqual(mix.floatChannelData![1][i], expectedR, accuracy: 1e-5, "right frame \(i)")
            if abs(mix.floatChannelData![0][i] - expectedL) > 1e-5 { break }
        }
        XCTAssertEqual(engine.manualRenderingSampleTime, 2048)
        engine.stop()
        XCTAssertFalse(engine.isRunning)
    }

    func testOfflineRateConversion() throws {
        let engine = AVAudioEngine()
        let out = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1))
        engine.connect(engine.mainMixerNode, to: engine.outputNode, format: out)
        try engine.enableManualRenderingMode(.offline, format: out, maximumFrameCount: 512)
        player.scheduleBuffer(sine(frequency: 440, amplitude: 0.5, rate: 44100, channels: 1, frames: 44100), completionHandler: nil)
        try engine.start()
        player.play()
        let mix = try renderAll(engine, frames: 9600)
        // A 440 Hz tone at 44.1 kHz comes out as a 440 Hz tone at 48 kHz: check the level
        // (the sum of squares of a sine is amplitude^2 / 2) after the converter's lead-in.
        var energy = 0.0
        for i in 2000..<9600 { energy += Double(mix.floatChannelData![0][i] * mix.floatChannelData![0][i]) }
        let rms = (energy / 7600).squareRoot()
        XCTAssertEqual(rms, 0.5 / 2.0.squareRoot(), accuracy: 0.01, "rms after rate conversion")
        var crossings = 0
        for i in 2001..<9600 where mix.floatChannelData![0][i - 1] < 0 && mix.floatChannelData![0][i] >= 0 { crossings += 1 }
        XCTAssertEqual(Double(crossings), 440 * 7600 / 48000, accuracy: 2, "the tone stays at 440 Hz")
        #if APPKITWIN_AVFAUDIO
        // Our converter has no delay: compare sample for sample with the ideal tone.
        var maxError: Float = 0
        for i in 100..<9600 {
            let expected = 0.5 * Float(sin(2 * Double.pi * 440 * Double(i) / 48000))
            maxError = max(maxError, abs(mix.floatChannelData![0][i] - expected))
        }
        XCTAssertLessThan(maxError, 2e-3, "sample-for-sample error of the 44.1k -> 48k conversion")
        #endif
        engine.stop()
    }

    func testPlayerNodeSchedulingAndCompletions() throws {
        let engine = AVAudioEngine()
        let out = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1)!
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: out)
        engine.connect(engine.mainMixerNode, to: engine.outputNode, format: out)
        try engine.enableManualRenderingMode(.offline, format: out, maximumFrameCount: 256)
        let first = expectation(description: "first consumed"), second = expectation(description: "second consumed")
        let third = expectation(description: "third rendered"), fourth = expectation(description: "fourth played back")
        fourth.isInverted = true     // never fires in manual rendering mode (no playback clock), as Apple's
        var order: [String] = []
        let lock = NSLock()
        func note(_ s: String) { lock.lock(); order.append(s); lock.unlock() }
        // Every handler is called; the order between handlers is not promised (Apple
        // delivers them from more than one place, even for one callback type).
        player.scheduleBuffer(constant([0.25], rate: 48000, frames: 300), completionCallbackType: .dataConsumed) { type in
            XCTAssertEqual(type, .dataConsumed); note("first"); first.fulfill()
        }
        player.scheduleBuffer(constant([0.5], rate: 48000, frames: 300), completionCallbackType: .dataConsumed) { type in
            XCTAssertEqual(type, .dataConsumed); note("second"); second.fulfill()
        }
        player.scheduleBuffer(constant([1.0], rate: 48000, frames: 200), completionCallbackType: .dataRendered) { type in
            XCTAssertEqual(type, .dataRendered); third.fulfill()
        }
        player.scheduleBuffer(constant([0.75], rate: 48000, frames: 100), completionCallbackType: .dataPlayedBack) { type in
            XCTAssertEqual(type, .dataPlayedBack); fourth.fulfill()
        }
        try engine.start()
        player.play()
        XCTAssertTrue(player.isPlaying)
        let mix = try renderAll(engine, frames: 1024)
        XCTAssertEqual(mix.floatChannelData![0][0], 0.25)
        XCTAssertEqual(mix.floatChannelData![0][299], 0.25)
        XCTAssertEqual(mix.floatChannelData![0][300], 0.5)
        XCTAssertEqual(mix.floatChannelData![0][599], 0.5)
        XCTAssertEqual(mix.floatChannelData![0][600], 1.0)
        XCTAssertEqual(mix.floatChannelData![0][799], 1.0)
        XCTAssertEqual(mix.floatChannelData![0][800], 0.75)
        XCTAssertEqual(mix.floatChannelData![0][899], 0.75)
        XCTAssertEqual(mix.floatChannelData![0][900], 0, "silence after the last buffer")
        XCTAssertEqual(mix.floatChannelData![0][1023], 0)
        _ = try renderAll(engine, frames: 256)
        wait(for: [first, second, third], timeout: 5)
        wait(for: [fourth], timeout: 0.3)
        lock.lock(); XCTAssertEqual(Set(order), ["first", "second"]); lock.unlock()

        // A looping buffer plays until stopped, and stop() calls its handler. The player is
        // already playing, and Apple's engine applies a schedule asynchronously, so render
        // until the loop's audio shows up (bounded) before checking that it keeps going.
        let stopped = expectation(description: "loop stopped")
        player.scheduleBuffer(constant([0.75], rate: 48000, frames: 100), at: nil, options: .loops) { stopped.fulfill() }
        var started = false
        for _ in 0..<200 {
            let chunk = try renderAll(engine, frames: 256)
            if chunk.floatChannelData![0][255] == 0.75 { started = true; break }
        }
        XCTAssertTrue(started, "the looping buffer was never heard")
        let looped = try renderAll(engine, frames: 512)
        XCTAssertEqual(looped.floatChannelData![0][0], 0.75)
        XCTAssertEqual(looped.floatChannelData![0][511], 0.75, "looping keeps going past the buffer length")
        player.stop()
        XCTAssertFalse(player.isPlaying)
        wait(for: [stopped], timeout: 5)
        let silent = try renderAll(engine, frames: 256)
        XCTAssertEqual(silent.floatChannelData![0][0], 0)

        // Scheduling at a player time: silence until the time comes.
        player.scheduleBuffer(constant([0.1], rate: 48000, frames: 100), at: AVAudioTime(sampleTime: 200, atRate: 48000), options: [], completionHandler: nil)
        player.play()
        let timed = try renderAll(engine, frames: 512)
        XCTAssertEqual(timed.floatChannelData![0][100], 0)
        XCTAssertEqual(timed.floatChannelData![0][199], 0)
        XCTAssertEqual(timed.floatChannelData![0][200], 0.1)
        XCTAssertEqual(timed.floatChannelData![0][299], 0.1)
        XCTAssertEqual(timed.floatChannelData![0][300], 0)
        player.pause()
        XCTAssertFalse(player.isPlaying)
        engine.stop()
    }

    func testScheduleFileAndSegment() throws {
        let url = temporaryURL("segment.wav")
        try? FileManager.default.removeItem(at: url)
        do {
            // The file is finished (its header patched) when the writer goes away.
            let writer = try AVAudioFile(forWriting: url, settings: [AVFormatIDKey: Int(kAudioFormatLinearPCM), AVSampleRateKey: 48000.0, AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false])
            let ramp = AVAudioPCMBuffer(pcmFormat: writer.processingFormat, frameCapacity: 1000)!
            ramp.frameLength = 1000
            for i in 0..<1000 { ramp.floatChannelData![0][i] = Float(i) / 2000 }
            try writer.write(from: ramp)
        }

        let engine = AVAudioEngine()
        let out = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1)!
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: out)
        engine.connect(engine.mainMixerNode, to: engine.outputNode, format: out)
        try engine.enableManualRenderingMode(.offline, format: out, maximumFrameCount: 512)
        let file = try AVAudioFile(forReading: url)
        let done = expectation(description: "segment done")
        player.scheduleSegment(file, startingFrame: 500, frameCount: 100, at: nil) { done.fulfill() }
        player.scheduleFile(file, at: nil, completionHandler: nil)
        try engine.start()
        player.play()
        let mix = try renderAll(engine, frames: 1200)
        XCTAssertEqual(mix.floatChannelData![0][0], 500.0 / 2000, accuracy: 1.0 / 32768)
        XCTAssertEqual(mix.floatChannelData![0][99], 599.0 / 2000, accuracy: 1.0 / 32768)
        XCTAssertEqual(mix.floatChannelData![0][100], 0, accuracy: 1.0 / 32768, "the whole file follows the segment")
        XCTAssertEqual(mix.floatChannelData![0][100 + 999], 999.0 / 2000, accuracy: 1.0 / 32768)
        XCTAssertEqual(mix.floatChannelData![0][1100], 0)
        wait(for: [done], timeout: 5)
        engine.stop()
    }

    /// Taps deliver only while a device renders (not in manual rendering mode, as Apple's):
    /// this runs the engine on the null output backend, so only in the port.
    func testTapReceivesRenderedFrames() throws {
        #if !APPKITWIN_AVFAUDIO
        throw XCTSkip("taps do not deliver in manual rendering mode; a device-backed engine is needed")
        #else
        let previous = PlatformAudio.backend
        PlatformAudio.backend = NullAudioBackend()
        defer { PlatformAudio.backend = previous }
        let engine = AVAudioEngine()
        let out = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: out)
        engine.connect(engine.mainMixerNode, to: engine.outputNode, format: out)
        let lock = NSLock()
        var received: [(Int64, Int, Float)] = []
        let got = expectation(description: "tap buffers")
        got.assertForOverFulfill = false
        engine.mainMixerNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { buffer, when in
            lock.lock()
            received.append((when.sampleTime, Int(buffer.frameLength), buffer.floatChannelData![0][0]))
            lock.unlock()
            got.fulfill()
        }
        player.scheduleBuffer(constant([0.3, 0.3], rate: 48000, frames: 48000), completionHandler: nil)
        try engine.start()
        player.play()
        wait(for: [got], timeout: 5)
        let deadline = Date(timeIntervalSinceNow: 2)
        while Date() < deadline { lock.lock(); let n = received.count; lock.unlock(); if n >= 2 { break }; Thread.sleep(forTimeInterval: 0.02) }
        lock.lock(); let r = received; lock.unlock()
        XCTAssertGreaterThanOrEqual(r.count, 2)
        XCTAssertEqual(r[0].2, 0.3, accuracy: 1e-6)
        XCTAssertGreaterThan(r[0].1, 0)
        XCTAssertGreaterThan(r[1].0, r[0].0, "tap times advance")
        engine.mainMixerNode.removeTap(onBus: 0)
        engine.stop()
        #endif
    }

    func testEQBandAttenuates() throws {
        let engine = AVAudioEngine()
        let out = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1)!
        let player = AVAudioPlayerNode()
        let eq = AVAudioUnitEQ(numberOfBands: 1)
        engine.attach(player); engine.attach(eq)
        engine.connect(player, to: eq, format: out)
        engine.connect(eq, to: engine.mainMixerNode, format: out)
        engine.connect(engine.mainMixerNode, to: engine.outputNode, format: out)
        try engine.enableManualRenderingMode(.offline, format: out, maximumFrameCount: 512)
        XCTAssertEqual(eq.bands.count, 1)
        eq.bands[0].filterType = .lowPass
        eq.bands[0].frequency = 500
        eq.bands[0].bandwidth = 0.5
        eq.bands[0].bypass = false
        player.scheduleBuffer(sine(frequency: 8000, amplitude: 0.5, rate: 48000, channels: 1, frames: 48000), completionHandler: nil)
        try engine.start()
        player.play()
        let mix = try renderAll(engine, frames: 9600)
        var energy = 0.0
        for i in 4800..<9600 { energy += Double(mix.floatChannelData![0][i] * mix.floatChannelData![0][i]) }
        let rms = (energy / 4800).squareRoot()
        XCTAssertLessThan(rms, 0.05, "an 8 kHz tone through a 500 Hz low-pass is attenuated (rms \(rms))")
        engine.stop()
    }

    // MARK: Real-time path and the player class

    #if APPKITWIN_AVFAUDIO
    /// Polls `condition` every few milliseconds for up to two seconds.
    private func waitUntil(_ condition: () -> Bool) {
        let deadline = Date(timeIntervalSinceNow: 2)
        while !condition() && Date() < deadline { Thread.sleep(forTimeInterval: 0.005) }
    }

    /// Installs the null output backend for the test and restores the previous one.
    private func withNullBackend(_ body: () throws -> Void) rethrows {
        let previous = PlatformAudio.backend
        PlatformAudio.backend = NullAudioBackend()
        defer { PlatformAudio.backend = previous }
        try body()
    }

    func testEngineRendersThroughTheNullStream() throws {
        try withNullBackend {
            let engine = AVAudioEngine()
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: nil)
            XCTAssertEqual(engine.outputNode.outputFormat(forBus: 0).sampleRate, 48000)
            player.scheduleBuffer(constant([0.5, 0.5], rate: 48000, frames: 48000), completionHandler: nil)
            try engine.start()
            XCTAssertTrue(engine.isRunning)
            XCTAssertNotNil(engine._outputDescription)
            player.play()
            Thread.sleep(forTimeInterval: 0.25)
            let t = engine.outputNode.lastRenderTime
            XCTAssertNotNil(t)
            XCTAssertGreaterThan(t!.sampleTime, 4800, "the null stream renders in real time")
            XCTAssertGreaterThan(player.outputPresentationLatency, 0)
            XCTAssertNotNil(player.playerTime(forNodeTime: t!))
            engine.pause()
            XCTAssertFalse(engine.isRunning)
            let paused = engine.outputNode.lastRenderTime!.sampleTime
            Thread.sleep(forTimeInterval: 0.1)
            XCTAssertEqual(engine.outputNode.lastRenderTime!.sampleTime, paused)
            try engine.start()
            Thread.sleep(forTimeInterval: 0.1)
            XCTAssertGreaterThan(engine.outputNode.lastRenderTime!.sampleTime, paused)
            engine.stop()
        }
    }

    final class FinishDelegate: NSObject, AVAudioPlayerDelegate {
        let finished = XCTestExpectation(description: "finished")
        var count = 0
        func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
            count += 1
            XCTAssertTrue(flag)
            finished.fulfill()
        }
    }

    func testAVAudioPlayerStateMachine() throws {
        let url = temporaryURL("player.wav")
        try? FileManager.default.removeItem(at: url)
        do {
            let writer = try AVAudioFile(forWriting: url, settings: [AVFormatIDKey: Int(kAudioFormatLinearPCM), AVSampleRateKey: 48000.0, AVNumberOfChannelsKey: 2, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false])
            try writer.write(from: sine(frequency: 440, amplitude: 0.5, rate: 48000, channels: 2, frames: 9600))   // 0.2 s
        }
        try withNullBackend {
            let player = try AVAudioPlayer(contentsOf: url)
            XCTAssertEqual(player.duration, 0.2, accuracy: 1e-6)
            XCTAssertEqual(player.numberOfChannels, 2)
            XCTAssertEqual(player.url, url)
            XCTAssertNil(player.data)
            XCTAssertFalse(player.isPlaying)
            XCTAssertEqual(player.settings[AVLinearPCMBitDepthKey] as? Int, 16)
            let delegate = FinishDelegate()
            player.delegate = delegate
            player.volume = 0.7
            XCTAssertEqual(player.volume, 0.7)
            player.numberOfLoops = 1
            XCTAssertTrue(player.prepareToPlay())
            XCTAssertTrue(player.play())
            XCTAssertTrue(player.isPlaying)
            // The null stream renders in real time: wait for the position to advance rather
            // than sleeping a fixed time (CI runners are slow and their clocks coarse).
            waitUntil { player.currentTime > 0.02 }
            XCTAssertGreaterThan(player.currentTime, 0.02)
            XCTAssertLessThan(player.currentTime, 0.2)
            player.pause()
            XCTAssertFalse(player.isPlaying)
            let paused = player.currentTime
            Thread.sleep(forTimeInterval: 0.05)
            XCTAssertEqual(player.currentTime, paused, accuracy: 1e-6, "pause keeps the position")
            XCTAssertTrue(player.play())
            wait(for: [delegate.finished], timeout: 5)
            XCTAssertEqual(delegate.count, 1, "numberOfLoops = 1 plays twice and finishes once")
            XCTAssertFalse(player.isPlaying)
            XCTAssertEqual(player.currentTime, 0, accuracy: 1e-6)
            // stop() keeps currentTime; play() resumes there.
            player.numberOfLoops = 0
            XCTAssertTrue(player.play())
            waitUntil { player.currentTime > 0.02 }
            player.stop()
            XCTAssertFalse(player.isPlaying)
            XCTAssertGreaterThan(player.currentTime, 0.01)
            player.currentTime = 0.15
            XCTAssertEqual(player.currentTime, 0.15, accuracy: 1e-6)
            let again = FinishDelegate()
            player.delegate = again
            XCTAssertTrue(player.play())
            wait(for: [again.finished], timeout: 5)
            // From Data.
            let data = try Data(contentsOf: url)
            let fromData = try AVAudioPlayer(data: data)
            XCTAssertEqual(fromData.duration, 0.2, accuracy: 1e-6)
            XCTAssertNotNil(fromData.data)
            XCTAssertNil(fromData.url)
            fromData.isMeteringEnabled = true
            XCTAssertTrue(fromData.play())
            Thread.sleep(forTimeInterval: 0.1)
            fromData.updateMeters()
            XCTAssertGreaterThan(fromData.averagePower(forChannel: 0), -20, "a -6 dBFS sine meters above -20 dB")
            XCTAssertLessThan(fromData.peakPower(forChannel: 0), 0)
            fromData.stop()
        }
    }
    #endif

    /// The platform backend: enumeration always answers; a stream opens and calls back
    /// when the machine has an output device, otherwise the test is skipped.
    func testPlatformOutputStream() throws {
        #if APPKITWIN_AVFAUDIO
        let backend = PlatformAudio.backend
        let devices = try backend.outputDevices()
        print("audio backend \(backend.name): \(devices.map { "\($0.name) \(Int($0.sampleRate)) Hz \($0.channelCount) ch\($0.isDefault ? " (default)" : "")" })")
        let calls = _AtomicInt64(0)
        let stream: any PlatformAudioOutputStream
        do {
            stream = try backend.openOutputStream(device: nil, sampleRate: nil, channelCount: nil) { out, frames in
                out.update(repeating: 0, count: frames * 2)
                calls.add(Int64(frames))
            }
        } catch {
            throw XCTSkip("no output stream on this machine: \(error)")
        }
        XCTAssertGreaterThan(stream.sampleRate, 0)
        XCTAssertGreaterThan(stream.channelCount, 0)
        XCTAssertGreaterThan(stream.bufferFrameCount, 0)
        print("stream: \(stream.deviceName) \(stream.sampleRate) Hz \(stream.channelCount) ch, period \(stream.bufferFrameCount) frames, latency \(stream.latency * 1000) ms")
        try stream.start()
        Thread.sleep(forTimeInterval: 0.3)
        stream.stop()
        let rendered = calls.value
        XCTAssertGreaterThan(rendered, Int64(stream.sampleRate * 0.1), "the stream pulled at least 100 ms of audio in 300 ms")
        Thread.sleep(forTimeInterval: 0.05)
        XCTAssertEqual(calls.value, rendered, "no callbacks after stop()")
        XCTAssertGreaterThanOrEqual(stream.latency, 0)
        stream.close()
        #else
        throw XCTSkip("the platform audio seam exists only in the port")
        #endif
    }
}
