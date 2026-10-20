import AppKit
import SwiftUI
import WidgetKit

/// Background helper. macOS routes every link tapped in a widget to its containing app, so this handles them all:
///   http(s)://...              → open in the default browser, then quit
///   devboard://refresh         → reload widget timelines, then quit
///   devboard://hints?q=<b64>   → show the question's hints page (with "Write answer in Notes")
///   devboard://none            → background tap; do nothing
@main
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: NSWindow?
    private var handledURL = false

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Opened directly (not via a widget link): reload and show setup instructions.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [self] in
            guard !handledURL else { return }
            WidgetCenter.shared.reloadAllTimelines()
            show(title: "DevBoard", size: NSSize(width: 440, height: 250), view: WelcomeView())
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        handledURL = true
        guard let url = urls.first else { return }
        if url.scheme == "http" || url.scheme == "https" {
            NSWorkspace.shared.open(url)
        } else if url.host == "refresh" {
            WidgetCenter.shared.reloadAllTimelines()
        } else if url.host == "hints",
                  let encoded = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "q" })?.value,
                  let q = QuestionPayload.decode(base64url: encoded) {
            show(title: q.tag, size: NSSize(width: 580, height: 560), view: HintsView(question: q, progress: HintProgress()))
            return
        }
        if window == nil { quitSoon() }
    }

    private func show(title: String, size: NSSize, view: some View) {
        let w = window ?? NSWindow(contentRect: NSRect(origin: .zero, size: size),
                                   styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        w.title = title
        w.titleVisibility = .hidden
        w.titlebarAppearsTransparent = true
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.contentView = NSHostingView(rootView: view)
        w.setContentSize(size)
        w.center()
        window = w
        NSApp.activate()
        w.makeKeyAndOrderFront(nil)
        w.orderFrontRegardless()
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        quitSoon()
    }

    private func quitSoon() {
        // Give WidgetKit's XPC message time to go out before exiting.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { NSApp.terminate(nil) }
    }
}

// MARK: - Hints page

final class HintProgress: ObservableObject {
    @Published var revealed = 0
    @Published var notesError: String?
}

struct HintsView: View {
    let question: QuestionPayload
    @ObservedObject var progress: HintProgress

    private var accent: Color {
        if question.tag.hasPrefix("OS") { return Color(red: 0.20, green: 0.78, blue: 0.70) }
        if question.tag.hasPrefix("CN") { return Color(red: 0.32, green: 0.62, blue: 1.00) }
        if question.tag.hasPrefix("DBMS") { return Color(red: 0.70, green: 0.52, blue: 1.00) }
        if question.tag.hasPrefix("Infra") { return Color(red: 1.00, green: 0.62, blue: 0.30) }
        return Color(red: 0.96, green: 0.42, blue: 0.60)
    }

