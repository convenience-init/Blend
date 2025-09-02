# AsyncNet AI Coding Instructions

This codebase is a Swift networking library with comprehensive image handling, built for **iOS/iPadOS 18+ and macOS 15+** with **Swift 6 strict concurrency compliance** and full SwiftUI integration.

## Prerequisites

**Development Environment Requirements:**

- **Xcode**: 16.0 or later (required for Swift 6 support)
- **Swift**: 6.0 or later (strict concurrency, Sendable checks, region-based isolation)
- **iOS Deployment Target**: 18.0+ (iPadOS 18.0+ included)
- **macOS Deployment Target**: 15.0+

**Swift 6 Enforcement Requirements:**

- **Package.swift**: Add `// swift-tools-version: 6.0` at the top of the file to enforce Swift 6 toolchain
- **Build Settings**: Enable strict concurrency checking in Xcode project settings:
  - Set "Strict Concurrency Checking" to "Complete"
  - Enable "Sendable Checking" for all targets
- **Xcode Flags**: Use these additional compiler flags for maximum concurrency safety:
  - `-Xfrontend -strict-concurrency=complete` (matches Xcode “Strict Concurrency: Complete”)
  - `-Xfrontend -warn-concurrency` (additional concurrency warnings)
  - `-Xfrontend -enable-actor-data-race-checks` (optional; prefer Debug-only due to overhead)
**CI/CD Requirements:**
- Use Xcode 16+ in GitHub Actions or other CI systems
- Ensure SwiftPM resolves to Swift 6 toolchain
- Test on iOS 18+ and macOS 15+ simulators/devices
- **CI Build Commands**: Use these explicit commands in your CI matrix/job:
  - `swift build --configuration Debug \
     -Xswiftc -Xfrontend -Xswiftc -strict-concurrency=complete \
     -Xswiftc -Xfrontend -Xswiftc -warn-concurrency \
     -Xswiftc -Xfrontend -Xswiftc -enable-actor-data-race-checks`
  - `swift test --configuration Debug \
     -Xswiftc -Xfrontend -Xswiftc -strict-concurrency=complete \
     -Xswiftc -Xfrontend -Xswiftc -warn-concurrency \
     -Xswiftc -Xfrontend -Xswiftc -enable-actor-data-race-checks`

> **Toolchain Note**: Swift 6 features like `@MainActor` isolation, `Sendable` conformance checking, and region-based memory analysis require Xcode 16+. Using older toolchains will result in compilation errors or runtime issues.

## Architecture Overview

AsyncNet follows a **protocol-oriented design** with modern Swift 6 patterns and these core service boundaries:

- **Network Layer**: `AsyncRequestable` and `AdvancedAsyncRequestable` protocols + `Endpoint` definitions in `/base/` and `/endpoints/`
  - **Basic Networking**: `AsyncRequestable` for simple services with single response types
  - **Advanced Networking**: `AdvancedAsyncRequestable` for complex services requiring master-detail patterns, CRUD operations, and multiple response types
  - **Image Operations**: `ImageService` is actor-based and provided via dependency injection in `/services/`, with comprehensive upload/download, caching, and SwiftUI integration
- **SwiftUI Integration**: Complete view modifier suite in `/extensions/SwiftUIExtensions.swift` with async state management
- **Error Handling**: Centralized `NetworkError` enum with Sendable conformance and upload-specific cases
- **Platform Abstraction**: Cross-platform support via `PlatformImage` typealias and conditional compilation

### Key Architectural Decisions

**Swift 6 Compliance**: Built for strict concurrency with `@MainActor` isolation, `Sendable` conformance, and region analysis optimization. The library targets **iOS 18+/macOS 15+** to leverage latest platform concurrency improvements.

**Platform Abstraction**: Uses `PlatformImage` typealias (`UIImage` on iOS, `NSImage` on macOS) with conditional compilation via `#if canImport(UIKit)` blocks. NSImage extensions provide UIImage-compatible APIs.

**Concurrency Model**: `ImageService` is actor-based for proper isolation and thread safety. All image operations happen through actor-isolated methods with custom URLSession for background networking.

**Service Pattern**: `ImageService` uses dependency injection and actor isolation, while networking uses protocol composition through `AsyncRequestable`/`AdvancedAsyncRequestable` with Sendable constraints. Services are designed for testability and proper isolation.

**Protocol Hierarchy**:
```
AsyncRequestable (Basic - Single Response Type)
  ↳ AdvancedAsyncRequestable (Enhanced - Dual Response Types)
```

### Protocol Usage Guidelines

**Choose `AsyncRequestable` when:**
- Your service only needs one response type
- Simple CRUD operations with consistent response formats
- Basic networking requirements

**Choose `AdvancedAsyncRequestable` when:**
- Master-detail patterns (list view + detail view)
- CRUD operations with different response types for different operations
- Generic service composition requirements
- Type-safe service hierarchies with multiple response contracts

### AdvancedAsyncRequestable Features

**Associated Types:**
- `ResponseModel`: Primary response type (typically for list/collection operations)
- `SecondaryResponseModel`: Secondary response type (typically for detail/single-item operations)

**Convenience Methods:**
- `fetchList(from:)`: Type-safe list operations using `ResponseModel`
- `fetchDetails(from:)`: Type-safe detail operations using `SecondaryResponseModel`

