import Testing
@testable import OpenAPIDynamic
import Foundation
import HTTPTypes
import OpenAPIRuntime

@Test func testClientInitialization() async throws {
    let client = OpenAPIDynamic()
    // Client initializes successfully with default configuration
    #expect(client.session === URLSession.shared)
}

@Test func testRequestBuilder() async throws {
    var builder = RequestBuilder()

    builder.setMethod(.post)
    builder.setURL("https://api.example.com/users?limit=10")
    builder.addHeader(.contentType, "application/json")
    builder.setBody("{\"name\":\"test\"}".data(using: .utf8))

    #expect(builder.method == .post)
    #expect(builder.url.absoluteString == "https://api.example.com/users?limit=10")
    #expect(builder.headers[.contentType] == "application/json")
    #expect(builder.body == "{\"name\":\"test\"}".data(using: .utf8))
}

@Test func testHTTPError() async throws {
    let response = HTTPResponse(status: .badRequest)
    let body = Data("error".utf8)
    let error = HTTPError.statusError(response, body: body)

    #expect(error.localizedDescription == "HTTP 400 Bad Request")
}

@Test func testResponseValidation() async throws {
    let successResponse = HTTPResponse(status: .ok)
    try successResponse.validateSuccess()

    let errorResponse = HTTPResponse(status: .notFound)
    #expect(throws: HTTPError.statusError(errorResponse, body: nil)) {
        try errorResponse.validateSuccess()
    }
}

@Test func testDecodingError() async throws {
    let error = DecodingError.noData
    #expect(error.localizedDescription == "No response data available for decoding")
}

@Test func testUnexpectedStatusError() async throws {
    let status = HTTPResponse.Status.notFound
    let error = UnexpectedStatusError.unexpectedStatus(status)
    #expect(error.localizedDescription == "Unexpected HTTP status: 404")
}

@Test func testDecodeHelper() async throws {
    struct TestModel: Codable, Equatable {
        let value: String
    }

    let json = #"{"value":"test"}"#
    let data = Data(json.utf8)

    let decoded: TestModel = try decode(TestModel.self, from: data)
    #expect(decoded == TestModel(value: "test"))

    #expect(throws: DecodingError.noData) {
        try decode(TestModel.self, from: nil)
    }
}

@Test func testDecodingFailureHandlerReceivesRequestAndResponseContext() async throws {
    struct ObservedUser: Decodable {
        let id: Int
    }

    let url = URL(string: "https://api.example.com/users/1")!
    let responseBody = Data(#"{"id":"not-an-int"}"#.utf8)
    let session = makeMockSession(body: responseBody, for: url)
    let recorder = DecodingFailureContextRecorder()
    let client = OpenAPIDynamic(
        session: session,
        decodingFailureHandler: recorder.record
    )

    do {
        let _: ObservedUser = try await client.sendRequest { builder in
            builder.setMethod(.get)
            builder.setURL(url)
            builder.setOperationID("get-user")
        }
        Issue.record("Expected decoding to fail")
    } catch let error as Swift.DecodingError {
        #expect(String(describing: error).contains("id"))
    } catch {
        Issue.record("Expected Swift.DecodingError, got \(error)")
    }

    let context = try #require(recorder.context)
    #expect(context.method == .get)
    #expect(context.url == url)
    #expect(context.operationID == "get-user")
    #expect(context.response?.status == .ok)
    #expect(context.responseBody == responseBody)
    #expect(ObjectIdentifier(context.targetType) == ObjectIdentifier(ObservedUser.self))
    #expect(context.error is Swift.DecodingError)
}

private func makeMockSession(
    statusCode: Int = 200,
    body: Data?,
    for url: URL
) -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockURLProtocol.self]
    MockURLProtocol.register({ request in
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        return (response, body)
    }, for: url)
    return URLSession(configuration: configuration)
}

private final class DecodingFailureContextRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var _context: DecodingFailureContext?

    var context: DecodingFailureContext? {
        lock.lock()
        defer { lock.unlock() }
        return _context
    }

    func record(_ context: DecodingFailureContext) {
        lock.lock()
        _context = context
        lock.unlock()
    }
}

