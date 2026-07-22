// The Swift Programming Language
// https://docs.swift.org/swift-book

import Foundation
import HTTPTypes
import OpenAPIRuntime
import OpenAPIURLSession

/// A builder for constructing HTTP requests with flexible configuration.
public struct RequestBuilder {
    /// The HTTP method for the request.
    public var method: HTTPRequest.Method = .get

    /// The URL for the request.
    public var url: URL

    /// Headers to include in the request.
    public var headers: HTTPFields = [:]

    /// The request body data.
    public var body: Data?

    /// An optional operation ID for middleware identification.
    public var operationID: String?

    /// Creates a new request builder.
    public init() {
        self.url = URL(string: "https://example.com")!
    }

    /// Sets the HTTP method.
    /// - Parameter method: The HTTP method.
    /// - Returns: The builder for chaining.
    @discardableResult
    public mutating func setMethod(_ method: HTTPRequest.Method) -> Self {
        self.method = method
        return self
    }

    /// Sets the URL.
    /// - Parameter url: The URL for the request.
    /// - Returns: The builder for chaining.
    @discardableResult
    public mutating func setURL(_ url: URL) -> Self {
        self.url = url
        return self
    }

    /// Sets the URL.
    /// - Parameter url: The full URL string.
    /// - Returns: The builder for chaining.
    @discardableResult
    public mutating func setURL(_ url: String) -> Self {
        if let newURL = URL(string: url) {
            self.url = newURL
        }
        return self
    }

    /// Adds query parameters to the URL.
    /// - Parameter parameters: The query parameters.
    /// - Returns: The builder for chaining.
    @discardableResult
    public mutating func setQuery(_ parameters: [String: String]) -> Self {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
            return self
        }
        components.queryItems = parameters.map { URLQueryItem(name: $0.key, value: $0.value) }
        if let newURL = components.url {
            self.url = newURL
        }
        return self
    }

    /// Adds a header to the request.
    /// - Parameters:
    ///   - name: The header name.
    ///   - value: The header value.
    /// - Returns: The builder for chaining.
    @discardableResult
    public mutating func addHeader(_ name: HTTPField.Name, _ value: String) -> Self {
        headers[name] = value
        return self
    }

    /// Adds multiple headers to the request.
    /// - Parameter headers: The headers to add.
    /// - Returns: The builder for chaining.
    @discardableResult
    public mutating func addHeaders(_ headers: HTTPFields) -> Self {
        for field in headers {
            self.headers[field.name] = field.value
        }
        return self
    }

    /// Sets the request body.
    /// - Parameter body: The body data.
    /// - Returns: The builder for chaining.
    @discardableResult
    public mutating func setBody(_ body: Data?) -> Self {
        self.body = body
        return self
    }

    /// Sets the request body by encoding an Encodable value as JSON.
    /// - Parameters:
    ///   - body: The body to encode as JSON.
    ///   - encoder: The JSON encoder to use.
    /// - Returns: The builder for chaining.
    @discardableResult
    public mutating func setBody<T: Encodable>(_ body: T, encoder: JSONEncoder = .init()) throws -> Self {
        self.body = try encoder.encode(body)
        if headers[.contentType] == nil {
            headers[.contentType] = "application/json"
        }
        return self
    }

    /// Sets the operation ID for middleware.
    /// - Parameter operationID: The operation ID.
    /// - Returns: The builder for chaining.
    @discardableResult
    public mutating func setOperationID(_ operationID: String) -> Self {
        self.operationID = operationID
        return self
    }
}

/// Context passed to `OpenAPIDynamic` when response decoding fails.
public struct DecodingFailureContext {
    /// The HTTP method used by the request.
    public let method: HTTPRequest.Method

    /// The URL used by the request.
    public let url: URL

    /// The operation ID used by the middleware chain.
    public let operationID: String

    /// The HTTP response received before decoding.
    public let response: HTTPResponse?

    /// The response body that failed to decode.
    public let responseBody: Data?

    /// The expected Swift type.
    public let targetType: Any.Type

    /// The error thrown by JSON decoding or a custom decoder closure.
    public let error: any Error

    public init(
        method: HTTPRequest.Method,
        url: URL,
        operationID: String,
        response: HTTPResponse?,
        responseBody: Data?,
        targetType: Any.Type,
        error: any Error
    ) {
        self.method = method
        self.url = url
        self.operationID = operationID
        self.response = response
        self.responseBody = responseBody
        self.targetType = targetType
        self.error = error
    }
}

