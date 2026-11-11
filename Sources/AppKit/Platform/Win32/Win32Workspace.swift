// The workspace on Windows (ADR-0022): the shell behind `PlatformWorkspace`. Opening goes
// through ShellExecute (the registered handler, the default browser), revealing through
// Explorer's folder-and-select, icons come from the shell's system image lists, file
// associations from AssocQueryString and the registered handler list, the trash is the
// Recycle Bin (SHFileOperation with undo), the running applications are the processes
// that own top-level windows (what the taskbar shows) plus those launched here, the
// badge is a taskbar overlay icon and the application icon the windows' WM_SETICON;
// the accessibility options are SystemParametersInfo's and the personalization
// registry's. Events: a WinEvent hook for the foreground window, a hidden top-level
// window for the WM_SETTINGCHANGE, WM_POWERBROADCAST and WM_WTSSESSION_CHANGE
// broadcasts (message-only windows receive none), and a timer that diffs the window
// list for launches and terminations. The COM pieces live in cd2d_shell.cpp.
//
// Nothing of AppKit runs inside a callback the system owns. An out-of-context WinEvent
// hook is delivered through a kernel user callback (from inside GetMessage, or from the
// shell's own message pump while ShellExecuteEx is still running): a Swift trap there is
// a fatal user-callback exception (0xC000041D), and the activation bookkeeping would run
// re-entrantly inside the call that opened the document. So the hook only posts the event
// to the broadcast window, and while a shell call is in progress every event, broadcast
// and poll is queued and replayed from the next message after the call returns.

#if os(Windows)
import Foundation
import WinSDK
import CoreGraphics
import CD2D

@MainActor
final class Win32Workspace: PlatformWorkspace {
    private unowned let backend: Win32Backend
    weak var observer: (any PlatformWorkspaceObserver)?
    private var monitoring = false
    /// The hidden top-level window that receives broadcasts; its class is the message
    /// window's, so `Win32Backend.messageProc` forwards to `handle(message:)`.
    private var broadcastWindow: HWND?
    private var foregroundHook: HWINEVENTHOOK?
    private var minimizeHook: HWINEVENTHOOK?
    private static let pollTimer: UINT_PTR = 7
    /// Processes launched here (their pid), listed until they exit even without windows.
    private var launched: [DWORD: PlatformRunningApplication] = [:]
    private var lastPIDs: Set<DWORD> = []
    private var lastActivePID: DWORD? = nil
    private var hiddenPIDs: Set<DWORD> = []
    private var overlayIcon: HICON?
    private var applicationIcon: HICON?
    private var applicationSmallIcon: HICON?
    private var overlayDescription: [WCHAR] = [0]
    /// The broadcast window, for the hook callback (which runs outside the actor).
    nonisolated(unsafe) private static var broadcastHWND: HWND?
    /// Posted by the WinEvent hook: wParam the event, lParam the process id.
    static let eventMessage: UINT = UINT(WM_APP) + 0x57
    /// Posted after a shell call returns with work queued meanwhile.
    static let kickMessage: UINT = UINT(WM_APP) + 0x58
    /// Nesting depth of shell calls (ShellExecuteEx, SHOpenFolderAndSelectItems, ...) that
    /// may pump messages on this thread; workspace work is deferred while it is non-zero.
    private var shellCallDepth = 0
    private var deferred: [@MainActor (Win32Workspace) -> Void] = []
    private var trace: Bool { NSView._traceInvalidation }

    init(backend: Win32Backend) {
        self.backend = backend
    }

    /// Runs a shell call that may pump messages: events arriving meanwhile wait until the
    /// next message after it returns, so nothing re-enters the caller.
    private func shellCall<T>(_ body: () -> T) -> T {
        shellCallDepth += 1
        defer {
            shellCallDepth -= 1
            if shellCallDepth == 0, !deferred.isEmpty, let hwnd = broadcastWindow { _ = PostMessageW(hwnd, Win32Workspace.kickMessage, 0, 0) }
        }
        return body()
    }

    private func perform(_ work: @escaping @MainActor (Win32Workspace) -> Void) {
        if shellCallDepth > 0 { deferred.append(work) } else { work(self) }
    }

