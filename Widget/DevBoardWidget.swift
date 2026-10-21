import SwiftUI
import WidgetKit

// MARK: - Timeline (shared by all widgets)

struct Entry: TimelineEntry {
    let date: Date
    let snapshot: Snapshot

    static func live() async -> Entry { Entry(date: Date(), snapshot: await Refresher.shared.snapshot()) }
    static var cached: Entry { Entry(date: Date(), snapshot: SnapshotStore.load() ?? .sample) }
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry { .cached }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        if context.isPreview { completion(.cached); return }
        Task { completion(await Entry.live()) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        Task {
            let entry = await Entry.live()
            // Hourly, and just after midnight so the daily questions roll over on time.
            let cal = Calendar.current
            let tomorrow = cal.startOfDay(for: cal.date(byAdding: .day, value: 1, to: Date())!)
            // If today's questions couldn't be generated, retry in 10 minutes instead of an hour.
            let haveQuestions = entry.snapshot.csDate == SnapshotStore.csKey()
            let next = min(Date().addingTimeInterval(haveQuestions ? 3600 : 600), tomorrow.addingTimeInterval(60))
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }
}

// MARK: - Style

enum Theme {
    static let leetcode = Color(red: 1.00, green: 0.63, blue: 0.09)
    static let github = Color(red: 0.25, green: 0.77, blue: 0.39)
    static let design = Color(red: 0.96, green: 0.42, blue: 0.60)
    static let build = Color(red: 0.36, green: 0.80, blue: 0.85)
    static let cs = Color(red: 0.55, green: 0.55, blue: 1.00)

    static func subject(_ s: String) -> Color {
        switch s {
        case "OS": Color(red: 0.20, green: 0.78, blue: 0.70)
        case "CN": Color(red: 0.32, green: 0.62, blue: 1.00)
        case "Infra": Color(red: 1.00, green: 0.62, blue: 0.30)
        default: Color(red: 0.70, green: 0.52, blue: 1.00)
        }
    }

    static func subjectIcon(_ s: String) -> String {
        switch s {
        case "OS": "cpu"
        case "CN": "network"
        case "Infra": "cloud.fill"
        default: "cylinder.split.1x2"
        }
    }

    static let resume = Color(red: 0.98, green: 0.78, blue: 0.25)

    static func language(_ l: String) -> Color {
        switch l {
        case "Java": Color(red: 0.96, green: 0.52, blue: 0.20)
        case "Python": Color(red: 0.35, green: 0.62, blue: 0.95)
        case "C++": Color(red: 0.55, green: 0.55, blue: 1.00)
        default: Color(red: 0.62, green: 0.70, blue: 0.80)
        }
    }

    static func difficulty(_ d: String) -> Color {
        switch d.lowercased() {
        case "easy": Color(red: 0.00, green: 0.72, blue: 0.64)
        case "medium": Color(red: 1.00, green: 0.72, blue: 0.00)
        default: Color(red: 1.00, green: 0.30, blue: 0.40)
        }
    }
}

/// Brand logo shipped as a template PNG in the bundle (from Simple Icons).
struct BrandIcon: View {
    let name: String
    let size: CGFloat

    var body: some View {
        if let url = Bundle.main.url(forResource: name, withExtension: "png"), let img = NSImage(contentsOf: url) {
            Image(nsImage: img)
                .renderingMode(.template)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
        }
    }
}

/// Section header: icon + small caps label.
struct SectionLabel: View {
    let text: String
    let symbol: String?
    let brand: String?
    let color: Color

    init(_ text: String, symbol: String? = nil, brand: String? = nil, color: Color) {
        self.text = text
        self.symbol = symbol
        self.brand = brand
        self.color = color
    }

    var body: some View {
        HStack(spacing: 6) {
            Group {
                if let brand {
                    BrandIcon(name: brand, size: 11)
                } else if let symbol {
                    Image(systemName: symbol).font(.system(size: 10, weight: .semibold))
                }
            }
            .foregroundStyle(color)
            Text(text.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(.secondary)
        }
    }
}

struct Pill: View {
    let text: String
    let color: Color
    var symbol: String? = nil

