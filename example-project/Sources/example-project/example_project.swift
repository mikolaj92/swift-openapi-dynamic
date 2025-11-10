import OpenAPIDynamic
import OpenAPIRuntime
import Foundation
import HTTPTypes

struct User: Codable {
    let id: Int
    let name: String
    let email: String
}

struct CreateUser: Codable {
    let name: String
    let email: String
}

struct Post: Codable {
    let id: Int?
    let userId: Int
    let title: String
    let body: String
}

@main
struct example_project {
    static func main() async {
        do {
            let client = OpenAPIDynamic(
                middleware: []
            )

            print("=== OpenAPIDynamic Example ===\n")

            // 1. Fetch a user with automatic Accept header
            print("1. Fetching user with automatic JSON Accept header...")
            let user: User = try await client.sendRequest(
                method: .get,
                url: URL(string: "https://jsonplaceholder.typicode.com/users/1")!
            )
            print("   Fetched user: \(user.name) (\(user.email))\n")

            // 2. Create a post with Encodable body (auto-sets Content-Type)
            print("2. Creating a post with Encodable body (Content-Type auto-set)...")
            let newPost = Post(id: nil, userId: 1, title: "OpenAPIDynamic Example", body: "This post was created using the new API!")
            let (response, data) = try await client.sendRequestWithResponseBody(
                method: .post,
                url: URL(string: "https://jsonplaceholder.typicode.com/posts")!,
                body: newPost
            )
            print("   Response status: \(response.status)")
            let createdPost = try JSONDecoder().decode(Post.self, from: data!)
            print("   Created post ID: \(createdPost.id ?? 0)\n")

            // 3. Using the builder pattern
            print("3. Using the builder pattern...")
            let builderUser: User = try await client.sendRequest { @Sendable builder in
                builder.setMethod(.get)
                builder.setURL(URL(string: "https://jsonplaceholder.typicode.com/users/2")!)
                builder.addHeader(.userAgent, "OpenAPIDynamicExample/1.0")
            }
            print("   Builder fetched user: \(builderUser.name)\n")

            // 4. Custom headers and validation
            print("4. Custom headers with validation...")
            let validatedResponse = try await client.sendRequestAndValidate(
                method: .get,
                url: URL(string: "https://httpbin.org/status/200")!
            )
            print("   Validated response status: \(validatedResponse.status)\n")

            // 5. Flexible decoding
            print("5. Flexible decoding with custom processing...")
            let processedResult: String = try await client.sendRequestWithFlexibleDecoding(
                method: .get,
                url: URL(string: "https://httpbin.org/get")!,
                decoder: { @Sendable response, data in
                    let size = data?.count ?? 0
                    return "Received \(size) bytes of data"
                }
            )
            print("   \(processedResult)\n")

            print("=== All examples completed successfully! ===")

        } catch {
            print("Error: \(error)")
        }
    }
}