    private func notify(_ event: PlatformWorkspaceEvent) { perform { $0.observer?.platformWorkspaceDidObserve(event) } }

    // MARK: Monitoring

    func startMonitoring() {
        guard !monitoring else { return }
        monitoring = true
        broadcastWindow = backend.makeBroadcastWindow()
        Win32Workspace.broadcastHWND = broadcastWindow
        if let hwnd = broadcastWindow {
            cd2d_shell_register_notifications(UnsafeMutableRawPointer(hwnd))
            _ = SetTimer(hwnd, Win32Workspace.pollTimer, 2000, nil)
        }
        foregroundHook = SetWinEventHook(DWORD(EVENT_SYSTEM_FOREGROUND), DWORD(EVENT_SYSTEM_FOREGROUND), nil, Win32Workspace.winEventProc, 0, 0, DWORD(WINEVENT_OUTOFCONTEXT))
        minimizeHook = SetWinEventHook(DWORD(EVENT_SYSTEM_MINIMIZESTART), DWORD(EVENT_SYSTEM_MINIMIZEEND), nil, Win32Workspace.winEventProc, 0, 0, DWORD(WINEVENT_OUTOFCONTEXT))
        let snapshot = windowedProcesses()
        lastPIDs = Set(snapshot.keys)
        lastActivePID = foregroundPID()
        hiddenPIDs = Set(snapshot.filter { $0.value.allMinimized }.keys)
    }

    /// Runs inside a kernel user callback: nothing but a PostMessage.
    private static let winEventProc: WINEVENTPROC = { _, event, hwnd, _, _, _, _ in
        guard let hwnd, let target = Win32Workspace.broadcastHWND else { return }
        var pid: DWORD = 0
        GetWindowThreadProcessId(hwnd, &pid)
        guard pid != 0 else { return }
        _ = PostMessageW(target, Win32Workspace.eventMessage, WPARAM(event), LPARAM(Int(pid)))
    }

    private func foregroundDidChange(to pid: DWORD) {
        guard pid != lastActivePID else { return }
        lastActivePID = pid
        observer?.platformWorkspaceDidObserve(.applicationDidActivate(processIdentifier: Int32(bitPattern: pid)))
    }

    private func minimizationDidChange(pid: DWORD) {
        guard pid != GetCurrentProcessId() else { return }
        let windows = topLevelWindows().filter { $0.pid == pid }
        guard !windows.isEmpty else { return }
        let hidden = windows.allSatisfy { IsIconic($0.hwnd) }
        if hidden, !hiddenPIDs.contains(pid) {
            hiddenPIDs.insert(pid)
            observer?.platformWorkspaceDidObserve(.applicationDidHide(processIdentifier: Int32(bitPattern: pid)))
        } else if !hidden, hiddenPIDs.contains(pid) {
            hiddenPIDs.remove(pid)
            observer?.platformWorkspaceDidObserve(.applicationDidUnhide(processIdentifier: Int32(bitPattern: pid)))
        }
    }