    var body: some View {
        HStack(spacing: 3) {
            if let symbol { Image(systemName: symbol).font(.system(size: 8, weight: .bold)) }
            Text(text)
        }
        .font(.system(size: 9.5, weight: .semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 7)
        .padding(.vertical, 2.5)
        .background(color.opacity(0.15), in: Capsule())
        .lineLimit(1)
    }
}

/// The only tappable text in the widgets: a title with a small ↗.
struct LinkTitle: View {
    let text: String
    let url: URL
    var size: CGFloat = 13
    var lines: Int = 1

    var body: some View {
        Link(destination: url) {
            // The arrow sits outside the text so it stays visible when the title is truncated.
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(text)
                    .font(.system(size: size, weight: .semibold))
                    .lineLimit(lines)
                    .multilineTextAlignment(.leading)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: size * 0.62, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

struct WidgetCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .containerBackground(for: .widget) { Color(nsColor: .windowBackgroundColor) }
            .widgetURL(Config.noopURL) // taps outside titles do nothing
    }
}

struct FooterHint: View {
    let text: String
    let symbol: String
    let color: Color

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(color.opacity(0.9))
    }
}

// MARK: - Activity widget

/// Last 13 weeks (~3 months): columns are weeks, rows are weekdays, month labels on top.
struct QuarterHeatmap: View {
    let levels: [String: Int]
    let tint: Color

    static let weeks = 13
    static let cell: CGFloat = 10
    static let gap: CGFloat = 3
    static let labelHeight: CGFloat = 14
    static var size: CGSize {
        CGSize(width: CGFloat(weeks) * (cell + gap) - gap, height: labelHeight + 7 * (cell + gap) - gap)
    }

