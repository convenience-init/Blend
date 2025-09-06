#if canImport(AppKit) && !canImport(UIKit)
    import AppKit
    import Foundation

    // MARK: - Platform Image Compatibility
    // This extension provides UIImage-like APIs for NSImage on macOS
    // Note: PlatformImage typealias is now defined in ImageService.swift

    extension NSImage {
        /// Returns the underlying CGImage representation
        @MainActor
        public var cgImage: CGImage? {
            // Ensure we're on main thread for AppKit compatibility
            assert(Thread.isMainThread, "NSImage.cgImage must be accessed from main thread")
            return cgImage(forProposedRect: nil, context: nil, hints: nil)
        }

        /// Creates JPEG data representation with compression quality
        /// - Parameter compressionQuality: Quality factor (0.0 to 1.0)
        /// - Returns: JPEG data or nil if conversion fails
        @MainActor
        public func jpegData(compressionQuality: CGFloat) async -> Data? {
            // Validate compression quality: reject NaN/inf and clamp to 0.0-1.0 range
            guard compressionQuality.isFinite else { return nil }
            let quality = min(max(compressionQuality, 0.0), 1.0)

            // First attempt: Direct TIFF conversion with validation
            if let data = await tiffRepresentationData() {
                return data.representation(
                    using: .jpeg,
                    properties: [.compressionFactor: quality]
                )
            }

            // Fallback: Rasterize the image and generate JPEG
            return await rasterizedJPEGData(compressionQuality: quality)
        }

        /// Creates PNG data representation
        /// - Returns: PNG data or nil if conversion fails
        @MainActor
        public func pngData() async -> Data? {
            // First attempt: Direct TIFF conversion with validation
            if let data = await tiffRepresentationData() {
                return data.representation(using: .png, properties: [:])
            }

            // Fallback: Rasterize the image into a fresh bitmap context
            // MainActor ensures this runs on the main thread for AppKit compatibility
            return await rasterizedPNGData()
        }

        /// Attempts to create a valid NSBitmapImageRep from the image's TIFF representation
        /// - Returns: Valid NSBitmapImageRep if TIFF conversion succeeds, nil otherwise
        @MainActor
        private func tiffRepresentationData() async -> NSBitmapImageRep? {
            guard let tiffData = tiffRepresentation,
                !tiffData.isEmpty,
                let bitmapRep = NSBitmapImageRep(data: tiffData),
                bitmapRep.pixelsWide > 0,
                bitmapRep.pixelsHigh > 0
            else {
                return nil
            }

            // Get current configuration limits
            let maxDimension = await AsyncNetConfig.shared.maxImageDimension
            let maxPixels = await AsyncNetConfig.shared.maxImagePixels

            // Safeguard against arbitrarily large dimensions to prevent unbounded memory allocation
            // Check individual dimensions
            guard bitmapRep.pixelsWide <= maxDimension,
                bitmapRep.pixelsHigh <= maxDimension
            else {
                return nil
            }

            // Check total pixel count to prevent excessive memory usage
            // Use multiplication that checks for overflow
            guard bitmapRep.pixelsWide <= Int.max / bitmapRep.pixelsHigh else {
                return nil  // Would overflow
            }
            let totalPixels = bitmapRep.pixelsWide * bitmapRep.pixelsHigh
            guard totalPixels <= maxPixels else {
                return nil
            }

            return bitmapRep
        }

        /// Rasterizes the image into a bitmap context and returns JPEG data
        /// - Parameter compressionQuality: Quality factor (0.0 to 1.0)
        /// - Returns: JPEG data or nil if rasterization fails
        @MainActor
        private func rasterizedJPEGData(compressionQuality: CGFloat) async -> Data? {
            // MainActor ensures this runs on the main thread for AppKit compatibility
            guard let bitmapRep = await rasterizedBitmap() else { return nil }
            return bitmapRep.representation(
                using: .jpeg,
                properties: [.compressionFactor: compressionQuality]
            )
        }

        /// Rasterizes the image into a bitmap context and returns PNG data
        /// - Returns: PNG data or nil if rasterization fails
        @MainActor
        private func rasterizedPNGData() async -> Data? {
            // MainActor ensures this runs on the main thread for AppKit compatibility
            guard let bitmapRep = await rasterizedBitmap() else { return nil }
            return bitmapRep.representation(using: .png, properties: [:])
        }

        /// Creates a rasterized bitmap representation of the image
        /// - Returns: NSBitmapImageRep containing the rasterized image, or nil if creation fails
        @MainActor
        private func rasterizedBitmap() async -> NSBitmapImageRep? {
            // MainActor ensures this runs on the main thread for AppKit compatibility
            return await rasterizedBitmapOnMainThread()
        }

        /// Creates a rasterized bitmap representation of the image (must be called on main thread)
        /// - Returns: NSBitmapImageRep containing the rasterized image, or nil if creation fails
        @MainActor
        private func rasterizedBitmapOnMainThread() async -> NSBitmapImageRep? {
            // Validate image and get dimensions
            guard let dimensions = await validateImageAndGetDimensions() else {
                return nil
            }

            // Create bitmap representation
            guard
                let bitmapRep = createBitmapRepresentation(
                    pixelsWide: dimensions.width, pixelsHigh: dimensions.height)
            else {
                return nil
            }

            // Draw image to bitmap
            drawImageToBitmap(
                bitmapRep, pixelsWide: dimensions.width, pixelsHigh: dimensions.height)

            return bitmapRep
        }

        /// Validates the image and determines pixel dimensions
        /// - Returns: Pixel dimensions as (width: Int, height: Int), or nil if invalid
        @MainActor
        private func validateImageAndGetDimensions() async -> (width: Int, height: Int)? {
            // Validate image
            guard isValid else { return nil }

            // Get current configuration limits
            let maxDimension = await AsyncNetConfig.shared.maxImageDimension
            let maxPixels = await AsyncNetConfig.shared.maxImagePixels

            // Determine pixel dimensions from the best available source
            var pixelsWide: Int
            var pixelsHigh: Int

            if let bestRep = representations.sorted(by: {
                let area0 = $0.pixelsWide * $0.pixelsHigh
                let area1 = $1.pixelsWide * $1.pixelsHigh
                    return area0 < area1
            }).first {
                pixelsWide = bestRep.pixelsWide
                pixelsHigh = bestRep.pixelsHigh
            } else if let cgImage = cgImage(forProposedRect: nil, context: nil, hints: nil) {
                pixelsWide = cgImage.width
                pixelsHigh = cgImage.height
            } else {
                // Fallback to point size as a last resort
                let targetSize = size
                guard targetSize.width > 0, targetSize.height > 0 else { return nil }
                pixelsWide = Int(ceil(targetSize.width))
                pixelsHigh = Int(ceil(targetSize.height))
            }

            // Safeguard against arbitrarily large dimensions to prevent unbounded memory allocation
            guard pixelsWide <= maxDimension, pixelsHigh <= maxDimension else {
                return nil
            }

            // Check total pixel count to prevent excessive memory usage
            guard pixelsWide <= Int.max / pixelsHigh else {
                return nil  // Would overflow
            }
            let totalPixels = pixelsWide * pixelsHigh
            guard totalPixels <= maxPixels else {
                return nil
            }

            // Validate that ceiled dimensions are valid
            guard pixelsWide > 0, pixelsHigh > 0 else {
                return nil
            }

            return (width: pixelsWide, height: pixelsHigh)
        }

        /// Creates a bitmap representation with the specified dimensions
        /// - Parameters:
        ///   - pixelsWide: Width in pixels
        ///   - pixelsHigh: Height in pixels
        /// - Returns: Configured NSBitmapImageRep, or nil if creation fails
        @MainActor
        private func createBitmapRepresentation(pixelsWide: Int, pixelsHigh: Int) -> NSBitmapImageRep? {
            let bitmapRep = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: pixelsWide,
                pixelsHigh: pixelsHigh,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .deviceRGB,
                bytesPerRow: 0,
                bitsPerPixel: 32
            )

            return bitmapRep
        }

        /// Draws the image into the bitmap representation
        /// - Parameters:
        ///   - bitmapRep: The bitmap to draw into
        ///   - pixelsWide: Width in pixels
        ///   - pixelsHigh: Height in pixels
        @MainActor
        private func drawImageToBitmap(
            _ bitmapRep: NSBitmapImageRep, pixelsWide: Int, pixelsHigh: Int
        ) {
            // Set up graphics context for drawing
            NSGraphicsContext.saveGraphicsState()
            defer { NSGraphicsContext.restoreGraphicsState() }

            guard let context = NSGraphicsContext(bitmapImageRep: bitmapRep) else {
                return
            }

            NSGraphicsContext.current = context
            NSGraphicsContext.current?.imageInterpolation = .high

            // Draw the image into the bitmap context using the ceiled dimensions
            let destSize = NSSize(width: pixelsWide, height: pixelsHigh)
            let destRect = NSRect(origin: .zero, size: destSize)
            // Compute explicit source rect from the image's actual bounds
            let sourceRect = NSRect(origin: .zero, size: self.size)
            draw(in: destRect, from: sourceRect, operation: .copy, fraction: 1.0)
        }
    }

#endif