    /// Broadcasts, the hook's posted events and the poll timer, from the backend's message
    /// window procedure. Pointers in lParam are read here; the work itself may be deferred.
    func handle(message: UINT, wParam: WPARAM, lParam: LPARAM) -> Bool {
        switch message {
        case UINT(WM_TIMER):
            guard wParam == Win32Workspace.pollTimer else { return false }
            perform { $0.pollWindowList() }
        case Win32Workspace.eventMessage:
            let event = DWORD(truncatingIfNeeded: wParam)
            let pid = DWORD(truncatingIfNeeded: lParam)
            perform { ws in
                switch event {
                case DWORD(EVENT_SYSTEM_FOREGROUND): ws.foregroundDidChange(to: pid)
                case DWORD(EVENT_SYSTEM_MINIMIZESTART), DWORD(EVENT_SYSTEM_MINIMIZEEND): ws.minimizationDidChange(pid: pid)
                default: break
                }
            }
        case Win32Workspace.kickMessage:
            guard shellCallDepth == 0 else { return true }
            let work = deferred
            deferred = []
            for w in work { w(self) }
        case UINT(WM_SETTINGCHANGE):
            notify(.accessibilityDisplayOptionsDidChange)
        case UINT(WM_POWERBROADCAST):
            switch Int(wParam) {
            case 0x4: notify(.willSleep)                      // PBT_APMSUSPEND
            case 0x12, 0x7: notify(.didWake)                 // PBT_APMRESUMEAUTOMATIC, PBT_APMRESUMESUSPEND
            case 0x8013:                                     // PBT_POWERSETTINGCHANGE
                var state: UInt32 = 0
                if cd2d_shell_display_state(UnsafeRawPointer(bitPattern: Int(lParam)), &state) {
                    notify(state == 0 ? .screensDidSleep : .screensDidWake)
                }
            default: break
            }
        case 0x02B1:                                         // WM_WTSSESSION_CHANGE
            switch Int(wParam) {
            case 0x1, 0x8: notify(.sessionDidBecomeActive)   // WTS_CONSOLE_CONNECT, WTS_SESSION_UNLOCK
            case 0x2, 0x7: notify(.sessionDidResignActive)   // WTS_CONSOLE_DISCONNECT, WTS_SESSION_LOCK
            default: break
            }
        default:
            return false
        }
        return true
    }

    private func pollWindowList() {
        let snapshot = windowedProcesses()
        let pids = Set(snapshot.keys)
        for pid in pids.subtracting(lastPIDs) where pid != GetCurrentProcessId() {
            if let app = runningApplication(withProcessIdentifier: Int32(bitPattern: pid)) { observer?.platformWorkspaceDidObserve(.applicationDidLaunch(app)) }
        }
        for pid in lastPIDs.subtracting(pids) where launched[pid] == nil {
            observer?.platformWorkspaceDidObserve(.applicationDidTerminate(processIdentifier: Int32(bitPattern: pid)))
        }
        for (pid, _) in launched where !processExists(pid) {
            launched[pid] = nil
            if !pids.contains(pid) { observer?.platformWorkspaceDidObserve(.applicationDidTerminate(processIdentifier: Int32(bitPattern: pid))) }
        }
        lastPIDs = pids
        if let fg = foregroundPID(), fg != lastActivePID { foregroundDidChange(to: fg) }
    }

    // MARK: Windows and processes

    private struct TopLevel { var hwnd: HWND; var pid: DWORD }
    private final class WindowList { var items: [TopLevel] = [] }

    /// The visible, unowned, non-tool top-level windows: the taskbar's buttons.
    private func topLevelWindows() -> [TopLevel] {
        let list = WindowList()
        let context = Unmanaged.passUnretained(list).toOpaque()
        _ = EnumWindows({ hwnd, lParam in
            guard let hwnd, let lParam = UnsafeRawPointer(bitPattern: Int(lParam)) else { return true }
            let list = Unmanaged<WindowList>.fromOpaque(lParam).takeUnretainedValue()
            guard IsWindowVisible(hwnd), GetWindow(hwnd, UINT(GW_OWNER)) == nil else { return true }
            let exStyle = GetWindowLongPtrW(hwnd, GWL_EXSTYLE)
            guard exStyle & LONG_PTR(WS_EX_TOOLWINDOW) == 0 else { return true }
            // Cloaked (UWP background, virtual-desktop) windows are not on the taskbar.
            var cloaked: DWORD = 0
            if DwmGetWindowAttribute(hwnd, 14 /* DWMWA_CLOAKED */, &cloaked, DWORD(MemoryLayout<DWORD>.size)) == S_OK, cloaked != 0 { return true }
            var pid: DWORD = 0
            GetWindowThreadProcessId(hwnd, &pid)
            if pid != 0 { list.items.append(TopLevel(hwnd: hwnd, pid: pid)) }
            return true
        }, LPARAM(Int(bitPattern: context)))
        return list.items
    }

    private struct ProcessWindows { var windows: [HWND]; var allMinimized: Bool }