**Example Usage:**
```swift
class UserService: AdvancedAsyncRequestable {
    typealias ResponseModel = [UserSummary]        // For user lists
    typealias SecondaryResponseModel = UserDetails // For user details
    
    func getUsers() async throws -> [UserSummary] {
        return try await fetchList(from: UsersEndpoint())
    }
    
    func getUserDetails(id: String) async throws -> UserDetails {
        return try await fetchDetails(from: UserDetailsEndpoint(userId: id))
    }
}
```

## Critical Development Patterns

### 1. Endpoint Definition Pattern
```swift
struct YourEndpoint: Endpoint {
    var scheme: URLScheme = .https
    var host: String = "api.example.com"
    var path: String = "/endpoint"
    var method: RequestMethod = .get
    var headers: [String: String]? = ["Accept": "application/json"] // Accept header for expected response type
    var body: Data? = nil
    var queryItems: [URLQueryItem]? = nil
    var timeoutDuration: Duration? = .seconds(30) // Maps to URLRequest.timeoutInterval — per-request timeout
}

// For POST/PUT requests with JSON bodies, use Encodable models:
struct CreateUserRequest: Encodable {
    let name: String
    let email: String
}

struct CreateUserEndpoint: Endpoint {
    let request: CreateUserRequest
    
    var scheme: URLScheme = .https
    var host: String = "api.example.com"
    var path: String = "/users"
    var method: RequestMethod = .post
    var headers: [String: String]? = ["Content-Type": "application/json"] // Content-Type for request body
    var timeoutDuration: Duration? = .seconds(30) // Maps to URLRequest.timeoutInterval — per-request timeout
    
    // Pre-encoded body stored as immutable Data - encoding happens once in init
    let body: Data?
    
    // Initialize with pre-encoded body to avoid repeated encoding and side effects
    init(request: CreateUserRequest, logger: Logger? = nil) throws {
        self.request = request
        do {
            self.body = try JSONEncoder().encode(request)
        } catch {
            // Surface encoding error via logger instead of print
            logger?.error("Failed to encode CreateUserRequest: \(error.localizedDescription)")
            throw error
        }
    }
    
    var queryItems: [URLQueryItem]? = nil
}
```

**Timeout Configuration Guidance:**
- **Per-Request Timeout** (`timeoutDuration`): Use for request-specific timeouts (e.g., long uploads need longer timeouts)
- **Session-Wide Timeout** (`URLSessionConfiguration.timeoutIntervalForRequest`): Use for consistent timeouts across all requests
- **Resource Timeout** (`URLSessionConfiguration.timeoutIntervalForResource`): Controls the total time for the entire resource transfer (including redirects, authentication, and data transfer). This is crucial for long uploads/downloads where `timeoutIntervalForRequest` may timeout before the transfer completes.
- **Zero Timeout Behavior**: A timeout value of `0` does NOT mean "no timeout" or infinite timeout. Instead, it causes `URLRequest`/`URLSession` to fall back to system default timeouts (typically 60 seconds for requests, 7 days for resources per Apple documentation). Avoid using `0` to express "infinite" timeout - use a clearly defined sentinel value (e.g., `Duration.seconds(86400)` for 24 hours) or explicit large timeout instead.
- **Duration Conversion**: Use this portable helper to convert Swift `Duration` to `TimeInterval`:
  ```swift
  /// Portable Duration to TimeInterval conversion
  /// - Parameter duration: Swift Duration to convert
  /// - Returns: TimeInterval representation (clamped to ≥ 0 to avoid negative timeout semantics)
  func timeInterval(from duration: Duration) -> TimeInterval {
      let components = duration.components
      let computedInterval = TimeInterval(components.seconds) + TimeInterval(components.attoseconds) / 1e18
      return max(0, computedInterval)  // Clamp to non-negative to prevent negative timeout semantics
  }
  ```
- **Request Timeout Setting**: Only set `URLRequest.timeoutInterval` when `endpoint.timeoutDuration` is non-nil:
  ```swift
  // Only set timeout when endpoint specifies one
  if let timeoutDuration = endpoint.timeoutDuration {
      request.timeoutInterval = timeInterval(from: timeoutDuration)
  }
  // Leave unset when nil so session's timeoutIntervalForRequest (default: 60s) applies
  ```
- **Nil Handling**: When `timeoutDuration` is `nil`, leave `URLRequest.timeoutInterval` unset so the session's `timeoutIntervalForRequest` (default: 60 seconds) is used as the fallback. Setting it to `0` causes fallback to system defaults, not infinite timeout.
- **Session Configuration Example**: Configure both per-request and resource timeouts:
  ```swift
  let configuration = URLSessionConfiguration.default
  configuration.timeoutIntervalForRequest = 30.0  // 30s per-request timeout
  configuration.timeoutIntervalForResource = 300.0 // 5min total resource timeout (for large uploads)
  let session = URLSession(configuration: configuration)
  ```
- **Best Practice**: Prefer per-request timeouts for fine-grained control, use session timeouts for global defaults. For large file uploads/downloads, ensure `timeoutIntervalForResource` is sufficiently long. Avoid using `0` for "infinite" timeouts - use explicit large values instead.