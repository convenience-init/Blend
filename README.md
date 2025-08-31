# AsyncNet

A powerful Swift networking library with comprehensive image handling capabilities, built for iOS, iPadOS, and macOS with full SwiftUI support.

## Features

**Modern Swift Concurrency** - Built with async/await and Swift 6 compliance  
**Cross-Platform** - Supports iOS 18+, iPadOS 18+, and macOS 15+  
**Complete Image Solution** - Download, upload, and cache images with ease  
**SwiftUI Integration** - Native SwiftUI view modifiers and components  
**High Performance** - Intelligent caching with configurable limits  
**Type Safe** - Protocol-oriented design with comprehensive error handling  

> **Platform Requirements**: iOS 18+ and macOS 15+ may provide improved resumable HTTP transfers (URLSession pause/resume and enhanced background reliability)[^1], HTTP/3 enhancements[^2], system TLS 1.3 improvements[^3], and corrected CFNetwork API signatures[^4].
> 
> **Support Note**: AsyncNet compiles on iOS 17+/macOS 14+ (minimum supported) with graceful degradation. On earlier versions, advanced networking features like improved HTTP/3 support and enhanced TLS may be limited or unavailable, falling back to standard URLSession behavior.

> **Platform Feature Matrix**:

| Feature | iOS 17 | iOS 18+ | macOS 14 | macOS 15+ |
|---------|--------|---------|----------|-----------|
| Basic Networking | ✅ | ✅ | ✅ | ✅ |
| HTTP/3 Support | Limited | Improved/where available | Limited | Improved/where available |
| TLS 1.3 | Standard | Improved | Standard | Improved |
| URLSession Pause/Resume | Standard | Improved | Standard | Improved |
| CFNetwork APIs | Standard | Updates in latest SDKs | Standard | Updates in latest SDKs |

