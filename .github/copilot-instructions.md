# Blend AI Coding Instructions

This codebase is a Swift networking library with comprehensive image handling, built for **iOS/iPadOS 18+ and macOS 15+** with **Swift 6 strict concurrency compliance** and full SwiftUI integration.

## Prerequisites

**Development Environment Requirements:**

- **Xcode**: 16.0 or later (required for Swift 6 support)
- **Swift**: 6.0 or later (strict concurrency, Sendable checks, region-based isolation)
- **iOS Deployment Target**: 18.0+ (iPadOS 18.0+ included)
- **macOS Deployment Target**: 15.0+

**Swift 6 Enforcement Requirements:**

- **Package.swift**: Add `// swift-tools-version: 6.0` at the top of the file to enforce Swift 6 toolchain, and include a platforms entry locking iOS to v18 and macOS to v15:
  ```swift
  // swift-tools-version: 6.0
  import PackageDescription

  let package = Package(
      name: "YourPackage",
      platforms: [
          .iOS(.v18),
          .macOS(.v15)
      ],
      targets: [
          .target(
              name: "YourTarget",
              swiftSettings: [
                  .swiftLanguageMode(.v6)  // Enforce Swift 6 language mode for strict concurrency
              ]
          ),
          .testTarget(
              name: "YourTargetTests",
              dependencies: ["YourTarget"],
              swiftSettings: [
                  .swiftLanguageMode(.v6)  // Enforce Swift 6 language mode for tests
              ]
          )
      ]
  )
  ```

## Architecture Overview

Blend follows a **protocol-oriented design** with modern Swift 6 patterns and these core service boundaries:

- **Network Layer**: `AsyncRequestable` and `AdvancedAsyncRequestable` protocols + `Endpoint` definitions in `/Core/Protocols/` and `/Core/Networking/`
  - **Basic Networking**: `AsyncRequestable` for simple services with single response types
  - **Advanced Networking**: `AdvancedAsyncRequestable` for complex services requiring master-detail patterns, CRUD operations, and multiple response types
  - **Image Operations**: `ImageService` is actor-based and provided via dependency injection in `/Image/Service/`, with comprehensive upload/download, caching, and SwiftUI integration
- **SwiftUI Integration**: Complete view modifier suite in `/UI/SwiftUI/SwiftUIExtensions.swift` with async state management
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
    var timeoutDuration: Duration? = .seconds(30) // Maps to URLRequest.timeoutInterval — per-request idle timeout (resets on data arrival)
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
    var timeoutDuration: Duration? = .seconds(30) // Maps to URLRequest.timeoutInterval — per-request idle timeout (resets on data arrival)
    
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
- **Per-Request Timeout** (`timeoutDuration`): Use for request-specific timeouts (e.g., long uploads need longer timeouts). Maps to `URLRequest.timeoutInterval` which defaults to 60 seconds and is an **idle timeout** that resets whenever data arrives. Setting it to `0` disables the idle timeout entirely (no per-request idle timeout).
- **Session-Wide Timeout** (`URLSessionConfiguration.timeoutIntervalForRequest`): Use for consistent idle timeouts across all requests. Defaults to 60 seconds (idle timeout that resets on data arrival).
- **Resource Timeout** (`URLSessionConfiguration.timeoutIntervalForResource`): Controls the total time for the entire resource transfer (including redirects, authentication, and data transfer). Defaults to 7 days. This is crucial for long uploads/downloads where per-request idle timeouts may reset before the transfer completes.
- **Zero Timeout Behavior**: Setting `URLRequest.timeoutInterval` to `0` disables the idle timeout (no per-request idle timeout), but the session's `timeoutIntervalForRequest` (default: 60s) still applies. Avoid using `0` to express "infinite" timeout - use explicit large values instead.
- **Background Session Behavior**: Background sessions will retry and resume on transient errors or idle timeouts, and only fail once the resource timeout (`timeoutIntervalForResource`) expires. Long transfers are governed by the resource timeout, not idle timeouts.
- **Duration Conversion**: Use this portable helper to convert Swift `Duration` to `TimeInterval`:
  ```swift
  /// Portable Duration to TimeInterval conversion
  /// - Parameter duration: Swift Duration to convert
  /// - Returns: TimeInterval representation (clamped to ≥ 0 to avoid negative timeout semantics)
  func timeInterval(from duration: Duration) -> TimeInterval {
      let components = duration.components
      let totalSeconds = Double(components.seconds) + Double(components.attoseconds) / 1e18
      return max(0, totalSeconds)  // Clamp to non-negative to prevent negative timeout semantics
  }
  ```
- **Request Timeout Setting**: Only set `URLRequest.timeoutInterval` when `endpoint.timeoutDuration` is non-nil:
  ```swift
  // Only set timeout when endpoint specifies one
  if let timeoutDuration = endpoint.timeoutDuration {
      request.timeoutInterval = timeInterval(from: timeoutDuration)
  }
  // Leave unset when nil so session's timeoutIntervalForRequest (default: 60s idle) applies
  ```
- **Nil Handling**: When `timeoutDuration` is `nil`, leave `URLRequest.timeoutInterval` unset so the session's `timeoutIntervalForRequest` (default: 60 seconds idle timeout) is used as the fallback. Setting it to `0` disables idle timeout but session defaults still apply.
- **Session Configuration Example**: Configure both per-request and resource timeouts:
  ```swift
  let configuration = URLSessionConfiguration.default
  configuration.timeoutIntervalForRequest = 30.0  // 30s per-request idle timeout
  configuration.timeoutIntervalForResource = 300.0 // 5min total resource timeout (for large uploads)
  let session = URLSession(configuration: configuration)
  ```
- **Best Practice**: Prefer per-request timeouts for fine-grained control, use session timeouts for global defaults. For large file uploads/downloads, ensure `timeoutIntervalForResource` is sufficiently long. Background sessions provide resilience against transient failures but are ultimately bounded by the resource timeout.