/// Called when `OpenAPIDynamic` receives a response but fails to decode it.
public typealias DecodingFailureHandler = @Sendable (DecodingFailureContext) -> Void

/// A dynamic HTTP client that can make arbitrary HTTP requests with middleware support.
/// This client is designed to work alongside static OpenAPI-generated clients,
/// sharing the same middleware chain for consistency.
public final class OpenAPIDynamic {

    /// The URLSession configuration used for requests.
    public let session: URLSession

    /// The middleware chain to apply to all requests.
    private let middleware: [any ClientMiddleware]

    /// Handles failures thrown while decoding a response body.
    private let decodingFailureHandler: DecodingFailureHandler?

    /// The maximum response body size collected by `Data`-returning APIs.
    public let maximumResponseBodyBytes: Int

    /// The operation ID used by overloads that do not accept a request builder.
    public let defaultOperationID: String

    /// Creates a new dynamic client.
    /// - Parameters:
    ///   - session: The URLSession to use for HTTP requests. Defaults to `.shared`.
    ///   - middleware: The middleware chain to apply to requests. Defaults to empty.
    ///   - decodingFailureHandler: Called when response decoding fails. Defaults to `nil`.
    ///   - maximumResponseBodyBytes: Maximum bytes collected by `Data`-returning APIs.
    ///   - defaultOperationID: Operation ID used by overloads without a request builder.
    public init(
        session: URLSession = .shared,
        middleware: [any ClientMiddleware] = [],
        decodingFailureHandler: DecodingFailureHandler? = nil,
        maximumResponseBodyBytes: Int = 10 * 1024 * 1024,
        defaultOperationID: String = "dynamic-request"
    ) {
        precondition(maximumResponseBodyBytes >= 0, "maximumResponseBodyBytes must not be negative")
        self.session = session
        self.middleware = middleware
        self.decodingFailureHandler = decodingFailureHandler
        self.maximumResponseBodyBytes = maximumResponseBodyBytes
        self.defaultOperationID = defaultOperationID
    }

    /// Creates a new dynamic client with middleware.
    public convenience init(
        session: URLSession = .shared,
        decodingFailureHandler: DecodingFailureHandler? = nil,
        maximumResponseBodyBytes: Int = 10 * 1024 * 1024,
        defaultOperationID: String = "dynamic-request",
        middleware: any ClientMiddleware...
    ) {
        self.init(
            session: session,
            middleware: middleware,
            decodingFailureHandler: decodingFailureHandler,
            maximumResponseBodyBytes: maximumResponseBodyBytes,
            defaultOperationID: defaultOperationID
        )
    }

    private struct DecodingMetadata {
        let method: HTTPRequest.Method
        let url: URL
        let operationID: String

        init(method: HTTPRequest.Method, url: URL, operationID: String) {
            self.method = method
            self.url = url
            self.operationID = operationID
        }

        init(_ builder: RequestBuilder, defaultOperationID: String) {
            self.init(
                method: builder.method,
                url: builder.url,
                operationID: builder.operationID ?? defaultOperationID
            )
        }
    }

    private static func decompose(_ url: URL) throws -> (baseURL: URL, path: String) {
        guard
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            components.scheme != nil,
            components.host != nil
        else {
            throw InvalidRequestURLError(url: url)
        }

        let path = components.percentEncodedPath + (components.percentEncodedQuery.map { "?" + $0 } ?? "")
        components.percentEncodedPath = ""
        components.percentEncodedQuery = nil
        components.fragment = nil
        guard let baseURL = components.url else {
            throw InvalidRequestURLError(url: url)
        }
        return (baseURL, path)
    }

    private func observeDecoding<T>(
        targetType: Any.Type,
        metadata: DecodingMetadata,
        response: HTTPResponse?,
        responseBody: Data?,
        _ decode: () throws -> T
    ) throws -> T {
        do {
            return try decode()
        } catch {
            decodingFailureHandler?(
                DecodingFailureContext(
                    method: metadata.method,
                    url: metadata.url,
                    operationID: metadata.operationID,
                    response: response,
                    responseBody: responseBody,
                    targetType: targetType,
                    error: error
                )
            )
            throw error
        }
    }

