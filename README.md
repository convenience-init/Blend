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
> **Support Note**: AsyncNet requires iOS 18+/macOS 15+ (minimum supported). Older OS versions are not supported.
> **Platform Feature Matrix**:

| Feature | iOS 18+ | macOS 15+ |
|---------|---------|-----------|
| Basic Networking | ✅ | ✅ |
| HTTP/3 Support | Improved/where available | Improved/where available |
| TLS 1.3 | Improved | Improved |
| URLSession Pause/Resume | Improved | Improved |
| CFNetwork APIs | Updates in latest SDKs | Updates in latest SDKs |

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
        .package(url: "https://github.com/convenience-init/async-net", from: "1.0.0")
    ],
    targets: [
        .target(
            name: "MyApp",
            dependencies: [
                .product(name: "AsyncNet", package: "async-net")
            ]
        ),
        .testTarget(
            name: "MyAppTests",
            dependencies: [
                "MyApp",
                .product(name: "AsyncNet", package: "async-net")
            ]
        )
    ]
)
```

> **Version Pinning Recommendation**: Use `from: "1.0.0"` to automatically receive non-breaking updates (patch and minor versions) while preventing accidental major version upgrades. This ensures you get bug fixes and minor enhancements without unexpected breaking changes. For more explicit control, you can use version ranges like `"1.0.0"..<"2.0.0"`.

## Platform Support

**Supported Platforms:**

- **iOS**: 18.0+ (includes iPadOS 18.0+)
- **macOS**: 15.0+

These platforms are both the minimum supported versions and the recommended/tested versions. AsyncNet requires these minimum versions for full Swift 6 concurrency support and modern SwiftUI integration.

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

    // AsyncNet convenience helper (requires: import AsyncNet)
    // let swiftUIImage = ImageService.swiftUIImage(from: imageData)

    // Use swiftUIImage in your SwiftUI view
    // swiftUIImage.resizable().frame(width: 200, height: 200)
} catch {
    print("Failed to load image: \(error)")
}

// Check cache first (returns PlatformImage/UIImage/NSImage)
if let cachedImage = imageService.cachedImage(forKey: "https://example.com/image.jpg") {
    // Safe conversion using AsyncNet helper (recommended approach)
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
// - **Minimum OS Requirements**: iOS 18.0+ / macOS 15.0+ (required for AsyncNet package)
// - **Swift Version**: Swift 6.0+ (Package.swift uses // swift-tools-version: 6.0)
// - **Xcode**: Xcode 16+ (or Swift 6 toolchain) recommended
// - **Framework**: SwiftUI framework
//
// **Note on SwiftUI Compatibility**: 
// - AsyncNet requires iOS 18.0+/macOS 15.0+ for full functionality
// - SwiftUI itself is available on iOS 15.0+/macOS 12.0+, but AsyncNet's modern concurrency features require the newer OS versions
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
                // Safe conversion using AsyncNet helper (recommended approach)
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
Implement cache clearing using SwiftUI's ScenePhase for modern, cross-platform lifecycle management:

```swift
import SwiftUI
import AsyncNet

@main
struct MyApp: App {
    @Environment(\.scenePhase) private var scenePhase
    let imageService = ImageService() // Or inject via dependency injection
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.imageService, imageService)
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
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
        .onChange(of: scenePhase) { oldPhase, newPhase in
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
