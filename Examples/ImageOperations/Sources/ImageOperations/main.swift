import Blend
import Foundation

// MARK: - Platform Image Import
#if canImport(UIKit)
    import UIKit
#endif

#if canImport(AppKit)
    import AppKit
#endif

#if canImport(SwiftUI)
    import SwiftUI
#endif

@main
struct ImageOperationsExample {
    static func main() async {
        blendLogger.info("🚀 Blend Image Operations Example")
        blendLogger.info("=================================\n")

        // Initialize image service with custom configuration
        let imageService = ImageService()

        do {
            // 1. IMAGE DOWNLOAD - Basic image fetching
            blendLogger.info("📥 1. Downloading image...")
            let imageURL = "https://picsum.photos/400/300"  // Random image from Lorem Picsum
            let imageData = try await imageService.fetchImageData(from: imageURL)
            blendLogger.info("✅ Downloaded \(imageData.count) bytes of image data")
            blendLogger.info("")

            // 2. IMAGE CONVERSION - Convert data to platform image
            blendLogger.info("🔄 2. Converting image data to platform image...")
            #if canImport(UIKit)
                guard let uiImage = UIImage(data: imageData) else {
                    throw NSError(
                        domain: "ImageOperations", code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "Failed to create UIImage"])
                }
                let platformImage = uiImage
                blendLogger.info("✅ Created UIImage: \(Int(uiImage.size.width))x\(Int(uiImage.size.height))")
            #elseif canImport(AppKit)
                guard let nsImage = NSImage(data: imageData) else {
                    throw NSError(
                        domain: "ImageOperations", code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "Failed to create NSImage"])
                }
                let platformImage = nsImage
                blendLogger.info("✅ Created NSImage: \(Int(nsImage.size.width))x\(Int(nsImage.size.height))")
            #endif
            blendLogger.info("")

            // 3. IMAGE CONVERSION - Convert to SwiftUI Image
            blendLogger.info("🎨 3. Converting to SwiftUI Image...")
            #if canImport(SwiftUI)
                // Convert data to PlatformImage first
                if let platformImage = ImageService.platformImage(from: imageData) {
                    // Then convert PlatformImage to SwiftUI Image
                    _ = Image.from(platformImage: platformImage)
                    blendLogger.info("✅ Created SwiftUI Image")
                } else {
                    blendLogger.info("❌ Failed to create PlatformImage from data")
                }
            #endif
            blendLogger.info("")

            // 4. IMAGE FORMAT CONVERSION - JPEG and PNG
            blendLogger.info("📦 4. Converting image formats...")

            // JPEG conversion with compression
            if let jpegData = await platformImage.jpegData(compressionQuality: 0.8) {
                blendLogger.info("✅ JPEG conversion: \(jpegData.count) bytes (80% quality)")
            } else {
                blendLogger.info("❌ JPEG conversion failed")
            }

            // PNG conversion (lossless)
            if let pngData = await platformImage.pngData() {
                blendLogger.info("✅ PNG conversion: \(pngData.count) bytes (lossless)")
            } else {
                blendLogger.info("❌ PNG conversion failed")
            }
            blendLogger.info("")

            // 5. IMAGE UPLOAD - Multipart form upload
            blendLogger.info("📤 5. Uploading image via multipart...")
            let uploadURL = URL(string: "https://httpbin.org/post")!  // Test endpoint that echoes back data

            let uploadConfig = UploadConfiguration(
                fieldName: "image",
                fileName: "sample_image.jpg",
                additionalFields: [
                    "title": "Sample Image",
                    "description": "Uploaded via Blend ImageOperations example",
                ]
            )

            let multipartResponse = try await imageService.uploadImageMultipart(
                imageData,
                to: uploadURL,
                configuration: uploadConfig
            )
            blendLogger.info("✅ Multipart upload successful")
            blendLogger.info("   Response size: \(multipartResponse.count) bytes")
            blendLogger.info("")

            // 6. IMAGE UPLOAD - Base64 upload
            blendLogger.info("📤 6. Uploading image via Base64...")
            let base64Response = try await imageService.uploadImageBase64(
                imageData,
                to: uploadURL,
                configuration: uploadConfig
            )
            blendLogger.info("✅ Base64 upload successful")
            blendLogger.info("   Response size: \(base64Response.count) bytes")
            blendLogger.info("")

