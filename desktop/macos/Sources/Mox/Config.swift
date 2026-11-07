import Foundation

struct Config {
    let supabaseURL: URL
    let supabaseAnonKey: String
    let hotkey: HotKeyCombo
    let pollInterval: TimeInterval

    static func load() throws -> Config {
        let env = loadEnv()

        guard let urlString = env["SUPABASE_URL"], let url = URL(string: urlString) else {
            throw ConfigError.missing("SUPABASE_URL")
        }
        guard let key = env["SUPABASE_ANON_KEY"], !key.isEmpty else {
            throw ConfigError.missing("SUPABASE_ANON_KEY")
        }

        // Default is ⌘⇧M — ⌘⇧U is taken by Finder's "Go → Utilities" menu,
        // which intercepts the keystroke when Finder is the active app.
        let hotkey = HotKeyCombo.parse(env["MOX_HOTKEY"] ?? "cmd+shift+m")
            ?? HotKeyCombo(key: .m, modifiers: [.command, .shift])
        let poll = TimeInterval(env["MOX_POLL_SECONDS"] ?? "") ?? 5

        return Config(supabaseURL: url, supabaseAnonKey: key, hotkey: hotkey, pollInterval: poll)
    }

    /// Look for a .env in (1) $MOX_ENV, (2) ~/.config/mox/.env, (3) cwd, (4) next to the binary.
    private static func loadEnv() -> [String: String] {
        var merged: [String: String] = [:]
        for (key, value) in ProcessInfo.processInfo.environment { merged[key] = value }

        let candidates: [String] = [
            ProcessInfo.processInfo.environment["MOX_ENV"],
            (FileManager.default.homeDirectoryForCurrentUser.path as NSString)
                .appendingPathComponent(".config/mox/.env"),
            FileManager.default.currentDirectoryPath + "/.env",
            (Bundle.main.bundlePath as NSString).appendingPathComponent("Contents/Resources/.env"),
            (Bundle.main.executableURL?.deletingLastPathComponent().path).map { $0 + "/.env" }
        ].compactMap { $0 }

        for path in candidates {
            guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
            for raw in text.split(whereSeparator: \.isNewline) {
                let line = raw.trimmingCharacters(in: .whitespaces)
                if line.isEmpty || line.hasPrefix("#") { continue }
                guard let separator = line.firstIndex(of: "=") else { continue }
                let key = String(line[..<separator]).trimmingCharacters(in: .whitespaces)
                var value = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
                if value.hasPrefix("\""), value.hasSuffix("\"") { value = String(value.dropFirst().dropLast()) }
                if merged[key] == nil { merged[key] = value }
            }
        }
        return merged
    }
}

enum ConfigError: LocalizedError {
    case missing(String)
    var errorDescription: String? {
        switch self {
        case .missing(let key): return "Missing \(key). Copy .env.example to .env and fill it in."
        }
    }
}
