import Testing
import Foundation
#if canImport(UIKit)
import UIKit
#endif
#if canImport(Cocoa)
import Cocoa
#endif
@testable import AsyncNet

@Suite("Platform Abstraction Tests")
struct PlatformAbstractionTests {
    @Test func testPlatformImageTypealias() {
        #if canImport(UIKit)
        let image = UIImage()
        let platformImage: PlatformImage = image
        #expect(type(of: platformImage) == UIImage.self)
        #elseif canImport(Cocoa)
        let image = NSImage(size: NSSize(width: 1, height: 1))
        let platformImage: PlatformImage = image
        #expect(type(of: platformImage) == NSImage.self)
        #endif
    }

    @Test func testNSImageExtensionJPEGData() {
        #if canImport(Cocoa) && !canImport(UIKit)
        let image = NSImage(size: NSSize(width: 1, height: 1))
        image.lockFocus()
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: 1, height: 1).fill()
        image.unlockFocus()
        let jpeg = image.jpegData(compressionQuality: 0.8)
        #expect(jpeg != nil)
        #endif
    }

    @Test func testNSImageExtensionPNGData() {
        #if canImport(Cocoa) && !canImport(UIKit)
        let image = NSImage(size: NSSize(width: 1, height: 1))
        image.lockFocus()
        NSColor.blue.setFill()
        NSRect(x: 0, y: 0, width: 1, height: 1).fill()
        image.unlockFocus()
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
        #elseif canImport(Cocoa)
        let image = NSImage(size: NSSize(width: 1, height: 1))
        image.lockFocus()
        NSColor.green.setFill()
        NSRect(x: 0, y: 0, width: 1, height: 1).fill()
        image.unlockFocus()
        let data = platformImageToData(image)
        #expect(data != nil)
        #expect(data?.count ?? 0 > 0)
        #endif
    }
}
