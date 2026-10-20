import Foundation

enum Net {
    static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 10
        c.timeoutIntervalForResource = 15
        c.httpAdditionalHeaders = ["User-Agent": "Mozilla/5.0 (Macintosh; Mac OS X 14_0) DevBoard/1.0 (+https://github.com)"]
        return URLSession(configuration: c)
    }()

    static func data(_ req: URLRequest) async throws -> Data {
        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }
}

enum LeetCode {
    private static func graphQL(_ query: String, variables: [String: Any] = [:]) async throws -> [String: Any] {
        var req = URLRequest(url: URL(string: "https://leetcode.com/graphql")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("https://leetcode.com", forHTTPHeaderField: "Referer")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["query": query, "variables": variables])
        let obj = try JSONSerialization.jsonObject(with: try await Net.data(req)) as? [String: Any]
        guard let data = obj?["data"] as? [String: Any] else { throw URLError(.cannotParseResponse) }
        return data
    }

    static func heatmap(user: String) async throws -> Heatmap {
        let q = """
        query($u: String!) { matchedUser(username: $u) {
          userCalendar { submissionCalendar }
          submitStatsGlobal { acSubmissionNum { difficulty count } }
        } }
        """
        let data = try await graphQL(q, variables: ["u": user])
        guard let mu = data["matchedUser"] as? [String: Any],
              let cal = mu["userCalendar"] as? [String: Any],
              let calStr = cal["submissionCalendar"] as? String,
              let raw = try JSONSerialization.jsonObject(with: Data(calStr.utf8)) as? [String: Int]
        else { throw URLError(.cannotParseResponse) }

        var levels: [String: Int] = [:]
        var total = 0
        for (ts, count) in raw {
            guard let t = Double(ts) else { continue }
            total += count
            let key = DayKey.utc.string(from: Date(timeIntervalSince1970: t))
            levels[key] = switch count { case 0: 0; case 1...2: 1; case 3...5: 2; case 6...9: 3; default: 4 }
        }

        var summary = "\(total) submissions"
        var solved: Int?
        if let stats = mu["submitStatsGlobal"] as? [String: Any],
           let ac = stats["acSubmissionNum"] as? [[String: Any]] {
            let by = Dictionary(ac.compactMap { d -> (String, Int)? in
                guard let k = d["difficulty"] as? String, let v = d["count"] as? Int else { return nil }
                return (k, v)
            }, uniquingKeysWith: { a, _ in a })
            solved = by["All"]
            summary = "\(by["All"] ?? 0) solved · E\(by["Easy"] ?? 0) M\(by["Medium"] ?? 0) H\(by["Hard"] ?? 0)"
        }
        return Heatmap(levels: levels, total: total, summary: summary, solved: solved)
    }

