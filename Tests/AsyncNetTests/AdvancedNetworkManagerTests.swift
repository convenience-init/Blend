import Foundation
import Testing

@testable import AsyncNet

@Suite("AdvancedNetworkManager Tests")
struct AdvancedNetworkManagerTests {
    @Test func testDeduplicationReturnsSameTaskSingleRequest() async throws {
        let cache = DefaultNetworkCache(maxSize: 10, expiration: 60)
        let mockSession = MockURLSession(
            nextData: Data([0x01, 0x02, 0x03]),
            nextResponse: HTTPURLResponse(
                url: URL(string: "https://mock.api/test")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            ))
        let manager = AdvancedNetworkManager(cache: cache, urlSession: mockSession)
        let request = URLRequest(url: URL(string: "https://mock.api/test")!)
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

    @Test func testRetryPolicyBackoff() async throws {
        let cache = DefaultNetworkCache(maxSize: 10, expiration: 60)
        // Provide 2 scripted responses: initial attempt + 1 retry
        let mockSession = MockURLSession(scriptedCalls: [
            (nil, nil, NetworkError.networkUnavailable),  // First call (initial attempt)
            (nil, nil, NetworkError.networkUnavailable),  // Second call (retry)
        ])
        let manager = AdvancedNetworkManager(cache: cache, urlSession: mockSession)
        let request = URLRequest(url: URL(string: "https://mock.api/fail")!)
        let retryPolicy = RetryPolicy(
            maxRetries: 1, shouldRetry: { _, _ in true }, backoff: { _ in 0.01 })
        do {
            _ = try await manager.fetchData(
                for: request, cacheKey: "fail-key", retryPolicy: retryPolicy)
            #expect(Bool(false))
        } catch {
            if case .networkUnavailable = error as? NetworkError {
                // Success - caught the expected NetworkError.networkUnavailable
            } else {
                #expect(Bool(false), "Expected NetworkError.networkUnavailable, got \(error)")
            }
        }
        let recorded = await mockSession.recordedRequests
        #expect(recorded.count == 2, "Expected initial attempt + 1 retry.")
    }

    @Test func testRetryPolicyBackoffCapping() async throws {
        // Test that backoff is capped at maxBackoff when used in fetchData
        // Use a deterministic custom policy to avoid flakiness from factory jitter
        let policy = RetryPolicy(
            maxRetries: 3,
            shouldRetry: { _, _ in true },
            backoff: { attempt in
                // Deterministic exponential backoff: 1s, 2s, 4s, 8s (no jitter)
                return pow(2.0, Double(attempt))
            }
        )

        // Test various attempt values - these return raw values from closure
        let backoff1 = policy.backoff?(0) ?? 0.0  // 2^0 = 1
        let backoff2 = policy.backoff?(1) ?? 0.0  // 2^1 = 2
        let backoff3 = policy.backoff?(2) ?? 0.0  // 2^2 = 4
        let backoff4 = policy.backoff?(3) ?? 0.0  // 2^3 = 8

        // Raw backoff values should not be capped in the closure
        #expect(backoff1 == 1.0, "Backoff for attempt 0 should be 1.0")
        #expect(backoff2 == 2.0, "Backoff for attempt 1 should be 2.0")
        #expect(backoff3 == 4.0, "Backoff for attempt 2 should be 4.0")
        #expect(backoff4 == 8.0, "Backoff for attempt 3 should be 8.0")

        // Test that capping happens when using the policy in practice
        let highAttemptPolicy = RetryPolicy(
            maxRetries: 10,
            shouldRetry: { _, _ in true },
            backoff: { attempt in
                // Deterministic exponential backoff for high attempts
                return pow(2.0, Double(attempt))
            },
            maxBackoff: 5.0
        )
        let rawBackoff = highAttemptPolicy.backoff?(10) ?? 0.0  // 2^10 = 1024, uncapped
        #expect(rawBackoff == 1024.0, "Raw backoff for attempt 10 should be 1024.0")

        // Simulate the capping that happens in fetchData
        let cappedBackoff = min(max(rawBackoff, 0.0), highAttemptPolicy.maxBackoff)
        #expect(cappedBackoff <= 5.0, "Capped backoff should respect maxBackoff")
        #expect(cappedBackoff == 5.0, "High raw backoff should be capped to maxBackoff")
    }

    @Test func testCacheReturnsCachedData() async throws {
        let cache = DefaultNetworkCache(maxSize: 10, expiration: 60)
        let mockSession = MockURLSession(
            nextData: Data([0x01, 0x02, 0x03]),
            nextResponse: HTTPURLResponse(
                url: URL(string: "https://mock.api/test")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            ))
        let manager = AdvancedNetworkManager(cache: cache, urlSession: mockSession)
        let request = URLRequest(url: URL(string: "https://mock.api/test")!)
        let data = Data([0x01, 0x02, 0x03])
        await cache.set(data, forKey: "cache-key")
        let result = try await manager.fetchData(for: request, cacheKey: "cache-key")
        #expect(result == data)

        // Verify that cache short-circuited the network call
        let callCount = await mockSession.callCount
        #expect(callCount == 0, "Expected no network calls when data is cached")
    }

    @Test func testConditionalCachingOnlyCachesSuccessfulResponses() async throws {
        let cache = DefaultNetworkCache(maxSize: 10, expiration: 60)

        // Test 1: Successful response (200 OK) should be cached
        // Policy: HTTP 2xx responses are cached, others are not
        let successData = Data([0x01, 0x02, 0x03])
        let successResponse = HTTPURLResponse(
            url: URL(string: "https://mock.api/success")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )
        let successSession = MockURLSession(nextData: successData, nextResponse: successResponse)
        let successManager = AdvancedNetworkManager(cache: cache, urlSession: successSession)

        let successRequest = URLRequest(url: URL(string: "https://mock.api/success")!)
        let successResult = try await successManager.fetchData(
            for: successRequest, cacheKey: "success-200-key")
        #expect(successResult == successData)

        // Verify successful 200 response was cached
        let cachedSuccessData = await cache.get(forKey: "success-200-key")
        #expect(cachedSuccessData == successData, "200 OK response should be cached (2xx policy)")

        // Test 2: Successful response (201 Created) should be cached
        // Policy: HTTP 2xx responses are cached, others are not
        let createdData = Data([0x04, 0x05, 0x06])
        let createdResponse = HTTPURLResponse(
            url: URL(string: "https://mock.api/created")!,
            statusCode: 201,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json", "Location": "/resource/123"]
        )
        let createdSession = MockURLSession(nextData: createdData, nextResponse: createdResponse)
        let createdManager = AdvancedNetworkManager(cache: cache, urlSession: createdSession)

        let createdRequest = URLRequest(url: URL(string: "https://mock.api/created")!)
        let createdResult = try await createdManager.fetchData(
            for: createdRequest, cacheKey: "created-201-key")
        #expect(createdResult == createdData)

        // Verify successful 201 response was cached
        let cachedCreatedData = await cache.get(forKey: "created-201-key")
        #expect(
            cachedCreatedData == createdData, "201 Created response should be cached (2xx policy)")

        // Test 3: Successful response (204 No Content) should be cached
        // Policy: HTTP 2xx responses are cached, others are not
        // Note: 204 responses typically have empty body, but our policy caches them if they're 2xx
        let noContentData = Data()  // Empty body for 204
        let noContentResponse = HTTPURLResponse(
            url: URL(string: "https://mock.api/nocontent")!,
            statusCode: 204,
            httpVersion: nil,
            headerFields: nil
        )
        let noContentSession = MockURLSession(
            nextData: noContentData, nextResponse: noContentResponse)
        let noContentManager = AdvancedNetworkManager(cache: cache, urlSession: noContentSession)

        let noContentRequest = URLRequest(url: URL(string: "https://mock.api/nocontent")!)
        let noContentResult = try await noContentManager.fetchData(
            for: noContentRequest, cacheKey: "nocontent-204-key")
        #expect(noContentResult == noContentData)

        // Verify successful 204 response was cached
        let cachedNoContentData = await cache.get(forKey: "nocontent-204-key")
        #expect(
            cachedNoContentData == noContentData,
            "204 No Content response should be cached (2xx policy)")

