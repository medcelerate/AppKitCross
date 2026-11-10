// AsyncImage and Material: the SwiftUI members NukeUI reaches for (its `LazyImage` preview
// compares itself with `AsyncImage`, its demo sits on `.background(Material.ultraThick)`).

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: AsyncImage

/// - SeeAlso: https://developer.apple.com/documentation/swiftui/asyncimagephase
public enum AsyncImagePhase: Sendable {
    case empty
    case success(Image)
    case failure(any Error)

    public var image: Image? {
        if case .success(let image) = self { return image }
        return nil
    }
    public var error: (any Error)? {
        if case .failure(let error) = self { return error }
        return nil
    }
}

/// Loads an image from a URL and shows a view for each phase of the load.
///
/// The bytes come from `Data(contentsOf:)` for file URLs and `URLSession.shared` for the
/// rest, decoded by `NSImage(data:)`; the phase changes under `transaction`. A new URL
/// restarts the load from `.empty`, as on macOS.
/// - SeeAlso: https://developer.apple.com/documentation/swiftui/asyncimage
public struct AsyncImage<Content: View>: View {
    let url: URL?
    let scale: CGFloat
    let transaction: Transaction
    let content: (AsyncImagePhase) -> Content
    @State private var phase = AsyncImagePhase.empty

    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/asyncimage/init(url:scale:)
    public init(url: URL?, scale: CGFloat = 1) where Content == Image {
        self.init(url: url, scale: scale) { phase in phase.image ?? Image(nsImage: NSImage()) }
    }

    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/asyncimage/init(url:scale:content:placeholder:)
    public init<I: View, P: View>(url: URL?, scale: CGFloat = 1, @ViewBuilder content: @escaping (Image) -> I, @ViewBuilder placeholder: @escaping () -> P) where Content == _ConditionalContent<I, P> {
        self.init(url: url, scale: scale) { phase -> _ConditionalContent<I, P> in
            if let image = phase.image { return ViewBuilder.buildEither(first: content(image)) }
            return ViewBuilder.buildEither(second: placeholder())
        }
    }

    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/asyncimage/init(url:scale:transaction:content:)
    public init(url: URL?, scale: CGFloat = 1, transaction: Transaction = Transaction(), @ViewBuilder content: @escaping (AsyncImagePhase) -> Content) {
        self.url = url
        self.scale = scale
        self.transaction = transaction
        self.content = content
    }

    public var body: some View {
        content(phase).task(id: url) { await load() }
    }

    @MainActor private func load() async {
        let url = self.url, scale = self.scale, transaction = self.transaction
        // A new URL (the task restarts) begins from `.empty`, including `nil`.
        if phase.image != nil || phase.error != nil {
            withTransaction(transaction) { phase = .empty }
        }
        guard let url else { return }
        let result: AsyncImagePhase
        do {
            let data = try await AsyncImage.bytes(of: url)
            guard let nsImage = NSImage(data: data) else { throw AsyncImage.LoadError.undecodable(url) }
            if scale != 1 && scale > 0 {
                nsImage.size = CGSize(width: nsImage.size.width / scale, height: nsImage.size.height / scale)
            }
            result = .success(Image(nsImage: nsImage))
        } catch {
            result = .failure(error)
        }
        guard !Task.isCancelled else { return }
        withTransaction(transaction) { phase = result }
    }

    enum LoadError: Error { case undecodable(URL) }

    private static func bytes(of url: URL) async throws -> Data {
        if url.isFileURL { return try Data(contentsOf: url) }
        return try await URLSession.shared.data(from: url).0
    }
}

// MARK: Material

/// A translucent background. The port has no live blur: a material fills with the window
/// background colour at an opacity that follows the thickness.
/// - SeeAlso: https://developer.apple.com/documentation/swiftui/material
public struct Material: ShapeStyle, Sendable {
    let opacity: Double

    public static let ultraThin = Material(opacity: 0.55)
    public static let thin = Material(opacity: 0.7)
    public static let regular = Material(opacity: 0.8)
    public static let thick = Material(opacity: 0.9)
    public static let ultraThick = Material(opacity: 0.95)
    public static let bar = Material(opacity: 0.85)

    @MainActor var color: Color { Color(nsColor: .windowBackgroundColor).opacity(opacity) }
    @MainActor public func _fill(_ context: CGContext, path: CGPath, in rect: CGRect, environment: EnvironmentValues) {
        color._fill(context, path: path, in: rect, environment: environment)
    }
    @MainActor public func _color(at point: CGPoint, in rect: CGRect, environment: EnvironmentValues) -> CGColor? {
        color._color(at: point, in: rect, environment: environment)
    }
}

extension ShapeStyle where Self == Material {
    public static var ultraThinMaterial: Material { .ultraThin }
    public static var thinMaterial: Material { .thin }
    public static var regularMaterial: Material { .regular }
    public static var thickMaterial: Material { .thick }
    public static var ultraThickMaterial: Material { .ultraThick }
    public static var bar: Material { .bar }
}

extension View {
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/background(_:ignoressafeareaedges:)
    /// Disfavoured so a style that is also a `View` (`Color`) keeps taking the view overload.
    @_disfavoredOverload
    public func background<S: ShapeStyle>(_ style: S, ignoresSafeAreaEdges edges: Edge.Set = .all) -> some View {
        background(Rectangle().fill(style))
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/background(in:fillstyle:)
    public func background<S: InsettableShape>(in shape: S, fillStyle: FillStyle = FillStyle()) -> some View {
        background(shape.fill(Material.regular, style: fillStyle))
    }
    /// - SeeAlso: https://developer.apple.com/documentation/swiftui/view/background(_:in:fillstyle:)
    public func background<S: ShapeStyle, T: InsettableShape>(_ style: S, in shape: T, fillStyle: FillStyle = FillStyle()) -> some View {
        background(shape.fill(style, style: fillStyle))
    }
}
