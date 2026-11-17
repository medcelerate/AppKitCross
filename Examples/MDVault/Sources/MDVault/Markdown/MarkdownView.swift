import AppKit
import SwiftUI

// MARK: - Document

struct MarkdownView: View {
    let nodes: [MDNode]
    let theme: MDTheme
    let baseURL: URL?

    var body: some View {
        ScrollView(.vertical) {
            MDBlockStack(nodes: nodes, theme: theme, baseURL: baseURL)
                .frame(maxWidth: theme.maxWidth, alignment: .leading)
                .padding(.horizontal, 40)
                .padding(.vertical, 36)
                .frame(maxWidth: .infinity, alignment: .top)
        }
        .textSelection(.enabled)
        .background(Color(nsColor: .textBackgroundColor))
    }
}

struct MDBlockStack: View {
    let nodes: [MDNode]
    let theme: MDTheme
    let baseURL: URL?
    var tight: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: tight ? theme.tightSpacing : theme.blockSpacing) {
            ForEach(nodes) { node in
                MDBlockView(node: node, theme: theme, baseURL: baseURL)
            }
        }
    }
}

// MARK: - Blocks

struct MDBlockView: View {
    let node: MDNode
    let theme: MDTheme
    let baseURL: URL?

    var body: some View {
        switch node.block {
        case .heading(let level, let inlines):
            VStack(alignment: .leading, spacing: 7) {
                Text(MDInlineRenderer.attributed(
                    inlines,
                    style: MDInlineStyle(size: theme.headingSize(level),
                                         bold: true,
                                         color: level >= 5 ? .secondary : .primary)))
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                if level <= 2 { Divider() }
            }
            .padding(.top, theme.headingTopSpace(level))

        case .paragraph(let inlines):
            Text(MDInlineRenderer.attributed(inlines, style: MDInlineStyle(size: theme.bodySize)))
                .lineSpacing(theme.bodySize * 0.38)
                .fixedSize(horizontal: false, vertical: true)

        case .codeBlock(let language, let code):
            MDCodeBlockView(language: language, code: code, theme: theme)

        case .blockQuote(let inner):
            HStack(alignment: .top, spacing: 15) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.accentColor.opacity(0.45))
                    .frame(width: 3)
                MDBlockStack(nodes: inner, theme: theme, baseURL: baseURL)
            }
            .fixedSize(horizontal: false, vertical: true)

        case .list(let list):
            MDListView(list: list, theme: theme, baseURL: baseURL)

        case .table(let table):
            MDTableView(table: table, theme: theme)

        case .thematicBreak:
            Divider().padding(.vertical, theme.bodySize * 0.4)

        case .image(let alt, let url):
            MDImageBlockView(alt: alt, url: url, baseURL: baseURL, theme: theme)
        }
    }
}

// MARK: - Lists

