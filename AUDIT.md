# Audit Report: swift-openapi-dynamic

**Date**: 2026-07-22  
**Objective**: Detailed audit of the library as an auxiliary tool for dynamic network requests on top of the swift-openapi-generator stack, specifically to enable reuse of existing `ClientMiddleware` instances together with the default system `URLSession`.

**Scope**: Correctness of middleware reuse, fidelity of transport/middleware composition compared to official `swift-openapi-runtime` + `swift-openapi-urlsession`, URL construction, body handling, session usage, API design, documentation, and test strategy.

---

## Executive Summary

`OpenAPIDynamic` now fulfills its core purpose: it accepts the same `[any ClientMiddleware]` values as generated clients, composes them around the official `URLSessionTransport`, and uses an injected or default system `URLSession`.

**Verified properties**:
- Middleware request order and response unwinding match `UniversalClient`.
- Request mutation, short-circuiting, response transformation, exact origin metadata, and operation ID propagation are deterministic unit-test contracts.
- URL decomposition preserves scheme, userinfo, IPv6 brackets, ports, percent-encoded paths, and percent-encoded queries; fragments are correctly excluded from HTTP requests.
- Transport and middleware failures use `ClientError` envelopes with distinct generated-style cause descriptions while preserving the underlying error and request context.
- `Data`-returning APIs enforce a configurable response limit (10 MiB by default); streaming overloads expose `HTTPBody` without applying that collection limit.
- Live external integration tests are explicit opt-in smoke tests and do not make routine `swift test` flaky.
- README and example code use the current public API and demonstrate a shared middleware array.

**Verdict**: Suitable for the intended use: write an ad-hoc absolute-URL request by hand, execute it with the system `URLSession`, and reuse the existing `ClientMiddleware` instances already configured for generated clients. It is complementary plumbing, not an alternative to code generation. Callers supply an operation ID only when their middleware uses one.
---

## 1. Purpose Alignment

Claim (README):
> "allowing you to make arbitrary HTTP requests while sharing middleware with your statically generated API clients."

Usage model shown:
```swift
let middleware = [AuthMiddleware(), LoggingMiddleware()]
let staticClient = Client(serverURL: baseURL, transport: URLSessionTransport(), middlewares: middleware)
let dynamicClient = OpenAPIDynamic(middleware: middleware)
```

This is the exact use case the library targets: one set of middleware instances used for both generated static calls and dynamic ad-hoc calls.

---

## 2. Architecture & Middleware Composition

### Official stack (from source inspection)

`UniversalClient.send` (swift-openapi-runtime):
- Starts with `next` closure that calls `transport.send(...)`.
- Then for `middleware in middlewares.reversed()` wraps:
  ```swift
  next = { req, body, url in
      try await middleware.intercept(req, body: body, baseURL: url, operationID: opID, next: tmp)
  }
  ```
- Result: array order = request order (first element sees request first).

### This library

`MiddlewareTransport.send` mirrors `UniversalClient` with a `next` closure initialized to `URLSessionTransport.send`, then wraps each middleware in reverse array order. Each boundary preserves an existing `ClientError`; otherwise it creates a `ClientError` containing operation ID, request/body, base URL, cause description, and underlying error.

**Finding**: Request/response forwarding, array order, `ClientMiddleware.intercept` compatibility, and generated-style failure envelopes match the official runtime pattern. The public `ClientError` cannot use internal `RuntimeError.transportFailed` / `.middlewareFailed` values from `OpenAPIRuntime`, so compatibility is expressed through the same envelope and equivalent cause descriptions rather than the internal cause type.

**Evidence**:
- `Package.resolved`: runtime 1.8.3, urlsession 1.2.0.
- Runtime `UniversalClient.swift:143-177` uses the same closure chain and reversed construction.
- Deterministic tests distinguish middleware and transport failures and assert context, cause description, and underlying error.
### Session usage

- `OpenAPIDynamic` holds `public let session: URLSession`.
- Default: `.shared`.
- Passed to `URLSessionTransport(configuration: .init(session: session))`.
- Correct: custom sessions (timeouts, delegate, cookie storage, auth challenges) flow through.

**No issue here.**

---

## 3. URL Construction Fidelity

