# swift-openapi-dynamic: Behavior

## Middleware sharing

`OpenAPIDynamic` handles hand-written, runtime-selected URL requests through `ClientMiddleware` and `URLSessionTransport`. It does not generate clients, operations, or schema-derived input/output types.

```swift
let middleware: [any ClientMiddleware] = [AuthMiddleware(), LoggingMiddleware()]
let dynamicClient = OpenAPIDynamic(middleware: middleware)
```

The middleware types above are supplied by the caller. The same array can also be passed to a client generated outside this package, using that client's actual initializer. Both clients then use the same middleware instances; those instances must be safe for concurrent calls.

The example project defines `LoggingMiddleware` and passes a shared `[any ClientMiddleware]` array to `OpenAPIDynamic`. It contains no generated `Client`.

## Transport and middleware composition

`MiddlewareTransport.send` starts with a closure calling `URLSessionTransport.send`, then wraps middleware in reverse array order. Requests enter middleware in array order; responses unwind through the chain in reverse order. Middleware can mutate requests, short-circuit execution, or transform responses.

Transport and middleware boundaries preserve existing `ClientError` values. Other failures become `ClientError` values containing the operation ID, original request/body, base URL, cause description, and underlying error. Transport failures use `"Transport threw an error."`; middleware failures identify the middleware type. These envelopes do not use the runtime's internal cause types.

`OpenAPIDynamic` stores an immutable `public let session: URLSession`, defaulting to `.shared`, and passes it to `URLSessionTransport(configuration: .init(session: session))`. The client is `Sendable`.

## URL construction

The client decomposes each absolute URL with `URLComponents`:
- `percentEncodedPath` plus `percentEncodedQuery` becomes `HTTPRequest.path`.
- Removing path, query, and fragment produces the origin `baseURL`, retaining scheme, userinfo, host, and port.
- Scheme and host are required; invalid or relative inputs throw `InvalidRequestURLError`.

Fragments are excluded from HTTP requests. `RequestBuilder` starts without a destination; sending it without one throws `MissingRequestURLError`. String URLs and query composition are throwing operations.

## Body handling

- `Data?` request bodies are wrapped as `HTTPBody` when present.
- Encodable body overloads encode JSON and add `Content-Type: application/json` only when absent.
- Middleware receives the streaming response `HTTPBody?` before collection.
- `sendRequestStreaming` returns that body without collecting it; the caller consumes the stream.
- APIs returning `Data` or decoded values collect after middleware completes, up to `maximumResponseBodyBytes` (10 MiB by default). Exceeding the limit throws; a negative configured limit fails a precondition.

## Headers and operation IDs

The `T: Decodable` overloads of `sendRequest`, `sendRequestAndValidate`, and `sendRequestWithResponseBody`, plus `sendRequestWithTypeDecoding`, add `Accept: application/json` only when absent. Status-specific and flexible decoding do not add `Accept`. Header defaults are applied before middleware executes.

Requests use `defaultOperationID` (`"dynamic-request"` by default) unless a streaming call supplies an ID or a builder overrides it with `setOperationID`. Decoding-failure context uses the same effective ID. Supply an ID when middleware branches on operation identity; dynamic URLs have no generated OpenAPI operation identity.

## Decoding and errors

`decodingFailureHandler` receives `DecodingFailureContext` with method, URL, operation ID, response, collected response body, target type, and error. It runs when decoding throws, after transport and body collection, and rethrows the same error. It does not replace middleware.

Required decoding throws `DecodingError.noData` for an absent body. A present zero-byte body is passed to the decoder. The optional decoded-body overload returns `(response, nil)` for an absent body without invoking the handler. `URLSession` maps a no-payload HTTP response to empty `Data()`, not an absent body.

`validateSuccess(with:)` accepts 2xx responses and otherwise throws `HTTPError.statusError` with the supplied body. Client validation methods pass the collected response body. Status-map decoding throws `UnexpectedStatusError` when no decoder or type matches the response status.

## Requirements and live tests

The package requires Swift 6.2+, swift-openapi-runtime 1.8.2+, and swift-openapi-urlsession 1.2.0+. Declared deployment floors are macOS 10.15, iOS/tvOS 13, and watchOS 6.

External HTTP integration tests require `OPENAPI_DYNAMIC_ENABLE_LIVE_TESTS=1`. Routine `swift test` runs skip those live tests.
