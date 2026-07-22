import Testing
import Foundation
import HTTPTypes
@testable import OpenAPIDynamic

@Suite(
    "Integration Tests",
    .enabled(
        if: TestConfiguration.areLiveNetworkTestsEnabled,
        "Set OPENAPI_DYNAMIC_ENABLE_LIVE_TESTS=1 to run live network integration tests"
    )
)
struct OpenAPIDynamicIntegrationTests {

    let client = OpenAPIDynamic()

    @Test("GET request to JSONPlaceholder returns user data")
    func testGetUser() async throws {
        let url = URL(string: "https://jsonplaceholder.typicode.com/users/1")!
        let user: User = try await client.sendRequest(method: .get, url: url)

        #expect(user.id == 1)
        #expect(user.name == "Leanne Graham")
        #expect(user.email == "Sincere@april.biz")
    }

    @Test("GET request with builder returns user data")
    func testGetUserWithBuilder() async throws {
        let user: User = try await client.sendRequest { builder in
            builder.setMethod(.get)
            builder.setURL("https://jsonplaceholder.typicode.com/users/1")
        }

        #expect(user.id == 1)
        #expect(user.name == "Leanne Graham")
    }

    @Test("POST request with Encodable body creates new post")
    func testCreatePost() async throws {
        let newPost = Post(id: nil, userId: 1, title: "Test Post", body: "This is a test post")
        let url = URL(string: "https://jsonplaceholder.typicode.com/posts")!

        let (response, data) = try await client.sendRequestWithResponseBody(method: .post, url: url, body: newPost)
        #expect(response.status.kind == .successful)

        let createdPost = try decode(Post.self, from: data)
        #expect(createdPost.userId == 1)
        #expect(createdPost.title == "Test Post")
        #expect(createdPost.body == "This is a test post")
        #expect(createdPost.id != nil) // JSONPlaceholder assigns an ID
    }

    @Test("PUT request with Encodable body updates post")
    func testUpdatePost() async throws {
        let updatedPost = Post(id: 1, userId: 1, title: "Updated Title", body: "Updated body")
        let url = URL(string: "https://jsonplaceholder.typicode.com/posts/1")!

        let (response, data) = try await client.sendRequestWithResponseBody(method: .put, url: url, body: updatedPost)
        #expect(response.status.kind == .successful)

        let result = try decode(Post.self, from: data)
        #expect(result.id == 1)
        #expect(result.title == "Updated Title")
        #expect(result.body == "Updated body")
    }

    @Test("DELETE request validates success")
    func testDeletePost() async throws {
        let url = URL(string: "https://jsonplaceholder.typicode.com/posts/1")!

        let response = try await client.sendRequestAndValidate(method: .delete, url: url)

        #expect(response.status.kind == .successful)
    }

    @Test("GET request with response body returns both response and data")
    func testGetWithResponseBody() async throws {
        let url = URL(string: "https://jsonplaceholder.typicode.com/users/1")!

        let (response, user): (HTTPResponse, User?) = try await client.sendRequestWithResponseBody(method: .get, url: url)

        #expect(response.status.kind == .successful)
        #expect(user != nil)
        #expect(user?.id == 1)
    }

    @Test("GET request without Accept header override uses default JSON Accept")
    func testAcceptHeaderAutoSet() async throws {
        let url = URL(string: "https://httpbin.org/get")!

        let response: HttpBinResponse = try await client.sendRequest(method: .get, url: url)

        #expect(response.headers["Accept"] == "application/json")
    }

    @Test("GET request with explicit Accept header override uses provided header")
    func testAcceptHeaderOverride() async throws {
        let url = URL(string: "https://httpbin.org/get")!
        var headers = HTTPFields()
        headers[.accept] = "text/plain"

        let response: HttpBinResponse = try await client.sendRequest(method: .get, url: url, headers: headers)

        #expect(response.headers["Accept"] == "text/plain")
    }

    @Test("POST request with Encodable body auto-sets Content-Type")
    func testContentTypeAutoSet() async throws {
        let testData = ["key": "value"]
        let url = URL(string: "https://httpbin.org/post")!

        let (response, data) = try await client.sendRequestWithResponseBody(method: .post, url: url, body: testData)
        #expect(response.status.kind == .successful)

        let httpBinResponse = try decode(HttpBinResponse.self, from: data)
        #expect(httpBinResponse.headers["Content-Type"] == "application/json")
        #expect(httpBinResponse.json == testData)
    }