The client decomposes each absolute URL with `URLComponents`:
- `percentEncodedPath` plus `percentEncodedQuery` becomes `HTTPRequest.path`.
- Path, query, and fragment are removed from a copy of the components to produce the origin `baseURL`.
- Scheme and host are required; invalid/non-absolute inputs throw `InvalidRequestURLError` rather than silently substituting an origin.

This preserves port, IPv6 brackets, userinfo, and percent encoding through the composition performed by `URLSessionTransport`. The fragment is intentionally omitted because HTTP requests do not transmit URL fragments.

**Evidence**: deterministic tests assert middleware receives `http://user:pass@[::1]:8080` and assert the real `URLSessionTransport` path receives a custom port plus encoded path/query unchanged.
---

## 4. Body Handling

### Request bodies
- `Data?` → wrapped as `HTTPBody($0)`.
- Encodable convenience: encodes to Data, sets Content-Type if missing, then same path.
- Middleware sees proper `HTTPBody?`.

### Response bodies
- Middleware receives the streaming `HTTPBody?` directly from the transport and may inspect or transform it.
- `sendRequestStreaming` overloads (direct and builder) return that body to the caller without collecting it.
- APIs returning `Data` or decoded values collect only after middleware completes and enforce `maximumResponseBodyBytes` (10 MiB default).
- Callers can select a smaller/larger bound at initialization; a negative limit is rejected by precondition.

This prevents accidental unlimited buffering while preserving an explicit streaming path for large or incremental responses.

---

## 5. Header Auto-Mutation & Operation ID

- Decoding paths (those returning `T` or using decoders) auto-add `Accept: application/json` if absent.
- Encodable body paths auto-add `Content-Type: application/json` if absent.
- Mutations happen in the public methods **before** constructing `HTTPRequest` and calling the transport/middleware chain.
- Therefore middleware **will see** the auto-added headers. This is the intended "smart defaults" behavior.

**Operation ID**:
- Direct overloads use configurable `defaultOperationID` (`"dynamic-request"` by default).
- Builder requests may override it with `RequestBuilder.setOperationID`; otherwise they inherit the client default.
- Decoding-failure context reports the same effective operation ID used by middleware.

Dynamic URLs have no generated OpenAPI operation identity, so callers should provide an ID when middleware dispatches by operation.

---

## 6. Decoding Failure Observability

`decodingFailureHandler`:
- Receives `DecodingFailureContext` with method, url, operationID, response, responseBody (Data), targetType, error.
- Called from `observeDecoding` inside the decode paths.
- Runs after body collection, at the point the decoder throws.
- Explicitly documented as "does not replace middleware".

**Correct design**: middleware still sees transport-level request/response. Observer is post-transport, pre-user decoding.

Tested with `MockURLProtocol` in unit tests (good pattern).

---

## 7. Error Handling

- `HTTPError.statusError(HTTPResponse, body: Data?)` — body preserved.
- `validateSuccess()` throws with body when non-2xx.
- `DecodingError.noData`.
- `UnexpectedStatusError` for status maps.

Matches the "body preservation" claim in README. Good.

---

## 8. API Surface & Ergonomics

Public surface is rich:
- `sendRequest*` family (raw response, with body, and validate).
- Overloads for `Encodable` body, `Decodable` result.
- Builder form: `sendRequestWithResponseBody { builder in ... }`.
- Status-specific and type-map decoding.
- Flexible decoder closure.
- `decode(_:from:)` helper.

**Documentation**:
- README examples use the actual `sendRequest*` APIs and `decodingFailureHandler` label.
- The middleware section no longer invents a generated-client initializer.
- The example project defines a real `LoggingMiddleware` and passes one shared `[any ClientMiddleware]` array to `OpenAPIDynamic`; `swift build` succeeds in `example-project`.
---

## 9. Test Strategy & Coverage

### Unit tests (`OpenAPIDynamicTests`)
- 28 deterministic Swift Testing tests pass under Swift 6.2, including a serialized edge-case suite with two parameterized URL tables totaling 14 cases.
- Middleware contracts cover array order, request mutation, short-circuiting, response transformation, exact base URL, custom and default operation IDs, middleware failure envelopes, and transport failure envelopes.
- URL fidelity covers empty/root paths, custom ports, IPv6, userinfo, percent-encoded path/query, empty query values, fragments, and rejection of relative URLs.
- Response tests cover zero-byte, exact-boundary, over-limit, empty transport, nil middleware, and streaming behavior.
- The mock registry is keyed by URL, one-shot, and lock-protected for concurrent execution; the edge-case suite is serialized.

