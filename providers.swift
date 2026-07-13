import ServiceManagement
import SwiftUI

// MARK: - Types

enum Provider: String, CaseIterable, Identifiable {
    case claude, gpt, gemini
    var id: String { rawValue }

    var name: String {
        switch self {
        case .claude: "Claude"
        case .gpt: "Codex"
        case .gemini: "Gemini"
        }
    }

    var glyph: String {
        switch self {
        case .claude: "✳"
        case .gpt: "⬡"
        case .gemini: "✦"
        }
    }

    var tint: Color {
        switch self {
        case .claude: Color(red: 0.85, green: 0.47, blue: 0.34) // terracotta
        case .gpt: Color(red: 0.10, green: 0.66, blue: 0.52) // openai teal
        case .gemini: Color(red: 0.35, green: 0.55, blue: 1.00) // gemini blue
        }
    }

    var loginCommand: String {
        switch self {
        case .claude: "claude /login"
        case .gpt: "codex login"
        case .gemini: "npx -y @google/gemini-cli"
        }
    }
}

struct UsageItem: Identifiable {
    let id: String
    let label: String
    let short: String
    let percent: Double
    let severity: String
    let resetsAt: Date?
}

struct ProviderState {
    var items: [UsageItem] = []
    var connected = false
    var note: String?
    var retryAt: Date?
    var updatedAt: Date?
    var resetCredits = 0
}

// MARK: - Helpers

func parseISO(_ s: String?) -> Date? {
    guard let s else { return nil }
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let d = f.date(from: s) { return d }
    f.formatOptions = [.withInternetDateTime]
    let stripped = s.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
    return f.date(from: stripped)
}

func resetText(_ d: Date?) -> String {
    guard let d else { return "" }
    let s = Int(d.timeIntervalSinceNow)
    if s <= 0 { return "resetting…" }
    if s < 600 { return "resets \(s / 60)m \(s % 60)s" }
    let h = s / 3600, m = (s % 3600) / 60
    if h >= 24 { return "resets \(h / 24)d \(h % 24)h" }
    if h > 0 { return "resets \(h)h \(m)m" }
    return "resets \(m)m"
}

func agoText(_ d: Date?) -> String {
    guard let d else { return "syncing…" }
    let s = Int(-d.timeIntervalSinceNow)
    if s < 10 { return "synced just now" }
    if s < 60 { return "synced \(s)s ago" }
    if s < 600 { return "synced \(s / 60)m \(s % 60)s ago" }
    if s < 3600 { return "synced \(s / 60)m ago" }
    if s < 86400 { return "synced \(s / 3600)h \((s % 3600) / 60)m ago" }
    return "synced \(s / 86400)d ago"
}

func retryText(_ d: Date?) -> String {
    guard let d else { return "" }
    let s = Int(d.timeIntervalSinceNow)
    if s <= 0 { return " · retrying…" }
    return " · retry in \(s)s"
}

func tokenText(_ n: Double) -> String {
    if n >= 1_000_000 { return String(format: "%.1fM", n / 1_000_000) }
    if n >= 1_000 { return String(format: "%.0fk", n / 1_000) }
    return "\(Int(n))"
}

private func home() -> URL { FileManager.default.homeDirectoryForCurrentUser }

private func httpGET(_ urlString: String, bearer: String) -> Data? {
    guard let url = URL(string: urlString) else { return nil }
    var req = URLRequest(url: url)
    req.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
    req.setValue("oauth-2021-10-01", forHTTPHeaderField: "anthropic-beta")
    req.timeoutInterval = 15
    let sem = DispatchSemaphore(value: 0)
    var out: Data?
    URLSession.shared.dataTask(with: req) { data, resp, _ in
        if (resp as? HTTPURLResponse)?.statusCode == 200 { out = data }
        sem.signal()
    }.resume()
    sem.wait()
    return out
}

// MARK: - Claude (Keychain token -> oauth usage API)

enum ClaudeFetcher {
    struct APIUsage: Decodable {
        struct Limit: Decodable {
            struct Scope: Decodable {
                struct Model: Decodable { let display_name: String? }
                let model: Model?
            }
            let kind: String
            let percent: Double?
            let severity: String?
            let resets_at: String?
            let scope: Scope?
        }
        struct Extra: Decodable {
            let is_enabled: Bool?
            let utilization: Double?
        }
        let limits: [Limit]?
        let extra_usage: Extra?
    }

