// Packet and event lists: building them in caller-owned memory the way CoreMIDI's C
// functions do, walking them, and turning their contents into the MIDI 1.0 messages the
// platform APIs take.
//
// Lists are variable length: packet n+1 starts right after packet n's bytes (or words),
// rounded up to the packet's alignment. Packets past the first are touched only through
// raw loads and stores, so a packet at the end of a short buffer is never read whole.

import Foundation

private let packetTimeOffset = MemoryLayout<MIDIPacket>.offset(of: \MIDIPacket.timeStamp)!
private let packetLengthOffset = MemoryLayout<MIDIPacket>.offset(of: \MIDIPacket.length)!
private let packetDataOffset = MemoryLayout<MIDIPacket>.offset(of: \MIDIPacket.data)!
private let packetAlignment = MemoryLayout<MIDIPacket>.alignment

private let eventTimeOffset = MemoryLayout<MIDIEventPacket>.offset(of: \MIDIEventPacket.timeStamp)!
private let eventCountOffset = MemoryLayout<MIDIEventPacket>.offset(of: \MIDIEventPacket.wordCount)!
private let eventWordsOffset = MemoryLayout<MIDIEventPacket>.offset(of: \MIDIEventPacket.words)!
private let eventAlignment = MemoryLayout<MIDIEventPacket>.alignment
/// The most words one event packet holds (its `words` tuple).
private let eventMaxWords = 64

private func alignUp(_ pointer: UnsafeMutableRawPointer, _ alignment: Int) -> UnsafeMutableRawPointer {
    let address = UInt(bitPattern: pointer)
    let mask = UInt(alignment - 1)
    return UnsafeMutableRawPointer(bitPattern: (address + mask) & ~mask)!
}

/// Apple's C functions return NULL when a list is full; the Swift import declares the result
/// non-optional, so this is what callers get there too.
private func nullPointer<T>(_: T.Type) -> UnsafeMutablePointer<T> {
    unsafeBitCast(UnsafeMutablePointer<T>?.none, to: UnsafeMutablePointer<T>.self)
}

// MARK: - MIDIPacketList

@discardableResult
public func MIDIPacketListInit(_ pktlist: UnsafeMutablePointer<MIDIPacketList>) -> UnsafeMutablePointer<MIDIPacket> {
    let raw = UnsafeMutableRawPointer(pktlist)
    raw.storeBytes(of: UInt32(0), toByteOffset: MemoryLayout<MIDIPacketList>.offset(of: \MIDIPacketList.numPackets)!, as: UInt32.self)
    return (raw + MemoryLayout<MIDIPacketList>.offset(of: \MIDIPacketList.packet)!).assumingMemoryBound(to: MIDIPacket.self)
}

@discardableResult
public func MIDIPacketNext(_ pkt: UnsafePointer<MIDIPacket>) -> UnsafeMutablePointer<MIDIPacket> {
    let raw = UnsafeMutableRawPointer(mutating: pkt)
    let length = Int(raw.load(fromByteOffset: packetLengthOffset, as: UInt16.self))
    return alignUp(raw + packetDataOffset + length, packetAlignment).assumingMemoryBound(to: MIDIPacket.self)
}

