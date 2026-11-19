// CoreMIDI for Windows and Linux (ADR-0050): the MIDI output subset of Apple's C API under
// its own names and Swift-imported signatures, over Windows MIDI Services (`CWinMIDI2`,
// Universal MIDI Packets through `Windows.Devices.Midi2`) or WinMM (`CWinMIDI`) on Windows
// and the ALSA sequencer (`CALSASeq`, libasound dlopen'ed at run time) on Linux.
//
// Coverage: clients (`MIDIClientCreateWithBlock`, `MIDIClientDispose`) with setup-change
// notifications, output ports (`MIDIOutputPortCreate`, `MIDIPortDispose`), destinations
// (`MIDIGetNumberOfDestinations`, `MIDIGetDestination`, `MIDIObjectFindByUniqueID`), the
// name/display name/manufacturer/model/unique ID properties, `MIDIPacketList` building
// (`MIDIPacketListInit`/`Add`/`MIDIPacketNext`) and `MIDISend` (running status, SysEx),
// `MIDIEventList` building (`MIDIEventListInit`/`Add`/`MIDIEventPacketNext`) and
// `MIDISendEventList` (UMP: MIDI 1.0 channel voice and system messages, 7-bit SysEx, MIDI
// 2.0 channel voice down-converted to MIDI 1.0 bytes for WinMM and ALSA; on Windows MIDI
// Services the words go through untouched and `MIDISend`'s bytes are converted to UMP).
//
// Unique IDs are stable across replugging: a hash of the device name plus its index among
// same-named devices. The destination list is polled every 2 s while a client exists; a
// change calls every client's notify block with `.msgSetupChanged` on a CoreMIDI queue.
// `APPKITWIN_MIDI_BACKEND=null` (and the macOS test build) uses an in-memory backend; on
// Windows `=winmm` and `=midi2` force one of the two platform backends.
//
// Limitations: output only (no sources, input ports, virtual endpoints, devices/entities,
// thru connections, MIDI-CI); timestamps are ignored (everything is sent immediately);
// only `.msgSetupChanged` is delivered. Windows code is written against the WinMM docs and
// the `Windows.Devices.Midi2` metadata, not yet run on a PC with Windows MIDI Services.

import Foundation

#if !canImport(Darwin)
public typealias OSStatus = Int32
/// Corelibs Foundation does not export CoreFoundation's types; `CFString` is `NSString`
/// here, as in this package's CoreText, so `"name" as CFString` and `cf as String` compile.
public typealias CFString = NSString
/// MacTypes' success status. Disfavored so it does not clash with AVFAudio's `noErr` when
/// a file imports both modules.
@_disfavoredOverload public let noErr: OSStatus = 0
#endif

// MARK: - Object references

public typealias MIDIObjectRef = UInt32
public typealias MIDIClientRef = MIDIObjectRef
public typealias MIDIPortRef = MIDIObjectRef
public typealias MIDIDeviceRef = MIDIObjectRef
public typealias MIDIEntityRef = MIDIObjectRef
public typealias MIDIEndpointRef = MIDIObjectRef
public typealias MIDITimeStamp = UInt64
public typealias MIDIUniqueID = Int32

public var kMIDIInvalidUniqueID: MIDIUniqueID { 0 }

public enum MIDIObjectType: Int32, @unchecked Sendable {
    case other = -1
    case device = 0
    case entity = 1
    case source = 2
    case destination = 3
    case externalDevice = 16
    case externalEntity = 17
    case externalSource = 18
    case externalDestination = 19
}

public enum MIDIProtocolID: Int32, @unchecked Sendable {
    case _1_0 = 1
    case _2_0 = 2
}

// MARK: - Errors

