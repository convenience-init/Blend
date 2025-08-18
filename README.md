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
    var header: [String: String]? = ["Content-Type": "application/json"]
    var body: Data? = nil
    var queryItems: [URLQueryItem]? = nil
}

// Create a service that implements AsyncRequestable
class UserService: AsyncRequestable {
    func getUsers() async throws -> [User] {
        return try await sendRequest(endpoint: UsersEndpoint(), responseModel: [User].self)
    }
}
```

### Image Operations

#### Download Images

```swift
import AsyncNet

// Download an image
let imageService = ImageService()
let image = try await imageService.fetchImageData(from: "https://example.com/image.jpg")

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
let imageService = injectedImageService

// Example PlatformImage (replace with actual image loading)
let image: PlatformImage = ... // Load or create your PlatformImage here

let uploadConfig = ImageService.UploadConfiguration(
    fieldName: "photo",
    fileName: "profile.jpg",
    compressionQuality: 0.8,
    additionalFields: ["userId": "123"]
)

// Multipart form upload
let multipartResponse = try await imageService.uploadImageMultipart(
    image,
    to: URL(string: "https://api.example.com/upload")!,
    configuration: uploadConfig
)

// Base64 upload
let base64Response = try await imageService.uploadImageBase64(
    image,
    to: URL(string: "https://api.example.com/upload")!,
    configuration: uploadConfig
)
```

### SwiftUI Integration

#### Async Image Loading

```swift
import SwiftUI
import AsyncNet

struct ProfileView: View {
    let imageURL: String
    
    var body: some View {
        Rectangle()
            .frame(width: 200, height: 200)
            .asyncImage(
                from: imageURL,
                placeholder: ProgressView().controlSize(.large),
                errorView: Image(systemName: "person.circle.fill")
            )
    }
}
```

#### Async Image Loading (Modern Pattern)

```swift
import SwiftUI
import AsyncNet

struct ProfileView: View {
    let imageURL: String
    let imageService = ImageService() // Dependency injection recommended

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

#### Complete Image Component (AsyncImageModel @Observable)

```swift
import SwiftUI
import AsyncNet

struct ImageGalleryView: View {
    let imageService = ImageService()

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

#### Image Upload with Progress (Modern Pattern)

```swift
import SwiftUI
import AsyncNet

struct PhotoUploadView: View {
    @State private var selectedImage: PlatformImage?
    let imageService = ImageService()
    
    var body: some View {
        VStack {
            if let image = selectedImage {
                Image(platformImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 200)
                    .imageUploader(
                        uploadURL: URL(string: "https://api.example.com/photos")!,
                        imageService: imageService,
                        uploadType: .multipart,
                        onSuccess: { data in
                            print("Photo uploaded successfully")
                        },
                        onError: { error in
                            print("Upload failed: \(error.localizedDescription)")
                        }
                    )
            }
            
            Button("Select Photo") {
                // Photo picker implementation
            }
        }
    }
}

---
#### Migration Notes

- Legacy state variables and methods (e.g., `isLoading`, `hasError`, `loadImage`) are now managed by the `AsyncImageModel` using the new `@Observable` macro and async/await methods.
- Always inject `ImageService` for strict concurrency and testability.
- Use `.asyncImage()`, `.imageUploader()`, and `AsyncNetImageView` for robust SwiftUI integration with modern Swift 6 APIs.

```swift
do {
    // Modern error handling with NetworkError
    let image = try await imageService.fetchImageData(from: url)
} catch let error as NetworkError {
    print("Network error: \(error.message)")
} catch {
    print("Unexpected error: \(error)")
}
```

### Cache Management

```swift
import AsyncNet

// Configure cache limits
imageService.imageCache.countLimit = 200  // Max 200 images
imageService.imageCache.totalCostLimit = 100 * 1024 * 1024  // Max 100MB

// Clear cache
imageService.clearCache()

// Remove specific image
imageService.removeFromCache(key: "https://example.com/image.jpg")
```

### Custom Upload Configuration

```swift
import AsyncNet

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

let response = try await imageService.uploadImageMultipart(
    userImage,
    to: uploadEndpoint,
    configuration: customConfig
)
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

See `DevDocs/AsyncNet_Jira_Tickets.md` for detailed ticket-based test requirements and strategy.

## Platform Support

- **iOS**: 18.0+
- **iPadOS**: 18.0+
- **macOS**: 15.0+

## Architecture

AsyncNet follows a protocol-oriented design with these core components:

- **`AsyncRequestable`**: Generic networking protocol for API requests
- **`Endpoint`**: Protocol defining request structure  
- **`ImageService`**: Comprehensive image service with dependency injection support
- **`NetworkError`**: Comprehensive error handling
- SwiftUI Extensions: Native SwiftUI integration

## Contributing

We welcome contributions! Please see our [Contributing Guide](CONTRIBUTING.md) for details.

## License

AsyncNet is available under the MIT license. See the [LICENSE](LICENSE) file for more info.

## Best Practices & Migration Guide

### Swift 6 Concurrency

- Always use actor isolation and Sendable types for thread safety.
- Inject services (e.g., `ImageService`) for strict concurrency and testability.
- Use @MainActor for UI/image conversion in SwiftUI.

```bash
swift package generate-documentation
```

Use `PlatformImage` typealias for cross-platform image handling.