            // 7. CACHE OPERATIONS - Testing cache functionality
            blendLogger.info("💾 7. Testing image caching...")

            // Check if image is cached (should be false initially)
            let isInitiallyCached = await imageService.isImageCached(forKey: imageURL)
            blendLogger.info("   Initially cached: \(isInitiallyCached)")

            // Fetch again to cache it
            _ = try await imageService.fetchImageData(from: imageURL)

            // Check if image is now cached
            let isNowCached = await imageService.isImageCached(forKey: imageURL)
            blendLogger.info("   After fetch cached: \(isNowCached)")

            // Clear cache
            await imageService.clearCache()
            let isCachedAfterClear = await imageService.isImageCached(forKey: imageURL)
            blendLogger.info("   After clear cached: \(isCachedAfterClear)")
            blendLogger.info("")

            // 8. BATCH IMAGE OPERATIONS - Multiple images
            blendLogger.info("📚 8. Batch image operations...")
            let imageURLs = [
                "https://picsum.photos/200/200?random=1",
                "https://picsum.photos/200/200?random=2",
                "https://picsum.photos/200/200?random=3",
            ]

            // Download multiple images concurrently
            let batchResults = try await withThrowingTaskGroup(of: (String, Data).self) { group in
                for url in imageURLs {
                    group.addTask {
                        let data = try await imageService.fetchImageData(from: url)
                        return (url, data)
                    }
                }

                var results: [(String, Data)] = []
                for try await result in group {
                    results.append(result)
                }
                return results
            }

            blendLogger.info("✅ Downloaded \(batchResults.count) images:")
            for (url, data) in batchResults {
                blendLogger.info("   • \(URL(string: url)?.lastPathComponent ?? "image"): \(data.count) bytes")
            }
            blendLogger.info("")

            // 9. ERROR HANDLING - Testing error scenarios
            blendLogger.info("⚠️ 9. Testing error handling...")

            do {
                // Try to fetch from invalid URL
                _ = try await imageService.fetchImageData(
                    from: "https://invalid-domain-that-does-not-exist.com/image.jpg")
            } catch let error as NetworkError {
                blendLogger.info("✅ Caught expected network error: \(error.localizedDescription)")
            }

            do {
                // Try to upload to invalid URL
                _ = try await imageService.uploadImageMultipart(
                    imageData,
                    to: URL(string: "https://invalid-domain-that-does-not-exist.com/upload")!,
                    configuration: uploadConfig
                )
            } catch let error as NetworkError {
                blendLogger.info("✅ Caught expected upload error: \(error.localizedDescription)")
            }
            blendLogger.info("")

            blendLogger.info("🎉 Image Operations Example completed successfully!")
            blendLogger.info("\nThis example demonstrated:")
            blendLogger.info("• Image downloading and data conversion")
            blendLogger.info("• Platform-specific image handling (UIKit/AppKit)")
            blendLogger.info("• SwiftUI Image integration")
            blendLogger.info("• Multiple image format conversions (JPEG/PNG)")
            blendLogger.info("• Multipart and Base64 upload methods")
            blendLogger.info("• Image caching operations")
            blendLogger.info("• Batch/concurrent image processing")
            blendLogger.info("• Comprehensive error handling")

        } catch let error as NetworkError {
            blendLogger.info("❌ Network Error: \(error.localizedDescription)")
            switch error {
            case .httpError(let statusCode, _):
                blendLogger.info("   HTTP Status: \(statusCode)")
            case .networkUnavailable:
                blendLogger.info("   No internet connection")
            case .decodingError(let description, _):
                blendLogger.info("   Decoding failed: \(description)")
            case .uploadFailed(let details):
                blendLogger.info("   Upload failed: \(details)")
            case .imageProcessingFailed:
                blendLogger.info("   Image processing failed")
            default:
                blendLogger.info("   Other network error: \(error.localizedDescription)")
            }
        } catch {
            blendLogger.info("❌ Unexpected Error: \(error.localizedDescription)")
        }
    }
}