    /// Performs an HTTP request with the configured middleware.
    /// - Parameters:
    ///   - method: The HTTP method.
    ///   - url: The URL for the request.
    ///   - headers: Additional headers to include.
    ///   - body: The request body data.
    /// - Returns: The HTTP response.
    /// - Throws: Any error that occurs during the request or middleware processing.
    public func sendRequest(
        method: HTTPRequest.Method,
        url: URL,
        headers: HTTPFields = [:],
        body: Data? = nil
    ) async throws -> HTTPResponse {
        let (response, _) = try await sendRequestWithResponseBody(
            method: method,
            url: url,
            headers: headers,
            body: body
        )
        return response
    }

    /// Performs an HTTP request with the configured middleware and an Encodable body.
    /// - Parameters:
    ///   - method: The HTTP method.
    ///   - url: The URL for the request.
    ///   - headers: Additional headers to include.
    ///   - body: The request body to encode as JSON.
    ///   - encoder: The JSON encoder to use.
    /// - Returns: The HTTP response.
    /// - Throws: Any error that occurs during the request, encoding, or middleware processing.
    public func sendRequest<T: Encodable>(
        method: HTTPRequest.Method,
        url: URL,
        headers: HTTPFields = [:],
        body: T,
        encoder: JSONEncoder = .init()
    ) async throws -> HTTPResponse {
        let data = try encoder.encode(body)
        var headers = headers
        if headers[.contentType] == nil {
            headers[.contentType] = "application/json"
        }
        return try await sendRequest(method: method, url: url, headers: headers, body: data)
    }

    public func sendRequestStreaming(
        method: HTTPRequest.Method,
        url: URL,
        headers: HTTPFields = [:],
        body: Data? = nil,
        operationID: String? = nil
    ) async throws -> (HTTPResponse, HTTPBody?) {
        let (baseURL, path) = try Self.decompose(url)
        let request = HTTPRequest(method: method, scheme: nil, authority: nil, path: path, headerFields: headers)
        return try await MiddlewareTransport(session: session, middleware: middleware).send(
            request,
            body: body.map(HTTPBody.init),
            baseURL: baseURL,
            operationID: operationID ?? defaultOperationID
        )
    }

    /// Performs an HTTP request and collects its response body up to the configured limit.
    public func sendRequestWithResponseBody(
        method: HTTPRequest.Method,
        url: URL,
        headers: HTTPFields = [:],
        body: Data? = nil
    ) async throws -> (HTTPResponse, Data?) {
        let (response, responseBody) = try await sendRequestStreaming(
            method: method,
            url: url,
            headers: headers,
            body: body
        )
        let responseData: Data?
        if let responseBody {
            responseData = try await Data(collecting: responseBody, upTo: maximumResponseBodyBytes)
        } else {
            responseData = nil
        }
        return (response, responseData)
    }

    /// Performs an HTTP request with the configured middleware and an Encodable body, returning both response and body.
    /// - Parameters:
    ///   - method: The HTTP method.
    ///   - url: The URL for the request.
    ///   - headers: Additional headers to include.
    ///   - body: The request body to encode as JSON.
    ///   - encoder: The JSON encoder to use.
    /// - Returns: A tuple containing the HTTP response and optional body data.
    /// - Throws: Any error that occurs during the request, encoding, or middleware processing.
    public func sendRequestWithResponseBody<T: Encodable>(
        method: HTTPRequest.Method,
        url: URL,
        headers: HTTPFields = [:],
        body: T,
        encoder: JSONEncoder = .init()
    ) async throws -> (HTTPResponse, Data?) {
        let data = try encoder.encode(body)
        var headers = headers
        if headers[.contentType] == nil {
            headers[.contentType] = "application/json"
        }
        return try await sendRequestWithResponseBody(method: method, url: url, headers: headers, body: data)
    }

    /// Performs an HTTP request and validates that the response status is successful (2xx).
    /// - Parameters:
    ///   - method: The HTTP method.
    ///   - url: The URL for the request.
    ///   - headers: Additional headers to include.
    ///   - body: The request body data.
    /// - Returns: The HTTP response.
    /// - Throws: `HTTPError` if the response status is not successful, or any other request error.
    public func sendRequestAndValidate(
        method: HTTPRequest.Method,
        url: URL,
        headers: HTTPFields = [:],
        body: Data? = nil
    ) async throws -> HTTPResponse {
        let (response, data) = try await sendRequestWithResponseBody(method: method, url: url, headers: headers, body: body)
        try response.validateSuccess(with: data)
        return response
    }