    var body: some View {
        Canvas { ctx, _ in
            let cal = Calendar.current
            let today = cal.startOfDay(for: Date())
            let offset = (cal.component(.weekday, from: today) - cal.firstWeekday + 7) % 7
            guard let start = cal.date(byAdding: .day, value: -(offset + (Self.weeks - 1) * 7), to: today) else { return }
            let opacity: [Double] = [0, 0.32, 0.55, 0.78, 1]
            let step = Self.cell + Self.gap

            for c in 0..<Self.weeks {
                for r in 0..<7 {
                    guard let day = cal.date(byAdding: .day, value: c * 7 + r, to: start) else { continue }
                    let x = CGFloat(c) * step
                    if cal.component(.day, from: day) == 1, c < Self.weeks - 1 {
                        let month = Text(day.formatted(.dateTime.month(.abbreviated)))
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.secondary)
                        ctx.draw(month, at: CGPoint(x: x, y: 0), anchor: .topLeading)
                    }
                    guard day <= today else { continue }
                    let rect = CGRect(x: x, y: Self.labelHeight + CGFloat(r) * step, width: Self.cell, height: Self.cell)
                    let level = min(levels[DayKey.local.string(from: day)] ?? 0, 4)
                    ctx.fill(Path(roundedRect: rect, cornerRadius: 2.5),
                             with: .color(level == 0 ? .primary.opacity(0.07) : tint.opacity(opacity[level])))
                    if day == today {
                        ctx.stroke(Path(roundedRect: rect.insetBy(dx: -1.5, dy: -1.5), cornerRadius: 3.5),
                                   with: .color(.primary.opacity(0.4)), lineWidth: 1)
                    }
                }
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
    }
}

struct Stat<Icon: View>: View {
    let value: String
    let label: String
    @ViewBuilder let icon: () -> Icon

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .center, spacing: 5) {
                icon()
                Text(value)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

struct StreakFlame: View {
    let active: Bool

    var body: some View {
        Image(systemName: "flame.fill")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(active
                ? AnyShapeStyle(LinearGradient(colors: [Color(red: 1, green: 0.84, blue: 0.2), Color(red: 1, green: 0.42, blue: 0.1)],
                                               startPoint: .top, endPoint: .bottom))
                : AnyShapeStyle(.tertiary))
    }
}

struct ActivityBlock: View {
    let title: String
    let logo: String
    let logoColor: Color
    let tint: Color
    let data: Heatmap?
    let url: URL
    let secondaryValue: String
    let secondaryLabel: String
    let secondaryIcon: String
    var configured = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                // Only the logo + name open the profile.
                Link(destination: url) {
                    HStack(spacing: 6) {
                        BrandIcon(name: logo, size: 14).foregroundStyle(logoColor)
                        Text(title).font(.system(size: 12.5, weight: .semibold))
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer()
                if data?.activeToday == true {
                    Pill(text: "Today", color: tint, symbol: "checkmark")
                } else {
                    Text(!configured ? "Set username in config.json" : data == nil ? "Unavailable" : "Not yet today")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
            }
            HStack(alignment: .bottom, spacing: 0) {
                QuarterHeatmap(levels: data?.levels ?? [:], tint: tint)
                Spacer(minLength: 12)
                VStack(alignment: .leading, spacing: 8) {
                    let streak = data?.currentStreak ?? 0
                    Stat(value: data == nil ? "–" : "\(streak)", label: "day streak") {
                        StreakFlame(active: streak > 0)
                    }
                    Stat(value: data == nil ? "–" : secondaryValue, label: secondaryLabel) {
                        Image(systemName: secondaryIcon)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(tint)
                    }
                }
                .frame(width: 104, alignment: .leading)
            }
        }
    }
}

struct ActivityView: View {
    let entry: Entry

    var body: some View {
        let s = entry.snapshot
        WidgetCard {
            VStack(alignment: .leading, spacing: 0) {
                ActivityBlock(title: "LeetCode", logo: "leetcode", logoColor: Theme.leetcode, tint: Theme.leetcode,
                              data: s.leetcode, url: Config.leetCodeProfile,
                              secondaryValue: s.leetcode?.solved.map(String.init) ?? "–", secondaryLabel: "problems solved",
                              secondaryIcon: "checkmark.seal.fill", configured: Config.leetCodeUser != nil)
                Divider().opacity(0.6).padding(.vertical, 12)
                ActivityBlock(title: "GitHub", logo: "github", logoColor: .primary, tint: Theme.github,
                              data: s.github, url: Config.gitHubProfile,
                              secondaryValue: "\(s.github?.total ?? 0)", secondaryLabel: "contributions / yr",
                              secondaryIcon: "arrow.triangle.branch", configured: Config.gitHubUser != nil)
                Spacer(minLength: 0)
                HStack {
                    Label(s.fetchedAt > .distantPast
                          ? "Updated \(s.fetchedAt.formatted(date: .omitted, time: .shortened))"
                          : "Not updated yet", systemImage: "clock")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Link(destination: Config.refreshURL) {
                        Label("Refresh", systemImage: "arrow.clockwise")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(.primary.opacity(0.08), in: Capsule())
                    }
                }
            }
        }
    }
}

// MARK: - Today widget (LeetCode daily + system design)

struct BlurredHints: View {
    let hints: [String]
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(hints.prefix(3).enumerated()), id: \.offset) { n, hint in
                HStack(spacing: 8) {
                    Text("\(n + 1)")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(color)
                        .frame(width: 16, height: 16)
                        .background(color.opacity(0.14), in: Circle())
                    Text(hint)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .blur(radius: 3.5)
                }
            }
        }
    }
}

struct TodayView: View {
    let entry: Entry
    let family: WidgetFamily

    private var large: Bool { family == .systemLarge }

    var body: some View {
        WidgetCard {
            VStack(alignment: .leading, spacing: 0) {
                daily
                Divider().opacity(0.6).padding(.vertical, large ? 14 : 10)
                design
            }
        }
    }

