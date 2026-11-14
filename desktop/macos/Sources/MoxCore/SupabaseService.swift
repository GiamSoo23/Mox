import Foundation

/// Speaks the Mox protocol v2 (shared/PROTOCOL.md) to the owner's Supabase
/// project over REST: Auth, PostgREST (schema `mox`) and Storage.
public final class SupabaseService {
    private let settings: MoxSettings
    private let deviceID: UUID
    private let session: URLSession
    private let tokens = TokenStore()
    private let bucket = "mox"
    /// v2 always stores the file under this name (#34).
    private let objectName = "current"

    public init(settings: MoxSettings, deviceID: UUID, session: URLSession? = nil) {
        self.settings = settings
        self.deviceID = deviceID
        self.session = session ?? {
            let cfg = URLSessionConfiguration.default
            cfg.timeoutIntervalForRequest = 120
            cfg.timeoutIntervalForResource = 600
            return URLSession(configuration: cfg)
        }()
    }

    // MARK: Protocol calls

    /// §4.1: signs in and checks that the project speaks schema v2 and that
    /// this user is the owner.
    public func checkSchema() async throws {
        let data = try await send { token in self.rest("meta", query: "select=schema_version", token: token) }
        guard let meta = try JSONDecoder().decode([MetaRow].self, from: data).first else { throw MoxError.notOwner }
        guard meta.schemaVersion == 2 else { throw MoxError.schemaMismatch(meta.schemaVersion) }
    }

    /// §4.2: the file in the slot, or nil when nothing has been sent yet.
    public func fetchCurrent() async throws -> CurrentFile? {
        let data = try await send { token in self.rest("current_file", query: "id=eq.1&select=*", token: token) }
        guard let row = try JSONDecoder().decode([CurrentFile].self, from: data).first else { return nil }
        try row.validate()
        return row
    }

    /// §4.3 + §4.4: uploads the bytes, then replaces the row. Bytes first, so
    /// other devices never see a row pointing at a file that isn't there yet.
    public func uploadFile(localPath: String) async throws -> CurrentFile {
        let url = URL(fileURLWithPath: localPath)
        let attrs = try FileManager.default.attributesOfItem(atPath: localPath)
        let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        guard size > 0 else { throw MoxError.upload("The file is empty.") }
        guard size <= CurrentFile.maxSize else { throw MoxError.tooLarge(size) }
        let mime = MimeTypes.forExtension(url.pathExtension)
        return try await upload(url, name: url.lastPathComponent, mime: mime, size: size, kind: "file")
    }

    /// Sends what was selected: one file as is, or several files and folders
    /// as a bundle (PROTOCOL.md §9).
    public func uploadSelection(_ paths: [String]) async throws -> CurrentFile {
        let urls = paths.map { URL(fileURLWithPath: $0) }
        let items = try BundleWriter.items(for: urls)
        guard !items.isEmpty else { throw MoxError.upload("There's nothing to send in what's selected.") }
        if items.count == 1 { return try await uploadFile(localPath: items[0].source.path) }
        let zip = FileManager.default.temporaryDirectory.appendingPathComponent("mox-bundle-\(UUID().uuidString).zip")
        defer { try? FileManager.default.removeItem(at: zip) }
        try BundleWriter.write(items, to: zip)
        let size = (try FileManager.default.attributesOfItem(atPath: zip.path)[.size] as? NSNumber)?.int64Value ?? 0
        guard size <= CurrentFile.maxSize else { throw MoxError.tooLarge(size) }
        return try await upload(zip, name: BundleWriter.fileName(count: items.count), mime: "application/zip",
                                size: size, kind: "bundle", itemCount: items.count)
    }

