# AsyncNet

A powerful Swift networking library with comprehensive image handling capabilities, built for iOS, iPadOS, and macOS with full SwiftUI support.

## Features

**Modern Swift Concurrency** - Built with async/await and Swift 6 compliance  
**Cross-Platform** - Supports iOS 18+, iPadOS 18+, and macOS 15+  
**Complete Image Solution** - Download, upload, and cache images with ease  
**SwiftUI Integration** - Native SwiftUI view modifiers and components  
**High Performance** - Intelligent caching with configurable limits  
**Type Safe** - Protocol-oriented design with comprehensive error handling  

## Installation

### Swift Package Manager

Add AsyncNet to your project through Xcode:

1. File → Add Package Dependencies...
2. Enter the repository URL: `https://github.com/convenience-init/async-net`
3. Select your version requirements

Or add it to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/convenience-init/async-net", from: "1.0.0")
]
```

## Platform Support

- **iOS**: 18.0+ (includes iPadOS 18.0+)
- **macOS**: 15.0+

## Quick Start

### Basic Network Request

```swift
import AsyncNet

// Define your endpoint
struct UsersEndpoint: Endpoint {
    var scheme: URLScheme = .https
    var host: String = "api.example.com"
    var path: String = "/users"
    var method: RequestMethod = .GET
    var headers: [String: String]? = ["Content-Type": "application/json"]
    var body: Data? = nil
    var queryItems: [URLQueryItem]? = nil
    var contentType: String? = "application/json"
    var timeout: TimeInterval? = 30
}

// Create a service that implements AsyncRequestable
class UserService: AsyncRequestable {
    func getUsers() async throws -> [User] {
        return try await sendRequest(to: UsersEndpoint())
    }
}
```

### Image Operations

#### Download Images

```swift
import AsyncNet

// Download an image
let imageService = ImageService()
let data = try await imageService.fetchImageData(from: "https://example.com/image.jpg")

// For SwiftUI
let data = try await imageService.fetchImageData(from: "https://example.com/image.jpg")
let swiftUIImage = ImageService.swiftUIImage(from: data)

// Check cache first
if let cachedImage = imageService.cachedImage(forKey: "https://example.com/image.jpg") {
    // Use cached image
}
```

#### Upload Images

```swift
import AsyncNet

// Dependency-injected image service
let imageService = ImageService()

// Example PlatformImage (replace with actual image loading)
let uploadURL = URL(string: "https://api.example.com/upload")!
let platformImage: PlatformImage = ... // Load or create your PlatformImage here

// Cross-platform helpers: jpegData and pngData are available on PlatformImage (UIImage/NSImage)
let imageData: Data
if let jpeg = platformImage.jpegData(compressionQuality: 0.8) {
    imageData = jpeg
} else if let png = platformImage.pngData() {
    imageData = png
} else {
    throw NetworkError.imageProcessingFailed
}

let uploadConfig = ImageService.UploadConfiguration(
    fieldName: "photo",
    fileName: "profile.jpg",
    compressionQuality: 0.8,
    additionalFields: ["userId": "123"]
)

// Multipart form upload (Data-based)
let multipartResponse = try await imageService.uploadImageMultipart(imageData, to: uploadURL, configuration: uploadConfig)

// Base64 upload (Data-based)
let base64Response = try await imageService.uploadImageBase64(imageData, to: uploadURL, configuration: uploadConfig)
```

### SwiftUI Integration

#### Async Image Loading

```swift
import SwiftUI
import AsyncNet

struct ProfileView: View {
    let imageURL: String
    let imageService: ImageService // Dependency injection required
    
    var body: some View {
        AsyncNetImageView(
            url: imageURL,
            imageService: imageService
        )
        .frame(width: 200, height: 200)
    }
}
```

#### Async Image Loading (Modern Pattern)

```swift
import SwiftUI
import AsyncNet

struct ProfileView: View {
    let imageURL: String
    // Recommended DI: pass via init (constructor injection), or use Environment
    // Example: init(imageService: ImageService) { self.imageService = imageService }
    // Or: @Environment(ImageService.self) var imageService
    let imageService: ImageService // Dependency injection required

    var body: some View {
        Rectangle()
            .frame(width: 200, height: 200)
            .asyncImage(
                from: imageURL,
                imageService: imageService,
                placeholder: ProgressView().controlSize(.large),
                errorView: Image(systemName: "person.circle.fill")
            )
    }
}
```

#### Environment-Based Dependency Injection

```swift
import SwiftUI
import AsyncNet

