import Foundation

/// Settings read at launch from the process environment and `.env` files.
/// The Supabase settings are optional here: normally they live in the
/// Keychain, and a `.env` is only a developer convenience.
public struct Config {
    /// Present only when all four values are set (URL, publishable key, Mox
    /// user email and password).
    public let settings: MoxSettings?
    public let hotkey: HotKeyCombo
    public let pollInterval: TimeInterval

    /// Builds the configuration. The process environment wins over files,
    /// and earlier files win over later ones (see `defaultEnvFilePaths`).
    public static func load(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        envFilePaths: [String]? = nil
    ) -> Config {
        let paths = envFilePaths ?? defaultEnvFilePaths(environment: environment)
        let files = paths.compactMap { try? String(contentsOfFile: $0, encoding: .utf8) }
        return from(EnvFile.merge(environment: environment, files: files))
    }

    /// Builds the configuration from already-merged values.
    public static func from(_ env: [String: String]) -> Config {
        func value(_ name: String) -> String? { env[name].flatMap { $0.isEmpty ? nil : $0 } }
        var settings: MoxSettings?
        // SUPABASE_ANON_KEY is the pre-v2 name, still accepted.
        if let urlString = value("SUPABASE_URL"), let url = URL(string: urlString),
           let key = value("SUPABASE_PUBLISHABLE_KEY") ?? value("SUPABASE_ANON_KEY"),
           let email = value("MOX_USER_EMAIL"), let password = value("MOX_USER_PASSWORD") {
            settings = MoxSettings(projectURL: url, publishableKey: key, email: email, password: password)
        }

        // Default is ⌘⇧M — ⌘⇧U is taken by Finder's "Go → Utilities" menu,
        // which intercepts the keystroke when Finder is the active app.
        let hotkey = HotKeyCombo.parse(env["MOX_HOTKEY"] ?? "cmd+shift+m")
            ?? HotKeyCombo(key: .m, modifiers: [.command, .shift])
        let poll = TimeInterval(env["MOX_POLL_SECONDS"] ?? "") ?? 5

        return Config(settings: settings, hotkey: hotkey, pollInterval: poll)
    }

    /// Where `.env` files are looked for, in order: $MOX_ENV,
    /// ~/.config/mox/.env, the current directory, the app bundle's
    /// Resources, and the folder next to the binary.
    public static func defaultEnvFilePaths(environment: [String: String]) -> [String] {
        [
            environment["MOX_ENV"],
            (FileManager.default.homeDirectoryForCurrentUser.path as NSString)
                .appendingPathComponent(".config/mox/.env"),
            FileManager.default.currentDirectoryPath + "/.env",
            (Bundle.main.bundlePath as NSString).appendingPathComponent("Contents/Resources/.env"),
            (Bundle.main.executableURL?.deletingLastPathComponent().path).map { $0 + "/.env" }
        ].compactMap { $0 }
    }
}

/// Parsing for simple `.env` files: `KEY=value` lines, `#` comments, blank
/// lines, and optional double quotes around the value.
public enum EnvFile {
    public static func parse(_ text: String) -> [String: String] {
        var values: [String: String] = [:]
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            guard let separator = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<separator]).trimmingCharacters(in: .whitespaces)
            var value = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
            if value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") {
                value = String(value.dropFirst().dropLast())
            }
            if values[key] == nil { values[key] = value }
        }
        return values
    }

    /// The environment first, then each file in order. The first value
    /// found for a key wins.
    public static func merge(environment: [String: String], files: [String]) -> [String: String] {
        var merged = environment
        for text in files {
            for (key, value) in parse(text) where merged[key] == nil {
                merged[key] = value
            }
        }
        return merged
    }
}
