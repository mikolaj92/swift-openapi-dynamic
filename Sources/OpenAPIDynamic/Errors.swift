import Foundation
import HTTPTypes
import OpenAPIRuntime
import OpenAPIURLSession

/// A URL string supplied to `RequestBuilder` is not an absolute HTTP or HTTPS URL.
public struct InvalidRequestURLStringError: Error, LocalizedError, Equatable {
  public let value: String

  public var errorDescription: String? {
    "Invalid absolute HTTP request URL: \(value)"
  }
}

/// A request was sent without a destination URL.
public struct MissingRequestURLError: Error, LocalizedError, Equatable {
  public var errorDescription: String? {
    "Request is missing an absolute HTTP URL"
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
///
/// Synthesized `Equatable` compares the full `HTTPResponse` (status and headers)
/// and the preserved response body. Two errors with the same status but different
/// payloads are not equal; `errorDescription` still reports only the status line.
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
}

/// Errors that can occur during decoding.
public enum DecodingError: Error, LocalizedError, Equatable {
  /// No data was available to decode.
  ///
  /// Thrown when a required decoded value is requested and the collected response body is `nil`.
  /// A present zero-byte body is not this error: it is passed to `JSONDecoder` and typically
  /// surfaces as `Swift.DecodingError`.
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
///
/// - Throws: ``DecodingError/noData`` when `data` is `nil`. A present empty `Data()` is decoded
///   and typically throws `Swift.DecodingError`.
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