    private var daily: some View {
        let d = entry.snapshot.daily
        return VStack(alignment: .leading, spacing: large ? 7 : 5) {
            HStack {
                SectionLabel("Daily problem", brand: "leetcode", color: Theme.leetcode)
                Spacer()
                if let d { Pill(text: d.difficulty, color: Theme.difficulty(d.difficulty)) }
            }
            if let d, let url = URL(string: d.url) {
                LinkTitle(text: d.title, url: url, size: large ? 15 : 13, lines: large ? 2 : 1)
            } else {
                Text("Unavailable right now").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
            }
            if large, let tags = d?.tags, !tags.isEmpty {
                Label(tags.joined(separator: " · "), systemImage: "tag")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder private var design: some View {
        if let q = entry.snapshot.systemDesign {
            VStack(alignment: .leading, spacing: large ? 7 : 4) {
                HStack {
                    SectionLabel("System design", symbol: "server.rack", color: Theme.design)
                    Spacer()
                    if q.isResume {
                        Pill(text: "From your resume", color: Theme.resume, symbol: "person.text.rectangle")
                    } else {
                        Pill(text: q.category, color: Theme.design)
                    }
                }
                LinkTitle(text: q.title, url: Config.hintsURL(q.payload), size: large ? 15 : 13, lines: large ? 2 : 1)
                Text(q.prompt)
                    .font(.system(size: large ? 12 : 11))
                    .foregroundStyle(.secondary)
                    .lineSpacing(large ? 2 : 0)
                    .lineLimit(large ? 4 : 2)
                if large {
                    Spacer(minLength: 10)
                    BlurredHints(hints: q.hints, color: Theme.design)
                    Spacer(minLength: 10)
                    FooterHint(text: "Open the question for hints & notes", symbol: "lightbulb", color: Theme.design)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel("System design", symbol: "server.rack", color: Theme.design)
                Text(CSGenerator.apiKey == nil ? "Add an AI API key: run ./setup.sh again." : "Generating today's question…")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - CS fundamentals widget (OS, CN, DBMS — generated on device)

struct CSRow: View {
    let q: CSQuestion
    let large: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Label(q.subject, systemImage: Theme.subjectIcon(q.subject))
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.subject(q.subject))
                .frame(width: 54, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if q.isResume {
                        Image(systemName: "person.text.rectangle")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.resume)
                    }
                    LinkTitle(text: q.title, url: Config.hintsURL(q.payload), size: 12, lines: large ? 2 : 1)
                }
                if large {
                    Text(q.prompt)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct CSView: View {
    let entry: Entry
    let family: WidgetFamily

    var body: some View {
        let large = family == .systemLarge
        let qs = entry.snapshot.fundamentals
        WidgetCard {
            VStack(alignment: .leading, spacing: large ? 11 : 8) {
                HStack {
                    SectionLabel("CS fundamentals", symbol: "graduationcap.fill", color: Theme.cs)
                    Spacer()
                    Label("OS · CN · DBMS · Infra", systemImage: "sparkles")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
                if qs.isEmpty {
                    Text(CSGenerator.apiKey == nil
                         ? "Add an AI API key: run ./setup.sh again."
                         : "Generating today's questions…")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                ForEach(Array(qs.enumerated()), id: \.offset) { n, q in
                    if large && n > 0 { Divider().opacity(0.5) }
                    CSRow(q: q, large: large)
                }
                Spacer(minLength: 0)
                if large || qs.isEmpty {
                    FooterHint(text: "Open a question for hints & notes", symbol: "lightbulb", color: Theme.cs)
                }
            }
        }
    }
}

// MARK: - Build idea widget

struct RepoRow: View {
    let repo: FreshRepo

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let url = URL(string: repo.url) {
                LinkTitle(text: repo.name, url: url, size: 12)
            }
            Text(repo.description)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(2)
            HStack(spacing: 8) {
                Label("\(repo.stars)", systemImage: "star.fill")
                if !repo.language.isEmpty {
                    Label(repo.language, systemImage: "chevron.left.forwardslash.chevron.right")
                        .foregroundStyle(Theme.language(repo.language))
                }
            }
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct BuildView: View {
    let entry: Entry
    let family: WidgetFamily

    var body: some View {
        let large = family == .systemLarge
        let idea = entry.snapshot.idea
        let topic = entry.snapshot.freshTopic ?? "tech"
        WidgetCard {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        SectionLabel("Build idea", symbol: "hammer.fill", color: Theme.build)
                        Spacer()
                        if let idea {
                            Pill(text: idea.language, color: Theme.language(idea.language),
                                 symbol: "chevron.left.forwardslash.chevron.right")
                        }
                    }
                    if let idea, let url = URL(string: idea.url) {
                        LinkTitle(text: idea.title, url: url, size: large ? 15 : 14, lines: 2)
                        Label("Build your own \(idea.category.lowercased())", systemImage: "square.stack.3d.up")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else {
                        Text("Unavailable right now").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                    }
                }
                if large, let fresh = entry.snapshot.fresh, !fresh.isEmpty {
                    Divider().opacity(0.6).padding(.vertical, 12)
                    HStack {
                        SectionLabel("Fresh in \(topic)", symbol: "sparkles", color: Theme.build)
                        Spacer()
                        HStack(spacing: 4) {
                            BrandIcon(name: "github", size: 10)
                            Text("GitHub")
                        }
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    }
                    .padding(.bottom, 9)
                    VStack(alignment: .leading, spacing: 9) {
                        ForEach(fresh.prefix(3), id: \.self) { RepoRow(repo: $0) }
                    }
                }
                Spacer(minLength: 0)
                if !large, let top = entry.snapshot.fresh?.first, let url = URL(string: top.url) {
                    HStack(spacing: 5) {
                        Image(systemName: "sparkles").foregroundStyle(Theme.build)
                        Text("Fresh in \(topic):").foregroundStyle(.secondary)
                        Link(destination: url) {
                            (Text(top.name.components(separatedBy: "/").last ?? top.name).fontWeight(.semibold)
                             + Text(" ") + Text(Image(systemName: "arrow.up.right")).font(.system(size: 7, weight: .bold)))
                                .lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        Label("\(top.stars)", systemImage: "star.fill").foregroundStyle(.tertiary)
                    }
                    .font(.system(size: 10.5))
                }
            }
        }
    }
}

// MARK: - Widgets

struct FamilyReader<Content: View>: View {
    @Environment(\.widgetFamily) private var family
    let content: (WidgetFamily) -> Content
    var body: some View { content(family) }
}

struct ActivityWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DevBoardActivity", provider: Provider()) { ActivityView(entry: $0) }
            .configurationDisplayName("Activity")
            .description("LeetCode and GitHub heatmaps for the last 3 months.")
            .supportedFamilies([.systemLarge])
    }
}

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DevBoardToday", provider: Provider()) { entry in
            FamilyReader { TodayView(entry: entry, family: $0) }
        }
        .configurationDisplayName("Today")
        .description("LeetCode daily problem and an AI-written system design question with hints.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct CSWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DevBoardCS", provider: Provider()) { entry in
            FamilyReader { CSView(entry: entry, family: $0) }
        }
        .configurationDisplayName("CS Fundamentals")
        .description("Fresh daily OS, Networks, DBMS and Infra questions with hints, written by AI.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct BuildWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DevBoardBuild", provider: Provider()) { entry in
            FamilyReader { BuildView(entry: entry, family: $0) }
        }
        .configurationDisplayName("Build Idea")
        .description("A daily backend/systems project to build in C, C++, Java or Python.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

@main
struct DevBoardBundle: WidgetBundle {
    var body: some Widget {
        ActivityWidget()
        TodayWidget()
        CSWidget()
        BuildWidget()
    }
}

// MARK: - Sample data (widget gallery preview)

extension Snapshot {
    static var sample: Snapshot {
        var lc: [String: Int] = [:], gh: [String: Int] = [:]
        let cal = Calendar.current
        for i in 0..<120 {
            let key = DayKey.local.string(from: cal.date(byAdding: .day, value: -i, to: Date())!)
            lc[key] = (i * 7 + 3) % 5 == 0 ? 0 : (i * 13) % 5
            gh[key] = (i * 11) % 6 > 3 ? 0 : (i * 3) % 5
        }
        return Snapshot(
            leetcode: Heatmap(levels: lc, total: 512, summary: "", solved: 245),
            github: Heatmap(levels: gh, total: 350, summary: ""),
            daily: DailyProblem(title: "LRU Cache", difficulty: "Medium", url: "https://leetcode.com/problems/lru-cache/",
                                date: "", tags: ["Hash Table", "Design"]),
            idea: ProjectIdea(category: "Database", language: "Python", title: "DBDB: Dog Bed Database",
                              url: "https://github.com/codecrafters-io/build-your-own-x"),
            fetchedAt: Date())
    }
}
