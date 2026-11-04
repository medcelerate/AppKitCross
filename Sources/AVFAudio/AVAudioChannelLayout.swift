// AVAudioChannelLayout: a tagged or described channel layout.

import Foundation

/// - SeeAlso: https://developer.apple.com/documentation/avfaudio/avaudiochannellayout
open class AVAudioChannelLayout: NSObject, NSSecureCoding, @unchecked Sendable {
    private let storage: UnsafeMutablePointer<AudioChannelLayout>
    private let descriptionCount: Int

    public init?(layoutTag: AudioChannelLayoutTag) {
        guard layoutTag != kAudioChannelLayoutTag_UseChannelDescriptions, layoutTag != kAudioChannelLayoutTag_UseChannelBitmap,
              AudioChannelLayoutTag_GetNumberOfChannels(layoutTag) > 0 else { return nil }
        var l = AudioChannelLayout()
        l.mChannelLayoutTag = layoutTag
        storage = UnsafeMutablePointer<AudioChannelLayout>.allocate(capacity: 1)
        storage.initialize(to: l)
        descriptionCount = 0
    }

    public init(layout: UnsafePointer<AudioChannelLayout>) {
        let n = Int(layout.pointee.mNumberChannelDescriptions)
        descriptionCount = n
        let bytes = MemoryLayout<AudioChannelLayout>.offset(of: \.mChannelDescriptions)! + max(1, n) * MemoryLayout<AudioChannelDescription>.stride
        let raw = UnsafeMutableRawPointer.allocate(byteCount: bytes, alignment: MemoryLayout<AudioChannelLayout>.alignment)
        raw.copyMemory(from: UnsafeRawPointer(layout), byteCount: bytes)
        storage = raw.bindMemory(to: AudioChannelLayout.self, capacity: 1)
    }

    deinit { storage.deallocate() }

    open var layoutTag: AudioChannelLayoutTag { storage.pointee.mChannelLayoutTag }
    open var layout: UnsafePointer<AudioChannelLayout> { UnsafePointer(storage) }
    open var channelCount: AVAudioChannelCount {
        let tag = storage.pointee.mChannelLayoutTag
        if tag == kAudioChannelLayoutTag_UseChannelDescriptions { return storage.pointee.mNumberChannelDescriptions }
        if tag == kAudioChannelLayoutTag_UseChannelBitmap { return UInt32(storage.pointee.mChannelBitmap.nonzeroBitCount) }
        return AudioChannelLayoutTag_GetNumberOfChannels(tag)
    }

    open override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? AVAudioChannelLayout else { return false }
        if other === self { return true }
        guard layoutTag == other.layoutTag, storage.pointee.mChannelBitmap == other.storage.pointee.mChannelBitmap,
              descriptionCount == other.descriptionCount else { return false }
        let a = _descriptions, b = other._descriptions
        return a == b
    }
    open override var hash: Int { Int(layoutTag) ^ Int(storage.pointee.mChannelBitmap) }

    var _descriptions: [AudioChannelDescription] {
        guard descriptionCount > 0 else { return [] }
        let base = UnsafeMutableRawPointer(storage).advanced(by: MemoryLayout<AudioChannelLayout>.offset(of: \.mChannelDescriptions)!)
            .assumingMemoryBound(to: AudioChannelDescription.self)
        return (0..<descriptionCount).map { base[$0] }
    }

    /// Apple's layout for a channel count when the caller gave none: mono and stereo have
    /// tags; more channels are discrete.
    static func _standard(channels: AVAudioChannelCount) -> AVAudioChannelLayout? {
        switch channels {
        case 1: return AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_Mono)
        case 2: return AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_Stereo)
        case 0: return nil
        default: return AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_DiscreteInOrder | channels)
        }
    }

    // NSSecureCoding
    public class var supportsSecureCoding: Bool { true }
    public required init?(coder: NSCoder) {
        let tag = UInt32(truncatingIfNeeded: coder.decodeInt64(forKey: "tag"))
        var l = AudioChannelLayout(); l.mChannelLayoutTag = tag
        l.mChannelBitmap = UInt32(truncatingIfNeeded: coder.decodeInt64(forKey: "bitmap"))
        storage = UnsafeMutablePointer<AudioChannelLayout>.allocate(capacity: 1)
        storage.initialize(to: l)
        descriptionCount = 0
        super.init()
    }
    open func encode(with coder: NSCoder) {
        coder.encode(Int64(layoutTag), forKey: "tag")
        coder.encode(Int64(storage.pointee.mChannelBitmap), forKey: "bitmap")
    }
}