    /// Performs an HTTP request with an Encodable body and validates that the response status is successful (2xx).
    /// - Parameters:
    ///   - method: The HTTP method.
    ///   - url: The URL for the request.
    ///   - headers: Additional headers to include.
    ///   - body: The request body to encode as JSON.
    ///   - encoder: The JSON encoder to use.
    /// - Returns: The HTTP response.
    /// - Throws: `HTTPError` if the response status is not successful, or any other request/encoding error.
    public func sendRequestAndValidate<T: Encodable>(
        method: HTTPRequest.Method,
        url: URL,
        headers: HTTPFields = [:],
        body: T,
        encoder: JSONEncoder = .init()
    ) async throws -> HTTPResponse {
        let data = try encoder.encode(body)
        var headers = headers
        if headers[.contentType] == nil {
            headers[.contentType] = "application/json"
        }
        return try await sendRequestAndValidate(method: method, url: url, headers: headers, body: data)
    }

    /// Performs an HTTP request with a builder and validates that the response status is successful (2xx).
    /// - Parameter builder: A closure that configures the request.
    /// - Returns: The HTTP response.
    /// - Throws: `HTTPError` if the response status is not successful, or any other request error.
    public func sendRequestAndValidate(
        _ builder: (inout RequestBuilder) -> Void
    ) async throws -> HTTPResponse {
        let (response, data) = try await sendRequestWithResponseBody(builder)
        try response.validateSuccess(with: data)
        return response
    }

    /// Performs a streaming HTTP request configured by a request builder.
    public func sendRequestStreaming(
        _ builder: (inout RequestBuilder) -> Void
    ) async throws -> (HTTPResponse, HTTPBody?) {
        var requestBuilder = RequestBuilder()
        builder(&requestBuilder)
        return try await sendRequestStreaming(
            method: requestBuilder.method,
            url: requestBuilder.url,
            headers: requestBuilder.headers,
            body: requestBuilder.body,
            operationID: requestBuilder.operationID
        )
    }

    /// Performs an HTTP request configured by a builder and collects its response body up to the configured limit.
    public func sendRequestWithResponseBody(
        _ builder: (inout RequestBuilder) -> Void
    ) async throws -> (HTTPResponse, Data?) {
        let (response, responseBody) = try await sendRequestStreaming(builder)
        let responseData: Data?
        if let responseBody {
            responseData = try await Data(collecting: responseBody, upTo: maximumResponseBodyBytes)
        } else {
            responseData = nil
        }
        return (response, responseData)
    }
}

/// The supplied request URL cannot be represented as an absolute HTTP request.
public struct InvalidRequestURLError: Error, LocalizedError, Equatable {
    public let url: URL

    public var errorDescription: String? {
        "Invalid absolute request URL: \(url.absoluteString)"
    }
}

/// Errors that can occur during HTTP requests.
public enum HTTPError: Error, LocalizedError, Equatable {
    /// The HTTP response status indicates an error.
    case statusError(HTTPResponse, body: Data?)

    /// A description of the error.
    public var errorDescription: String? {
        switch self {
        case .statusError(let response, _):
            return "HTTP \(response.status.code) \(response.status.reasonPhrase)"
        }
    }

    public static func == (lhs: HTTPError, rhs: HTTPError) -> Bool {
        switch (lhs, rhs) {
        case (.statusError(let lhsResponse, _), .statusError(let rhsResponse, _)):
            return lhsResponse.status == rhsResponse.status
        }
    }
}

/// Errors that can occur during decoding.
public enum DecodingError: Error, LocalizedError {
    /// No data was available to decode.
    case noData

    /// A description of the error.
    public var errorDescription: String? {
        switch self {
        case .noData:
            return "No response data available for decoding"
        }
    }
}

/// Errors for unexpected HTTP statuses.
public enum UnexpectedStatusError: Error, LocalizedError {
    /// The response status was not expected.
    case unexpectedStatus(HTTPResponse.Status)

    /// A description of the error.
    public var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let status):
            return "Unexpected HTTP status: \(status.code)"
        }
    }
}

