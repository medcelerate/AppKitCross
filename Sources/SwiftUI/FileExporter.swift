// `fileExporter` and `fileImporter`: a save or open panel shown while a binding is true,
// as a sheet on the view's window (a free panel when that window already shows a sheet).
// The binding goes back to false when the panel closes.

import Foundation
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif

extension View {
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/fileexporter(ispresented:document:contenttype:defaultfilename:oncompletion:)-32vwk
    ///
    /// Writes the document's file wrapper to the chosen URL. A cancelled panel does not
    /// call `onCompletion`, as on macOS.
    public func fileExporter<D: FileDocument>(isPresented: Binding<Bool>, document: D?, contentType: UTType, defaultFilename: String? = nil, onCompletion: @escaping (_ result: Result<URL, any Error>) -> Void) -> some View {
        fileExporter(isPresented: isPresented, document: document, contentTypes: [contentType], defaultFilename: defaultFilename, onCompletion: onCompletion, onCancellation: {})
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/fileexporter(ispresented:document:contenttype:defaultfilename:oncompletion:)-1lsbf
    public func fileExporter<D: ReferenceFileDocument>(isPresented: Binding<Bool>, document: D?, contentType: UTType, defaultFilename: String? = nil, onCompletion: @escaping (_ result: Result<URL, any Error>) -> Void) -> some View {
        fileExporter(isPresented: isPresented, document: document, contentTypes: [contentType], defaultFilename: defaultFilename, onCompletion: onCompletion, onCancellation: {})
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/fileexporter(ispresented:document:contenttypes:defaultfilename:oncompletion:oncancellation:)-4ojxs
    public func fileExporter<D: FileDocument>(isPresented: Binding<Bool>, document: D?, contentTypes: [UTType] = [], defaultFilename: String? = nil, onCompletion: @escaping (Result<URL, any Error>) -> Void, onCancellation: @escaping () -> Void = {}) -> some View {
        let types = contentTypes.isEmpty ? D.writableContentTypes : contentTypes
        let write: ((UTType) throws -> FileWrapper)? = document.map { doc in { type in try doc.fileWrapper(configuration: FileDocumentWriteConfiguration(contentType: type, existingFile: nil)) } }
        return _FilePanelModified(content: self, request: .export(types: types, defaultFilename: defaultFilename, write: write, onCompletion: onCompletion), isPresented: isPresented, onCancellation: onCancellation)
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/fileexporter(ispresented:document:contenttypes:defaultfilename:oncompletion:oncancellation:)-9k6jj
    public func fileExporter<D: ReferenceFileDocument>(isPresented: Binding<Bool>, document: D?, contentTypes: [UTType] = [], defaultFilename: String? = nil, onCompletion: @escaping (Result<URL, any Error>) -> Void, onCancellation: @escaping () -> Void = {}) -> some View {
        let types = contentTypes.isEmpty ? D.writableContentTypes : contentTypes
        let write: ((UTType) throws -> FileWrapper)? = document.map { doc in { type in
            try doc.fileWrapper(snapshot: doc.snapshot(contentType: type), configuration: FileDocumentWriteConfiguration(contentType: type, existingFile: nil))
        } }
        return _FilePanelModified(content: self, request: .export(types: types, defaultFilename: defaultFilename, write: write, onCompletion: onCompletion), isPresented: isPresented, onCancellation: onCancellation)
    }

    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/fileimporter(ispresented:allowedcontenttypes:oncompletion:)
    public func fileImporter(isPresented: Binding<Bool>, allowedContentTypes: [UTType], onCompletion: @escaping (_ result: Result<URL, any Error>) -> Void) -> some View {
        _FilePanelModified(content: self, request: .open(types: allowedContentTypes, multiple: false, onCompletion: { result in onCompletion(result.map { $0[0] }) }), isPresented: isPresented, onCancellation: {})
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/fileimporter(ispresented:allowedcontenttypes:allowsmultipleselection:oncompletion:)
    public func fileImporter(isPresented: Binding<Bool>, allowedContentTypes: [UTType], allowsMultipleSelection: Bool, onCompletion: @escaping (_ result: Result<[URL], any Error>) -> Void) -> some View {
        _FilePanelModified(content: self, request: .open(types: allowedContentTypes, multiple: allowsMultipleSelection, onCompletion: onCompletion), isPresented: isPresented, onCancellation: {})
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/fileimporter(ispresented:allowedcontenttypes:allowsmultipleselection:oncompletion:oncancellation:)
    public func fileImporter(isPresented: Binding<Bool>, allowedContentTypes: [UTType], allowsMultipleSelection: Bool, onCompletion: @escaping (_ result: Result<[URL], any Error>) -> Void, onCancellation: @escaping () -> Void) -> some View {
        _FilePanelModified(content: self, request: .open(types: allowedContentTypes, multiple: allowsMultipleSelection, onCompletion: onCompletion), isPresented: isPresented, onCancellation: onCancellation)
    }
}

enum _FilePanelRequest {
    case export(types: [UTType], defaultFilename: String?, write: ((UTType) throws -> FileWrapper)?, onCompletion: (Result<URL, any Error>) -> Void)
    case open(types: [UTType], multiple: Bool, onCompletion: (Result<[URL], any Error>) -> Void)
}

struct _FilePanelModified<Content: View>: View, _PrimitiveView {
    typealias Body = Never
    let content: Content
    let request: _FilePanelRequest
    let isPresented: Binding<Bool>
    let onCancellation: () -> Void
    func _makePrimitive(node: _ViewNode) -> _Primitive {
        _FilePanelPrimitive(request: request, isPresented: isPresented, onCancellation: onCancellation, content: _ViewBox(content))
    }
}

@MainActor
final class _FilePanelPrimitive: _Primitive {
    var request: _FilePanelRequest
    var isPresented: Binding<Bool>
    var onCancellation: () -> Void
    /// The panel on screen (tests drive it).
    private(set) var panel: NSSavePanel?

    init(request: _FilePanelRequest, isPresented: Binding<Bool>, onCancellation: @escaping () -> Void, content: _AnyViewBox) {
        self.request = request; self.isPresented = isPresented; self.onCancellation = onCancellation
        super.init()
        children = [content]
    }
    override var isLayoutTransparent: Bool { true }
    override func attach(to node: _ViewNode) { super.attach(to: node); sync() }
    override func update(from other: _Primitive) {
        super.update(from: other)
        guard let o = other as? _FilePanelPrimitive else { return }
        request = o.request; isPresented = o.isPresented; onCancellation = o.onCancellation
        sync()
    }
    override func detach() { panel?.cancel(nil); panel = nil }

    private func sync() {
        if isPresented.wrappedValue { if panel == nil { present() } }
        else if let p = panel { panel = nil; p.cancel(nil) }
    }
    /// A view presented before it is in a window (the binding true at launch) shows its
    /// panel once layout has placed it in one.
    override func didLayout(node: _ViewNode) {
        if isPresented.wrappedValue, panel == nil, window != nil { present() }
    }
    private var window: NSWindow? { node?.root?.host?.hostView.window }

    private func present() {
        // Wait for a window to attach the sheet to (didLayout presents it then).
        guard let window else { return }
        let p: NSSavePanel
        switch request {
        case .export(let types, let name, _, _):
            p = NSSavePanel()
            p.allowedContentTypes = types
            if let name { p.nameFieldStringValue = name }
            p.canCreateDirectories = true
        case .open(let types, let multiple, _):
            let o = NSOpenPanel()
            o.allowedContentTypes = types
            o.allowsMultipleSelection = multiple
            o.canChooseFiles = true
            o.canChooseDirectories = types.contains { $0.conforms(to: .folder) || $0.conforms(to: .directory) }
            p = o
        }
        panel = p
        let done: (NSApplication.ModalResponse) -> Void = { [weak self, weak p] response in
            guard let self, let p else { return }
            self.finish(p, response)
        }
        if window.attachedSheet == nil {
            p.beginSheetModal(for: window, completionHandler: done)
        } else {
            p.begin(completionHandler: done)
        }
    }

    private func finish(_ p: NSSavePanel, _ response: NSApplication.ModalResponse) {
        let current = panel === p
        if current { panel = nil }
        if isPresented.wrappedValue { isPresented.wrappedValue = false }
        guard response == .OK else { if current { onCancellation() }; return }
        switch request {
        case .export(let types, _, let write, let onCompletion):
            guard let url = p.url else { return }
            guard let write else { onCompletion(.failure(CocoaError(.fileWriteUnknown))); return }
            let type = UTType(filenameExtension: url.pathExtension).flatMap { t in types.first { t.conforms(to: $0) } } ?? types.first ?? .data
            do {
                let wrapper = try write(type)
                try wrapper.write(to: url, options: .atomic, originalContentsURL: nil)
                onCompletion(.success(url))
            } catch {
                onCompletion(.failure(error))
            }
        case .open(_, _, let onCompletion):
            let urls = (p as? NSOpenPanel)?.urls ?? []
            if urls.isEmpty { onCompletion(.failure(CocoaError(.fileReadNoSuchFile))) } else { onCompletion(.success(urls)) }
        }
    }
}
