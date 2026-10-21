import Foundation

/// User settings, read from config.json in the bundle (setup.sh / build.sh copy it from ~/.config/devboard/config.json).
/// The widget is sandboxed, so it can only read files shipped inside its own bundle.
enum Config {
    private struct File: Decodable {
        var leetcode_username: String?
        var github_username: String?
        var notes_folder: String?
        var resume_questions: Bool?
        var ai_provider: String?
        var ai_model: String?
        var ai_base_url: String?
    }

    private static let file: File = {
        guard let url = Bundle.main.url(forResource: "config", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let f = try? JSONDecoder().decode(File.self, from: data) else { return File() }
        return f
    }()

    private static func clean(_ s: String?) -> String? {
        guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return t
    }

    static var leetCodeUser: String? { clean(file.leetcode_username) }
    static var gitHubUser: String? { clean(file.github_username) }
    static var notesFolder: String { clean(file.notes_folder) ?? "Daily Problems" }
    static var resumeQuestions: Bool { file.resume_questions ?? true }
    /// "gemini" (default), "claude", or "openai" (any OpenAI-compatible Chat Completions API).
    static var aiProvider: String { clean(file.ai_provider)?.lowercased() ?? "gemini" }
    /// Overrides the provider's default model(s).
    static var aiModel: String? { clean(file.ai_model) }
    /// Base URL for "openai": OpenAI, OpenRouter, Groq, Together, a local Ollama or LM Studio…
    static var aiBaseURL: String { clean(file.ai_base_url) ?? "https://api.openai.com/v1" }
    static let urlScheme = "devboard"

    static var leetCodeProfile: URL {
        URL(string: leetCodeUser.map { "https://leetcode.com/u/\($0)/" } ?? "https://leetcode.com")!
    }
    static var gitHubProfile: URL { URL(string: gitHubUser.map { "https://github.com/\($0)" } ?? "https://github.com")! }
    static var refreshURL: URL { URL(string: "\(urlScheme)://refresh")! }
    /// Background taps that should do nothing (the helper just exits).
    static var noopURL: URL { URL(string: "\(urlScheme)://none")! }
    /// Opens the hints page for a question (the question travels in the URL, base64url JSON).
    static func hintsURL(_ q: QuestionPayload) -> URL {
        let data = (try? JSONEncoder().encode(q)) ?? Data()
        let b64 = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        return URL(string: "\(urlScheme)://hints?q=\(b64)")!
    }
}

/// Contribution levels keyed by "yyyy-MM-dd", values 0...4.
struct Heatmap: Codable {
    var levels: [String: Int]
    var total: Int
    var summary: String
    var solved: Int? = nil
}

struct DailyProblem: Codable {
    var title: String
    var difficulty: String
    var url: String
    var date: String
    var tags: [String]
}

/// A "build X from scratch" guide from codecrafters-io/build-your-own-x.
struct ProjectIdea: Codable, Hashable {
    var category: String
    var language: String
    var title: String
    var url: String
}

/// A recently created, popular GitHub repo in the day's domain.
struct FreshRepo: Codable, Hashable {
    var name: String
    var description: String
    var url: String
    var stars: Int
    var language: String
}

/// A generated question. subject is OS, CN, DBMS, Infra or SD (system design; topic is "Category: scenario").
struct CSQuestion: Codable, Hashable {
    var subject: String
    var topic: String
    var title: String
    var prompt: String
    var hints: [String]
    var fromResume: Bool? = nil

    var isResume: Bool { fromResume == true }
    /// Short label for pills: the SD category, or the subject.
    var category: String {
        subject == "SD" ? (topic.components(separatedBy: ":").first ?? "Design") : subject
    }
}

/// Everything the hints page / Notes needs, passed from the widget to the helper app.
struct QuestionPayload: Codable {
    var tag: String // e.g. "System Design · Kafka" or "OS · page faults"
    var title: String
    var prompt: String
    var hints: [String]
    var fromResume: Bool? = nil

    /// Note title in Notes › Daily Problems; resume questions are prefixed so they're easy to find.
    var noteTitle: String { fromResume == true ? "[RESUME] \(title)" : title }

    static func decode(base64url s: String) -> QuestionPayload? {
        var b64 = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        guard let data = Data(base64Encoded: b64) else { return nil }
        return try? JSONDecoder().decode(QuestionPayload.self, from: data)
    }
}

extension CSQuestion {
    var payload: QuestionPayload {
        let head = subject == "SD" ? "System Design · \(isResume ? "Design" : category)" : subject
        let tail = isResume ? "From your resume" : (subject == "SD" ? nil : topic)
        return QuestionPayload(tag: [head, tail].compactMap { $0 }.joined(separator: " · "), title: title, prompt: prompt,
                               hints: hints, fromResume: isResume)
    }
}

extension Snapshot {
    var systemDesign: CSQuestion? { cs?.first { $0.subject == "SD" } }
    var fundamentals: [CSQuestion] { (cs ?? []).filter { $0.subject != "SD" } }
}

struct Snapshot: Codable {
    var leetcode: Heatmap?
    var github: Heatmap?
    var daily: DailyProblem?
    var idea: ProjectIdea?
    var freshTopic: String?
    var fresh: [FreshRepo]?
    var cs: [CSQuestion]?
    var csDate: String? // day the CS questions were generated for
    var fetchedAt: Date = .distantPast
}

enum DayKey {
    static let local: DateFormatter = make(TimeZone.current)
    static let utc: DateFormatter = make(TimeZone(identifier: "UTC")!)

    private static func make(_ tz: TimeZone) -> DateFormatter {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = tz
        f.dateFormat = "yyyy-MM-dd"
        return f
    }
}

extension Heatmap {
    /// Consecutive active days ending today (or yesterday, if today has no activity yet).
    var currentStreak: Int {
        let cal = Calendar.current
        var day = cal.startOfDay(for: Date())
        if (levels[DayKey.local.string(from: day)] ?? 0) == 0 {
            day = cal.date(byAdding: .day, value: -1, to: day)!
        }
        var streak = 0
        while (levels[DayKey.local.string(from: day)] ?? 0) > 0 {
            streak += 1
            day = cal.date(byAdding: .day, value: -1, to: day)!
        }
        return streak
    }

    var activeToday: Bool { (levels[DayKey.local.string(from: Date())] ?? 0) > 0 }
}

/// Deterministic daily rotation through a list, shuffled once so neighbours differ.
enum DailyPick {
    static func dayNumber(_ date: Date = Date()) -> Int {
        let cal = Calendar.current
        let epoch = cal.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        return cal.dateComponents([.day], from: epoch, to: cal.startOfDay(for: date)).day ?? 0
    }

    static func index(count: Int, seed: UInt64, date: Date = Date()) -> Int? {
        guard count > 0 else { return nil }
        var order = Array(0..<count)
        var s = seed
        for i in stride(from: count - 1, to: 0, by: -1) {
            s = s &* 6364136223846793005 &+ 1442695040888963407
            order.swapAt(i, Int((s >> 33) % UInt64(i + 1)))
        }
        let d = dayNumber(date)
        return order[((d % count) + count) % count]
    }
}
