// Renders README screenshots of every widget layout and the hints page from demo data (no network, no personal data).
// Run via Tools/screenshots/render.sh
import AppKit
import SwiftUI
import WidgetKit

enum Demo {
    static var snapshot: Snapshot {
        var lc: [String: Int] = [:], gh: [String: Int] = [:]
        let cal = Calendar.current
        for i in 0..<100 {
            let key = DayKey.local.string(from: cal.date(byAdding: .day, value: -i, to: Date())!)
            let wave = (i * 37 + 11) % 17
            lc[key] = i < 12 ? [1, 2, 3, 2, 4][i % 5] : (wave < 6 ? 0 : wave % 5)
            gh[key] = i < 5 ? [2, 3, 1, 4, 2][i] : ((i * 29 + 5) % 13 < 4 ? 0 : (i * 7) % 5)
        }
        let hints = [
            "Ask what each poll loop is doing between two calls to poll().",
            "Compare the batch processing time with max.poll.interval.ms.",
            "When a member misses that deadline the coordinator evicts it and rebalances everyone.",
            "Smaller batches, faster writes and cooperative-sticky assignment stop the loop.",
        ]
        return Snapshot(
            leetcode: Heatmap(levels: lc, total: 1280, summary: "", solved: 342),
            github: Heatmap(levels: gh, total: 1284, summary: ""),
            daily: DailyProblem(title: "LRU Cache", difficulty: "Medium", url: "https://leetcode.com/problems/lru-cache/",
                                date: "", tags: ["Hash Table", "Linked List", "Design"]),
            idea: ProjectIdea(category: "Database", language: "C", title: "Let's Build a Simple Database",
                              url: "https://cstack.github.io/db_tutorial/"),
            freshTopic: "Payments",
            fresh: [
                FreshRepo(name: "example/ledger-core", description: "Double-entry ledger service with idempotent transfers and an outbox for events.",
                          url: "https://github.com", stars: 2140, language: "Java"),
                FreshRepo(name: "example/upi-sim", description: "Local simulator for UPI collect and pay flows, with webhooks and retries.",
                          url: "https://github.com", stars: 860, language: "Python"),
                FreshRepo(name: "example/tinyhsm", description: "Software HSM for signing payment messages, written for learning.",
                          url: "https://github.com", stars: 412, language: "C"),
            ],
            cs: [
                CSQuestion(subject: "OS", topic: "spinlocks", title: "When does a spinlock beat a mutex, and when does it burn CPU?",
                           prompt: "64 threads share 8 cores and latency explodes under a spinlock. Explain why.", hints: hints),
                CSQuestion(subject: "CN", topic: "TCP teardown", title: "Why does a busy proxy run out of ports with TIME_WAIT sockets?",
                           prompt: "Outbound connections start failing with EADDRNOTAVAIL. Find the cause.", hints: hints),
                CSQuestion(subject: "DBMS", topic: "your experience", title: "In your dispatch service, why did you shard Redis by geography?",
                           prompt: "Walk through hot cells, cross-shard queries and what happens when a shard fails.", hints: hints, fromResume: true),
                CSQuestion(subject: "Infra", topic: "CPU limits", title: "Why are pods throttled at 30% average CPU usage?",
                           prompt: "Dashboards show low CPU but high p99. Explain CFS quotas and what you would change.", hints: hints),
                CSQuestion(subject: "SD", topic: "Kafka: consumer lag with constant rebalances",
                           title: "Why does consumer lag grow while the group rebalances every few minutes?",
                           prompt: "Each poll batch does database writes and the group keeps evicting members. Diagnose and fix it.", hints: hints),
            ],
            csDate: SnapshotStore.csKey(),
            fetchedAt: Date())
    }
}

func tile(_ v: some View, _ h: CGFloat) -> some View {
    v.padding(16)
        .frame(width: 344, height: h)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 27.88, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
}

func backdrop(dark: Bool) -> LinearGradient {
    LinearGradient(colors: dark ? [Color(red: 0.12, green: 0.10, blue: 0.22), Color(red: 0.30, green: 0.10, blue: 0.25)]
                                : [Color(red: 0.78, green: 0.84, blue: 0.98), Color(red: 0.96, green: 0.80, blue: 0.88)],
                   startPoint: .topLeading, endPoint: .bottomTrailing)
}

@MainActor func render(_ v: some View, dark: Bool, to path: String) {
    let r = ImageRenderer(content: v.environment(\.colorScheme, dark ? .dark : .light))
    r.scale = 2
    NSAppearance(named: dark ? .darkAqua : .aqua)!.performAsCurrentDrawingAppearance {
        guard let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { print("render failed: \(path)"); return }
        try! png.write(to: URL(fileURLWithPath: path))
        print("wrote \(path)")
    }
}

@main
struct RenderScreenshots {
    @MainActor static func main() {
        let out = CommandLine.arguments.dropFirst().first ?? "docs/screenshots"
        let e = Entry(date: Date(), snapshot: Demo.snapshot)
        for dark in [true, false] {
            let stack = VStack(spacing: 14) {
                tile(ActivityView(entry: e), 344)
                tile(TodayView(entry: e, family: .systemMedium), 164)
                tile(CSView(entry: e, family: .systemMedium), 164)
                tile(BuildView(entry: e, family: .systemMedium), 164)
            }
            .padding(28)
            .background(backdrop(dark: dark))
            render(stack, dark: dark, to: "\(out)/stack-\(dark ? "dark" : "light").png")
        }
        let large = HStack(alignment: .top, spacing: 16) {
            tile(TodayView(entry: e, family: .systemLarge), 344)
            tile(CSView(entry: e, family: .systemLarge), 344)
            tile(BuildView(entry: e, family: .systemLarge), 344)
        }
        .padding(28)
        .background(backdrop(dark: true))
        render(large, dark: true, to: "\(out)/large-dark.png")

        let progress = HintProgress()
        progress.revealed = 2
        let q = Demo.snapshot.systemDesign!.payload
        let hints = HintsView(question: q, progress: progress)
            .frame(width: 580, height: 560)
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(28)
            .background(backdrop(dark: true))
        render(hints, dark: true, to: "\(out)/hints-dark.png")
    }
}
