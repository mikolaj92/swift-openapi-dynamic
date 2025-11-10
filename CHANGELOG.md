# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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