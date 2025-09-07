import Blend
import Foundation

// MARK: - Data Models

/// User summary for list views
struct UserSummary: Codable, Identifiable {
    let id: Int
    let name: String
    let username: String
    let email: String

    var initials: String {
        name.split(separator: " ").compactMap { $0.first }.prefix(2).map(String.init).joined()
    }
}

/// Detailed user information for detail views
struct UserDetails: Codable, Identifiable {
    let id: Int
    let name: String
    let username: String
    let email: String
    let phone: String
    let website: String

    struct Address: Codable {
        let street: String
        let suite: String
        let city: String
        let zipcode: String

        var fullAddress: String {
            "\(street), \(suite), \(city) \(zipcode)"
        }
    }

    struct Company: Codable {
        let name: String
        let catchPhrase: String
        let bs: String
    }

    let address: Address
    let company: Company
}

/// Input model for creating/updating users
struct UserInput: Codable {
    let name: String
    let username: String
    let email: String
    let phone: String?
    let website: String?
}

// MARK: - Endpoints

/// Endpoint for fetching all users (list operation)
struct UsersEndpoint: Endpoint {
    var scheme: URLScheme = .https
    var host: String = "jsonplaceholder.typicode.com"
    var path: String = "/users"
    var method: RequestMethod = .get
    var headers: [String: String]? = ["Accept": "application/json"]
    var contentType: String? = nil
    var timeout: TimeInterval? = nil
    var timeoutDuration: Duration? = .seconds(30)
    var body: Data? = nil
    var port: Int? = nil
    var fragment: String? = nil
    var queryItems: [URLQueryItem]? = nil
}

/// Endpoint for fetching a specific user (detail operation)
struct UserDetailsEndpoint: Endpoint {
    let userId: Int

    var scheme: URLScheme = .https
    var host: String = "jsonplaceholder.typicode.com"
    var path: String { "/users/\(userId)" }
    var method: RequestMethod = .get
    var headers: [String: String]? = ["Accept": "application/json"]
    var contentType: String? = nil
    var timeout: TimeInterval? = nil
    var timeoutDuration: Duration? = .seconds(30)
    var body: Data? = nil
    var port: Int? = nil
    var fragment: String? = nil
    var queryItems: [URLQueryItem]? = nil
}

/// Endpoint for creating a new user
struct CreateUserEndpoint: Endpoint {
    let input: UserInput

    var scheme: URLScheme = .https
    var host: String = "jsonplaceholder.typicode.com"
    var path: String = "/users"
    var method: RequestMethod = .post
    var headers: [String: String]? = [
        "Content-Type": "application/json",
        "Accept": "application/json",
    ]
    var contentType: String? = "application/json"
    var timeout: TimeInterval? = nil
    var timeoutDuration: Duration? = .seconds(30)
    var body: Data?
    var port: Int? = nil
    var fragment: String? = nil
    var queryItems: [URLQueryItem]? = nil

    init(input: UserInput) {
        self.input = input
        self.body = try? JSONEncoder().encode(input)
    }
}

/// Endpoint for updating a user
struct UpdateUserEndpoint: Endpoint {
    let userId: Int
    let input: UserInput

    var scheme: URLScheme = .https
    var host: String = "jsonplaceholder.typicode.com"
    var path: String { "/users/\(userId)" }
    var method: RequestMethod = .put
    var headers: [String: String]? = [
        "Content-Type": "application/json",
        "Accept": "application/json",
    ]
    var contentType: String? = "application/json"
    var timeout: TimeInterval? = nil
    var timeoutDuration: Duration? = .seconds(30)
    var body: Data?
    var port: Int? = nil
    var fragment: String? = nil
    var queryItems: [URLQueryItem]? = nil

    init(userId: Int, input: UserInput) {
        self.userId = userId
        self.input = input
        self.body = try? JSONEncoder().encode(input)
    }
}

