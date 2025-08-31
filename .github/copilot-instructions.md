# AsyncNet AI Coding Instructions

This codebase is a Swift networking library with comprehensive image handling, built for **iOS/iPadOS 18+ and macOS 15+** with **Swift 6 strict concurrency compliance** and full SwiftUI integration.

## Architecture Overview

AsyncNet follows a **protocol-oriented design** with modern Swift 6 patterns and these core service boundaries:

- **Network Layer**: `AsyncRequestable` protocol + `Endpoint` definitions in `/base/` and `/endpoints/`
-- **Image Operations**: `ImageService` is actor-based and provided via dependency injection in `/services/`, with comprehensive upload/download, caching, and SwiftUI integration
- **SwiftUI Integration**: Complete view modifier suite in `/extensions/SwiftUIExtensions.swift` with async state management
- **Error Handling**: Centralized `NetworkError` enum with Sendable conformance and upload-specific cases
- **Platform Abstraction**: Cross-platform support via `PlatformImage` typealias and conditional compilation

### Key Architectural Decisions

**Swift 6 Compliance**: Built for strict concurrency with `@MainActor` isolation, `Sendable` conformance, and region analysis optimization. The library targets **iOS 18+/macOS 15+** to leverage latest platform concurrency improvements.

**Platform Abstraction**: Uses `PlatformImage` typealias (`UIImage` on iOS, `NSImage` on macOS) with conditional compilation via `#if canImport(UIKit)` blocks. NSImage extensions provide UIImage-compatible APIs.

**Concurrency Model**: `ImageService` is actor-based for proper isolation and thread safety. All image operations happen through actor-isolated methods with custom URLSession for background networking.

**Service Pattern**: `ImageService` uses dependency injection and actor isolation, while networking uses protocol composition through `AsyncRequestable` with Sendable constraints. Services are designed for testability and proper isolation.

## Critical Development Patterns

### 1. Endpoint Definition Pattern
```swift
struct YourEndpoint: Endpoint {
    var scheme: URLScheme = .https
    var host: String = "api.example.com"
    var path: String = "/endpoint"
    var method: RequestMethod = .get
    var headers: [String: String]? = ["Content-Type": "application/json"]
    var body: Data? = nil
    var queryItems: [URLQueryItem]? = nil
    var timeoutDuration: Duration? = .seconds(30)
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
    var headers: [String: String]? = ["Content-Type": "application/json"]
    var timeoutDuration: Duration? = .seconds(30)
    
    // Encode the Encodable body to Data
    var body: Data? {
        try? JSONEncoder().encode(request)
    }
    
    var queryItems: [URLQueryItem]? = nil
}
```

### 2. Service Implementation Pattern (Swift 6 Compliant)
```swift
class YourService: AsyncRequestable {
    // Generic method that accepts any Endpoint type
    func sendTypedRequest<T: Decodable & Sendable, E: Endpoint>(
        to endpoint: E,
        responseModel: T.Type
    ) async throws -> T {
        return try await sendRequest(to: endpoint)
    }
    
    // Convenience method for common GET requests
    func fetchData<T: Decodable & Sendable, E: Endpoint>(
        from endpoint: E,
        responseType: T.Type
    ) async throws -> T {
        return try await sendRequest(to: endpoint)
    }
    
    // Example with typed request body - caller provides the endpoint
    func createUser(name: String, email: String) async throws -> User {
        let request = CreateUserRequest(name: name, email: email)
        let endpoint = CreateUserEndpoint(request: request)
        return try await sendRequest(to: endpoint)
    }
    
    // Flexible method for any endpoint - maximum reusability
    func performRequest<T: Decodable & Sendable>(
        _ endpoint: some Endpoint,
        expecting responseType: T.Type
    ) async throws -> T {
        return try await sendRequest(to: endpoint)
    }
    
    // Usage examples:
    func exampleUsage() async throws {
        // Using specific endpoint types
        let user = try await createUser(name: "John", email: "john@example.com")
        
        // Using generic method with any endpoint
        let endpoint = YourEndpoint()
        let data: SomeResponse = try await performRequest(endpoint, expecting: SomeResponse.self)
        
        // Using convenience method
        let anotherData: AnotherResponse = try await fetchData(from: endpoint, responseType: AnotherResponse.self)
    }
}
```

