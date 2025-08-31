#if canImport(AppKit) && !canImport(UIKit)
import AppKit

// MARK: - Platform Image Compatibility
// This extension provides UIImage-like APIs for NSImage on macOS
// Note: PlatformImage typealias is now defined in ImageService.swift

public extension NSImage {
    /// Returns the underlying CGImage representation
    var cgImage: CGImage? {
        var proposedRect = CGRect(origin: .zero, size: size)
        return cgImage(forProposedRect: &proposedRect, context: nil, hints: nil)
    }
    
    
    /// Creates JPEG data representation with compression quality
    /// - Parameter compressionQuality: Quality factor (0.0 to 1.0)
    /// - Returns: JPEG data or nil if conversion fails
    func jpegData(compressionQuality: CGFloat) -> Data? {
        // First attempt: Direct TIFF conversion with validation
        if let tiffData = tiffRepresentation,
           !tiffData.isEmpty,
           let bitmapRep = NSBitmapImageRep(data: tiffData),
           bitmapRep.pixelsWide > 0,
           bitmapRep.pixelsHigh > 0 {
            
            return bitmapRep.representation(
                using: .jpeg,
                properties: [.compressionFactor: compressionQuality]
            )
        }
        
        // Fallback: Rasterize the image and generate JPEG
        return rasterizedJPEGData(compressionQuality: compressionQuality)
    }
    
    /// Creates PNG data representation
    /// - Returns: PNG data or nil if conversion fails
    func pngData() -> Data? {
        // First attempt: Direct TIFF conversion with validation
        if let tiffData = tiffRepresentation,
           !tiffData.isEmpty,
           let bitmapRep = NSBitmapImageRep(data: tiffData),
           bitmapRep.pixelsWide > 0,
           bitmapRep.pixelsHigh > 0 {
            
            return bitmapRep.representation(using: .png, properties: [:])
        }
        
        // Fallback: Rasterize the image into a fresh bitmap context
        return rasterizedPNGData()
    }
    
    /// Rasterizes the image into a bitmap context and returns JPEG data
    /// - Parameter compressionQuality: Quality factor (0.0 to 1.0)
    /// - Returns: JPEG data or nil if rasterization fails
    private func rasterizedJPEGData(compressionQuality: CGFloat) -> Data? {
        let targetSize = size
        
        // Ensure we have valid dimensions
        guard targetSize.width > 0, targetSize.height > 0 else {
            return nil
        }
        
        // Create bitmap representation with proper configuration
        guard let bitmapRep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(targetSize.width),
            pixelsHigh: Int(targetSize.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 32
        ) else {
            return nil
        }
        
        // Set up graphics context for drawing
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        
        guard let context = NSGraphicsContext(bitmapImageRep: bitmapRep) else {
            return nil
        }
        
        NSGraphicsContext.current = context
        
        // Draw the image into the bitmap context
        let rect = NSRect(origin: .zero, size: targetSize)
        draw(in: rect, from: rect, operation: .copy, fraction: 1.0)
        
        // Generate JPEG data from the rasterized bitmap
        return bitmapRep.representation(
            using: .jpeg,
            properties: [.compressionFactor: compressionQuality]
        )
    }
    
    /// Rasterizes the image into a bitmap context and returns PNG data
    /// - Returns: PNG data or nil if rasterization fails
    private func rasterizedPNGData() -> Data? {
        let targetSize = size
        
        // Ensure we have valid dimensions
        guard targetSize.width > 0, targetSize.height > 0 else {
            return nil
        }
        
        // Create bitmap representation with proper configuration
        guard let bitmapRep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(targetSize.width),
            pixelsHigh: Int(targetSize.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 32
        ) else {
            return nil
        }
        
        // Set up graphics context for drawing
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        
        guard let context = NSGraphicsContext(bitmapImageRep: bitmapRep) else {
            return nil
        }
        
        NSGraphicsContext.current = context
        
        // Draw the image into the bitmap context
        let rect = NSRect(origin: .zero, size: targetSize)
        draw(in: rect, from: rect, operation: .copy, fraction: 1.0)
        
        // Generate PNG data from the rasterized bitmap
        return bitmapRep.representation(using: .png, properties: [:])
    }
}

#endif
