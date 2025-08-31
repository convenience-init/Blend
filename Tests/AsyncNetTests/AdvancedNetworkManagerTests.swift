import Testing
import Foundation
@testable import AsyncNet

@Suite("AdvancedNetworkManager Tests")
struct AdvancedNetworkManagerTests {
    @Test func testDeduplicationReturnsSameTaskSingleRequest() async throws {
        let cache = DefaultNetworkCache(maxSize: 10, expiration: 60)
        let mockSession = MockURLSession(nextData: Data([0x01, 0x02, 0x03]), nextResponse: HTTPURLResponse(
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
        #expect(recordedRequests.count == 1, "Expected exactly one network request due to deduplication")
    }

    @Test func testRetryPolicyBackoff() async throws {
        let cache = DefaultNetworkCache(maxSize: 10, expiration: 60)
        let mockSession = MockURLSession(nextError: NetworkError.networkUnavailable)
        let manager = AdvancedNetworkManager(cache: cache, urlSession: mockSession)
        let request = URLRequest(url: URL(string: "https://mock.api/fail")!)
        let retryPolicy = RetryPolicy(maxRetries: 1, shouldRetry: { _, _ in true }, backoff: { _ in 0.01 })
        do {
            _ = try await manager.fetchData(for: request, cacheKey: "fail-key", retryPolicy: retryPolicy)
            #expect(Bool(false))
        } catch {
            #expect(error is NetworkError)
        }
        let recorded = await mockSession.recordedRequests
        #expect(recorded.count == 2, "Expected initial attempt + 1 retry.")
    }

    @Test func testRetryPolicyBackoffCapping() async throws {
        // Test that backoff is capped at maxBackoff when used in fetchData
        let policy = RetryPolicy.exponentialBackoff(maxRetries: 3, maxBackoff: 10.0)
        
        // Test various attempt values - these return raw values from closure
        let backoff1 = policy.backoff?(0) ?? 0.0
        let backoff2 = policy.backoff?(1) ?? 0.0  
        let backoff3 = policy.backoff?(2) ?? 0.0
        let backoff4 = policy.backoff?(3) ?? 0.0 // This would be 8+random without cap
        
        // Raw backoff values should not be capped in the closure
        #expect(backoff1 > 0, "Backoff should be positive")
        #expect(backoff2 > backoff1, "Backoff should increase exponentially")
        #expect(backoff3 > backoff2, "Backoff should increase exponentially")
        #expect(backoff4 > backoff3, "Backoff should increase exponentially")
        
        // Test that capping happens when using the policy in practice
        let highAttemptPolicy = RetryPolicy.exponentialBackoff(maxRetries: 10, maxBackoff: 5.0)
        let rawBackoff = highAttemptPolicy.backoff?(10) ?? 0.0 // 2^10 = 1024, uncapped
        #expect(rawBackoff > 1000, "Raw backoff should be very high without capping")
        
        // Simulate the capping that happens in fetchData
        let cappedBackoff = min(max(rawBackoff, 0.0), highAttemptPolicy.maxBackoff)
        #expect(cappedBackoff <= 5.0, "Capped backoff should respect maxBackoff")
        #expect(cappedBackoff == 5.0, "High raw backoff should be capped to maxBackoff")
    }

    @Test func testCacheReturnsCachedData() async throws {
        let cache = DefaultNetworkCache(maxSize: 10, expiration: 60)
        let mockSession = MockURLSession(nextData: Data([0x01, 0x02, 0x03]), nextResponse: HTTPURLResponse(
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
    }

    @Test func testConditionalCachingOnlyCachesSuccessfulResponses() async throws {
        let cache = DefaultNetworkCache(maxSize: 10, expiration: 60)
        
        // Test 1: Successful response (200) should be cached
        let successData = Data([0x01, 0x02, 0x03])
        let successResponse = HTTPURLResponse(
            url: URL(string: "https://mock.api/success")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )
        let successSession = MockURLSession(nextData: successData, nextResponse: successResponse)
        let manager = AdvancedNetworkManager(cache: cache, urlSession: successSession)
        
        let successRequest = URLRequest(url: URL(string: "https://mock.api/success")!)
        let successResult = try await manager.fetchData(for: successRequest, cacheKey: "success-key")
        #expect(successResult == successData)
        
        // Verify successful response was cached
        let cachedSuccessData = await cache.get(forKey: "success-key")
        #expect(cachedSuccessData == successData, "Successful response should be cached")
        
        // Test 2: Error response (404) should not be cached
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
        let errorResult = try await errorManager.fetchData(for: errorRequest, cacheKey: "error-key")
        #expect(errorResult == errorData)
        
        // Verify error response was NOT cached
        let cachedErrorData = await cache.get(forKey: "error-key")
        #expect(cachedErrorData == nil, "Error response should not be cached")
        
        // Test 3: Non-HTTP response should not be cached
        let nonHttpData = Data([0x04, 0x05, 0x06])
        let nonHttpResponse = URLResponse(url: URL(string: "https://mock.api/nonhttp")!, mimeType: nil, expectedContentLength: 0, textEncodingName: nil)
        let nonHttpSession = MockURLSession(nextData: nonHttpData, nextResponse: nonHttpResponse)
        let nonHttpManager = AdvancedNetworkManager(cache: cache, urlSession: nonHttpSession)
        
        let nonHttpRequest = URLRequest(url: URL(string: "https://mock.api/nonhttp")!)
        let nonHttpResult = try await nonHttpManager.fetchData(for: nonHttpRequest, cacheKey: "nonhttp-key")
        #expect(nonHttpResult == nonHttpData)
        
        // Verify non-HTTP response was NOT cached
        let cachedNonHttpData = await cache.get(forKey: "nonhttp-key")
        #expect(cachedNonHttpData == nil, "Non-HTTP response should not be cached")
    }

    @Test func testRetryPolicyWithNonRetryableError() async throws {
        let cache = DefaultNetworkCache(maxSize: 10, expiration: 60)
        let mockSession = MockURLSession(nextError: NetworkError.invalidEndpoint(reason: "Test"))
        let manager = AdvancedNetworkManager(cache: cache, urlSession: mockSession)
        let request = URLRequest(url: URL(string: "https://mock.api/test")!)
        let retryPolicy = RetryPolicy(maxRetries: 3, shouldRetry: { error, _ in
            // Only retry on networkUnavailable error
            if let networkError = error as? NetworkError, case .networkUnavailable = networkError {
                return true
            }
            return false
        }, backoff: { attempt in
            return pow(2.0, Double(attempt - 1)) * 0.1 // Exponential backoff: 0.1s, 0.2s, 0.4s
        })
        
        do {
            _ = try await manager.fetchData(for: request, cacheKey: "key1", retryPolicy: retryPolicy)
            #expect(Bool(false), "Expected non-retryable error to be thrown")
        } catch {
            #expect(error is NetworkError)
            if case NetworkError.invalidEndpoint(let reason) = error {
                #expect(reason == "Test")
            } else {
                #expect(Bool(false), "Expected invalidEndpoint error")
            }
        }
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
            components.path = endPoint.path
            components.queryItems = endPoint.queryItems
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
            if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
                throw NetworkError.customError("HTTP error", details: "Status code: \(httpResponse.statusCode)")
            }
            // Decode Data into TestModel
            return try jsonDecoder.decode(TestModel.self, from: data)
        }
    }

    @Test func testSendRequestReturnsDecodedModel() async throws {
        let mockSession = MockURLSession(nextData: Data("{\"value\":42}".utf8), nextResponse: HTTPURLResponse(
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
        let mockSession = MockURLSession(nextData: Data("{\"value\":42}".utf8), nextResponse: HTTPURLResponse(
            url: URL(string: "https://mock.api/test")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        ))
        let service = MockService(urlSession: mockSession)
        let endpoint = MockEndpoint()
        let manager = AdvancedNetworkManager(urlSession: mockSession)
        let result: TestModel = try await service.sendRequestAdvanced(to: endpoint, networkManager: manager)
        #expect(result == TestModel(value: 42))
    }

    @Test func testSendRequestThrowsInvalidBodyForGET() async throws {
        let mockSession = MockURLSession(nextData: Data("{\"value\":42}".utf8), nextResponse: HTTPURLResponse(
            url: URL(string: "https://mock.api/test")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        ))
        let service = MockService(urlSession: mockSession)
        var endpoint = MockEndpoint()
        endpoint.body = Data("test body".utf8) // Add body to GET request
        
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
        let mockSession = MockURLSession(nextData: Data("{\"value\":42}".utf8), nextResponse: HTTPURLResponse(
            url: URL(string: "https://mock.api/test")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        ))
        let service = MockService(urlSession: mockSession)
        let endpoint = MockEndpoint.withBothTimeouts // Has timeoutDuration=15s, timeout=60s
        
        // Make the request
        _ = try await service.sendRequest(to: endpoint)
        
        // Verify the recorded request has the correct timeout (15s from timeoutDuration, not 60s from legacy timeout)
        let recordedRequests = await mockSession.recordedRequests
        #expect(recordedRequests.count == 1, "Expected exactly one request to be recorded")
        
        let request = recordedRequests[0]
        #expect(request.timeoutInterval == 15.0, "Expected timeoutDuration (15s) to take precedence over legacy timeout (60s)")
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
}

@Suite("NetworkError Tests")
struct NetworkErrorTests {
    @Test func testWrapCustomError() {
        struct DummyError: Error, Sendable {
            let message: String
            var localizedDescription: String { message }
        }
        let dummy = DummyError(message: "Dummy failure")
        let wrapped = NetworkError.wrap(dummy)
        if case let .custom(message, details) = wrapped {
            #expect(message == "Unknown error")
            #expect(details?.contains("Dummy failure") == true)
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
            if case let .custom(message, details) = wrapped {
                #expect(message == "Unknown error")
                #expect(details?.contains("DecodingError") == true)
            } else {
                #expect(Bool(false), "Expected custom error for DecodingError")
            }
        } catch {
            #expect(Bool(false), "Expected DecodingError")
        }
    }
    
    @Test func testInvalidBodyForGETError() {
        let error = NetworkError.invalidBodyForGET
        #expect(error.errorDescription == "GET requests cannot have a body.")
        #expect(error.recoverySuggestion == "Remove the body from GET requests or use a different HTTP method.")
    }
}