// Define environment key
private struct ImageServiceKey: EnvironmentKey {
    static let defaultValue: ImageService = ImageService()
}

extension EnvironmentValues {
    var imageService: ImageService {
        get { self[ImageServiceKey.self] }
        set { self[ImageServiceKey.self] = newValue }
    }
}

// Usage in views
struct ProfileView: View {
    @Environment(\.imageService) private var imageService
    
    var body: some View {
        AsyncNetImageView(
            url: "https://example.com/profile.jpg",
            imageService: imageService
        )
        .frame(width: 200, height: 200)
    }
}

// Setup in App with dependency injection
@main
struct MyApp: App {
    // Create service with custom configuration
    let imageService = ImageService(
        cacheCountLimit: 200,
        cacheTotalCostLimit: 100 * 1024 * 1024
    )
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.imageService, imageService)
        }
    }
}

// Alternative: Factory pattern for different environments
class ServiceFactory {
    static func makeImageService(for environment: AppEnvironment) -> ImageService {
        switch environment {
        case .development:
            return ImageService(cacheCountLimit: 50, cacheTotalCostLimit: 10 * 1024 * 1024)
        case .production:
            return ImageService(cacheCountLimit: 200, cacheTotalCostLimit: 100 * 1024 * 1024)
        }
    }
}
```

### Dependency Injection Patterns

#### Constructor Injection (Recommended)

```swift
struct ProfileView: View {
    let imageService: ImageService
    
    init(imageService: ImageService = ImageService()) {
        self.imageService = imageService
    }
    
    var body: some View {
        AsyncNetImageView(
            url: "https://example.com/profile.jpg",
            imageService: imageService
        )
        .frame(width: 200, height: 200)
    }
}

// Modern pattern with @Observable (iOS 18+)
@Observable
class ViewModel {
    let imageService: ImageService
    
    init(imageService: ImageService = ImageService()) {
        self.imageService = imageService
    }
}

struct ModernProfileView: View {
    @State private var viewModel: ViewModel
    
    init(imageService: ImageService = ImageService()) {
        _viewModel = State(wrappedValue: ViewModel(imageService: imageService))
    }
    
    var body: some View {
        AsyncNetImageView(
            url: "https://example.com/profile.jpg",
            imageService: viewModel.imageService
        )
        .frame(width: 200, height: 200)
    }
}
```

#### Environment Injection

```swift
// Modern Environment injection using EnvironmentKey
private struct ImageServiceKey: EnvironmentKey {
    static let defaultValue: ImageService = ImageService()
}

extension EnvironmentValues {
    var imageService: ImageService {
        get { self[ImageServiceKey.self] }
        set { self[ImageServiceKey.self] = newValue }
    }
}

// Usage in views
struct ProfileView: View {
    @Environment(\.imageService) private var imageService
    
    var body: some View {
        AsyncNetImageView(
            url: "https://example.com/profile.jpg",
            imageService: imageService
        )
        .frame(width: 200, height: 200)
    }
}

// Setup in App with dependency injection
@main
struct MyApp: App {
    // Create service with custom configuration
    let imageService = ImageService(
        cacheCountLimit: 200,
        cacheTotalCostLimit: 100 * 1024 * 1024
    )
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.imageService, imageService)
        }
    }
}

// Alternative: Factory pattern for different environments
class ServiceFactory {
    static func makeImageService(for environment: AppEnvironment) -> ImageService {
        switch environment {
        case .development:
            return ImageService(cacheCountLimit: 50, cacheTotalCostLimit: 10 * 1024 * 1024)
        case .production:
            return ImageService(cacheCountLimit: 200, cacheTotalCostLimit: 100 * 1024 * 1024)
        }
    }
}
```

#### Complete Image Component with Upload

```swift
import SwiftUI
import AsyncNet

struct ImageGalleryView: View {
    let imageService: ImageService // Dependency injection required