    private func windowedProcesses() -> [DWORD: ProcessWindows] {
        var result: [DWORD: ProcessWindows] = [:]
        for w in topLevelWindows() {
            let iconic = IsIconic(w.hwnd)
            if var p = result[w.pid] { p.windows.append(w.hwnd); p.allMinimized = p.allMinimized && iconic; result[w.pid] = p }
            else { result[w.pid] = ProcessWindows(windows: [w.hwnd], allMinimized: iconic) }
        }
        return result
    }

    private func foregroundPID() -> DWORD? {
        guard let fg = GetForegroundWindow() else { return nil }
        var pid: DWORD = 0
        GetWindowThreadProcessId(fg, &pid)
        return pid == 0 ? nil : pid
    }

    private func processExists(_ pid: DWORD) -> Bool {
        guard let h = OpenProcess(DWORD(PROCESS_QUERY_LIMITED_INFORMATION), false, pid) else { return false }
        defer { CloseHandle(h) }
        var code: DWORD = 0
        return GetExitCodeProcess(h, &code) && code == 259 /* STILL_ACTIVE */
    }

    private func executablePath(_ pid: DWORD) -> String? {
        guard let h = OpenProcess(DWORD(PROCESS_QUERY_LIMITED_INFORMATION), false, pid) else { return nil }
        defer { CloseHandle(h) }
        var buffer = [WCHAR](repeating: 0, count: 1024)
        var size = DWORD(buffer.count)
        guard QueryFullProcessImageNameW(h, 0, &buffer, &size), size > 0 else { return nil }
        return String(decoding: buffer[0..<Int(size)], as: UTF16.self)
    }

    private func launchDate(_ pid: DWORD) -> Date? {
        guard let h = OpenProcess(DWORD(PROCESS_QUERY_LIMITED_INFORMATION), false, pid) else { return nil }
        defer { CloseHandle(h) }
        var creation = FILETIME(), exit = FILETIME(), kernel = FILETIME(), user = FILETIME()
        guard GetProcessTimes(h, &creation, &exit, &kernel, &user) else { return nil }
        let ticks = (UInt64(creation.dwHighDateTime) << 32) | UInt64(creation.dwLowDateTime)
        return Date(timeIntervalSince1970: Double(ticks) / 10_000_000 - 11_644_473_600)
    }

    private func fileDescription(_ exe: String) -> String? {
        var buffer = [UInt16](repeating: 0, count: 512)
        let ok = exe.withCString(encodedAs: UTF16.self) { cd2d_shell_file_description($0, &buffer, UInt32(buffer.count)) }
        guard ok else { return nil }
        let s = String(decoding: buffer.prefix { $0 != 0 }, as: UTF16.self)
        return s.isEmpty ? nil : s
    }

    private func appUserModelID(_ pid: DWORD) -> String? {
        var buffer = [UInt16](repeating: 0, count: 512)
        guard cd2d_shell_app_user_model_id(pid, &buffer, UInt32(buffer.count)) else { return nil }
        return String(decoding: buffer.prefix { $0 != 0 }, as: UTF16.self)
    }

    private func application(pid: DWORD, windows: ProcessWindows?) -> PlatformRunningApplication? {
        if let l = launched[pid], windows == nil { return l }
        guard let exe = executablePath(pid) else { return launched[pid] }
        let url = URL(fileURLWithPath: exe)
        let base = url.deletingPathExtension().lastPathComponent
        let foreground = foregroundPID()
        return PlatformRunningApplication(processIdentifier: Int32(bitPattern: pid), localizedName: fileDescription(exe) ?? base,
                                          bundleIdentifier: appUserModelID(pid) ?? base.lowercased(), executableURL: url, applicationURL: url,
                                          launchDate: launchDate(pid), isActive: foreground == pid, isHidden: windows?.allMinimized ?? false,
                                          hasWindows: windows != nil)
    }

    var runningApplications: [PlatformRunningApplication] {
        let me = GetCurrentProcessId()
        var result: [PlatformRunningApplication] = []
        let windowed = windowedProcesses()
        for (pid, windows) in windowed where pid != me {
            if let app = application(pid: pid, windows: windows) { result.append(app) }
        }
        for (pid, app) in launched where windowed[pid] == nil && pid != me && processExists(pid) { result.append(app) }
        return result.sorted { $0.processIdentifier < $1.processIdentifier }
    }

