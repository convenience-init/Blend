# Advanced Networking Example

This example demonstrates advanced networking patterns using Blend's `AdvancedAsyncRequestable` protocol, including master-detail operations, CRUD functionality, and complex service composition.

## What You'll Learn

- How to use `AdvancedAsyncRequestable` with dual response types
- Master-detail patterns (list view + detail view)
- CRUD operations with different response types
- Advanced service patterns and composition
- Batch operations and combined data fetching
- Type-safe service hierarchies

## Key Components

### 1. Dual Response Types

```swift
class UserService: AdvancedAsyncRequestable {
    typealias ResponseModel = [UserSummary]        // For list operations
    typealias SecondaryResponseModel = UserDetails // For detail operations
}
```

### 2. Master-Detail Pattern

```swift
// List operation - returns summaries
let users = try await userService.getUsers() // [UserSummary]

// Detail operation - returns full details
let details = try await userService.getUserDetails(id: 1) // UserDetails
```

### 3. CRUD Operations

```swift
// Create - returns created item details
let newUser = try await userService.createUser(input) // UserDetails

// Update - returns updated item details
let updatedUser = try await userService.updateUser(id: 1, input) // UserDetails

// Delete - returns summary for consistency
let deletedUser = try await userService.deleteUser(id: 1) // UserSummary
```

### 4. Advanced Patterns

```swift
// Combined data fetching
let (summary, details) = try await userService.getUserWithDetails(id: 1)

// Batch operations
let batchResults = try await userService.getUsersWithDetails(ids: [1, 2, 3])
```

## Running the Example

```bash
cd Examples/AdvancedNetworking
swift run
```

## Expected Output

```
🚀 Blend Advanced Networking Example
====================================

📋 1. Fetching user list...
✅ Found 10 users
👥 First 3 users:
   • Leanne Graham (@Bret) - Sincere@april.biz
   • Ervin Howell (@Antonette) - Shanna@melissa.tv
   • Clementine Bauch (@Samantha) - Nathan@yesenia.net

📋 2. Fetching details for first user...
✅ User Details for Leanne Graham:
   📧 Email: Sincere@april.biz
   📱 Phone: 1-770-736-8031 x56442
   🌐 Website: hildegard.org
   🏢 Company: Romaguera-Crona
   📍 Address: Kulas Light, Apt. 556, Gwenborough 92998-3874

📋 3. Creating a new user...
✅ Created user: John Doe (ID: 11)

📋 4. Updating the created user...
✅ Updated user: John Doe Updated
   📧 New email: john.doe.updated@example.com
   🌐 New website: updated.johndoe.dev

📋 5. Advanced pattern - User with details...
✅ Combined data for Leanne Graham:
   📧 Email: Sincere@april.biz
   🏢 Company: Romaguera-Crona

📋 6. Batch operation - Multiple users with details...
✅ Retrieved details for 3 users:
   • Leanne Graham: Romaguera-Crona
   • Ervin Howell: Deckow-Crist
   • Clementine Bauch: Romaguera-Jacobson

🎉 Advanced Networking Example completed successfully!
```

## Architecture Patterns Demonstrated

### 1. Service Layer Pattern
- Clean separation between data models and business logic
- Protocol-oriented design with `AdvancedAsyncRequestable`
- Type-safe service composition

### 2. Repository Pattern
- Centralized data access through service methods
- Consistent error handling across all operations
- Reusable endpoint definitions

### 3. Master-Detail Pattern
- List view with summary data (`ResponseModel`)
- Detail view with complete data (`SecondaryResponseModel`)
- Efficient data loading strategies

### 4. CRUD Operations
- Create operations return full details
- Update operations return updated details
- Delete operations return summary for consistency
- Proper HTTP method usage (POST, PUT, DELETE)

## Error Handling

The example demonstrates comprehensive error handling:

```swift
do {
    let users = try await userService.getUsers()
} catch let error as NetworkError {
    switch error {
    case .httpError(let statusCode, _):
        print("HTTP Error: \(statusCode)")
    case .networkUnavailable:
        print("No internet connection")
    case .decodingError:
        print("Failed to parse response")
    default:
        print("Network error: \(error.message())")
    }
}
```

## API Used

This example uses the [JSONPlaceholder](https://jsonplaceholder.typicode.com/) API, which provides:
- RESTful endpoints for user management
- Realistic JSON responses
- No authentication required
- Reliable for testing and examples

## Next Steps

After understanding this advanced example, check out:
- [Image Operations](../ImageOperations/) - Image handling with caching
- [SwiftUI Integration](../SwiftUIIntegration/) - UI integration patterns
- [Error Handling](../ErrorHandling/) - Comprehensive error scenarios

## Files

- `Package.swift` - Swift Package configuration
- `Sources/AdvancedNetworking/main.swift` - Main example implementation
- `README.md` - This documentation