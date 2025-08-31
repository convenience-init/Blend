import Testing
import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
@testable import AsyncNet

@Suite("Platform Abstraction Tests")
struct PlatformAbstractionTests {
    @Test func testPlatformImageTypealias() {
        #if canImport(UIKit)
        let image = UIImage()
        let platformImage: PlatformImage = image
        #expect(platformImage is UIImage)
        #elseif canImport(AppKit)
        let image = NSImage(size: NSSize(width: 1, height: 1))
        let platformImage: PlatformImage = image
        #expect(platformImage is NSImage)
        #endif
    }

    @Test func testNSImageExtensionJPEGData() {
    #if canImport(AppKit) && !canImport(UIKit)
    let size = NSSize(width: 1, height: 1)
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1, pixelsHigh: 1, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else {
        Issue.record("Failed to create NSBitmapImageRep")
        return
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSColor.red.setFill()
    NSBezierPath(rect: NSRect(x: 0, y: 0, width: 1, height: 1)).fill()
    let image = NSImage(size: size)
    image.addRepresentation(rep)
    let jpeg = image.jpegData(compressionQuality: 0.8)
    #expect(jpeg != nil)
    #endif
    }

    @Test func testNSImageExtensionPNGData() {
    #if canImport(AppKit) && !canImport(UIKit)
    let size = NSSize(width: 1, height: 1)
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1, pixelsHigh: 1, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else {
        Issue.record("Failed to create NSBitmapImageRep")
        return
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSColor.blue.setFill()
    let rect = NSRect(x: 0, y: 0, width: 1, height: 1)
    NSBezierPath(rect: rect).fill()
    let image = NSImage(size: size)
    image.addRepresentation(rep)
    let png = image.pngData()
    #expect(png != nil)
    #endif
    }

    @Test @MainActor func testPlatformImageToData() {
        #if canImport(UIKit)
        // Render a 1x1 pixel image using UIGraphicsImageRenderer
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1))
        let image = renderer.image { ctx in
            UIColor.green.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        let data = platformImageToData(image)
        #expect(data != nil)
        #expect(data?.count ?? 0 > 0)
    #elseif canImport(AppKit)
    let size = NSSize(width: 1, height: 1)
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1, pixelsHigh: 1, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else {
        Issue.record("Failed to create NSBitmapImageRep")
        return
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSColor.green.setFill()
    let rect = NSRect(x: 0, y: 0, width: 1, height: 1)
    NSBezierPath(rect: rect).fill()
    let image = NSImage(size: size)
    image.addRepresentation(rep)
    let data = platformImageToData(image)
    #expect(data != nil)
    #expect(data?.count ?? 0 > 0)
        #endif
    }

    @Test func testNSImageExtensionEdgeCases() {
    #if canImport(AppKit) && !canImport(UIKit)
    // Test with zero-sized image
    let zeroSizeImage = NSImage(size: NSSize(width: 0, height: 0))
    #expect(zeroSizeImage.pngData() == nil)
    #expect(zeroSizeImage.jpegData(compressionQuality: 0.8) == nil)
    
    // Test with corrupted TIFF data
    let corruptedImage = NSImage(size: NSSize(width: 10, height: 10))
    // Create a representation with invalid data to simulate corruption
    if let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: 10,
        pixelsHigh: 10,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 32
    ) {
        corruptedImage.addRepresentation(rep)
        // The methods should still work via the fallback rasterization path
        let pngData = corruptedImage.pngData()
        let jpegData = corruptedImage.jpegData(compressionQuality: 0.8)
        
        // Both should succeed via rasterization fallback
        #expect(pngData != nil)
        #expect(jpegData != nil)
        #expect(pngData?.count ?? 0 > 0)
        #expect(jpegData?.count ?? 0 > 0)
    }
    #endif
    }
}
