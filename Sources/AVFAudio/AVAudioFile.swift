// AVAudioFile: reads and writes WAV and AIFF/AIFF-C files, converting between the file's
// PCM encoding and a processing format (Float32 non-interleaved unless asked otherwise).

import Foundation

/// - SeeAlso: https://developer.apple.com/documentation/avfaudio/avaudiofile
open class AVAudioFile: NSObject, @unchecked Sendable {
    private let _url: URL
    private let _fileFormat: AVAudioFormat
    private let _processingFormat: AVAudioFormat
    private let encoding: _PCMEncoding
    private let kind: _ContainerKind
    private var _length: AVAudioFramePosition
    private var _framePosition: AVAudioFramePosition = 0
    private var _isOpen = true
    private let lock = NSLock()
    // Reading
    private var source: _ByteSource?
    private let dataOffset: Int
    // Writing
    private var writer: FileHandle?
    private var headerData: Data?

    /// Opens `fileURL` for reading with the standard processing format.
    public convenience init(forReading fileURL: URL) throws {
        try self.init(forReading: fileURL, commonFormat: .pcmFormatFloat32, interleaved: false)
    }

    public init(forReading fileURL: URL, commonFormat format: AVAudioCommonFormat, interleaved: Bool) throws {
        _url = fileURL
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw _osStatusError(kAudioFileUnspecifiedError, "AVAudioFile: \(fileURL.path) does not exist")
        }
        let src: _FileByteSource
        do { src = try _FileByteSource(url: fileURL) } catch {
            throw _osStatusError(kAudioFilePermissionsError, "AVAudioFile: cannot open \(fileURL.path): \(error)")
        }
        let info: _ContainerInfo
        do { info = try _Containers.parse(src) } catch let e as _ContainerError {
            src.close()
            throw _osStatusError(e.status, "AVAudioFile: \(fileURL.lastPathComponent): \(e.message)")
        }
        source = src
        encoding = info.encoding
        kind = info.kind
        dataOffset = info.dataOffset
        _length = AVAudioFramePosition(info.frameCount)
        var asbd = info.encoding.asbd
        _fileFormat = AVAudioFormat(streamDescription: &asbd)!
        guard let pf = AVAudioFormat(commonFormat: format, sampleRate: info.encoding.sampleRate, channels: AVAudioChannelCount(info.encoding.channels), interleaved: interleaved) else {
            src.close()
            throw _osStatusError(kAudioFileUnsupportedDataFormatError, "AVAudioFile: unsupported processing format")
        }
        _processingFormat = pf
        super.init()
    }

    /// Creates `fileURL` for writing; the container comes from the path extension and the
    /// encoding from `settings` (AVAudioSettings keys).
    public convenience init(forWriting fileURL: URL, settings: [String: Any]) throws {
        try self.init(forWriting: fileURL, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
    }

    public init(forWriting fileURL: URL, settings: [String: Any], commonFormat format: AVAudioCommonFormat, interleaved: Bool) throws {
        _url = fileURL
        let kind: _ContainerKind
        switch fileURL.pathExtension.lowercased() {
        case "wav", "wave": kind = .wave
        case "aif", "aiff": kind = .aiff
        case "aifc": kind = .aifc
        default: throw _osStatusError(kAudioFileUnsupportedFileTypeError, "AVAudioFile: unsupported file type .\(fileURL.pathExtension)")
        }
        self.kind = kind
        guard let ff = AVAudioFormat(settings: settings), ff.streamDescription.pointee.mFormatID == kAudioFormatLinearPCM else {
            throw _osStatusError(kAudioFileUnsupportedDataFormatError, "AVAudioFile: unsupported settings \(settings)")
        }
        let d = ff.streamDescription.pointee
        let isFloat = d.mFormatFlags & kAudioFormatFlagIsFloat != 0
        let bits = Int(d.mBitsPerChannel)
        if kind == .aiff && isFloat {
            throw _osStatusError(kAudioFileUnsupportedDataFormatError, "AVAudioFile: AIFF holds integer PCM only; use .aifc for float")
        }
        if kind == .wave && (bits > 32 && !isFloat) || (bits < 8) || ![8, 16, 24, 32, 64].contains(bits) {
            throw _osStatusError(kAudioFileUnsupportedDataFormatError, "AVAudioFile: unsupported bit depth \(bits)")
        }
        let bigEndian = kind == .wave ? false : (kind == .aiff ? true : d.mFormatFlags & kAudioFormatFlagIsBigEndian != 0 || isFloat)
        encoding = _PCMEncoding(bitsPerSample: bits, isFloat: isFloat, isBigEndian: bigEndian, isSigned: !(kind == .wave && bits == 8), channels: Int(d.mChannelsPerFrame), sampleRate: d.mSampleRate)
        var asbd = encoding.asbd
        _fileFormat = AVAudioFormat(streamDescription: &asbd, channelLayout: ff.channelLayout)!
        guard let pf = AVAudioFormat(commonFormat: format, sampleRate: d.mSampleRate, channels: d.mChannelsPerFrame, interleaved: interleaved) else {
            throw _osStatusError(kAudioFileUnsupportedDataFormatError, "AVAudioFile: unsupported processing format")
        }
        _processingFormat = pf
        dataOffset = 0
        _length = 0
        let header = _Containers.header(kind: kind, encoding: encoding, frameCount: 0)
        guard FileManager.default.createFile(atPath: fileURL.path, contents: header), let h = try? FileHandle(forWritingTo: fileURL) else {
            throw _osStatusError(kAudioFilePermissionsError, "AVAudioFile: cannot create \(fileURL.path)")
        }
        h.seekToEndOfFile()
        writer = h
        headerData = header
        super.init()
    }

    deinit { close() }

    open var isOpen: Bool { lock.withLock { _isOpen } }
    open var url: URL { _url }
    open var fileFormat: AVAudioFormat { _fileFormat }
    open var processingFormat: AVAudioFormat { _processingFormat }
    open var length: AVAudioFramePosition { lock.withLock { _length } }
    open var framePosition: AVAudioFramePosition {
        get { lock.withLock { _framePosition } }
        set { lock.withLock { _framePosition = max(0, min(newValue, _length)) } }
    }

    /// Finishes a file opened for writing (patches the header) and releases the handle.
    open func close() {
        lock.lock(); defer { lock.unlock() }
        guard _isOpen else { return }
        _isOpen = false
        if let w = writer, let header = headerData {
            let frames = Int(_length)
            let dataBytes = frames * encoding.bytesPerFrame
            for patch in _Containers.sizePatches(kind: kind, encoding: encoding, header: header) {
                let value = patch.isFrameCount ? frames : patch.base + dataBytes
                var bytes = [UInt8](repeating: 0, count: 4)
                for i in 0..<4 { bytes[i] = UInt8((value >> (patch.bigEndian ? 24 - 8 * i : 8 * i)) & 0xFF) }
                w.seek(toFileOffset: UInt64(patch.offset))
                w.write(Data(bytes))
            }
            if dataBytes & 1 == 1 { w.seekToEndOfFile(); w.write(Data([0])) }
            w.closeFile()
            writer = nil
        }
        (source as? _FileByteSource)?.close()
        source = nil
    }

    /// Reads up to the buffer's capacity.
    open func read(into buffer: AVAudioPCMBuffer) throws {
        try read(into: buffer, frameCount: buffer.frameCapacity)
    }

    /// Reads up to `frames` frames from the current position; fewer at the end of the file
    /// (the buffer's `frameLength` says how many).
    open func read(into buffer: AVAudioPCMBuffer, frameCount frames: AVAudioFrameCount) throws {
        lock.lock(); defer { lock.unlock() }
        guard _isOpen, let source else { throw _osStatusError(kAudioFileNotOpenError, "AVAudioFile: not open") }
        guard writer == nil else { throw _osStatusError(kAudioFileOperationNotSupportedError, "AVAudioFile: opened for writing") }
        guard buffer.format.isEqual(_processingFormat) else {
            throw _osStatusError(kAudioFileUnsupportedDataFormatError, "AVAudioFile: buffer format \(buffer.format) differs from the processing format \(_processingFormat)")
        }
        let want = Int(min(frames, buffer.frameCapacity))
        let available = max(0, Int(_length - _framePosition))
        let n = min(want, available)
        buffer.frameLength = AVAudioFrameCount(n)
        guard n > 0 else { return }
        let bytes = source.read(at: dataOffset + Int(_framePosition) * encoding.bytesPerFrame, count: n * encoding.bytesPerFrame)
        let got = bytes.count / encoding.bytesPerFrame
        _decode(bytes, frames: got, into: buffer)
        buffer.frameLength = AVAudioFrameCount(got)
        _framePosition += AVAudioFramePosition(got)
    }

    private func _decode(_ bytes: Data, frames: Int, into buffer: AVAudioPCMBuffer) {
        let ch = encoding.channels
        let planes = UnsafeMutablePointer<UnsafeMutablePointer<Float>>.allocate(capacity: ch)
        for c in 0..<ch { planes[c] = UnsafeMutablePointer<Float>.allocate(capacity: max(1, frames)) }
        defer { for c in 0..<ch { planes[c].deallocate() }; planes.deallocate() }
        bytes.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            _PCMCodec.decode(base, frames: frames, encoding: encoding, into: planes, outOffset: 0)
        }
        for c in 0..<ch { buffer._writeFloats(channel: c, frame: 0, count: frames, from: planes[c]) }
    }

    /// Appends the buffer's frames (in the processing format) to a file opened for writing.
    open func write(from buffer: AVAudioPCMBuffer) throws {
        lock.lock(); defer { lock.unlock() }
        guard _isOpen, let w = writer else { throw _osStatusError(kAudioFileOperationNotSupportedError, "AVAudioFile: not opened for writing") }
        guard buffer.format.isEqual(_processingFormat) else {
            throw _osStatusError(kAudioFileUnsupportedDataFormatError, "AVAudioFile: buffer format \(buffer.format) differs from the processing format \(_processingFormat)")
        }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return }
        let ch = encoding.channels
        let planes = UnsafeMutablePointer<UnsafeMutablePointer<Float>>.allocate(capacity: ch)
        for c in 0..<ch {
            planes[c] = UnsafeMutablePointer<Float>.allocate(capacity: frames)
            buffer._readFloats(channel: c, frame: 0, count: frames, into: planes[c])
        }
        defer { for c in 0..<ch { planes[c].deallocate() }; planes.deallocate() }
        var out = Data(count: frames * encoding.bytesPerFrame)
        out.withUnsafeMutableBytes { raw in
            _PCMCodec.encode(UnsafePointer(planes), srcOffset: 0, frames: frames, encoding: encoding, into: raw.baseAddress!)
        }
        w.seekToEndOfFile()
        w.write(out)
        _length += AVAudioFramePosition(frames)
        _framePosition = _length
    }

    /// Reads every frame into one buffer in the processing format (used by the player
    /// classes); nil for an empty file.
    func _readAll() throws -> AVAudioPCMBuffer? {
        let total = length
        guard total > 0, total < AVAudioFramePosition(UInt32.max) else { return nil }
        guard let buffer = AVAudioPCMBuffer(pcmFormat: _processingFormat, frameCapacity: AVAudioFrameCount(total)) else { return nil }
        let saved = framePosition
        framePosition = 0
        try read(into: buffer)
        framePosition = saved
        return buffer
    }

    /// An in-memory file for `AVAudioPlayer(data:)`: parses the container without a URL.
    static func _decode(data: Data) throws -> (format: AVAudioFormat, buffer: AVAudioPCMBuffer) {
        let src = _DataByteSource(data)
        let info: _ContainerInfo
        do { info = try _Containers.parse(src) } catch let e as _ContainerError {
            throw _osStatusError(e.status, "AVAudioPlayer: \(e.message)")
        }
        var asbd = info.encoding.asbd
        let format = AVAudioFormat(streamDescription: &asbd)!
        let pf = AVAudioFormat(standardFormatWithSampleRate: info.encoding.sampleRate, channels: AVAudioChannelCount(info.encoding.channels))!
        let frames = info.frameCount
        guard let buffer = AVAudioPCMBuffer(pcmFormat: pf, frameCapacity: AVAudioFrameCount(max(1, frames))) else {
            throw _osStatusError(kAudioFileInvalidFileError, "AVAudioPlayer: empty file")
        }
        let bytes = src.read(at: info.dataOffset, count: frames * info.encoding.bytesPerFrame)
        let got = bytes.count / info.encoding.bytesPerFrame
        bytes.withUnsafeBytes { raw in
            guard let base = raw.baseAddress, got > 0 else { return }
            _PCMCodec.decode(base, frames: got, encoding: info.encoding, into: UnsafeMutablePointer(mutating: buffer.floatChannelData!), outOffset: 0)
        }
        buffer.frameLength = AVAudioFrameCount(got)
        return (format, buffer)
    }
}
