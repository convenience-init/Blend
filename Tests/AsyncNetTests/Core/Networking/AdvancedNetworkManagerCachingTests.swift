import Foundation
import Testing

@testable import AsyncNet

@Suite("AdvancedNetworkManager Caching Tests")
public struct AdvancedNetworkManagerCachingTests {
    @Test public func testConditionalCachingOnlyCachesSuccessfulResponses() async throws {
        let cache = DefaultNetworkCache(maxSize: 10, expiration: 60)

        // Test successful responses are cached
        try await testSuccessfulResponseCaching(cache: cache, statusCode: 200, testName: "200 OK")
        try await testSuccessfulResponseCaching(
            cache: cache, statusCode: 201, testName: "201 Created")
        try await testSuccessfulResponseCaching(
            cache: cache, statusCode: 204, testName: "204 No Content")

        // Test error responses are not cached
        try await testErrorResponseNotCached(cache: cache)

        // Test non-HTTP responses are not cached
        try await testNonHttpResponseNotCached(cache: cache)
    }

    /// Tests that successful HTTP responses are cached
    private func testSuccessfulResponseCaching(
        cache: DefaultNetworkCache, statusCode: Int, testName: String
    ) async throws {
        let testData = Data([UInt8(statusCode % 256), 0x02, 0x03])
        let response = HTTPURLResponse(
            url: testURL(for: statusCode),
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )
        let session = MockURLSession(nextData: testData, nextResponse: response)
        let manager = AdvancedNetworkManager(cache: cache, urlSession: session)

        let request = URLRequest(url: testURL(for: statusCode))
        let result = try await manager.fetchData(for: request, cacheKey: "key-\(statusCode)")
        #expect(result == testData)

        // Verify response was cached
        let cachedData = await cache.get(forKey: "key-\(statusCode)")
        #expect(cachedData == testData, "\(testName) response should be cached (2xx policy)")
    }

    /// Tests that error responses are not cached
    private func testErrorResponseNotCached(cache: DefaultNetworkCache) async throws {
        let errorData = Data("Not Found".utf8)
        let errorResponse = HTTPURLResponse(
            url: errorURL,
            statusCode: 404,
            httpVersion: nil,
            headerFields: ["Content-Type": "text/plain"]
        )

        let session = MockURLSession(nextData: errorData, nextResponse: errorResponse)
        let manager = AdvancedNetworkManager(cache: cache, urlSession: session)

        let request = URLRequest(url: errorURL)
        do {
            _ = try await manager.fetchData(for: request, cacheKey: "error-404-key")
            #expect(Bool(false), "Expected NetworkError.notFound for 404 status code")
        } catch let error as NetworkError {
            if case let .notFound(data, statusCode) = error {
                #expect(statusCode == 404, "Expected 404 status code in error")
                #expect(data == errorData, "Expected error data to match response data")
            } else {
                #expect(Bool(false), "Expected NetworkError.notFound for 404 response")
            }
        } catch {
            #expect(Bool(false), "Expected NetworkError for 404 response, got \(type(of: error))")
        }

        // Verify error response was NOT cached
        let cachedErrorData = await cache.get(forKey: "error-404-key")
        #expect(
            cachedErrorData == nil, "404 Not Found response should not be cached (non-2xx policy)")
    }

    /// Tests that non-HTTP responses are not cached
    private func testNonHttpResponseNotCached(cache: DefaultNetworkCache) async throws {
        let nonHttpData = Data([0x07, 0x08, 0x09])
        let nonHttpResponse = URLResponse(
            url: nonHttpURL, mimeType: nil, expectedContentLength: 0,
            textEncodingName: nil)
        let session = MockURLSession(nextData: nonHttpData, nextResponse: nonHttpResponse)
        let manager = AdvancedNetworkManager(cache: cache, urlSession: session)

        let request = URLRequest(url: nonHttpURL)
        let result = try await manager.fetchData(for: request, cacheKey: "nonhttp-key")
        #expect(result == nonHttpData)

        // Verify non-HTTP response was NOT cached
        let cachedNonHttpData = await cache.get(forKey: "nonhttp-key")
        #expect(
            cachedNonHttpData == nil,
            "Non-HTTP response should not be cached (only HTTP 2xx responses are cached)")
    }

    // MARK: - Test URLs

    private func testURL(for statusCode: Int) -> URL {
        guard let url = URL(string: "https://mock.api/test\(statusCode)") else {
            fatalError("Invalid test URL for status code \(statusCode)")
        }
        return url
    }

    private var errorURL: URL {
        guard let url = URL(string: "https://mock.api/error") else {
            fatalError("Invalid error test URL")
        }
        return url
    }

    private var nonHttpURL: URL {
        guard let url = URL(string: "https://mock.api/nonhttp") else {
            fatalError("Invalid non-HTTP test URL")
        }
        return url
    }
}