    private static var cachedPlan: String?
    private static var cooldownUntil = Date.distantPast

    private static func planName(_ token: String) -> String? {
        if let cachedPlan { return cachedPlan }
        guard let data = httpGET("https://api.anthropic.com/api/oauth/profile", bearer: token),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let org = json["organization"] as? [String: Any]
        else { return nil }
        let tier = org["rate_limit_tier"] as? String ?? ""
        let plan: String?
        if tier.contains("max_20x") { plan = "Max 20×" }
        else if tier.contains("max_5x") { plan = "Max 5×" }
        else if tier.contains("pro") { plan = "Pro" }
        else if tier.contains("free") { plan = "Free" }
        else { plan = nil }
        cachedPlan = plan
        return plan
    }

    private enum TokenResult { case token(String), loggedOut, transient }

    // ponytail: shells out to `security` instead of Security.framework — same result, less code
    private static func readToken() -> TokenResult {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        p.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return .transient }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        // 44 = errSecItemNotFound — genuinely logged out. Anything else is transient
        // (keychain locked, denied dialog, race) and must not wipe last-good data.
        if p.terminationStatus == 44 { return .loggedOut }
        guard p.terminationStatus == 0,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String
        else { return .transient }
        return .token(token)
    }

    static func fetch() -> ProviderState {
        var st = ProviderState()
        let token: String
        switch readToken() {
        case .loggedOut:
            st.note = "Login via Claude Code"
            return st
        case .transient:
            st.connected = true
            st.note = "Keychain busy — will retry"
            return st
        case .token(let t):
            token = t
        }
        st.connected = true
        guard Date() >= cooldownUntil else {
            st.note = "Rate limited"
            st.retryAt = cooldownUntil
            return st
        }

        var req = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2021-10-01", forHTTPHeaderField: "anthropic-beta")
        req.timeoutInterval = 15

        let sem = DispatchSemaphore(value: 0)
        var fetched: Data?
        var failure = "Request timed out"
        var backoff: TimeInterval = 0
        URLSession.shared.dataTask(with: req) { data, resp, error in
            defer { sem.signal() }
            if let error { failure = error.localizedDescription; return }
            let http = resp as? HTTPURLResponse
            guard http?.statusCode == 200 else {
                switch http?.statusCode ?? 0 {
                case 401:
                    failure = "Token expired — open Claude Code to refresh it"
                case 429:
                    // Respect the API's Retry-After hint; default to a short 90s otherwise.
                    let hinted = Double(http?.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 90
                    backoff = min(max(hinted, 60), 600)
                    failure = "Rate limited"
                case let code:
                    failure = "HTTP \(code)"
                }
                return
            }
            fetched = data
        }.resume()
        sem.wait()

        if backoff > 0 {
            cooldownUntil = Date().addingTimeInterval(backoff)
            st.retryAt = cooldownUntil
        }
        guard let data = fetched else {
            NSLog("AIsland claude: no data — %@", failure)
            st.note = failure
            return st
        }
        guard let usage = try? JSONDecoder().decode(APIUsage.self, from: data),
              let limits = usage.limits, !limits.isEmpty
        else {
            // The API rate-limits with a 200 + error body sometimes; back off either way.
            NSLog("AIsland claude: empty/undecodable body: %@",
                  String(decoding: data.prefix(160), as: UTF8.self))
            cooldownUntil = Date().addingTimeInterval(90)
            st.note = "API busy"
            st.retryAt = cooldownUntil
            return st
        }
        st.items = limits.map { l in
            let scopeName = l.scope?.model?.display_name
            let label: String
            switch l.kind {
            case "session": label = "Session (5h)"
            case "weekly_all": label = "Weekly · all models"
            case "weekly_scoped": label = "Weekly · \(scopeName ?? "scoped")"
            default: label = l.kind
            }
            return UsageItem(
                id: l.kind + (scopeName ?? ""),
                label: label,
                short: l.kind == "session" ? "5h" : "7d",
                percent: l.percent ?? 0,
                severity: l.severity ?? "normal",
                resetsAt: parseISO(l.resets_at)
            )
        }
        if usage.extra_usage?.is_enabled == true, let used = usage.extra_usage?.utilization {
            st.items.append(UsageItem(
                id: "extra", label: "Extra usage credits", short: "extra",
                percent: used, severity: "normal", resetsAt: nil
            ))
        }
        if let plan = planName(token) { st.note = "\(plan) plan" }
        st.updatedAt = Date()
        return st
    }
}

