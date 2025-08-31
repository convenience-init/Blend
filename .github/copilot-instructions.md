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
    var method: RequestMethod = .GET
    var headers: [String: String]? = ["Content-Type": "application/json"]
    var body: Data? = nil
    var queryItems: [URLQueryItem]? = nil
    var contentType: String? = "application/json"
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
    var contentType: String? = "application/json"
    var timeoutDuration: Duration? = .seconds(30)
    
    // Encode the Encodable body to Data
    var body: Data? {
        try? JSONEncoder().encode(request)
    }
    
    var queryItems: [URLQueryItem]? = nil
    var timeout: TimeInterval? = nil
}
```

### 2. Service Implementation Pattern (Swift 6 Compliant)
```swift
class YourService: AsyncRequestable {
    // Generic method that accepts any Endpoint type
    func sendRequest<T: Decodable & Sendable, E: Endpoint>(
        to endpoint: E,
        responseModel: T.Type
    ) async throws -> T {
        return try await sendRequest(to: endpoint, responseModel: responseModel)
    }
    
    // Convenience method for common GET requests
    func fetchData<T: Decodable & Sendable, E: Endpoint>(
        from endpoint: E,
        responseType: T.Type
    ) async throws -> T {
        return try await sendRequest(to: endpoint, responseModel: responseType)
    }
    
    // Example with typed request body - caller provides the endpoint
    func createUser(name: String, email: String) async throws -> User {
        let request = CreateUserRequest(name: name, email: email)
        let endpoint = CreateUserEndpoint(request: request)
        return try await sendRequest(to: endpoint, responseModel: User.self)
    }
    