private final class MockURLProtocol: URLProtocol {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var _handlers: [String: (URLRequest) throws -> (HTTPURLResponse, Data?)] = [:]

    static func register(_ handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data?), for url: URL) {
        lock.lock()
        _handlers[url.absoluteString] = handler
        lock.unlock()
    }

    static func takeHandler(for request: URLRequest) -> ((URLRequest) throws -> (HTTPURLResponse, Data?))? {
        lock.lock()
        defer { lock.unlock() }
        guard let key = request.url?.absoluteString else { return nil }
        return _handlers.removeValue(forKey: key)
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let requestHandler = Self.takeHandler(for: request) else {
            client?.urlProtocol(
                self,
                didFailWithError: URLError(.badServerResponse)
            )
            return
        }

        do {
            let (response, data) = try requestHandler(request)
            client?.urlProtocol(
                self,
                didReceive: response,
                cacheStoragePolicy: .notAllowed
            )
            if let data {
                client?.urlProtocol(self, didLoad: data)
            }
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

// Integration test with a mock server would require additional setup
// For now, we test the client structure and basic functionality

// MARK: - ClientMiddleware tests (deterministic via MockURLProtocol)

struct RecordingMiddleware: ClientMiddleware {
    let name: String
    let recorder: Recorder

    func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String,
        next: @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        recorder.append(name)
        return try await next(request, body, baseURL)
    }
}

struct HeaderInjectingMiddleware: ClientMiddleware {
    let headerName: HTTPField.Name
    let value: String

    func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String,
        next: @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        var req = request
        req.headerFields[headerName] = value
        return try await next(req, body, baseURL)
    }
}

struct ShortCircuitMiddleware: ClientMiddleware {
    let status: HTTPResponse.Status
    let body: Data?

    func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String,
        next: @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        let resp = HTTPResponse(status: status)
        if let b = self.body {
            return (resp, HTTPBody(b))
        }
        return (resp, nil)
    }
}

struct ResponseTransformMiddleware: ClientMiddleware {
    func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String,
        next: @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        let (resp, respBody) = try await next(request, body, baseURL)
        var newResp = HTTPResponse(status: .created)
        newResp.headerFields = resp.headerFields
        return (newResp, respBody)
    }
}

final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private var _calls: [String] = []
    var calls: [String] {
        lock.lock(); defer { lock.unlock() }; return _calls
    }
    func append(_ name: String) {
        lock.lock(); _calls.append(name); lock.unlock()
    }
}

@Test("Middleware execution order matches array order")
func testMiddlewareOrder() async throws {
    let recorder = Recorder()
    let url = URL(string: "https://example.com/test")!
    let session = makeMockSession(statusCode: 200, body: Data("{\"ok\":true}".utf8), for: url)
    let client = OpenAPIDynamic(
        session: session,
        middleware: [
            RecordingMiddleware(name: "first", recorder: recorder),
            RecordingMiddleware(name: "second", recorder: recorder)
        ]
    )
    _ = try await client.sendRequest(method: .get, url: url)

    #expect(recorder.calls == ["first", "second"])
}

@Test("Middleware mutation is visible to transport (header injected)")
func testMiddlewareRequestMutation() async throws {
    let url = URL(string: "https://example.com/mut")!
    var seen: String?
    let session = makeMockSessionWithHandler(for: url) { req in
        seen = req.value(forHTTPHeaderField: "X-Mw")
        let r = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (r, Data("ok".utf8))
    }
    let client = OpenAPIDynamic(
        session: session,
        middleware: [HeaderInjectingMiddleware(headerName: .init("X-Mw")!, value: "injected")]
    )
    _ = try await client.sendRequest(method: .get, url: url)

    #expect(seen == "injected")
}

@Test("Middleware can short-circuit (transport never called)")
func testMiddlewareShortCircuit() async throws {
    let url = URL(string: "https://example.com/sc")!
    var transportHit = false
    let session = makeMockSessionWithHandler(for: url) { req in
        transportHit = true
        let r = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        return (r, Data("transport".utf8))
    }
    let client = OpenAPIDynamic(
        session: session,
        middleware: [ShortCircuitMiddleware(status: .accepted, body: Data("short".utf8))]
    )
    let (resp, data) = try await client.sendRequestWithResponseBody(method: .get, url: url)

    #expect(!transportHit)
    #expect(resp.status == .accepted)
    #expect(data == Data("short".utf8))
}

