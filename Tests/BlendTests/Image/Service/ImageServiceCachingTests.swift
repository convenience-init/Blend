import Foundation
import Testing

@testable import Blend

@Suite("Image Service Caching Tests")
public struct ImageServiceCachingTests {
    @Test public func testImageCaching() async throws {
        // Prepare mock image data and response
        let imageData = Data([0xFF, 0xD8, 0xFF, 0xE0])  // JPEG header
        let response = HTTPURLResponse(
            url: URL(string: "https://mock.api/test")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "image/jpeg", "Mime-Type": "image/jpeg"]
        )!
        let mockSession = MockURLSession(nextData: imageData, nextResponse: response)
        let service = ImageService(
            imageCacheCountLimit: 100,
            imageCacheTotalCostLimit: 50 * 1024 * 1024,
            dataCacheCountLimit: 200,
            dataCacheTotalCostLimit: 100 * 1024 * 1024,
            urlSession: mockSession
        )

        // First fetch should use network
        let result1 = try await service.fetchImageData(from: "https://mock.api/test")
        #expect(result1 == imageData)

        // Second fetch should use cache
        let result2 = try await service.fetchImageData(from: "https://mock.api/test")
        #expect(result2 == imageData)

        // Verify only one network request was made
        #expect(await mockSession.callCount == 1)
    }

    @Test public func testDataCaching() async throws {
        // Prepare mock image data and response
        let imageData = Data([0xFF, 0xD8, 0xFF, 0xE0])  // JPEG header
        let response = HTTPURLResponse(
            url: URL(string: "https://mock.api/test")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "image/jpeg", "Mime-Type": "image/jpeg"]
        )!
        let mockSession = MockURLSession(nextData: imageData, nextResponse: response)
        let service = ImageService(
            imageCacheCountLimit: 100,
            imageCacheTotalCostLimit: 50 * 1024 * 1024,
            dataCacheCountLimit: 200,
            dataCacheTotalCostLimit: 100 * 1024 * 1024,
            urlSession: mockSession
        )

        // First fetch should use network
        let result1 = try await service.fetchImageData(from: "https://mock.api/test")
        #expect(result1 == imageData)

        // Second fetch should use cache
        let result2 = try await service.fetchImageData(from: "https://mock.api/test")
        #expect(result2 == imageData)

        // Verify only one network request was made
        #expect(await mockSession.callCount == 1)
    }
}
