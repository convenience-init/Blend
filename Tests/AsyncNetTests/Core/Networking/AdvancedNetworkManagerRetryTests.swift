import Foundation
import Testing

@testable import AsyncNet

@Suite("Advanced Network Manager Retry Tests")
public struct AdvancedNetworkManagerRetryTests {
    @Test public func testRetryPolicyBackoff() async throws {
        let cache = DefaultNetworkCache(maxSize: 10, expiration: 60)
        // Script multiple failures to trigger retries: first 2 fail, third succeeds
        let mockSession = MockURLSession(scriptedCalls: [
            MockScript(data: nil, response: nil, error: NetworkError.networkUnavailable),  // First attempt fails
            MockScript(data: nil, response: nil, error: NetworkError.networkUnavailable),  // Retry 1 fails
            MockScript(
                data: Data([0x01, 0x02, 0x03]),
                response: HTTPURLResponse(
                    url: URL(string: "https://mock.api/test")!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                ),
                error: nil
            ),  // Retry 2 succeeds
        ])
        let manager = AdvancedNetworkManager(cache: cache, urlSession: mockSession)
        let request = URLRequest(url: URL(string: "https://mock.api/test")!)
        let retryPolicy = RetryPolicy(
            maxAttempts: 3,  // 1 initial + 2 retries = 3 total attempts
            shouldRetry: { _, _ in true },
            backoff: { attempt in
                // Exponential backoff: 0.1s, 0.2s, 0.4s
                return pow(2.0, Double(attempt)) * 0.1
            })

        let startTime = Date()
        let result = try await manager.fetchData(
            for: request, cacheKey: "test-key", retryPolicy: retryPolicy)
        let elapsed = Date().timeIntervalSince(startTime)

        // Verify the request eventually succeeded with the expected data
        #expect(result == Data([0x01, 0x02, 0x03]))

        // Verify that retries occurred (3 total attempts: 1 initial + 2 retries)
        let recorded = await mockSession.recordedRequests
        #expect(recorded.count == 3, "Expected 3 total attempts (1 initial + 2 retries)")

        // Verify backoff delays were applied (should be around 0.1 + 0.2 = 0.3s total delay)
        #expect(
            elapsed >= 0.3,
            "Expected at least 0.3s elapsed due to backoff delays (0.1s + 0.2s)")
        #expect(elapsed < 1.5, "Expected less than 1.5s elapsed (backoff should be reasonable)")
    }
}
