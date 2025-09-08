# Blend

A **Powerful, intuitive Swift 6 networking library** that makes modern platform-agnostic development a breeze through **composable, protocol-oriented architecture**. Blend combines powerful networking and image handling capabilities with deep SwiftUI integration, enabling developers to build reactive, type-safe applications with unprecedented ease and flexibility.

 Blend embraces **composability** through its protocol hierarchy (`AsyncRequestable` → `AdvancedAsyncRequestable`) and **SwiftUI-first design** with native reactive components, making complex networking patterns feel natural in modern Swift 6 applications.

[![Version](https://img.shields.io/badge/version-1.0.0-blue.svg)](https://github.com/convenience-init/Blend/releases/tag/v1.0.0)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Swift](https://img.shields.io/badge/Swift-6.0-orange.svg)](https://swift.org)
[![iOS](https://img.shields.io/badge/iOS-18+-lightgrey.svg)](https://developer.apple.com/ios/)
[![macOS](https://img.shields.io/badge/macOS-15+-lightgrey.svg)](https://developer.apple.com/macos/)

## Features

**🎯 SwiftUI-First by Design** - Native reactive components and view modifiers built specifically for SwiftUI  
**🔧 Protocol-Oriented Composability** - Flexible service composition with type-safe hierarchies  
**⚡ Modern Swift Concurrency** - Built with async/await and Swift 6 compliance  
**🌉 Cross-Platform** - Supports iOS 18+, iPadOS 18+, and macOS 15+  
**🖼️ Complete Image Solution** - Download, upload, and cache and display images with ease  
**🚀 High Performance** - Intelligent LRU caching with configurable limits  
**🔒 Type Safe** - Protocol-oriented design with comprehensive error handling  

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

// Option 1: Simple async/await upload (no progress tracking)
let multipartResponse = try await imageService.uploadImageMultipart(imageData, to: uploadURL, configuration: uploadConfig)

// Option 2: Upload with progress tracking callback
let base64Response = try await imageService.uploadImageBase64(
    imageData, 
    to: uploadURL, 
    configuration: uploadConfig
) { progress in
    print("Upload progress: \(Int(progress * 100))%")
}

// Upload Method Tradeoffs:
// - Base64 encoding increases payload size by ~33% and can more easily hit request size limits
// - Base64 adds memory and network overhead due to text encoding/decoding
// - Multipart sends binary data directly and is generally preferable for larger files
// - Use Base64 only for small images or when the API requires JSON payloads
// - Multipart uploads are recommended as the default choice
```

#### Complete Image Component with Upload

```swift
import SwiftUI
import Blend

struct ImageGalleryView: View {
    let imageService: ImageService

    var body: some View {
        VStack {
            AsyncNetImageView(
                url: "https://example.com/gallery/1.jpg",
                uploadURL: URL(string: "https://api.example.com/upload")!,
                uploadType: .multipart,
                configuration: UploadConfiguration(),
                autoUpload: true, // Automatically upload after loading
                imageService: imageService
            )
            .frame(height: 300)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

// Programmatic upload examples
struct UploadView: View {
    @State private var uploadResult: String = ""
    let imageService: ImageService
    
    var body: some View {
        VStack {
            AsyncNetImageView(
                url: "https://example.com/gallery/1.jpg",
                uploadURL: URL(string: "https://api.example.com/upload")!,
                uploadType: .multipart,
                configuration: UploadConfiguration(),
                imageService: imageService
            )
            .frame(height: 200)
            
            HStack {
                // Option 1: Simple upload without progress tracking
                Button("Upload (Simple)") {
                    Task {
                        do {
                            let imageView = AsyncNetImageView(/* same parameters */)
                            let result = try await imageView.uploadImage()
                            uploadResult = "Upload successful: \(result.count) bytes"
                        } catch {
                            uploadResult = "Upload failed: \(error.localizedDescription)"
                        }
                    }
                }
                
                // Option 2: Upload with progress tracking
                Button("Upload (With Progress)") {
                    Task {
                        do {
                            let imageView = AsyncNetImageView(/* same parameters */)
                            let result = try await imageView.uploadImage { progress in
                                print("Upload progress: \(Int(progress * 100))%")
                            }
                            uploadResult = "Upload successful: \(result.count) bytes"
                        } catch {
                            uploadResult = "Upload failed: \(error.localizedDescription)"
                        }
                    }
                }
            }
            
            Text(uploadResult)
        }
    }
}
```

#### AsyncImageModel with Progress Tracking

```swift
import SwiftUI
import Blend

struct AdvancedUploadView: View {
    @State private var model = AsyncImageModel(imageService: ImageService())
    @State private var uploadProgress: Double = 0.0
    @State private var isUploading = false
    
    var body: some View {
        VStack {
            if let image = model.loadedImage {
                Image.from(platformImage: image)
                    .resizable()
                    .frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                
                if isUploading {
                    ProgressView("Uploading...", value: uploadProgress, total: 1.0)
                        .progressViewStyle(.linear)
                        .padding()
                }
                
                HStack {
                    // Option 1: Simple upload without progress tracking
                    Button("Upload (Simple)") {
                        Task {
                            do {
                                isUploading = true
                                let result = try await model.uploadImage(
                                    image,
                                    to: URL(string: "https://api.example.com/upload")!,
                                    uploadType: .multipart,
                                    configuration: UploadConfiguration()
                                )
                                print("Upload successful: \(result.count) bytes")
                            } catch {
                                print("Upload failed: \(error)")
                            }
                            isUploading = false
                        }
                    }
                    
                    // Option 2: Upload with progress tracking
                    Button("Upload (With Progress)") {
                        Task {
                            do {
                                isUploading = true
                                uploadProgress = 0.0
                                
                                let result = try await model.uploadImage(
                                    image,
                                    to: URL(string: "https://api.example.com/upload")!,
                                    uploadType: .multipart,
                                    configuration: UploadConfiguration()
                                ) { progress in
                                    uploadProgress = progress
                                }
                                
                                print("Upload successful: \(result.count) bytes")
                            } catch {
                                print("Upload failed: \(error)")
                            }
                            isUploading = false
                        }
                    }
                }
                .disabled(isUploading)
            } else if model.isLoading {
                ProgressView("Loading image...")
            } else {
                Button("Load Image") {
                    Task {
                        await model.loadImage(from: "https://example.com/image.jpg")
                    }
                }
            }
        }
        .task {
            await model.loadImage(from: "https://example.com/image.jpg")
        }
    }
}
```