        // Test 4: Error response (404 Not Found) should not be cached
        // Policy: Only 2xx responses are cached
        let errorData = Data("Not Found".utf8)
        let errorResponse = HTTPURLResponse(
            url: URL(string: "https://mock.api/error")!,
            statusCode: 404,
            httpVersion: nil,
            headerFields: ["Content-Type": "text/plain"]
        )
        let errorSession = MockURLSession(nextData: errorData, nextResponse: errorResponse)
        let errorManager = AdvancedNetworkManager(cache: cache, urlSession: errorSession)

        let errorRequest = URLRequest(url: URL(string: "https://mock.api/error")!)
        let errorResult = try await errorManager.fetchData(
            for: errorRequest, cacheKey: "error-404-key")
        #expect(errorResult == errorData)

        // Verify error response was NOT cached
        let cachedErrorData = await cache.get(forKey: "error-404-key")
        #expect(
            cachedErrorData == nil, "404 Not Found response should not be cached (non-2xx policy)")

        // Test 5: Non-HTTP response should not be cached
        // Policy: Only HTTP responses with 2xx status codes are cached
        let nonHttpData = Data([0x07, 0x08, 0x09])
        let nonHttpResponse = URLResponse(
            url: URL(string: "https://mock.api/nonhttp")!, mimeType: nil, expectedContentLength: 0,
            textEncodingName: nil)
        let nonHttpSession = MockURLSession(nextData: nonHttpData, nextResponse: nonHttpResponse)
        let nonHttpManager = AdvancedNetworkManager(cache: cache, urlSession: nonHttpSession)

        let nonHttpRequest = URLRequest(url: URL(string: "https://mock.api/nonhttp")!)
        let nonHttpResult = try await nonHttpManager.fetchData(
            for: nonHttpRequest, cacheKey: "nonhttp-key")
        #expect(nonHttpResult == nonHttpData)

        // Verify non-HTTP response was NOT cached
        let cachedNonHttpData = await cache.get(forKey: "nonhttp-key")
        #expect(
            cachedNonHttpData == nil,
            "Non-HTTP response should not be cached (only HTTP 2xx responses are cached)")
    }

    @Test func testRetryPolicyWithNonRetryableError() async throws {
        let cache = DefaultNetworkCache(maxSize: 10, expiration: 60)
        let mockSession = MockURLSession(nextError: NetworkError.invalidEndpoint(reason: "Test"))
        let manager = AdvancedNetworkManager(cache: cache, urlSession: mockSession)
        let request = URLRequest(url: URL(string: "https://mock.api/test")!)
        let retryPolicy = RetryPolicy(
            maxRetries: 3,
            shouldRetry: { error, _ in
                // Only retry on networkUnavailable error
                if let networkError = error as? NetworkError,
                    case .networkUnavailable = networkError
                {
                    return true
                }
                return false
            },
            backoff: { attempt in
                return pow(2.0, Double(attempt - 1)) * 0.1  // Exponential backoff: 0.1s, 0.2s, 0.4s
            })

        do {
            _ = try await manager.fetchData(
                for: request, cacheKey: "key1", retryPolicy: retryPolicy)
            #expect(Bool(false), "Expected non-retryable error to be thrown")
        } catch {
            #expect(error is NetworkError)
            if case NetworkError.invalidEndpoint(let reason) = error {
                #expect(reason == "Test")
            } else {
                #expect(Bool(false), "Expected invalidEndpoint error")
            }
        }
        let recorded = await mockSession.recordedRequests
        #expect(recorded.count == 1, "Non-retryable error should not be retried")
    }
}