### Integration tests (`OpenAPIDynamicIntegrationTests`)
- Live tests remain useful smoke coverage for external service interoperability.
- They are explicitly gated by `OPENAPI_DYNAMIC_ENABLE_LIVE_TESTS=1`; routine local and CI `swift test` runs skip them with a clear reason.
- They are not used as deterministic correctness evidence.

### Conclusion on tests
Core URLSession/middleware behavior is covered without network access. External interoperability remains manually opt-in by design.
---

## 10. Other Observations

- Declared deployment floors remain macOS 10.15, iOS/tvOS 13, and watchOS 6, matching the dependency manifests.
- The package requires a Swift 6.2+ toolchain. The source no longer uses conditional-expression syntax unnecessarily, but SwiftPM tools version 6.2 is the authoritative compiler floor.
- Dependency floors now match APIs used by the implementation: swift-openapi-runtime 1.8.2+ and swift-openapi-urlsession 1.2.0+.
- A library build targeting `arm64-apple-macosx10.15` succeeds with the resolved dependency graph.
- No unnecessary dependencies.
- Always creates a new `MiddlewareTransport` per request (fine, cheap).

---

## 11. Recommendations (Prioritized)

### Operational guidance

1. Reuse the same middleware instances only when their internal state is `Sendable` and safe for concurrent calls; this requirement comes from the runtime middleware contract.
2. Set `defaultOperationID` per dynamic client, or set an ID on each builder, when authentication, metrics, or routing middleware branches on operation identity.
3. Choose `maximumResponseBodyBytes` from the expected payload contract. Use `sendRequestStreaming` for genuinely large or incremental bodies.
4. Keep live integration tests opt-in unless external services are replaced by a controlled local server.

### Optional expansion

Consider accepting an arbitrary `ClientTransport` only when a concrete caller needs transport reuse beyond URLSession. The current scope explicitly targets the system URLSession stack; adding another abstraction now would not improve that use case.
---

## 12. Summary Table

| Aspect | Status | Notes |
|---|---|---|
| Middleware protocol fidelity | Good | Official closure ordering and generated-style `ClientError` envelopes |
| Session injection | Good | Default `.shared`; custom `URLSession` reaches `URLSessionTransport` |
| BaseURL/path fidelity | Good | Port, IPv6, userinfo, encoded path/query covered |
| Body handling | Good | 10 MiB default bound plus explicit streaming API |
| Auto headers | As designed | JSON defaults are visible to middleware and caller overrides win |
| Operation ID | Good | Configurable client default and builder override |
| Error body preservation | Good | Non-2xx validation preserves collected body |
| Decoding handler | Good | Separate post-transport decoding context |
| Unit tests | Good | 28 deterministic Swift Testing tests pass under Swift 6.2 |
| Integration stability | Good | External smoke tests are explicit opt-in |
| Documentation accuracy | Good | Current API; executable middleware-sharing example |

---

## Final Assessment

The library is a sound helper for hand-written, runtime-selected URL requests that must pass through the same `ClientMiddleware` stack as generated clients and ultimately use system `URLSession`. Its behavior is aligned at every boundary reusable middleware observes: ordering, mutable request/body/base URL forwarding, response unwinding, operation metadata, and error envelopes.

It deliberately does not reproduce generated operations, schema-derived input/output types, or generated clients. Those remain the responsibility of `swift-openapi-generator`. `OpenAPIDynamic` only fills the separate ad-hoc-request path while avoiding duplicated authentication, logging, tracing, retry, or other middleware logic.

Verification on 2026-07-22: the final `swift test` run passed 28 deterministic Swift Testing tests, including seven middleware decomposition and seven `URLSessionTransport` round-trip URL cases; 18 live-network smoke tests were skipped by their explicit opt-in gate. `swift build -Xswiftc -target -Xswiftc arm64-apple-macosx10.15` and `swift build` in `example-project` passed.

End of audit.