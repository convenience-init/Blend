import Foundation
import Testing

@testable import AsyncNet

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

@Suite("Platform Abstraction Tests")
public struct PlatformAbstractionTests {

    #if canImport(AppKit) && !canImport(UIKit)
        /// Creates a test NSBitmapImageRep with standard parameters for testing
        @MainActor
        private func createTestBitmapImageRep(size: NSSize) -> NSBitmapImageRep? {
            return NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: Int(size.width),
                pixelsHigh: Int(size.height),
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            )
        }

        /// Draws a color in the current graphics context within the specified rectangle
        @MainActor
        private func drawColorInContext(color: NSColor, rect: NSRect) {
            NSGraphicsContext.saveGraphicsState()
            defer { NSGraphicsContext.restoreGraphicsState() }
            color.setFill()
            NSBezierPath(rect: rect).fill()
        }

        /// Helper to create and manage NSGraphicsContext for drawing operations
        /// - Parameters:
        ///   - bitmapRep: The NSBitmapImageRep to create context from
        ///   - drawingBlock: Closure to execute with the context set as current
        /// - Returns: True if context was successfully created and drawing block executed
        @MainActor
        private func withGraphicsContext(_ bitmapRep: NSBitmapImageRep, drawingBlock: () -> Void)
            -> Bool
        {
            guard let ctx = NSGraphicsContext(bitmapImageRep: bitmapRep) else {
                return false
            }
            let previousCtx = NSGraphicsContext.current
            NSGraphicsContext.current = ctx
            defer { NSGraphicsContext.current = previousCtx }
            drawingBlock()
            return true
        }
    #endif

    @Test public func testPlatformImageTypealias() {
        #if canImport(UIKit)
            let image = UIImage()
            let platformImage: PlatformImage = image
        // Type check is redundant since PlatformImage is a typealias for UIImage on iOS
        // The assignment above already proves the typealias works correctly
        #elseif canImport(AppKit)
            let image = NSImage(size: NSSize(width: 1, height: 1))
            let platformImage: PlatformImage = image
        // Type check is redundant since PlatformImage is a typealias for NSImage on macOS
        // The assignment above already proves the typealias works correctly
        #endif
    }

    @Test @MainActor public func testNSImageExtensionJPEGData() {
        #if canImport(AppKit) && !canImport(UIKit)
            let size = NSSize(width: 1, height: 1)
            guard let rep = createTestBitmapImageRep(size: size) else {
                Issue.record("Failed to create NSBitmapImageRep")
                return
            }
            let success = withGraphicsContext(rep) {
                drawColorInContext(color: .red, rect: NSRect(x: 0, y: 0, width: 1, height: 1))
            }
            guard success else {
                Issue.record("Failed to create NSGraphicsContext")
                return
            }
            let image = NSImage(size: size)
            image.addRepresentation(rep)
            let jpeg = image.jpegData(compressionQuality: 0.8)
            #expect(jpeg != nil)
            #expect(jpeg?.count ?? 0 > 0)

            // Verify JPEG Start Of Image (SOI) marker (0xFF 0xD8)
            if let jpegData = jpeg {
                #expect(jpegData.count >= 2, "JPEG data must be at least 2 bytes for SOI marker")
                #expect(jpegData[0] == 0xFF, "JPEG data must start with SOI marker 0xFF")
                #expect(jpegData[1] == 0xD8, "JPEG data must have SOI marker 0xD8 as second byte")
            }
        #endif
    }

    @Test @MainActor public func testNSImageExtensionPNGData() {
        #if canImport(AppKit) && !canImport(UIKit)
            let size = NSSize(width: 1, height: 1)
            guard let rep = createTestBitmapImageRep(size: size) else {
                Issue.record("Failed to create NSBitmapImageRep")
                return
            }
            let success = withGraphicsContext(rep) {
                drawColorInContext(color: .blue, rect: NSRect(x: 0, y: 0, width: 1, height: 1))
            }
            guard success else {
                Issue.record("Failed to create NSGraphicsContext")
                return
            }
            let image = NSImage(size: size)
            image.addRepresentation(rep)
            let png = image.pngData()
            #expect(png != nil)
            #expect(png?.count ?? 0 > 0)

            // Verify PNG file signature (8-byte magic sequence)
            if let pngData = png {
                #expect(pngData.count >= 8, "PNG data must be at least 8 bytes for file signature")
                let expectedSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
                let actualSignature = Array(pngData.prefix(8))
                #expect(
                    actualSignature == expectedSignature,
                    """
                    PNG file signature mismatch:
                    Expected: \(expectedSignature.map { String(format: "0x%02X", $0) }.joined(separator: " "))
                    Actual:   \(actualSignature.map { String(format: "0x%02X", $0) }.joined(separator: " "))
                    """)
            }
        #endif
    }

    @Test @MainActor public func testPlatformImageToData() {
        #if canImport(UIKit)
            // Render a 1x1 pixel image using UIGraphicsImageRenderer
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1))
            let image = renderer.image { ctx in
                ctx.cgContext.setFillColor(UIColor.green.cgColor)
                ctx.cgContext.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
            }
            let data = ImageService.platformImageToData(image)
            #expect(data != nil)
            #expect(data?.count ?? 0 > 0)
        #elseif canImport(AppKit)
            let size = NSSize(width: 1, height: 1)
            guard let rep = createTestBitmapImageRep(size: size) else {
                Issue.record("Failed to create NSBitmapImageRep")
                return
            }
            let success = withGraphicsContext(rep) {
                drawColorInContext(color: .green, rect: NSRect(x: 0, y: 0, width: 1, height: 1))
            }
            guard success else {
                Issue.record("Failed to create NSGraphicsContext")
                return
            }
            let image = NSImage(size: size)
            image.addRepresentation(rep)
            let data = ImageService.platformImageToData(image)
            #expect(data != nil)
            #expect(data?.count ?? 0 > 0)
        #endif
    }

    @Test @MainActor public func testNSImageExtensionZeroSizeImage() {
        #if canImport(AppKit) && !canImport(UIKit)
            // Test with zero-sized image
            let zeroSizeImage = NSImage(size: NSSize(width: 0, height: 0))
            #expect(zeroSizeImage.pngData() == nil)
            #expect(zeroSizeImage.jpegData(compressionQuality: 0.8) == nil)
        #endif
    }

    @Test @MainActor public func testNSImageExtensionRasterizationFallback() {
        #if canImport(AppKit) && !canImport(UIKit)
            // Test with image that has no TIFF encoder (forces rasterization)
            let customImage = NSImage(size: NSSize(width: 10, height: 10))

            // Create a custom image rep that has no TIFF encoder
            let customRep = NSCustomImageRep(size: NSSize(width: 10, height: 10), flipped: false) {
                rect in
                NSColor.blue.setFill()
                NSBezierPath(rect: rect).fill()
                return true
            }
            customImage.addRepresentation(customRep)

            // Both should succeed via rasterization fallback
            let customPngData = customImage.pngData()
            let customJpegData = customImage.jpegData(compressionQuality: 0.8)
            #expect(customPngData != nil)
            #expect(customJpegData != nil)
            #expect(customPngData?.count ?? 0 > 0)
            #expect(customJpegData?.count ?? 0 > 0)
        #endif
    }

    @Test @MainActor public func testNSImageExtensionCorruptedTIFFHandling() {
        #if canImport(AppKit) && !canImport(UIKit)
            // Test with actually corrupted TIFF data
            let corruptedImage = NSImage(size: NSSize(width: 10, height: 10))

            // Create a valid bitmap representation
            if let rep = createTestBitmapImageRep(size: NSSize(width: 10, height: 10)) {
                corruptedImage.addRepresentation(rep)

                // Get valid TIFF data from the original representation
                guard let validTiffData = rep.tiffRepresentation else {
                    Issue.record("Failed to get TIFF representation from valid bitmap")
                    return
                }

                // Corrupt the TIFF data by mutating a few bytes
                var corruptedTiffData = validTiffData
                if corruptedTiffData.count > 10 {
                    // Corrupt bytes in the TIFF header area (bytes 8-10)
                    corruptedTiffData[8] = 0xFF  // Corrupt version field
                    corruptedTiffData[9] = 0xFF  // Corrupt version field
                    corruptedTiffData[10] = 0x00  // Corrupt byte order marker
                }

                // Remove the original valid representation
                corruptedImage.removeRepresentation(rep)

                // Create a new bitmap representation from the corrupted TIFF data
                if let corruptedRep = NSBitmapImageRep(data: corruptedTiffData) {
                    // Add the corrupted TIFF representation to the image
                    corruptedImage.addRepresentation(corruptedRep)
                } else {
                    Issue.record("Failed to create NSBitmapImageRep from corrupted TIFF data")
                    return
                }
            }

            // The methods should still work via the fallback rasterization path
            let pngData = corruptedImage.pngData()
            let jpegData = corruptedImage.jpegData(compressionQuality: 0.8)

            // Both should succeed via rasterization fallback
            #expect(pngData != nil)
            #expect(jpegData != nil)
            #expect(pngData?.count ?? 0 > 0)
            #expect(jpegData?.count ?? 0 > 0)
        #endif
    }
}
