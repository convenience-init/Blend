import Testing
import Foundation
@testable import AsyncNet
#if canImport(UIKit)
import UIKit
#elseif canImport(Cocoa)
import Cocoa
#endif

@Suite("Image Service Edge Case Tests")
struct ImageServiceEdgeCaseTests {
    @Test func testCacheEvictionMaxLRUCount() async throws {
        let imageData = Data([0xFF, 0xD8, 0xFF])
        let response = HTTPURLResponse(
            url: URL(string: "https://mock.api/test")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "image/jpeg"]
        )!
        let mockSession = MockURLSession(nextData: imageData, nextResponse: response)
        let service = ImageService(cacheCountLimit: 5, cacheTotalCostLimit: 1024 * 1024, urlSession: mockSession)
        // Fill cache
        for i in 0..<5 {
            let url = "https://mock.api/test\(i)"
            _ = try await service.fetchImageData(from: url)
        }
        // Add one more to trigger eviction
        let urlEvict = "https://mock.api/testEvict"
        _ = try await service.fetchImageData(from: urlEvict)
        // Oldest should be evicted
        let oldestUrl = "https://mock.api/test0"
    let isCached = await service.isImageCached(forKey: oldestUrl)
    #expect(isCached == false)
    }

    @Test func testCacheEvictionMaxAge() async throws {
        let imageData = Data([0xFF, 0xD8, 0xFF])
        let response = HTTPURLResponse(
            url: URL(string: "https://mock.api/test")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "image/jpeg"]
        )!
        let mockSession = MockURLSession(nextData: imageData, nextResponse: response)
        let service = ImageService(cacheCountLimit: 5, cacheTotalCostLimit: 1024 * 1024, urlSession: mockSession)
    await service.updateCacheConfiguration(ImageService.CacheConfiguration(maxAge: 0.01, maxLRUCount: 5))
    let url = "https://mock.api/test"
    _ = try await service.fetchImageData(from: url)
    try await Task.sleep(nanoseconds: 20_000_000) // 20ms
    let isCached = await service.isImageCached(forKey: url)
    #expect(isCached == false)
    }

    @Test func testCacheMetricsHitsMisses() async throws {
        let imageData = Data([0xFF, 0xD8, 0xFF])
        let response = HTTPURLResponse(
            url: URL(string: "https://mock.api/test")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "image/jpeg"]
        )!
        let mockSession = MockURLSession(nextData: imageData, nextResponse: response)
        let service = ImageService(urlSession: mockSession)
        let url = "https://mock.api/test"
        _ = try await service.fetchImageData(from: url) // miss
        _ = try await service.fetchImageData(from: url) // hit
    #expect(await service.cacheHits > 0)
    #expect(await service.cacheMisses > 0)
    }

    @Test func testEvictionAfterCacheConfigUpdate() async throws {
        let imageData = Data([0xFF, 0xD8, 0xFF])
        let response = HTTPURLResponse(
            url: URL(string: "https://mock.api/test")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "image/jpeg"]
        )!
        let mockSession = MockURLSession(nextData: imageData, nextResponse: response)
        let service = ImageService(cacheCountLimit: 5, cacheTotalCostLimit: 1024 * 1024, urlSession: mockSession)
        for i in 0..<5 {
            let url = "https://mock.api/test\(i)"
            _ = try await service.fetchImageData(from: url)
        }
        // Access last two items to make them most recently used
        _ = try await service.fetchImageData(from: "https://mock.api/test3")
        _ = try await service.fetchImageData(from: "https://mock.api/test4")
        // Update config to stricter limit
        await service.updateCacheConfiguration(ImageService.CacheConfiguration(maxAge: 3600, maxLRUCount: 2))
        // Explicitly check MRU survivors and evicted items
        #expect(await service.isImageCached(forKey: "https://mock.api/test3") == true)
        #expect(await service.isImageCached(forKey: "https://mock.api/test4") == true)
        #expect(await service.isImageCached(forKey: "https://mock.api/test0") == false)
        #expect(await service.isImageCached(forKey: "https://mock.api/test1") == false)
        #expect(await service.isImageCached(forKey: "https://mock.api/test2") == false)
    }
}
