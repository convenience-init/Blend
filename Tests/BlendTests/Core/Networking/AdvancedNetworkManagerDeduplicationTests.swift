import Foundation
import Testing

@testable import Blend

@Suite("Advanced Network Manager Deduplication Tests")
public struct AdvancedNetworkManagerDeduplicationTests {
    // MARK: - Test URLs

    private var testURL: URL {
        guard let url = URL(string: "https://mock.api/test") else {
            fatalError("Invalid test URL")
        }
        return url
    }

    @Test public func testDeduplicationReturnsSameTaskSingleRequest() async throws {
        let cache = DefaultNetworkCache(maxSize: 10, expiration: 60)
        let mockSession = MockURLSession(
            nextData: Data([0x01, 0x02, 0x03]),
            nextResponse: HTTPURLResponse(
                url: testURL,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            ))
        let manager = AdvancedNetworkManager(cache: cache, urlSession: mockSession)
        let request = URLRequest(url: testURL)
        async let first: Data = try manager.fetchData(for: request, cacheKey: "key1")
        async let second: Data = try manager.fetchData(for: request, cacheKey: "key1")
        let result1 = try await first
        let result2 = try await second

        // Verify deduplication: both calls should return the same data
        #expect(result1 == result2)

        // Verify deduplication: only one network request should have been made
        let recordedRequests = await mockSession.recordedRequests
        #expect(
            recordedRequests.count == 1, "Expected exactly one network request due to deduplication"
        )
    }
}