// MARK: - GPT / Codex (live wham API, session-log fallback)

enum CodexFetcher {
    private static func chatGPTAuth() -> (token: String, account: String)? {
        let url = home().appendingPathComponent(".codex/auth.json")
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tokens = json["tokens"] as? [String: Any],
              let token = tokens["access_token"] as? String,
              let account = tokens["account_id"] as? String
        else { return nil }
        return (token, account)
    }

    private static func whamRequest(_ path: String, method: String = "GET", body: [String: Any]? = nil) -> Data? {
        guard let auth = chatGPTAuth(),
              let url = URL(string: "https://chatgpt.com/backend-api\(path)") else { return nil }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("Bearer \(auth.token)", forHTTPHeaderField: "Authorization")
        req.setValue(auth.account, forHTTPHeaderField: "ChatGPT-Account-Id")
        req.setValue("codex-cli", forHTTPHeaderField: "User-Agent")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        req.timeoutInterval = 15
        let sem = DispatchSemaphore(value: 0)
        var out: Data?
        URLSession.shared.dataTask(with: req) { data, resp, _ in
            if (200...299).contains((resp as? HTTPURLResponse)?.statusCode ?? 0) { out = data }
            sem.signal()
        }.resume()
        sem.wait()
        return out
    }

    // Same endpoint Codex CLI itself uses — live percentages plus reset credits.
    private static func liveFetch() -> ProviderState? {
        guard let data = whamRequest("/wham/usage"),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rl = json["rate_limit"] as? [String: Any]
        else { return nil }
        var st = ProviderState()
        st.connected = true
        let exceeded = rl["limit_reached"] as? Bool == true
        for (key, name) in [("primary_window", "primary"), ("secondary_window", "secondary")] {
            guard let w = rl[key] as? [String: Any],
                  let used = w["used_percent"] as? Double else { continue }
            let minutes = (w["limit_window_seconds"] as? Double ?? 0) / 60
            let resets = (w["reset_at"] as? Double).map { Date(timeIntervalSince1970: $0) }
            st.items.append(UsageItem(
                id: "codex-\(name)",
                label: windowLabel(minutes),
                short: shortLabel(minutes),
                percent: used,
                severity: exceeded ? "exceeded" : "normal",
                resetsAt: resets
            ))
        }
        guard !st.items.isEmpty else { return nil }
        if let credits = json["rate_limit_reset_credits"] as? [String: Any],
           let n = credits["available_count"] as? Int {
            st.resetCredits = n
        }
        var bits: [String] = []
        if let plan = json["plan_type"] as? String { bits.append("\(plan) plan · live") }
        if st.resetCredits > 0 { bits.append("\(st.resetCredits) reset credits") }
        st.note = bits.isEmpty ? nil : bits.joined(separator: " · ")
        st.updatedAt = Date()
        return st
    }

    static func consumeResetCredit() -> Bool {
        whamRequest(
            "/wham/rate-limit-reset-credits/consume",
            method: "POST",
            body: ["redeem_request_id": UUID().uuidString]
        ) != nil
    }