    var frontmostProcessIdentifier: Int32? { foregroundPID().map { Int32(bitPattern: $0) } }

    func runningApplication(withProcessIdentifier pid: Int32) -> PlatformRunningApplication? {
        let dwPID = DWORD(bitPattern: pid)
        return application(pid: dwPID, windows: windowedProcesses()[dwPID])
    }

    private func windows(of pid: Int32) -> [HWND] { windowedProcesses()[DWORD(bitPattern: pid)]?.windows ?? [] }

    func activate(processIdentifier pid: Int32) -> Bool {
        let ws = windows(of: pid)
        guard let main = ws.first(where: { !IsIconic($0) }) ?? ws.first else { return false }
        if IsIconic(main) { ShowWindow(main, SW_RESTORE) }
        return SetForegroundWindow(main)
    }
    func hide(processIdentifier pid: Int32) -> Bool {
        let ws = windows(of: pid)
        guard !ws.isEmpty else { return false }
        for w in ws where !IsIconic(w) { ShowWindow(w, SW_MINIMIZE) }
        return true
    }
    func unhide(processIdentifier pid: Int32) -> Bool {
        let ws = windows(of: pid)
        guard !ws.isEmpty else { return false }
        for w in ws where IsIconic(w) { ShowWindow(w, SW_RESTORE) }
        return true
    }
    func terminate(processIdentifier pid: Int32, force: Bool) -> Bool {
        let dwPID = DWORD(bitPattern: pid)
        guard dwPID != GetCurrentProcessId(), dwPID != 0 else { return false }
        if force {
            guard let h = OpenProcess(DWORD(PROCESS_TERMINATE), false, dwPID) else { return false }
            defer { CloseHandle(h) }
            return TerminateProcess(h, 1)
        }
        let ws = windows(of: pid)
        guard !ws.isEmpty else { return false }
        for w in ws { PostMessageW(w, UINT(WM_CLOSE), 0, 0) }
        return true
    }
    func executableArchitecture(processIdentifier pid: Int32) -> Int? {
        let arch = cd2d_shell_process_architecture(DWORD(bitPattern: pid))
        return arch == 0 ? nil : Int(arch)
    }

    // MARK: Opening

    private func execute(_ file: String, parameters: String, show: Int32) -> DWORD? {
        var pid: UInt32 = 0
        let ok = shellCall {
            file.withCString(encodedAs: UTF16.self) { f in
                parameters.withCString(encodedAs: UTF16.self) { p in cd2d_shell_execute(nil, f, p, show, &pid) }
            }
        }
        if trace { NSView._trace("win32 workspace: ShellExecute '\(file)' '\(parameters)' -> \(ok ? "pid \(pid)" : "failed \(GetLastError())")") }
        return ok ? pid : nil
    }

    /// A command-line argument, quoted as CommandLineToArgv expects.
    private static func quote(_ s: String) -> String {
        guard s.contains(where: { $0 == " " || $0 == "\t" || $0 == "\"" }) || s.isEmpty else { return s }
        var out = "\""
        var backslashes = 0
        for ch in s {
            if ch == "\\" { backslashes += 1; continue }
            if ch == "\"" { out += String(repeating: "\\", count: backslashes * 2 + 1) + "\""; backslashes = 0; continue }
            out += String(repeating: "\\", count: backslashes) + String(ch)
            backslashes = 0
        }
        out += String(repeating: "\\", count: backslashes * 2) + "\""
        return out
    }

    func open(_ url: URL) -> Bool {
        execute(url.isFileURL ? url.path : url.absoluteString, parameters: "", show: SW_SHOWNORMAL) != nil
    }

