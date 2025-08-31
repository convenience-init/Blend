import Testing
import Foundation
@testable import AsyncNet

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
        // Provide enough scripted responses for all the calls this test makes (6 calls total)
        let mockSession = MockURLSession(
            scriptedData: Array(repeating: imageData, count: 6),
            scriptedResponses: Array(repeating: response, count: 6),
            scriptedErrors: Array(repeating: nil as Error?, count: 6)
        )
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
        #expect(await service.isImageCached(forKey: oldestUrl) == false)
        
        // Newly inserted item should remain cached
        #expect(await service.isImageCached(forKey: urlEvict) == true)
        
        // Mid-range items should remain cached (test1 and test2 were not the oldest)
        #expect(await service.isImageCached(forKey: "https://mock.api/test1") == true)
        #expect(await service.isImageCached(forKey: "https://mock.api/test2") == true)
        
        // Recent items should remain cached (test3 and test4 were the most recent before eviction)
        #expect(await service.isImageCached(forKey: "https://mock.api/test3") == true)
        #expect(await service.isImageCached(forKey: "https://mock.api/test4") == true)
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
        
        // Set a short maxAge for testing cache expiry
        let maxAge: TimeInterval = 0.01 // 10ms
        await service.updateCacheConfiguration(ImageService.CacheConfiguration(maxAge: maxAge, maxLRUCount: 5))
        
        let url = "https://mock.api/test"
        _ = try await service.fetchImageData(from: url)
        
        // Verify image is cached immediately after fetching
        #expect(await service.isImageCached(forKey: url) == true)
        
        // Sleep for maxAge duration plus buffer to ensure expiry
        let sleepDuration = UInt64(maxAge * 1_000_000_000) + 50_000_000 // maxAge + 50ms buffer
        try await Task.sleep(nanoseconds: sleepDuration)
        
        // Verify image is no longer cached after expiry
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
        #expect(await service.cacheMisses == 1)
        #expect(await service.cacheHits == 1)
    }

    @Test func testEvictionAfterCacheConfigUpdate() async throws {
        let imageData = Data([0xFF, 0xD8, 0xFF])
        let response = HTTPURLResponse(
            url: URL(string: "https://mock.api/test")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "image/jpeg"]
        )!
        // Provide enough scripted responses for all the calls this test makes (7 calls total)
        let mockSession = MockURLSession(
            scriptedData: Array(repeating: imageData, count: 7),
            scriptedResponses: Array(repeating: response, count: 7),
            scriptedErrors: Array(repeating: nil as Error?, count: 7)
        )
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
        
        // Allow time for cache eviction to complete
        try await Task.sleep(nanoseconds: 10_000_000) // 10ms delay
        
        // Explicitly check MRU survivors and evicted items
        #expect(await service.isImageCached(forKey: "https://mock.api/test3") == true)
        #expect(await service.isImageCached(forKey: "https://mock.api/test4") == true)
        #expect(await service.isImageCached(forKey: "https://mock.api/test0") == false)
        #expect(await service.isImageCached(forKey: "https://mock.api/test1") == false)
        #expect(await service.isImageCached(forKey: "https://mock.api/test2") == false)
    }
}