    var body: some View {
        VStack {
            AsyncNetImageView(
                url: "https://example.com/gallery/1.jpg",
                uploadURL: URL(string: "https://api.example.com/upload"),
                uploadType: .multipart,
                configuration: ImageService.UploadConfiguration(),
                onUploadSuccess: { data in
                    print("Upload successful: \(data)")
                },
                onUploadError: { error in
                    print("Upload failed: \(error)")
                },
                imageService: imageService
            )
            .frame(height: 300)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}
```

#### Image Upload with Progress

```swift
import SwiftUI
import AsyncNet

struct PhotoUploadView: View {
    @State private var selectedImage: PlatformImage?
    let imageService: ImageService // Dependency injection required
    
    var body: some View {
        VStack {
            if let image = selectedImage {
                Image(platformImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 200)
            }
            
            Button("Select Photo") {
                // Photo picker implementation
            }
            
            if let image = selectedImage {
                Button("Upload") {
                    Task {
                        do {
                            guard let imageData = image.jpegData(compressionQuality: 0.8) else {
                                print("Failed to convert image")
                                return
                            }
                            let config = ImageService.UploadConfiguration()
                            let response = try await imageService.uploadImageMultipart(
                                imageData,
                                to: URL(string: "https://api.example.com/photos")!,
                                configuration: config
                            )
                            print("Upload successful")
                        } catch {
                            print("Upload failed: \(error)")
                        }
                    }
                }
            }
        }
    }
}
```

---

#### Notes

- Always inject `ImageService` for strict concurrency and testability.
- Use `AsyncNetImageView` for robust SwiftUI integration with modern Swift 6 APIs.

```swift
do {
    // Modern error handling with NetworkError
    let image = try await imageService.fetchImageData(from: "https://example.com/image.jpg")
} catch let error as NetworkError {
    print("Network error: \(error.message)")
} catch {
    print("Unexpected error: \(error)")
}
```

### NetworkError Cases

AsyncNet provides comprehensive error handling through the `NetworkError` enum:

- **`.httpError(statusCode: Int, data: Data?)`**: HTTP errors with status code and optional response data
- **`.decodingError(underlyingDescription: String, data: Data?)`**: JSON decoding failures
- **`.networkUnavailable`**: Network connectivity issues
- **`.requestTimeout(duration: TimeInterval)`**: Request timeout errors
- **`.invalidEndpoint(reason: String)`**: Invalid URL or endpoint configuration
- **`.unauthorized`**: Authentication failures (401)
- **`.noResponse`**: No response received from server
- **`.badMimeType(String)`**: Unsupported image MIME type
- **`.uploadFailed(String)`**: Image upload failures
- **`.imageProcessingFailed`**: PlatformImage conversion failures
- **`.cacheError(String)`**: Cache operation failures
- **`.transportError(code: URLError.Code, underlying: URLError)`**: Low-level network transport errors

### Cache Management

```swift
import AsyncNet

let imageService = ImageService()

// Configure cache limits (these are set during initialization)
let imageService = ImageService(cacheCountLimit: 200, cacheTotalCostLimit: 100 * 1024 * 1024)

// Clear cache
await imageService.clearCache()

// Remove specific image
await imageService.removeFromCache(key: "https://example.com/image.jpg")

// Check if image is cached
let isCached = await imageService.isImageCached(forKey: "https://example.com/image.jpg")
```

### LRU Cache Implementation

AsyncNet includes a sophisticated **LRU (Least Recently Used) cache** implementation with the following features:

#### Key Features

- **O(1) Operations**: Constant-time cache access, insertion, and eviction
- **Dual-Layer Caching**: Separate caches for image data and decoded images
- **Time-Based Expiration**: Configurable cache entry lifetimes
- **Memory Management**: Automatic eviction based on count and memory limits
- **Thread-Safe**: Actor-isolated for strict concurrency compliance

#### Cache Architecture

```swift
// Custom LRU Node for O(1) doubly-linked list operations
private class LRUNode {
    let key: NSString
    var prev: LRUNode?
    var next: LRUNode?
    var timestamp: TimeInterval
}

// Cache configuration
public struct CacheConfiguration: Sendable {
    public let maxAge: TimeInterval     // Entry lifetime in seconds
    public let maxLRUCount: Int         // Maximum entries in LRU list
}
```

#### Cache Metrics & Monitoring

```swift
// Access cache performance metrics
let hits = await imageService.cacheHits
let misses = await imageService.cacheMisses
let hitRate = Double(hits) / Double(hits + misses)

// Monitor cache efficiency
print("Cache hit rate: \(hitRate * 100)%")
```

#### Advanced Cache Configuration

```swift
// Configure cache with custom settings
let imageService = ImageService(
    cacheCountLimit: 200,           // Max 200 entries
    cacheTotalCostLimit: 100 * 1024 * 1024  // Max 100MB
)

// Update cache configuration at runtime
let newConfig = ImageService.CacheConfiguration(
    maxAge: 1800,      // 30 minutes
    maxLRUCount: 150   // Max 150 entries
)
await imageService.updateCacheConfiguration(newConfig)
```

#### Cache Eviction Strategy

The LRU cache implements a **hybrid eviction strategy**:

1. **Time-Based Eviction**: Entries older than `maxAge` are automatically removed
2. **Count-Based Eviction**: When cache exceeds `maxLRUCount`, least recently used entries are evicted
3. **Memory-Based Eviction**: NSCache automatically evicts entries when memory limits are reached

#### Performance Characteristics

- **Lookup**: O(1) - Hash table access
- **Insertion**: O(1) - Doubly-linked list operations
- **Eviction**: O(1) - Tail removal from LRU list
- **Memory**: Bounded by configurable limits
- **Thread Safety**: Actor isolation ensures no race conditions

### Custom Upload Configuration

```swift
import AsyncNet

let imageService = ImageService()

let customConfig = ImageService.UploadConfiguration(
    fieldName: "image_file",
    fileName: "user_avatar.png",
    compressionQuality: 0.9,
    additionalFields: [
        "user_id": "12345",
        "category": "avatar",
        "version": "2.0"
    ]
)

guard let imageData = platformImage.jpegData(compressionQuality: 0.9) else {
    throw NetworkError.imageProcessingFailed
}

let response = try await imageService.uploadImageMultipart(
    imageData,
    to: URL(string: "https://api.example.com/upload")!,
    configuration: customConfig
)
```

### Advanced Networking Features

AsyncNet includes `AdvancedNetworkManager` for enhanced networking capabilities:

```swift
import AsyncNet

// Create advanced network manager with caching and interceptors
let cache = DefaultNetworkCache()
let interceptors: [NetworkInterceptor] = []
let networkManager = AdvancedNetworkManager(cache: cache, interceptors: interceptors)

// Use with AsyncRequestable
class UserService: AsyncRequestable {
    func getUsers() async throws -> [User] {
        let endpoint = UsersEndpoint()
        return try await sendRequestAdvanced(
            to: endpoint,
            networkManager: networkManager,
            cacheKey: "users",
            retryPolicy: .default
        )
    }
}
```

## Testing & Coverage

AsyncNet uses strict Swift 6 concurrency and comprehensive unit tests for all public APIs, error paths, and platform-specific features (iOS 18+, macOS 15+). Tests use protocol-based mocking for networking and cover:

- AsyncRequestable protocol
- Endpoint protocol
- NetworkError enum
- ImageService actor (fetch, upload, cache)
- PlatformImage conversion (UIImage/NSImage)
- SwiftUI integration (Image conversion)

### Running Tests

```bash
swift test --enable-code-coverage
```

### CI/CD

All PRs and pushes to main run tests and report coverage via GitHub Actions (see `.github/workflows/ci.yml`).

### Coverage Goals

- 50%+ coverage in Phase 1
- 90%+ coverage in Phase 4

### Test Strategy

- Protocol-based mocking for network layer
- Platform-specific tests for iOS/macOS
- SwiftUI integration tests
- Error path validation

## Architecture

AsyncNet follows a protocol-oriented design with these core components:

- **`AsyncRequestable`**: Generic networking protocol for API requests
- **`Endpoint`**: Protocol defining request structure  
- **`ImageService`**: Actor-based image service with dependency injection support
- **`AdvancedNetworkManager`**: Enhanced networking with caching, retry, and interceptors
- **`NetworkError`**: Comprehensive error handling with Sendable conformance
- **SwiftUI Extensions**: Native SwiftUI integration with AsyncNetImageView and AsyncImageModel

## Contributing

We welcome contributions! Please see our [Contributing Guide](CONTRIBUTING.md) for details.

## License

AsyncNet is available under the MIT license. See the [LICENSE](LICENSE) file for more info.

## Best Practices & Migration Guide

### Swift 6 Concurrency

- Always use actor isolation and Sendable types for thread safety.
- Inject services (e.g., `ImageService`) for strict concurrency and testability.
- Use @MainActor for UI/image conversion in SwiftUI.

### Dependency Injection Patterns

#### Constructor Injection (Recommended)

```swift
struct ProfileView: View {
    let imageService: ImageService
    
    init(imageService: ImageService = ImageService()) {
        self.imageService = imageService
    }
}
```

#### Environment Injection

```swift
struct ProfileView: View {
    @Environment(\.imageService) private var imageService
}
```

### Testing with Protocol-Based Mocking

```swift
// Protocol for testability
protocol ImageServiceProtocol: Sendable {
    func fetchImageData(from urlString: String) async throws -> Data
}

// Mock implementation
class MockImageService: ImageServiceProtocol {
    func fetchImageData(from urlString: String) async throws -> Data {
        return Data() // Mock data
    }
}
```

```bash
swift package generate-documentation
```