struct MDListView: View {
    let list: MDList
    let theme: MDTheme
    let baseURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: list.tight ? theme.tightSpacing : theme.blockSpacing * 0.65) {
            ForEach(Array(list.items.enumerated()), id: \.element.id) { index, item in
                HStack(alignment: .firstTextBaseline, spacing: 9) {
                    marker(index: index, item: item)
                        .frame(minWidth: theme.bodySize * 1.5, alignment: .trailing)
                    MDBlockStack(nodes: item.blocks, theme: theme, baseURL: baseURL, tight: list.tight)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    @ViewBuilder
    private func marker(index: Int, item: MDListItem) -> some View {
        if let checked = item.checked {
            Image(systemName: checked ? "checkmark.square.fill" : "square")
                .font(.system(size: theme.bodySize))
                .foregroundStyle(checked ? Color.accentColor : Color.secondary)
        } else if list.ordered {
            Text("\(list.start + index).")
                .font(Font(MDFont.make(size: theme.bodySize, weight: .medium)))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        } else {
            Text("•")
                .font(Font(MDFont.make(size: theme.bodySize * 1.2, bold: true)))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Code

struct MDCodeBlockView: View {
    let language: String?
    let code: String
    let theme: MDTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let language, !language.isEmpty {
                Text(language.uppercased())
                    .font(.system(size: max(9, theme.codeSize * 0.72), weight: .semibold, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 15)
                    .padding(.top, 10)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(Font(MDFont.make(size: theme.codeSize, mono: true)))
                    .lineSpacing(3.5)
                    .textSelection(.enabled)
                    .padding(15)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.055)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.10)))
    }
}

// MARK: - Tables

struct MDTableView: View {
    let table: MDTable
    let theme: MDTheme

    var body: some View {
        Grid(alignment: .topLeading, horizontalSpacing: 0, verticalSpacing: 0) {
            GridRow {
                ForEach(Array(table.headers.enumerated()), id: \.offset) { index, cell in
                    cellView(cell, index: index, bold: true, shade: 0.06)
                        .gridColumnAlignment(alignment(index))
                }
            }
            Divider().gridCellUnsizedAxes(.horizontal)
            ForEach(Array(table.rows.enumerated()), id: \.offset) { rowIndex, row in
                GridRow {
                    ForEach(Array(row.enumerated()), id: \.offset) { index, cell in
                        cellView(cell, index: index, bold: false,
                                 shade: rowIndex.isMultiple(of: 2) ? 0 : 0.03)
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.primary.opacity(0.12)))
    }

    private func alignment(_ index: Int) -> HorizontalAlignment {
        switch table.aligns.indices.contains(index) ? table.aligns[index] : .leading {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }

    private func cellView(_ inlines: [MDInline], index: Int, bold: Bool, shade: Double) -> some View {
        Text(MDInlineRenderer.attributed(
            inlines,
            style: MDInlineStyle(size: theme.bodySize * 0.95, bold: bold)))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 13)
            .padding(.vertical, 8)
            // Fill the column so row shading covers the full width.
            .frame(maxWidth: .infinity, alignment: textAlignment(index))
            .background(Color.primary.opacity(shade))
    }

    private func textAlignment(_ index: Int) -> Alignment {
        switch table.aligns.indices.contains(index) ? table.aligns[index] : .leading {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }
}

// MARK: - Images

struct MDImageBlockView: View {
    let alt: String
    let url: String
    let baseURL: URL?
    let theme: MDTheme

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            content
            if !alt.isEmpty {
                Text(alt)
                    .font(.system(size: theme.bodySize * 0.85))
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let image = localImage {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: image.size.width, maxHeight: 560)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        } else if let remote = remoteURL {
            AsyncImage(url: remote) { phase in
                switch phase {
                case .success(let image):
                    image.resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 560)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                case .failure:
                    placeholder
                default:
                    ProgressView().controlSize(.small).frame(height: 60)
                }
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        HStack(spacing: 8) {
            Image(systemName: "photo")
            Text(url.isEmpty ? "missing image" : url).lineLimit(1).truncationMode(.middle)
        }
        .font(.system(size: theme.bodySize * 0.85))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05)))
    }

    private var remoteURL: URL? {
        guard let parsed = URL(string: url), let scheme = parsed.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return nil }
        return parsed
    }

    /// Relative image paths resolve against the document's own folder.
    private var localImage: NSImage? {
        guard remoteURL == nil, !url.isEmpty else { return nil }
        let decoded = url.removingPercentEncoding ?? url
        let candidate: URL
        if decoded.hasPrefix("file://") {
            guard let parsed = URL(string: url) else { return nil }
            candidate = parsed
        } else if decoded.hasPrefix("/") {
            candidate = URL(fileURLWithPath: decoded)
        } else if decoded.hasPrefix("~") {
            candidate = URL(fileURLWithPath: (decoded as NSString).expandingTildeInPath)
        } else if let baseURL {
            candidate = baseURL.deletingLastPathComponent().appendingPathComponent(decoded)
        } else {
            return nil
        }
        return NSImage(contentsOf: candidate)
    }
}