    /// Sends plain text as a text item (#101).
    public func uploadText(_ text: String) async throws -> CurrentFile {
        let data = try TextPayload.encode(text)
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("mox-text-\(UUID().uuidString).txt")
        try data.write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }
        return try await upload(tmp, name: TextPayload.fileName, mime: TextPayload.mime,
                                size: Int64(data.count), kind: "text")
    }

    /// The current item's contents as text (#101).
    public func downloadText() async throws -> String {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("mox-text-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: tmp) }
        try await downloadCurrent(to: tmp)
        return TextPayload.decode(try Data(contentsOf: tmp))
    }

    private func upload(_ url: URL, name: String, mime: String, size: Int64, kind: String,
                        itemCount: Int = 1) async throws -> CurrentFile {
        _ = try await send(upload: url) { token in
            var req = self.request("storage/v1/object/\(self.bucket)/\(self.objectName)", token: token)
            req.httpMethod = "POST"
            req.setValue(mime, forHTTPHeaderField: "Content-Type")
            req.setValue("true", forHTTPHeaderField: "x-upsert")
            return req
        }

        let row: [String: Any] = [
            "id": 1,
            "original_name": name,
            "mime_type": mime,
            "size_bytes": size,
            "kind": kind,
            "item_count": itemCount,
            "source_platform": "macos",
            "source_device_id": deviceID.uuidString.lowercased()
        ]
        let body = try JSONSerialization.data(withJSONObject: row)
        let data = try await send { token in
            var req = self.rest("current_file", query: "on_conflict=id", token: token, writing: true)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue("resolution=merge-duplicates,return=representation", forHTTPHeaderField: "Prefer")
            req.httpBody = body
            return req
        }
        guard let written = try JSONDecoder().decode([CurrentFile].self, from: data).first else {
            throw MoxError.upload("Supabase didn't return the new row.")
        }
        return written
    }

    /// §4.5: a short-lived download link that needs no credentials.
    public func signedDownloadURL(expiresIn seconds: Int = 600) async throws -> URL {
        struct Reply: Decodable { let signedURL: String }
        let body = try JSONSerialization.data(withJSONObject: ["expiresIn": seconds])
        let data = try await send { token in
            var req = self.request("storage/v1/object/sign/\(self.bucket)/\(self.objectName)", token: token)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = body
            return req
        }
        let reply = try JSONDecoder().decode(Reply.self, from: data)
        // signedURL is relative: prefix it with /storage/v1.
        guard let url = URL(string: settings.projectURL.appendingPathComponent("storage/v1").absoluteString
                                + reply.signedURL) else {
            throw MoxError.upload("Supabase returned an invalid download link.")
        }
        return url
    }

    /// §4.6: downloads the current file to `dest`, replacing it if present.
    public func downloadCurrent(to dest: URL) async throws {
        let signed = try await signedDownloadURL()
        let (tmp, resp) = try await session.download(from: signed)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw MoxError.http(status, "download failed") }
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.moveItem(at: tmp, to: dest)
    }

    // MARK: Auth (§2)

    /// Sends a request built with a valid access token. On 401 it signs in
    /// again and retries once.
    private func send(upload file: URL? = nil, _ build: @escaping (String) -> URLRequest) async throws -> Data {
        for attempt in 0..<2 {
            let token = try await accessToken(renew: attempt > 0)
            let req = build(token)
            let (data, resp) = try await {
                if let file { return try await session.upload(for: req, fromFile: file) }
                return try await session.data(for: req)
            }()
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if status == 401, attempt == 0 { continue }
            guard (200..<300).contains(status) else {
                throw MoxError.http(status, String(data: data, encoding: .utf8) ?? "")
            }
            return data
        }
        throw MoxError.signInFailed
    }

    private func accessToken(renew: Bool) async throws -> String {
        if !renew, let token = await tokens.valid() { return token }
        let (token, lifetime) = try await signIn()
        await tokens.store(token, expiresIn: lifetime)
        return token
    }

    /// Signs in as the Mox user. Each device keeps its own session.
    private func signIn() async throws -> (String, TimeInterval) {
        var comps = URLComponents(url: settings.projectURL.appendingPathComponent("auth/v1/token"),
                                  resolvingAgainstBaseURL: false)
        comps?.queryItems = [URLQueryItem(name: "grant_type", value: "password")]
        guard let url = comps?.url else { throw MoxError.signInFailed }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(settings.publishableKey, forHTTPHeaderField: "apikey")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["email": settings.email,
                                                                   "password": settings.password])
        let (data, resp) = try await session.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw MoxError.signInFailed }
        let reply = try JSONDecoder().decode(SignInReply.self, from: data)
        return (reply.accessToken, reply.expiresIn)
    }

    // MARK: Request building (§3)

    private func request(_ path: String, query: String? = nil, token: String) -> URLRequest {
        var comps = URLComponents(url: settings.projectURL.appendingPathComponent(path),
                                  resolvingAgainstBaseURL: false)
        comps?.percentEncodedQuery = query
        var req = URLRequest(url: comps?.url ?? settings.projectURL)
        req.setValue(settings.publishableKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return req
    }

    /// A PostgREST request against the `mox` schema.
    private func rest(_ table: String, query: String, token: String, writing: Bool = false) -> URLRequest {
        var req = request("rest/v1/\(table)", query: query, token: token)
        req.setValue("mox", forHTTPHeaderField: writing ? "Content-Profile" : "Accept-Profile")
        return req
    }
}

/// `mox.meta`, as far as clients care.
private struct MetaRow: Decodable {
    let schemaVersion: Int
    enum CodingKeys: String, CodingKey { case schemaVersion = "schema_version" }
}

/// The parts of Supabase Auth's sign-in response Mox uses.
private struct SignInReply: Decodable {
    let accessToken: String
    let expiresIn: TimeInterval
    enum CodingKeys: String, CodingKey { case accessToken = "access_token", expiresIn = "expires_in" }
}

/// The current access token, shared safely across concurrent requests.
actor TokenStore {
    private var token: String?
    private var expiry = Date.distantPast

    /// The token if it's valid for at least another minute.
    func valid() -> String? {
        guard let token, expiry.timeIntervalSinceNow > 60 else { return nil }
        return token
    }

    func store(_ token: String, expiresIn lifetime: TimeInterval) {
        self.token = token
        expiry = Date().addingTimeInterval(lifetime)
    }
}
