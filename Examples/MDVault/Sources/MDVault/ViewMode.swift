import SwiftUI

enum ViewMode: String, CaseIterable, Identifiable {
    case editor
    case viewer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .editor: return "Editor"
        case .viewer: return "Viewer"
        }
    }

    var symbol: String {
        switch self {
        case .editor: return "chevron.left.forwardslash.chevron.right"
        case .viewer: return "doc.richtext"
        }
    }

    mutating func toggle() { self = self == .editor ? .viewer : .editor }
}

/// Lets the View menu drive the focused window's mode.
struct MDViewModeKey: FocusedValueKey {
    typealias Value = Binding<ViewMode>
}

extension FocusedValues {
    var mdViewMode: Binding<ViewMode>? {
        get { self[MDViewModeKey.self] }
        set { self[MDViewModeKey.self] = newValue }
    }
}