@discardableResult
public func MIDIPacketListAdd(_ pktlist: UnsafeMutablePointer<MIDIPacketList>, _ listSize: Int, _ curPacket: UnsafeMutablePointer<MIDIPacket>, _ time: MIDITimeStamp, _ nData: Int, _ data: UnsafePointer<UInt8>) -> UnsafeMutablePointer<MIDIPacket> {
    let listRaw = UnsafeMutableRawPointer(pktlist)
    let end = listRaw + listSize
    let countOffset = MemoryLayout<MIDIPacketList>.offset(of: \MIDIPacketList.numPackets)!
    let count = listRaw.load(fromByteOffset: countOffset, as: UInt32.self)
    let current = UnsafeMutableRawPointer(curPacket)
    guard nData >= 0, nData <= Int(UInt16.max) else { return nullPointer(MIDIPacket.self) }

    var target = current
    if count > 0 {
        let currentLength = Int(current.load(fromByteOffset: packetLengthOffset, as: UInt16.self))
        let currentTime = current.load(fromByteOffset: packetTimeOffset, as: MIDITimeStamp.self)
        let currentIsSysEx = currentLength > 0 && current.load(fromByteOffset: packetDataOffset, as: UInt8.self) == 0xF0
        let newIsSysEx = nData > 0 && data[0] == 0xF0
        let tail = current + packetDataOffset + currentLength
        // Same timestamp, neither side SysEx: CoreMIDI appends to the current packet.
        if currentTime == time, !currentIsSysEx, !newIsSysEx, nData > 0, data[0] & 0x80 != 0,
           currentLength + nData <= Int(UInt16.max), tail + nData <= end {
            tail.copyMemory(from: data, byteCount: nData)
            current.storeBytes(of: UInt16(currentLength + nData), toByteOffset: packetLengthOffset, as: UInt16.self)
            return curPacket
        }
        target = alignUp(tail, packetAlignment)
    }
    guard target + packetDataOffset + nData <= end else { return nullPointer(MIDIPacket.self) }
    target.storeBytes(of: time, toByteOffset: packetTimeOffset, as: MIDITimeStamp.self)
    target.storeBytes(of: UInt16(nData), toByteOffset: packetLengthOffset, as: UInt16.self)
    (target + packetDataOffset).copyMemory(from: data, byteCount: nData)
    listRaw.storeBytes(of: count + 1, toByteOffset: countOffset, as: UInt32.self)
    return target.assumingMemoryBound(to: MIDIPacket.self)
}

/// The byte payloads of a packet list, in order.
struct _MIDIPackets: Sequence {
    let list: UnsafePointer<MIDIPacketList>

    init(_ list: UnsafePointer<MIDIPacketList>) { self.list = list }

    func makeIterator() -> AnyIterator<[UInt8]> {
        let raw = UnsafeRawPointer(list)
        let count = Int(raw.load(fromByteOffset: MemoryLayout<MIDIPacketList>.offset(of: \MIDIPacketList.numPackets)!, as: UInt32.self))
        var packet = UnsafeRawPointer(raw + MemoryLayout<MIDIPacketList>.offset(of: \MIDIPacketList.packet)!)
        var index = 0
        return AnyIterator {
            guard index < count else { return nil }
            index += 1
            let length = Int(packet.load(fromByteOffset: packetLengthOffset, as: UInt16.self))
            let bytes = Array(UnsafeRawBufferPointer(start: packet + packetDataOffset, count: length))
            packet = UnsafeRawPointer(MIDIPacketNext(packet.assumingMemoryBound(to: MIDIPacket.self)))
            return bytes
        }
    }
}

// MARK: - MIDIEventList

@discardableResult
public func MIDIEventListInit(_ evtlist: UnsafeMutablePointer<MIDIEventList>, _ protocol: MIDIProtocolID) -> UnsafeMutablePointer<MIDIEventPacket> {
    evtlist.pointer(to: \.protocol)!.pointee = `protocol`
    evtlist.pointer(to: \.numPackets)!.pointee = 0
    return evtlist.pointer(to: \.packet)!
}

@discardableResult
public func MIDIEventPacketNext(_ pkt: UnsafePointer<MIDIEventPacket>) -> UnsafeMutablePointer<MIDIEventPacket> {
    let raw = UnsafeMutableRawPointer(mutating: pkt)
    let count = Int(raw.load(fromByteOffset: eventCountOffset, as: UInt32.self))
    return alignUp(raw + eventWordsOffset + count * 4, eventAlignment).assumingMemoryBound(to: MIDIEventPacket.self)
}

@discardableResult
public func MIDIEventListAdd(_ evtlist: UnsafeMutablePointer<MIDIEventList>, _ listSize: Int, _ curPacket: UnsafeMutablePointer<MIDIEventPacket>, _ time: MIDITimeStamp, _ wordCount: Int, _ words: UnsafePointer<UInt32>) -> UnsafeMutablePointer<MIDIEventPacket> {
    let listRaw = UnsafeMutableRawPointer(evtlist)
    let end = listRaw + listSize
    let countPointer = evtlist.pointer(to: \.numPackets)!
    let count = countPointer.pointee
    let current = UnsafeMutableRawPointer(curPacket)
    guard wordCount >= 0, wordCount <= eventMaxWords else { return nullPointer(MIDIEventPacket.self) }

    var target = current
    if count > 0 {
        let currentCount = Int(current.load(fromByteOffset: eventCountOffset, as: UInt32.self))
        let currentTime = current.load(fromByteOffset: eventTimeOffset, as: MIDITimeStamp.self)
        let tail = current + eventWordsOffset + currentCount * 4
        if currentTime == time, currentCount + wordCount <= eventMaxWords, tail + wordCount * 4 <= end {
            tail.copyMemory(from: words, byteCount: wordCount * 4)
            current.storeBytes(of: UInt32(currentCount + wordCount), toByteOffset: eventCountOffset, as: UInt32.self)
            return curPacket
        }
        target = alignUp(tail, eventAlignment)
    }
    guard target + eventWordsOffset + wordCount * 4 <= end else { return nullPointer(MIDIEventPacket.self) }
    target.storeBytes(of: time, toByteOffset: eventTimeOffset, as: MIDITimeStamp.self)
    target.storeBytes(of: UInt32(wordCount), toByteOffset: eventCountOffset, as: UInt32.self)
    (target + eventWordsOffset).copyMemory(from: words, byteCount: wordCount * 4)
    countPointer.pointee = count + 1
    return target.assumingMemoryBound(to: MIDIEventPacket.self)
}

