// NSSound over AVAudioPlayer (ADR-0014): each sound owns a player on the shared output.
// Hand-written (see tools/apigen/config.json); the stub it replaced came from the
// generator.

import Foundation
import AVFAudio
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// - SeeAlso: https://developer.apple.com/documentation/appkit/nssound
open class NSSound: NSObject, NSCopying, NSSecureCoding, NSCoding, NSPasteboardReading, NSPasteboardWriting {
    private enum Source { case url(URL), data(Data) }
    private let source: Source
    private let player: AVAudioPlayer
    private var _name: NSSound.Name?
    private var _loops = false
    private var _playbackDeviceIdentifier: NSSound.PlaybackDeviceIdentifier?
    private var relay: _NSSoundDelegateRelay?
    /// `setName(_:)` registry, for `init(named:)`.
    nonisolated(unsafe) private static var named: [NSSound.Name: NSSound] = [:]
    private static let namedLock = NSLock()

    private init?(source: Source) {
        self.source = source
        do {
            switch source {
            case .url(let url): player = try AVAudioPlayer(contentsOf: url)
            case .data(let data): player = try AVAudioPlayer(data: data)
            }
        } catch {
            return nil
        }
        super.init()
        let r = _NSSoundDelegateRelay(sound: self)
        relay = r
        player.delegate = r
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssound/init(contentsof:byreference:)
    public convenience init?(contentsOf url: URL, byReference byRef: Bool) {
        self.init(source: .url(url))
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssound/init(contentsoffile:byreference:)
    public convenience init?(contentsOfFile path: String, byReference byRef: Bool) {
        self.init(source: .url(URL(fileURLWithPath: path)))
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssound/init(data:)
    public convenience init?(data: Data) {
        self.init(source: .data(data))
    }
    /// A sound registered with `setName(_:)`, or a sound resource of the main bundle
    /// (`name.wav`, `.aiff`, `.aif`, `.aifc`); the system sounds do not exist here.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssound/init(named:)
    public convenience init?(named name: NSSound.Name) {
        NSSound.namedLock.lock()
        let registered = NSSound.named[name]
        NSSound.namedLock.unlock()
        if let registered {
            self.init(source: registered.source)
            _name = name
            return
        }
        guard let url = NSSound._resourceURL(named: name) else { return nil }
        self.init(source: .url(url))
        _name = name
    }
    /// A sound file of the main bundle: `name` with each of the supported extensions.
    private static func _resourceURL(named name: NSSound.Name) -> URL? {
        for ext in ["wav", "aiff", "aif", "aifc"] {
            if let url = Bundle.main.url(forResource: name, withExtension: ext) { return url }
        }
        return nil
    }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssound/init(pasteboard:)
    public init?(pasteboard: NSPasteboard) { unimplemented() }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssound/beep()
    public static func beep() {
        if Thread.isMainThread { MainActor.assumeIsolated { Platform.backend.beep() } } else { DispatchQueue.main.async { Platform.backend.beep() } }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssound/caninit(with:)
    public class func canInit(with pasteboard: NSPasteboard) -> Bool { false }

    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssound/currenttime
    open var currentTime: TimeInterval {
        get { player.currentTime }
        set { player.currentTime = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssound/delegate
    open weak var delegate: (any NSSoundDelegate)?
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssound/duration
    open var duration: TimeInterval { player.duration }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssound/isplaying
    open var isPlaying: Bool { player.isPlaying }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssound/loops
    open var loops: Bool {
        get { _loops }
        set { _loops = newValue; player.numberOfLoops = newValue ? -1 : 0 }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssound/name
    open var name: NSSound.Name? { _name }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssound/pause()
    @discardableResult open func pause() -> Bool {
        guard player.isPlaying else { return false }
        player.pause()
        return true
    }
    /// Starts from the beginning; false when the sound is already playing or there is no
    /// output device.
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssound/play()
    @discardableResult open func play() -> Bool {
        guard !player.isPlaying else { return false }
        player.currentTime = 0
        return player.play()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssound/playbackdeviceidentifier
    open var playbackDeviceIdentifier: NSSound.PlaybackDeviceIdentifier? {
        get { _playbackDeviceIdentifier }
        set { _playbackDeviceIdentifier = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssound/resume()
    @discardableResult open func resume() -> Bool {
        guard !player.isPlaying, player.currentTime > 0 else { return false }
        return player.play()
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssound/setname(_:)
    @discardableResult open func setName(_ string: NSSound.Name?) -> Bool {
        NSSound.namedLock.lock(); defer { NSSound.namedLock.unlock() }
        if let old = _name { NSSound.named[old] = nil }
        _name = string
        if let string {
            if NSSound.named[string] != nil { return false }
            NSSound.named[string] = self
        }
        return true
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssound/soundunfilteredtypes
    class public var soundUnfilteredTypes: [String] { ["com.microsoft.waveform-audio", "public.aiff-audio", "public.aifc-audio"] }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssound/stop()
    @discardableResult open func stop() -> Bool {
        let was = player.isPlaying
        player.stop()
        player.currentTime = 0
        if was { _finished(successfully: false) }
        return was
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssound/volume
    open var volume: Float {
        get { player.volume }
        set { player.volume = newValue }
    }
    /// - SeeAlso: https://developer.apple.com/documentation/appkit/nssound/write(to:)
    open func write(to pasteboard: NSPasteboard) { unimplemented() }

    fileprivate func _finished(successfully: Bool) {
        guard let delegate else { return }
        if Thread.isMainThread {
            MainActor.assumeIsolated { delegate.sound(self, didFinishPlaying: successfully) }
        } else {
            DispatchQueue.main.async { delegate.sound(self, didFinishPlaying: successfully) }
        }
    }

    // Requirement of NSCopying
    open func copy(with zone: NSZone? = nil) -> Any {
        let c = NSSound(source: source)!
        c._name = _name
        c.loops = _loops
        c.volume = volume
        return c
    }
    // Requirement of NSSecureCoding
    class public var supportsSecureCoding: Bool { true }
    // Requirement of NSCoding
    open func encode(with coder: NSCoder) { unimplemented() }
    // Requirement of NSCoding
    public required init?(coder: NSCoder) { unimplemented() }
    // Requirement of NSPasteboardReading
    public required init?(pasteboardPropertyList propertyList: Any, ofType type: NSPasteboard.PasteboardType) { unimplemented() }
}

/// Bridges the player's delegate (any thread) to the sound's main-actor delegate.
private final class _NSSoundDelegateRelay: NSObject, AVAudioPlayerDelegate {
    weak var sound: NSSound?
    init(sound: NSSound) { self.sound = sound }
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        sound?._finished(successfully: flag)
    }
}
