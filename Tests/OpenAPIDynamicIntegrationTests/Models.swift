import Foundation

// MARK: - Success Response Models

struct User: Codable, Equatable {
    let id: Int
    let name: String
    let email: String
    let username: String
    let address: Address
    let phone: String
    let website: String
    let company: Company
}

struct Address: Codable, Equatable {
    let street: String
    let suite: String
    let city: String
    let zipcode: String
    let geo: Geo
}

struct Geo: Codable, Equatable {
    let lat: String
    let lng: String
}

struct Company: Codable, Equatable {
    let name: String
    let catchPhrase: String
    let bs: String
}

struct Post: Codable, Equatable {
    let id: Int?
    let userId: Int
    let title: String
    let body: String
}

struct HttpBinResponse: Codable, Equatable {
    let url: String
    let headers: [String: String]
    let origin: String
    let args: [String: String]
    let data: String?
    let json: [String: String]?
}

struct HttpBinHeadersResponse: Codable, Equatable {
    let headers: [String: String]
}

// MARK: - Error Response Models

struct APIError: Codable, Equatable {
    let error: String
    let message: String
    let statusCode: Int
}

struct HttpBinError: Codable, Equatable {
    let error: String
    let status: Int
    let message: String
}

// MARK: - Test Configuration

enum TestConfiguration {
    static let httpBinBaseURL = URL(string: "https://httpbin.org")!
    static let jsonPlaceholderBaseURL = URL(string: "https://jsonplaceholder.typicode.com")!
    static let timeout: TimeInterval = 30.0

    /// Opt-in for live external network tests. Unset by default so `swift test` and CI
    /// skip these flaky smoke tests. Set to `1` to run them manually:
    /// `OPENAPI_DYNAMIC_ENABLE_LIVE_TESTS=1 swift test --filter OpenAPIDynamicIntegrationTests`
    static var areLiveNetworkTestsEnabled: Bool {
        ProcessInfo.processInfo.environment["OPENAPI_DYNAMIC_ENABLE_LIVE_TESTS"] == "1"
    }
}