// The in-process stand-in for the MIDI server: object references, clients and ports, the
// destination snapshot with stable unique IDs, setup-change polling and notifications.

import Foundation
import Dispatch

final class MIDIServer: @unchecked Sendable {
    static let shared = MIDIServer()

    /// Seconds between setup polls while a client exists.
    static let pollInterval = 2.0
    /// A non-forced rescan reuses a snapshot younger than this.
    static let snapshotLifetime = 0.5

    private struct Client {
        var name: String
        var notify: MIDINotifyBlock?
    }

    private struct Port {
        var client: MIDIClientRef
        var name: String
    }

    private struct Endpoint {
        var uniqueID: MIDIUniqueID
        var destination: MIDIPlatformDestination
    }

    private struct NotifyBox: @unchecked Sendable {
        let block: MIDINotifyBlock
    }

    private let lock = NSLock()
    private let backend: MIDIPlatformBackend
    private var nextRef: MIDIObjectRef = 0x0010_0000
    private var clients: [MIDIClientRef: Client] = [:]
    private var ports: [MIDIPortRef: Port] = [:]
    private var endpoints: [MIDIEndpointRef: Endpoint] = [:]
    private var refByUniqueID: [MIDIUniqueID: MIDIEndpointRef] = [:]
    private var online: [MIDIEndpointRef] = []
    private var opened: Set<MIDIEndpointRef> = []
    private var lastScan: DispatchTime?
    private var timer: DispatchSourceTimer?
    private var announced = false

    let notificationQueue = DispatchQueue(label: "AppKitCross.CoreMIDI.notifications")
    private let pollQueue = DispatchQueue(label: "AppKitCross.CoreMIDI.setup-poll", qos: .utility)

    init(backend: MIDIPlatformBackend = _makeMIDIBackend()) {
        self.backend = backend
    }

    func withBackend<T>(_ body: (MIDIPlatformBackend) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body(backend)
    }

    private func allocateRef() -> MIDIObjectRef {
        nextRef += 1
        return nextRef
    }

    // MARK: Unique IDs

