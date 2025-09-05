#if canImport(AppKit) && !canImport(UIKit)
    import AppKit

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

        // Constants for dimension and pixel count limits to prevent excessive memory usage
        private static let maxDimension = 16384  // 16K pixels max per dimension (reasonable for most use cases)
        private static let maxTotalPixels = 100 * 1024 * 1024  // 100M pixels max total (approx 400MB at 32bpp)

        /// Creates JPEG data representation with compression quality
        /// - Parameter compressionQuality: Quality factor (0.0 to 1.0)
        /// - Returns: JPEG data or nil if conversion fails
        @MainActor
        public func jpegData(compressionQuality: CGFloat) -> Data? {
            // Validate compression quality: reject NaN/inf and clamp to 0.0-1.0 range
            guard compressionQuality.isFinite else { return nil }
            let quality = min(max(compressionQuality, 0.0), 1.0)

            // First attempt: Direct TIFF conversion with validation
            if let data = tiffRepresentationData() {
                return data.representation(
                    using: .jpeg,
                    properties: [.compressionFactor: quality]
                )
            }

            // Fallback: Rasterize the image and generate JPEG
            return rasterizedJPEGData(compressionQuality: quality)
        }

        /// Creates PNG data representation
        /// - Returns: PNG data or nil if conversion fails
        @MainActor
        public func pngData() -> Data? {
            // First attempt: Direct TIFF conversion with validation
            if let data = tiffRepresentationData() {
                return data.representation(using: .png, properties: [:])
            }

            // Fallback: Rasterize the image into a fresh bitmap context
            // MainActor ensures this runs on the main thread for AppKit compatibility
            return rasterizedPNGData()
        }

        /// Attempts to create a valid NSBitmapImageRep from the image's TIFF representation
        /// - Returns: Valid NSBitmapImageRep if TIFF conversion succeeds, nil otherwise
        @MainActor
        private func tiffRepresentationData() -> NSBitmapImageRep? {
            guard let tiffData = tiffRepresentation,
                !tiffData.isEmpty,
                let bitmapRep = NSBitmapImageRep(data: tiffData),
                bitmapRep.pixelsWide > 0,
                bitmapRep.pixelsHigh > 0
            else {
                return nil
            }

            // Safeguard against arbitrarily large dimensions to prevent unbounded memory allocation
            // Check individual dimensions
            guard bitmapRep.pixelsWide <= Self.maxDimension,
                bitmapRep.pixelsHigh <= Self.maxDimension
            else {
                return nil
            }

            // Check total pixel count to prevent excessive memory usage
            // Use multiplication that checks for overflow
            guard bitmapRep.pixelsWide <= Int.max / bitmapRep.pixelsHigh else {
                return nil  // Would overflow
            }
            let totalPixels = bitmapRep.pixelsWide * bitmapRep.pixelsHigh
            guard totalPixels <= Self.maxTotalPixels else {
                return nil
            }

            return bitmapRep
        }

        /// Rasterizes the image into a bitmap context and returns JPEG data
        /// - Parameter compressionQuality: Quality factor (0.0 to 1.0)
        /// - Returns: JPEG data or nil if rasterization fails
        @MainActor
        private func rasterizedJPEGData(compressionQuality: CGFloat) -> Data? {
            // MainActor ensures this runs on the main thread for AppKit compatibility
            guard let bitmapRep = rasterizedBitmap() else { return nil }
            return bitmapRep.representation(
                using: .jpeg,
                properties: [.compressionFactor: compressionQuality]
            )
        }

        /// Rasterizes the image into a bitmap context and returns PNG data
        /// - Returns: PNG data or nil if rasterization fails
        @MainActor
        private func rasterizedPNGData() -> Data? {
            // MainActor ensures this runs on the main thread for AppKit compatibility
            guard let bitmapRep = rasterizedBitmap() else { return nil }
            return bitmapRep.representation(using: .png, properties: [:])
        }

        /// Creates a rasterized bitmap representation of the image
        /// - Returns: NSBitmapImageRep containing the rasterized image, or nil if creation fails
        @MainActor
        private func rasterizedBitmap() -> NSBitmapImageRep? {
            // MainActor ensures this runs on the main thread for AppKit compatibility
            return rasterizedBitmapOnMainThread()
        }

        /// Creates a rasterized bitmap representation of the image (must be called on main thread)
        /// - Returns: NSBitmapImageRep containing the rasterized image, or nil if creation fails
        @MainActor
        private func rasterizedBitmapOnMainThread() -> NSBitmapImageRep? {
            // Prevent quality loss: derive pixel dimensions from the best available rep (not points)
            // Using NSImage.size (points) can downscale high‑DPI images where size ≠ pixel dimensions.
            // Prefer the largest NSBitmapImageRep or fall back to CGImage dimensions, then rasterize.
            // Also switch to sRGB and enable high interpolation for better color fidelity and scaling.

            // Validate image
            guard isValid else { return nil }

            // Determine pixel dimensions from the best available source
            var pixelsWide: Int
            var pixelsHigh: Int

            if let bestRep =
                representations
                .max(by: {
                    // Use Int64 to prevent overflow when calculating area
                    let area0 = Int64($0.pixelsWide) * Int64($0.pixelsHigh)
                    let area1 = Int64($1.pixelsWide) * Int64($1.pixelsHigh)
                    return area0 < area1
                })
            {
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
            // Check individual dimensions
            guard pixelsWide <= Self.maxDimension, pixelsHigh <= Self.maxDimension else {
                return nil
            }

            // Check total pixel count to prevent excessive memory usage
            // Use multiplication that checks for overflow
            guard pixelsWide <= Int.max / pixelsHigh else {
                return nil  // Would overflow
            }
            let totalPixels = pixelsWide * pixelsHigh
            guard totalPixels <= Self.maxTotalPixels else {
                return nil
            }

            // Validate that ceiled dimensions are valid
            guard pixelsWide > 0, pixelsHigh > 0 else {
                return nil
            }

            // Create bitmap representation with proper configuration
            guard
                let bitmapRep = NSBitmapImageRep(
                    bitmapDataPlanes: nil,
                    pixelsWide: pixelsWide,
                    pixelsHigh: pixelsHigh,
                    bitsPerSample: 8,
                    samplesPerPixel: 4,
                    hasAlpha: true,
                    isPlanar: false,
                    colorSpaceName: .calibratedRGB,
                    bytesPerRow: 0,
                    bitsPerPixel: 32
                )
            else {
                return nil
            }

            // Set up graphics context for drawing
            NSGraphicsContext.saveGraphicsState()
            defer { NSGraphicsContext.restoreGraphicsState() }

            guard let context = NSGraphicsContext(bitmapImageRep: bitmapRep) else {
                return nil
            }

            NSGraphicsContext.current = context
            NSGraphicsContext.current?.imageInterpolation = .high

            // Draw the image into the bitmap context using the ceiled dimensions
            let destSize = NSSize(width: pixelsWide, height: pixelsHigh)
            let destRect = NSRect(origin: .zero, size: destSize)
            // Compute explicit source rect from the image's actual bounds
            let sourceRect = NSRect(origin: .zero, size: self.size)
            draw(in: destRect, from: sourceRect, operation: .copy, fraction: 1.0)

            return bitmapRep
        }
    }

#endif
