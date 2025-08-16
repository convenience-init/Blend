#if canImport(Cocoa) && !canImport(UIKit)
import Cocoa

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
        guard let tiffData = tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        
        return bitmapRep.representation(
            using: .jpeg,
            properties: [.compressionFactor: compressionQuality]
        )
    }
    
    /// Creates PNG data representation
    /// - Returns: PNG data or nil if conversion fails
    func pngData() -> Data? {
        guard let tiffData = tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        
        return bitmapRep.representation(using: .png, properties: [:])
    }
}

#endif