/// The word payloads of an event list, in order.
struct _MIDIEventPackets: Sequence {
    let list: UnsafePointer<MIDIEventList>

    init(_ list: UnsafePointer<MIDIEventList>) { self.list = list }

    func makeIterator() -> AnyIterator<[UInt32]> {
        let count = Int(list.pointer(to: \.numPackets)!.pointee)
        var packet = UnsafeRawPointer(list.pointer(to: \.packet)!)
        var index = 0
        return AnyIterator {
            guard index < count else { return nil }
            index += 1
            let wordCount = Int(packet.load(fromByteOffset: eventCountOffset, as: UInt32.self))
            let words = (0..<wordCount).map { packet.load(fromByteOffset: eventWordsOffset + $0 * 4, as: UInt32.self) }
            packet = UnsafeRawPointer(MIDIEventPacketNext(packet.assumingMemoryBound(to: MIDIEventPacket.self)))
            return words
        }
    }
}

// MARK: - Messages

/// One message for the platform API: a short (1-3 byte) message or a complete SysEx.
enum _MIDIMessage: Equatable {
    case short([UInt8])
    case sysEx([UInt8])

    var bytes: [UInt8] {
        switch self {
        case .short(let bytes), .sysEx(let bytes): return bytes
        }
    }
}

/// Number of data bytes after a status byte (MIDI 1.0).
func _MIDIDataLength(_ status: UInt8) -> Int {
    switch status {
    case 0x80...0xBF, 0xE0...0xEF: return 2
    case 0xC0...0xDF: return 1
    case 0xF1, 0xF3: return 1
    case 0xF2: return 2
    default: return 0
    }
}

/// Splits a MIDI 1.0 byte stream into messages: running status, SysEx (also across
/// packets), real-time bytes interleaved anywhere.
struct _MIDIByteStreamParser {
    private(set) var messages: [_MIDIMessage] = []
    private var runningStatus: UInt8 = 0
    private var pending: [UInt8] = []
    private var sysEx: [UInt8]?

    mutating func feed(_ bytes: [UInt8]) {
        for byte in bytes { feed(byte) }
    }

    mutating func feed(_ byte: UInt8) {
        if byte >= 0xF8 {
            messages.append(.short([byte]))
            return
        }
        if var buffer = sysEx {
            if byte & 0x80 == 0 {
                buffer.append(byte)
                sysEx = buffer
                return
            }
            // F7 ends the SysEx; any other status byte ends it too (and is then parsed).
            buffer.append(0xF7)
            messages.append(.sysEx(buffer))
            sysEx = nil
            if byte == 0xF7 { return }
        }
        if byte == 0xF0 {
            sysEx = [0xF0]
            pending = []
            runningStatus = 0
            return
        }
        if byte & 0x80 != 0 {
            pending = [byte]
            runningStatus = byte < 0xF0 ? byte : 0
            if _MIDIDataLength(byte) == 0 {
                if byte != 0xF7 { messages.append(.short([byte])) }
                pending = []
            }
            return
        }
        if pending.isEmpty {
            guard runningStatus != 0 else { return }   // stray data byte
            pending = [runningStatus]
        }
        pending.append(byte)
        if pending.count == _MIDIDataLength(pending[0]) + 1 {
            messages.append(.short(pending))
            pending = []
        }
    }

    /// Flushes an unterminated SysEx (sent as is, like CoreMIDI does with split SysEx).
    mutating func finish() {
        if let buffer = sysEx, buffer.count > 1 {
            messages.append(.sysEx(buffer))
        }
        sysEx = nil
    }
}

