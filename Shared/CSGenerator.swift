import Foundation
import os

/// Generates the daily OS / CN / DBMS / Infra / system design questions with an LLM (one request a day):
/// Google Gemini (free tier, the default), Anthropic Claude, or any OpenAI-compatible API, picked by `ai_provider` in config.json.
/// Only the subtopic is chosen here, so questions don't repeat; the question and hints are written fresh by the model.
/// The API key is read from `api_key` in the widget bundle, which build.sh copies from ~/.config/devboard/.
/// The optional resume profile (`profile.txt`) is copied the same way.
enum CSGenerator {
    static let log = Logger(subsystem: "dev.devboard", category: "questions")

    /// Gemini models, tried in order. Thinking is kept low/off so a reload finishes well inside WidgetKit's watchdog limit.
    static let geminiModels: [(name: String, thinking: [String: Any])] = [
        ("gemini-3.8-flash", ["thinkingLevel": "low"]),    // gemini-2.5-flash is closed to new API keys
        ("gemini-3.5-flash", ["thinkingLevel": "low"]),    // fallback; often overloaded on the free tier
        ("gemini-flash-latest", [:]),
    ]

    static let topics: [(subject: String, list: [String])] = [
        ("OS", [
            "process vs thread", "context switching", "virtual memory and paging", "TLB and TLB misses", "page faults",
            "page replacement (LRU, Clock)", "thrashing", "deadlock conditions and prevention", "mutex vs semaphore",
            "spinlocks", "priority inversion", "CPU scheduling and Linux CFS", "fork and copy-on-write", "zombie processes",
            "system calls and kernel mode", "interrupts vs polling", "malloc and memory fragmentation", "condition variables",
            "producer-consumer", "readers-writers", "inodes and file systems", "journaling file systems", "page cache and fsync",
            "mmap", "IPC: pipes, shared memory, sockets", "signals", "memory barriers and atomics", "false sharing", "NUMA",
            "namespaces and cgroups", "OOM killer", "epoll vs select", "swap", "boot process", "kernel architectures",
        ]),
        ("CN", [
            "TCP three-way handshake", "TCP teardown and TIME_WAIT", "TCP vs UDP", "flow control vs congestion control",
            "congestion control (CUBIC, BBR)", "Nagle and delayed ACK", "DNS resolution", "HTTP/1.1 vs HTTP/2 vs HTTP/3",
            "TLS 1.3 handshake", "certificate validation", "subnetting and CIDR", "longest prefix match routing", "NAT",
            "ARP and ARP spoofing", "DHCP", "OSPF vs BGP", "BGP hijacking", "VLANs", "MTU and path MTU discovery",
            "traceroute and ICMP", "socket accept queue and backlog", "L4 vs L7 load balancing", "CDNs and anycast",
            "WebSockets vs SSE", "gRPC vs REST", "keep-alive and connection pooling", "CORS", "stateful firewalls",
            "QUIC", "IPv6", "bandwidth-delay product", "DDoS mitigation", "man-in-the-middle and TLS",
        ]),
        ("DBMS", [
            "ACID", "isolation levels and anomalies", "MVCC", "two-phase locking", "normalization (3NF, BCNF)",
            "denormalization", "B+ tree indexes", "hash vs B+ tree indexes", "clustered vs secondary indexes",
            "composite indexes and leftmost prefix", "covering indexes", "query planning and statistics", "join algorithms",
            "write-ahead logging", "ARIES recovery", "window functions", "Nth highest salary SQL", "materialized views",
            "replication (sync vs async)", "sharding strategies", "CAP and PACELC", "LSM trees vs B-trees", "partitioning",
            "optimistic vs pessimistic concurrency", "phantom reads and gap locks", "deadlocks in databases",
            "connection pooling", "two-phase commit", "consistent hashing", "OLTP vs OLAP and columnar storage",
            "vacuum and compaction", "write skew", "foreign keys and cascades",
        ]),
        ("Infra", [
            "Kubernetes pod scheduling", "liveness vs readiness vs startup probes", "HPA autoscaling", "CPU limits and throttling",
            "memory limits and OOMKilled pods", "Docker image layers and build cache", "container networking and CNI",
            "Kubernetes Services and kube-proxy", "Ingress and load balancers", "ConfigMaps and Secrets", "rolling vs blue-green vs canary",
            "Jenkins CI/CD pipelines", "GitOps with Argo CD", "Prometheus metrics and cardinality", "SLOs and burn-rate alerting",
            "distributed tracing", "log aggregation", "Linux load average", "file descriptor limits", "CoreDNS and ndots",
            "service mesh sidecars", "AWS VPC and subnets", "IAM roles for pods (IRSA)", "S3 consistency and performance",
            "node autoscaling (Karpenter)", "etcd", "StatefulSets", "PodDisruptionBudgets", "graceful shutdown and preStop",
            "TLS certificate rotation", "backups and disaster recovery", "Terraform state",
        ]),
        ("SD", [
            "Concurrency: lost updates on a hot counter", "Concurrency: double charge on client retry", "Concurrency: deadlocks between transfers",
            "Concurrency: thread pool exhaustion from a slow dependency", "Concurrency: distributed lock expiry during GC pause",
            "Concurrency: out-of-order event processing", "JVM: OOMKilled pod with healthy heap", "JVM: slow memory leak over days",
            "JVM: p99 spikes from GC pauses", "JVM: virtual thread pinning", "Redis: cache stampede", "Redis: hot key on one shard",
            "Redis: cache and DB inconsistency", "Redis: distributed rate limiter", "Kafka: consumer lag with constant rebalances",
            "Kafka: duplicate processing after restart", "Kafka: poison pill message", "Kafka: ordering per key",
            "Kafka: transactional outbox for dual writes", "Kafka: delayed retries without blocking a partition",
            "RabbitMQ: request-reply at scale", "RabbitMQ: DLQ and redelivery storms", "Spring Boot: @Transactional pitfalls",
            "Spring Boot: N+1 queries", "Spring Boot: connection pool exhaustion", "Spring Boot: graceful shutdown on deploys",
            "Databases: migrating a huge table without downtime", "Databases: keyset pagination", "Databases: read replica lag",
            "Databases: write skew", "Cassandra: lightweight transactions and contention", "Distributed systems: idempotent payment API",
            "Distributed systems: saga with compensation", "Distributed systems: cascading failure", "Distributed systems: retry amplification",
            "Distributed systems: reliable webhooks", "Distributed systems: delayed job scheduler", "Distributed systems: leaderboard at scale",
            "Distributed systems: notification fan-out to millions", "Incidents: payment success rate drops at 2am",
        ]),
    ]

