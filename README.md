# OpenAPIDynamic

[![Swift](https://img.shields.io/badge/Swift-6.2+-orange.svg)](https://swift.org)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

A dynamic HTTP client for Swift that integrates with [swift-openapi-generator](https://github.com/apple/swift-openapi-generator), allowing you to make arbitrary HTTP requests while sharing middleware with your statically generated API clients.

## Overview

When using swift-openapi-generator, most of your API calls are handled by statically generated client code. However, sometimes you need to make dynamic HTTP requests where the URL and method are determined at runtime. This library provides a `OpenAPIDynamic` that can make such dynamic requests while sharing the same middleware chain as your static clients.

## Features

- **Dynamic HTTP requests**: Make requests with runtime-determined URLs and methods
- **Middleware compatibility**: Share middleware with static swift-openapi-generator clients
- **Flexible request building**: Use a fluent API to construct requests
- **Codable decoding**: Automatic JSON decoding with type safety
- **Decoding observability**: Inspect response decoding failures from one client-level hook
- **Status-specific decoding**: Handle different response models based on HTTP status codes
- **Response handling**: Get both response metadata and body data
- **Error handling**: Built-in HTTP status validation and structured error types

## Installation

Add this package to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/mikolaj92/swift-openapi-dynamic", from: "1.2.0"),
    .package(url: "https://github.com/apple/swift-openapi-runtime", from: "1.8.2"),
    .package(url: "https://github.com/apple/swift-openapi-urlsession", from: "1.2.0"),
],
```

Then add `"OpenAPIDynamic"` to your target's dependencies.

## Usage

### Basic Setup

```swift
import OpenAPIDynamic
import OpenAPIRuntime

let client = OpenAPIDynamic(
    middleware: [YourMiddleware()]
)
```

### Decoding Observability

Provide `decodingFailureHandler` to receive one callback whenever a response is received but decoding fails. The callback includes request metadata, operation ID, response status, response body, expected Swift type, and the thrown decoding error.

```swift
let client = OpenAPIDynamic(
    middleware: [YourMiddleware()],
    decodingFailureHandler: { context in
        print("Failed to decode \(context.targetType)")
        print("Request: \(context.method.rawValue) \(context.url)")
        print("Operation ID: \(context.operationID)")
        print("Status: \(context.response?.status.code ?? -1)")
        print("Error: \(context.error)")
    }
)
```

This handler does not replace middleware. Middleware still sees transport-level request and response data. `decodingFailureHandler` runs after the response body is collected, at the exact point where `JSONDecoder` or a custom decoder closure throws.

### Smart Defaults

OpenAPIDynamic includes intelligent defaults to make common JSON API patterns work seamlessly:

- **Automatic Accept Header**: When using methods that decode JSON responses (like `sendRequestAndValidate<T: Decodable>`), the `Accept: application/json` header is automatically set if not already specified
- **Content-Type for JSON Bodies**: When sending Encodable bodies, `Content-Type: application/json` is automatically set

```swift
// Accept: application/json is automatically added
let user: User = try await client.sendRequestAndValidate(method: .get, url: url)

// Content-Type: application/json is automatically added for Encodable bodies
let response = try await client.sendRequest(method: .post, url: url, body: userData)
```

### Making Dynamic Requests

```swift
// Simple request with URL
let response = try await client.sendRequest(
    method: .get,
    url: URL(string: "https://api.example.com/dynamic-endpoint")!
)

// Request with body and headers
let response = try await client.sendRequest(
    method: .post,
    url: someDynamicURL,
    headers: [.contentType: "application/json"],
    body: jsonData
)

// Get response with body data
let (response, bodyData) = try await client.sendRequestWithResponseBody(
    method: .get,
    url: dynamicURL
)

// Request with an Encodable body (automatically JSON-encoded and content type set)
let user = User(name: "John", email: "john@example.com")
let response = try await client.sendRequest(
    method: .post,
    url: someDynamicURL,
    body: user
)
```

### Using the Request Builder

For more complex requests, use the fluent request builder. String URLs and query composition are throwing operations: invalid or missing absolute HTTP(S) destinations fail before middleware or transport runs.

```swift
let (response, bodyData) = try await client.sendRequestWithResponseBody { builder in
    builder.setMethod(.post)
    try builder.setURL("https://api.example.com/api/v1/users")
    try builder.setQuery(["limit": "10"])
    builder.addHeader(.authorization, "Bearer \(token)")
    builder.addHeader(.contentType, "application/json")
    builder.setBody(userJSONData)
    builder.setOperationID("create-user")
}
```

### Validating Responses

```swift
// Automatically validate successful HTTP status (2xx)
let response = try await client.sendRequestAndValidate { builder in
    builder.setMethod(.get)
    try builder.setURL("https://api.example.com/api/health")
}

// Manual validation
let response = try await client.sendRequest(method: .get, url: healthURL)
try response.validateSuccess()
```

### Response buffering and streaming

`sendRequest`, decoding methods, validation methods, and `sendRequestWithResponseBody` collect response data. Collection is bounded by `maximumResponseBodyBytes`, which defaults to 10 MiB; exceeding the limit throws while collecting the body. Set the limit explicitly when constructing the client if your API needs a different bound.

Use `sendRequestStreaming` when the response must remain an `HTTPBody` stream instead of being collected into `Data`. The streaming overloads are available for both direct parameters and the request builder; the caller owns consuming the returned body.

```swift
let client = OpenAPIDynamic(maximumResponseBodyBytes: 2 * 1024 * 1024)
let (response, body): (HTTPResponse, HTTPBody?) = try await client.sendRequestStreaming(
    method: .get,
    url: downloadURL,
    operationID: "download-file"
)
```

Requests that do not provide an operation ID use `defaultOperationID`, whose default value is `"dynamic-request"`. A builder can override it with `setOperationID`.

## Codable Decoding

The library provides powerful Codable decoding capabilities for type-safe JSON handling.

### Basic Decoding

All decoding overloads distinguish an absent response body from a present zero-byte body. APIs that require a decoded value throw `OpenAPIDynamic.DecodingError.noData` for an absent body; a present empty body is passed to the decoder and normally produces `Swift.DecodingError`. The optional `sendRequestWithResponseBody<T>` overload returns `nil` only when the transport or middleware returned no body.

```swift
// Decode response to a specific type (automatically sets Accept: application/json)
let user: User = try await client.sendRequest(method: .get, url: userURL)

// Decode with success validation (automatically sets Accept: application/json)
let user: User = try await client.sendRequestAndValidate(method: .get, url: userURL)

// Get both response and decoded body (automatically sets Accept: application/json)
let (response, user): (HTTPResponse, User) = try await client.sendRequestWithResponseBody(method: .get, url: userURL)
```

### Status-Specific Decoding

Handle different response models based on HTTP status codes:

```swift
// Using type map
let result = try await client.sendRequestWithTypeDecoding(
    method: .post,
    url: createUserURL,
    typeMap: [200: User.self, 201: CreatedUser.self, 400: ValidationError.self]
)

// Using status decoders
let user: User = try await client.sendRequestWithStatusDecoding(
    method: .get,
    url: userURL,
    decoders: [.ok: { try decode(User.self, from: $0) }]
)

switch result {
case let user as User: print("User: \(user)")
case let created as CreatedUser: print("Created: \(created)")
case let error as ValidationError: throw error
default: throw UnexpectedStatusError.unexpectedStatus(response.status)
}

// Using status decoders
let user: User = try await client.sendRequestWithStatusDecoding(
    method: .get,
    url: userURL,
    decoders: [.ok: { try decode(User.self, from: $0) }]
)
```

### Flexible Decoding

For maximum control, use the flexible decoding closure:

```swift
let user = try await client.sendRequestWithFlexibleDecoding(method: .get, url: userURL) { response, data in
    switch response.status.code {
    case 200: return try JSONDecoder().decode(User.self, from: data!)
    case 404: throw try JSONDecoder().decode(NotFoundError.self, from: data!)
    default: throw UnexpectedStatusError.unexpectedStatus(response.status)
    }
}
```

### Helper Functions

```swift
// Safe decoding helper
let user = try decode(User.self, from: data)

// Custom decoder
let decoder = JSONDecoder()
decoder.dateDecodingStrategy = .iso8601
let user: User = try await client.sendRequest(method: .get, url: userURL, decoder: decoder)
```

### Sharing Middleware

The client accepts any middleware that conforms to `ClientMiddleware` from OpenAPIRuntime:

```swift
import Foundation
import HTTPTypes
import OpenAPIDynamic
import OpenAPIRuntime
struct LoggingMiddleware: ClientMiddleware {
    func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String,
        next: @Sendable (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        let path = request.path ?? ""
        print("Making request to \(path)")
        return try await next(request, body, baseURL)
    }
}

let client = OpenAPIDynamic(
    middleware: [LoggingMiddleware()]
)
```

## Integration with Static Clients

`ClientMiddleware` is the middleware protocol used by generated clients. Keep one array of middleware instances and pass that array to both a generated client and `OpenAPIDynamic`; the dynamic client executes the same instances around its underlying `URLSession` transport.

```swift
let middleware: [any ClientMiddleware] = [AuthMiddleware(), LoggingMiddleware()]
let dynamicClient = OpenAPIDynamic(middleware: middleware)
```

When you have a generated `Client`, pass this same `middleware` array to the generated client's middleware parameter. The exact generated initializer depends on the API document and generator configuration, so this README does not invent a `Client` initializer.

The example project has no generated `Client`; its `LoggingMiddleware` and shared array demonstrate actual middleware execution with `OpenAPIDynamic`.

## Error Handling

The library provides structured HTTP status errors with the collected response body when using validation:

```swift
do {
    let user: User = try await client.sendRequestAndValidate(method: .get, url: userURL)
} catch let error as HTTPError {
    switch error {
    case .statusError(let response, let body):
        print("HTTP error: \(response.status)")
        if let body {
            let errorModel = try? JSONDecoder().decode(APIError.self, from: body)
            print("Error details: \(String(describing: errorModel))")
        }
    }
} catch let error as DecodingError {
    if case .noData = error { print("Response had no body data") }
} catch let error as UnexpectedStatusError {
    print("Unexpected status: \(error.localizedDescription)")
}
```

Transport and middleware failures are wrapped in the OpenAPIRuntime `ClientError` envelope, preserving the operation ID, request context, cause description, and underlying error. Transport failures use `"Transport threw an error."`; middleware failures identify the middleware type. These errors are distinct from HTTP status validation errors and decoding errors.

### Error Types

- `HTTPError.statusError`: HTTP errors with optional response body
- `DecodingError.noData`: Missing response data during decoding
- `UnexpectedStatusError.unexpectedStatus`: Unmapped HTTP status codes
- `ClientError`: Transport or middleware failures with generated-client-compatible context


## Requirements

- Swift 6.2+ toolchain
- macOS 10.15+, iOS 13+, tvOS 13+, watchOS 6+
- swift-openapi-runtime 1.8.2+
- swift-openapi-urlsession 1.2.0+

## Contributing

Contributions are welcome! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for details.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