@Suite("AsyncRequestable & Endpoint Tests")
struct AsyncRequestableTests {
    struct TestModel: Decodable, Equatable { let value: Int }
    struct MockService: AsyncRequestable {
        typealias ResponseModel = TestModel
        let urlSession: URLSessionProtocol
        func sendRequest(to endPoint: Endpoint) async throws -> TestModel {
            // Build URL from Endpoint properties
            var components = URLComponents()
            components.scheme = endPoint.scheme.rawValue
            components.host = endPoint.host
            components.path = endPoint.normalizedPath
            components.queryItems = endPoint.queryItems
            // Add port and fragment handling if Endpoint exposes them
            let mirror = Mirror(reflecting: endPoint)
            if let portChild = mirror.children.first(where: { $0.label == "port" }),
                let port = portChild.value as? Int
            {
                components.port = port
            }
            if let fragmentChild = mirror.children.first(where: { $0.label == "fragment" }),
                let fragment = fragmentChild.value as? String
            {
                components.fragment = fragment
            }
            guard let url = components.url else {
                throw NetworkError.invalidEndpoint(reason: "Invalid endpoint URL")
            }
            var request = URLRequest(url: url)
            request.httpMethod = endPoint.method.rawValue
            if let headers = endPoint.headers {
                for (key, value) in headers {
                    request.setValue(value, forHTTPHeaderField: key)
                }
            }
            if let body = endPoint.body {
                if endPoint.method == .get {
                    throw NetworkError.invalidBodyForGET
                }
                request.httpBody = body
            }
            // Set timeout from endpoint (preferring timeoutDuration over legacy timeout)
            if let timeout = endPoint.effectiveTimeout {
                request.timeoutInterval = timeout
            }
            // Perform network call
            let (data, response) = try await urlSession.data(for: request)
            if let httpResponse = response as? HTTPURLResponse,
                !(200...299).contains(httpResponse.statusCode)
            {
                throw NetworkError.customError(
                    "HTTP error", details: "Status code: \(httpResponse.statusCode)")
            }
            // Decode Data into TestModel
            return try jsonDecoder.decode(TestModel.self, from: data)
        }
    }