    static func fetch() -> ProviderState {
        var st = ProviderState()
        let fm = FileManager.default
        st.connected = fm.fileExists(atPath: home().appendingPathComponent(".codex/auth.json").path)
        guard st.connected else {
            st.note = "Login via browser"
            return st
        }
        if let live = liveFetch() { return live }
        // Token expired or offline — fall back to the newest session log.
        guard let file = newestSession() else {
            st.note = "No Codex sessions yet — run codex once"
            return st
        }
        var found: (payload: [String: Any], rl: [String: Any])?
        for line in rateLimitCandidates(file) {
            guard let data = line.data(using: .utf8),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let payload = root["payload"] as? [String: Any],
                  let rl = payload["rate_limits"] as? [String: Any]
            else { continue }
            found = (payload, rl)
            break
        }
        guard let (payload, rl) = found else {
            st.note = "No rate-limit data in sessions"
            return st
        }
        for key in ["primary", "secondary"] {
            guard let w = rl[key] as? [String: Any],
                  let used = w["used_percent"] as? Double else { continue }
            let minutes = w["window_minutes"] as? Double ?? 0
            let resets = (w["resets_at"] as? Double).map { Date(timeIntervalSince1970: $0) }
            st.items.append(UsageItem(
                id: "codex-\(key)",
                label: windowLabel(minutes),
                short: shortLabel(minutes),
                percent: used,
                severity: used >= 100 ? "exceeded" : "normal",
                resetsAt: resets
            ))
        }
        var bits: [String] = []
        if let plan = rl["plan_type"] as? String { bits.append("\(plan) plan") }
        if let info = payload["info"] as? [String: Any],
           let total = info["total_token_usage"] as? [String: Any],
           let n = total["total_tokens"] as? Double {
            bits.append("last run \(tokenText(n)) tokens")
        }
        if let credits = rl["credits"] as? [String: Any],
           credits["has_credits"] as? Bool == true,
           let balance = credits["balance"] as? String {
            bits.append("credits \(balance)")
        }
        st.note = bits.isEmpty ? nil : bits.joined(separator: " · ")
        let attrs = try? fm.attributesOfItem(atPath: file.path)
        st.updatedAt = attrs?[.modificationDate] as? Date
        return st
    }

    private static func newestSession() -> URL? {
        let dir = home().appendingPathComponent(".codex/sessions")
        guard let en = FileManager.default.enumerator(
            at: dir, includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return nil }
        var best: (URL, Date)?
        for case let url as URL in en where url.pathExtension == "jsonl" {
            let d = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            if best == nil || d > best!.1 { best = (url, d) }
        }
        return best?.0
    }

    private static func rateLimitCandidates(_ url: URL) -> [String] {
        // Read only the tail — session logs grow to many MB and we need the newest entry.
        guard let fh = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? fh.close() }
        let size = (try? fh.seekToEnd()) ?? 0
        let window: UInt64 = 262_144
        try? fh.seek(toOffset: size > window ? size - window : 0)
        guard let data = try? fh.readToEnd() else { return [] }
        // Lenient decode: the seek can land mid-codepoint; a mangled first line just won't match.
        let text = String(decoding: data, as: UTF8.self)
        return text.components(separatedBy: "\n").reversed().filter {
            $0.contains("\"rate_limits\"") && $0.contains("used_percent")
        }
    }

    private static func windowLabel(_ minutes: Double) -> String {
        if minutes >= 10080 { return "Weekly" }
        if (250...350).contains(minutes) { return "Session (5h)" }
        return "\(Int(minutes / 60))h window"
    }

    private static func shortLabel(_ minutes: Double) -> String {
        if minutes >= 10080 { return "7d" }
        return "\(Int(minutes / 60))h"
    }
}

// MARK: - Gemini (auth status only — no public usage API)

enum GeminiFetcher {
    static func fetch() -> ProviderState {
        var st = ProviderState()
        st.connected = FileManager.default.fileExists(
            atPath: home().appendingPathComponent(".gemini/oauth_creds.json").path
        )
        st.note = st.connected
            ? "Connected — Gemini exposes no usage API yet"
            : "Login via browser"
        if st.connected { st.updatedAt = Date() }
        return st
    }
}

// MARK: - Model

final class UsageModel: ObservableObject {
    @Published var states: [Provider: ProviderState] = [:]
    @Published var selected: Provider {
        didSet { UserDefaults.standard.set(selected.rawValue, forKey: "provider") }
    }
    // ponytail: hover state lives here because bare swiftc can't load the @State macro on this SDK
    @Published var hovering = false
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published var onboarding = !UserDefaults.standard.bool(forKey: "didOnboard")
    var onHoverChange: ((Bool) -> Void)?
    private var timer: Timer?
    private var lastFetch = Date.distantPast
    private var isRefreshing = false
    private var hoverWork: DispatchWorkItem?

    @Published var resetArmed = false
    private var disarmWork: DispatchWorkItem?