/// Helper function for safe decoding of response data.
public func decode<T: Decodable>(
    _ type: T.Type,
    from data: Data?,
    using decoder: JSONDecoder = .init()
) throws -> T {
    guard let data = data else {
        throw DecodingError.noData
    }
    return try decoder.decode(type, from: data)
}

extension HTTPResponse {
    /// Validates that the response status code indicates success (2xx).
    /// - Throws: `HTTPError.statusError` if the status is not successful.
    public func validateSuccess(with body: Data? = nil) throws {
        guard status.kind == .successful else {
            throw HTTPError.statusError(self, body: body)
        }
    }
}

// MARK: - Decoding Extensions

extension OpenAPIDynamic {
    /// Performs an HTTP request and decodes the response body to the specified type.
    /// - Parameters:
    ///   - method: The HTTP method.
    ///   - url: The URL for the request.
    ///   - headers: Additional headers to include.
    ///   - body: The request body data.
    ///   - decoder: The JSON decoder to use.
    /// - Returns: The decoded response body.
    /// - Throws: Any error that occurs during the request, or decoding errors.
    public func sendRequest<T: Decodable>(
        method: HTTPRequest.Method,
        url: URL,
        headers: HTTPFields = [:],
        body: Data? = nil,
        decoder: JSONDecoder = .init()
    ) async throws -> T {
        var headers = headers
        if headers[.accept] == nil {
            headers[.accept] = "application/json"
        }
        let (response, data) = try await sendRequestWithResponseBody(method: method, url: url, headers: headers, body: body)
        return try observeDecoding(
            targetType: T.self,
            metadata: DecodingMetadata(method: method, url: url, operationID: defaultOperationID),
            response: response,
            responseBody: data
        ) {
            try decoder.decode(T.self, from: data ?? Data())
        }
    }

    /// Performs an HTTP request with a builder and decodes the response body to the specified type.
    /// - Parameters:
    ///   - builder: A closure that configures the request.
    ///   - decoder: The JSON decoder to use.
    /// - Returns: The decoded response body.
    /// - Throws: Any error that occurs during the request, or decoding errors.
    public func sendRequest<T: Decodable>(
        _ builder: (inout RequestBuilder) -> Void,
        decoder: JSONDecoder = .init()
    ) async throws -> T {
        var requestBuilder = RequestBuilder()
        builder(&requestBuilder)
        if requestBuilder.headers[.accept] == nil {
            requestBuilder.headers[.accept] = "application/json"
        }
        let metadata = DecodingMetadata(requestBuilder, defaultOperationID: defaultOperationID)
        let (response, data) = try await sendRequestWithResponseBody {
            $0.method = requestBuilder.method
            $0.url = requestBuilder.url
            $0.headers = requestBuilder.headers
            $0.body = requestBuilder.body
            $0.operationID = requestBuilder.operationID
        }
        return try observeDecoding(
            targetType: T.self,
            metadata: metadata,
            response: response,
            responseBody: data
        ) {
            try decoder.decode(T.self, from: data ?? Data())
        }
    }

    /// Performs an HTTP request, validates success, and decodes the response body to the specified type.
    /// - Parameters:
    ///   - method: The HTTP method.
    ///   - url: The URL for the request.
    ///   - headers: Additional headers to include.
    ///   - body: The request body data.
    ///   - decoder: The JSON decoder to use.
    /// - Returns: The decoded response body.
    /// - Throws: `HTTPError` if the response status is not successful, or any other request/decoding error.
    public func sendRequestAndValidate<T: Decodable>(
        method: HTTPRequest.Method,
        url: URL,
        headers: HTTPFields = [:],
        body: Data? = nil,
        decoder: JSONDecoder = .init()
    ) async throws -> T {
        var headers = headers
        if headers[.accept] == nil {
            headers[.accept] = "application/json"
        }
        let (response, data) = try await sendRequestWithResponseBody(method: method, url: url, headers: headers, body: body)
        try response.validateSuccess(with: data)
        return try observeDecoding(
            targetType: T.self,
            metadata: DecodingMetadata(method: method, url: url, operationID: defaultOperationID),
            response: response,
            responseBody: data
        ) {
            try decoder.decode(T.self, from: data ?? Data())
        }
    }