    func open(_ urls: [URL], withApplicationAt applicationURL: URL?, options: PlatformLaunchOptions) throws -> PlatformRunningApplication {
        let show = options.hides ? SW_SHOWMINNOACTIVE : (options.activates ? SW_SHOWNORMAL : SW_SHOWNOACTIVATE)
        let documents = urls.map { $0.isFileURL ? $0.path : $0.absoluteString }
        let file: String
        var parameters = (options.arguments + documents).map(Win32Workspace.quote).joined(separator: " ")
        if let applicationURL {
            guard FileManager.default.fileExists(atPath: applicationURL.path) else { throw PlatformWorkspaceError.noApplication(applicationURL.path) }
            file = applicationURL.path
        } else {
            guard let first = urls.first else { throw PlatformWorkspaceError.noApplication("nothing") }
            let target: PlatformOpenTarget = first.isFileURL ? .file(first) : .scheme(first.scheme?.lowercased() ?? "")
            if let handler = applicationURLs(toOpen: target).first {
                file = handler.path
            } else {
                // The shell may still know (a verb without an executable): ask it directly.
                guard let pid = execute(documents[0], parameters: "", show: show), pid != 0 else { throw PlatformWorkspaceError.noApplication(first.absoluteString) }
                return remember(pid: pid, fallbackName: first.lastPathComponent)
            }
            parameters = (options.arguments + documents).map(Win32Workspace.quote).joined(separator: " ")
        }
        if !options.environment.isEmpty, trace { NSView._trace("win32 workspace: launch environment is not applied through ShellExecute") }
        guard let pid = execute(file, parameters: parameters, show: show) else { throw PlatformWorkspaceError.launchFailed(file) }
        return remember(pid: pid, fallbackName: URL(fileURLWithPath: file).deletingPathExtension().lastPathComponent)
    }

    private func remember(pid: DWORD, fallbackName: String) -> PlatformRunningApplication {
        guard pid != 0 else {
            // ShellExecute handed the document to a running instance (DDE, single-instance
            // applications): report the foreground application, or a placeholder.
            if let fg = foregroundPID(), let app = application(pid: fg, windows: windowedProcesses()[fg]) { return app }
            return PlatformRunningApplication(processIdentifier: 0, localizedName: fallbackName, hasWindows: true)
        }
        var app = application(pid: pid, windows: nil) ?? PlatformRunningApplication(processIdentifier: Int32(bitPattern: pid), localizedName: fallbackName)
        app.launchDate = app.launchDate ?? Date()
        app.hasWindows = true
        launched[pid] = app
        return app
    }

    func revealFiles(_ urls: [URL], selecting: Bool) -> Bool {
        let paths = urls.map(\.path)
        guard !paths.isEmpty else { return false }
        if !selecting { return execute(paths[0], parameters: "", show: SW_SHOWNORMAL) != nil }
        var joined: [UInt16] = []
        for p in paths { joined += Array(p.utf16) + [0] }
        return shellCall { cd2d_shell_reveal(joined, UInt32(paths.count)) }
    }

    // MARK: Associations

    func applicationURLs(toOpen target: PlatformOpenTarget) -> [URL] {
        var ext: String? = nil
        var scheme: String? = nil
        switch target {
        case .file(let url): ext = url.pathExtension.isEmpty ? nil : "." + url.pathExtension.lowercased()
        case .fileExtension(let e): ext = e.isEmpty ? nil : "." + e.lowercased()
        case .scheme(let s): scheme = s
        }
        var result: [URL] = []
        var buffer = [UInt16](repeating: 0, count: 1024)
        if let assoc = ext ?? scheme, assoc.withCString(encodedAs: UTF16.self, { cd2d_shell_default_handler($0, scheme != nil, &buffer, UInt32(buffer.count)) }) {
            result.append(URL(fileURLWithPath: String(decoding: buffer.prefix { $0 != 0 }, as: UTF16.self)))
        }
        if let ext {
            var length: UInt32 = 0
            if let list = ext.withCString(encodedAs: UTF16.self, { cd2d_shell_handlers($0, &length) }) {
                defer { cd2d_shell_free(list) }
                let all = Array(UnsafeBufferPointer(start: list, count: Int(length)))
                for path in all.split(separator: 0) {
                    let url = URL(fileURLWithPath: String(decoding: path, as: UTF16.self))
                    if !result.contains(where: { $0.path.caseInsensitiveCompare(url.path) == .orderedSame }) { result.append(url) }
                }
            }
        }
        return result
    }

