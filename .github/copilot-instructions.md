````instructions
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
  - `-Xfrontend -warn-concurrency` (additional concurrency warnings)
  - `-Xfrontend -enable-actor-data-race-checks` (data race detection)

**CI/CD Requirements:**
- Use Xcode 16+ in GitHub Actions or other CI systems
- Ensure SwiftPM resolves to Swift 6 toolchain
- Test on iOS 18+ and macOS 15+ simulators/devices
- **CI Environment Variables**: Set `SWIFT_STRICT_CONCURRENCY=complete` in CI matrices to enforce complete concurrency checking
- **CI Build Flags**: Add these flags to CI build commands:
  - `swift build -Xswiftc -Xfrontend -Xswiftc -warn-concurrency`
  - `swift test -Xswiftc -Xfrontend -Xswiftc -enable-actor-data-race-checks`

> **Toolchain Note**: Swift 6 features like `@MainActor` isolation, `Sendable` conformance checking, and region-based memory analysis require Xcode 16+. Using older toolchains will result in compilation errors or runtime issues.

## Architecture Overview

AsyncNet follows a **protocol-oriented design** with modern Swift 6 patterns and these core service boundaries:

- **Network Layer**: `AsyncRequestable` protocol + `Endpoint` definitions in `/base/` and `/endpoints/`
  - **Image Operations**: `ImageService` is actor-based and provided via dependency injection in `/services/`, with comprehensive upload/download, caching, and SwiftUI integration
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
    
    // Store encoding error for inspection if needed
    let encodingError: Error?
    
    // Initialize with pre-encoded body to avoid repeated encoding and side effects
    init(request: CreateUserRequest, logger: Logger? = nil) {
        do {
            self.body = try JSONEncoder().encode(request)
            self.encodingError = nil
        } catch {
            self.body = nil
            self.encodingError = error
            // Surface encoding error via logger instead of print
            logger?.error("Failed to encode CreateUserRequest: \(error.localizedDescription)")
        }
    }
    
    var queryItems: [URLQueryItem]? = nil
}
```

**Timeout Configuration Guidance:**
- **Per-Request Timeout** (`timeoutDuration`): Use for request-specific timeouts (e.g., long uploads need longer timeouts)
- **Session-Wide Timeout** (`URLSessionConfiguration.timeoutIntervalForRequest`): Use for consistent timeouts across all requests
- **Duration Conversion**: Convert Swift `Duration` to `TimeInterval` (e.g., `duration.timeInterval`) before setting `URLRequest.timeoutInterval`
- **Nil Handling**: When `timeoutDuration` is `nil`, leave `URLRequest.timeoutInterval` unset so the session's `timeoutIntervalForRequest` (default: 60 seconds) is used as the fallback
- **Best Practice**: Prefer per-request timeouts for fine-grained control, use session timeouts for global defaults

### 2. Service Implementation Pattern (Swift 6 Compliant)
```swift
class YourService: AsyncRequestable {
    // Core method that handles all endpoint types
    func sendRequest<T: Decodable & Sendable>(
        to endpoint: some Endpoint,
        expecting responseType: T.Type
    ) async throws -> T {
        // Implementation delegates to AsyncRequestable.sendRequest
        return try await (self as AsyncRequestable).sendRequest(to: endpoint, expecting: responseType)
    }
    
    // Example with typed request body - caller provides the endpoint
    func createUser(name: String, email: String) async throws -> User {
        let request = CreateUserRequest(name: name, email: email)
        let endpoint = CreateUserEndpoint(request: request)
        return try await sendRequest(to: endpoint, expecting: User.self)
    }
    
    // Usage examples:
    func exampleUsage() async throws {
        // Using specific endpoint types
        let user = try await createUser(name: "John", email: "john@example.com")
        
        // Using generic method with any endpoint
        let endpoint = YourEndpoint()
        let data: SomeResponse = try await sendRequest(to: endpoint, expecting: SomeResponse.self)
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
```swift
// Convert PlatformImage to Data before upload
let imageData = try platformImageToData(platformImage, compressionQuality: 0.8)
```

### 6. Swift 6 Actor Patterns
`ImageService` is actor-based and provided via dependency injection. All image operations are actor-isolated and concurrency-safe. Example usage:
```swift
import Foundation
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
                await MainActor.run {
                    let loadedImage = platformImage(from: data)
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

### 6.1 Platform Image Conversion Helper

```swift
/// Cross-platform image conversion helper for AsyncNet
/// Converts PlatformImage (UIImage/NSImage) to Data for actor-safe transmission
///
/// - Parameters:
///   - image: The PlatformImage to convert (UIImage on iOS, NSImage on macOS)
///   - compressionQuality: JPEG compression quality from 0.0 (maximum compression) to 1.0 (minimum compression)
/// - Returns: Data representation of the image
/// - Throws: NetworkError.imageProcessingFailed if image processing fails
///
/// **Platform Behavior:**
/// - **iOS/iPadOS**: Uses `UIImage.jpegData(compressionQuality:)` for JPEG encoding
/// - **macOS**: Converts NSImage to NSBitmapImageRep/CGImage and encodes to JPEG/PNG as appropriate
///   - Prefers JPEG for photographic content, PNG for graphics with transparency
///   - Falls back to TIFF representation if bitmap conversion fails
///
/// **Thread Safety:** Must be called on @MainActor due to UI-related PlatformImage operations.
///
/// **Error Handling:** Throws NetworkError.imageProcessingFailed for:
/// - Invalid or corrupted image data
/// - Unsupported image formats
/// - Memory allocation failures during conversion
/// - Platform-specific encoding failures
///
/// **Usage Note:** Always call from @MainActor context:
```swift
@MainActor
func platformImageToData(_ image: PlatformImage, compressionQuality: CGFloat) throws -> Data
```

**Example Usage:**
```swift
// Convert PlatformImage to Data before upload
let imageData = try platformImageToData(platformImage, compressionQuality: 0.8)
// Use imageData for upload or storage
```