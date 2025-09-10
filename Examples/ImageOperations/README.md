# Image Operations Example

This example demonstrates comprehensive image handling capabilities in Blend, including downloading, uploading, caching, format conversion, and error handling.

## What You'll Learn

- How to download and cache images using `ImageService`
- Platform-specific image handling (UIKit/AppKit)
- Image format conversion (JPEG, PNG)
- Multipart and Base64 upload methods
- Image caching and cache management
- Batch image operations
- Error handling for image operations

## Key Components

### 1. Image Service Initialization

```swift
// Basic initialization
let imageService = ImageService()

// With custom cache configuration
let imageService = ImageService(cacheCountLimit: 100, cacheTotalCostLimit: 50 * 1024 * 1024)
```

### 2. Image Downloading

```swift
// Download image data
let imageData = try await imageService.fetchImageData(from: "https://example.com/image.jpg")

// Convert to platform image
#if canImport(UIKit)
let platformImage = UIImage(data: imageData)
#elseif canImport(AppKit)
let platformImage = NSImage(data: imageData)
#endif

// Convert to SwiftUI Image
let swiftUIImage = Image.from(platformImage: platformImage)
```

### 3. Image Format Conversion

```swift
// JPEG conversion with compression
let jpegData = platformImage.jpegData(compressionQuality: 0.8)

// PNG conversion (lossless)
let pngData = platformImage.pngData()
```

### 4. Image Upload

```swift
// Multipart upload (recommended for large files)
let multipartResponse = try await imageService.uploadImageMultipart(
    imageData,
    to: uploadURL,
    configuration: ImageService.UploadConfiguration(
        fieldName: "image",
        fileName: "photo.jpg",
        compressionQuality: 0.9,
        additionalFields: ["title": "My Photo"]
    )
)

// Base64 upload (for JSON APIs)
let base64Response = try await imageService.uploadImageBase64(
    imageData,
    to: uploadURL,
    configuration: uploadConfig
)
```

### 5. Cache Management

```swift
// Check if image is cached
let isCached = await imageService.isImageCached(forKey: imageURL)

// Clear cache
await imageService.clearCache()

// Remove specific image from cache
await imageService.removeFromCache(key: imageURL)
```

## Running the Example

```bash
cd Examples/ImageOperations
swift run
```

## Expected Output

```
🚀 Blend Image Operations Example
=================================

📥 1. Downloading image...
✅ Downloaded 12345 bytes of image data

🔄 2. Converting image data to platform image...
✅ Created UIImage: 400x300

🎨 3. Converting to SwiftUI Image...
✅ Created SwiftUI Image

📦 4. Converting image formats...
✅ JPEG conversion: 8765 bytes (80% quality)
✅ PNG conversion: 12345 bytes (lossless)

📤 5. Uploading image via multipart...
✅ Multipart upload successful
   Response size: 1024 bytes

📤 6. Uploading image via Base64...
✅ Base64 upload successful
   Response size: 1024 bytes

💾 7. Testing image caching...
   Initially cached: false
   After fetch cached: true
   After clear cached: false

📚 8. Batch image operations...
✅ Downloaded 3 images:
   • image: 5432 bytes
   • image: 5678 bytes
   • image: 5234 bytes

⚠️ 9. Testing error handling...
✅ Caught expected network error: The operation couldn't be completed
✅ Caught expected upload error: The operation couldn't be completed

🎉 Image Operations Example completed successfully!
```

## Platform-Specific Handling

### iOS (UIKit)
```swift
import UIKit

// Create UIImage from data
let uiImage = UIImage(data: imageData)

// Convert to SwiftUI Image
let swiftUIImage = Image(uiImage: uiImage)

// Format conversion
let jpegData = uiImage.jpegData(compressionQuality: 0.8)
let pngData = uiImage.pngData()
```

### macOS (AppKit)
```swift
import AppKit

// Create NSImage from data
let nsImage = NSImage(data: imageData)

// Convert to SwiftUI Image
let swiftUIImage = Image(nsImage: nsImage)

// Format conversion (requires Blend extensions)
let jpegData = nsImage.jpegData(compressionQuality: 0.8)
let pngData = nsImage.pngData()
```

## Upload Methods Comparison

| Method | Pros | Cons | Use Case |
|--------|------|------|----------|
| **Multipart** | Binary data, efficient, no size limit | More complex | Large files, images |
| **Base64** | Simple, JSON-compatible | ~33% size increase, memory intensive | Small files, JSON APIs |

## Error Handling

The example demonstrates comprehensive error handling:

```swift
do {
    let imageData = try await imageService.fetchImageData(from: url)
} catch let error as NetworkError {
    switch error {
    case .httpError(let statusCode, _):
        print("HTTP Error: \(statusCode)")
    case .networkUnavailable:
        print("No internet connection")
    case .uploadFailed(let details):
        print("Upload failed: \(details)")
    case .imageProcessingFailed:
        print("Image processing failed")
    default:
        print("Network error: \(error.message())")
    }
}
```

## API Used

This example uses:
- **[Lorem Picsum](https://picsum.photos/)** - Random image generation for testing
- **[HTTPBin](https://httpbin.org/)** - HTTP request/response testing service

## Performance Considerations

- **Caching**: Images are automatically cached after first download
- **Format Selection**: Use JPEG for photos, PNG for graphics with transparency
- **Compression**: Balance quality vs file size (0.8 compression is usually optimal)
- **Batch Operations**: Use `TaskGroup` for concurrent image processing

## Next Steps

After understanding this image operations example, check out:
- [Error Handling](../ErrorHandling/) - Comprehensive error scenarios
- [SwiftUI Integration](../SwiftUIIntegration/) - UI integration patterns

## Files

- `Package.swift` - Swift Package configuration
- `Sources/ImageOperations/main.swift` - Main example implementation
- `README.md` - This documentation