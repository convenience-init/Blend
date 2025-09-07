# Blend API Documentation

## Overview

Blend is a modern Swift networking library built for iOS 18+ and macOS 15+ with full Swift 6 strict concurrency compliance. This documentation provides a comprehensive reference for all public APIs.

## Core Protocols

### AsyncRequestable

The foundation protocol for basic networking services that require a single response type.

```swift
protocol AsyncRequestable<ResponseModel: Decodable> {
    associatedtype ResponseModel: Decodable

    func sendRequest<T: Decodable>(_ type: T.Type, to endpoint: Endpoint) async throws -> T
}
```

**Key Features:**
- Type-safe network requests with async/await
- Single response type per service
- Automatic JSON decoding
- Error handling with NetworkError

**Usage:**
```swift
class UserService: AsyncRequestable {
    typealias ResponseModel = [User]

    func getUsers() async throws -> [User] {
        return try await sendRequest(to: UsersEndpoint())
    }
}
```

### AdvancedAsyncRequestable

Extended protocol for complex services requiring multiple response types, such as master-detail patterns.

```swift
protocol AdvancedAsyncRequestable: AsyncRequestable {
    associatedtype SecondaryResponseModel: Decodable

    func sendRequest<T: Decodable>(_ type: T.Type, to endpoint: Endpoint) async throws -> T
}
```

**Key Features:**
- Dual response types (ResponseModel + SecondaryResponseModel)
- Convenience methods: `fetchList()` and `fetchDetails()`
- Support for CRUD operations with different response types
- Type-safe service hierarchies

**Usage:**
```swift
class ProductService: AdvancedAsyncRequestable {
    typealias ResponseModel = [ProductSummary]
    typealias SecondaryResponseModel = ProductDetails

    func getProducts() async throws -> [ProductSummary] {
        return try await fetchList(from: ProductsEndpoint())
    }

    func getProduct(id: String) async throws -> ProductDetails {
        return try await fetchDetails(from: ProductDetailsEndpoint(id: id))
    }
}
```

## Networking Components

### Endpoint

Protocol defining the structure of network endpoints.

```swift
protocol Endpoint {
    var scheme: URLScheme { get }
    var host: String { get }
    var path: String { get }
    var method: RequestMethod { get }
    var headers: [String: String]? { get }
    var body: Data? { get }
    var queryItems: [URLQueryItem]? { get }
    var timeoutDuration: Duration? { get }
}
```

### RequestMethod

HTTP request methods supported by Blend.

```swift
enum RequestMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
    case patch = "PATCH"
    case head = "HEAD"
}
```

### URLScheme

URL schemes for network requests.

```swift
enum URLScheme: String {
    case http
    case https
}
```

## Image Service

### ImageService

Actor-isolated service for comprehensive image operations.

```swift
actor ImageService {
    // Download operations
    func fetchImageData(from urlString: String) async throws -> Data
    func cachedImage(forKey key: String) -> PlatformImage?

    // Upload operations
    func uploadImageMultipart(_ imageData: Data, to url: URL, configuration: UploadConfiguration) async throws -> Data
    func uploadImageBase64(_ imageData: Data, to url: URL, configuration: UploadConfiguration) async throws -> Data

    // Cache management
    func clearCache() async
    func removeFromCache(key: String) async
    func isImageCached(forKey key: String) async -> Bool

    // Configuration
    func setInterceptors(_ interceptors: [RequestInterceptor])
    func setRetryConfiguration(_ config: RetryConfiguration)
}
```

### UploadConfiguration

Configuration for image uploads.

```swift
struct UploadConfiguration {
    let fieldName: String
    let fileName: String
    let compressionQuality: CGFloat
    let additionalFields: [String: String]
}
```

### PlatformImage

Cross-platform image type alias.

```swift
#if canImport(UIKit)
    public typealias PlatformImage = UIImage
#elseif canImport(AppKit)
    public typealias PlatformImage = NSImage
#endif
```

## SwiftUI Integration

### AsyncImageModel

Observable view model for async image loading and uploading.

```swift
@MainActor
@Observable
class AsyncImageModel {
    var loadedImage: PlatformImage?
    var isLoading: Bool
    var hasError: Bool
    var isUploading: Bool
    var error: NetworkError?

    func loadImage(from url: String?) async
    func uploadImage(_ image: PlatformImage, to url: URL, uploadType: UploadType, configuration: UploadConfiguration) async
}
```

### View Extensions

SwiftUI view extensions for async image loading.

```swift
extension View {
    func asyncImage(
        from url: String?,
        imageService: ImageService,
        placeholder: some View,
        errorView: some View
    ) -> some View
}
```

### AsyncNetImageView

Complete SwiftUI view for image display with upload capabilities.

