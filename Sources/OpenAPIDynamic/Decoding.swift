import Foundation
import HTTPTypes
import OpenAPIRuntime
import OpenAPIURLSession

// MARK: - Decoding Extensions

extension OpenAPIDynamic {
  /// Performs an HTTP request and decodes the response body to the specified type.
  ///
  /// An absent collected body (`nil`) throws ``DecodingError/noData``. A present zero-byte body
  /// is passed to `decoder` and typically throws `Swift.DecodingError`. `decodingFailureHandler`
  /// receives the same error that is rethrown to the caller.
  /// - Parameters:
  ///   - method: The HTTP method.
  ///   - url: The URL for the request.
  ///   - headers: Additional headers to include.
  ///   - body: The request body data.
  ///   - decoder: The JSON decoder to use.
  /// - Returns: The decoded response body.
  /// - Throws: ``DecodingError/noData`` if the response body is absent, `Swift.DecodingError` for
  ///   a present body that cannot be decoded, or any request error.
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
    let (response, data) = try await sendRequestWithResponseBody(
      method: method, url: url, headers: headers, body: body)
    return try observeDecoding(
      targetType: T.self,
      metadata: DecodingMetadata(method: method, url: url, operationID: defaultOperationID),
      response: response,
      responseBody: data
    ) {
      try decode(T.self, from: data, using: decoder)
    }
  }

  /// Performs an HTTP request with a builder and decodes the response body to the specified type.
  ///
  /// An absent collected body (`nil`) throws ``DecodingError/noData``. A present zero-byte body
  /// is passed to `decoder` and typically throws `Swift.DecodingError`. `decodingFailureHandler`
  /// receives the same error that is rethrown to the caller.
  /// - Parameters:
  ///   - builder: A closure that configures the request.
  ///   - decoder: The JSON decoder to use.
  /// - Returns: The decoded response body.
  /// - Throws: ``DecodingError/noData`` if the response body is absent, `Swift.DecodingError` for
  ///   a present body that cannot be decoded, or any request error.
  public func sendRequest<T: Decodable>(
    _ builder: (inout RequestBuilder) throws -> Void,
    decoder: JSONDecoder = .init()
  ) async throws -> T {
    var requestBuilder = RequestBuilder()
    try builder(&requestBuilder)
    if requestBuilder.headers[.accept] == nil {
      requestBuilder.headers[.accept] = "application/json"
    }
    let metadata = try DecodingMetadata(requestBuilder, defaultOperationID: defaultOperationID)
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
      try decode(T.self, from: data, using: decoder)
    }
  }

  /// Performs an HTTP request, validates success, and decodes the response body to the specified type.
  ///
  /// After a successful status, an absent collected body (`nil`) throws ``DecodingError/noData``.
  /// A present zero-byte body is passed to `decoder` and typically throws `Swift.DecodingError`.
  /// `decodingFailureHandler` receives the same error that is rethrown to the caller.
  /// - Parameters:
  ///   - method: The HTTP method.
  ///   - url: The URL for the request.
  ///   - headers: Additional headers to include.
  ///   - body: The request body data.
  ///   - decoder: The JSON decoder to use.
  /// - Returns: The decoded response body.
  /// - Throws: `HTTPError` if the response status is not successful, ``DecodingError/noData`` if
  ///   the body is absent, `Swift.DecodingError` for a present body that cannot be decoded, or any
  ///   other request error.
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
    let (response, data) = try await sendRequestWithResponseBody(
      method: method, url: url, headers: headers, body: body)
    try response.validateSuccess(with: data)
    return try observeDecoding(
      targetType: T.self,
      metadata: DecodingMetadata(method: method, url: url, operationID: defaultOperationID),
      response: response,
      responseBody: data
    ) {
      try decode(T.self, from: data, using: decoder)
    }
  }

  /// Performs an HTTP request with a builder, validates success, and decodes the response body to the specified type.
  ///
  /// After a successful status, an absent collected body (`nil`) throws ``DecodingError/noData``.
  /// A present zero-byte body is passed to `decoder` and typically throws `Swift.DecodingError`.
  /// `decodingFailureHandler` receives the same error that is rethrown to the caller.
  /// - Parameters:
  ///   - builder: A closure that configures the request.
  ///   - decoder: The JSON decoder to use.
  /// - Returns: The decoded response body.
  /// - Throws: `HTTPError` if the response status is not successful, ``DecodingError/noData`` if
  ///   the body is absent, `Swift.DecodingError` for a present body that cannot be decoded, or any
  ///   other request error.
  public func sendRequestAndValidate<T: Decodable>(
    _ builder: (inout RequestBuilder) throws -> Void,
    decoder: JSONDecoder = .init()
  ) async throws -> T {
    var requestBuilder = RequestBuilder()
    try builder(&requestBuilder)
    if requestBuilder.headers[.accept] == nil {
      requestBuilder.headers[.accept] = "application/json"
    }
    let metadata = try DecodingMetadata(requestBuilder, defaultOperationID: defaultOperationID)
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
      try decode(T.self, from: data, using: decoder)
    }
  }

  /// Performs an HTTP request and returns the response with the decoded body.
  ///
  /// Distinguishes an absent body from a present zero-byte body. A `nil` collected body returns
  /// `(response, nil)` without throwing and without invoking `decodingFailureHandler`. A present
  /// empty `Data()` is decoded and typically throws `Swift.DecodingError`; that error is forwarded
  /// to `decodingFailureHandler` and rethrown. `URLSession` maps a no-payload HTTP response to
  /// empty `Data()`, so this overload returns `nil` only when middleware or the transport returned
  /// no body.
  /// - Parameters:
  ///   - method: The HTTP method.
  ///   - url: The URL for the request.
  ///   - headers: Additional headers to include.
  ///   - body: The request body data.
  ///   - decoder: The JSON decoder to use.
  /// - Returns: The HTTP response and the decoded body, or `nil` when no body was collected.
  /// - Throws: `Swift.DecodingError` for a present body that cannot be decoded, or any request error.
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
    let (response, data) = try await sendRequestWithResponseBody(
      method: method, url: url, headers: headers, body: body)
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
  ///
  /// Distinguishes an absent body from a present zero-byte body. A `nil` collected body returns
  /// `(response, nil)` without throwing and without invoking `decodingFailureHandler`. A present
  /// empty `Data()` is decoded and typically throws `Swift.DecodingError`; that error is forwarded
  /// to `decodingFailureHandler` and rethrown. `URLSession` maps a no-payload HTTP response to
  /// empty `Data()`, so this overload returns `nil` only when middleware or the transport returned
  /// no body.
  /// - Parameters:
  ///   - builder: A closure that configures the request.
  ///   - decoder: The JSON decoder to use.
  /// - Returns: The HTTP response and the decoded body, or `nil` when no body was collected.
  /// - Throws: `Swift.DecodingError` for a present body that cannot be decoded, or any request error.
  public func sendRequestWithResponseBody<T: Decodable>(
    _ builder: (inout RequestBuilder) throws -> Void,
    decoder: JSONDecoder = .init()
  ) async throws -> (HTTPResponse, T?) {
    var requestBuilder = RequestBuilder()
    try builder(&requestBuilder)
    if requestBuilder.headers[.accept] == nil {
      requestBuilder.headers[.accept] = "application/json"
    }
    let metadata = try DecodingMetadata(requestBuilder, defaultOperationID: defaultOperationID)
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
    let (response, data) = try await sendRequestWithResponseBody(
      method: method, url: url, headers: headers, body: body)
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
    _ builder: (inout RequestBuilder) throws -> Void,
    decoders: [HTTPResponse.Status: (Data?) throws -> T]
  ) async throws -> T {
    var requestBuilder = RequestBuilder()
    try builder(&requestBuilder)
    let metadata = try DecodingMetadata(requestBuilder, defaultOperationID: defaultOperationID)
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
    let (response, data) = try await sendRequestWithResponseBody(
      method: method, url: url, headers: headers, body: body)
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
    _ builder: (inout RequestBuilder) throws -> Void,
    typeMap: [Int: Decodable.Type],
    decoder: JSONDecoder = .init()
  ) async throws -> Decodable {
    var requestBuilder = RequestBuilder()
    try builder(&requestBuilder)
    if requestBuilder.headers[.accept] == nil {
      requestBuilder.headers[.accept] = "application/json"
    }
    let metadata = try DecodingMetadata(requestBuilder, defaultOperationID: defaultOperationID)
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
    let (response, data) = try await sendRequestWithResponseBody(
      method: method, url: url, headers: headers, body: body)
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
    _ builder: (inout RequestBuilder) throws -> Void,
    decoder: (HTTPResponse, Data?) throws -> T
  ) async throws -> T {
    var requestBuilder = RequestBuilder()
    try builder(&requestBuilder)
    let metadata = try DecodingMetadata(requestBuilder, defaultOperationID: defaultOperationID)
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
