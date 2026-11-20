import XCTest
import Foundation
#if canImport(CoreMIDIPortable)
@testable import CoreMIDIPortable
#else
@testable import CoreMIDI
#endif

/// The send paths of Sibyl's `MIDISender`, written exactly as the app writes them against
/// Apple's CoreMIDI, so the test also proves the signatures line up.
private final class SibylStyleSender {
    var client = MIDIClientRef()
    var outputPort = MIDIPortRef()

    init?() {
        var status = MIDIClientCreateWithBlock("Sibyl" as CFString, &client) { _ in }
        guard status == noErr else { return nil }
        status = MIDIOutputPortCreate(client, "Sibyl Out" as CFString, &outputPort)
        guard status == noErr else { return nil }
    }

    deinit {
        if outputPort != 0 { MIDIPortDispose(outputPort) }
        if client != 0 { MIDIClientDispose(client) }
    }

    func resolve(_ uniqueID: MIDIUniqueID) -> MIDIEndpointRef? {
        var endpoint = MIDIEndpointRef()
        var type = MIDIObjectType.other
        guard MIDIObjectFindByUniqueID(uniqueID, &endpoint, &type) == noErr, endpoint != 0 else { return nil }
        return endpoint
    }

    @discardableResult
    func sendShort(_ status: UInt8, _ data1: UInt8, _ data2: UInt8, to endpoint: MIDIEndpointRef, byteCount: Int = 3) -> OSStatus {
        let word = (UInt32(0x2) << 28)
            | (UInt32(status) << 16)
            | (UInt32(data1) << 8)
            | UInt32(byteCount == 3 ? data2 : 0)
        var list = MIDIEventList()
        var packet = MIDIEventListInit(&list, ._1_0)
        withUnsafePointer(to: word) { wordPointer in
            packet = MIDIEventListAdd(&list, MemoryLayout<MIDIEventList>.size, packet, 0, 1, wordPointer)
        }
        return MIDISendEventList(outputPort, endpoint, &list)
    }

    @discardableResult
    func sendSysEx(_ bytes: [UInt8], to endpoint: MIDIEndpointRef) -> OSStatus {
        let packetListSize = 1024
        let raw = UnsafeMutableRawPointer.allocate(byteCount: packetListSize,
                                                   alignment: MemoryLayout<MIDIPacketList>.alignment)
        defer { raw.deallocate() }
        let packetList = raw.assumingMemoryBound(to: MIDIPacketList.self)
        var packet = MIDIPacketListInit(packetList)
        packet = bytes.withUnsafeBufferPointer { buffer in
            MIDIPacketListAdd(packetList, packetListSize, packet, 0, bytes.count, buffer.baseAddress!)
        }
        return MIDISend(outputPort, endpoint, packetList)
    }

    static func uniqueID(of endpoint: MIDIEndpointRef) -> MIDIUniqueID {
        var value: MIDIUniqueID = 0
        MIDIObjectGetIntegerProperty(endpoint, kMIDIPropertyUniqueID, &value)
        return value
    }

    static func stringProperty(_ endpoint: MIDIEndpointRef, _ property: CFString) -> String? {
        var value: Unmanaged<CFString>?
        guard MIDIObjectGetStringProperty(endpoint, property, &value) == noErr,
              let value else { return nil }
        return value.takeRetainedValue() as String
    }
}

final class CoreMIDITests: XCTestCase {
    override func setUp() {
        super.setUp()
        _MIDITestHooks.useNullBackend()
        XCTAssertNotNil(_MIDITestHooks.nullBackend, "the tests run on the null backend")
        _MIDITestHooks.setAcceptsUMP(false)
        _MIDITestHooks.resetDestinations()
        _MIDITestHooks.clearSent()
    }

    override func tearDown() {
        _MIDITestHooks.setAcceptsUMP(false)
        super.tearDown()
    }