    /// FNV-1a of "name#occurrence", folded to a positive, non-zero `MIDIUniqueID`.
    static func uniqueID(name: String, occurrence: Int) -> MIDIUniqueID {
        var hash: UInt32 = 0x811C_9DC5
        for byte in "\(name)#\(occurrence)".utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 0x0100_0193
        }
        let value = MIDIUniqueID(bitPattern: hash & 0x7FFF_FFFF)
        return value == kMIDIInvalidUniqueID ? 1 : value
    }

    // MARK: Snapshot

    /// Rescans the backend (`force`, or when the snapshot is stale); on a change closes the
    /// open outputs (platform indices may have moved) and notifies every client.
    func refresh(force: Bool) {
        var blocks: [NotifyBox] = []
        lock.lock()
        let now = DispatchTime.now()
        if !force, let lastScan, now.uptimeNanoseconds - lastScan.uptimeNanoseconds < UInt64(Self.snapshotLifetime * 1e9) {
            lock.unlock()
            return
        }
        let firstScan = lastScan == nil
        lastScan = now
        let scanned = backend.destinations()
        var occurrences: [String: Int] = [:]
        var used = Set<MIDIUniqueID>()
        var newOnline: [MIDIEndpointRef] = []
        var changed = false
        for destination in scanned {
            let occurrence = occurrences[destination.name, default: 0]
            occurrences[destination.name] = occurrence + 1
            var id = Self.uniqueID(name: destination.name, occurrence: occurrence)
            while used.contains(id) || id == kMIDIInvalidUniqueID { id = (id &+ 1) & 0x7FFF_FFFF }
            used.insert(id)
            let ref: MIDIEndpointRef
            if let existing = refByUniqueID[id] {
                ref = existing
                if endpoints[ref]?.destination != destination { changed = true }
            } else {
                ref = allocateRef()
                refByUniqueID[id] = ref
            }
            endpoints[ref] = Endpoint(uniqueID: id, destination: destination)
            newOnline.append(ref)
        }
        if newOnline != online { changed = true }
        online = newOnline
        if changed && !firstScan {
            for ref in opened {
                if let endpoint = endpoints[ref] { backend.close(endpoint.destination) }
            }
            opened = []
            blocks = clients.values.compactMap { $0.notify.map(NotifyBox.init) }
        }
        lock.unlock()

        for box in blocks {
            notificationQueue.async {
                var notification = MIDINotification(messageID: .msgSetupChanged, messageSize: UInt32(MemoryLayout<MIDINotification>.size))
                withUnsafePointer(to: &notification) { box.block($0) }
            }
        }
    }

    private func startPollingLocked() {
        guard timer == nil else { return }
        let source = DispatchSource.makeTimerSource(queue: pollQueue)
        source.schedule(deadline: .now() + Self.pollInterval, repeating: Self.pollInterval)
        source.setEventHandler { [weak self] in self?.refresh(force: true) }
        source.resume()
        timer = source
    }

    private func stopPollingLocked() {
        timer?.cancel()
        timer = nil
        for ref in opened {
            if let endpoint = endpoints[ref] { backend.close(endpoint.destination) }
        }
        opened = []
    }

    // MARK: Clients and ports

    func createClient(name: String, notify: MIDINotifyBlock?, out: UnsafeMutablePointer<MIDIClientRef>) -> OSStatus {
        refresh(force: false)   // the first scan establishes the baseline without notifying
        lock.lock()
        defer { lock.unlock() }
        if !announced {
            announced = true
            if let line = backend.startupLine(destinationCount: online.count) {
                FileHandle.standardError.write(Data("CoreMIDI: \(line)\n".utf8))
            }
        }
        let ref = allocateRef()
        clients[ref] = Client(name: name, notify: notify)
        startPollingLocked()
        out.pointee = ref
        return noErr
    }

    func disposeClient(_ client: MIDIClientRef) -> OSStatus {
        lock.lock()
        defer { lock.unlock() }
        guard clients.removeValue(forKey: client) != nil else { return kMIDIInvalidClient }
        ports = ports.filter { $0.value.client != client }
        if clients.isEmpty { stopPollingLocked() }
        return noErr
    }

    func createOutputPort(client: MIDIClientRef, name: String, out: UnsafeMutablePointer<MIDIPortRef>) -> OSStatus {
        lock.lock()
        defer { lock.unlock() }
        guard clients[client] != nil else { return kMIDIInvalidClient }
        let ref = allocateRef()
        ports[ref] = Port(client: client, name: name)
        out.pointee = ref
        return noErr
    }

    func disposePort(_ port: MIDIPortRef) -> OSStatus {
        lock.lock()
        defer { lock.unlock() }
        return ports.removeValue(forKey: port) == nil ? kMIDIInvalidPort : noErr
    }

    // MARK: Destinations and properties

    func destinationCount() -> Int {
        refresh(force: false)
        lock.lock()
        defer { lock.unlock() }
        return online.count
    }

    func destination(at index: Int) -> MIDIEndpointRef {
        lock.lock()
        defer { lock.unlock() }
        return online.indices.contains(index) ? online[index] : 0
    }

    func find(uniqueID: MIDIUniqueID, outObject: UnsafeMutablePointer<MIDIObjectRef>?, outType: UnsafeMutablePointer<MIDIObjectType>?) -> OSStatus {
        refresh(force: false)
        lock.lock()
        defer { lock.unlock() }
        if let ref = refByUniqueID[uniqueID], online.contains(ref) {
            outObject?.pointee = ref
            outType?.pointee = .destination
            return noErr
        }
        outObject?.pointee = 0
        outType?.pointee = .other
        return kMIDIObjectNotFound
    }

    func integerProperty(_ object: MIDIObjectRef, _ property: String, _ out: UnsafeMutablePointer<Int32>) -> OSStatus {
        lock.lock()
        defer { lock.unlock() }
        guard let endpoint = endpoints[object] else {
            return clients[object] != nil || ports[object] != nil ? kMIDIUnknownProperty : kMIDIObjectNotFound
        }
        switch property {
        case _MIDIString(kMIDIPropertyUniqueID):
            out.pointee = endpoint.uniqueID
            return noErr
        case _MIDIString(kMIDIPropertyName), _MIDIString(kMIDIPropertyDisplayName),
             _MIDIString(kMIDIPropertyManufacturer), _MIDIString(kMIDIPropertyModel):
            return kMIDIWrongPropertyType
        default:
            return kMIDIUnknownProperty
        }
    }

    func stringProperty(_ object: MIDIObjectRef, _ property: String) -> Result<String, _MIDIStatus> {
        lock.lock()
        defer { lock.unlock() }
        let value: String?
        if let endpoint = endpoints[object] {
            let destination = endpoint.destination
            switch property {
            case _MIDIString(kMIDIPropertyName): value = destination.name
            case _MIDIString(kMIDIPropertyDisplayName): value = destination.displayName ?? destination.name
            case _MIDIString(kMIDIPropertyManufacturer): value = destination.manufacturer
            case _MIDIString(kMIDIPropertyModel): value = destination.model
            case _MIDIString(kMIDIPropertyUniqueID): return .failure(_MIDIStatus(code: kMIDIWrongPropertyType))
            default: value = nil
            }
        } else if let name = clients[object]?.name ?? ports[object]?.name {
            value = property == _MIDIString(kMIDIPropertyName) ? name : nil
        } else {
            return .failure(_MIDIStatus(code: kMIDIObjectNotFound))
        }
        guard let value else { return .failure(_MIDIStatus(code: kMIDIUnknownProperty)) }
        return .success(value)
    }

    // MARK: Sending

    /// Whether `MIDISend`/`MIDISendEventList` should hand the backend UMP words.
    var backendAcceptsUMP: Bool {
        lock.lock()
        defer { lock.unlock() }
        return backend.acceptsUMP
    }

    /// Checks the port and endpoint and opens the destination on first use. Under the lock.
    private func openedDestinationLocked(port: MIDIPortRef, ref: MIDIEndpointRef) -> Result<MIDIPlatformDestination, _MIDIStatus> {
        guard ports[port] != nil else { return .failure(_MIDIStatus(code: kMIDIInvalidPort)) }
        guard let endpoint = endpoints[ref] else {
            return .failure(_MIDIStatus(code: clients[ref] != nil || ports[ref] != nil ? kMIDIWrongEndpointType : kMIDIUnknownEndpoint))
        }
        guard online.contains(ref) else { return .failure(_MIDIStatus(code: kMIDIUnknownEndpoint)) }
        if !opened.contains(ref) {
            let status = backend.open(endpoint.destination)
            guard status == noErr else { return .failure(_MIDIStatus(code: status)) }
            opened.insert(ref)
        }
        return .success(endpoint.destination)
    }

    func sendUMP(_ words: [UInt32], port: MIDIPortRef, destination ref: MIDIEndpointRef) -> OSStatus {
        lock.lock()
        defer { lock.unlock() }
        switch openedDestinationLocked(port: port, ref: ref) {
        case .failure(let status): return status.code
        case .success(let destination): return words.isEmpty ? noErr : backend.sendUMP(words, to: destination)
        }
    }

    func send(_ messages: [_MIDIMessage], port: MIDIPortRef, destination ref: MIDIEndpointRef) -> OSStatus {
        lock.lock()
        defer { lock.unlock() }
        let destination: MIDIPlatformDestination
        switch openedDestinationLocked(port: port, ref: ref) {
        case .failure(let status): return status.code
        case .success(let value): destination = value
        }
        for message in messages {
            let status: OSStatus
            switch message {
            case .short(let bytes): status = backend.sendShort(bytes, to: destination)
            case .sysEx(let bytes): status = backend.sendLong(bytes, to: destination)
            }
            if status != noErr { return status }
        }
        return noErr
    }
}
