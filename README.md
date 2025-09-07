# Blend

A powerful Swift networking library with comprehensive image handling capabilities, built for iOS, iPadOS, and macOS with full SwiftUI support.

[![Version](https://img.shields.io/badge/version-1.0.0-blue.svg)](https://github.com/convenience-init/Blend/releases/tag/v1.0.0)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Swift](https://img.shields.io/badge/Swift-6.0-orange.svg)](https://swift.org)
[![iOS](https://img.shields.io/badge/iOS-18+-lightgrey.svg)](https://developer.apple.com/ios/)
[![macOS](https://img.shields.io/badge/macOS-15+-lightgrey.svg)](https://developer.apple.com/macos/)

## Features

**Modern Swift Concurrency** - Built with async/await and Swift 6 compliance  
**Cross-Platform** - Supports iOS 18+, iPadOS 18+, and macOS 15+  
**Complete Image Solution** - Download, upload, and cache images with ease  
**SwiftUI Integration** - Native SwiftUI view modifiers and components  
**High Performance** - Intelligent caching with configurable limits  
**Type Safe** - Protocol-oriented design with comprehensive error handling  

> **Platform Requirements**: iOS 18+ and macOS 15+ may provide improved resumable HTTP transfers (URLSession pause/resume and enhanced background reliability)[^1], HTTP/3 enhancements[^2], system TLS 1.3 improvements[^3], and corrected CFNetwork API signatures[^4].
>
> **Support Note**: Blend requires iOS 18+/macOS 15+ for full functionality.
> **Platform Feature Matrix**:

| Feature | iOS 18+ | macOS 15+ |
|---------|---------|-----------|
| Basic Networking | ✅ | ✅ |
| HTTP/3 Support | Improved/where available | Improved/where available |
| TLS 1.3 | Improved | Improved |
| URLSession Pause/Resume | Improved | Improved |
| CFNetwork APIs | Updates in latest SDKs | Updates in latest SDKs |

> [^1]: [URLSession Pause and Resume Documentation](https://developer.apple.com/documentation/foundation/pausing-and-resuming-uploads)
> [^2]: [WWDC 2021: Accelerate networking with HTTP/3 and QUIC](https://developer.apple.com/videos/play/wwdc2021/10095/)
> [^3]: [Transport Layer Security (TLS) Protocol Versions](https://developer.apple.com/documentation/security/tls_protocol_versions)
> [^4]: [CFNetwork Framework Reference](https://developer.apple.com/documentation/cfnetwork)

## Installation

### Swift Package Manager

Add Blend to your project through Xcode:

1. File → Add Package Dependency…
2. Enter the repository URL: `https://github.com/convenience-init/Blend`
3. Select your version requirements

Or add it to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/convenience-init/Blend", from: "1.0.0")
]
```

Complete `Package.swift` example:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MyApp",
    platforms: [
        .iOS(.v18),
        .macOS(.v15)
    ],
    dependencies: [
        .package(url: "https://github.com/convenience-init/Blend", from: "1.0.0")
    ],
    targets: [
        .target(
            name: "MyApp",
            dependencies: [
                .product(name: "Blend", package: "Blend")
            ]
        ),
        .testTarget(
            name: "MyAppTests",
            dependencies: [
                "MyApp",
                .product(name: "Blend", package: "Blend")
            ]
        )
    ]
)
```

## Platform Support

**Supported Platforms:**

- **iOS**: 18.0+ (includes iPadOS 18.0+)
- **macOS**: 15.0+

These platforms are both the minimum supported versions and the recommended/tested versions. Blend requires these minimum versions for full Swift 6 concurrency support and modern SwiftUI integration.

## Quick Start

### Basic Network Request

```swift
import Blend

// Define your endpoint
struct UsersEndpoint: Endpoint {
    var scheme: URLScheme = .https
    var host: String = "api.example.com"
    var path: String = "/users"
    var method: RequestMethod = .get
    var headers: [String: String]? = ["Accept": "application/json"]
    var body: Data? = nil
    var queryItems: [URLQueryItem]? = nil
    var timeoutDuration: Duration? = .seconds(30)
}

// Create a service that implements AsyncRequestable
class UserService: AsyncRequestable {
    typealias ResponseModel = [User] // Documents the primary response type
    
    func getUsers() async throws -> [User] {
        return try await sendRequest(to: UsersEndpoint())
    }
}
```

### Advanced Networking with Multiple Response Types

For services requiring master-detail patterns, CRUD operations, or complex type hierarchies, use `AdvancedAsyncRequestable`:

#### Master-Detail Pattern Example

```swift
import Blend

// Define endpoints for list and detail views
struct UsersEndpoint: Endpoint {
    var scheme: URLScheme = .https
    var host: String = "api.example.com"
    var path: String = "/users"
    var method: RequestMethod = .get
}

struct UserDetailsEndpoint: Endpoint {
    let userId: String
    
    var scheme: URLScheme = .https
    var host: String = "api.example.com"
    var path: String { "/users/\(userId)" }
    var method: RequestMethod = .get
}

// Service with both list and detail response types
class UserService: AdvancedAsyncRequestable {
    typealias ResponseModel = [UserSummary]        // For user lists
    typealias SecondaryResponseModel = UserDetails // For user details
    
    // Convenience methods automatically use correct types
    func getUsers() async throws -> [UserSummary] {
        return try await fetchList(from: UsersEndpoint())
    }
    
    func getUserDetails(id: String) async throws -> UserDetails {
        return try await fetchDetails(from: UserDetailsEndpoint(userId: id))
    }
    
    // Can also use generic sendRequest for custom response types
    func createUser(_ input: UserInput) async throws -> UserDetails {
        return try await sendRequest(to: CreateUserEndpoint(input: input))
    }
}
```

#### CRUD Operations with Different Response Types

```swift
import Blend

class ProductService: AdvancedAsyncRequestable {
    typealias ResponseModel = [ProductSummary]     // List operations
    typealias SecondaryResponseModel = ProductDetails // Detail operations
    
    // List operation - returns summary array
    func getProducts() async throws -> [ProductSummary] {
        return try await fetchList(from: ProductsEndpoint())
    }
    
    // Read operation - returns full details
    func getProduct(id: String) async throws -> ProductDetails {
        return try await fetchDetails(from: ProductDetailsEndpoint(id: id))
    }
    
    // Create operation - returns created item details
    func createProduct(_ input: ProductInput) async throws -> ProductDetails {
        return try await sendRequest(to: CreateProductEndpoint(input: input))
    }
    
    // Update operation - returns updated item details
    func updateProduct(id: String, _ input: ProductInput) async throws -> ProductDetails {
        return try await sendRequest(to: UpdateProductEndpoint(id: id, input: input))
    }
    
    // Delete operation - returns summary (could be just status)
    func deleteProduct(id: String) async throws -> ProductSummary {
        return try await sendRequest(to: DeleteProductEndpoint(id: id))
    }
}
```

#### Generic Service Composition

```swift
import Blend

// Generic CRUD service that works with any AdvancedAsyncRequestable
class GenericCrudService<T: AdvancedAsyncRequestable> {
    let service: T
    
    init(service: T) {
        self.service = service
    }
    
    // Generic list operation
    func listItems() async throws -> T.ResponseModel {
        // Implementation would use service's fetchList method
        fatalError("Implement based on your endpoint pattern")
    }
    
    // Generic detail operation
    func getItemDetails(id: String) async throws -> T.SecondaryResponseModel {
        // Implementation would use service's fetchDetails method
        fatalError("Implement based on your endpoint pattern")
    }
}

// Usage with type-safe composition
let userCrudService = GenericCrudService(service: UserService())
let productCrudService = GenericCrudService(service: ProductService())

// Both services work with the same generic interface
// but maintain their specific response types
```

#### Type-Safe Service Hierarchies

```swift
import Blend

// Base protocol for all API services
protocol ApiService: AdvancedAsyncRequestable {
    // Common requirements for all API services
    var baseURL: String { get }
    var apiKey: String { get }
}

// Specialized service protocols
protocol UserManagementService: ApiService
where ResponseModel: Sequence, ResponseModel.Element == UserSummary {
    // User services must use UserSummary for lists
}

protocol ProductManagementService: ApiService
where ResponseModel: Sequence, ResponseModel.Element == ProductSummary {
    // Product services must use ProductSummary for lists
}

// Concrete implementations
class ConcreteUserService: UserManagementService {
    typealias ResponseModel = [UserSummary]
    typealias SecondaryResponseModel = UserDetails
    
    let baseURL = "https://api.example.com"
    let apiKey = "your-api-key"
    
    // Implementation...
}

class ConcreteProductService: ProductManagementService {
    typealias ResponseModel = [ProductSummary]
    typealias SecondaryResponseModel = ProductDetails
    
    let baseURL = "https://api.example.com"
    let apiKey = "your-api-key"
    
    // Implementation...
}
```

### Image Operations

#### Download Images

```swift
import Blend
import SwiftUI
// Platform-conditional imports at the top level
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

let imageService = ImageService()

// Fetch image data and convert to SwiftUI Image
do {
    let imageData = try await imageService.fetchImageData(from: "https://example.com/image.jpg")

    // Platform-standard conversion (platform-specific imports moved to top)
    #if canImport(UIKit)
    if let uiImage = UIImage(data: imageData) {
        let swiftUIImage = Image(uiImage: uiImage)
    }
    #elseif canImport(AppKit)
    if let nsImage = NSImage(data: imageData) {
        let swiftUIImage = Image(nsImage: nsImage)
    }
    #endif

    // Blend convenience helper (requires: import Blend)
    // Convert data to PlatformImage, then to SwiftUI Image:
    // if let platformImage = ImageService.platformImage(from: imageData) {
    //     let swiftUIImage = Image.from(platformImage: platformImage)
    // }

    // Use swiftUIImage in your SwiftUI view
    // swiftUIImage.resizable().frame(width: 200, height: 200)
} catch {
    print("Failed to load image: \(error)")
}

// Check cache first (returns PlatformImage/UIImage/NSImage)
if let cachedImage = imageService.cachedImage(forKey: "https://example.com/image.jpg") {
    // Safe conversion using Blend helper (recommended approach)
    if let swiftUIImage = Image.from(platformImage: cachedImage) {
        // Use swiftUIImage in your SwiftUI view
        swiftUIImage.resizable().frame(width: 200, height: 200)
    } else {
        // Handle conversion failure gracefully
        print("Failed to convert cached image to SwiftUI Image")
    }

    // Alternative: Platform-standard conversion with safe casting
    /*
    #if canImport(UIKit)
    if let uiImage = cachedImage as? UIImage {
        let swiftUIImage = Image(uiImage: uiImage)
        // Use swiftUIImage in your SwiftUI view
    }
    #elseif canImport(AppKit)
    if let nsImage = cachedImage as? NSImage {
        let swiftUIImage = Image(nsImage: nsImage)
        // Use swiftUIImage in your SwiftUI view
    }
    #endif
    */
}
```

#### Upload Images

```swift
import Blend

// Dependency-injected image service
let imageService = ImageService()

// Example PlatformImage (replace with actual image loading)
let uploadURL = URL(string: "https://api.example.com/upload")!
let platformImage: PlatformImage = ... // Load or create your PlatformImage here

// Cross-platform PlatformImage helpers
// Note: NSImage does not natively expose jpegData/pngData - Blend provides these as extensions
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

let uploadConfig = UploadConfiguration(
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

> **Note on Image Conversion Examples**: The examples above use platform-standard SwiftUI `Image` initializers (`Image(uiImage:)` for iOS and `Image(nsImage:)` for macOS) to demonstrate universal compatibility. Blend provides convenience helpers `ImageService.swiftUIImage(from:)` and `Image.from(platformImage:)` in the `Blend` module for cross-platform image conversion. To use these helpers, add `import Blend` to your file. Blend helpers abstract platform differences and provide consistent error handling.

### SwiftUI Integration

#### Async Image Loading (Modern Pattern)

```swift
import SwiftUI
import Blend  // Required for .asyncImage modifier

struct ProfileView: View {
    let imageURL: String
    let imageService: ImageService // Dependency injection required

    var body: some View {
        Rectangle()
            .frame(width: 200, height: 200)
            .asyncImage(  // Blend extension (requires: import Blend)
                from: imageURL,
                imageService: imageService,
                placeholder: ProgressView().controlSize(.large),
                errorView: Image(systemName: "person.circle.fill")
            )
    }
}

// Requirements:
// - **Minimum OS Requirements**: iOS 18.0+ / macOS 15.0+
// - **Swift Version**: Swift 6.0+ (Package.swift uses // swift-tools-version: 6.0)
// - **Xcode**: Xcode 16+ (or Swift 6 toolchain) recommended
// - **Framework**: SwiftUI framework
//
// **Note on SwiftUI Compatibility**: 
// - Blend requires iOS 18.0+/macOS 15.0+ for full functionality
// - SwiftUI itself is available on iOS 15.0+/macOS 12.0+, but Blend's modern concurrency features require the newer OS versions
```

#### Complete Image Component with Upload

```swift
import SwiftUI
import Blend

struct ImageGalleryView: View {
    let imageService: ImageService // Dependency injection required

    var body: some View {
        VStack {
            AsyncNetImageView(
                url: "https://example.com/gallery/1.jpg",
                uploadURL: URL(string: "https://api.example.com/upload")!,
                uploadType: .multipart,
                configuration: UploadConfiguration(),
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
// - Implementation location: Sources/Blend/extensions/SwiftUIExtensions.swift - AsyncImageModel.uploadImage()
```

#### Image Upload with Progress

```swift
import SwiftUI
import Blend

struct PhotoUploadView: View {
    @State private var selectedImage: PlatformImage?
    let imageService: ImageService // Dependency injection required
    
    var body: some View {
        VStack {
            if let platformImage = selectedImage {
                // Safe conversion using Blend helper (recommended approach)
                if let swiftUIImage = Image.from(platformImage: platformImage) {
                    swiftUIImage
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 200)
                } else {
                    // Handle conversion failure gracefully
                    Image(systemName: "photo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 200)
                }

                // Alternative: Platform-standard conversion with safe casting
                /*
                #if canImport(UIKit)
                if let uiImage = platformImage as? UIImage {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 200)
                }
                #elseif canImport(AppKit)
                if let nsImage = platformImage as? NSImage {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 200)
                }
                #endif
                */
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
                            
                            let config = UploadConfiguration()
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
import Blend

let imageService = ImageService()

// Fetch image data and convert to SwiftUI Image
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

Blend provides comprehensive error handling through the `NetworkError` enum:

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
import Blend

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

- **Important**: Setting `cacheCountLimit: 0` or `cacheTotalCostLimit: 0` does **NOT** disable caching - it means "no limit" (unlimited caching). Avoid this configuration for sensitive content.
- To disable caching, do not attach an `NSCache` instance or pass `nil`/`no-op` cache to `ImageService`
- Use `ImageService` constructor flags or configuration that explicitly disables caching when available
- Call `cache.removeAllObjects()` on the underlying `NSCache` to clear all cached items
- Call `await imageService.removeFromCache(key: "sensitive-image-url")` immediately after use to clear specific sensitive items

**Avoid Caching PII-Containing Assets:**

- Never cache user avatars, profile images, or images with embedded metadata
- Use `fetchImageData(from: urlString)` without caching for sensitive content
- Implement custom logic to bypass cache for authenticated user content

**Aggressive Cache Eviction:**

- Configure short `maxAge` (e.g., 300 seconds) for sensitive content using `CacheConfiguration(maxAge: 300)`
- Call `await imageService.clearCache()` proactively for sensitive sessions
- Use `await imageService.updateCacheConfiguration(CacheConfiguration(maxAge: 0))` to disable time-based caching

**Lifecycle Cache Clearing:**
Implement cache clearing using SwiftUI's ScenePhase for modern, cross-platform lifecycle management:

```swift
import SwiftUI
import Blend

// Environment key for ImageService injection
private struct ImageServiceKey: EnvironmentKey {
    static let defaultValue: ImageService = ImageService()
}

extension EnvironmentValues {
    var imageService: ImageService {
        get { self[ImageServiceKey.self] }
        set { self[ImageServiceKey.self] = newValue }
    }
}

@main
struct MyApp: App {
    @Environment(\.scenePhase) private var scenePhase
    let imageService = ImageService() // Or inject via dependency injection
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.imageService, imageService)
        }
        .onChange(of: scenePhase) { newPhase in
            switch newPhase {
            case .background:
                // Clear cache when app goes to background
                Task {
                    await imageService.clearCache()
                }
            case .inactive:
                // Optional: Clear cache when app becomes inactive
                Task {
                    await imageService.clearCache()
                }
            case .active:
                // App became active - no action needed for cache
                break
            @unknown default:
                // Handle future scene phases
                break
            }
        }
    }
}

// Alternative: Handle lifecycle in individual views
struct SensitiveContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    let imageService: ImageService
    
    var body: some View {
        VStack {
            Text("Sensitive Content")
            // Your sensitive content here
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .background {
                Task {
                    await imageService.clearCache()
                }
            }
        }
    }
}
```

**Benefits of ScenePhase Approach:**

- **Cross-platform**: Works identically on iOS, macOS, watchOS, and tvOS
- **Multi-scene support**: Handles multiple windows/scenes correctly in iOS 13+ and macOS 10.15+
- **Modern SwiftUI**: Uses SwiftUI's built-in lifecycle management
- **Consistent behavior**: Same lifecycle events across all platforms
- **Future-proof**: Automatically supports new scene phases as they're added
