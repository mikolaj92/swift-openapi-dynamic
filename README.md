# OpenAPIDynamic

[![Swift](https://img.shields.io/badge/Swift-6.2+-orange.svg)](https://swift.org)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Build](https://github.com/mikolaj92/swift-openapi-dynamic/actions/workflows/daily_test.yml/badge.svg)](https://github.com/mikolaj92/swift-openapi-dynamic/actions)

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
    .package(url: "https://github.com/mikolaj92/swift-openapi-dynamic", from: "1.1.0"),
    .package(url: "https://github.com/apple/swift-openapi-runtime", from: "1.0.0"),
    .package(url: "https://github.com/apple/swift-openapi-urlsession", from: "1.0.0"),
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

Provide `decodingFailureObserver` to receive one callback whenever a response is received but decoding fails. The callback includes request metadata, operation ID, response status, response body, expected Swift type, and the thrown decoding error.

```swift
let client = OpenAPIDynamic(
    middleware: [YourMiddleware()],
    decodingFailureObserver: { context in
        print("Failed to decode \(context.targetType)")
        print("Request: \(context.method.rawValue) \(context.url)")
        print("Operation ID: \(context.operationID)")
        print("Status: \(context.response?.status.code ?? -1)")
        print("Error: \(context.error)")
    }
)
```

This observer does not replace middleware. Middleware still sees transport-level request and response data. `decodingFailureObserver` runs after the response body is collected, at the exact point where `JSONDecoder` or a custom decoder closure throws.

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

// Request with body and headers
let response = try await client.request(
    method: .post,
    url: someDynamicURL,
    headers: [.contentType: "application/json"],
    body: jsonData
)

// Request with Encodable body (automatically JSON-encoded and content-type set)
let user = User(name: "John", email: "john@example.com")
let response = try await client.request(
    method: .post,
    url: someDynamicURL,
    body: user
)

// Get response with body data
let (response, bodyData) = try await client.requestWithBody(
    method: .get,
    url: dynamicURL
)
```

### Using the Request Builder

For more complex requests, use the fluent request builder:

```swift
let (response, bodyData) = try await client.sendRequestWithResponseBody { builder in
    builder.setMethod(.post)
    builder.setURL("https://api.example.com/api/v1/users")
    builder.setQuery(["limit": "10"])
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
    builder.setURL("https://api.example.com/api/health")
}

// Manual validation
let response = try await client.sendRequest(method: .get, url: healthURL)
try response.validateSuccess()
```

## Codable Decoding

The library provides powerful Codable decoding capabilities for type-safe JSON handling.

### Basic Decoding

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
let user: User = try await client.requestWithStatusDecoding(
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
let user: User = try await client.request(method: .get, url: userURL, decoder: decoder)
```

### Sharing Middleware

The client accepts any middleware that conforms to `ClientMiddleware` from OpenAPIRuntime:

```swift
import OpenAPIRuntime

struct LoggingMiddleware: ClientMiddleware {
    func intercept(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String,
        next: (HTTPRequest, HTTPBody?, URL) async throws -> (HTTPResponse, HTTPBody?)
    ) async throws -> (HTTPResponse, HTTPBody?) {
        print("Making request to \(request.path ?? "")")
        return try await next(request, body, baseURL)
    }
}

let client = OpenAPIDynamic(
    middleware: [LoggingMiddleware()]
)
```

## Integration with Static Clients

Use the same middleware instances for both static and dynamic clients:

```swift
let middleware = [AuthMiddleware(), LoggingMiddleware()]

// Static client (generated by swift-openapi-generator)
let staticClient = Client(
    serverURL: baseURL,
    transport: URLSessionTransport(),
    middlewares: middleware
)

// Dynamic client (this library)
let dynamicClient = OpenAPIDynamic(
    middleware: middleware
)
```

## Error Handling

The library provides structured error handling with body data preservation:

```swift
do {
    let user: User = try await client.sendRequestAndValidate(method: .get, url: userURL)
} catch let error as HTTPError {
    switch error {
    case .statusError(let response, let body):
        print("HTTP error: \(response.status)")
        if let body = body {
            let errorModel = try? JSONDecoder().decode(APIError.self, from: body)
            print("Error details: \(errorModel)")
        }
    }
} catch let error as DecodingError {
    switch error {
    case .noData:
        print("Response had no body data")
    }
} catch let error as UnexpectedStatusError {
    print("Unexpected status: \(error.localizedDescription)")
} catch {
    print("Other error: \(error)")
}
```

### Error Types

- `HTTPError.statusError`: HTTP errors with optional response body
- `DecodingError.noData`: Missing response data during decoding
- `UnexpectedStatusError.unexpectedStatus`: Unmapped HTTP status codes

## Requirements

- Swift 6.2+
- macOS 10.15+
- Compatible with swift-openapi-runtime and swift-openapi-urlsession

## Contributing

Contributions are welcome! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for details.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
