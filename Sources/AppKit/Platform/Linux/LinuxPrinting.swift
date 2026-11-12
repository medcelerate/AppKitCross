// Printing on Linux (ADR-0022): Cairo's PDF surface for documents, CUPS for devices.
// The printer list comes from `lpstat -p -d` and a job is `lp` of the rendered PDF (the
// CUPS command-line tools; libcups is not linked, so a system without CUPS simply has
// no printers and prints to PDF). Shared by the X11 and Wayland backends.

#if os(Linux)
import Foundation
import CoreGraphics

@MainActor
final class LinuxPrintBackend: PlatformPrintBackend {
    private static func which(_ tool: String) -> String? {
        ["/usr/bin/", "/usr/local/bin/", "/bin/"].map { $0 + tool }.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Runs a CUPS tool and returns its standard output, nil when it is missing or fails.
    private static func run(_ tool: String, _ args: [String]) -> String? {
        guard let exe = which(tool) else { return nil }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    /// `lpstat -p` lines are "printer NAME is idle. ..."; `lpstat -d` says
    /// "system default destination: NAME".
    var printers: [PlatformPrinter] {
        guard let list = LinuxPrintBackend.run("lpstat", ["-p"]) else { return [] }
        let defaultName = LinuxPrintBackend.run("lpstat", ["-d"]).flatMap { line -> String? in
            guard let colon = line.firstIndex(of: ":") else { return nil }
            return line[line.index(after: colon)...].trimmingCharacters(in: .whitespacesAndNewlines)
        }
        var out: [PlatformPrinter] = []
        for line in list.split(separator: "\n") {
            let parts = line.split(separator: " ")
            guard parts.count >= 2, parts[0] == "printer" else { continue }
            let name = String(parts[1])
            out.append(PlatformPrinter(name: name, type: "CUPS", isDefault: name == defaultName))
        }
        if let i = out.firstIndex(where: \.isDefault), i != 0 { out.swapAt(0, i) }
        return out
    }

    func makePDFDocument(title: String?) -> (any PlatformPrintDocument)? { _PlatformPDF.makeDocument(title: title) }

    func makePrintJob(_ settings: PlatformPrintJobSettings) -> (any PlatformPrintDocument)? {
        guard LinuxPrintBackend.which("lp") != nil, let pdf = _PlatformPDF.makeDocument(title: settings.jobTitle) else { return nil }
        return LinuxCUPSJob(settings: settings, pdf: pdf)
    }

    /// Linux has no native print dialog of its own; the package's panel is the dialog.
    func runNativePrintPanel(_ settings: inout PlatformPrintJobSettings, pageCount: Int, parent: PlatformWindow?) -> Bool? { nil }
}

/// Renders to a PDF, then `lp -d printer -t title [-n copies] file`.
@MainActor
final class LinuxCUPSJob: PlatformPrintDocument {
    private let settings: PlatformPrintJobSettings
    private let pdf: any PlatformPrintDocument
    init(settings: PlatformPrintJobSettings, pdf: any PlatformPrintDocument) {
        self.settings = settings
        self.pdf = pdf
    }
    func beginPage(size: CGSize) -> CGContext? { pdf.beginPage(size: size) }
    func endPage() { pdf.endPage() }
    func finish() -> Data? {
        guard let data = pdf.finish() else { return nil }
        let path = NSTemporaryDirectory() + "/appkitcross-job-\(UUID().uuidString).pdf"
        do { try data.write(to: URL(fileURLWithPath: path)) } catch { return nil }
        var args = ["-t", settings.jobTitle]
        if let printer = settings.printerName { args += ["-d", printer] }
        // Copies are already repeated in the document (NSPrintOperation collates them).
        args += ["-o", settings.landscape ? "landscape" : "portrait", path]
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = ["lp"] + args
        p.standardOutput = Pipe()
        p.standardError = Pipe()
        do { try p.run() } catch { NSLog("NSPrintOperation: cannot run lp: \(error)"); return nil }
        p.waitUntilExit()
        try? FileManager.default.removeItem(atPath: path)
        if p.terminationStatus != 0 { NSLog("NSPrintOperation: lp exited with \(p.terminationStatus)") }
        return nil
    }
    func cancel() { pdf.cancel() }
}
#endif