public var kMIDIInvalidClient: OSStatus { -10830 }
public var kMIDIInvalidPort: OSStatus { -10831 }
public var kMIDIWrongEndpointType: OSStatus { -10832 }
public var kMIDINoConnection: OSStatus { -10833 }
public var kMIDIUnknownEndpoint: OSStatus { -10834 }
public var kMIDIUnknownProperty: OSStatus { -10835 }
public var kMIDIWrongPropertyType: OSStatus { -10836 }
public var kMIDINoCurrentSetup: OSStatus { -10837 }
public var kMIDIMessageSendErr: OSStatus { -10838 }
public var kMIDIServerStartErr: OSStatus { -10839 }
public var kMIDISetupFormatErr: OSStatus { -10840 }
public var kMIDIWrongThread: OSStatus { -10841 }
public var kMIDIObjectNotFound: OSStatus { -10842 }
public var kMIDIIDNotUnique: OSStatus { -10843 }
public var kMIDINotPermitted: OSStatus { -10844 }
public var kMIDIUnknownError: OSStatus { -10845 }

// MARK: - Properties

nonisolated(unsafe) public let kMIDIPropertyName: CFString = "name" as CFString
nonisolated(unsafe) public let kMIDIPropertyManufacturer: CFString = "manufacturer" as CFString
nonisolated(unsafe) public let kMIDIPropertyModel: CFString = "model" as CFString
nonisolated(unsafe) public let kMIDIPropertyUniqueID: CFString = "uniqueID" as CFString
nonisolated(unsafe) public let kMIDIPropertyDisplayName: CFString = "displayName" as CFString

// MARK: - Notifications

public enum MIDINotificationMessageID: Int32, @unchecked Sendable {
    case msgSetupChanged = 1
    case msgObjectAdded = 2
    case msgObjectRemoved = 3
    case msgPropertyChanged = 4
    case msgThruConnectionsChanged = 5
    case msgSerialPortOwnerChanged = 6
    case msgIOError = 7
}

public struct MIDINotification {
    public init() {
        messageID = .msgSetupChanged
        messageSize = 0
    }
    public init(messageID: MIDINotificationMessageID, messageSize: UInt32) {
        self.messageID = messageID
        self.messageSize = messageSize
    }
    public var messageID: MIDINotificationMessageID
    public var messageSize: UInt32
}

public typealias MIDINotifyBlock = (UnsafePointer<MIDINotification>) -> Void

// MARK: - Packets

/// A MIDI 1.0 byte packet. As in C, a packet's `data` may run past the 256-byte tuple when
/// the list it lives in was allocated larger; walk lists with `MIDIPacketNext`.
public struct MIDIPacket {
    public init() {
        timeStamp = 0
        length = 0
        data = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    }
    public init(timeStamp: MIDITimeStamp, length: UInt16, data: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)) {
        self.timeStamp = timeStamp
        self.length = length
        self.data = data
    }
    public var timeStamp: MIDITimeStamp
    public var length: UInt16
    public var data: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)
}

public struct MIDIPacketList {
    public init() {
        numPackets = 0
        packet = MIDIPacket()
    }
    public init(numPackets: UInt32, packet: MIDIPacket) {
        self.numPackets = numPackets
        self.packet = packet
    }
    public var numPackets: UInt32
    public var packet: MIDIPacket
}

/// A Universal MIDI Packet group sharing one timestamp.
public struct MIDIEventPacket {
    public init() {
        timeStamp = 0
        wordCount = 0
        words = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    }
    public init(timeStamp: MIDITimeStamp, wordCount: UInt32, words: (UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32)) {
        self.timeStamp = timeStamp
        self.wordCount = wordCount
        self.words = words
    }
    public var timeStamp: MIDITimeStamp
    public var wordCount: UInt32
    public var words: (UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32, UInt32)
}

public struct MIDIEventList {
    public init() {
        self.protocol = ._1_0
        numPackets = 0
        packet = MIDIEventPacket()
    }
    public init(protocol: MIDIProtocolID, numPackets: UInt32, packet: MIDIEventPacket) {
        self.protocol = `protocol`
        self.numPackets = numPackets
        self.packet = packet
    }
    public var `protocol`: MIDIProtocolID
    public var numPackets: UInt32
    public var packet: MIDIEventPacket
}

// MARK: - Clients and ports