    static func daily() async throws -> DailyProblem {
        let q = "query { activeDailyCodingChallengeQuestion { date link question { title difficulty topicTags { name } } } }"
        let data = try await graphQL(q)
        guard let d = data["activeDailyCodingChallengeQuestion"] as? [String: Any],
              let link = d["link"] as? String,
              let question = d["question"] as? [String: Any],
              let title = question["title"] as? String
        else { throw URLError(.cannotParseResponse) }
        let tags = (question["topicTags"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
        return DailyProblem(title: title,
                            difficulty: question["difficulty"] as? String ?? "",
                            url: "https://leetcode.com" + link,
                            date: d["date"] as? String ?? "",
                            tags: Array(tags.prefix(2)))
    }
}

enum GitHub {
    private static let cell = try! NSRegularExpression(pattern: #"data-date="(\d{4}-\d{2}-\d{2})"[^>]*?data-level="([0-4])""#)
    private static let totalRx = try! NSRegularExpression(pattern: #"([\d,]+)\s+contributions?\s+in the last year"#)

    /// Parses the public contributions calendar, so no token is needed.
    static func heatmap(user: String) async throws -> Heatmap {
        let req = URLRequest(url: URL(string: "https://github.com/users/\(user)/contributions")!)
        let html = String(decoding: try await Net.data(req), as: UTF8.self)
        let ns = html as NSString
        var levels: [String: Int] = [:]
        for m in cell.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            levels[ns.substring(with: m.range(at: 1))] = Int(ns.substring(with: m.range(at: 2)))
        }
        guard !levels.isEmpty else { throw URLError(.cannotParseResponse) }
        var total = 0
        if let m = totalRx.firstMatch(in: html, range: NSRange(location: 0, length: ns.length)) {
            total = Int(ns.substring(with: m.range(at: 1)).replacingOccurrences(of: ",", with: "")) ?? 0
        }
        return Heatmap(levels: levels, total: total, summary: "\(total) contributions this year")
    }
}

enum BuildIdeas {
    static let languages: Set<String> = ["C", "C++", "Java", "Python"]
    /// Backend / systems categories from build-your-own-x (skip graphics, games, front-end, etc.).
    static let categories: Set<String> = [
        "Distributed Systems", "BitTorrent Client", "Blockchain / Cryptocurrency", "Command-Line Tool", "Database",
        "Docker", "Emulator / Virtual Machine", "Git", "Memory Allocator", "Network Stack", "Operating System",
        "Processor", "Programming Language", "Regex Engine", "Search Engine", "Shell", "Text Editor",
        "Web Browser", "Web Server",
    ]
    private static let source = URL(string: "https://raw.githubusercontent.com/codecrafters-io/build-your-own-x/master/README.md")!
    private static let entryRx = try! NSRegularExpression(pattern: #"^\* \[\*\*([^*]+)\*\*: _(.+?)_\]\((https?://[^)\s]+)\)"#)

    private static var cacheURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("build-ideas.json")
    }

    /// The list changes rarely, so it's fetched at most once a day.
    static func all() async throws -> [ProjectIdea] {
        if let attrs = try? FileManager.default.attributesOfItem(atPath: cacheURL.path),
           let modified = attrs[.modificationDate] as? Date, Date().timeIntervalSince(modified) < 86_400,
           let data = try? Data(contentsOf: cacheURL),
           let cached = try? JSONDecoder().decode([ProjectIdea].self, from: data), !cached.isEmpty {
            return cached
        }
        let text = String(decoding: try await Net.data(URLRequest(url: source)), as: UTF8.self)
        var ideas: [ProjectIdea] = []
        var category = ""
        for line in text.components(separatedBy: "\n") {
            if line.hasPrefix("#### Build your own `") {
                category = line.replacingOccurrences(of: "#### Build your own `", with: "").replacingOccurrences(of: "`", with: "")
                continue
            }
            guard categories.contains(category) else { continue }
            let ns = line as NSString
            guard let m = entryRx.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { continue }
            let langs = ns.substring(with: m.range(at: 1)).components(separatedBy: "/").map { $0.trimmingCharacters(in: .whitespaces) }
            guard let lang = langs.first(where: languages.contains) else { continue }
            ideas.append(ProjectIdea(category: category, language: lang,
                                     title: ns.substring(with: m.range(at: 2)), url: ns.substring(with: m.range(at: 3))))
        }
        guard !ideas.isEmpty else { throw URLError(.cannotParseResponse) }
        try? JSONEncoder().encode(ideas).write(to: cacheURL, options: .atomic)
        return ideas
    }

    static func today() async throws -> ProjectIdea {
        let ideas = try await all()
        return ideas[DailyPick.index(count: ideas.count, seed: 0xB111D)!]
    }
}

enum FreshRepos {
    static let topics: [(topic: String, label: String)] = [
        ("payments", "Payments"), ("cybersecurity", "Cybersecurity"), ("banking", "Banking"),
        ("operating-system", "Operating Systems"), ("fintech", "Fintech"), ("cryptography", "Cryptography"),
        ("database", "Databases"), ("networking", "Networking"), ("distributed-systems", "Distributed Systems"),
    ]

    static var todaysTopic: (topic: String, label: String) {
        topics[((DailyPick.dayNumber() % topics.count) + topics.count) % topics.count]
    }

    /// Popular repos created in the last ~6 months for today's topic, in C, C++, Java or Python.
    static func fetch(limit: Int = 3) async throws -> [FreshRepo] {
        let since = Calendar.current.date(byAdding: .day, value: -180, to: Date())!
        let q = "topic:\(todaysTopic.topic) created:>\(DayKey.local.string(from: since)) stars:>5 "
            + "language:Java language:Python language:C language:C++"
        var comps = URLComponents(string: "https://api.github.com/search/repositories")!
        comps.queryItems = [.init(name: "q", value: q), .init(name: "sort", value: "stars"), .init(name: "per_page", value: "15")]
        var req = URLRequest(url: comps.url!)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let obj = try JSONSerialization.jsonObject(with: try await Net.data(req)) as? [String: Any],
              let items = obj["items"] as? [[String: Any]] else { throw URLError(.cannotParseResponse) }

        return Array(items.compactMap { r -> FreshRepo? in
            guard let name = r["full_name"] as? String, let url = r["html_url"] as? String,
                  let desc = (r["description"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  desc.count >= 20, isMostlyLatin(desc) else { return nil }
            return FreshRepo(name: name, description: desc, url: url,
                             stars: r["stargazers_count"] as? Int ?? 0, language: r["language"] as? String ?? "")
        }.prefix(limit))
    }

    private static func isMostlyLatin(_ s: String) -> Bool {
        let letters = s.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        guard !letters.isEmpty else { return false }
        return Double(letters.filter { $0.isASCII }.count) / Double(letters.count) > 0.8
    }
}

enum SnapshotStore {
    /// Identifies today's generated question set; the version suffix forces regeneration after format changes.
    static func csKey(_ date: Date = Date()) -> String { DayKey.local.string(from: date) + "/gemini-v3" }

    private static var url: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("devboard-snapshot.json")
    }

    static func load() -> Snapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .secondsSince1970
        return try? dec.decode(Snapshot.self, from: data)
    }

    static func save(_ s: Snapshot) {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .secondsSince1970
        try? enc.encode(s).write(to: url, options: .atomic)
    }

    /// Fetches everything in parallel; any source that fails falls back to the last cached value.
    static func refresh() async -> Snapshot {
        let cached = load() ?? Snapshot()
        async let lc = Config.leetCodeUser == nil ? nil : try? LeetCode.heatmap(user: Config.leetCodeUser!)
        async let gh = Config.gitHubUser == nil ? nil : try? GitHub.heatmap(user: Config.gitHubUser!)
        async let daily = try? LeetCode.daily()
        async let idea = try? BuildIdeas.today()
        async let fresh = try? FreshRepos.fetch()
        let today = csKey()
        let needCS = cached.csDate != today || (cached.cs ?? []).isEmpty
        async let cs: [CSQuestion]? = needCS ? generateCS() : cached.cs

        let (lcR, ghR, dailyR, ideaR, freshR, csR) = await (lc, gh, daily, idea, fresh, cs)
        let topic = FreshRepos.todaysTopic.label
        var s = Snapshot()
        // An unset username clears its section instead of showing someone else's cached data.
        s.leetcode = Config.leetCodeUser == nil ? nil : lcR ?? cached.leetcode
        s.github = Config.gitHubUser == nil ? nil : ghR ?? cached.github
        s.daily = dailyR ?? cached.daily
        s.idea = ideaR ?? cached.idea
        if let freshR, !freshR.isEmpty {
            s.fresh = freshR
            s.freshTopic = topic
        } else {
            s.fresh = cached.fresh
            s.freshTopic = cached.freshTopic
        }
        if let csR, !csR.isEmpty {
            s.cs = csR
            s.csDate = needCS ? today : cached.csDate
        } else {
            // Generation failed: keep the last Gemini-generated set rather than showing nothing.
            let usable = cached.csDate?.contains("/gemini") == true // any earlier Gemini set beats nothing
            s.cs = usable ? cached.cs : nil
            s.csDate = usable ? cached.csDate : nil
        }
        let gotAnything = lcR != nil || ghR != nil || dailyR != nil || ideaR != nil || freshR != nil
        s.fetchedAt = gotAnything ? Date() : cached.fetchedAt
        save(s)
        return s
    }
}

private func generateCS() async -> [CSQuestion]? {
    do {
        let qs = try await CSGenerator.generate()
        CSGenerator.log.info("generated \(qs.count) CS questions")
        return qs
    } catch {
        CSGenerator.log.error("CS generation failed: \(String(describing: error), privacy: .public)")
        return nil
    }
}

/// All widgets reload together (hourly / refresh button); share one network fetch between them.
actor Refresher {
    static let shared = Refresher()
    private var inFlight: Task<Snapshot, Never>?

    func snapshot(maxAge: TimeInterval = 90) async -> Snapshot {
        if let cached = SnapshotStore.load(), Date().timeIntervalSince(cached.fetchedAt) < maxAge { return cached }
        if let task = inFlight { return await task.value }
        let task = Task { await SnapshotStore.refresh() }
        inFlight = task
        let result = await task.value
        inFlight = nil
        return result
    }
}