    private var icon: String {
        if question.tag.hasPrefix("OS") { return "cpu" }
        if question.tag.hasPrefix("CN") { return "network" }
        if question.tag.hasPrefix("DBMS") { return "cylinder.split.1x2" }
        if question.tag.hasPrefix("Infra") { return "cloud.fill" }
        return "server.rack"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(question.tag, systemImage: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(accent)
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(accent.opacity(0.14), in: Capsule())
            Text(question.title)
                .font(.system(size: 21, weight: .bold))
                .fixedSize(horizontal: false, vertical: true)
            Text(question.prompt)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            HStack(spacing: 6) {
                Image(systemName: "lightbulb.fill").foregroundStyle(accent)
                Text("Hints").font(.system(size: 13, weight: .semibold))
                Text("\(progress.revealed)/\(question.hints.count)")
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(.tertiary)
                Spacer()
                if progress.revealed == 0 {
                    Text("Think it through first").font(.system(size: 12)).foregroundStyle(.tertiary)
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(question.hints.enumerated()), id: \.offset) { i, hint in
                        HStack(alignment: .top, spacing: 10) {
                            Text("\(i + 1)")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(accent)
                                .frame(width: 22, height: 22)
                                .background(accent.opacity(0.16), in: Circle())
                            Text(hint)
                                .font(.system(size: 13.5))
                                .lineSpacing(2)
                                .fixedSize(horizontal: false, vertical: true)
                                .blur(radius: i < progress.revealed ? 0 : 5)
                                .opacity(i < progress.revealed ? 1 : 0.5)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let err = progress.notesError {
                Label(err, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
            }
            HStack(spacing: 10) {
                if progress.revealed < question.hints.count {
                    Button {
                        withAnimation(.easeOut(duration: 0.25)) { progress.revealed += 1 }
                    } label: {
                        Label(progress.revealed == 0 ? "Reveal first hint" : "Next hint", systemImage: "eye")
                    }
                    .keyboardShortcut(.space, modifiers: [])
                    Button("Show all") { withAnimation(.easeOut(duration: 0.25)) { progress.revealed = question.hints.count } }
                        .buttonStyle(.borderless)
                }
                Spacer()
                Button {
                    if let err = NotesBridge.open(question) {
                        progress.notesError = err + " Allow DevBoard in System Settings › Privacy & Security › Automation."
                    } else {
                        NSApp.keyWindow?.close()
                    }
                } label: {
                    Label("Write answer in Notes", systemImage: "square.and.pencil")
                }
                .keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
        }
        .padding(.horizontal, 28)
        .padding(.top, 36)
        .padding(.bottom, 22)
        .frame(minWidth: 580, minHeight: 560)
    }
}

// MARK: - Notes

/// Talks to Notes over AppleScript. One note per question, titled with the question, in the "Daily Problems" folder.
enum NotesBridge {
    static let hintsHeading = "💡 Hints"

    /// Returns an error message, or nil on success.
    static func open(_ q: QuestionPayload) -> String? {
        let date = Date().formatted(date: .abbreviated, time: .omitted)
        let body = """
        <div><h1>\(html(q.noteTitle))</h1></div>\
        <div><i>\(html(q.tag)) · \(html(date))</i></div><div><br></div>\
        <div>\(html(q.prompt))</div><div><br></div>\
        <div><h2>My answer</h2></div><div><br></div><div><br></div><div><br></div><div><br></div>
        """
        // Hints go last, below the answer space, so they're only seen when scrolled to.
        let hints = q.hints.isEmpty ? "" : "<div><br></div><div><h2>\(hintsHeading)</h2></div><ol>"
            + q.hints.map { "<li>\(html($0))</li>" }.joined() + "</ol>"
        let folder = applescript(Config.notesFolder)
        let script = """
        tell application "Notes"
            set acct to default account
            if not (exists folder \(folder) of acct) then make new folder at acct with properties {name:\(folder)}
            set f to folder \(folder) of acct
            set matches to (every note of f whose name is \(applescript(q.noteTitle)))
            if (count of matches) > 0 then
                set n to item 1 of matches
            else
                set n to make new note at f with properties {body:\(applescript(body + hints))}
            end if
            if \(q.hints.isEmpty ? "false" : "true") and (plaintext of n does not contain "Hints") then
                set body of n to (body of n) & \(applescript(hints))
            end if
            show n
            activate
        end tell
        """
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
        return error.map { ($0[NSAppleScript.errorMessage] as? String) ?? "Unknown AppleScript error." }
    }

    private static func applescript(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    private static func html(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

struct WelcomeView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("DevBoard is installed").font(.system(size: 20, weight: .bold))
            Text("Add it to Notification Center:").foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                Label("Click the date & time in the menu bar → Edit Widgets", systemImage: "1.circle.fill")
                Label("Search “DevBoard”", systemImage: "2.circle.fill")
                Label("Add Activity, Today, CS Fundamentals and Build Idea", systemImage: "3.circle.fill")
            }
            .font(.system(size: 13))
            HStack {
                Spacer()
                Button("Got it") { NSApp.keyWindow?.close() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 34)
        .padding(.bottom, 20)
        .frame(width: 440, height: 250)
    }
}