/// Endpoint for deleting a user
struct DeleteUserEndpoint: Endpoint {
    let userId: Int

    var scheme: URLScheme = .https
    var host: String = "jsonplaceholder.typicode.com"
    var path: String { "/users/\(userId)" }
    var method: RequestMethod = .delete
    var headers: [String: String]? = ["Accept": "application/json"]
    var contentType: String? = nil
    var timeout: TimeInterval? = nil
    var timeoutDuration: Duration? = .seconds(30)
    var body: Data? = nil
    var port: Int? = nil
    var fragment: String? = nil
    var queryItems: [URLQueryItem]? = nil
}

// MARK: - Service Implementation

/// Advanced user service demonstrating master-detail patterns and CRUD operations
struct UserService: AdvancedAsyncRequestable {
    /// Primary response type for list operations
    typealias ResponseModel = [UserSummary]

    /// Secondary response type for detail operations
    typealias SecondaryResponseModel = UserDetails

    // MARK: - Required Protocol Implementation

    /// Generic request function required by AdvancedAsyncRequestable
    func sendRequest<T: Decodable>(_ type: T.Type, to endpoint: Endpoint) async throws -> T {
        return try await sendRequest(to: endpoint)
    }

    // MARK: - List Operations

    /// Fetch all users (list operation using ResponseModel)
    func getUsers() async throws -> [UserSummary] {
        return try await fetchList(from: UsersEndpoint())
    }

    // MARK: - Detail Operations

    /// Fetch user details (detail operation using SecondaryResponseModel)
    func getUserDetails(id: Int) async throws -> UserDetails {
        return try await fetchDetails(from: UserDetailsEndpoint(userId: id))
    }

    // MARK: - CRUD Operations

    /// Create a new user
    func createUser(_ input: UserInput) async throws -> UserDetails {
        return try await sendRequest(UserDetails.self, to: CreateUserEndpoint(input: input))
    }

    /// Update an existing user
    func updateUser(id: Int, _ input: UserInput) async throws -> UserDetails {
        return try await sendRequest(
            UserDetails.self, to: UpdateUserEndpoint(userId: id, input: input))
    }

    /// Delete a user (returns summary for consistency)
    func deleteUser(id: Int) async throws -> UserSummary {
        return try await sendRequest(UserSummary.self, to: DeleteUserEndpoint(userId: id))
    }

    // MARK: - Advanced Patterns

    /// Get user with details in one operation
    func getUserWithDetails(id: Int) async throws -> (summary: UserSummary, details: UserDetails) {
        async let detailsTask = getUserDetails(id: id)

        let users = try await getUsers()
        guard let summary = users.first(where: { $0.id == id }) else {
            throw NSError(
                domain: "UserService", code: 404,
                userInfo: [NSLocalizedDescriptionKey: "User not found"])
        }

        let details = try await detailsTask
        return (summary, details)
    }

    /// Batch operation: Get multiple users with their details
    func getUsersWithDetails(ids: [Int]) async throws -> [(
        summary: UserSummary, details: UserDetails
    )] {
        return try await withThrowingTaskGroup(of: (UserSummary, UserDetails).self) { group in
            for id in ids {
                group.addTask {
                    let (summary, details) = try await self.getUserWithDetails(id: id)
                    return (summary, details)
                }
            }

            var results: [(UserSummary, UserDetails)] = []
            for try await result in group {
                results.append(result)
            }
            return results
        }
    }
}

// MARK: - Main Example