    /// Performs an HTTP request with a builder, validates success, and decodes the response body to the specified type.
    /// - Parameters:
    ///   - builder: A closure that configures the request.
    ///   - decoder: The JSON decoder to use.
    /// - Returns: The decoded response body.
    /// - Throws: `HTTPError` if the response status is not successful, or any other request/decoding error.
    public func sendRequestAndValidate<T: Decodable>(
        _ builder: (inout RequestBuilder) -> Void,
        decoder: JSONDecoder = .init()
    ) async throws -> T {
        var requestBuilder = RequestBuilder()
        builder(&requestBuilder)
        if requestBuilder.headers[.accept] == nil {
            requestBuilder.headers[.accept] = "application/json"
        }
        let metadata = DecodingMetadata(requestBuilder, defaultOperationID: defaultOperationID)
        let (response, data) = try await sendRequestWithResponseBody {
            $0.method = requestBuilder.method
            $0.url = requestBuilder.url
            $0.headers = requestBuilder.headers
            $0.body = requestBuilder.body
            $0.operationID = requestBuilder.operationID
        }
        try response.validateSuccess(with: data)
        return try observeDecoding(
            targetType: T.self,
            metadata: metadata,
            response: response,
            responseBody: data
        ) {
            try decoder.decode(T.self, from: data ?? Data())
        }
    }

    /// Performs an HTTP request and returns the response with the decoded body.
    /// - Parameters:
    ///   - method: The HTTP method.
    ///   - url: The URL for the request.
    ///   - headers: Additional headers to include.
    ///   - body: The request body data.
    ///   - decoder: The JSON decoder to use.
    /// - Returns: A tuple containing the HTTP response and optional decoded body.
    /// - Throws: Any error that occurs during the request, or decoding errors.
    public func sendRequestWithResponseBody<T: Decodable>(
        method: HTTPRequest.Method,
        url: URL,
        headers: HTTPFields = [:],
        body: Data? = nil,
        decoder: JSONDecoder = .init()
    ) async throws -> (HTTPResponse, T?) {
        var headers = headers
        if headers[.accept] == nil {
            headers[.accept] = "application/json"
        }
        let (response, data) = try await sendRequestWithResponseBody(method: method, url: url, headers: headers, body: body)
        let decoded = try data.map { body in
            try observeDecoding(
                targetType: T.self,
                metadata: DecodingMetadata(method: method, url: url, operationID: defaultOperationID),
                response: response,
                responseBody: data
            ) {
                try decoder.decode(T.self, from: body)
            }
        }
        return (response, decoded)
    }

    /// Performs an HTTP request with a builder and returns the response with the decoded body.
    /// - Parameters:
    ///   - builder: A closure that configures the request.
    ///   - decoder: The JSON decoder to use.
    /// - Returns: A tuple containing the HTTP response and optional decoded body.
    /// - Throws: Any error that occurs during the request, or decoding errors.
    public func sendRequestWithResponseBody<T: Decodable>(
        _ builder: (inout RequestBuilder) -> Void,
        decoder: JSONDecoder = .init()
    ) async throws -> (HTTPResponse, T?) {
        var requestBuilder = RequestBuilder()
        builder(&requestBuilder)
        if requestBuilder.headers[.accept] == nil {
            requestBuilder.headers[.accept] = "application/json"
        }
        let metadata = DecodingMetadata(requestBuilder, defaultOperationID: defaultOperationID)
        let (response, data) = try await sendRequestWithResponseBody {
            $0.method = requestBuilder.method
            $0.url = requestBuilder.url
            $0.headers = requestBuilder.headers
            $0.body = requestBuilder.body
            $0.operationID = requestBuilder.operationID
        }
        let decoded = try data.map { body in
            try observeDecoding(
                targetType: T.self,
                metadata: metadata,
                response: response,
                responseBody: data
            ) {
                try decoder.decode(T.self, from: body)
            }
        }
        return (response, decoded)
    }