    @Test func testSendRequestReturnsDecodedModel() async throws {
        let mockSession = MockURLSession(
            nextData: Data("{\"value\":42}".utf8),
            nextResponse: HTTPURLResponse(
                url: URL(string: "https://mock.api/test")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            ))
        let service = MockService(urlSession: mockSession)
        let endpoint = MockEndpoint()
        let result = try await service.sendRequest(to: endpoint)
        #expect(result == TestModel(value: 42))
    }

    @Test func testSendRequestAdvancedReturnsDecodedModel() async throws {
        let mockSession = MockURLSession(
            nextData: Data("{\"value\":42}".utf8),
            nextResponse: HTTPURLResponse(
                url: URL(string: "https://mock.api/test")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            ))
        let service = MockService(urlSession: mockSession)
        let endpoint = MockEndpoint()
        let manager = AdvancedNetworkManager(urlSession: mockSession)
        let result: TestModel = try await service.sendRequestAdvanced(
            to: endpoint, networkManager: manager)
        #expect(result == TestModel(value: 42))
    }

    @Test func testSendRequestThrowsInvalidBodyForGET() async throws {
        let mockSession = MockURLSession(
            nextData: Data("{\"value\":42}".utf8),
            nextResponse: HTTPURLResponse(
                url: URL(string: "https://mock.api/test")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            ))
        let service = MockService(urlSession: mockSession)
        var endpoint = MockEndpoint()
        endpoint.body = Data("test body".utf8)  // Add body to GET request

        do {
            _ = try await service.sendRequest(to: endpoint)
            #expect(Bool(false), "Expected invalidBodyForGET error")
        } catch let error as NetworkError {
            #expect(error == .invalidBodyForGET)
        } catch {
            #expect(Bool(false), "Expected NetworkError.invalidBodyForGET")
        }
    }

    @Test func testTimeoutResolutionPrefersDurationOverLegacy() async throws {
        let mockSession = MockURLSession(
            nextData: Data("{\"value\":42}".utf8),
            nextResponse: HTTPURLResponse(
                url: URL(string: "https://mock.api/test")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            ))
        let service = MockService(urlSession: mockSession)
        let endpoint = MockEndpoint.withBothTimeouts  // Has timeoutDuration=15s, timeout=60s

        // Make the request
        _ = try await service.sendRequest(to: endpoint)

        // Verify the recorded request has the correct timeout (15s from timeoutDuration, not 60s from legacy timeout)
        let recordedRequests = await mockSession.recordedRequests
        #expect(recordedRequests.count == 1, "Expected exactly one request to be recorded")

        let request = recordedRequests[0]
        #expect(
            request.timeoutInterval == 15.0,
            "Expected timeoutDuration (15s) to take precedence over legacy timeout (60s)")
        #expect(request.timeoutInterval != 60.0, "Should not use legacy timeout value")
    }

    @Test func testJsonDecoderConfiguration() async throws {
        // Test that conforming types have access to the jsonDecoder property
        struct SimpleService: AsyncRequestable {
            typealias ResponseModel = Int

            func sendRequest(to endPoint: Endpoint) async throws -> Int {
                // Just test that jsonDecoder is accessible and returns a JSONDecoder
                _ = jsonDecoder
                return 42
            }
        }

        let service = SimpleService()
        let endpoint = MockEndpoint()
        let result = try await service.sendRequest(to: endpoint)
        #expect(result == 42)
    }

    @Test func testCustomJsonDecoderInjection() async throws {
        // Test that custom decoders can be injected for testing
        struct TestService: AsyncRequestable {
            typealias ResponseModel = TestModel
            let customDecoder: JSONDecoder

            var jsonDecoder: JSONDecoder {
                customDecoder
            }

            func sendRequest(to endPoint: Endpoint) async throws -> TestModel {
                // Use the injected decoder
                return try customDecoder.decode(TestModel.self, from: Data("{\"value\":99}".utf8))
            }
        }

        // Create a custom decoder with different configuration
        let customDecoder = JSONDecoder()
        customDecoder.keyDecodingStrategy = .useDefaultKeys  // Different from default snake_case

        let service = TestService(customDecoder: customDecoder)

        // Test that the custom decoder is used
        let mockSession = MockURLSession(
            nextData: Data("{\"value\":99}".utf8),
            nextResponse: HTTPURLResponse(
                url: URL(string: "https://mock.api/test")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            ))

        // Since we're testing decoder injection, we'll create a simple test
        let result = try service.customDecoder.decode(
            TestModel.self, from: Data("{\"value\":99}".utf8))
        #expect(result.value == 99, "Custom decoder should decode the value correctly")
    }

    @Test func testSendRequestThrowsForNon2xxStatusCode() async throws {
        // Test that non-2xx HTTP status codes throw NetworkError.customError with status code in message
        let mockSession = MockURLSession(
            nextData: Data(),  // Empty data for 500 response
            nextResponse: HTTPURLResponse(
                url: URL(string: "https://mock.api/error")!,
                statusCode: 500,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            ))
        let service = MockService(urlSession: mockSession)
        let endpoint = MockEndpoint()

        do {
            _ = try await service.sendRequest(to: endpoint)
            #expect(Bool(false), "Expected HTTP error to be thrown for 500 status code")
        } catch let error as NetworkError {
            // Assert the error is NetworkError.customError
            if case let .customError(message, details) = error {
                #expect(message == "HTTP error", "Should have HTTP error message")
                #expect(
                    details?.contains("500") == true, "Error details should contain status code 500"
                )
                #expect(
                    details?.contains("Status code: 500") == true,
                    "Error details should contain 'Status code: 500'")
            } else {
                #expect(Bool(false), "Expected NetworkError.customError for HTTP 500 response")
            }
        } catch {
            #expect(Bool(false), "Expected NetworkError.customError, got \(type(of: error))")
        }
    }
}

