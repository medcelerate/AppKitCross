import AppKit
import SwiftUI
import UniformTypeIdentifiers

@main
struct MDVaultApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: MarkdownDocument()) { configuration in
            ContentView(document: configuration.$document, fileURL: configuration.fileURL)
        }
        .defaultSize(width: 920, height: 720)
        .commands { MDCommands() }
    }
}

struct MDCommands: Commands {
    @FocusedValue(\.mdViewMode) private var mode
    @AppStorage("viewerFontSize") private var viewerFontSize: Double = 15
    @AppStorage("editorFontSize") private var editorFontSize: Double = 13.5

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Divider()
            Button("Set MD Vault as Default for Markdown…") {
                DefaultAppHelper.setAsDefault()
            }
        }

        CommandGroup(after: .toolbar) {
            Button("Toggle Editor / Viewer") { mode?.wrappedValue.toggle() }
                .keyboardShortcut("e", modifiers: .command)
                .disabled(mode == nil)
            Button(ViewMode.editor.title) { mode?.wrappedValue = .editor }
                .keyboardShortcut("1", modifiers: .command)
                .disabled(mode == nil)
            Button(ViewMode.viewer.title) { mode?.wrappedValue = .viewer }
                .keyboardShortcut("2", modifiers: .command)
                .disabled(mode == nil)

            Divider()

            Button("Bigger Text") { scale(by: 1) }
                .keyboardShortcut("+", modifiers: .command)
            Button("Smaller Text") { scale(by: -1) }
                .keyboardShortcut("-", modifiers: .command)
            Button("Actual Size") { viewerFontSize = 15; editorFontSize = 13.5 }
                .keyboardShortcut("0", modifiers: .command)

            Divider()
        }
    }

    private func scale(by delta: Double) {
        viewerFontSize = min(36, max(10, viewerFontSize + delta))
        editorFontSize = min(32, max(9, editorFontSize + delta))
    }
}

enum DefaultAppHelper {
    static func setAsDefault() {
        guard let type = UTType("net.daringfireball.markdown") else { return }
        NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpen: type) { error in
            DispatchQueue.main.async {
                let alert = NSAlert()
                if let error {
                    alert.alertStyle = .warning
                    alert.messageText = "Couldn't set the default app"
                    alert.informativeText = error.localizedDescription
                } else {
                    alert.messageText = "MD Vault is now the default for Markdown files"
                    alert.informativeText = "Double-clicking a .md file in Finder will open it here."
                }
                alert.runModal()
            }
        }
    }
}