    /// Every day one slot (rotating OS → CN → DBMS → Infra → SD) is spun from the resume profile.
    static func resumeSlot(_ date: Date = Date()) -> Int? {
        let day = DailyPick.dayNumber(date)
        return ((day % topics.count) + topics.count) % topics.count
    }

    static var profile: String? {
        guard let url = Bundle.main.url(forResource: "profile", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return nil }
        return text
    }

    static func todaysTopics(_ date: Date = Date()) -> [(subject: String, topic: String)] {
        topics.enumerated().map { n, t in
            (t.subject, t.list[DailyPick.index(count: t.list.count, seed: 0x7091C + UInt64(n), date: date)!])
        }
    }

    enum GenError: Error { case noKey, http(Int, String), unparseable(String) }

    static var apiKey: String? {
        guard let url = Bundle.main.url(forResource: "api_key", withExtension: nil)
                ?? Bundle.main.url(forResource: "gemini_key", withExtension: nil), // builds from before api_key
              let key = try? String(contentsOf: url, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
              !key.isEmpty else { return nil }
        return key
    }

    // Per-attempt cap; a slow model falls through to the next, faster one.
    private static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 60 // gemini-3.8-flash often needs 15-50s on the free tier
        c.timeoutIntervalForResource = 60
        return URLSession(configuration: c)
    }()

    private static let instructions = """
    You are a senior backend engineer who interviews candidates at top tech companies. You write interview \
    questions on operating systems, computer networks, databases, infrastructure (Kubernetes, Linux, cloud, CI/CD, \
    observability) and production system design for backend engineers.
    Rules for every question:
    - title: a specific question ending with a question mark, under 80 characters. Never a bare topic name.
    - prompt: a short realistic scenario or what a strong answer must cover, at most two sentences.
    - hints: exactly four. Each is a concrete nudge about the real mechanism, progressing from a gentle pointer \
    to nearly the key insight, without stating the full answer. No numbering, no generic advice like "define the term".
    - Be technically precise and correct; prefer questions that test understanding over memorised definitions.
    - System design questions describe a production scenario (an incident, a scaling limit or a race) and ask \
    how to diagnose and fix it.
    - When asked to base a question on the candidate's profile, speak like an interviewer probing their own work, \
    e.g. "In your order service you used ... what happens when ...?". Pick one specific project and dig into \
    a real failure mode or design trade-off in it.
    """

