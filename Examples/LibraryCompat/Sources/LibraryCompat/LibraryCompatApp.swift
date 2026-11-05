// LibraryCompat: popular third-party SwiftUI packages built against AppKitWin's SwiftUI,
// one tab each, exercising the headline feature of every library that compiles on this
// platform. The verdicts and the API gaps are in docs/compatibility/swiftui-libraries.md;
// tools/library-compat.sh builds and probes the libraries.
//
//     LibraryCompat                      # the window
//     LibraryCompat --screenshot <dir>   # one PNG per tab, then exit
//     APPKITWIN_COMPAT_TAB=confetti      # opens on that tab

import AppKit
import SwiftUI
#if HAS_SHIMMER
import Shimmer
#endif
#if HAS_CONFETTI
import ConfettiSwiftUI
#endif
#if HAS_WRAPPINGHSTACK
import WrappingHStack
#endif
#if HAS_DEFAULTS
import Defaults
#endif
#if HAS_MARKDOWNUI
import MarkdownUI
#endif
#if HAS_INTROSPECT
import SwiftUIIntrospect
#endif
#if HAS_CHARTS
import SwiftUICharts
#endif

@main
struct LibraryCompatApp: App {
    var body: some Scene {
        WindowGroup("Library Compatibility") {
            ContentView()
        }
        .defaultSize(width: 640, height: 440)
    }
}

/// One entry per library: the tab, whether this build includes it, and why not.
struct LibraryEntry: Identifiable {
    let id: String
    let name: String
    let version: String
    let included: Bool
    /// Why the library is not in this platform's build (the first compile error).
    let exclusion: String?
}

enum Libraries {
    static let all: [LibraryEntry] = [
        LibraryEntry(id: "shimmer", name: "SwiftUI-Shimmer", version: "1.5.1", included: Compiled.shimmer, exclusion: nil),
        LibraryEntry(id: "confetti", name: "ConfettiSwiftUI", version: "3.0.0", included: Compiled.confetti, exclusion: nil),
        LibraryEntry(id: "wrapping", name: "WrappingHStack", version: "2.2.11", included: Compiled.wrapping,
                     exclusion: "keys its hosting controller on `#if os(macOS)`, so on Windows and Linux it reaches for UIHostingController"),
        LibraryEntry(id: "defaults", name: "Defaults", version: "9.0.9", included: Compiled.defaults,
                     exclusion: "`#if os(macOS)` … `#else import UIKit`: every platform that is not macOS is assumed to have UIKit"),
        LibraryEntry(id: "markdown", name: "swift-markdown-ui", version: "2.4.1", included: Compiled.markdown,
                     exclusion: "its NetworkImage dependency extends URLSession in a file that imports only Foundation, which on Windows and Linux is FoundationNetworking's"),
        LibraryEntry(id: "introspect", name: "SwiftUI-Introspect", version: "27.1.0", included: Compiled.introspect,
                     exclusion: "imports ObjectiveC and reaches into AppKit's private view hierarchy"),
        LibraryEntry(id: "charts", name: "SwiftUICharts", version: "2.10.4", included: Compiled.charts,
                     exclusion: Platform.name == "Windows"
                        ? "the Swift 6.4.1 frontend asserts on its shape files (debug-type round trip; the probe disables the check), and `Color.systemsBackground` switches on os(iOS/watchOS/tvOS/macOS/visionOS) with no default (Extensions.swift:136)"
                        : "`Color.systemsBackground` switches on os(iOS/watchOS/tvOS/macOS/visionOS) with no default (Extensions.swift:136); everything else compiles"),
        LibraryEntry(id: "nuke", name: "Nuke + NukeUI", version: "13.2.1", included: false,
                     exclusion: "`#if !os(macOS) import UIKit`, Core Image filters and the ImageIO C API"),
    ]
}

/// Which libraries this build was compiled with (Package.swift lists them per platform and
/// defines HAS_<NAME> for each).
enum Compiled {
    #if HAS_SHIMMER
    static let shimmer = true
    #else
    static let shimmer = false
    #endif
    #if HAS_CONFETTI
    static let confetti = true
    #else
    static let confetti = false
    #endif
    #if HAS_WRAPPINGHSTACK
    static let wrapping = true
    #else
    static let wrapping = false
    #endif
    #if HAS_DEFAULTS
    static let defaults = true
    #else
    static let defaults = false
    #endif
    #if HAS_MARKDOWNUI
    static let markdown = true
    #else
    static let markdown = false
    #endif
    #if HAS_INTROSPECT
    static let introspect = true
    #else
    static let introspect = false
    #endif
    #if HAS_CHARTS
    static let charts = true
    #else
    static let charts = false
    #endif
}

