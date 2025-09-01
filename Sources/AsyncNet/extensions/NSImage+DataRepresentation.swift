#if canImport(AppKit) && !canImport(UIKit)
    import AppKit

    // MARK: - Platform Image Compatibility
    // This extension provides UIImage-like APIs for NSImage on macOS
    // Note: PlatformImage typealias is now defined in ImageService.swift

    extension NSImage {
        /// Returns the underlying CGImage representation
        public var cgImage: CGImage? {
            return cgImage(forProposedRect: nil, context: nil, hints: nil)
        }

        /// Creates JPEG data representation with compression quality
        /// - Parameter compressionQuality: Quality factor (0.0 to 1.0)
        /// - Returns: JPEG data or nil if conversion fails
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
        public func pngData() -> Data? {
            // First attempt: Direct TIFF conversion with validation
            if let data = tiffRepresentationData() {
                return data.representation(using: .png, properties: [:])
            }

            // Fallback: Rasterize the image into a fresh bitmap context
            return rasterizedPNGData()
        }

        /// Attempts to create a valid NSBitmapImageRep from the image's TIFF representation
        /// - Returns: Valid NSBitmapImageRep if TIFF conversion succeeds, nil otherwise
        private func tiffRepresentationData() -> NSBitmapImageRep? {
            guard let tiffData = tiffRepresentation,
                !tiffData.isEmpty,
                let bitmapRep = NSBitmapImageRep(data: tiffData),
                bitmapRep.pixelsWide > 0,
                bitmapRep.pixelsHigh > 0
            else {
                return nil
            }
            return bitmapRep
        }

        /// Rasterizes the image into a bitmap context and returns JPEG data
        /// - Parameter compressionQuality: Quality factor (0.0 to 1.0)
        /// - Returns: JPEG data or nil if rasterization fails
        private func rasterizedJPEGData(compressionQuality: CGFloat) -> Data? {
            guard let bitmapRep = rasterizedBitmap() else { return nil }

            // Generate JPEG data from the rasterized bitmap
            return bitmapRep.representation(
                using: .jpeg,
                properties: [.compressionFactor: compressionQuality]
            )
        }

        /// Rasterizes the image into a bitmap context and returns PNG data
        /// - Returns: PNG data or nil if rasterization fails
        private func rasterizedPNGData() -> Data? {
            guard let bitmapRep = rasterizedBitmap() else { return nil }

            // Generate PNG data from the rasterized bitmap
            return bitmapRep.representation(using: .png, properties: [:])
        }

        /// Creates a rasterized bitmap representation of the image
        /// - Returns: NSBitmapImageRep containing the rasterized image, or nil if creation fails
        private func rasterizedBitmap() -> NSBitmapImageRep? {
            assert(
                Thread.isMainThread,
                "rasterizedBitmap() uses AppKit drawing and must run on the main thread")

            let targetSize = size

            // Ensure we have valid dimensions
            guard targetSize.width > 0, targetSize.height > 0 else {
                return nil
            }

            // Calculate pixel dimensions using ceiling to prevent clipping
            let pixelsWide = Int(ceil(targetSize.width))
            let pixelsHigh = Int(ceil(targetSize.height))

            // Safeguard against arbitrarily large dimensions to prevent unbounded memory allocation
            let MAX_DIMENSION = 16384  // 16K pixels max per dimension (reasonable for most use cases)
            let MAX_PIXELS = 100 * 1024 * 1024  // 100M pixels max total (approx 400MB at 32bpp)

            // Check individual dimensions
            guard pixelsWide <= MAX_DIMENSION, pixelsHigh <= MAX_DIMENSION else {
                return nil
            }

            // Check total pixel count to prevent excessive memory usage
            // Use multiplication that checks for overflow
            guard pixelsWide <= Int.max / pixelsHigh else {
                return nil  // Would overflow
            }
            let totalPixels = pixelsWide * pixelsHigh
            guard totalPixels <= MAX_PIXELS else {
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
                    colorSpaceName: .deviceRGB,
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

            // Draw the image into the bitmap context using the ceiled dimensions
            let bitmapSize = NSSize(width: pixelsWide, height: pixelsHigh)
            let rect = NSRect(origin: .zero, size: bitmapSize)
            draw(
                in: rect, from: NSRect(origin: .zero, size: targetSize), operation: .copy,
                fraction: 1.0)

            return bitmapRep
        }
    }

#endif
