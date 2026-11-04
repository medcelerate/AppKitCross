// AudioPlayer: an AVAudioEngine with a player node for a WAV file and a second one for a
// generated sine, a level meter fed by a tap on the main mixer, play/pause/loop, and an
// offline render switch for machines without a sound device. Same source on every
// platform: on macOS it runs on Apple's AVFoundation.

import AppKit
import AVFoundation
import Foundation

/// Two seconds of a sine, in the format the player node renders.
func makeSine(frequency: Double, format: AVAudioFormat, seconds: Double) -> AVAudioPCMBuffer {
    let frames = Int(format.sampleRate * seconds)
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
    buffer.frameLength = AVAudioFrameCount(frames)
    for c in 0..<Int(format.channelCount) {
        for i in 0..<frames {
            // A short fade at both ends keeps the loop point click-free.
            let fade = min(1, min(Double(i), Double(frames - 1 - i)) / 480)
            buffer.floatChannelData![c][i] = Float(0.3 * fade * sin(2 * Double.pi * frequency * Double(i) / format.sampleRate))
        }
    }
    return buffer
}

/// A three-second demo melody (so there is something to play before a file is opened).
func makeDemo(format: AVAudioFormat) -> AVAudioPCMBuffer {
    let notes: [Double] = [261.63, 329.63, 392.00, 523.25, 392.00, 329.63]
    let frames = Int(format.sampleRate * 3)
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
    buffer.frameLength = AVAudioFrameCount(frames)
    let perNote = frames / notes.count
    for i in 0..<frames {
        let n = min(notes.count - 1, i / perNote), t = Double(i % perNote) / format.sampleRate
        let envelope = exp(-t * 4) * min(1, Double(i % perNote) / 200)
        let v = Float(0.4 * envelope * (sin(2 * Double.pi * notes[n] * t) + 0.3 * sin(2 * Double.pi * notes[n] * 2 * t)))
        for c in 0..<Int(format.channelCount) { buffer.floatChannelData![c][i] = v * (c == 0 ? 1 : 0.8) }
    }
    return buffer
}

/// The engine graph: file player and sine player into the main mixer, a tap for the meter.
@MainActor
final class AudioModel {
    let engine = AVAudioEngine()
    let filePlayer = AVAudioPlayerNode()
    let sinePlayer = AVAudioPlayerNode()
    private(set) var fileBuffer: AVAudioPCMBuffer?
    private(set) var fileName = "demo melody (generated)"
    var loops = false
    private(set) var isPlayingFile = false
    private(set) var sineOn = false
    private var pausedAt: AVAudioFramePosition = 0
    private var playGeneration = 0
    /// Peak level per channel (0...1) from the tap, updated off the main thread.
    var onLevels: (([Float]) -> Void)?
    var onFinished: (() -> Void)?
    private let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!

    init() {
        engine.attach(filePlayer)
        engine.attach(sinePlayer)
        engine.connect(filePlayer, to: engine.mainMixerNode, format: format)
        engine.connect(sinePlayer, to: engine.mainMixerNode, format: format)
        fileBuffer = makeDemo(format: format)
        installTap()
    }

    private func installTap() {
        engine.mainMixerNode.removeTap(onBus: 0)
        // Tap blocks run on the engine's thread: the closure is @Sendable, so it is not
        // tied to the main actor, and the result hops over before touching the model.
        engine.mainMixerNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { @Sendable [weak self] buffer, _ in
            guard let self, let data = buffer.floatChannelData else { return }
            let n = Int(buffer.frameLength)
            var levels: [Float] = []
            for c in 0..<Int(buffer.format.channelCount) {
                var peak: Float = 0
                for i in 0..<n { peak = max(peak, abs(data[c][i])) }
                levels.append(peak)
            }
            DispatchQueue.main.async { MainActor.assumeIsolated { self.onLevels?(levels) } }
        }
    }

    /// Starts the engine on the device; the description or the error text for the status line.
    @discardableResult func startEngine() -> String {
        if engine.isRunning { return statusLine }
        do {
            try engine.start()
            return statusLine
        } catch {
            return "no audio output: \(error.localizedDescription)"
        }
    }

    var statusLine: String {
        let out = engine.outputNode
        let f = out.outputFormat(forBus: 0)
        var s = "output \(Int(f.sampleRate)) Hz, \(f.channelCount) ch, latency \(String(format: "%.1f", out.presentationLatency * 1000)) ms"
        #if !canImport(Darwin)
        if let d = engine._outputDescription { s = d }
        #endif
        return s
    }

