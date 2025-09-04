import Foundation
import Testing

@testable import AsyncNet

@Suite("Image Service Edge Case Tests")
struct ImageServiceEdgeCaseTests {
    @Test func testCacheEvictionMaxLRUCount() async throws {
        let imageData = Data([0xFF, 0xD8, 0xFF, 0xE0])
        // Generate URLs for the test requests
        let requestUrls =
            (0..<5).map { "https://mock.api/test\($0)" } + ["https://mock.api/testEvict"]
        // Create responses with URLs matching each request
        let scriptedResponses = requestUrls.map { urlString in
            HTTPURLResponse(
                url: URL(string: urlString)!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "image/jpeg"]
            )!
        }
        // Provide enough scripted responses for all the calls this test makes (6 calls total)
        let mockSession = MockURLSession(
            scriptedData: Array(repeating: imageData, count: 6),
            scriptedResponses: scriptedResponses,
            scriptedErrors: Array(repeating: nil as Error?, count: 6)
        )
        let service = ImageService(
            imageCacheCountLimit: 5,
            imageCacheTotalCostLimit: 1024 * 1024,
            dataCacheCountLimit: 5,
            dataCacheTotalCostLimit: 1024 * 1024,
            urlSession: mockSession)
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
        let imageData = Data([0xFF, 0xD8, 0xFF, 0xE0])
        let response = HTTPURLResponse(
            url: URL(string: "https://mock.api/test")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "image/jpeg"]
        )!
        let mockSession = MockURLSession(nextData: imageData, nextResponse: response)
        let service = ImageService(
            imageCacheCountLimit: 5,
            imageCacheTotalCostLimit: 1024 * 1024,
            dataCacheCountLimit: 5,
            dataCacheTotalCostLimit: 1024 * 1024,
            urlSession: mockSession)

        // Set a conservative maxAge for testing cache expiry (avoids flakiness on slower CI/hosts)
        let maxAgeSeconds: TimeInterval = 0.1  // 100ms - conservative value for reliable testing
        let bufferSeconds: TimeInterval = 0.3  // 300ms buffer for reliable expiry on slower systems

        await service.updateCacheConfiguration(
            ImageService.CacheConfiguration(maxAge: maxAgeSeconds, maxLRUCount: 5))

        let url = "https://mock.api/test"
        _ = try await service.fetchImageData(from: url)

        // Verify image is cached immediately after fetching
        #expect(await service.isImageCached(forKey: url) == true)

        // Sleep for maxAge duration plus generous buffer to ensure expiry on slower systems
        let maxAgeNanoseconds = UInt64(maxAgeSeconds * 1_000_000_000)
        let bufferNanoseconds = UInt64(bufferSeconds * 1_000_000_000)
        let sleepDuration = maxAgeNanoseconds + bufferNanoseconds
        try await Task.sleep(nanoseconds: sleepDuration)

        // Verify image is no longer cached after expiry
        let isCached = await service.isImageCached(forKey: url)
        #expect(isCached == false, "Image should be evicted after maxAge expiry")
    }

    @Test func testCacheMetricsHitsMisses() async throws {
        let imageData = Data([0xFF, 0xD8, 0xFF, 0xE0])
        let response = HTTPURLResponse(
            url: URL(string: "https://mock.api/test")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "image/jpeg"]
        )!
        let mockSession = MockURLSession(nextData: imageData, nextResponse: response)
        let service = ImageService(
            imageCacheCountLimit: 100,
            imageCacheTotalCostLimit: 50 * 1024 * 1024,
            dataCacheCountLimit: 100,
            dataCacheTotalCostLimit: 50 * 1024 * 1024,
            urlSession: mockSession)
        let url = "https://mock.api/test"
        _ = try await service.fetchImageData(from: url)  // miss
        _ = try await service.fetchImageData(from: url)  // hit
        #expect(await service.cacheMisses == 1)
        #expect(await service.cacheHits == 1)
    }

    @Test func testEvictionAfterCacheConfigUpdate() async throws {
        let imageData = Data([0xFF, 0xD8, 0xFF, 0xE0])
        // Generate URLs for the test requests
        let requestUrls = (0..<6).map { "https://mock.api/test\($0)" }
        // Create responses with URLs matching each request
        let scriptedResponses = requestUrls.map { urlString in
            HTTPURLResponse(
                url: URL(string: urlString)!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "image/jpeg"]
            )!
        }
        // Provide enough scripted responses for all the calls this test makes (6 calls total: 6 inserts)
        let mockSession = MockURLSession(
            scriptedData: Array(repeating: imageData, count: 6),
            scriptedResponses: scriptedResponses,
            scriptedErrors: Array(repeating: nil as Error?, count: 6)
        )
        // Start with a higher limit, then reduce it to trigger eviction after a config update.
        let service = ImageService(
            imageCacheCountLimit: 6,
            imageCacheTotalCostLimit: 1024 * 1024,
            dataCacheCountLimit: 6,
            dataCacheTotalCostLimit: 1024 * 1024,
            urlSession: mockSession)
        // Fill cache to capacity
        for i in 0..<6 {
            let url = "https://mock.api/test\(i)"
            _ = try await service.fetchImageData(from: url)
        }
        // Reduce limit to trigger eviction due to config update
        await service.updateCacheConfiguration(
            ImageService.CacheConfiguration(maxAge: 60, maxLRUCount: 5))
        // Oldest should be evicted (test0) after config change
        let oldestUrl = "https://mock.api/test0"
        #expect(
            await service.isImageCached(forKey: oldestUrl) == false,
            "Oldest item (test0) should be evicted when limit is reduced to 5")

        // Most recent item should remain cached
        #expect(
            await service.isImageCached(forKey: "https://mock.api/test5") == true,
            "Most recent item (test5) should remain cached")

        // Mid-range items should remain cached (test1 and test2 were not the oldest)
        #expect(
            await service.isImageCached(forKey: "https://mock.api/test1") == true,
            "Mid-range item (test1) should remain cached")
        #expect(
            await service.isImageCached(forKey: "https://mock.api/test2") == true,
            "Mid-range item (test2) should remain cached")

        // Recent items should remain cached (test3 and test4 were the most recent before eviction)
        #expect(
            await service.isImageCached(forKey: "https://mock.api/test3") == true,
            "Recent item (test3) should remain cached")
        #expect(
            await service.isImageCached(forKey: "https://mock.api/test4") == true,
            "Recent item (test4) should remain cached")
    }
}