    private func firstDestination() -> MIDIEndpointRef {
        XCTAssertEqual(MIDIGetNumberOfDestinations(), 2)
        return MIDIGetDestination(0)
    }

    func testClientAndPortCreation() {
        var client = MIDIClientRef()
        XCTAssertEqual(MIDIClientCreateWithBlock("Test" as CFString, &client, nil), noErr)
        XCTAssertNotEqual(client, 0)
        var port = MIDIPortRef()
        XCTAssertEqual(MIDIOutputPortCreate(client, "Out" as CFString, &port), noErr)
        XCTAssertNotEqual(port, 0)
        XCTAssertNotEqual(port, client)
        XCTAssertEqual(SibylStyleSender.stringProperty(port, kMIDIPropertyName), "Out")

        var bogus = MIDIPortRef()
        XCTAssertEqual(MIDIOutputPortCreate(0xDEAD, "x" as CFString, &bogus), kMIDIInvalidClient)

        XCTAssertEqual(MIDIPortDispose(port), noErr)
        XCTAssertEqual(MIDIPortDispose(port), kMIDIInvalidPort)
        XCTAssertEqual(MIDIClientDispose(client), noErr)
        XCTAssertEqual(MIDIClientDispose(client), kMIDIInvalidClient)
    }

    func testDestinationsEnumerateWithNamesAndUniqueIDs() {
        XCTAssertEqual(MIDIGetNumberOfDestinations(), 2)
        let a = MIDIGetDestination(0), b = MIDIGetDestination(1)
        XCTAssertNotEqual(a, 0)
        XCTAssertNotEqual(b, 0)
        XCTAssertNotEqual(a, b)
        XCTAssertEqual(MIDIGetDestination(2), 0)
        XCTAssertEqual(SibylStyleSender.stringProperty(a, kMIDIPropertyName), "Null MIDI Out A")
        XCTAssertEqual(SibylStyleSender.stringProperty(a, kMIDIPropertyDisplayName), "AppKitCross Null MIDI Out A")
        XCTAssertEqual(SibylStyleSender.stringProperty(b, kMIDIPropertyManufacturer), "AppKitCross")
        XCTAssertEqual(SibylStyleSender.stringProperty(b, kMIDIPropertyModel), "Null Output")
        let idA = SibylStyleSender.uniqueID(of: a), idB = SibylStyleSender.uniqueID(of: b)
        XCTAssertNotEqual(idA, kMIDIInvalidUniqueID)
        XCTAssertNotEqual(idA, idB)
        XCTAssertEqual(idA, MIDIServer.uniqueID(name: "Null MIDI Out A", occurrence: 0))

        var value: Int32 = 0
        XCTAssertEqual(MIDIObjectGetIntegerProperty(a, kMIDIPropertyName, &value), kMIDIWrongPropertyType)
        var string: Unmanaged<CFString>?
        XCTAssertEqual(MIDIObjectGetStringProperty(0x7777_7777, kMIDIPropertyName, &string), kMIDIObjectNotFound)
        XCTAssertNil(string)
    }

    func testFindByUniqueIDRoundTrips() {
        let endpoint = firstDestination()
        let id = SibylStyleSender.uniqueID(of: endpoint)
        var found = MIDIObjectRef()
        var type = MIDIObjectType.other
        XCTAssertEqual(MIDIObjectFindByUniqueID(id, &found, &type), noErr)
        XCTAssertEqual(found, endpoint)
        XCTAssertEqual(type, .destination)
        XCTAssertEqual(MIDIObjectFindByUniqueID(12345, &found, &type), kMIDIObjectNotFound)
        XCTAssertEqual(found, 0)
    }