    static func generate(_ date: Date = Date()) async throws -> [CSQuestion] {
        guard let key = apiKey else { throw GenError.noKey }
        let picks = todaysTopics(date)
        let slot = (profile == nil || !Config.resumeQuestions) ? nil : resumeSlot(date)
        var prompt = "Write one question for each line below, in this order:\n"
            + picks.enumerated().map { i, p in
                i == slot
                    ? "- subject \(p.subject): base it on the candidate profile below (stay within \(subjectName(p.subject)))"
                    : "- subject \(p.subject), topic: \(p.topic)"
            }.joined(separator: "\n")
        if let slot, let profile {
            prompt += "\n\nCandidate profile (use only for the \(picks[slot].subject) question):\n\(profile)"
        }

        // Each attempt is (label, request). Only Gemini has a fallback chain; the others use one model.
        let attempts: [(String, () async throws -> String)]
        switch Config.aiProvider {
        case "claude", "anthropic":
            let model = Config.aiModel ?? "claude-opus-5-5"
            attempts = [(model, { try await callClaude(model: model, key: key, prompt: prompt) })]
        case "openai":
            guard let model = Config.aiModel else { throw GenError.unparseable("set ai_model in config.json for ai_provider openai") }
            attempts = [(model, { try await callOpenAI(model: model, key: key, prompt: prompt) })]
        default:
            let models = Config.aiModel.map { [($0, [String: Any]())] } ?? geminiModels
            attempts = models.map { m in (m.name, { try await callGemini(model: m.name, thinking: m.thinking, key: key, prompt: prompt) }) }
        }

        var lastError: Error = GenError.unparseable("no model tried")
        for (name, attempt) in attempts {
            do {
                let text = try await attempt()
                let qs = try parse(text, picks: picks, resumeSlot: slot)
                log.info("generated \(qs.count) questions with \(name, privacy: .public)")
                return qs
            } catch GenError.http(let code, let body) where code == 400 && !body.contains("not found") {
                throw GenError.http(code, body) // a bad request won't succeed on another model
            } catch {
                // Overloaded (503), over quota (429), unavailable (404), timed out or unparseable: try the next model.
                log.info("model \(name, privacy: .public) failed: \(String(describing: error).prefix(160), privacy: .public)")
                lastError = error
            }
        }
        throw lastError
    }

    /// The questions as a JSON array, in the shape `parse` expects.
    private static let questionsSchema: [String: Any] = [
        "type": "array",
        "items": [
            "type": "object",
            "properties": [
                "subject": ["type": "string"],
                "title": ["type": "string"],
                "prompt": ["type": "string"],
                "hints": ["type": "array", "items": ["type": "string"]],
            ],
            "required": ["subject", "title", "prompt", "hints"],
            "additionalProperties": false,
        ],
    ]