    /// Two-tap confirm — consuming a reset credit is a real account action.
    func resetCodexLimit() {
        if !resetArmed {
            resetArmed = true
            disarmWork?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.resetArmed = false }
            disarmWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: work)
            return
        }
        disarmWork?.cancel()
        resetArmed = false
        states[.gpt, default: ProviderState()].note = "Resetting limit…"
        DispatchQueue.global(qos: .userInitiated).async {
            let ok = CodexFetcher.consumeResetCredit()
            DispatchQueue.main.async {
                self.states[.gpt, default: ProviderState()].note = ok
                    ? "Limit reset ✓"
                    : "Reset failed — try again or use the Codex CLI"
                if ok { self.refresh() }
            }
        }
    }

    func endOnboarding() {
        guard onboarding else { return }
        onboarding = false
        UserDefaults.standard.set(true, forKey: "didOnboard")
    }

    func setHover(_ h: Bool) {
        hoverWork?.cancel()
        hoverWork = nil
        if h {
            endOnboarding()
            applyHover(true)
        } else {
            // Debounce exit so edge flicker doesn't stutter the collapse animation.
            let work = DispatchWorkItem { [weak self] in self?.applyHover(false) }
            hoverWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
        }
    }

    private func applyHover(_ h: Bool) {
        guard hovering != h else { return }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) { hovering = h }
        onHoverChange?(h)
    }

    init() {
        selected = Provider(rawValue: UserDefaults.standard.string(forKey: "provider") ?? "") ?? .claude
    }

    var current: ProviderState { states[selected] ?? ProviderState() }

    func start() {
        refresh()
        // ponytail: 60s polling; make configurable if it ever matters
        let t = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        t.tolerance = 5
        RunLoop.main.add(t, forMode: .common)
        timer = t

        // First run: open the card once with a hint so the pill isn't a mystery.
        if onboarding {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                guard let self, self.onboarding else { return }
                self.applyHover(true)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 9) { [weak self] in
                guard let self, self.onboarding else { return }
                self.endOnboarding()
                self.applyHover(false)
            }
        }
    }

    func refreshIfStale() {
        if Date().timeIntervalSince(lastFetch) > 30 { refresh() }
    }

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        lastFetch = Date()
        DispatchQueue.global(qos: .utility).async {
            let result: [Provider: ProviderState] = [
                .claude: ClaudeFetcher.fetch(),
                .gpt: CodexFetcher.fetch(),
                .gemini: GeminiFetcher.fetch(),
            ]
            DispatchQueue.main.async {
                self.isRefreshing = false
                // Keep last good data when a provider hiccups (network blip, log rotation).
                var merged: [Provider: ProviderState] = [:]
                for (p, fresh) in result {
                    if fresh.items.isEmpty, fresh.connected,
                       let old = self.states[p], !old.items.isEmpty {
                        var keep = old
                        keep.note = fresh.note ?? old.note
                        keep.retryAt = fresh.retryAt
                        merged[p] = keep
                    } else {
                        merged[p] = fresh
                    }
                }
                self.states = merged
                // Fire a refresh right when the earliest backoff expires instead of
                // waiting out the rest of the 60s poll cycle.
                if let soonest = merged.values.compactMap(\.retryAt).min(),
                   soonest > Date() {
                    DispatchQueue.main.asyncAfter(
                        deadline: .now() + soonest.timeIntervalSinceNow + 1
                    ) { [weak self] in
                        // Full refresh, not refreshIfStale — the 30s staleness throttle
                        // would swallow this exact-moment retry and leave "retrying…" stuck.
                        self?.refresh()
                    }
                }
            }
        }
    }

    func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("AIsland: launch-at-login toggle failed: \(error)")
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func connect(_ p: Provider) {
        states[p, default: ProviderState()].note = "Opening Terminal…"
        let script = """
        tell application "Terminal"
            activate
            do script "\(p.loginCommand)"
        end tell
        """
        DispatchQueue.global(qos: .userInitiated).async {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            proc.arguments = ["-e", script]
            var ok = true
            do {
                try proc.run()
                proc.waitUntilExit()
                ok = proc.terminationStatus == 0
            } catch { ok = false }
            DispatchQueue.main.async {
                self.states[p, default: ProviderState()].note = ok
                    ? "Finish login in Terminal, then hit refresh"
                    : "Couldn't open Terminal — run: \(p.loginCommand)"
            }
        }
    }
}