@Test("Middleware can transform response status and pass body through")
func testMiddlewareResponseTransform() async throws {
    let url = URL(string: "https://example.com/tx")!
    let session = makeMockSession(statusCode: 200, body: Data("payload".utf8), for: url)
    let client = OpenAPIDynamic(
        session: session,
        middleware: [ResponseTransformMiddleware()]
    )
    let (resp, data) = try await client.sendRequestWithResponseBody(method: .get, url: url)

    #expect(resp.status == .created)
    #expect(data == Data("payload".utf8))
}

private final class MetadataRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var _baseURL: URL?
    private var _operationID: String?

    var values: (URL?, String?) {
        lock.lock(); defer { lock.unlock() }
        return (_baseURL, _operationID)
    }

    func record(baseURL: URL, operationID: String) {
        lock.lock(); defer { lock.unlock() }
        _baseURL = baseURL
        _operationID = operationID
    }
}

private struct MetadataMiddleware: ClientMiddleware {
    let recorder: MetadataRecorder

    func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String,
        next: @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        recorder.record(baseURL: baseURL, operationID: operationID)
        return (HTTPResponse(status: .ok), nil)
    }
}

private struct ThrowingMiddleware: ClientMiddleware {
    struct Failure: Error {}

    func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String,
        next: @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        throw Failure()
    }
}

@Test("URL origin and operation ID reach middleware intact")
func testMiddlewareMetadata() async throws {
    let recorder = MetadataRecorder()
    let client = OpenAPIDynamic(defaultOperationID: "fallback", middleware: MetadataMiddleware(recorder: recorder))
    let url = URL(string: "http://user:pass@[::1]:8080/api/items?q=a%2Fb#ignored")!

    _ = try await client.sendRequestStreaming { builder in
        builder.setURL(url)
        builder.setOperationID("list-items")
    }

    let (baseURL, operationID) = recorder.values
    #expect(baseURL?.absoluteString == "http://user:pass@[::1]:8080")
    #expect(operationID == "list-items")
}

@Test("Custom port and encoded path reach URLSession unchanged")
func testURLFidelityAtTransport() async throws {
    let url = URL(string: "http://localhost:8080/a%2Fb?q=x%2Fy")!
    let session = makeMockSession(body: Data(), for: url)
    let client = OpenAPIDynamic(session: session)

    _ = try await client.sendRequest(method: .get, url: url)
}

@Test("Middleware failures use ClientError envelope")
func testMiddlewareErrorEnvelope() async throws {
    let url = URL(string: "https://example.com/error")!
    let client = OpenAPIDynamic(defaultOperationID: "dynamic-op", middleware: ThrowingMiddleware())

    do {
        _ = try await client.sendRequest(method: .get, url: url)
        Issue.record("Expected middleware failure")
    } catch let error as ClientError {
        #expect(error.operationID == "dynamic-op")
        #expect(error.baseURL == URL(string: "https://example.com"))
        #expect(error.causeDescription.contains("Middleware"))
        #expect(error.underlyingError is ThrowingMiddleware.Failure)
    }
}

@Test("Response collection enforces configured limit")
func testResponseBodyLimit() async throws {
    let url = URL(string: "https://example.com/large")!
    let session = makeMockSession(body: Data("12345".utf8), for: url)
    let client = OpenAPIDynamic(session: session, maximumResponseBodyBytes: 4)

    await #expect(throws: (any Error).self) {
        _ = try await client.sendRequestWithResponseBody(method: .get, url: url)
    }
}

@Test("Transport failures use distinct ClientError envelope")
func testTransportErrorEnvelope() async throws {
    let url = URL(string: "https://example.com/transport-error")!
    let session = makeMockSessionWithHandler(for: url) { _ in
        throw URLError(.timedOut)
    }
    let client = OpenAPIDynamic(session: session, defaultOperationID: "transport-op")

    do {
        _ = try await client.sendRequest(method: .get, url: url)
        Issue.record("Expected transport failure")
    } catch let error as ClientError {
        #expect(error.operationID == "transport-op")
        #expect(error.request?.path == "/transport-error")
        #expect(error.baseURL == URL(string: "https://example.com"))
        #expect(error.causeDescription == "Transport threw an error.")
        #expect(error.underlyingError is URLError)
    }
}