### 3. Cross-Platform Image Handling
Always use `PlatformImage` type, never `UIImage`/`NSImage` directly. The codebase handles platform differences automatically through conditional compilation and NSImage extensions.

### 4. SwiftUI Integration Pattern
View modifiers follow this naming: `.asyncImage()`, `.imageUploader()`, `AsyncNetImageView` - they wrap underlying `ImageService` calls with proper state management and loading states.

### 5. Image Upload Patterns
// Note: ImageService upload APIs are Data-based. Always convert PlatformImage (UIImage/NSImage) to Data before sending to the actor. Crossing actor boundaries with non-Sendable types (such as PlatformImage) is not allowed; use Data or a Sendable CGImage wrapper for all actor interactions.

// Cross-platform image conversion: Use platformImageToData() helper instead of calling jpegData directly on PlatformImage
// This ensures compatibility between iOS (UIImage.jpegData) and macOS (NSImage via NSBitmapImageRep)
```swift
// Convert PlatformImage to Data before upload
guard let imageData = platformImageToData(platformImage, compressionQuality: 0.8) else {
    throw NetworkError.imageProcessingFailed
}
```

### 6. Swift 6 Actor Patterns
`ImageService` is actor-based and provided via dependency injection. All image operations are actor-isolated and concurrency-safe. Example usage:
```swift
import SwiftUI

public actor ImageService {
    private let imageCache: NSCache<NSString, NSData>
    private let urlSession: URLSession

    public init(cacheConfiguration: CacheConfiguration = .default) {
        // Dependency-injectable initialization
    }

    // Concurrency-safe: return Data (Sendable)
    public func fetchImageData(from urlString: String) async throws -> Data {
        // Actor-isolated implementation
    }
}

@MainActor
func platformImage(from data: Data) -> PlatformImage? {
    PlatformImage(data: data)
}

struct ContentView: View {
    let imageService: ImageService

    @State private var image: PlatformImage?

    init(imageService: ImageService = ImageService()) {
        self.imageService = imageService
    }

    var body: some View {
        // ...existing code...
        VStack {
            if let image = image {
                SwiftUI.Image(platformImage: image)
            } else {
                ProgressView()
            }
        }
        .task {
            do {
                let data = try await imageService.fetchImageData(from: "https://example.com/image.jpg")
                if Task.isCancelled { return }
                let loadedImage = await platformImage(from: data)
                await MainActor.run {
                    image = loadedImage
                }
            } catch {
                // Handle error (e.g., show error UI)
            }
        }
        // ...existing code...
    }
}
```
// Note: Always cross actor boundaries with Sendable types (Data, CGImage, etc). Use @MainActor helpers for UI conversion to PlatformImage.
// SwiftUI.Image extension available: SwiftUI.Image(platformImage:) provides cross-platform Image creation from PlatformImage (UIImage/NSImage)
````
### 7. Request Body Serialization Pattern
Always use type-safe `Encodable` models for request bodies instead of raw dictionaries. The `Endpoint` protocol supports `body: Data?`, so encode your models to JSON:

```swift
// ✅ Type-safe approach
struct LoginRequest: Encodable {
    let username: String
    let password: String
}

struct LoginEndpoint: Endpoint {
    let credentials: LoginRequest
    
    var body: Data? {
        do {
            return try JSONEncoder().encode(credentials)
        } catch {
            // Log encoding error for debugging - in production, consider using a logging framework
            print("Failed to encode LoginRequest: \(error.localizedDescription)")
            // Return nil to indicate encoding failure - caller should handle this appropriately
            return nil
        }
    }
    // ... other properties
}

// ❌ Avoid ad-hoc dictionaries
let body: [String: String] = ["username": "user", "password": "pass"]
// This loses type safety and refactoring support
```

**Serialization Best Practices:**
- Use `JSONEncoder()` for REST APIs with `application/json` content type
- Handle encoding errors explicitly with do/catch instead of `try?` to surface failures
- When `body` returns `nil` due to encoding failure, log the error and handle appropriately
- Consider custom `JSONEncoder` configuration for date formatting, key encoding, etc.
- For binary data (images, files), use the raw `Data` directly without encoding
- Test your `Encodable` models to ensure they serialize correctly
- Callers should check for `nil` body and handle encoding failures gracefully