    // Flexible method for any endpoint - maximum reusability
    func performRequest<T: Decodable & Sendable>(
        _ endpoint: some Endpoint,
        expecting responseType: T.Type
    ) async throws -> T {
        return try await sendRequest(to: endpoint, responseModel: responseType)
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
```swift
// Dependency-injected image service (actor-based)
let imageService = injectedImageService

// Convert PlatformImage to Data before upload
guard let imageData = platformImage.jpegData(compressionQuality: 0.8) else {
    throw NetworkError.imageProcessingFailed
}

// Multipart form upload (Data-based)
let config = ImageService.UploadConfiguration(
    fieldName: "photo",
    fileName: "image.jpg",
    compressionQuality: 0.8,
    additionalFields: ["userId": "123"]
)
let multipartResponse = try await imageService.uploadImageMultipart(imageData, to: url, configuration: config)

// Base64 JSON upload (Data-based)
let base64Response = try await imageService.uploadImageBase64(imageData, to: url, configuration: config)
```

### 6. Swift 6 Actor Patterns
`ImageService` is actor-based and provided via dependency injection. All image operations are actor-isolated and concurrency-safe. Example usage:
```swift
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
                Image(platformImage: image)
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

## Error Handling Conventions

Use the centralized `NetworkError` enum - **never throw generic errors**. Key cases:
- `.invalidURL(String)` for malformed URLs
- `.uploadFailed(String)` for image upload failures  
- `.badMimeType(String)` for unsupported image formats
- `.cacheError(String)` for cache-related issues
- `.imageProcessingFailed` for image conversion failures

Pattern: `catch let error as NetworkError` for specific handling, with `error.message()` for user-friendly strings.

**Swift 6 Compliance**: `NetworkError` conforms to `Sendable` and includes helper methods:
```swift
// Wrap generic errors safely
throw NetworkError.wrap(someError)

// Create custom errors with context
throw NetworkError.customError("Upload failed", details: "Invalid image format")
```

## Build & Test Workflows

**Standard Commands**:
```bash
# Build the package
swift build

# Run tests (currently minimal - expand as needed)
swift test

# Generate documentation
swift package generate-documentation
```

**Platform Testing**: The library targets iOS 18+/macOS 15+ for simplified Swift 6 compliance. Test on both platforms as concurrency behavior and performance optimizations can differ.

**Swift 6 Mode**: Always build with strict concurrency checking:
```bash
# Build with strict concurrency (enabled by default with Swift 6)
swift build -Xswiftc -strict-concurrency=complete
```

## Integration Points & Dependencies

**Zero External Dependencies**: This is intentional - the library uses only Foundation, UIKit/Cocoa, and SwiftUI.

**URLSession Configuration**: `ImageService` uses custom session with 10MB memory cache + 100MB disk cache. Don't bypass this - extend the service instead.

**Concrete Setup Example:**
```swift
// Create custom cache with specific capacities
let cache = URLCache(
    memoryCapacity: 10 * 1024 * 1024,  // 10MB memory cache
    diskCapacity: 100 * 1024 * 1024,   // 100MB disk cache
    diskPath: "AsyncNetCache"          // Custom cache directory
)

// Configure URLSession with cache and cache policy
let configuration = URLSessionConfiguration.default
configuration.urlCache = cache
configuration.requestCachePolicy = .returnCacheDataElseLoad

// Create URLSession with custom configuration
let session = URLSession(configuration: configuration)

// Extend ImageService to use this session
extension ImageService {
    convenience init(customSession: URLSession) {
        // Initialize with custom session instead of default
        // This allows dependency injection of the configured session
    }
}
```

**Cache Policy Explanation:**
- `.returnCacheDataElseLoad` prioritizes cached data but fetches from network if cache miss
- Memory cache (10MB) provides fast access to recently used images
- Disk cache (100MB) persists images across app launches
- Custom disk path "AsyncNetCache" keeps cache isolated from system caches

**SwiftUI Integration**: Complete SwiftUI integration through view modifiers and components. All SwiftUI features are available since the minimum target platforms include comprehensive SwiftUI support.

**Phase-Based Development**: The library follows a structured 5-phase development plan:
- **Phase 1 (Complete)**: Image features, SwiftUI integration, basic Swift 6 patterns
- **Phase 2 (Next)**: Full Swift 6 actor compliance and concurrency optimization  
- **Phase 3**: iOS 18+/macOS 15+ platform features and performance optimization
- **Phase 4**: Comprehensive testing and documentation
- **Phase 5**: Production polish and release preparation

## Critical Files for Understanding Data Flow

1. **`AsyncRequestable.swift`** - Core networking protocol with URLRequest building logic
2. **`ImageService.swift`** - Image operations hub with caching strategy and actor-based implementation
3. **`SwiftUIExtensions.swift`** - View modifier implementations showing async state management patterns
4. **`NetworkError.swift`** - Complete error taxonomy and Sendable error handling patterns
5. **`Swift6_Compliance_Guide.md`** - Comprehensive patterns for Swift 6 migration and concurrency
6. **`AsyncNet_Master_Action_Plan.md`** - Project roadmap and architectural evolution planning

## Development Gotchas

**Actor Isolation**: `ImageService` is actor-based and provided via dependency injection. Avoid singleton patterns and always use dependency injection for strict concurrency and testability.

**Platform Compilation**: Use conditional compilation blocks for platform-specific code, never runtime checks:
```swift
#if canImport(UIKit)
// iOS/iPadOS specific code
#elseif canImport(AppKit)
// macOS specific code
#endif
```

**Cache Keys**: Image URLs are used as cache keys - ensure consistent URL formatting throughout the app.

**SwiftUI State**: View modifiers manage their own `@State` - don't duplicate state management in consuming views.

**Swift 6 Migration**: When moving to Phase 2, follow these priorities:
1. Convert `ImageService` to full actor isolation with dependency injection
2. Remove singleton patterns in favor of injectable services
3. Ensure all types crossing isolation boundaries are `Sendable`
4. Use `sending` keyword for ownership transfer
5. Leverage iOS 18+/macOS 15+ concurrency optimizations

**Dependency Injection**: Design services for injection rather than global access:
```swift
// ❌ Avoid singleton patterns
// ImageService.shared.fetchImage(from: url)

// ✅ Use dependency injection and strict Sendable boundaries
let imageService = ImageService()
let data = try await imageService.fetchImageData(from: url)
let image = await platformImage(from: data)


// ✅ Use dependency injection and strict Sendable boundaries
class ImageRepository {
    private let imageService: ImageService

    init(imageService: ImageService) {
        self.imageService = imageService
    }

    // Return Data (Sendable) from actor/service context
    func loadImageData(from url: String) async throws -> Data {
        return try await imageService.fetchImageData(from: url)
    }
}

// At the call site, convert Data to PlatformImage on the main actor:
@MainActor
func platformImage(from data: Data) -> PlatformImage? {
    PlatformImage(data: data)
}

// Usage:
let data = try await imageRepository.loadImageData(from: url)
let image = await platformImage(from: data)
```

**Upload Configuration**: Always use `ImageService.UploadConfiguration` for structured upload parameters - supports both multipart and base64 uploads with additional fields.

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
        try? JSONEncoder().encode(credentials)
    }
    // ... other properties
}

// ❌ Avoid ad-hoc dictionaries
let body: [String: String] = ["username": "user", "password": "pass"]
// This loses type safety and refactoring support
```

**Serialization Best Practices:**
- Use `JSONEncoder()` for REST APIs with `application/json` content type
- Handle encoding errors gracefully (the `body` property can return `nil`)
- Consider custom `JSONEncoder` configuration for date formatting, key encoding, etc.
- For binary data (images, files), use the raw `Data` directly without encoding
- Test your `Encodable` models to ensure they serialize correctly

When adding features, follow the established patterns: protocol-first design, centralized error handling, platform abstraction, and SwiftUI integration through view modifiers.