    /// Performs an HTTP request with status-specific decoding using a map of decoders.
    /// - Parameters:
    ///   - method: The HTTP method.
    ///   - url: The URL for the request.
    ///   - headers: Additional headers to include.
    ///   - body: The request body data.
    ///   - decoders: A map from HTTP status to decoding closure.
    /// - Returns: The decoded result.
    /// - Throws: `UnexpectedStatusError` if the status is not in the map, or any request/decoding error.
    public func sendRequestWithStatusDecoding<T>(
        method: HTTPRequest.Method,
        url: URL,
        headers: HTTPFields = [:],
        body: Data? = nil,
        decoders: [HTTPResponse.Status: (Data?) throws -> T]
    ) async throws -> T {
        let (response, data) = try await sendRequestWithResponseBody(method: method, url: url, headers: headers, body: body)
        guard let decoder = decoders[response.status] else {
            throw UnexpectedStatusError.unexpectedStatus(response.status)
        }
        return try observeDecoding(
            targetType: T.self,
            metadata: DecodingMetadata(method: method, url: url, operationID: defaultOperationID),
            response: response,
            responseBody: data
        ) {
            try decoder(data)
        }
    }

    /// Performs an HTTP request with a builder and status-specific decoding using a map of decoders.
    /// - Parameters:
    ///   - builder: A closure that configures the request.
    ///   - decoders: A map from HTTP status to decoding closure.
    /// - Returns: The decoded result.
    /// - Throws: `UnexpectedStatusError` if the status is not in the map, or any request/decoding error.
    public func sendRequestWithStatusDecoding<T>(
        _ builder: (inout RequestBuilder) -> Void,
        decoders: [HTTPResponse.Status: (Data?) throws -> T]
    ) async throws -> T {
        var requestBuilder = RequestBuilder()
        builder(&requestBuilder)
        let metadata = DecodingMetadata(requestBuilder, defaultOperationID: defaultOperationID)
        let (response, data) = try await sendRequestWithResponseBody {
            $0.method = requestBuilder.method
            $0.url = requestBuilder.url
            $0.headers = requestBuilder.headers
            $0.body = requestBuilder.body
            $0.operationID = requestBuilder.operationID
        }
        guard let decoder = decoders[response.status] else {
            throw UnexpectedStatusError.unexpectedStatus(response.status)
        }
        return try observeDecoding(
            targetType: T.self,
            metadata: metadata,
            response: response,
            responseBody: data
        ) {
            try decoder(data)
        }
    }

    /// Performs an HTTP request with type-based decoding using a map of types.
    /// - Parameters:
    ///   - method: The HTTP method.
    ///   - url: The URL for the request.
    ///   - headers: Additional headers to include.
    ///   - body: The request body data.
    ///   - typeMap: A map from HTTP status code to decodable type.
    ///   - decoder: The JSON decoder to use.
    /// - Returns: The decoded result as `Decodable`.
    /// - Throws: `UnexpectedStatusError` if the status code is not in the map, or any request/decoding error.
    public func sendRequestWithTypeDecoding(
        method: HTTPRequest.Method,
        url: URL,
        headers: HTTPFields = [:],
        body: Data? = nil,
        typeMap: [Int: Decodable.Type],
        decoder: JSONDecoder = .init()
    ) async throws -> Decodable {
        var headers = headers
        if headers[.accept] == nil {
            headers[.accept] = "application/json"
        }
        let (response, data) = try await sendRequestWithResponseBody(method: method, url: url, headers: headers, body: body)
        guard let type = typeMap[response.status.code] else {
            throw UnexpectedStatusError.unexpectedStatus(response.status)
        }
        return try observeDecoding(
            targetType: type,
            metadata: DecodingMetadata(method: method, url: url, operationID: defaultOperationID),
            response: response,
            responseBody: data
        ) {
            try decode(type, from: data, using: decoder)
        }
    }

    /// Performs an HTTP request with a builder and type-based decoding using a map of types.
    /// - Parameters:
    ///   - builder: A closure that configures the request.
    ///   - typeMap: A map from HTTP status code to decodable type.
    ///   - decoder: The JSON decoder to use.
    /// - Returns: The decoded result as `Decodable`.
    /// - Throws: `UnexpectedStatusError` if the status code is not in the map, or any request/decoding error.
    public func sendRequestWithTypeDecoding(
        _ builder: (inout RequestBuilder) -> Void,
        typeMap: [Int: Decodable.Type],
        decoder: JSONDecoder = .init()
    ) async throws -> Decodable {
        var requestBuilder = RequestBuilder()
        builder(&requestBuilder)
        if requestBuilder.headers[.accept] == nil {
            requestBuilder.headers[.accept] = "application/json"
        }
        let metadata = DecodingMetadata(requestBuilder, defaultOperationID: defaultOperationID)
        let (response, data) = try await sendRequestWithResponseBody {
            $0.method = requestBuilder.method
            $0.url = requestBuilder.url
            $0.headers = requestBuilder.headers
            $0.body = requestBuilder.body
            $0.operationID = requestBuilder.operationID
        }
        guard let type = typeMap[response.status.code] else {
            throw UnexpectedStatusError.unexpectedStatus(response.status)
        }
        return try observeDecoding(
            targetType: type,
            metadata: metadata,
            response: response,
            responseBody: data
        ) {
            try decode(type, from: data, using: decoder)
        }
    }