    func open(url: URL) throws {
        let file = try AVAudioFile(forReading: url)
        guard let raw = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else { return }
        try file.read(into: raw)
        stopFile()
        // Match the player's format (48 kHz stereo) so loops and seeks are frame-exact.
        let frames = Int(Double(raw.frameLength) * format.sampleRate / file.processingFormat.sampleRate)
        let converted = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(max(1, frames)))!
        converted.frameLength = AVAudioFrameCount(frames)
        let ratio = file.processingFormat.sampleRate / format.sampleRate
        let inChannels = Int(file.processingFormat.channelCount)
        for i in 0..<frames {
            let x = Double(i) * ratio
            let j = min(Int(x), Int(raw.frameLength) - 1), k = min(j + 1, Int(raw.frameLength) - 1)
            let t = Float(x - Double(j))
            for c in 0..<2 {
                let src = raw.floatChannelData![min(c, inChannels - 1)]
                converted.floatChannelData![c][i] = src[j] + (src[k] - src[j]) * t
            }
        }
        fileBuffer = converted
        fileName = url.lastPathComponent
        pausedAt = 0
    }

    var duration: Double { Double(fileBuffer?.frameLength ?? 0) / format.sampleRate }

    /// The playback position in seconds.
    var position: Double {
        guard let buffer = fileBuffer else { return 0 }
        let total = Double(buffer.frameLength)
        guard isPlayingFile, let last = filePlayer.lastRenderTime, let pt = filePlayer.playerTime(forNodeTime: last) else {
            return Double(pausedAt) / format.sampleRate
        }
        let frame = Double(pausedAt) + Double(pt.sampleTime)
        return (loops ? frame.truncatingRemainder(dividingBy: total) : min(frame, total)) / format.sampleRate
    }

    func playFile() {
        guard let buffer = fileBuffer else { return }
        startEngine()
        guard engine.isRunning else { return }
        playGeneration += 1
        let generation = playGeneration
        filePlayer.stop()
        let total = Int(buffer.frameLength)
        let start = Int(min(pausedAt, AVAudioFramePosition(total)))
        if start < total {
            let rest = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(total - start))!
            rest.frameLength = AVAudioFrameCount(total - start)
            for c in 0..<2 { rest.floatChannelData![c].update(from: buffer.floatChannelData![c] + start, count: total - start) }
            filePlayer.scheduleBuffer(rest, at: nil, options: [], completionCallbackType: .dataPlayedBack) { @Sendable [weak self] _ in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { guard let self, generation == self.playGeneration, !self.loops else { return }; self.fileFinished() }
                }
            }
        }
        if loops { filePlayer.scheduleBuffer(buffer, at: nil, options: .loops, completionHandler: nil) }
        filePlayer.play()
        isPlayingFile = true
    }

    private func fileFinished() {
        isPlayingFile = false
        pausedAt = 0
        onFinished?()
    }

    func pauseFile() {
        guard isPlayingFile else { return }
        pausedAt = AVAudioFramePosition(position * format.sampleRate)
        playGeneration += 1
        filePlayer.stop()
        isPlayingFile = false
    }

    func stopFile() {
        playGeneration += 1
        filePlayer.stop()
        isPlayingFile = false
        pausedAt = 0
    }

    func toggleSine() {
        if sineOn {
            sinePlayer.stop()
            sineOn = false
            return
        }
        startEngine()
        guard engine.isRunning else { return }
        sinePlayer.scheduleBuffer(makeSine(frequency: 440, format: format, seconds: 2), at: nil, options: .loops, completionHandler: nil)
        sinePlayer.play()
        sineOn = true
    }

    /// Renders `seconds` of the file player (from the start) plus the sine into a WAV.
    func render(to url: URL, seconds: Double) throws -> Int {
        engine.stop()
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096)
        try engine.start()
        if let buffer = fileBuffer { filePlayer.scheduleBuffer(buffer, at: nil, options: .loops, completionHandler: nil) }
        sinePlayer.scheduleBuffer(makeSine(frequency: 440, format: format, seconds: 2), at: nil, options: .loops, completionHandler: nil)
        filePlayer.play(); sinePlayer.play()
        try? FileManager.default.removeItem(at: url)
        let settings: [String: Any] = [AVFormatIDKey: Int(kAudioFormatLinearPCM), AVSampleRateKey: format.sampleRate, AVNumberOfChannelsKey: 2, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false]
        let file = try AVAudioFile(forWriting: url, settings: settings)
        let chunk = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096)!
        var rendered = 0
        let total = Int(seconds * format.sampleRate)
        while rendered < total {
            let n = AVAudioFrameCount(min(4096, total - rendered))
            let status = try engine.renderOffline(n, to: chunk)
            guard status == .success, chunk.frameLength > 0 else { break }
            try file.write(from: chunk)
            rendered += Int(chunk.frameLength)
        }
        filePlayer.stop(); sinePlayer.stop()
        engine.stop()
        engine.disableManualRenderingMode()
        return rendered
    }
}

