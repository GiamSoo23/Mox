import Foundation

/// Minimal Supabase REST client for Mox. Talks to Storage + PostgREST directly.
final class SupabaseService {
    struct CurrentFile: Decodable, Equatable {
        let storage_path: String
        let original_name: String
        let mime_type: String?
        let size_bytes: Int64
        let uploaded_from: String
        let uploaded_at: String
    }

    private let baseURL: URL
    private let anonKey: String
    private let session: URLSession
    private let bucket = "mox"

    init(config: Config) {
        self.baseURL = config.supabaseURL
        self.anonKey = config.supabaseAnonKey
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 120
        cfg.timeoutIntervalForResource = 600
        self.session = URLSession(configuration: cfg)
    }

    // MARK: Public API

    /// Reads the current file row, or nil if the table is empty.
    func fetchCurrent() async throws -> CurrentFile? {
        var req = restRequest(path: "current_file", query: "id=eq.1&select=*")
        req.httpMethod = "GET"
        let (data, resp) = try await session.data(for: req)
        try expect2xx(resp, data)
        let rows = try JSONDecoder().decode([CurrentFile].self, from: data)
        return rows.first
    }

    /// Uploads a local file and atomically updates the current_file row.
    /// Returns the row that was written.
    func uploadFile(localPath: String, uploadedFrom: String = "mac") async throws -> CurrentFile {
        let url = URL(fileURLWithPath: localPath)
        let attrs = try FileManager.default.attributesOfItem(atPath: localPath)
        let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        guard size > 0 else { throw MoxError.upload("File is empty.") }
        guard size <= 500 * 1024 * 1024 else {
            throw MoxError.upload("File exceeds 500 MB cap.")
        }
        let ext = url.pathExtension.isEmpty ? "bin" : url.pathExtension
        let storagePath = "current.\(ext)"
        let mime = mimeType(for: ext)

        try await storageUpload(localFile: url, storagePath: storagePath, mime: mime)

        let row: [String: Any] = [
            "id": 1,
            "storage_path": storagePath,
            "original_name": url.lastPathComponent,
            "mime_type": mime,
            "size_bytes": size,
            "uploaded_from": uploadedFrom
        ]
        return try await upsertCurrent(row)
    }

    /// Generates a short-lived signed download URL.
    func signedDownloadURL(for path: String, expiresIn seconds: Int = 600) async throws -> URL {
        var req = storageRequest(path: "object/sign/\(bucket)/\(path)")
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["expiresIn": seconds])
        let (data, resp) = try await session.data(for: req)
        try expect2xx(resp, data)
        struct Reply: Decodable { let signedURL: String }
        let r = try JSONDecoder().decode(Reply.self, from: data)
        // signedURL is path-only, prefix with /storage/v1
        let full = baseURL.appendingPathComponent("storage/v1").absoluteString + r.signedURL
        guard let u = URL(string: full) else { throw MoxError.upload("Bad signed URL") }
        return u
    }

    /// Downloads the current file directly to a local destination URL.
    func downloadCurrent(to dest: URL) async throws {
        guard let current = try await fetchCurrent() else {
            throw MoxError.upload("Nothing to download.")
        }
        let signed = try await signedDownloadURL(for: current.storage_path)
        let (tmp, resp) = try await session.download(from: signed)
        try expect2xx(resp, Data())
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.moveItem(at: tmp, to: dest)
    }

    // MARK: Internals

    private func storageUpload(localFile: URL, storagePath: String, mime: String) async throws {
        var req = storageRequest(path: "object/\(bucket)/\(storagePath)")
        req.httpMethod = "POST"
        req.setValue(mime, forHTTPHeaderField: "Content-Type")
        req.setValue("true", forHTTPHeaderField: "x-upsert")
        let (data, resp) = try await session.upload(for: req, fromFile: localFile)
        try expect2xx(resp, data)
    }

    private func upsertCurrent(_ row: [String: Any]) async throws -> CurrentFile {
        var req = restRequest(path: "current_file", query: "on_conflict=id")
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("resolution=merge-duplicates,return=representation",
                     forHTTPHeaderField: "Prefer")
        req.httpBody = try JSONSerialization.data(withJSONObject: row)
        let (data, resp) = try await session.data(for: req)
        try expect2xx(resp, data)
        let rows = try JSONDecoder().decode([CurrentFile].self, from: data)
        guard let r = rows.first else { throw MoxError.upload("No row returned.") }
        return r
    }

    private func storageRequest(path: String) -> URLRequest {
        var req = URLRequest(url: baseURL.appendingPathComponent("storage/v1/\(path)"))
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        return req
    }

    private func restRequest(path: String, query: String? = nil) -> URLRequest {
        var comps = URLComponents(
            url: baseURL.appendingPathComponent("rest/v1/\(path)"),
            resolvingAgainstBaseURL: false
        )!
        comps.query = query
        var req = URLRequest(url: comps.url!)
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        return req
    }

    private func expect2xx(_ resp: URLResponse, _ body: Data) throws {
        guard let http = resp as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            let msg = String(data: body, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw MoxError.upload("Supabase: HTTP \(http.statusCode) — \(msg)")
        }
    }

    private func mimeType(for ext: String) -> String {
        let map: [String: String] = [
            "png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg",
            "heic": "image/heic", "gif": "image/gif", "webp": "image/webp",
            "pdf": "application/pdf", "zip": "application/zip",
            "txt": "text/plain", "md": "text/markdown",
            "mp4": "video/mp4", "mov": "video/quicktime",
            "mp3": "audio/mpeg", "m4a": "audio/mp4",
            "json": "application/json"
        ]
        return map[ext.lowercased()] ?? "application/octet-stream"
    }
}

enum MoxError: LocalizedError {
    case upload(String)
    var errorDescription: String? {
        switch self { case .upload(let m): return m }
    }
}