/// Converts Universal MIDI Packet words to MIDI 1.0 messages.
struct _UMPConverter {
    private(set) var messages: [_MIDIMessage] = []
    private var sysEx: [UInt8]?

    /// Words per message, by message type (the top nibble of the first word).
    static let wordCounts = [1, 1, 1, 2, 2, 4, 1, 1, 2, 2, 2, 3, 3, 4, 4, 4]

    mutating func feed(_ words: [UInt32]) {
        var index = 0
        while index < words.count {
            let type = Int(words[index] >> 28)
            let size = Self.wordCounts[type]
            guard index + size <= words.count else { return }
            convert(Array(words[index..<index + size]))
            index += size
        }
    }

    private mutating func convert(_ words: [UInt32]) {
        let w0 = words[0]
        let status = UInt8((w0 >> 16) & 0xFF)
        let data1 = UInt8((w0 >> 8) & 0x7F)
        let data2 = UInt8(w0 & 0x7F)
        switch w0 >> 28 {
        case 0x1:   // system common and real time
            switch _MIDIDataLength(status) {
            case 1: messages.append(.short([status, data1]))
            case 2: messages.append(.short([status, data1, data2]))
            default: messages.append(.short([status]))
            }
        case 0x2:   // MIDI 1.0 channel voice
            guard status >= 0x80, status < 0xF0 else { return }
            messages.append(.short(_MIDIDataLength(status) == 1 ? [status, data1] : [status, data1, data2]))
        case 0x3:   // 7-bit SysEx data
            let form = (w0 >> 20) & 0xF
            let count = min(Int((w0 >> 16) & 0xF), 6)
            let all: [UInt8] = [UInt8((w0 >> 8) & 0x7F), UInt8(w0 & 0x7F),
                                UInt8((words[1] >> 24) & 0x7F), UInt8((words[1] >> 16) & 0x7F),
                                UInt8((words[1] >> 8) & 0x7F), UInt8(words[1] & 0x7F)]
            let payload = Array(all.prefix(count))
            switch form {
            case 0: messages.append(.sysEx([0xF0] + payload + [0xF7]))
            case 1: sysEx = [0xF0] + payload
            case 2: sysEx?.append(contentsOf: payload)
            case 3:
                if var buffer = sysEx {
                    buffer.append(contentsOf: payload)
                    buffer.append(0xF7)
                    messages.append(.sysEx(buffer))
                }
                sysEx = nil
            default: break
            }
        case 0x4:   // MIDI 2.0 channel voice, down-converted
            convertMIDI2(w0, words[1])
        default:
            break   // utility, data 128, flex data, stream: nothing to send on a MIDI 1.0 port
        }
    }

    private mutating func convertMIDI2(_ w0: UInt32, _ w1: UInt32) {
        let opcode = UInt8((w0 >> 20) & 0xF)
        let channel = UInt8((w0 >> 16) & 0xF)
        let index = UInt8((w0 >> 8) & 0x7F)
        let value7 = UInt8(w1 >> 25)
        switch opcode {
        case 0x8:
            messages.append(.short([0x80 | channel, index, UInt8(w1 >> 25)]))
        case 0x9:
            let velocity16 = w1 >> 16
            var velocity = UInt8(velocity16 >> 9)
            if velocity == 0 && velocity16 != 0 { velocity = 1 }   // never turn a note on into a note off
            messages.append(.short([0x90 | channel, index, velocity]))
        case 0xA:
            messages.append(.short([0xA0 | channel, index, value7]))
        case 0xB:
            messages.append(.short([0xB0 | channel, index, value7]))
        case 0xC:
            if w0 & 1 != 0 {
                messages.append(.short([0xB0 | channel, 0, UInt8((w1 >> 8) & 0x7F)]))
                messages.append(.short([0xB0 | channel, 32, UInt8(w1 & 0x7F)]))
            }
            messages.append(.short([0xC0 | channel, UInt8((w1 >> 24) & 0x7F)]))
        case 0xD:
            messages.append(.short([0xD0 | channel, value7]))
        case 0xE:
            let bend14 = w1 >> 18
            messages.append(.short([0xE0 | channel, UInt8(bend14 & 0x7F), UInt8(bend14 >> 7)]))
        default:
            break   // registered/assignable controllers and per-note messages have no 1.0 form here
        }
    }
}