```swift
struct AsyncNetImageView: View {
    let url: String?
    let uploadURL: URL?
    let uploadType: UploadType
    let configuration: ImageService.UploadConfiguration
    let onUploadSuccess: ((Data) -> Void)?
    let onUploadError: ((NetworkError) -> Void)?
    let imageService: ImageService
}
```

## Error Handling

### NetworkError

Comprehensive error enum for all network operations.

```swift
enum NetworkError: Error {
    case httpError(statusCode: Int, data: Data?)
    case decodingError(underlyingDescription: String, data: Data?)
    case networkUnavailable
    case requestTimeout(duration: TimeInterval)
    case invalidEndpoint(reason: String)
    case unauthorized
    case noResponse
    case badMimeType(String)
    case uploadFailed(String)
    case imageProcessingFailed
    case cacheError(String)
    case transportError(code: URLError.Code, underlying: URLError)
}
```

**Error Categories:**
- **HTTP Errors**: Status code and response data
- **Decoding Errors**: JSON parsing failures
- **Network Errors**: Connectivity and timeout issues
- **Authentication Errors**: Unauthorized access
- **Image Errors**: Processing and upload failures
- **Cache Errors**: Storage and retrieval issues
- **Transport Errors**: Low-level network failures

## Configuration

### RetryConfiguration

Configuration for retry/backoff logic.

```swift
struct RetryConfiguration {
    let maxAttempts: Int
    let baseDelay: TimeInterval
    let jitter: TimeInterval
    let maxDelay: TimeInterval
    let shouldRetry: (@Sendable (Error) -> Bool)?
    let backoff: (@Sendable (Int) -> TimeInterval)?
}
```

### CacheConfiguration

Configuration for image caching.

```swift
struct CacheConfiguration {
    let countLimit: Int
    let totalCostLimit: Int
    let maxAge: TimeInterval
}
```

## Platform Support

### Supported Platforms

- **iOS**: 18.0+ (includes iPadOS 18.0+)
- **macOS**: 15.0+
- **Swift**: 6.0+
- **Xcode**: 16.0+

### Platform-Specific Extensions

#### NSImage Extensions (macOS)

```swift
extension NSImage {
    func jpegData(compressionQuality: CGFloat) -> Data?
    func pngData() -> Data?
}
```

#### Image Extensions (Cross-platform)

```swift
extension Image {
    static func from(platformImage: PlatformImage) -> Image
}
```

## Security Considerations

### Cache Management for Sensitive Data

- Use `ImageService` with appropriate cache limits
- Implement cache clearing for sensitive sessions
- Avoid caching PII-containing images
- Use short `maxAge` for sensitive content

### Request Interceptors

```swift
protocol RequestInterceptor {
    func intercept(request: URLRequest) async throws -> URLRequest
}
```

## Best Practices

### Service Design

1. **Choose the Right Protocol**: Use `AsyncRequestable` for simple services, `AdvancedAsyncRequestable` for complex ones
2. **Dependency Injection**: Always inject `ImageService` for testability
3. **Error Handling**: Use specific `NetworkError` cases for proper error handling
4. **Platform Abstraction**: Use `PlatformImage` and cross-platform helpers

### Performance Optimization

1. **Caching**: Configure appropriate cache limits based on use case
2. **Retry Logic**: Use `RetryConfiguration` for resilient network operations
3. **Request Deduplication**: Automatic deduplication prevents duplicate requests
4. **Background Processing**: Use actor isolation for thread safety

### Testing

1. **Mock Services**: Use dependency injection for testable services
2. **Error Simulation**: Test error scenarios with `NetworkError` cases
3. **Platform Testing**: Test on both iOS and macOS platforms
4. **Async Testing**: Use Swift 6 concurrency testing patterns

## Migration Guide

### From Other Networking Libraries

1. **Replace URLSession calls** with Blend protocols
2. **Update error handling** to use `NetworkError`
3. **Implement dependency injection** for services
4. **Use SwiftUI extensions** for image loading

### Swift 6 Migration

1. **Enable strict concurrency** in Package.swift
2. **Use actor isolation** for shared state
3. **Adopt Sendable** for data types
4. **Update completion handlers** to async/await

## Troubleshooting

### Common Issues

1. **Platform Image Conversion**: Use `Image.from(platformImage:)` for cross-platform compatibility
2. **Cache Not Working**: Check cache limits and ensure proper initialization
3. **Upload Failures**: Verify `UploadConfiguration` and endpoint setup
4. **Timeout Issues**: Adjust `timeoutDuration` in endpoints

### Debug Information

- Enable logging for network requests
- Check `NetworkError` details for specific failure reasons
- Verify platform requirements (iOS 18+, macOS 15+)
- Test with Swift 6 toolchain

## Examples

See the main README.md for comprehensive usage examples covering:

- Basic network requests
- Advanced networking with multiple response types
- Image download and upload operations
- SwiftUI integration
- Error handling patterns
- Cache management
- Security best practices

---

*This documentation is automatically generated from source code comments and may be updated as the API evolves.*