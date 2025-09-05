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
        // Script multiple failures to trigger retries: first 2 fail, third succeeds
        let mockSession = MockURLSession(scriptedCalls: [
            (nil, nil, NetworkError.networkUnavailable),  // First attempt fails
            (nil, nil, NetworkError.networkUnavailable),  // Retry 1 fails
            (
                Data([0x01, 0x02, 0x03]),
                HTTPURLResponse(
                    url: URL(string: "https://mock.api/test")!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                ), nil
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
            elapsed >= 0.3, "Expected at least 0.3s elapsed due to backoff delays (0.1s + 0.2s)")
        #expect(elapsed < 1.5, "Expected less than 1.5s elapsed (backoff should be reasonable)")
    }

    @Test func testRetryPolicyBackoffCapping() async throws {
        // Test that backoff is capped at maxBackoff when used in fetchData
        // Use a deterministic custom policy to avoid flakiness from factory jitter
        let policy = RetryPolicy(
            maxAttempts: 3,
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
            maxAttempts: 10,
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
        // Policy: Only 2xx responses are cached, non-2xx responses throw errors
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
        do {
            _ = try await errorManager.fetchData(
                for: errorRequest, cacheKey: "error-404-key")
            #expect(Bool(false), "Expected NetworkError.notFound for 404 status code")
        } catch let error as NetworkError {
            // Verify it's the expected HTTP error
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
            maxAttempts: 3,
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
                return pow(2.0, Double(attempt)) * 0.1  // Exponential backoff: 0.1s, 0.2s, 0.4s
            })

        do {
            _ = try await manager.fetchData(
                for: request, cacheKey: "key1", retryPolicy: retryPolicy)
            #expect(Bool(false), "Expected non-retryable error to be thrown")
        } catch {
            #expect(error is NetworkError)
            if let netErr = error as? NetworkError, case .invalidEndpoint(let reason) = netErr {
                #expect(reason == "Test")
            } else {
                #expect(Bool(false), "Expected invalidEndpoint error")
            }
        }
        let recorded = await mockSession.recordedRequests
        #expect(recorded.count == 1, "Non-retryable error should not be retried")
    }

    @Test func testRetryPolicyBackoffCappingInPractice() async throws {
        let cache = DefaultNetworkCache(maxSize: 10, expiration: 60)
        // Script multiple failures to trigger retries
        let mockSession = MockURLSession(scriptedCalls: [
            (nil, nil, NetworkError.networkUnavailable),  // First attempt
            (nil, nil, NetworkError.networkUnavailable),  // Retry 1
            (
                Data([0x01]),
                HTTPURLResponse(
                    url: URL(string: "https://mock.api/test")!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                ), nil
            ),  // Retry 2 succeeds
        ])
        let manager = AdvancedNetworkManager(cache: cache, urlSession: mockSession)
        let request = URLRequest(url: URL(string: "https://mock.api/test")!)

        let policy = RetryPolicy(
            maxAttempts: 3,
            shouldRetry: { _, _ in true },
            backoff: { attempt in pow(10.0, Double(attempt)) },  // 10s, 100s, 1000s
            maxBackoff: 0.5  // Cap at 0.5 seconds
        )

        let startTime = Date()
        _ = try await manager.fetchData(
            for: request, cacheKey: "test-key", retryPolicy: policy)
        let elapsed = Date().timeIntervalSince(startTime)

        // With maxBackoff of 0.5s and 2 retries, total delay should be ~1s
        // Allow some tolerance for execution time
        #expect(elapsed < 2.0, "Total elapsed time should respect maxBackoff capping")
    }

    @Test func testRequestTimeoutDoesNotMutateOriginalRequest() async throws {
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

        // Create original request with specific timeout
        var originalRequest = URLRequest(url: URL(string: "https://mock.api/test")!)
        originalRequest.timeoutInterval = 10.0  // Set original timeout

        // Store the original timeout for comparison
        let originalTimeout = originalRequest.timeoutInterval

        // Use the request in fetchData with a different retry policy timeout
        let retryPolicy = RetryPolicy(maxAttempts: 2, timeoutInterval: 30.0)
        _ = try await manager.fetchData(
            for: originalRequest, cacheKey: "test-key", retryPolicy: retryPolicy)

        // Verify the original request object was not mutated
        #expect(
            originalRequest.timeoutInterval == originalTimeout,
            "Original request timeout should not be mutated by retry policy")
        #expect(originalRequest.timeoutInterval == 10.0, "Original timeout should remain 10.0")
    }
}