struct ContentView: View {
    @State private var tab = ProcessInfo.processInfo.environment["APPKITWIN_COMPAT_TAB"] ?? "shimmer"

    var body: some View {
        TabView(selection: $tab) {
            ForEach(Libraries.all) { entry in
                LibraryTab(entry: entry)
                    .tabItem { Text(entry.name) }
                    .tag(entry.id)
            }
        }
        .padding(8)
        .onAppear { Screenshots.scheduleIfRequested { tab = $0 } }
    }
}

/// A library's page: its header, then the demo or the reason it is excluded.
struct LibraryTab: View {
    let entry: LibraryEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(entry.name).font(.title2).bold()
                Text(entry.version).foregroundColor(.secondary)
                Spacer()
                Text(entry.included ? "built on \(Platform.name)" : "not built on \(Platform.name)")
                    .font(.caption)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(entry.included ? Color.green.opacity(0.25) : Color.orange.opacity(0.3)))
            }
            if entry.included {
                demo
            } else {
                Text("Excluded from this platform's build: \(entry.exclusion ?? "does not compile").")
                    .fixedSize(horizontal: false, vertical: true)
                Text("Re-check with `tools/library-compat.sh --probe`; the report is docs/compatibility/swiftui-libraries.md.")
                    .font(.caption).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(12)
    }

    @ViewBuilder private var demo: some View {
        switch entry.id {
        case "shimmer": ShimmerDemo()
        case "confetti": ConfettiDemo()
        case "wrapping": WrappingDemo()
        case "defaults": DefaultsDemo()
        case "markdown": MarkdownDemo()
        case "introspect": IntrospectDemo()
        case "charts": ChartsDemo()
        default: EmptyView()
        }
    }
}

enum Platform {
    static var name: String {
        #if os(Windows)
        return "Windows"
        #elseif os(Linux)
        return "Linux"
        #else
        return "macOS"
        #endif
    }
}

// MARK: Demos

struct ShimmerDemo: View {
    @State private var active = true
    var body: some View {
        #if HAS_SHIMMER
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Shimmering", isOn: $active)
            VStack(alignment: .leading, spacing: 8) {
                Text("Loading the library report…").font(.headline)
                RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.35)).frame(width: 320, height: 14)
                RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.35)).frame(width: 260, height: 14)
                RoundedRectangle(cornerRadius: 6).fill(Color.gray.opacity(0.35)).frame(width: 290, height: 14)
            }
            .shimmering(active: active)
            Text("Custom gradient, overlay mode").font(.headline)
                .shimmering(active: active, gradient: Gradient(colors: [.clear, .orange, .white, .green, .clear]), bandSize: 0.5, mode: .overlay())
            Text("`.shimmering()` masks the content with an animated LinearGradient (`.mask`, `Gradient`, `.animation(_:value:)`).")
                .font(.caption).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        #else
        EmptyView()
        #endif
    }
}

