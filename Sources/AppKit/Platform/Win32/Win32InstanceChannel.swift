// The single-instance channel on Windows (ADR-0045, Platform/InstanceChannel.swift): a named
// pipe per identity, user and session. The first process creates it with
// FILE_FLAG_FIRST_PIPE_INSTANCE (so of two processes racing exactly one wins) and serves it
// from a thread; a later launch connects, lets the listener take the foreground
// (AllowSetForegroundWindow on the server's process id: only the process the user just started
// may, and it hands that right on), writes its message, and waits for a one-byte reply.

#if os(Windows)
import Foundation
import WinSDK

/// INVALID_HANDLE_VALUE (-1) is a macro the importer does not bring over.
private func isValid(_ h: HANDLE?) -> Bool { h.map { Int(bitPattern: $0) != -1 } ?? false }

final class Win32InstanceChannel: PlatformInstanceChannel, @unchecked Sendable {
    let name: String
    private var server: HANDLE? = nil
    private var stopped = false
    private let lock = NSLock()

    init(identifier: String) {
        var session: DWORD = 0
        ProcessIdToSessionId(GetCurrentProcessId(), &session)
        let user = PlatformInstanceChannels.sanitized(ProcessInfo.processInfo.environment["USERNAME"] ?? "user")
        name = "\\\\.\\pipe\\AppKitCross-\(PlatformInstanceChannels.sanitized(identifier))-\(user)-\(session)"
    }

    func send(_ message: Data) -> Bool {
        var opened: HANDLE? = nil
        for _ in 0..<3 {
            opened = name.withCString(encodedAs: UTF16.self) {
                CreateFileW($0, DWORD(GENERIC_READ) | DWORD(GENERIC_WRITE), 0, nil, DWORD(OPEN_EXISTING), 0, nil)
            }
            if isValid(opened) { break }
            guard GetLastError() == DWORD(ERROR_PIPE_BUSY) else { return false }
            _ = name.withCString(encodedAs: UTF16.self) { WaitNamedPipeW($0, 2000) }
        }
        guard isValid(opened), let pipe = opened else { return false }
        defer { CloseHandle(pipe) }
        var serverPID: ULONG = 0
        if GetNamedPipeServerProcessId(pipe, &serverPID) { AllowSetForegroundWindow(DWORD(serverPID)) }
        // The message, length-prefixed (the pipe stays open for the reply).
        var length = UInt32(message.count).littleEndian
        var frame = Data(bytes: &length, count: 4)
        frame.append(message)
        var written: DWORD = 0
        let ok = frame.withUnsafeBytes { WriteFile(pipe, $0.baseAddress, DWORD($0.count), &written, nil) }
        guard ok, written == DWORD(frame.count) else { return false }
        var ack: UInt8 = 0
        var read: DWORD = 0
        return ReadFile(pipe, &ack, 1, &read, nil) && read == 1
    }

    func listen(_ handler: @escaping @Sendable (Data) -> Void) -> Bool {
        guard let first = makeInstance(first: true) else { return false }
        lock.lock(); server = first; lock.unlock()
        let thread = Thread { [weak self] in
            var current: HANDLE? = first
            while let pipe = current {
                let connected = ConnectNamedPipe(pipe, nil) || GetLastError() == DWORD(ERROR_PIPE_CONNECTED)
                guard let self else { CloseHandle(pipe); return }
                self.lock.lock(); let stop = self.stopped; self.lock.unlock()
                if stop { CloseHandle(pipe); return }
                if connected, let message = Win32InstanceChannel.readFrame(pipe) {
                    var ack: UInt8 = 1
                    var written: DWORD = 0
                    _ = WriteFile(pipe, &ack, 1, &written, nil)
                    FlushFileBuffers(pipe)
                    if !message.isEmpty { handler(message) }
                }
                DisconnectNamedPipe(pipe)
                current = pipe
            }
        }
        thread.name = "AppKitCross instance channel"
        thread.start()
        return true
    }

    private func makeInstance(first: Bool) -> HANDLE? {
        let openMode = DWORD(PIPE_ACCESS_DUPLEX) | (first ? DWORD(FILE_FLAG_FIRST_PIPE_INSTANCE) : 0)
        let pipeMode = DWORD(PIPE_TYPE_BYTE) | DWORD(PIPE_READMODE_BYTE) | DWORD(PIPE_WAIT) | DWORD(PIPE_REJECT_REMOTE_CLIENTS)
        let h = name.withCString(encodedAs: UTF16.self) {
            CreateNamedPipeW($0, openMode, pipeMode, 1, 4096, 64 * 1024, 0, nil)
        }
        return isValid(h) ? h : nil
    }

    private static func readFrame(_ pipe: HANDLE) -> Data? {
        func readExactly(_ count: Int) -> Data? {
            var out = Data()
            var buffer = [UInt8](repeating: 0, count: min(max(count, 1), 64 * 1024))
            while out.count < count {
                var got: DWORD = 0
                let want = DWORD(min(buffer.count, count - out.count))
                guard ReadFile(pipe, &buffer, want, &got, nil), got > 0 else { return nil }
                out.append(buffer, count: Int(got))
            }
            return out
        }
        guard let header = readExactly(4) else { return nil }
        let length = header.withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self)) }
        guard length <= 16 * 1024 * 1024 else { return nil }
        return length == 0 ? Data() : readExactly(Int(length))
    }

    func close() {
        lock.lock()
        stopped = true
        let h = server
        server = nil
        lock.unlock()
        guard h != nil else { return }
        // Wake the thread blocked in ConnectNamedPipe; it sees `stopped` and closes the pipe.
        let wake = name.withCString(encodedAs: UTF16.self) { CreateFileW($0, DWORD(GENERIC_READ) | DWORD(GENERIC_WRITE), 0, nil, DWORD(OPEN_EXISTING), 0, nil) }
        if isValid(wake), let wake { CloseHandle(wake) }
    }
}
#endif