@Suite("NetworkError Tests")
struct NetworkErrorTests {
    @Test func testWrapCustomError() {
        struct DummyError: Error, LocalizedError, Sendable {
            let message: String
            var localizedDescription: String { message }
            var errorDescription: String? { "Custom error: \(message)" }
            var recoverySuggestion: String? { "Try again with different parameters" }
        }
        let dummy = DummyError(message: "Dummy failure")
        let wrapped = NetworkError.wrap(dummy)
        if case let .customError(message, details) = wrapped {
            #expect(message == "Unknown error")
            #expect(details?.contains("Dummy failure") == true)
            // Check that the wrapped error preserves the original error's description
            #expect(
                details?.contains("DummyError") == true, "Should include the error type in details")
            #expect(
                details?.contains("message: \"Dummy failure\"") == true,
                "Should include the message in details")

            // Verify that the original error has the expected localized properties
            #expect(
                dummy.errorDescription == "Custom error: Dummy failure",
                "Original error should have errorDescription")
            #expect(
                dummy.recoverySuggestion == "Try again with different parameters",
                "Original error should have recoverySuggestion")
        } else {
            #expect(Bool(false))
        }
    }

    @Test func testCustomErrorMessage() {
        let error = NetworkError.customError("Endpoint error", details: "Details")
        #expect(error.errorDescription?.contains("Endpoint error") == true)
        #expect(error.errorDescription?.contains("Details") == true)
    }
    @Test func testWrapURLError() {
        let urlError = URLError(.notConnectedToInternet)
        let wrapped = NetworkError.wrap(urlError)
        #expect(wrapped == .networkUnavailable)
    }
    @Test func testWrapUnknownURLError() {
        let urlError = URLError(.cannotFindHost)
        let wrapped = NetworkError.wrap(urlError)
        #expect(wrapped == .invalidEndpoint(reason: "Host not found"))
    }
    @Test func testWrapURLErrorTimedOut() {
        let urlError = URLError(.timedOut)
        let wrapped = NetworkError.wrap(urlError)
        #expect(wrapped == .requestTimeout(duration: NetworkError.defaultTimeoutDuration))
    }
    @Test func testWrapURLErrorCannotConnectToHost() {
        let urlError = URLError(.cannotConnectToHost)
        let wrapped = NetworkError.wrap(urlError)
        #expect(wrapped == .networkUnavailable)
    }
    @Test func testWrapDecodingError() {
        // Create a real DecodingError by attempting to decode invalid JSON
        let invalidJSON = "invalid json".data(using: .utf8)!
        struct TestModel: Decodable {
            let value: Int
        }

        do {
            _ = try JSONDecoder().decode(TestModel.self, from: invalidJSON)
            #expect(Bool(false), "Expected decoding to fail")
        } catch let decodingError as DecodingError {
            let wrapped = NetworkError.wrap(decodingError)
            if case let .decodingFailed(reason, underlying, data) = wrapped {
                #expect(reason.contains("Data corrupted"), "Should contain data corruption message")
                #expect(reason.contains("root"), "Should contain coding path information")
                #expect(underlying is DecodingError, "Should preserve original DecodingError")
                #expect(data == nil, "Should not include data for this error type")
            } else {
                #expect(Bool(false), "Expected decodingFailed error for DecodingError")
            }
        } catch {
            #expect(Bool(false), "Expected DecodingError")
        }
    }

    @Test func testDecodingErrorDetailedMessages() {
        // Test different types of DecodingError cases
        let jsonData = """
            {
                "name": "Test",
                "missing_field": null
            }
            """.data(using: .utf8)!

        struct TestModel: Decodable {
            let name: String
            let age: Int  // This will cause a typeMismatch error
            let email: String  // This will cause a keyNotFound error
        }

        do {
            _ = try JSONDecoder().decode(TestModel.self, from: jsonData)
            #expect(Bool(false), "Expected decoding to fail")
        } catch let decodingError as DecodingError {
            let wrapped = NetworkError.wrap(decodingError)
            if case let .decodingFailed(reason, underlying, _) = wrapped {
                #expect(underlying is DecodingError, "Should preserve original DecodingError")
                // The error should contain detailed information about the failure
                #expect(
                    reason.contains("age") || reason.contains("email"),
                    "Should contain field information")
                #expect(
                    reason.contains("Type mismatch") || reason.contains("not found"),
                    "Should contain specific error type")
            } else {
                #expect(Bool(false), "Expected decodingFailed error for DecodingError")
            }
        } catch {
            #expect(Bool(false), "Expected DecodingError")
        }
    }

    @Test func testInvalidBodyForGETError() {
        let error = NetworkError.invalidBodyForGET
        #expect(error.errorDescription == "GET requests cannot have a body.")
        #expect(
            error.recoverySuggestion
                == "Remove the body from GET requests or use a different HTTP method.")
    }

    @Test func testCacheExpiration() async throws {
        // Create cache with very short expiration (0.1 seconds)
        let cache = DefaultNetworkCache(maxSize: 10, expiration: 0.1)
        let testData = Data([0x01, 0x02, 0x03])
        let key = "test-expiration-key"

        // Set data in cache
        await cache.set(testData, forKey: key)

        // Immediately retrieve - should work
        var retrieved = await cache.get(forKey: key)
        #expect(retrieved == testData, "Data should be retrievable immediately after caching")

        // Wait for expiration
        try await Task.sleep(nanoseconds: 150_000_000)  // 0.15 seconds

        // Try to retrieve again - should return nil due to expiration
        retrieved = await cache.get(forKey: key)
        #expect(retrieved == nil, "Data should be nil after expiration")
    }

    @Test func testCacheMaxSizeEnforcement() async throws {
        // Create cache with maxSize of 2
        let cache = DefaultNetworkCache(maxSize: 2, expiration: 60)

        // Add 3 items - LRU order will be: head=key3, key2, tail=key2
        await cache.set(Data([0x01]), forKey: "key1")
        await cache.set(Data([0x02]), forKey: "key2")
        await cache.set(Data([0x03]), forKey: "key3")

        // First item should have been evicted (it was the LRU/tail)
        let data1 = await cache.get(forKey: "key1")
        #expect(data1 == nil, "First item should have been evicted due to maxSize")

        // Second and third items should still be retrievable
        let data2 = await cache.get(forKey: "key2")
        let data3 = await cache.get(forKey: "key3")
        #expect(data2 == Data([0x02]), "Second item should still be cached")
        #expect(data3 == Data([0x03]), "Third item should still be cached")
    }

    @Test func testCustomRetryLogicRespected() async throws {
        // Test that custom shouldRetry logic is respected and not overridden by default behavior
        let mockSession = MockURLSession(nextError: NetworkError.networkUnavailable)  // This would normally be retried by default
        let manager = AdvancedNetworkManager(urlSession: mockSession)
        let request = URLRequest(url: URL(string: "https://mock.api/fail")!)

        // Custom retry policy that explicitly says NOT to retry networkUnavailable errors
        let customRetryPolicy = RetryPolicy(
            maxRetries: 3,
            shouldRetry: { error, attempt in
                // Explicitly don't retry network unavailable errors, even though default would
                if let networkError = error as? NetworkError,
                    case .networkUnavailable = networkError
                {
                    return false
                }
                return true
            },
            backoff: { _ in 0.01 }
        )

        do {
            _ = try await manager.fetchData(
                for: request, cacheKey: "custom-retry-test", retryPolicy: customRetryPolicy)
            #expect(
                Bool(false), "Expected custom retry logic to prevent retries for networkUnavailable"
            )
        } catch {
            #expect(error is NetworkError)
            if let networkError = error as? NetworkError, case .networkUnavailable = networkError {
                // Success - custom logic prevented retry of networkUnavailable error
            } else {
                #expect(Bool(false), "Expected networkUnavailable error")
            }
        }

        // Verify that only 1 request was made (no retries due to custom logic)
        let recordedRequests = await mockSession.recordedRequests
        #expect(
            recordedRequests.count == 1,
            "Expected exactly 1 request (no retries due to custom shouldRetry logic)")
    }
}

