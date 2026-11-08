import Foundation

/// The single row in `current_file`: the file currently held by Mox.
public struct CurrentFile: Decodable, Equatable {
    public let storagePath: String
    public let originalName: String
    public let mimeType: String?
    public let sizeBytes: Int64
    public let uploadedFrom: String
    public let uploadedAt: String

    /// The row's JSON uses the table's snake_case column names.
    enum CodingKeys: String, CodingKey {
        case storagePath = "storage_path"
        case originalName = "original_name"
        case mimeType = "mime_type"
        case sizeBytes = "size_bytes"
        case uploadedFrom = "uploaded_from"
        case uploadedAt = "uploaded_at"
    }
}

/// Minimal Supabase REST client for Mox. Talks to Storage + PostgREST directly.
public final class SupabaseService {
    private let baseURL: URL
    private let anonKey: String
    private let session: URLSession
    private let bucket = "mox"

    public init(config: Config) {
        self.baseURL = config.supabaseURL
        self.anonKey = config.supabaseAnonKey
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 120
        cfg.timeoutIntervalForResource = 600
        self.session = URLSession(configuration: cfg)
    }

    // MARK: Public API

    /// Reads the current file row, or nil if the table is empty.
    public func fetchCurrent() async throws -> CurrentFile? {
        var req = restRequest(path: "current_file", query: "id=eq.1&select=*")
        req.httpMethod = "GET"
        let (data, resp) = try await session.data(for: req)
        try expect2xx(resp, data)
        let rows = try JSONDecoder().decode([CurrentFile].self, from: data)
        return rows.first
    }

    /// Uploads a local file and atomically updates the current_file row.
    /// Returns the row that was written.
    public func uploadFile(localPath: String, uploadedFrom: String = "mac") async throws -> CurrentFile {
        let url = URL(fileURLWithPath: localPath)
        let attrs = try FileManager.default.attributesOfItem(atPath: localPath)
        let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        guard size > 0 else { throw MoxError.upload("File is empty.") }
        guard size <= 500 * 1024 * 1024 else {
            throw MoxError.upload("File exceeds 500 MB cap.")
        }
        let ext = url.pathExtension.isEmpty ? "bin" : url.pathExtension
        let storagePath = "current.\(ext)"
        let mime = MimeTypes.forExtension(ext)

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
    public func signedDownloadURL(for path: String, expiresIn seconds: Int = 600) async throws -> URL {
        var req = storageRequest(path: "object/sign/\(bucket)/\(path)")
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["expiresIn": seconds])
        let (data, resp) = try await session.data(for: req)
        try expect2xx(resp, data)
        struct Reply: Decodable { let signedURL: String }
        let reply = try JSONDecoder().decode(Reply.self, from: data)
        // signedURL is path-only, prefix with /storage/v1
        let full = baseURL.appendingPathComponent("storage/v1").absoluteString + reply.signedURL
        guard let signedURL = URL(string: full) else { throw MoxError.upload("Bad signed URL") }
        return signedURL
    }

    /// Downloads the current file directly to a local destination URL.
    public func downloadCurrent(to dest: URL) async throws {
        guard let current = try await fetchCurrent() else {
            throw MoxError.upload("Nothing to download.")
        }
        let signed = try await signedDownloadURL(for: current.storagePath)
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
        guard let row = rows.first else { throw MoxError.upload("No row returned.") }
        return row
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
}

public enum MoxError: LocalizedError, Equatable {
    case upload(String)
    public var errorDescription: String? {
        switch self {
        case .upload(let message): return message
        }
    }
}
