import Testing
@testable import OpenAPIDynamic
import Foundation
import HTTPTypes

@Test func testClientInitialization() async throws {
    let client = OpenAPIDynamic()
    // Client initializes successfully with default configuration
    #expect(client.session != nil)
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

    let decoded = try decode(TestModel.self, from: data) as! TestModel
    #expect(decoded == TestModel(value: "test"))

    #expect(throws: DecodingError.noData) {
        try decode(TestModel.self, from: nil)
    }
}

// Integration test with a mock server would require additional setup
// For now, we test the client structure and basic functionality