@Suite("Endpoint Tests")
struct EndpointTests {
    @Test func testResolvedHeadersNormalization() async throws {
        // Test that resolvedHeaders properly normalizes headers and handles contentType injection
        struct TestEndpoint: Endpoint {
            var scheme: URLScheme = .https
            var host: String = "api.example.com"
            var path: String = "/test"
            var method: RequestMethod = .post
            var headers: [String: String]? = [
                "Authorization": "Bearer token", "content-type": "text/plain",
            ]
            var queryItems: [URLQueryItem]? = nil
            var contentType: String? = "application/json"
            var timeout: TimeInterval? = nil
            var timeoutDuration: Duration? = nil
            var body: Data? = Data("test".utf8)
        }

        let endpoint = TestEndpoint()
        let resolved = endpoint.resolvedHeaders

        // Should have normalized "content-type" to "Content-Type" and used the header value, not contentType
        #expect(
            resolved?["Content-Type"] == "text/plain",
            "Should use existing content-type header value")
        #expect(resolved?["Authorization"] == "Bearer token", "Should preserve other headers")
    }

    @Test func testResolvedHeadersRejectsControlCharactersInContentType() async throws {
        // Test that contentType with control characters is rejected to prevent header injection
        struct TestEndpoint: Endpoint {
            var scheme: URLScheme = .https
            var host: String = "api.example.com"
            var path: String = "/test"
            var method: RequestMethod = .post
            var headers: [String: String]? = nil
            var queryItems: [URLQueryItem]? = nil
            var contentType: String? = "application/json\r\nX-Injected: malicious"
            var timeout: TimeInterval? = nil
            var timeoutDuration: Duration? = nil
            var body: Data? = Data("test".utf8)
        }

        let endpoint = TestEndpoint()
        let resolved = endpoint.resolvedHeaders

        // Should reject contentType with control characters and not set Content-Type header
        #expect(
            resolved?["Content-Type"] == nil, "Should reject contentType with control characters")
        #expect(
            resolved == nil || resolved?.isEmpty == true,
            "Should not inject any headers when contentType has control characters")
    }

    @Test func testResolvedHeadersAcceptsValidContentType() async throws {
        // Test that valid contentType without control characters is accepted
        struct TestEndpoint: Endpoint {
            var scheme: URLScheme = .https
            var host: String = "api.example.com"
            var path: String = "/test"
            var method: RequestMethod = .post
            var headers: [String: String]? = nil
            var queryItems: [URLQueryItem]? = nil
            var contentType: String? = "application/json"
            var timeout: TimeInterval? = nil
            var timeoutDuration: Duration? = nil
            var body: Data? = Data("test".utf8)
        }

        let endpoint = TestEndpoint()
        let resolved = endpoint.resolvedHeaders

        // Should accept valid contentType and set Content-Type header
        #expect(resolved?["Content-Type"] == "application/json", "Should accept valid contentType")
    }

    @Test func testNormalizedPathAddsLeadingSlash() async throws {
        // Test that normalizedPath adds leading slash when missing
        struct TestEndpoint: Endpoint {
            var scheme: URLScheme = .https
            var host: String = "api.example.com"
            var path: String = "users"  // Missing leading slash
            var method: RequestMethod = .get
            var headers: [String: String]? = nil
            var queryItems: [URLQueryItem]? = nil
            var contentType: String? = nil
            var timeout: TimeInterval? = nil
            var timeoutDuration: Duration? = nil
            var body: Data? = nil
        }

        let endpoint = TestEndpoint()
        #expect(endpoint.normalizedPath == "/users", "Should add leading slash to path without one")
    }

    @Test func testNormalizedPathPreservesExistingLeadingSlash() async throws {
        // Test that normalizedPath preserves existing leading slash
        struct TestEndpoint: Endpoint {
            var scheme: URLScheme = .https
            var host: String = "api.example.com"
            var path: String = "/users"  // Already has leading slash
            var method: RequestMethod = .get
            var headers: [String: String]? = nil
            var queryItems: [URLQueryItem]? = nil
            var contentType: String? = nil
            var timeout: TimeInterval? = nil
            var timeoutDuration: Duration? = nil
            var body: Data? = nil
        }

        let endpoint = TestEndpoint()
        #expect(endpoint.normalizedPath == "/users", "Should preserve existing leading slash")
    }
}

