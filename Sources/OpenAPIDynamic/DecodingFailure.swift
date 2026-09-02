import Foundation
import HTTPTypes
import OpenAPIRuntime
import OpenAPIURLSession

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
