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

  /// Creates a new request builder without a destination URL.
  ///
  /// A request cannot be sent until `setURL` succeeds or `url` is assigned explicitly.
  public init() {
    self.url = URL(string: "about:blank")!
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

  /// Sets the URL from an absolute HTTP or HTTPS URL string.
  /// - Parameter url: The full URL string.
  /// - Returns: The builder for chaining.
  /// - Throws: `InvalidRequestURLStringError` when the string is not an absolute HTTP URL.
  @discardableResult
  public mutating func setURL(_ url: String) throws -> Self {
    guard
      let newURL = URL(string: url),
      let scheme = newURL.scheme?.lowercased(),
      scheme == "http" || scheme == "https",
      newURL.host != nil
    else {
      throw InvalidRequestURLStringError(value: url)
    }
    self.url = newURL
    return self
  }

  /// Adds query parameters to the URL.
  /// - Parameter parameters: The query parameters.
  /// - Returns: The builder for chaining.
  /// - Throws: `InvalidRequestURLError` when the current URL cannot be composed safely.
  @discardableResult
  public mutating func setQuery(_ parameters: [String: String]) throws -> Self {
    guard
      var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
      components.scheme?.lowercased() == "http" || components.scheme?.lowercased() == "https",
      components.host != nil
    else {
      throw InvalidRequestURLError(url: url)
    }
    components.queryItems =
      parameters
      .sorted { $0.key < $1.key }
      .map { URLQueryItem(name: $0.key, value: $0.value) }
    guard let newURL = components.url else {
      throw InvalidRequestURLError(url: url)
    }
    self.url = newURL
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
  public mutating func setBody<T: Encodable>(_ body: T, encoder: JSONEncoder = .init()) throws
    -> Self
  {
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
