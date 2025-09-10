import Blend
import Foundation

// MARK: - Data Models

struct User: Codable, Identifiable {
    let id: Int
    let name: String
    let email: String
    let username: String
}

// MARK: - Endpoints

struct UsersEndpoint: Endpoint {
    var scheme: URLScheme = .https
    var host: String = "jsonplaceholder.typicode.com"
    var path: String = "/users"
    var method: RequestMethod = .get
    var headers: [String: String]? = ["Accept": "application/json"]
    var body: Data? = nil
    var queryItems: [URLQueryItem]? = nil
    var contentType: String? = nil
    var timeout: TimeInterval? = nil
    var timeoutDuration: Duration? = .seconds(30)
    var port: Int? = nil
    var fragment: String? = nil
}

struct UserDetailsEndpoint: Endpoint {
    let userId: Int

    var scheme: URLScheme = .https
    var host: String = "jsonplaceholder.typicode.com"
    var path: String { "/users/\(userId)" }
    var method: RequestMethod = .get
    var headers: [String: String]? = ["Accept": "application/json"]
    var body: Data? = nil
    var queryItems: [URLQueryItem]? = nil
    var contentType: String? = nil
    var timeout: TimeInterval? = nil
    var timeoutDuration: Duration? = .seconds(30)
    var port: Int? = nil
    var fragment: String? = nil
}

// MARK: - Service

class UserService: AsyncRequestable {
    typealias ResponseModel = [User]

    func getUsers() async throws -> [User] {
        return try await sendRequest(to: UsersEndpoint())
    }

    func getUserDetails(id: Int) async throws -> User {
        return try await sendRequest(to: UserDetailsEndpoint(userId: id))
    }
}

// MARK: - Main Application

@main
struct BasicNetworkingExample {
    static func main() async {
        blendLogger.info("Blend Basic Networking Example")
        print("=================================")

        let userService = UserService()

        do {
            // Fetch all users
            print("\n📡 Fetching users...")
            let users = try await userService.getUsers()
            print("✅ Found \(users.count) users")

            // Display first few users
            for user in users.prefix(3) {
                print("👤 \(user.name) (\(user.email))")
            }

            // Fetch details for first user
            if let firstUser = users.first {
                print("\n📡 Fetching details for \(firstUser.name)...")
                let userDetails = try await userService.getUserDetails(id: firstUser.id)
                print("✅ User Details:")
                print("   Name: \(userDetails.name)")
                print("   Email: \(userDetails.email)")
                print("   Username: \(userDetails.username)")
            }

        } catch let error as NetworkError {
            print("❌ Network Error: \(error.localizedDescription)")

            switch error {
            case .networkUnavailable:
                print("   No internet connection")
            case .requestTimeout:
                print("   Request timed out")
            case .httpError(let statusCode, _):
                print("   HTTP \(statusCode)")
            default:
                print("   \(error.localizedDescription)")
            }

        } catch {
            print("❌ Unexpected Error: \(error.localizedDescription)")
        }

        print("\n🎉 Example completed!")
    }
}