/// Two horizontal bars following the mixer's peak level, with a slow-falling peak mark.
final class LevelMeterView: NSView {
    var levels: [Float] = [0, 0] { didSet { for i in 0..<min(peaks.count, levels.count) { peaks[i] = max(peaks[i] * 0.97, levels[i]) }; needsDisplay = true } }
    private var peaks: [Float] = [0, 0]
    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlBackgroundColor.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4).fill()
        let n = max(1, levels.count)
        let h = (bounds.height - 4) / CGFloat(n) - 2
        for (i, level) in levels.enumerated() {
            let y = bounds.height - 2 - CGFloat(i + 1) * (h + 2) + 2
            let track = NSRect(x: 2, y: y, width: bounds.width - 4, height: h)
            NSColor.separatorColor.setFill(); NSBezierPath(rect: track).fill()
            let db = level > 0 ? 20 * log10(level) : -60
            let fraction = CGFloat(max(0, min(1, (db + 60) / 60)))
            let fill = NSRect(x: 2, y: y, width: (bounds.width - 4) * fraction, height: h)
            (db > -3 ? NSColor.systemRed : (db > -12 ? NSColor.systemYellow : NSColor.systemGreen)).setFill()
            NSBezierPath(rect: fill).fill()
            let peakDb = peaks[i] > 0 ? 20 * log10(peaks[i]) : -60
            let px = 2 + (bounds.width - 4) * CGFloat(max(0, min(1, (peakDb + 60) / 60)))
            NSColor.labelColor.setFill(); NSBezierPath(rect: NSRect(x: px - 1, y: y, width: 2, height: h)).fill()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSSelectorHandling {
    var window: NSWindow!
    let model = AudioModel()
    var playButton: NSButton!, sineButton: NSButton!, loopCheckbox: NSButton!
    var meter: LevelMeterView!
    var status: NSTextField!, fileLabel: NSTextField!, positionLabel: NSTextField!
    var timer: Timer?

    func performSelectorAction(_ action: Selector, with sender: Any?) -> Bool {
        switch action {
        case Selector(("openFile:")):
            let panel = NSOpenPanel()
            panel.title = "Open WAV"
            panel.allowedFileTypes = ["wav", "aif", "aiff", "aifc"]
            if panel.runModal() == .OK, let url = panel.url { open(url) }
            return true
        case Selector(("playPause:")):
            if model.isPlayingFile { model.pauseFile() } else { model.playFile() }
            update()
            return true
        case Selector(("stop:")): model.stopFile(); update(); return true
        case Selector(("toggleSine:")): model.toggleSine(); update(); return true
        case Selector(("toggleLoop:")):
            model.loops = loopCheckbox.state == .on
            if model.isPlayingFile { model.pauseFile(); model.playFile() }
            return true
        case Selector(("volumeChanged:")):
            model.engine.mainMixerNode.outputVolume = Float((sender as? NSSlider)?.doubleValue ?? 1)
            return true
        case Selector(("quit:")): NSApp.terminate(sender); return true
        default: return false
        }
    }

    func open(_ url: URL) {
        do {
            try model.open(url: url)
            fileLabel.stringValue = "\(model.fileName) (\(String(format: "%.1f", model.duration)) s)"
        } catch {
            fileLabel.stringValue = "cannot open \(url.lastPathComponent): \(error.localizedDescription)"
        }
        update()
    }

    func update() {
        playButton.title = model.isPlayingFile ? "Pause" : "Play"
        sineButton.title = model.sineOn ? "Stop Sine" : "Sine 440 Hz"
        status.stringValue = model.engine.isRunning ? model.statusLine : "engine stopped"
        positionLabel.stringValue = String(format: "%.1f / %.1f s", model.position, model.duration)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let main = NSMenu(title: "Main")
        let fileItem = NSMenuItem(title: "File", action: nil, keyEquivalent: "")
        let file = NSMenu(title: "File")
        file.addItem(withTitle: "Open WAV\u{2026}", action: Selector(("openFile:")), keyEquivalent: "o")
        file.addItem(NSMenuItem.separator())
        file.addItem(withTitle: "Quit", action: Selector(("quit:")), keyEquivalent: "q")
        fileItem.submenu = file
        main.addItem(fileItem)
        let playItem = NSMenuItem(title: "Playback", action: nil, keyEquivalent: "")
        let playback = NSMenu(title: "Playback")
        playback.addItem(withTitle: "Play / Pause", action: Selector(("playPause:")), keyEquivalent: " ")
        playback.addItem(withTitle: "Stop", action: Selector(("stop:")), keyEquivalent: ".")
        playback.addItem(withTitle: "Sine 440 Hz", action: Selector(("toggleSine:")), keyEquivalent: "s")
        playItem.submenu = playback
        main.addItem(playItem)
        NSApp.mainMenu = main

        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 220),
                          styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "AudioPlayer"
        let content = window.contentView!

        fileLabel = NSTextField(labelWithString: "\(model.fileName) (\(String(format: "%.1f", model.duration)) s)")
        fileLabel.frame = NSRect(x: 16, y: 184, width: 488, height: 20)
        content.addSubview(fileLabel)

        meter = LevelMeterView(frame: NSRect(x: 16, y: 120, width: 488, height: 48))
        content.addSubview(meter)
        model.onLevels = { [weak self] levels in self?.meter.levels = levels }
        model.onFinished = { [weak self] in self?.update() }

        positionLabel = NSTextField(labelWithString: "0.0 / 0.0 s")
        positionLabel.textColor = .secondaryLabelColor
        positionLabel.frame = NSRect(x: 16, y: 96, width: 200, height: 18)
        content.addSubview(positionLabel)

        let openButton = NSButton(title: "Open WAV\u{2026}", target: self, action: Selector(("openFile:")))
        playButton = NSButton(title: "Play", target: self, action: Selector(("playPause:")))
        let stop = NSButton(title: "Stop", target: self, action: Selector(("stop:")))
        loopCheckbox = NSButton(checkboxWithTitle: "Loop", target: self, action: Selector(("toggleLoop:")))
        sineButton = NSButton(title: "Sine 440 Hz", target: self, action: Selector(("toggleSine:")))
        let volume = NSSlider(value: 1, minValue: 0, maxValue: 1, target: self, action: Selector(("volumeChanged:")))
        volume.widthAnchor.constraint(equalToConstant: 90).isActive = true
        let bar = NSStackView(views: [openButton, playButton, stop, loopCheckbox, sineButton, volume])
        bar.orientation = .horizontal
        bar.spacing = 8
        bar.frame = NSRect(x: 16, y: 52, width: 488, height: 30)
        content.addSubview(bar)

        status = NSTextField(labelWithString: "")
        status.textColor = .secondaryLabelColor
        status.font = NSFont.systemFont(ofSize: 11)
        status.frame = NSRect(x: 16, y: 14, width: 488, height: 18)
        content.addSubview(status)

        window.center()
        window.makeKeyAndOrderFront(nil)

        let args = CommandLine.arguments
        // `AudioPlayer --render out.wav [file.wav]` renders two seconds offline and exits.
        if let i = args.firstIndex(of: "--render"), i + 1 < args.count {
            if i + 2 < args.count { open(URL(fileURLWithPath: args[i + 2])) }
            do {
                let frames = try model.render(to: URL(fileURLWithPath: args[i + 1]), seconds: 2)
                print("rendered \(args[i + 1]) (\(frames) frames, \(model.fileName) + 440 Hz sine)")
            } catch {
                print("render failed: \(error)")
            }
            fflush(nil)
            NSApp.terminate(nil)
            return
        }
        if args.count > 1, !args[1].hasPrefix("-") { open(URL(fileURLWithPath: args[1])) }
        status.stringValue = model.startEngine()
        print("audio: \(status.stringValue)")
        fflush(nil)
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        }
        update()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

let delegate = AppDelegate()
let app = NSApplication.shared
app.delegate = delegate
app.run()