@discardableResult
public func MIDIClientCreateWithBlock(_ name: CFString, _ outClient: UnsafeMutablePointer<MIDIClientRef>, _ notifyBlock: MIDINotifyBlock?) -> OSStatus {
    MIDIServer.shared.createClient(name: _MIDIString(name), notify: notifyBlock, out: outClient)
}

@discardableResult
public func MIDIClientDispose(_ client: MIDIClientRef) -> OSStatus {
    MIDIServer.shared.disposeClient(client)
}

@discardableResult
public func MIDIOutputPortCreate(_ client: MIDIClientRef, _ portName: CFString, _ outPort: UnsafeMutablePointer<MIDIPortRef>) -> OSStatus {
    MIDIServer.shared.createOutputPort(client: client, name: _MIDIString(portName), out: outPort)
}

@discardableResult
public func MIDIPortDispose(_ port: MIDIPortRef) -> OSStatus {
    MIDIServer.shared.disposePort(port)
}

// MARK: - Destinations and properties

@discardableResult
public func MIDIGetNumberOfDestinations() -> Int {
    MIDIServer.shared.destinationCount()
}

@discardableResult
public func MIDIGetDestination(_ destIndex0: Int) -> MIDIEndpointRef {
    MIDIServer.shared.destination(at: destIndex0)
}

@discardableResult
public func MIDIObjectFindByUniqueID(_ inUniqueID: MIDIUniqueID, _ outObject: UnsafeMutablePointer<MIDIObjectRef>?, _ outObjectType: UnsafeMutablePointer<MIDIObjectType>?) -> OSStatus {
    MIDIServer.shared.find(uniqueID: inUniqueID, outObject: outObject, outType: outObjectType)
}

@discardableResult
public func MIDIObjectGetIntegerProperty(_ obj: MIDIObjectRef, _ propertyID: CFString, _ outValue: UnsafeMutablePointer<Int32>) -> OSStatus {
    MIDIServer.shared.integerProperty(obj, _MIDIString(propertyID), outValue)
}

@discardableResult
public func MIDIObjectGetStringProperty(_ obj: MIDIObjectRef, _ propertyID: CFString, _ str: UnsafeMutablePointer<Unmanaged<CFString>?>) -> OSStatus {
    switch MIDIServer.shared.stringProperty(obj, _MIDIString(propertyID)) {
    case .success(let value):
        str.pointee = Unmanaged.passRetained(value as CFString)
        return noErr
    case .failure(let status):
        str.pointee = nil
        return status.code
    }
}

// MARK: - Sending

@discardableResult
public func MIDISend(_ port: MIDIPortRef, _ dest: MIDIEndpointRef, _ pktlist: UnsafePointer<MIDIPacketList>) -> OSStatus {
    var parser = _MIDIByteStreamParser()
    for packet in _MIDIPackets(pktlist) {
        parser.feed(packet)
    }
    parser.finish()
    if MIDIServer.shared.backendAcceptsUMP {
        return MIDIServer.shared.sendUMP(_MIDIBytesToUMP(parser.messages), port: port, destination: dest)
    }
    return MIDIServer.shared.send(parser.messages, port: port, destination: dest)
}

@discardableResult
public func MIDISendEventList(_ port: MIDIPortRef, _ dest: MIDIEndpointRef, _ evtlist: UnsafePointer<MIDIEventList>) -> OSStatus {
    if MIDIServer.shared.backendAcceptsUMP {
        // The words as the app built them, whatever the list's protocol: the service takes
        // MIDI 1.0 and 2.0 UMP alike and translates for the device.
        return MIDIServer.shared.sendUMP(_MIDIEventPackets(evtlist).flatMap { $0 }, port: port, destination: dest)
    }
    var converter = _UMPConverter()
    for words in _MIDIEventPackets(evtlist) {
        converter.feed(words)
    }
    return MIDIServer.shared.send(converter.messages, port: port, destination: dest)
}

/// `CFString` to `String` on every platform (`as String` bridging on Darwin and corelibs).
func _MIDIString(_ value: CFString) -> String {
    value as String
}

/// An `OSStatus` failure carried through `Result`.
struct _MIDIStatus: Error {
    let code: OSStatus
}