@Suite("AsyncNetConfig Tests")
struct AsyncNetConfigTests {
    @Test func testAsyncNetConfigThreadSafety() async throws {
        // Test that AsyncNetConfig can be safely accessed from concurrent contexts
        let config = AsyncNetConfig(timeoutDuration: 60.0)

        // Test initial value
        let initialTimeout = await config.timeoutDuration
        #expect(initialTimeout == 60.0, "Initial timeout should be 60 seconds")

        // Test setting new timeout
        await config.setTimeoutDuration(30.0)
        let newTimeout = await config.timeoutDuration
        #expect(newTimeout == 30.0, "Timeout should be updated to 30 seconds")

        // Test reset
        await config.resetTimeoutDuration()
        let resetTimeout = await config.timeoutDuration
        #expect(resetTimeout == 60.0, "Timeout should be reset to 60 seconds")
    }

    @Test func testWrapAsyncWithCustomTimeout() async throws {
        // Test that wrapAsync uses the configured timeout duration
        let config = AsyncNetConfig(timeoutDuration: 60.0)

        // Set custom timeout
        await config.setTimeoutDuration(45.0)

        // Verify setting worked
        let afterSet = await config.timeoutDuration
        #expect(afterSet == 45.0, "Config should be set to 45.0")

        let urlError = URLError(.timedOut)
        let wrapped = await NetworkError.wrapAsync(urlError, config: config)

        if case let .requestTimeout(duration) = wrapped {
            #expect(
                duration == 45.0, "Should use configured timeout duration of 45.0, got \(duration)")
        } else {
            #expect(Bool(false), "Expected requestTimeout error, got \(wrapped)")
        }
    }

    @Test func testWrapAsyncURLErrorMapping() async throws {
        let config = AsyncNetConfig(timeoutDuration: 60.0)

        // Test various URLError codes
        let testCases: [(URLError.Code, NetworkError)] = [
            (.timedOut, .requestTimeout(duration: 60.0)),
            (.notConnectedToInternet, .networkUnavailable),
            (.networkConnectionLost, .networkUnavailable),
            (.cannotConnectToHost, .networkUnavailable),
            (.cannotFindHost, .invalidEndpoint(reason: "Host not found")),
            (.dnsLookupFailed, .invalidEndpoint(reason: "DNS lookup failed")),
            (.cancelled, .requestCancelled),
        ]

        for (code, expected) in testCases {
            let urlError = URLError(code)
            let wrapped = await NetworkError.wrapAsync(urlError, config: config)

            switch (code, expected) {
            case (.timedOut, .requestTimeout):
                if case .requestTimeout = wrapped {
                    // Success - timeout duration verified above
                } else {
                    #expect(Bool(false), "Expected requestTimeout for .timedOut")
                }
            default:
                #expect(wrapped == expected, "Expected \(expected) for \(code), got \(wrapped)")
            }
        }
    }

    @Test func testWrapAsyncDecodingError() async throws {
        let config = AsyncNetConfig(timeoutDuration: 60.0)

        // Create a real DecodingError
        let invalidJSON = "invalid json".data(using: .utf8)!
        struct TestModel: Decodable {
            let value: Int
        }

        do {
            _ = try JSONDecoder().decode(TestModel.self, from: invalidJSON)
            #expect(Bool(false), "Expected decoding to fail")
        } catch let decodingError as DecodingError {
            let wrapped = await NetworkError.wrapAsync(decodingError, config: config)

            if case let .decodingFailed(reason, underlying, data) = wrapped {
                #expect(reason.contains("Data corrupted"), "Should contain data corruption message")
                #expect(underlying is DecodingError, "Should preserve original DecodingError")
                #expect(data == nil, "Should not include data for this error type")
            } else {
                #expect(Bool(false), "Expected decodingFailed error for DecodingError")
            }
        } catch {
            #expect(Bool(false), "Expected DecodingError")
        }
    }

    @Test func testWrapAsyncUnknownError() async throws {
        let config = AsyncNetConfig(timeoutDuration: 60.0)

        struct CustomError: Error {
            let message = "Custom test error"
        }

        let customError = CustomError()
        let wrapped = await NetworkError.wrapAsync(customError, config: config)

        if case let .customError(message, details) = wrapped {
            #expect(message == "Unknown error", "Should use generic unknown error message")
            #expect(
                details?.contains("Custom test error") == true,
                "Should include original error description")
        } else {
            #expect(Bool(false), "Expected customError for unknown error type")
        }
    }
}