    /// An Application User Model ID of a running process, an App Paths registration or
    /// an executable name on PATH.
    func applicationURL(withBundleIdentifier identifier: String) -> URL? {
        for (pid, _) in windowedProcesses() where appUserModelID(pid) == identifier {
            if let exe = executablePath(pid) { return URL(fileURLWithPath: exe) }
        }
        let name = identifier.lowercased().hasSuffix(".exe") ? identifier : identifier + ".exe"
        var buffer = [WCHAR](repeating: 0, count: 1024)
        var size = DWORD(buffer.count)
        let hklm = HKEY(bitPattern: Int(Int32(bitPattern: 0x8000_0002)))
        let hkcu = HKEY(bitPattern: Int(Int32(bitPattern: 0x8000_0001)))
        for root in [hkcu, hklm] {
            let status = "Software\\Microsoft\\Windows\\CurrentVersion\\App Paths\\\(name)".withCString(encodedAs: UTF16.self) { key in
                RegGetValueW(root, key, nil, DWORD(RRF_RT_REG_SZ), nil, &buffer, &size)
            }
            if status == ERROR_SUCCESS { return URL(fileURLWithPath: String(decoding: buffer.prefix { $0 != 0 }, as: UTF16.self)) }
            size = DWORD(buffer.count)
        }
        var found = [WCHAR](repeating: 0, count: 1024)
        var filePart: UnsafeMutablePointer<WCHAR>? = nil
        let n = name.withCString(encodedAs: UTF16.self) { SearchPathW(nil, $0, nil, DWORD(found.count), &found, &filePart) }
        if n > 0 { return URL(fileURLWithPath: String(decoding: found.prefix(Int(n)), as: UTF16.self)) }
        return nil
    }

    /// Windows 10 and later let only the user change defaults (the Settings app).
    func setDefaultApplication(at applicationURL: URL, toOpen target: PlatformOpenTarget) throws {
        throw PlatformWorkspaceError.unsupported("Windows lets only the user choose default applications (Settings > Apps > Default apps)")
    }

    // MARK: Icons

    func icon(for target: PlatformIconTarget, size: CGFloat, scale: CGFloat) -> CGImage? {
        let px = UInt32((size * scale).rounded())
        var path: String
        var useAttributes = false, isDirectory = false
        switch target {
        case .file(let p): path = p
        case .folder: path = "folder"; useAttributes = true; isDirectory = true
        case .fileExtension(let ext): path = ext.isEmpty ? "file" : "file." + ext; useAttributes = true
        case .application(let url): path = url.path
        case .process(let pid):
            guard let exe = executablePath(DWORD(bitPattern: pid)) else { return nil }
            path = exe
        }
        var pixels: UnsafeMutablePointer<UInt8>? = nil
        var w: UInt32 = 0, h: UInt32 = 0
        let ok = path.withCString(encodedAs: UTF16.self) { cd2d_shell_icon($0, useAttributes, isDirectory, px, &pixels, &w, &h) }
        guard ok, let pixels, w > 0, h > 0 else { return nil }
        defer { cd2d_shell_free(pixels) }
        let data = Data(bytes: pixels, count: Int(w * h * 4))
        return CGImage.fromBGRA(width: Int(w), height: Int(h), stride: Int(w) * 4, data: data)
    }

    // MARK: Files

    func recycle(_ url: URL) throws -> URL? {
        let ok = shellCall { url.path.replacingOccurrences(of: "/", with: "\\").withCString(encodedAs: UTF16.self) { cd2d_shell_recycle($0) } }
        guard ok else { throw PlatformWorkspaceError.fileOperationFailed("Recycle Bin refused \(url.path)") }
        return nil   // the bin's own names are not exposed
    }

    func noteFileSystemChanged(_ path: String) {
        path.withCString(encodedAs: UTF16.self) { SHChangeNotify(LONG(SHCNE_UPDATEITEM), UINT(SHCNF_PATHW), $0, nil) }
    }

    // MARK: Settings

