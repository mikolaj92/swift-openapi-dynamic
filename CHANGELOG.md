# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed
- `HTTPError` equality now includes the full HTTP response and preserved body.
- Updated issue templates to show the current `OpenAPIDynamic(middleware:)` and `sendRequest` API.
- Removed the README build badge that pointed at the deleted `daily_test.yml` GitHub Actions workflow.

### Testing
- Added a pytest check that README does not advertise the deleted `daily_test.yml` workflow badge.

### Changed
- Declared immutable `OpenAPIDynamic` instances `Sendable` for use across Swift concurrency domains.

## [1.2.0] - 2026-07-22

### Added
- Added bounded response collection with a configurable 10 MiB default limit.
- Added streaming request APIs returning `HTTPBody` without collecting the response.
- Added configurable default and per-request operation IDs for middleware.

### Fixed
- Preserved ports, IPv6 hosts, userinfo, and percent-encoded paths and queries when forwarding absolute URLs through `URLSessionTransport`.
- Rejected relative request URLs instead of silently constructing an invalid transport request.
- Wrapped middleware and transport failures in generated-client-compatible `ClientError` context.
- Made live-network integration tests explicit opt-in so routine test runs remain deterministic.

### Changed
- Raised the minimum `swift-openapi-runtime` version to 1.8.2 and `swift-openapi-urlsession` version to 1.2.0.

## [1.1.0] - 2026-05-31

### Added
- Added `DecodingFailureContext` and the decoding-failure callback, now named `DecodingFailureHandler`.
- Added client-level decoding-failure support, now exposed as `decodingFailureHandler`.
- Handler context includes method, URL, operation ID, response, response body, target type, and thrown error.

## [1.0.0] - 2025-11-10

### Added
- Initial release of OpenAPIDynamic
- Dynamic HTTP client with middleware support
- Integration with swift-openapi-generator
- Fluent request builder API
- Comprehensive Codable decoding extensions
- Status-specific response decoding
- Structured error handling with body preservation
- Helper functions for safe JSON decoding
- Full test suite with unit and integration tests

### Features
- `OpenAPIDynamic` class for dynamic HTTP requests
- `RequestBuilder` for fluent request construction
- Decoding methods: `request<T>()`, `requestSuccessful<T>()`, `requestWithBody<T>()`
- Status decoding: `requestWithStatusDecoding()`, `requestWithTypeDecoding()`
- Flexible decoding: `requestDecoded()`
- Error types: `HTTPError`, `DecodingError`, `UnexpectedStatusError`
- Helper: `decode()` function for safe decoding

### Documentation
- Comprehensive README with usage examples
- API documentation comments
- Installation and integration guides

### Testing
- 26 comprehensive tests covering all functionality
- Unit tests for error handling and utilities
- Integration tests with real HTTP APIs
- Both success and failure scenario coverage

### Infrastructure
- Swift Package Manager support
- GitHub Actions CI/CD pipeline
- MIT License
- Contributing guidelines