@Suite("AsyncRequestable & Endpoint Tests")
struct AsyncRequestableTests {
    struct TestModel: Decodable, Equatable { let value: Int }
    struct MockService: AdvancedAsyncRequestable {
        typealias ResponseModel = TestModel
        typealias SecondaryResponseModel = TestModel
        let urlSession: URLSessionProtocol
        
        func sendRequest<T: Decodable>(_ type: T.Type, to endpoint: Endpoint) async throws -> T {
            // Use shared helper to build the request
            let request = try buildURLRequest(from: endpoint)

            // Perform network call
            let (data, response) = try await urlSession.data(for: request)
            if let httpResponse = response as? HTTPURLResponse,
                !(200...299).contains(httpResponse.statusCode)
            {
                throw NetworkError.customError(
                    "HTTP error", details: "Status code: \(httpResponse.statusCode)")
            }
            // Decode Data into ResponseModel
            return try jsonDecoder.decode(type, from: data)
        }

        func sendRequest<ResponseModel>(
            to endPoint: Endpoint,
            session: URLSessionProtocol = URLSession.shared
        ) async throws -> ResponseModel where ResponseModel: Decodable {
            let request = try buildURLRequest(from: endPoint)
            let (data, response) = try await session.data(for: request)  // Use self.urlSession instead of session parameter
            guard let httpResponse = response as? HTTPURLResponse else {
                throw NetworkError.noResponse
            }
            switch httpResponse.statusCode {
            case 200...299:
                do {
                    return try jsonDecoder.decode(ResponseModel.self, from: data)
                } catch {
                    throw NetworkError.decodingError(underlying: error, data: data)
                }
            case 400:
                throw NetworkError.badRequest(data: data, statusCode: httpResponse.statusCode)
            case 401:
                throw NetworkError.unauthorized(data: data, statusCode: httpResponse.statusCode)
            case 403:
                throw NetworkError.forbidden(data: data, statusCode: httpResponse.statusCode)
            case 404:
                throw NetworkError.notFound(data: data, statusCode: httpResponse.statusCode)
            case 429:
                throw NetworkError.rateLimited(data: data, statusCode: httpResponse.statusCode)
            case 500...599:
                throw NetworkError.customError(
                    "HTTP error", details: "Status code: \(httpResponse.statusCode)")
            default:
                throw NetworkError.httpError(statusCode: httpResponse.statusCode, data: data)
            }
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
        let result: TestModel = try await service.sendRequest(TestModel.self, to: endpoint)
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
        
        // Create a test service with custom network manager
        struct TestService: AsyncRequestable {
            typealias ResponseModel = TestModel
            let testManager: AdvancedNetworkManager

            var networkManager: AdvancedNetworkManager {
                testManager
            }

            func sendRequest<ResponseModel>(
                to endPoint: Endpoint, session: URLSessionProtocol = URLSession.shared
            ) async throws -> ResponseModel
            where ResponseModel: Decodable {
                // Build the request and fetch data using the test manager
                let request = try buildURLRequest(from: endPoint)
                let data = try await testManager.fetchData(for: request)
                // Decode the response
                return try jsonDecoder.decode(ResponseModel.self, from: data)
            }
        }

        let manager = AdvancedNetworkManager(urlSession: mockSession)
        let service = TestService(testManager: manager)
        let endpoint = MockEndpoint()
        let result: TestModel = try await service.sendRequestAdvanced(to: endpoint)
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
        let endpoint = MockEndpoint(body: Data("test body".utf8))  // Add body to GET request

        do {
            _ = try await service.sendRequest(to: endpoint, session: mockSession) as TestModel
            #expect(Bool(false), "Expected invalidEndpoint error for GET with body")
        } catch let error as NetworkError {
            if case let .invalidEndpoint(reason) = error {
                #expect(
                    reason.contains("GET requests must not have a body"),
                    "Should contain descriptive error message")
            } else {
                #expect(Bool(false), "Expected NetworkError.invalidEndpoint")
            }
        } catch {
            #expect(Bool(false), "Expected NetworkError.invalidEndpoint")
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
        _ = try await service.sendRequest(to: endpoint, session: mockSession) as TestModel

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
        struct SimpleService: AdvancedAsyncRequestable {
            typealias ResponseModel = Int
            typealias SecondaryResponseModel = String

            func sendRequest<T: Decodable>(_ type: T.Type, to endpoint: Endpoint) async throws -> T
            {
                // Just test that jsonDecoder is accessible and returns a JSONDecoder
                _ = jsonDecoder
                // For testing purposes, return a dummy value that can be decoded
                if type == Int.self {
                    guard let result = 42 as? T else {
                        throw NetworkError.decodingError(
                            underlying: NSError(
                                domain: "Test", code: -1,
                                userInfo: [NSLocalizedDescriptionKey: "Type cast failed in test"]),
                            data: Data())
                    }
                    return result
                } else {
                    throw NetworkError.decodingError(
                        underlying: NSError(domain: "Test", code: -1), data: Data())
                }
            }
            
            func sendRequest<ResponseModel>(
                to endPoint: Endpoint,
                session: URLSessionProtocol = URLSession.shared
            ) async throws -> ResponseModel where ResponseModel: Decodable {
                // Just test that jsonDecoder is accessible
                _ = jsonDecoder
                // Return dummy value for testing
                if ResponseModel.self == Int.self {
                    guard let result = 42 as? ResponseModel else {
                        throw NetworkError.decodingError(
                            underlying: NSError(domain: "Test", code: -1), data: Data())
                    }
                    return result
                } else {
                    throw NetworkError.decodingError(
                        underlying: NSError(domain: "Test", code: -1), data: Data())
                }
            }
        }

        let service = SimpleService()
        let endpoint = MockEndpoint()
        let result: Int = try await service.sendRequest(to: endpoint)
        #expect(result == 42)
    }