    var accessibilityDisplayOptions: PlatformAccessibilityDisplayOptions {
        var o = PlatformAccessibilityDisplayOptions()
        var animation: WindowsBool = true
        if SystemParametersInfoW(UINT(SPI_GETCLIENTAREAANIMATION), 0, &animation, 0) { o.reduceMotion = !animation.boolValue }
        var contrast = HIGHCONTRASTW()
        contrast.cbSize = UINT(MemoryLayout<HIGHCONTRASTW>.size)
        if SystemParametersInfoW(UINT(SPI_GETHIGHCONTRAST), contrast.cbSize, &contrast, 0) { o.increaseContrast = contrast.dwFlags & DWORD(HCF_HIGHCONTRASTON) != 0 }
        var reader: WindowsBool = false
        if SystemParametersInfoW(UINT(SPI_GETSCREENREADER), 0, &reader, 0) { o.voiceOverEnabled = reader.boolValue }
        // Settings > Personalization > Colors > Transparency effects.
        var value: DWORD = 1
        var size = DWORD(MemoryLayout<DWORD>.size)
        let hkcu = HKEY(bitPattern: Int(Int32(bitPattern: 0x8000_0001)))
        let status = "Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize".withCString(encodedAs: UTF16.self) { key in
            "EnableTransparency".withCString(encodedAs: UTF16.self) { name in RegGetValueW(hkcu, key, name, DWORD(RRF_RT_REG_DWORD), nil, &value, &size) }
        }
        if status == ERROR_SUCCESS { o.reduceTransparency = value == 0 }
        return o
    }

    func desktopImageURL(forDisplay index: Int) -> URL? {
        var buffer = [WCHAR](repeating: 0, count: 1024)
        guard SystemParametersInfoW(UINT(SPI_GETDESKWALLPAPER), UINT(buffer.count), &buffer, 0) else { return nil }
        let path = String(decoding: buffer.prefix { $0 != 0 }, as: UTF16.self)
        return path.isEmpty ? nil : URL(fileURLWithPath: path)
    }
    func setDesktopImageURL(_ url: URL, forDisplay index: Int) throws {
        guard url.isFileURL else { throw PlatformWorkspaceError.unsupported("the desktop picture must be a file") }
        let ok = url.path.replacingOccurrences(of: "/", with: "\\").withCString(encodedAs: UTF16.self) { p in
            SystemParametersInfoW(UINT(SPI_SETDESKWALLPAPER), 0, UnsafeMutableRawPointer(mutating: p), UINT(SPIF_UPDATEINIFILE | SPIF_SENDCHANGE))
        }
        guard ok else { throw PlatformWorkspaceError.fileOperationFailed("SPI_SETDESKWALLPAPER failed: \(GetLastError())") }
    }

    // MARK: The taskbar button

    func setDockTile(_ tile: PlatformDockTile) {
        if let old = overlayIcon { overlayIcon = nil; DestroyIcon(old) }
        if let overlay = tile.badgeOverlay { overlayIcon = Win32StatusItem.makeIcon(overlay) }
        overlayDescription = Array((tile.badgeLabel ?? "").utf16) + [0]
        if let old = applicationIcon { applicationIcon = nil; DestroyIcon(old) }
        if let old = applicationSmallIcon { applicationSmallIcon = nil; DestroyIcon(old) }
        if let icon = tile.icon {
            applicationIcon = Win32StatusItem.makeIcon(icon)
            applicationSmallIcon = Win32StatusItem.makeIcon(icon)
        }
        for window in backend.windows { apply(to: window) }
    }

    /// Applies the overlay and icon to a window (every window gets them: the taskbar
    /// groups them by executable and shows the overlay of the active one).
    func apply(to window: Win32Window) {
        guard let hwnd = window.hwnd, window.wantsMenuBar || window.styleMask.contains(.titled) else { return }
        _ = cd2d_shell_set_overlay_icon(UnsafeMutableRawPointer(hwnd), overlayIcon.map { UnsafeMutableRawPointer($0) }, overlayDescription)
        SendMessageW(hwnd, UINT(WM_SETICON), WPARAM(ICON_BIG), applicationIcon.map { LPARAM(Int(bitPattern: UnsafeRawPointer($0))) } ?? 0)
        SendMessageW(hwnd, UINT(WM_SETICON), WPARAM(ICON_SMALL), applicationSmallIcon.map { LPARAM(Int(bitPattern: UnsafeRawPointer($0))) } ?? 0)
    }
}
#endif