@main
struct AdvancedNetworkingExample {
    static func main() async {
        blendLogger.info("Blend Advanced Networking Example")
        blendLogger.info("====================================")

        let userService = UserService()

        do {
            // 1. LIST OPERATION: Get all users
            blendLogger.info("1. Fetching user list...")
            let users = try await userService.getUsers()
            blendLogger.info("✅ Found \(users.count) users")
            blendLogger.info("First 3 users:")
            for user in users.prefix(3) {
                blendLogger.info("   • \(user.name) (@\(user.username)) - \(user.email)")
            }
            blendLogger.info("")

            // 2. DETAIL OPERATION: Get specific user details
            blendLogger.info("2. Fetching details for first user...")
            let firstUserId = users.first?.id ?? 1
            let userDetails = try await userService.getUserDetails(id: firstUserId)
            blendLogger.info("✅ User Details for \(userDetails.name):")
            blendLogger.info("   📧 Email: \(userDetails.email)")
            blendLogger.info("   📱 Phone: \(userDetails.phone)")
            blendLogger.info("   🌐 Website: \(userDetails.website)")
            blendLogger.info("   🏢 Company: \(userDetails.company.name)")
            blendLogger.info("   📍 Address: \(userDetails.address.fullAddress)")
            blendLogger.info("")

            // 3. CREATE OPERATION: Create a new user
            blendLogger.info("3. Creating a new user...")
            let newUserInput = UserInput(
                name: "John Doe",
                username: "johndoe",
                email: "john.doe@example.com",
                phone: "+1-555-123-4567",
                website: "johndoe.dev"
            )

            let createdUser = try await userService.createUser(newUserInput)
            blendLogger.info("✅ Created user: \(createdUser.name) (ID: \(createdUser.id))")
            blendLogger.info("")

            // 4. UPDATE OPERATION: Update the created user
            blendLogger.info("4. Updating the created user...")
            let updateInput = UserInput(
                name: "John Doe Updated",
                username: "johndoe_updated",
                email: "john.doe.updated@example.com",
                phone: createdUser.phone,
                website: "updated.johndoe.dev"
            )

            let updatedUser = try await userService.updateUser(id: createdUser.id, updateInput)
            blendLogger.info("✅ Updated user: \(updatedUser.name)")
            blendLogger.info("   📧 New email: \(updatedUser.email)")
            blendLogger.info("   🌐 New website: \(updatedUser.website)")
            blendLogger.info("")

            // 5. ADVANCED PATTERN: Get user with details
            blendLogger.info("5. Advanced pattern - User with details...")
            let (summary, details) = try await userService.getUserWithDetails(id: firstUserId)
            blendLogger.info("✅ Combined data for \(summary.name):")
            blendLogger.info("   📧 Email: \(details.email)")
            blendLogger.info("   🏢 Company: \(details.company.name)")
            blendLogger.info("")

            // 6. BATCH OPERATION: Get multiple users with details
            blendLogger.info("6. Batch operation - Multiple users with details...")
            let userIds = users.prefix(3).map { $0.id }
            let batchResults = try await userService.getUsersWithDetails(ids: Array(userIds))
            blendLogger.info("✅ Retrieved details for \(batchResults.count) users:")
            for (summary, details) in batchResults {
                blendLogger.info("   • \(summary.name): \(details.company.name)")
            }
            blendLogger.info("")

            blendLogger.info("Advanced Networking Example completed successfully!")
            blendLogger.info("This example demonstrated:")
            blendLogger.info("• List operations with ResponseModel ([UserSummary])")
            blendLogger.info("• Detail operations with SecondaryResponseModel (UserDetails)")
            blendLogger.info("• CRUD operations (Create, Read, Update, Delete)")
            blendLogger.info("• Advanced patterns (combined data, batch operations)")
            blendLogger.info("• Error handling with NetworkError")

        } catch let error as NetworkError {
            blendLogger.info("❌ Network Error: \(error.localizedDescription)")
            switch error {
            case .httpError(let statusCode, _):
                blendLogger.info("   HTTP Status: \(statusCode)")
            case .networkUnavailable:
                blendLogger.info("   No internet connection")
            case .decodingError:
                blendLogger.info("   Failed to parse response")
            default:
                blendLogger.info("   Other network error")
            }
        } catch {
            blendLogger.info("❌ Unexpected Error: \(error.localizedDescription)")
        }
    }
}
