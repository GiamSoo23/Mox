import Foundation
import Network

/// What the browser brought back to `http://localhost:53682/callback` at
/// the end of "Sign in with Supabase" (#81).
public enum OAuthCallback: Equatable {
    case code(String)
    case denied(String)
    /// Not the callback (a favicon request, another path): ignore it.
    case notCallback

    /// Reads the first line of an HTTP request, e.g.
    /// `GET /callback?code=…&state=… HTTP/1.1`. A callback whose `state`
    /// isn't the one we sent is refused, so another page can't feed Mox a code.
    public static func parse(requestLine: String, expectedState: String) -> OAuthCallback {
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2, parts[0] == "GET",
              let comps = URLComponents(string: "http://localhost" + parts[1]),
              comps.path == "/callback" else { return .notCallback }
        var query: [String: String] = [:]
        for item in comps.queryItems ?? [] where query[item.name] == nil {
            query[item.name] = item.value ?? ""
        }
        if let error = query["error"] {
            return .denied(query["error_description"] ?? error)
        }
        guard query["state"] == expectedState else {
            return .denied("The sign-in answer didn't match this request. Try again.")
        }
        guard let code = query["code"], !code.isEmpty else {
            return .denied("Supabase didn't send a sign-in code. Try again.")
        }
        return .code(code)
    }
}

/// A one-shot web server on the loopback port the OAuth app redirects to.
/// It accepts connections from this Mac only, answers the browser with a
/// short "you can close this tab" page, and stops after the callback.
public final class OAuthLoopbackServer {
    public static let port: UInt16 = 53682

    private let expectedState: String
    private let queue = DispatchQueue(label: "com.mox.oauth-loopback")
    private var listener: NWListener?
    private var continuation: CheckedContinuation<String, Error>?

    public init(expectedState: String) {
        self.expectedState = expectedState
    }

    /// Starts listening and returns the authorization code once the browser
    /// comes back. Call `stop()` to give up (the wait then throws).
    public func waitForCode() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                self.continuation = continuation
                do {
                    try self.start()
                } catch {
                    self.finish(.failure(OAuthLoopbackError.portBusy))
                }
            }
        }
    }

    public func stop() {
        queue.async { self.finish(.failure(CancellationError())) }
    }

    private func start() throws {
        let params = NWParameters.tcp
        params.acceptLocalOnly = true
        params.allowLocalEndpointReuse = true
        guard let port = NWEndpoint.Port(rawValue: Self.port) else { throw OAuthLoopbackError.portBusy }
        let listener = try NWListener(using: params, on: port)
        listener.newConnectionHandler = { [weak self] connection in self?.handle(connection) }
        listener.stateUpdateHandler = { [weak self] state in
            if case .failed = state { self?.finish(.failure(OAuthLoopbackError.portBusy)) }
        }
        self.listener = listener
        listener.start(queue: queue)
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, _, _ in
            guard let self else { return connection.cancel() }
            let text = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let firstLine = text.components(separatedBy: "\r\n").first ?? ""
            let result = OAuthCallback.parse(requestLine: firstLine, expectedState: self.expectedState)
            let page: String
            switch result {
            case .notCallback:
                Self.respond(connection, status: "404 Not Found", body: "")
                return
            case .code(let code):
                page = "Signed in. You can close this tab and go back to Mox."
                self.finish(.success(code))
            case .denied(let reason):
                page = "Mox couldn't sign in: \(reason)"
                self.finish(.failure(OAuthLoopbackError.denied(reason)))
            }
            Self.respond(connection, status: "200 OK", body: Self.html(page))
        }
    }

    private func finish(_ result: Result<String, Error>) {
        listener?.cancel()
        listener = nil
        continuation?.resume(with: result)
        continuation = nil
    }

    private static func respond(_ connection: NWConnection, status: String, body: String) {
        let bytes = Data(body.utf8)
        let head = "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\n"
            + "Content-Length: \(bytes.count)\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(head.utf8) + bytes, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    static func html(_ message: String) -> String {
        let escaped = message
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        return """
            <!DOCTYPE html><html><head><meta charset="utf-8"><title>Mox</title></head>
            <body style="font-family: -apple-system, sans-serif; text-align: center; margin-top: 20vh">
            <h2>\(escaped)</h2></body></html>
            """
    }
}

public enum OAuthLoopbackError: LocalizedError, Equatable {
    case portBusy
    case denied(String)

    public var errorDescription: String? {
        switch self {
        case .portBusy:
            return "Another app is using port \(OAuthLoopbackServer.port), which Mox needs to finish "
                + "signing in. Close it, or use an access token instead."
        case .denied(let reason):
            return reason
        }
    }
}
