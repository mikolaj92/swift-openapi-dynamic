import Foundation
import HTTPTypes
import OpenAPIRuntime
import OpenAPIURLSession

/// A transport that applies middleware to URLSession requests.
struct MiddlewareTransport: ClientTransport {
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
        return try await transport.send(
          request, body: body, baseURL: baseURL, operationID: operationID)
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