    private static func post(_ url: String, headers: [String: String], body: [String: Any]) async throws -> [String: Any] {
        guard let u = URL(string: url) else { throw GenError.unparseable("bad URL \(url)") }
        var req = URLRequest(url: u)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        headers.forEach { req.setValue($1, forHTTPHeaderField: $0) }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await session.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw GenError.http(status, String(decoding: data.prefix(300), as: UTF8.self)) }
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GenError.unparseable(String(decoding: data.prefix(300), as: UTF8.self))
        }
        return obj
    }

    /// Anthropic Messages API, with structured output so the reply is always the questions JSON.
    private static func callClaude(model: String, key: String, prompt: String) async throws -> String {
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 16000,
            "system": instructions,
            "messages": [["role": "user", "content": prompt]],
            // Low effort keeps the reply fast; structured output needs an object at the top level.
            "output_config": [
                "effort": "low",
                "format": ["type": "json_schema", "schema": [
                    "type": "object",
                    "properties": ["questions": questionsSchema],
                    "required": ["questions"],
                    "additionalProperties": false,
                ]],
            ],
            // If a safety classifier declines, re-run on Anthropic's recommended fallback model instead of failing.
            "fallbacks": "default",
        ]
        let obj = try await post("https://api.anthropic.com/v1/messages", headers: [
            "x-api-key": key,
            "anthropic-version": "2023-06-01",
            "anthropic-beta": "server-side-fallback-2026-07-01",
        ], body: body)
        guard obj["stop_reason"] as? String != "refusal", let content = obj["content"] as? [[String: Any]] else {
            throw GenError.unparseable("Claude declined or returned no content")
        }
        return content.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined()
    }

    /// Any OpenAI-compatible Chat Completions endpoint (OpenAI, OpenRouter, Groq, Together, Ollama, LM Studio…).
    private static func callOpenAI(model: String, key: String, prompt: String) async throws -> String {
        let base = Config.aiBaseURL.hasSuffix("/") ? String(Config.aiBaseURL.dropLast()) : Config.aiBaseURL
        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": instructions],
                ["role": "user", "content": prompt + "\n\nReply with only a JSON object: {\"questions\": [{\"subject\", \"title\", \"prompt\", \"hints\": [...]}, ...]}"],
            ],
            // json_object is the most widely supported JSON mode across compatible servers.
            "response_format": ["type": "json_object"],
        ]
        let obj = try await post(base + "/chat/completions", headers: ["Authorization": "Bearer \(key)"], body: body)
        guard let choices = obj["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let text = message["content"] as? String else {
            throw GenError.unparseable(String(describing: obj).prefix(300).description)
        }
        return text
    }

    private static func callGemini(model: String, thinking: [String: Any], key: String, prompt: String) async throws -> String {
        let schema: [String: Any] = [
            "type": "ARRAY",
            "items": [
                "type": "OBJECT",
                "properties": [
                    "subject": ["type": "STRING"],
                    "title": ["type": "STRING"],
                    "prompt": ["type": "STRING"],
                    "hints": ["type": "ARRAY", "items": ["type": "STRING"]],
                ],
                "required": ["subject", "title", "prompt", "hints"],
            ],
        ]
        let body: [String: Any] = [
            "systemInstruction": ["parts": [["text": instructions]]],
            "contents": [["role": "user", "parts": [["text": prompt]]]],
            "generationConfig": ["temperature": 0.8, "responseMimeType": "application/json", "responseSchema": schema]
                .merging(thinking.isEmpty ? [:] : ["thinkingConfig": thinking]) { a, _ in a },
        ]
        let obj = try await post("https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent",
                                 headers: ["x-goog-api-key": key], body: body)
        guard let candidates = obj["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]] else {
            throw GenError.unparseable(String(describing: obj).prefix(300).description)
        }
        // Skip any "thought" parts from thinking models.
        return parts.filter { ($0["thought"] as? Bool) != true }.compactMap { $0["text"] as? String }.joined()
    }

    private struct Raw: Decodable {
        let subject: String
        let title: String
        let prompt: String
        let hints: [String]
    }

    static func subjectName(_ s: String) -> String {
        switch s {
        case "OS": "Operating Systems"
        case "CN": "Computer Networks"
        case "DBMS": "Database Management Systems"
        case "Infra": "Infrastructure (Kubernetes, Linux, cloud, CI/CD, observability)"
        default: "System Design"
        }
    }

    static func parse(_ text: String, picks: [(subject: String, topic: String)], resumeSlot: Int?) throws -> [CSQuestion] {
        guard let start = text.firstIndex(of: "["), let end = text.lastIndex(of: "]") else {
            throw GenError.unparseable(String(text.prefix(300)))
        }
        let raws = try JSONDecoder().decode([Raw].self, from: Data(text[start...end].utf8))
        let qs: [CSQuestion] = zip(picks, raws).enumerated().compactMap { i, pair in
            let (pick, raw) = pair
            let hints = raw.hints.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            let title = raw.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, !hints.isEmpty else { return nil }
            let fromResume = i == resumeSlot
            let topic = fromResume ? "your experience" : pick.topic
            return CSQuestion(subject: pick.subject, topic: topic, title: title,
                              prompt: raw.prompt.trimmingCharacters(in: .whitespacesAndNewlines), hints: Array(hints.prefix(5)),
                              fromResume: fromResume)
        }
        guard qs.count == picks.count else { throw GenError.unparseable(String(text.prefix(300))) }
        return qs
    }
}