struct ConfettiDemo: View {
    @State private var counter = 0
    var body: some View {
        #if HAS_CONFETTI
        VStack(spacing: 16) {
            Text("Fired \(counter) time\(counter == 1 ? "" : "s")")
            Button("Celebrate") { counter += 1 }
                .confettiCannon(trigger: $counter, num: 40, confettiSize: 12, rainHeight: 320, radius: 220)
                .onAppear {
                    // Screenshots catch the confetti mid-air.
                    if Screenshots.trace { print("confetti: appeared, requested=\(Screenshots.requested)") }
                    if Screenshots.requested { DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { counter += 1; if Screenshots.trace { print("confetti: counter=\(counter)") } } }
                }
            Text("`.confettiCannon` animates shapes with `.offset`, `.opacity`, `.rotation3DEffect` and `withAnimation` timing curves.")
                .font(.caption).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
        #else
        EmptyView()
        #endif
    }
}

struct WrappingDemo: View {
    let tags = ["AppKit", "SwiftUI", "Windows", "Linux", "Direct2D", "DirectComposition", "Cairo", "Wayland", "X11", "Vulkan", "Metal", "CoreText", "Combine", "Accessibility", "Drag and drop"]
    var body: some View {
        #if HAS_WRAPPINGHSTACK
        VStack(alignment: .leading, spacing: 10) {
            WrappingHStack(tags, id: \.self, spacing: .constant(6), lineSpacing: 6) { tag in
                Text(tag)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(Color.blue.opacity(0.2)))
            }
            .frame(maxWidth: 420)
            Text("A tag cloud that wraps at the available width (`GeometryReader`, `anchorPreference`, `onPreferenceChange`, `NSHostingController.sizeThatFits`).")
                .font(.caption).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        #else
        EmptyView()
        #endif
    }
}

#if HAS_DEFAULTS
extension Defaults.Keys {
    static let greeting = Key<String>("libraryCompat.greeting", default: "Hello from Defaults")
    static let showsDetails = Key<Bool>("libraryCompat.showsDetails", default: true)
    static let launches = Key<Int>("libraryCompat.launches", default: 0)
}
#endif

struct DefaultsDemo: View {
    #if HAS_DEFAULTS
    @Default(.greeting) private var greeting
    @Default(.launches) private var launches
    #endif
    var body: some View {
        #if HAS_DEFAULTS
        VStack(alignment: .leading, spacing: 10) {
            TextField("Greeting", text: $greeting)
            Defaults.Toggle("Show details", key: .showsDetails)
            Text("Stored greeting: \(greeting)")
            Text("Launches so far: \(launches)")
            Text("`@Default` and `Defaults.Toggle` keep their values in UserDefaults; relaunch to see them persist.")
                .font(.caption).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear { launches += 1 }
        #else
        EmptyView()
        #endif
    }
}

struct MarkdownDemo: View {
    var body: some View {
        #if HAS_MARKDOWNUI
        ScrollView {
            Markdown("""
            # AppKitWin
            A **source-compatible** port of AppKit and SwiftUI to Windows and Linux.

            - Direct2D and DirectComposition on Windows
            - Cairo, X11 and Wayland on Linux
            - [x] Builds against the port's `SwiftUI`

            | Platform | Backend |
            | --- | --- |
            | Windows | Direct2D |
            | Linux | Cairo |

            > Markdown rendered by `swift-markdown-ui` (`Grid`, `Layout`, `Text(AttributedString)`, label styles).
            """)
            .padding(4)
        }
        #else
        EmptyView()
        #endif
    }
}

struct IntrospectDemo: View {
    @State private var text = "Introspected"
    var body: some View {
        #if HAS_INTROSPECT
        VStack(alignment: .leading, spacing: 10) {
            TextField("Text", text: $text)
                .introspect(.textField, on: .macOS(.v14, .v15, .v26)) { field in
                    field.backgroundColor = NSColor.systemYellow.withAlphaComponent(0.3)
                }
            Text("`.introspect(.textField)` hands the NSTextField behind the field to the closure.")
                .font(.caption).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        #else
        EmptyView()
        #endif
    }
}

struct ChartsDemo: View {
    #if HAS_CHARTS
    /// Monthly build counts as a line and as bars (`LineChart`, `BarChart`).
    @State private var line = LineChartData(
        dataSets: LineDataSet(
            dataPoints: [12, 18, 15, 24, 30, 27, 36].enumerated().map { LineChartDataPoint(value: $1, xAxisLabel: "M\($0 + 1)", description: "month \($0 + 1)") },
            legendTitle: "Builds",
            pointStyle: PointStyle(pointSize: 6, borderColour: .blue, fillColour: .white, lineWidth: 2, pointType: .filledOutLine, pointShape: .circle),
            style: LineStyle(lineColour: ColourStyle(colour: .blue), lineType: .curvedLine)),
        metadata: ChartMetadata(title: "Builds per month", subtitle: "SwiftUICharts LineChart"),
        chartStyle: LineChartStyle(infoBoxPlacement: .infoBox(isStatic: false), xAxisGridStyle: GridStyle(numberOfLines: 7), yAxisGridStyle: GridStyle(numberOfLines: 4), yAxisNumberOfLabels: 4, baseline: .zero, globalAnimation: .easeOut(duration: 0.8)))
    @State private var bars = BarChartData(
        dataSets: BarDataSet(dataPoints: [
            BarChartDataPoint(value: 9, xAxisLabel: "mac", description: "macOS", colour: ColourStyle(colour: .purple)),
            BarChartDataPoint(value: 14, xAxisLabel: "win", description: "Windows", colour: ColourStyle(colour: .orange)),
            BarChartDataPoint(value: 11, xAxisLabel: "lin", description: "Linux", colour: ColourStyle(colour: .green)),
        ], legendTitle: "Platforms"),
        metadata: ChartMetadata(title: "Jobs per platform", subtitle: "SwiftUICharts BarChart"),
        barStyle: BarStyle(barWidth: 0.6, cornerRadius: CornerRadius(top: 6, bottom: 0), colourFrom: .dataPoints),
        chartStyle: BarChartStyle(yAxisNumberOfLabels: 3, globalAnimation: .easeOut(duration: 0.8)))
    #endif
    var body: some View {
        #if HAS_CHARTS
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 16) {
                LineChart(chartData: line)
                    .pointMarkers(chartData: line)
                    .touchOverlay(chartData: line)
                    .xAxisGrid(chartData: line)
                    .yAxisGrid(chartData: line)
                    .xAxisLabels(chartData: line)
                    .yAxisLabels(chartData: line)
                    .headerBox(chartData: line)
                    .legends(chartData: line, columns: [GridItem(.flexible())])
                    .frame(minWidth: 240, minHeight: 180)
                BarChart(chartData: bars)
                    .touchOverlay(chartData: bars)
                    .yAxisGrid(chartData: bars)
                    .xAxisLabels(chartData: bars)
                    .yAxisLabels(chartData: bars)
                    .headerBox(chartData: bars)
                    .frame(minWidth: 200, minHeight: 180)
            }
            Text("`LineChart` and `BarChart` draw with `Path.trimmedPath`, `Shape.trim`/`.scale`, `LazyVGrid` legends, `.position`, `.zIndex` and a `DragGesture` touch overlay; the library imports `CoreGraphics.CGGeometry`.")
                .font(.caption).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        #else
        EmptyView()
        #endif
    }
}

// MARK: Screenshots

/// `--screenshot <dir>`: renders every tab into <dir>/library-compat-<tab>-<platform>.png
/// (through the view hierarchy, as the window draws it) and exits.
enum Screenshots {
    static var requested: Bool { CommandLine.arguments.contains("--screenshot") }
    static var trace: Bool { ProcessInfo.processInfo.environment["APPKITWIN_COMPAT_TRACE"] != nil }
    @MainActor static func scheduleIfRequested(select: @escaping (String) -> Void) {
        guard let i = CommandLine.arguments.firstIndex(of: "--screenshot"), i + 1 < CommandLine.arguments.count else { return }
        let dir = CommandLine.arguments[i + 1]
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        var remaining = Libraries.all.map(\.id)
        func next() {
            guard let id = remaining.first else {
                fflush(nil)
                exit(0)
            }
            remaining.removeFirst()
            if trace { print("screenshots: selecting \(id)") }
            select(id)
            // The headless host has no display cycle: lay the new tab out now so its
            // appearance handlers run before the capture.
            NSApp.windows.first(where: { $0.isVisible })?.contentView?.layoutSubtreeIfNeeded()
            // Let the tab lay out and its animations start (the shimmer band, the confetti) before capturing.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                write(id: id, to: dir)
                next()
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { next() }
    }

    @MainActor static func write(id: String, to dir: String) {
        guard let w = NSApp.windows.first(where: { $0.isVisible }), let cv = w.contentView else { return }
        cv.layoutSubtreeIfNeeded()
        w.display()
        guard let rep = cv.bitmapImageRepForCachingDisplay(in: cv.bounds) else { return }
        cv.cacheDisplay(in: cv.bounds, to: rep)
        let composed = NSImage(size: cv.bounds.size)
        composed.lockFocus()
        w.effectiveAppearance.performAsCurrentDrawingAppearance {
            w.backgroundColor.setFill()
            NSBezierPath.fill(NSRect(origin: .zero, size: cv.bounds.size))
        }
        if let cg = rep.cgImage { NSGraphicsContext.current?.cgContext.draw(cg, in: NSRect(origin: .zero, size: cv.bounds.size)) }
        composed.unlockFocus()
        guard let final = composed.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        if let png = NSBitmapImageRep(cgImage: final).representation(using: .png, properties: [:]) {
            let path = (dir as NSString).appendingPathComponent("library-compat-\(id)-\(Platform.name.lowercased()).png")
            try? png.write(to: URL(fileURLWithPath: path))
            print("screenshot: \(path)")
        }
    }
}