> [^1]: [Apple URLSession Documentation](https://developer.apple.com/documentation/foundation/urlsession)
> [^2]: [HTTP/3 Support](https://developer.apple.com/documentation/foundation/urlsession/3767356-httpversion)
> [^3]: [TLS Protocol Versions](https://developer.apple.com/documentation/security/tls_protocol_versions)
> [^4]: [CFNetwork Framework](https://developer.apple.com/documentation/cfnetwork)

## Installation

### Swift Package Manager

Add AsyncNet to your project through Xcode:

1. File → Add Package Dependency…
2. Enter the repository URL: `https://github.com/convenience-init/async-net`
3. Select your version requirements

Or add it to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/convenience-init/async-net", from: "1.0.0")
]
```

> **Version Pinning Recommendation**: Use `from: "1.0.0"` to automatically receive non-breaking updates (patch and minor versions) while preventing accidental major version upgrades. This ensures you get bug fixes and minor enhancements without unexpected breaking changes. For more explicit control, you can use version ranges like `"1.0.0"..<"2.0.0"`.

## Platform Support

**Recommended / Tested:**

- **iOS**: 18.0+ (includes iPadOS 18.0+)
- **macOS**: 15.0+

**Minimum Supported (compilation only):**

- **iOS**: 17.0+ (includes iPadOS 17.0+)
- **macOS**: 14.0+

## Quick Start

### Basic Network Request

```swift
import AsyncNet

// Define your endpoint
struct UsersEndpoint: Endpoint {
    var scheme: URLScheme = .https
    var host: String = "api.example.com"
    var path: String = "/users"
    var method: RequestMethod = .get
    var headers: [String: String]? = ["Content-Type": "application/json"]
    var body: Data? = nil
    var queryItems: [URLQueryItem]? = nil
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

let imageService = ImageService()

// Fetch image data and convert to SwiftUI Image
do {
    let imageData = try await imageService.fetchImageData(from: "https://example.com/image.jpg")

    // Platform-standard conversion (requires platform-specific imports)
    #if canImport(UIKit)
    import UIKit
    if let uiImage = UIImage(data: imageData) {
        let swiftUIImage = Image(uiImage: uiImage)
    }
    #elseif canImport(AppKit)
    import AppKit
    if let nsImage = NSImage(data: imageData) {
        let swiftUIImage = Image(nsImage: nsImage)
    }
    #endif

    // AsyncNet convenience helper (requires: import AsyncNet)
    // let swiftUIImage = ImageService.swiftUIImage(from: imageData)

    // Use swiftUIImage in your SwiftUI view
    // Image(swiftUIImage).resizable().frame(width: 200, height: 200)
} catch {
    print("Failed to load image: \(error)")
}

// Check cache first (returns PlatformImage/UIImage/NSImage)
if let cachedImage = imageService.cachedImage(forKey: "https://example.com/image.jpg") {
    // Platform-standard conversion
    #if canImport(UIKit)
    let swiftUIImage = Image(uiImage: cachedImage as! UIImage)
    #elseif canImport(AppKit)
    let swiftUIImage = Image(nsImage: cachedImage as! NSImage)
    #endif

    // AsyncNet convenience helper (requires: import AsyncNet)
    // let swiftUIImage = Image.from(platformImage: cachedImage)

    // Use swiftUIImage in your SwiftUI view
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

// Cross-platform PlatformImage helpers
// Note: NSImage does not natively expose jpegData/pngData - AsyncNet provides these as extensions
// for consistent cross-platform API (iOS/macOS)

// jpegData(compressionQuality: CGFloat) -> Data?
// Creates JPEG data representation with configurable compression quality (0.0 to 1.0)
// Returns nil if image conversion fails
let jpegData = platformImage.jpegData(compressionQuality: 0.8)

// pngData() -> Data?
// Creates PNG data representation with lossless compression
// Returns nil if image conversion fails
let pngData = platformImage.pngData()

// Preferred usage pattern with fallback and error handling
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

// Upload Method Tradeoffs:
// - Base64 encoding increases payload size by ~33% and can more easily hit request size limits
// - Base64 adds memory and network overhead due to text encoding/decoding
// - Multipart sends binary data directly and is generally preferable for larger files
// - Use Base64 only for small images or when the API requires JSON payloads
// - Multipart uploads are recommended as the default choice
```

> **Note on Image Conversion Examples**: The examples above use platform-standard SwiftUI `Image` initializers (`Image(uiImage:)` for iOS and `Image(nsImage:)` for macOS) to demonstrate universal compatibility. AsyncNet provides convenience helpers `ImageService.swiftUIImage(from:)` and `Image.from(platformImage:)` in the `AsyncNet` module for cross-platform image conversion. To use these helpers, add `import AsyncNet` to your file. The AsyncNet helpers abstract platform differences and provide consistent error handling.

### SwiftUI Integration

#### Async Image Loading (Modern Pattern)

```swift
import SwiftUI
import AsyncNet  // Required for .asyncImage modifier

struct ProfileView: View {
    let imageURL: String
    let imageService: ImageService // Dependency injection required

    var body: some View {
        Rectangle()
            .frame(width: 200, height: 200)
            .asyncImage(  // AsyncNet extension (requires: import AsyncNet)
                from: imageURL,
                imageService: imageService,
                placeholder: ProgressView().controlSize(.large),
                errorView: Image(systemName: "person.circle.fill")
            )
    }
}

// Requirements:
// - iOS 15.0+ / macOS 12.0+ (for SwiftUI support)
// - iOS 17.0+ / macOS 14.0+ (minimum AsyncNet support)
// - iOS 18.0+ / macOS 15.0+ (recommended for full feature support)
// - Swift 5.5+ (for async/await)
// - SwiftUI framework

// Dependency Injection Options:
// 1. Constructor injection: init(imageService: ImageService) { self.imageService = imageService }
// 2. Environment injection: @Environment(\.imageService) private var imageService
// 3. Factory pattern: ServiceFactory.makeImageService(for: environment)
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
                uploadURL: URL(string: "https://api.example.com/upload")!,
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

// Upload Callbacks Documentation:
// - onUploadSuccess: ((Data) -> Void)? - Called on main thread with server response data
// - onUploadError: ((NetworkError) -> Void)? - Called on main thread with NetworkError details
// - Data parameter contains the raw response from the upload endpoint (e.g., JSON confirmation)
// - NetworkError provides comprehensive error information (see NetworkError enum documentation)
// - Callbacks are invoked on the main thread, so UI updates can be performed directly
//
// Thread Safety Guarantee:
// - Upload callbacks are guaranteed to execute on the main thread via @MainActor isolation
// - The AsyncImageModel class is marked @MainActor, ensuring all callback invocations run on the main thread
// - Implementation location: Sources/AsyncNet/extensions/SwiftUIExtensions.swift - AsyncImageModel.uploadImage()
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
            if let platformImage = selectedImage {
                // Platform-standard conversion
                #if canImport(UIKit)
                Image(uiImage: platformImage as! UIImage)
                #elseif canImport(AppKit)
                Image(nsImage: platformImage as! NSImage)
                #endif

                // AsyncNet convenience helper (requires: import AsyncNet)
                // Image.from(platformImage: platformImage)

                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 200)
            }
            
            Button("Select Photo") {
                // Photo picker implementation
            }
            
            if let platformImage = selectedImage {
                Button("Upload") {
                    Task {
                        do {
                            // Mirror JPEG→PNG fallback pattern from earlier example
                            let imageData: Data
                            if let jpegData = platformImage.jpegData(compressionQuality: 0.8) {
                                imageData = jpegData
                                print("Using JPEG conversion (compression: 0.8)")
                            } else if let pngData = platformImage.pngData() {
                                imageData = pngData
                                print("JPEG conversion failed, falling back to PNG")
                            } else {
                                print("Failed to convert image to both JPEG and PNG formats")
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
    let imageData = try await imageService.fetchImageData(from: "https://example.com/image.jpg")
} catch let error as NetworkError {
    // Option 1: Use the message() method
    print("Network error: \(error.message())")
    
    // Option 2: Use localizedDescription (standard LocalizedError)
    print("Network error: \(error.localizedDescription)")
    
    // Option 3: Pattern match for specific error details
    switch error {
    case .httpError(let statusCode, _):
        print("HTTP error with status: \(statusCode)")
    case .decodingError(let description, _):
        print("Failed to decode response: \(description)")
    case .networkUnavailable:
        print("No internet connection")
    case .requestTimeout(let duration):
        print("Request timed out after \(duration) seconds")
    case .invalidEndpoint(let reason):
        print("Invalid endpoint: \(reason)")
    case .unauthorized:
        print("Authentication required")
    case .uploadFailed(let details):
        print("Upload failed: \(details)")
    case .cacheError(let details):
        print("Cache error: \(details)")
    case .transportError(let code, let underlying):
        print("Network transport error: \(code.rawValue) - \(underlying.localizedDescription)")
    default:
        print("Other network error: \(error.localizedDescription)")
    }
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
let imageServiceConfigured = ImageService(cacheCountLimit: 200, cacheTotalCostLimit: 100 * 1024 * 1024)

// Execute cache operations in an async context
Task {
    // Clear cache
    await imageServiceConfigured.clearCache()

    // Remove specific image
    await imageServiceConfigured.removeFromCache(key: "https://example.com/image.jpg")

    // Check if image is cached
    let isCached = await imageServiceConfigured.isImageCached(forKey: "https://example.com/image.jpg")
    print("Image cached: \(isCached)")
}
```

#### Security Guidance for Sensitive Images

When handling sensitive images such as user avatars, profile pictures, or any content containing personally identifiable information (PII), implement strict cache management to prevent data leakage:

**Opt-out of Caching:**

- Set `cacheCountLimit: 0` and `cacheTotalCostLimit: 0` when initializing `ImageService` for sensitive content
- Use `ImageService(cacheCountLimit: 0, cacheTotalCostLimit: 0)` to disable all caching
- Call `await imageService.removeFromCache(key: "sensitive-image-url")` immediately after use

**Avoid Caching PII-Containing Assets:**

- Never cache user avatars, profile images, or images with embedded metadata
- Use `fetchImageData(from: urlString)` without caching for sensitive content
- Implement custom logic to bypass cache for authenticated user content

**Aggressive Cache Eviction:**

- Configure short `maxAge` (e.g., 300 seconds) for sensitive content using `CacheConfiguration(maxAge: 300)`
- Call `await imageService.clearCache()` proactively for sensitive sessions
- Use `await imageService.updateCacheConfiguration(CacheConfiguration(maxAge: 0))` to disable time-based caching

**Lifecycle Cache Clearing:**
Implement cache clearing on platform-specific lifecycle events:

```swift
// iOS: Clear cache on app backgrounding and memory warnings
#if canImport(UIKit)
import UIKit

class AppDelegate: UIResponder, UIApplicationDelegate {
    func applicationWillResignActive(_ application: UIApplication) {
        Task {
            await imageService.clearCache()
        }
    }
    
    func applicationDidReceiveMemoryWarning(_ application: UIApplication) {
        Task {
            await imageService.clearCache()
        }
    }
}
#endif

// macOS: Clear cache on app deactivation
#if canImport(AppKit)
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillResignActive(_ notification: Notification) {
        Task {
            await imageService.clearCache()
        }
    }
}
#endif
```

**Recommended Security Practices:**

- Use separate `ImageService` instances for sensitive vs. public content
- Implement cache encryption for highly sensitive environments
- Monitor cache usage with `imageService.cacheHits` and `imageService.cacheMisses`
- Clear caches on user logout or session termination

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
private final class LRUNode: @unchecked Sendable {
    let key: NSString
    var prev: LRUNode?  // Strong reference for proper list integrity
    var next: LRUNode?  // Strong reference for proper list integrity
    var timestamp: TimeInterval
    
    init(key: NSString, timestamp: TimeInterval) {
        self.key = key
        self.timestamp = timestamp
    }
}

// Cache owns head/tail references strongly to maintain list structure
private var lruHead: LRUNode?
private var lruTail: LRUNode?

// Node removal explicitly nils both prev/next to break cycles
private func removeLRUNode(_ node: LRUNode) {
    if node.prev != nil {
        node.prev?.next = node.next
    } else {
        lruHead = node.next
    }
    if node.next != nil {
        node.next?.prev = node.prev
    } else {
        lruTail = node.prev
    }
    node.prev = nil  // Break cycle
    node.next = nil  // Break cycle
}
```

#### Cache Metrics & Monitoring

```swift
// Access cache performance metrics in an async context
Task {
    let hits = await imageService.cacheHits
    let misses = await imageService.cacheMisses
    let hitRate = (hits + misses) == 0 ? 0.0 : Double(hits) / Double(hits + misses)

    // Monitor cache efficiency
    print("Cache hit rate: \(hitRate * 100)%")
}
```

#### Advanced Cache Configuration

```swift
// Configure cache with custom settings
let imageService = ImageService(
    cacheCountLimit: 200,           // Max 200 entries
    cacheTotalCostLimit: 100 * 1024 * 1024  // Max 100MB
)

// Update cache configuration at runtime in an async context
Task {
    let newConfig = CacheConfiguration(
        maxAge: 1800,      // 30 minutes
        maxLRUCount: 150   // Max 150 entries
    )
    await imageService.updateCacheConfiguration(newConfig)
}
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

// Declare platformImage - in real code, this would be loaded from assets or user input
#if canImport(UIKit)
import UIKit
let platformImage: PlatformImage = UIImage(named: "sample_image") ?? UIImage()
#elseif canImport(AppKit)
import AppKit
let platformImage: PlatformImage = NSImage(named: "sample_image") ?? NSImage()
#endif

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
- SwiftUI integration tests
- Error path validation

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
