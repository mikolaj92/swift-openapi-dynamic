import Foundation
import HTTPTypes
import OpenAPIRuntime
import OpenAPIURLSession

/// A dynamic HTTP client that can make arbitrary HTTP requests with middleware support.
/// This client is designed to work alongside static OpenAPI-generated clients,
/// sharing the same middleware chain for consistency.
public final class OpenAPIDynamic: Sendable {

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

  struct DecodingMetadata {
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

    let path =
      components.percentEncodedPath + (components.percentEncodedQuery.map { "?" + $0 } ?? "")
    components.percentEncodedPath = ""
    components.percentEncodedQuery = nil
    components.fragment = nil
    guard let baseURL = components.url else {
      throw InvalidRequestURLError(url: url)
    }
    return (baseURL, path)
  }

  func observeDecoding<T>(
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
    let request = HTTPRequest(
      method: method, scheme: nil, authority: nil, path: path, headerFields: headers)
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
    return try await sendRequestWithResponseBody(
      method: method, url: url, headers: headers, body: data)
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
    let (response, data) = try await sendRequestWithResponseBody(
      method: method, url: url, headers: headers, body: body)
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
    _ builder: (inout RequestBuilder) throws -> Void
  ) async throws -> HTTPResponse {
    let (response, data) = try await sendRequestWithResponseBody(builder)
    try response.validateSuccess(with: data)
    return response
  }

  /// Performs a streaming HTTP request configured by a request builder.
  public func sendRequestStreaming(
    _ builder: (inout RequestBuilder) throws -> Void
  ) async throws -> (HTTPResponse, HTTPBody?) {
    var requestBuilder = RequestBuilder()
    try builder(&requestBuilder)
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
    _ builder: (inout RequestBuilder) throws -> Void
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