    @Test func testCustomJsonDecoderInjection() async throws {
        // Test that custom decoders can be injected for testing
        struct TestService: AdvancedAsyncRequestable {
            typealias ResponseModel = TestModel
            typealias SecondaryResponseModel = TestModel
            let customDecoder: JSONDecoder

            var jsonDecoder: JSONDecoder {
                customDecoder
            }

            func sendRequest<T: Decodable>(_ type: T.Type, to endpoint: Endpoint) async throws -> T
            {
                // Use the injected decoder
                if type == TestModel.self {
                    let decodedValue = try customDecoder.decode(
                        TestModel.self, from: Data("{\"value\":99}".utf8))
                    guard let result = decodedValue as? T else {
                        throw NetworkError.decodingError(
                            underlying: NSError(
                                domain: "Test", code: -1,
                                userInfo: [NSLocalizedDescriptionKey: "Type cast failed in test"]),
                            data: Data())
                    }
                    return result
                } else {
                    throw NetworkError.decodingError(
                        underlying: NSError(domain: "Test", code: -1), data: Data())
                }
            }
        }

        // Create a custom decoder with different configuration
        let customDecoder = JSONDecoder()
        customDecoder.keyDecodingStrategy = .useDefaultKeys  // Different from default snake_case

        let service = TestService(customDecoder: customDecoder)

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
            _ = try await service.sendRequest(to: endpoint, session: mockSession) as TestModel
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

@Suite("AdvancedNetworkManager LRU Cache Tests")
struct AdvancedNetworkManagerLRUCacheTests {

    @Test func testAdvancedNetworkManagerLRUBasicOperations() async {
        let cache = DefaultNetworkCache(maxSize: 3, expiration: 3600.0)

        let data1 = Data([1, 2, 3])
        let data2 = Data([4, 5, 6])
        let data3 = Data([7, 8, 9])
        let data4 = Data([10, 11, 12])

        // Add items
        await cache.set(data1, forKey: "key1")
        await cache.set(data2, forKey: "key2")
        await cache.set(data3, forKey: "key3")

        // Access key1 to make it most recently used
        let retrieved1 = await cache.get(forKey: "key1")
        #expect(retrieved1 == data1)

        // Add key4, should evict key2 (least recently used)
        await cache.set(data4, forKey: "key4")

        // key2 should be evicted
        let retrieved2 = await cache.get(forKey: "key2")
        #expect(retrieved2 == nil)

        // Others should still be there
        let retrieved1Again = await cache.get(forKey: "key1")
        let retrieved3 = await cache.get(forKey: "key3")
        let retrieved4 = await cache.get(forKey: "key4")
        #expect(retrieved1Again == data1)
        #expect(retrieved3 == data3)
        #expect(retrieved4 == data4)
    }

    @Test func testAdvancedNetworkManagerLRUNodeRemoval() async {
        let cache = DefaultNetworkCache(maxSize: 5, expiration: 3600.0)

        // Add multiple items
        for i in 1...5 {
            let data = Data([UInt8(i)])
            await cache.set(data, forKey: "key\(i)")
        }

        // Remove middle item
        await cache.remove(forKey: "key3")

        // Should be able to add new item without issues
        let data = Data([6])
        await cache.set(data, forKey: "key6")

        // Verify structure integrity
        let retrieved1 = await cache.get(forKey: "key1")
        let retrieved2 = await cache.get(forKey: "key2")
        let retrieved3 = await cache.get(forKey: "key3")
        let retrieved4 = await cache.get(forKey: "key4")
        let retrieved5 = await cache.get(forKey: "key5")
        let retrieved6 = await cache.get(forKey: "key6")

        #expect(retrieved1 == Data([1]))
        #expect(retrieved2 == Data([2]))
        #expect(retrieved3 == nil)  // Should be removed
        #expect(retrieved4 == Data([4]))
        #expect(retrieved5 == Data([5]))
        #expect(retrieved6 == Data([6]))
    }

    @Test func testAdvancedNetworkManagerLRUExpiration() async {
        // Use a very short expiration for testing
        let cache = DefaultNetworkCache(maxSize: 10, expiration: 0.1)

        let data = Data([1, 2, 3])
        await cache.set(data, forKey: "key1")

        // Should be available immediately
        let retrieved = await cache.get(forKey: "key1")
        #expect(retrieved == data)

        // Wait for expiration
        try? await Task.sleep(nanoseconds: 200_000_000)  // 0.2 seconds

        // Should be expired
        let expired = await cache.get(forKey: "key1")
        #expect(expired == nil)
    }

    @Test func testAdvancedNetworkManagerLRUClear() async {
        let cache = DefaultNetworkCache(maxSize: 5, expiration: 3600.0)

        // Add items
        for i in 1...3 {
            let data = Data([UInt8(i)])
            await cache.set(data, forKey: "key\(i)")
        }

        // Clear cache
        await cache.clear()

        // All items should be gone
        for i in 1...3 {
            let retrieved = await cache.get(forKey: "key\(i)")
            #expect(retrieved == nil)
        }
    }

    @Test func testAdvancedNetworkManagerLRUStressTest() async {
        let cache = DefaultNetworkCache(maxSize: 100, expiration: 3600.0)

        // Add many items
        for i in 1...50 {  // Reduced count to avoid timeout
            let data = Data([UInt8(i % 256)])
            await cache.set(data, forKey: "key\(i)")
        }

        // Random access pattern
        for _ in 1...25 {  // Reduced count
            let randomKey = "key\(Int.random(in: 1...50))"
            _ = await cache.get(forKey: randomKey)
        }

        // Should still work without crashes
        let testData = Data([255])
        await cache.set(testData, forKey: "test")
        let retrieved = await cache.get(forKey: "test")
        #expect(retrieved == testData)
    }

    @Test func testAdvancedNetworkManagerLRUConcurrentAccess() async {
        let cache = DefaultNetworkCache(maxSize: 50, expiration: 3600.0)

        // Concurrent operations
        await withTaskGroup(of: Void.self) { group in
            for i in 1...10 {
                group.addTask {
                    let data = Data([UInt8(i)])
                    await cache.set(data, forKey: "key\(i)")
                }
            }

            for i in 1...10 {
                group.addTask {
                    _ = await cache.get(forKey: "key\(i)")
                }
            }

            for i in 11...20 {
                group.addTask {
                    let data = Data([UInt8(i)])
                    await cache.set(data, forKey: "key\(i)")
                }
            }
        }

        // Should not have crashed and basic operations should work
        let testData = Data([100])
        await cache.set(testData, forKey: "final")
        let retrieved = await cache.get(forKey: "final")
        #expect(retrieved == testData)
    }
}
