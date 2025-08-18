import Testing
import Foundation
@testable import AsyncNet

@Suite("AdvancedNetworkManager Tests")
struct AdvancedNetworkManagerTests {
    @Test func testDeduplicationReturnsSameTask() async throws {
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
        #expect(result1 == result2)
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
                request.httpBody = body
            }
            // Perform network call
            let (data, response) = try await urlSession.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
                throw NetworkError.customError("HTTP error", details: "Status code: \(httpResponse.statusCode)")
            }
            // Decode Data into TestModel
            return try JSONDecoder().decode(TestModel.self, from: data)
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
}

@Suite("NetworkError Tests")
struct NetworkErrorTests {
    @Test func testWrapUnknownFallback() {
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
        #expect(wrapped == .transportError(code: .cannotFindHost, underlying: urlError))
    }
    @Test func testWrapDecodingError() {
        struct DummyDecodingError: Error, Sendable {
            let message: String
            var localizedDescription: String { message }
        }
        let dummy = DummyDecodingError(message: "Corrupted")
        let error = NetworkError.wrap(dummy)
        if case let .custom(message, details) = error {
            #expect(message == "Unknown error")
            #expect(details?.contains("Corrupted") == true)
        } else {
            #expect(Bool(false))
        }
    }
}