    @Test("POST request with explicit Content-Type override uses provided header")
    func testContentTypeOverride() async throws {
        let testData = ["key": "value"]
        let url = URL(string: "https://httpbin.org/post")!
        var headers = HTTPFields()
        headers[.contentType] = "application/x-www-form-urlencoded"

        let (response, data) = try await client.sendRequestWithResponseBody(method: .post, url: url, headers: headers, body: testData)
        #expect(response.status.kind == .successful)

        let httpBinResponse = try decode(HttpBinResponse.self, from: data)
        #expect(httpBinResponse.headers["Content-Type"] == "application/x-www-form-urlencoded")
    }

    @Test("GET request for raw response does not set Accept header")
    func testNoAcceptHeaderForRawResponse() async throws {
        let url = URL(string: "https://httpbin.org/get")!

        // Make a raw request (no Accept header should be set to application/json)
        let (response, data) = try await client.sendRequestWithResponseBody(method: .get, url: url)
        #expect(response.status.kind == .successful)

        let httpBinResponse = try decode(HttpBinResponse.self, from: data)
        // HttpBin echoes back the request headers, so we can check if Accept was sent
        // For raw requests, our library should not set Accept to application/json
        // URLSession might set a default Accept header like */*
        #expect(httpBinResponse.headers["Accept"] != "application/json")
    }

    @Test("GET request with validation succeeds for 200 status")
    func testValidationSuccess() async throws {
        let url = URL(string: "https://httpbin.org/status/200")!

        let response = try await client.sendRequestAndValidate(method: .get, url: url)

        #expect(response.status == .ok)
    }

    @Test("GET request with validation fails for 404 status")
    func testValidationFailure() async throws {
        let url = URL(string: "https://httpbin.org/status/404")!

        do {
            let _ = try await client.sendRequestAndValidate(method: .get, url: url)
            Issue.record("Expected HTTPError but request succeeded")
        } catch let error as HTTPError {
            #expect(error.localizedDescription.contains("404"))
        } catch {
            Issue.record("Expected HTTPError but got different error: \(error)")
        }
    }

    @Test("Status-specific decoding handles different response types")
    func testStatusDecoding() async throws {
        let url = URL(string: "https://httpbin.org/status/200")!

        let result: String = try await client.sendRequestWithStatusDecoding(
            method: .get,
            url: url,
            decoders: [
                .ok: { _ in "Success" },
                .notFound: { _ in "Not Found" }
            ]
        )

        #expect(result == "Success")
    }

    @Test("Type-based decoding handles different status codes")
    func testTypeDecoding() async throws {
        let url = URL(string: "https://httpbin.org/get")!

        let result = try await client.sendRequestWithTypeDecoding(
            method: .get,
            url: url,
            typeMap: [
                200: HttpBinResponse.self
            ]
        )

        #expect(result is HttpBinResponse)
    }

    @Test("Flexible decoding allows custom processing")
    func testFlexibleDecoding() async throws {
        let url = URL(string: "https://httpbin.org/get")!

        let result: String = try await client.sendRequestWithFlexibleDecoding(method: .get, url: url) { response, data in
            guard response.status.kind == .successful else {
                throw HTTPError.statusError(response, body: data)
            }
            return "Processed: \(data?.count ?? 0) bytes"
        }

        #expect(result.hasPrefix("Processed:"))
    }

    @Test("Builder pattern works with all features")
    func testBuilderPattern() async throws {
        let postData = ["message": "Hello from builder"]
        let url = URL(string: "https://httpbin.org/post")!
        let jsonData = try JSONEncoder().encode(postData)

        let httpBinResponse: HttpBinResponse = try await client.sendRequest { builder in
            builder.setMethod(.post)
            builder.setURL(url)
            builder.addHeader(.userAgent, "OpenAPIDynamicTest/1.0")
            builder.setBody(jsonData as Data?)
            builder.addHeader(.contentType, "application/json")
        }

        #expect(httpBinResponse.headers["User-Agent"] == "OpenAPIDynamicTest/1.0")
        #expect(httpBinResponse.json == postData)
        #expect(httpBinResponse.headers["Accept"] == "application/json")
        #expect(httpBinResponse.headers["Content-Type"] == "application/json")
    }

    @Test("Query parameters are properly encoded")
    func testQueryParameters() async throws {
        let url = URL(string: "https://httpbin.org/get")!

        let response: HttpBinResponse = try await client.sendRequest { builder in
            builder.setMethod(.get)
            builder.setURL(url)
            builder.setQuery(["param1": "value1", "param2": "value 2"])
        }

        #expect(response.args["param1"] == "value1")
        #expect(response.args["param2"] == "value 2")
    }
}