    /// Performs an HTTP request with flexible decoding using a custom closure.
    /// - Parameters:
    ///   - method: The HTTP method.
    ///   - url: The URL for the request.
    ///   - headers: Additional headers to include.
    ///   - body: The request body data.
    ///   - decoder: A closure that takes the response and data and returns the decoded result.
    /// - Returns: The decoded result.
    /// - Throws: Any error from the request or the decoder closure.
    public func sendRequestWithFlexibleDecoding<T>(
        method: HTTPRequest.Method,
        url: URL,
        headers: HTTPFields = [:],
        body: Data? = nil,
        decoder: (HTTPResponse, Data?) throws -> T
    ) async throws -> T {
        let (response, data) = try await sendRequestWithResponseBody(method: method, url: url, headers: headers, body: body)
        return try observeDecoding(
            targetType: T.self,
            metadata: DecodingMetadata(method: method, url: url, operationID: defaultOperationID),
            response: response,
            responseBody: data
        ) {
            try decoder(response, data)
        }
    }

    /// Performs an HTTP request with a builder and flexible decoding using a custom closure.
    /// - Parameters:
    ///   - builder: A closure that configures the request.
    ///   - decoder: A closure that takes the response and data and returns the decoded result.
    /// - Returns: The decoded result.
    /// - Throws: Any error from the request or the decoder closure.
    public func sendRequestWithFlexibleDecoding<T>(
        _ builder: (inout RequestBuilder) -> Void,
        decoder: (HTTPResponse, Data?) throws -> T
    ) async throws -> T {
        var requestBuilder = RequestBuilder()
        builder(&requestBuilder)
        let metadata = DecodingMetadata(requestBuilder, defaultOperationID: defaultOperationID)
        let (response, data) = try await sendRequestWithResponseBody {
            $0.method = requestBuilder.method
            $0.url = requestBuilder.url
            $0.headers = requestBuilder.headers
            $0.body = requestBuilder.body
            $0.operationID = requestBuilder.operationID
        }
        return try observeDecoding(
            targetType: T.self,
            metadata: metadata,
            response: response,
            responseBody: data
        ) {
            try decoder(response, data)
        }
    }
}

/// A transport that applies middleware to URLSession requests.
private struct MiddlewareTransport: ClientTransport {
    let session: URLSession
    let middleware: [any ClientMiddleware]

    func send(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String
    ) async throws -> (HTTPResponse, HTTPBody?) {
        let transport = URLSessionTransport(configuration: .init(session: session))
        @Sendable func clientError(
            causeDescription: String,
            underlyingError: any Error
        ) -> ClientError {
            ClientError(
                operationID: operationID,
                operationInput: request,
                request: request,
                requestBody: body,
                baseURL: baseURL,
                causeDescription: causeDescription,
                underlyingError: underlyingError
            )
        }

        var next: @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?) = {
            request, body, baseURL in
            do {
                return try await transport.send(request, body: body, baseURL: baseURL, operationID: operationID)
            } catch let error as ClientError {
                throw error
            } catch {
                throw clientError(causeDescription: "Transport threw an error.", underlyingError: error)
            }
        }

        for middleware in middleware.reversed() {
            let downstream = next
            next = { request, body, baseURL in
                do {
                    return try await middleware.intercept(
                        request,
                        body: body,
                        baseURL: baseURL,
                        operationID: operationID,
                        next: downstream
                    )
                } catch let error as ClientError {
                    throw error
                } catch {
                    throw clientError(
                        causeDescription: "Middleware of type '\(type(of: middleware))' threw an error.",
                        underlyingError: error
                    )
                }
            }
        }

        return try await next(request, body, baseURL)
    }
}
