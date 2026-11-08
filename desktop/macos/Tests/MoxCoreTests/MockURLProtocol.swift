import Foundation

/// Intercepts URLSession requests in tests: records each request and
/// answers with whatever `handler` returns. No network involved.
final class MockURLProtocol: URLProtocol {
    struct Recorded {
        let request: URLRequest
        let body: Data
    }

    nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, Data))?
    nonisolated(unsafe) static var recorded: [Recorded] = []

    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        recorded = []
        return URLSession(configuration: config)
    }

    /// Reply with `status` and a JSON body for every request.
    static func reply(_ status: Int, _ json: String) {
        handler = { _ in (status, Data(json.utf8)) }
    }

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        // URLSession moves httpBody into a stream before protocols see it.
        var body = request.httpBody ?? Data()
        if body.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: buffer.count)
                if read <= 0 { break }
                body.append(buffer, count: read)
            }
            stream.close()
        }
        Self.recorded.append(Recorded(request: request, body: body))
        let (status, data) = Self.handler?(request) ?? (500, Data())
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    /// The body as UTF-8 text.
    static func text(_ data: Data) -> String { String(bytes: data, encoding: .utf8) ?? "" }

    static var lastJSON: [String: Any] {
        (try? JSONSerialization.jsonObject(with: recorded.last?.body ?? Data())) as? [String: Any] ?? [:]
    }
}
