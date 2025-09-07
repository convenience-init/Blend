# Basic Networking Example

This example demonstrates the fundamental usage of Blend's `AsyncRequestable` protocol for basic networking operations.

## What You'll Learn

- How to create a service conforming to `AsyncRequestable`
- How to define network endpoints
- How to make type-safe API requests
- Basic error handling with `NetworkError`

## Key Components

### 1. Data Models
```swift
struct User: Codable, Identifiable {
    let id: Int
    let name: String
    let email: String
    let username: String
}
```

### 2. Endpoints
```swift
struct UsersEndpoint: Endpoint {
    // Define URL components, HTTP method, headers, etc.
}

struct UserDetailsEndpoint: Endpoint {
    let userId: Int
    // Dynamic path based on user ID
}
```

### 3. Service Implementation
```swift
class UserService: AsyncRequestable {
    typealias ResponseModel = [User] // Single response type

    func getUsers() async throws -> [User] {
        return try await sendRequest(to: UsersEndpoint())
    }
}
```

## Running the Example

```bash
cd Examples/BasicNetworking
swift run
```

## Expected Output

```
🚀 Blend Basic Networking Example
=================================

📡 Fetching users...
✅ Found 10 users
👤 Leanne Graham (Sincere@april.biz)
👤 Ervin Howell (Shanna@melissa.tv)
👤 Clementine Bauch (Nathan@yesenia.net)

📡 Fetching details for Leanne Graham...
✅ User Details:
   Name: Leanne Graham
   Email: Sincere@april.biz
   Username: Bret

🎉 Example completed!
```

## Error Handling

The example demonstrates proper error handling:

```swift
do {
    let users = try await userService.getUsers()
    // Handle success
} catch let error as NetworkError {
    // Handle specific network errors
    print("Network Error: \(error.message())")
} catch {
    // Handle unexpected errors
    print("Unexpected Error: \(error.localizedDescription)")
}
```

## Next Steps

After understanding this basic example, check out:
- [Advanced Networking](../AdvancedNetworking/) - Multiple response types
- [Image Operations](../ImageOperations/) - Image handling
- [SwiftUI Integration](../SwiftUIIntegration/) - UI integration