@Test("Streaming API returns body without configured collection limit")
func testStreamingResponse() async throws {
    let url = URL(string: "https://example.com/stream")!
    let session = makeMockSession(body: Data("12345".utf8), for: url)
    let client = OpenAPIDynamic(session: session, maximumResponseBodyBytes: 1)

    let (_, body) = try await client.sendRequestStreaming(method: .get, url: url)
    let data = try await Data(collecting: #require(body), upTo: 5)
    #expect(data == Data("12345".utf8))
}

@Suite("URL, middleware, and body edge cases", .serialized)
struct RequestEdgeCaseTests {
    private struct CapturedRequest: Sendable {
        let path: String?
        let baseURL: URL
        let operationID: String
    }

    private final class Capture: @unchecked Sendable {
        private let lock = NSLock()
        private var value: CapturedRequest?

        func record(request: HTTPRequest, baseURL: URL, operationID: String) {
            lock.lock()
            value = CapturedRequest(path: request.path, baseURL: baseURL, operationID: operationID)
            lock.unlock()
        }

        func take() -> CapturedRequest? {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
    }

    private struct CapturingMiddleware: ClientMiddleware {
        let capture: Capture

        func intercept(
            _ request: HTTPRequest,
            body: HTTPBody?,
            baseURL: URL,
            operationID: String,
            next: @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
        ) async throws -> (HTTPResponse, HTTPBody?) {
            capture.record(request: request, baseURL: baseURL, operationID: operationID)
            return (HTTPResponse(status: .ok), nil)
        }
    }

    @Test(
        "Absolute URL decomposition preserves HTTP semantics",
        arguments: [
            ("https://example.com", "https://example.com", "", "dynamic-request"),
            ("https://example.com/", "https://example.com", "/", "dynamic-request"),
            ("http://localhost:8080/api", "http://localhost:8080", "/api", "dynamic-request"),
            ("http://[::1]:8080/a%2Fb?q=x%2Fy", "http://[::1]:8080", "/a%2Fb?q=x%2Fy", "dynamic-request"),
            ("https://user:pass@example.com/private", "https://user:pass@example.com", "/private", "dynamic-request"),
            ("https://example.com/search?empty=&flag", "https://example.com", "/search?empty=&flag", "dynamic-request"),
            ("https://example.com/a#not-sent", "https://example.com", "/a", "dynamic-request")
        ]
    )
    func absoluteURLDecomposition(
        input: String,
        expectedBaseURL: String,
        expectedPath: String,
        expectedOperationID: String
    ) async throws {
        let capture = Capture()
        let client = OpenAPIDynamic(middleware: CapturingMiddleware(capture: capture))

        _ = try await client.sendRequestStreaming(method: .get, url: #require(URL(string: input)))

        let request = try #require(capture.take())
        #expect(request.baseURL.absoluteString == expectedBaseURL)
        #expect(request.path == expectedPath)
        #expect(request.operationID == expectedOperationID)
    }

    @Test(
        "URLSessionTransport reconstructs final URL",
        arguments: [
            ("https://example.com", "https://example.com"),
            ("https://example.com/", "https://example.com/"),
            ("http://localhost:8080/api", "http://localhost:8080/api"),
            ("http://[::1]:8080/a%2Fb?q=x%2Fy", "http://[::1]:8080/a%2Fb?q=x%2Fy"),
            ("https://user:pass@example.com/private", "https://user:pass@example.com/private"),
            ("https://example.com/search?empty=&flag", "https://example.com/search?empty=&flag"),
            ("https://example.com/a#not-sent", "https://example.com/a")
        ]
    )
    func transportURLRoundTrip(input: String, expected: String) async throws {
        let inputURL = try #require(URL(string: input))
        let expectedURL = try #require(URL(string: expected))
        let session = makeMockSessionWithHandler(for: expectedURL) { request in
            #expect(request.url?.absoluteString == expected)
            return (
                HTTPURLResponse(
                    url: try #require(request.url),
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!,
                Data()
            )
        }

        _ = try await OpenAPIDynamic(session: session).sendRequest(method: .get, url: inputURL)
    }

    @Test("Builder inherits configured operation ID")
    func builderDefaultOperationID() async throws {
        let capture = Capture()
        let client = OpenAPIDynamic(
            defaultOperationID: "client-default",
            middleware: CapturingMiddleware(capture: capture)
        )

        _ = try await client.sendRequestStreaming { builder in
            builder.setURL("https://example.com/items")
        }

        #expect(try #require(capture.take()).operationID == "client-default")
    }

    @Test("Explicit operation ID overrides configured default")
    func explicitOperationID() async throws {
        let capture = Capture()
        let client = OpenAPIDynamic(
            defaultOperationID: "client-default",
            middleware: CapturingMiddleware(capture: capture)
        )

        _ = try await client.sendRequestStreaming(
            method: .get,
            url: #require(URL(string: "https://example.com/items")),
            operationID: "explicit"
        )

        #expect(try #require(capture.take()).operationID == "explicit")
    }

    @Test("Relative URL is rejected before middleware and transport")
    func relativeURLRejected() async throws {
        let capture = Capture()
        let client = OpenAPIDynamic(middleware: CapturingMiddleware(capture: capture))
        let url = try #require(URL(string: "/relative/path"))

        await #expect(throws: InvalidRequestURLError(url: url)) {
            _ = try await client.sendRequestStreaming(method: .get, url: url)
        }
        #expect(capture.take() == nil)
    }

    @Test("Zero-byte collection accepts empty body")
    func zeroLimitAcceptsEmptyBody() async throws {
        let url = try #require(URL(string: "https://example.com/empty"))
        let client = OpenAPIDynamic(
            session: makeMockSession(body: Data(), for: url),
            maximumResponseBodyBytes: 0
        )

        let (_, data) = try await client.sendRequestWithResponseBody(method: .get, url: url)
        #expect(data == Data())
    }

    @Test("Collection accepts body exactly at limit")
    func exactBodyLimit() async throws {
        let url = try #require(URL(string: "https://example.com/exact"))
        let expected = Data("1234".utf8)
        let client = OpenAPIDynamic(
            session: makeMockSession(body: expected, for: url),
            maximumResponseBodyBytes: expected.count
        )

        let (_, data) = try await client.sendRequestWithResponseBody(method: .get, url: url)
        #expect(data == expected)
    }

    @Test("Collection rejects body one byte over limit")
    func bodyOverLimit() async throws {
        let url = try #require(URL(string: "https://example.com/over"))
        let client = OpenAPIDynamic(
            session: makeMockSession(body: Data("12345".utf8), for: url),
            maximumResponseBodyBytes: 4
        )

        await #expect(throws: (any Error).self) {
            _ = try await client.sendRequestWithResponseBody(method: .get, url: url)
        }
    }
    @Test("URLSession no-payload response is empty data")
    func emptyTransportResponseBody() async throws {
        let url = try #require(URL(string: "https://example.com/no-body"))
        let client = OpenAPIDynamic(session: makeMockSession(body: nil, for: url))

        let (_, data) = try await client.sendRequestWithResponseBody(method: .get, url: url)
        #expect(data == Data())
    }

    @Test("Middleware nil response body remains nil")
    func nilMiddlewareResponseBody() async throws {
        let capture = Capture()
        let client = OpenAPIDynamic(middleware: CapturingMiddleware(capture: capture))

        let (_, data) = try await client.sendRequestWithResponseBody(
            method: .get,
            url: #require(URL(string: "https://example.com/no-body"))
        )
        #expect(data == nil)
    }
}

private func makeMockSessionWithHandler(
    for url: URL,
    _ handler: @escaping (URLRequest) throws -> (HTTPURLResponse, Data?)
) -> URLSession {
    let cfg = URLSessionConfiguration.ephemeral
    cfg.protocolClasses = [MockURLProtocol.self]
    MockURLProtocol.register(handler, for: url)
    return URLSession(configuration: cfg)
}
