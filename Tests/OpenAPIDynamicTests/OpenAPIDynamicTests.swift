import Testing
@testable import OpenAPIDynamic
import Foundation
import HTTPTypes

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

@Test func testDecodingFailureObserverReceivesRequestAndResponseContext() async throws {
    struct ObservedUser: Decodable {
        let id: Int
    }

    let url = URL(string: "https://api.example.com/users/1")!
    let responseBody = Data(#"{"id":"not-an-int"}"#.utf8)
    let session = makeMockSession(body: responseBody)
    var context: DecodingFailureContext?
    let client = OpenAPIDynamic(
        session: session,
        decodingFailureObserver: {
            context = $0
        }
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

    #expect(context?.method == .get)
    #expect(context?.url == url)
    #expect(context?.operationID == "get-user")
    #expect(context?.response?.status == .ok)
    #expect(context?.responseBody == responseBody)
    #expect(context?.targetType == ObservedUser.self)
    #expect(context?.error is Swift.DecodingError)
}

private func makeMockSession(
    statusCode: Int = 200,
    body: Data?
) -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockURLProtocol.self]
    MockURLProtocol.requestHandler = { request in
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        return (response, body)
    }
    return URLSession(configuration: configuration)
}

private final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data?))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let requestHandler = Self.requestHandler else {
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
