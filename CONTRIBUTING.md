# Contributing to OpenAPIDynamic

Thank you for your interest in contributing to OpenAPIDynamic! This document provides guidelines and information for contributors.

## Development Setup

### Prerequisites

- Swift 6.2 or later
- macOS 10.15 or later

### Getting Started

1. Fork the repository
2. Clone your fork:
   ```bash
    git clone https://github.com/mikolaj92/swift-openapi-dynamic.git
    cd swift-openapi-dynamic
   ```

3. Build the project:
   ```bash
   swift build
   ```

4. Run tests:
   ```bash
   swift test
   ```

## Development Workflow

### Code Style

- Follow the [Swift API Design Guidelines](https://swift.org/documentation/api-design-guidelines/)
- Use consistent naming conventions
- Add documentation comments for all public APIs
- Keep lines under 120 characters

### Testing

- Write unit tests for new functionality
- Include integration tests for HTTP interactions
- Ensure all tests pass before submitting PR
- Test both success and failure scenarios

### Pull Requests

1. Create a feature branch from `main`
2. Make your changes
3. Add/update tests as needed
4. Ensure all tests pass
5. Update documentation if needed
6. Submit a pull request with a clear description

### Commit Messages

Use clear, descriptive commit messages following conventional commits:

- `feat:` for new features
- `fix:` for bug fixes
- `docs:` for documentation changes
- `test:` for test changes
- `refactor:` for code refactoring

## Project Structure

```
Sources/OpenAPIDynamic/
├── OpenAPIDynamic.swift  # Main client implementation

Tests/
├── OpenAPIDynamicTests/          # Unit tests
└── OpenAPIDynamicIntegrationTests/  # Integration tests
```

## Code of Conduct

This project follows a code of conduct to ensure a welcoming environment for all contributors. By participating, you agree to:

- Be respectful and inclusive
- Focus on constructive feedback
- Accept responsibility for mistakes
- Show empathy towards other contributors

## License

By contributing to this project, you agree that your contributions will be licensed under the same MIT License that covers the project.

## Questions?

If you have questions about contributing, please open an issue or start a discussion in the repository.