    func testUniqueIDsAreStableAcrossReorderAndDuplicateNames() {
        let id = SibylStyleSender.uniqueID(of: MIDIGetDestination(0))
        var reordered = NullMIDIBackend.defaultDestinations
        reordered.reverse()
        reordered.append(MIDIPlatformDestination(key: "null:9", name: "Null MIDI Out A"))
        _MIDITestHooks.setDestinations(reordered)
        XCTAssertEqual(MIDIGetNumberOfDestinations(), 3)
        XCTAssertEqual(SibylStyleSender.uniqueID(of: MIDIGetDestination(1)), id)
        XCTAssertNotEqual(SibylStyleSender.uniqueID(of: MIDIGetDestination(2)), id)
    }

    func testPacketListSendIncludingSysEx() {
        guard let sender = SibylStyleSender() else { return XCTFail("client") }
        let endpoint = firstDestination()
        let sysEx: [UInt8] = [0xF0, 0x7F, 0x01, 0x02, 0x01, 0x01] + Array("1.50".utf8) + [0x00] + Array("12345678".utf8) + [0xF7]
        XCTAssertEqual(sysEx.count, 20)
        XCTAssertEqual(sender.sendSysEx(sysEx, to: endpoint), noErr)
        XCTAssertEqual(_MIDITestHooks.sent, [.init(destinationName: "Null MIDI Out A", bytes: sysEx, isSysEx: true)])

        // Several packets, running status, and a real-time byte inside a message.
        _MIDITestHooks.clearSent()
        let size = 512
        let raw = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: MemoryLayout<MIDIPacketList>.alignment)
        defer { raw.deallocate() }
        let list = raw.assumingMemoryBound(to: MIDIPacketList.self)
        var packet = MIDIPacketListInit(list)
        let first: [UInt8] = [0x90, 0x3C, 0x7F, 0x3E, 0x60]
        let second: [UInt8] = [0xB1, 0x07, 0xF8, 0x64]
        packet = MIDIPacketListAdd(list, size, packet, 10, first.count, first)
        packet = MIDIPacketListAdd(list, size, packet, 20, second.count, second)
        XCTAssertEqual(list.pointee.numPackets, 2)
        let next = MIDIPacketNext(&list.pointee.packet)
        XCTAssertEqual(next, packet)
        XCTAssertEqual(next.pointee.length, 4)
        XCTAssertEqual(MIDISend(sender.outputPort, endpoint, list), noErr)
        XCTAssertEqual(_MIDITestHooks.sent.map(\.bytes), [[0x90, 0x3C, 0x7F], [0x90, 0x3E, 0x60], [0xF8], [0xB1, 0x07, 0x64]])
    }

    func testPacketListAddMergesSameTimestampAndReportsFullList() {
        let size = MemoryLayout<MIDIPacketList>.size
        let raw = UnsafeMutableRawPointer.allocate(byteCount: 64, alignment: 8)
        defer { raw.deallocate() }
        let list = raw.assumingMemoryBound(to: MIDIPacketList.self)
        var packet = MIDIPacketListInit(list)
        packet = MIDIPacketListAdd(list, 64, packet, 5, 3, [0x80, 0x3C, 0x00])
        packet = MIDIPacketListAdd(list, 64, packet, 5, 3, [0x80, 0x3D, 0x00])
        XCTAssertEqual(list.pointee.numPackets, 1)
        XCTAssertEqual(packet.pointee.length, 6)
        let full = MIDIPacketListAdd(list, 64, packet, 6, 60, [UInt8](repeating: 0x7F, count: 60))
        XCTAssertNil(UnsafeMutablePointer<MIDIPacket>(bitPattern: UInt(bitPattern: full)), "a full list yields NULL like Apple's C function")
        XCTAssertGreaterThan(size, 256)
    }

    func testEventListNoteOnArrivesAsMIDI1Bytes() {
        guard let sender = SibylStyleSender() else { return XCTFail("client") }
        let endpoint = firstDestination()
        XCTAssertEqual(sender.sendShort(0x90, 0x3C, 0x7F, to: endpoint), noErr)
        XCTAssertEqual(sender.sendShort(0xC2, 0x05, 0, to: endpoint, byteCount: 2), noErr)
        XCTAssertEqual(sender.sendShort(0xB0, 0x07, 0x64, to: endpoint), noErr)
        XCTAssertEqual(_MIDITestHooks.sent.map(\.bytes), [[0x90, 0x3C, 0x7F], [0xC2, 0x05], [0xB0, 0x07, 0x64]])
        XCTAssertTrue(_MIDITestHooks.sent.allSatisfy { !$0.isSysEx })
    }

    func testEventListMIDI2AndSysEx7Conversion() {
        guard let sender = SibylStyleSender() else { return XCTFail("client") }
        let endpoint = MIDIGetDestination(1)
        var list = MIDIEventList()
        var packet = MIDIEventListInit(&list, ._2_0)
        // MIDI 2.0 note on, channel 3, note 60, velocity 0xFFFF; then a two-part SysEx7.
        let words: [UInt32] = [0x4093_3C00, 0xFFFF_0000,
                               0x3016_7E7F, 0x0601_0203,
                               0x3032_0405, 0x0000_0000]
        packet = MIDIEventListAdd(&list, MemoryLayout<MIDIEventList>.size, packet, 0, words.count, words)
        XCTAssertEqual(list.numPackets, 1)
        XCTAssertEqual(MIDISendEventList(sender.outputPort, endpoint, &list), noErr)
        XCTAssertEqual(_MIDITestHooks.sent, [
            .init(destinationName: "Null MIDI Out B", bytes: [0x93, 0x3C, 0x7F], isSysEx: false),
            .init(destinationName: "Null MIDI Out B", bytes: [0xF0, 0x7E, 0x7F, 0x06, 0x01, 0x02, 0x03, 0x04, 0x05, 0xF7], isSysEx: true),
        ])
    }

    func testSendErrors() {
        guard let sender = SibylStyleSender() else { return XCTFail("client") }
        var list = MIDIEventList()
        MIDIEventListInit(&list, ._1_0)
        XCTAssertEqual(MIDISendEventList(0xBAD, firstDestination(), &list), kMIDIInvalidPort)
        XCTAssertEqual(MIDISendEventList(sender.outputPort, 0xBAD, &list), kMIDIUnknownEndpoint)
        let removed = MIDIGetDestination(1)
        _MIDITestHooks.setDestinations(Array(NullMIDIBackend.defaultDestinations.prefix(1)))
        XCTAssertEqual(MIDISendEventList(sender.outputPort, removed, &list), kMIDIUnknownEndpoint)
        XCTAssertNil(sender.resolve(SibylStyleSender.uniqueID(of: removed)))
    }

    func testDisposeStopsSending() {
        var sender: SibylStyleSender? = SibylStyleSender()
        let port = sender!.outputPort
        let endpoint = firstDestination()
        sender = nil
        var list = MIDIEventList()
        MIDIEventListInit(&list, ._1_0)
        XCTAssertEqual(MIDISendEventList(port, endpoint, &list), kMIDIInvalidPort)
    }

    func testSetupChangeNotificationFromPoll() {
        let fired = expectation(description: "setup changed")
        fired.assertForOverFulfill = false
        var client = MIDIClientRef()
        XCTAssertEqual(MIDIClientCreateWithBlock("Watcher" as CFString, &client) { notification in
            if notification.pointee.messageID == .msgSetupChanged { fired.fulfill() }
        }, noErr)
        defer { MIDIClientDispose(client) }
        var outputs = NullMIDIBackend.defaultDestinations
        outputs.append(MIDIPlatformDestination(key: "null:2", name: "Hot-plugged Interface", manufacturer: "Acme"))
        _MIDITestHooks.setDestinations(outputs, refresh: false)   // left for the 2-second poll
        wait(for: [fired], timeout: MIDIServer.pollInterval * 3)
        XCTAssertEqual(MIDIGetNumberOfDestinations(), 3)
        XCTAssertNil(SibylStyleSender.stringProperty(MIDIGetDestination(2), kMIDIPropertyModel))
    }

    func testByteStreamParserEdgeCases() {
        var parser = _MIDIByteStreamParser()
        parser.feed([0xF0, 0x01, 0x02])
        parser.feed([0x03, 0xF7, 0xC0, 0x01, 0x02, 0xFE])
        parser.finish()
        XCTAssertEqual(parser.messages, [.sysEx([0xF0, 0x01, 0x02, 0x03, 0xF7]), .short([0xC0, 0x01]), .short([0xC0, 0x02]), .short([0xFE])])
    }

    // MARK: Windows MIDI Services paths (bytes to UMP, UMP passthrough)

    func testWindowsStartupLineCarriesTheRoutes() {
        let routes = "Windows MIDI Services: projection Windows.Devices.Midi2; Windows build 26200; in-box API not registered (0x80040154); no app-local Windows.Devices.Midi2.dll in C:\\App\\"
        XCTAssertEqual(_MIDIWindowsStartupLine(backend: "WinMM backend", detail: "Windows MIDI Services unavailable", routes: routes),
                       "WinMM backend (Windows MIDI Services unavailable) [\(routes)]")
        XCTAssertEqual(_MIDIWindowsStartupLine(backend: "Windows MIDI Services backend", detail: "2 endpoints", routes: " \(routes)\n"),
                       "Windows MIDI Services backend (2 endpoints) [\(routes)]", "trimmed")
        // A forced WinMM never ran the check: no brackets.
        XCTAssertEqual(_MIDIWindowsStartupLine(backend: "WinMM backend", detail: "APPKITWIN_MIDI_BACKEND=winmm", routes: ""),
                       "WinMM backend (APPKITWIN_MIDI_BACKEND=winmm)")
        XCTAssertEqual(_MIDIWindowsStartupLine(backend: "WinMM backend", detail: "", routes: ""), "WinMM backend")
    }

    private func ump(_ bytes: [UInt8]) -> [UInt32] {
        var parser = _MIDIByteStreamParser()
        parser.feed(bytes)
        parser.finish()
        return _MIDIBytesToUMP(parser.messages)
    }

    func testBytesToUMPChannelVoiceAndSystem() {
        XCTAssertEqual(ump([0x90, 0x3C, 0x7F]), [0x2090_3C7F])
        XCTAssertEqual(ump([0xC2, 0x05]), [0x20C2_0500], "program change: two bytes, data 2 zero")
        XCTAssertEqual(ump([0xD3, 0x40]), [0x20D3_4000])
        // Running status: the second note on reuses 0x90.
        XCTAssertEqual(ump([0x90, 0x3C, 0x7F, 0x3E, 0x60]), [0x2090_3C7F, 0x2090_3E60])
        // A real-time byte inside a message goes out first, as type 0x1.
        XCTAssertEqual(ump([0xB1, 0x07, 0xF8, 0x64]), [0x10F8_0000, 0x20B1_0764])
        // System common: song position (2 data bytes), song select (1), tune request (0).
        XCTAssertEqual(ump([0xF2, 0x10, 0x20, 0xF3, 0x05, 0xF6]), [0x10F2_1020, 0x10F3_0500, 0x10F6_0000])
        XCTAssertEqual(_MIDIBytesToUMP([.short([0x80, 0x3C, 0x00])], group: 3), [0x2380_3C00])
    }

    func testBytesToUMPSysExPackets() {
        // Sibyl's 20-byte MSC SysEx: 18 data bytes become start, continue, end of six each.
        let sysEx: [UInt8] = [0xF0, 0x7F, 0x01, 0x02, 0x01, 0x01] + Array("1.50".utf8) + [0x00] + Array("12345678".utf8) + [0xF7]
        XCTAssertEqual(sysEx.count, 20)
        let words = ump(sysEx)
        XCTAssertEqual(words.count, 6)
        XCTAssertEqual(words.enumerated().filter { $0.offset % 2 == 0 }.map { $0.element >> 28 }, [3, 3, 3])
        XCTAssertEqual(words.enumerated().filter { $0.offset % 2 == 0 }.map { ($0.element >> 20) & 0xF }, [1, 2, 3], "start, continue, end")
        XCTAssertEqual(words.enumerated().filter { $0.offset % 2 == 0 }.map { ($0.element >> 16) & 0xF }, [6, 6, 6])
        XCTAssertEqual(words[0], 0x3016_7F01)
        XCTAssertEqual(words[1], 0x0201_0131)   // 02 01 01 '1'
        XCTAssertEqual(words[4], 0x3036_3334)   // end, six bytes: '3' '4'
        XCTAssertEqual(words[5], 0x3536_3738)   // '5' '6' '7' '8'

        // Short ones: complete in one packet; seven bytes as start (6) and end (1).
        XCTAssertEqual(ump([0xF0, 0x7E, 0x7F, 0x06, 0x01, 0xF7]), [0x3004_7E7F, 0x0601_0000])
        XCTAssertEqual(ump([0xF0, 1, 2, 3, 4, 5, 6, 7, 0xF7]), [0x3016_0102, 0x0304_0506, 0x3031_0700, 0x0000_0000])
        XCTAssertEqual(ump([0xF0, 0xF7]), [0x3000_0000, 0x0000_0000])

        // The inverse of the WinMM path's conversion.
        var back = _UMPConverter()
        back.feed(words)
        XCTAssertEqual(back.messages, [.sysEx(sysEx)])
    }

    func testUMPPassthroughOnUMPBackend() {
        guard let sender = SibylStyleSender() else { return XCTFail("client") }
        _MIDITestHooks.setAcceptsUMP(true)
        let endpoint = MIDIGetDestination(1)

        // MIDI 2.0 event list: the words arrive exactly as built (group 1 kept).
        var list = MIDIEventList()
        var packet = MIDIEventListInit(&list, ._2_0)
        let words: [UInt32] = [0x4193_3C00, 0xFFFF_0000,
                               0x3016_7E7F, 0x0601_0203,
                               0x3032_0405, 0x0000_0000,
                               0x10F8_0000]
        packet = MIDIEventListAdd(&list, MemoryLayout<MIDIEventList>.size, packet, 0, words.count, words)
        XCTAssertEqual(MIDISendEventList(sender.outputPort, endpoint, &list), noErr)
        XCTAssertEqual(_MIDITestHooks.sentUMP, [.init(destinationName: "Null MIDI Out B", words: words)])
        XCTAssertEqual(_MIDITestHooks.sent, [], "nothing went through the byte path")

        // A MIDI 1.0 event list (Sibyl's sendShort) is not converted either.
        _MIDITestHooks.clearSent()
        XCTAssertEqual(sender.sendShort(0x90, 0x3C, 0x7F, to: endpoint), noErr)
        XCTAssertEqual(_MIDITestHooks.sentUMP.map(\.words), [[0x2090_3C7F]])

        // A byte packet list is converted to UMP.
        _MIDITestHooks.clearSent()
        let sysEx: [UInt8] = [0xF0, 0x7E, 0x7F, 0x06, 0x01, 0xF7]
        XCTAssertEqual(sender.sendSysEx(sysEx, to: endpoint), noErr)
        XCTAssertEqual(_MIDITestHooks.sentUMP.map(\.words), [[0x3004_7E7F, 0x0601_0000]])

        // Errors are the same as on the byte path.
        XCTAssertEqual(MIDISendEventList(0xBAD, endpoint, &list), kMIDIInvalidPort)
        XCTAssertEqual(MIDISendEventList(sender.outputPort, 0xBAD, &list), kMIDIUnknownEndpoint)
    }
}
