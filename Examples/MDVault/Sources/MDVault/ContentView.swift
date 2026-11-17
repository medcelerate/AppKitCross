import SwiftUI

struct ContentView: View {
    @Binding var document: MarkdownDocument
    let fileURL: URL?

    @AppStorage("lastViewMode") private var storedMode: ViewMode = .viewer
    @AppStorage("viewerFontSize") private var viewerFontSize: Double = 15
    @AppStorage("editorFontSize") private var editorFontSize: Double = 13.5

    @State private var mode: ViewMode = .viewer
    @State private var nodes: [MDNode] = []
    @State private var parsedText: String? = nil
    @State private var debounce: Task<Void, Never>? = nil

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch mode {
                case .editor:
                    MarkdownTextEditor(text: $document.text, fontSize: editorFontSize)
                case .viewer:
                    MarkdownView(nodes: nodes,
                                 theme: MDTheme(bodySize: viewerFontSize),
                                 baseURL: fileURL)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()
            statusBar
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("View", selection: $mode) {
                    ForEach(ViewMode.allCases) { value in
                        Text(value.title).tag(value)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 180)
                .help("Switch between the raw editor and the formatted viewer (⌘E)")
            }
        }
        .focusedSceneValue(\.mdViewMode, $mode)
        .onAppear {
            mode = storedMode
            parseNow()
        }
        .onChange(of: mode) { _, newMode in
            storedMode = newMode
            if newMode == .viewer { parseNow() }
        }
        .onChange(of: document.text) { _, _ in
            guard mode == .viewer else { return }
            scheduleParse()
        }
        .onDisappear { debounce?.cancel() }
    }

    // MARK: Status bar

    private var statusBar: some View {
        HStack(spacing: 12) {
            Text(mode.title).fontWeight(.semibold)
            Text("⌘E to switch").foregroundStyle(.tertiary)
            Spacer()
            Text("\(wordCount) words")
            Text("\(lineCount) lines")
            Text("\(document.text.count) chars")
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
        .background(.bar)
    }

    private var wordCount: Int {
        document.text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    private var lineCount: Int {
        document.text.isEmpty ? 0 : document.text.reduce(1) { $1 == "\n" ? $0 + 1 : $0 }
    }

    // MARK: Parsing

    private func parseNow() {
        debounce?.cancel()
        guard parsedText != document.text else { return }
        let source = document.text
        nodes = MarkdownParser.parse(source)
        parsedText = source
    }

    /// Typing in one window while another shows the viewer shouldn't reparse per keystroke.
    private func scheduleParse() {
        debounce?.cancel()
        debounce = Task {
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            parseNow()
        }
    }
}
