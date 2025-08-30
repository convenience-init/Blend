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
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1, pixelsHigh: 1, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor.red.setFill()
    NSBezierPath(rect: NSRect(x: 0, y: 0, width: 1, height: 1)).fill()
    NSGraphicsContext.restoreGraphicsState()
    let image = NSImage(size: size)
    image.addRepresentation(rep)
    let jpeg = image.jpegData(compressionQuality: 0.8)
    #expect(jpeg != nil)
    #endif
    }

    @Test func testNSImageExtensionPNGData() {
    #if canImport(AppKit) && !canImport(UIKit)
    let size = NSSize(width: 1, height: 1)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1, pixelsHigh: 1, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor.blue.setFill()
    let rect = NSRect(x: 0, y: 0, width: 1, height: 1)
    NSBezierPath(rect: rect).fill()
    NSGraphicsContext.restoreGraphicsState()
    let image = NSImage(size: size)
    image.addRepresentation(rep)
    let png = image.pngData()
    #expect(png != nil)
    #endif
    }

    @Test func testPlatformImageToData() {
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
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1, pixelsHigh: 1, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor.green.setFill()
    let rect = NSRect(x: 0, y: 0, width: 1, height: 1)
    NSBezierPath(rect: rect).fill()
    NSGraphicsContext.restoreGraphicsState()
    let image = NSImage(size: size)
    image.addRepresentation(rep)
    let data = platformImageToData(image)
    #expect(data != nil)
    #expect(data?.count ?? 0 > 0)
        #endif
    }
}
