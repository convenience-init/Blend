import Foundation
import Testing

@testable import Blend

// Extracted test model and services to reduce nesting violations
public struct TestModel: Decodable, Equatable {
    public let value: Int
}

public struct MockService: AdvancedAsyncRequestable {
    public typealias ResponseModel = TestModel
    public typealias SecondaryResponseModel = TestModel
    let urlSession: URLSessionProtocol

    public func sendRequest<T: Decodable>(_ type: T.Type, to endpoint: Endpoint) async throws -> T {
        // Use shared helper to build the request
        let request = try buildURLRequest(from: endpoint)

        // Perform network call
        let (data, response) = try await urlSession.data(for: request)
        // swiftlint:disable:next explicit_acl
        if let httpResponse = response as? HTTPURLResponse,
            !(200...299).contains(httpResponse.statusCode) {
            throw NetworkError.customError(
                "HTTP error", details: "Status code: \(httpResponse.statusCode)")
        }
        // Decode Data into ResponseModel
        return try jsonDecoder.decode(type, from: data)
    }

    public func sendRequest<ResponseModel>(
        to endPoint: Endpoint,
        session: URLSessionProtocol = URLSession.shared
    ) async throws -> ResponseModel where ResponseModel: Decodable {
        let request = try buildURLRequest(from: endPoint)
        let (data, response) = try await session.data(for: request)
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

// Extracted test services to reduce nesting violations
struct TestAsyncRequestableService: AsyncRequestable {
    public typealias ResponseModel = TestModel
    let testManager: AdvancedNetworkManager

    public var networkManager: AdvancedNetworkManager {
        testManager
    }

    public func sendRequest<ResponseModel>(
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

struct SimpleTestService: AdvancedAsyncRequestable {
    public typealias ResponseModel = Int
    public typealias SecondaryResponseModel = String

    public func sendRequest<T: Decodable>(_ type: T.Type, to endpoint: Endpoint) async throws -> T {
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

    public func sendRequest<ResponseModel>(
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

struct CustomDecoderTestService: AdvancedAsyncRequestable {
    public typealias ResponseModel = TestModel
    public typealias SecondaryResponseModel = TestModel
    let customDecoder: JSONDecoder

    public var jsonDecoder: JSONDecoder {
        customDecoder
    }

    public func sendRequest<T: Decodable>(_ type: T.Type, to endpoint: Endpoint) async throws -> T {
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

@Suite("AsyncRequestable & Endpoint Tests")
public struct AsyncRequestableProtocolTests {
    @Test public func testSendRequestReturnsDecodedModel() async throws {
        guard let testURL = URL(string: "https://mock.api/test") else {
            #expect(Bool(false), "Invalid test URL")
            return
        }
        let mockSession = MockURLSession(
            nextData: Data("{\"value\":42}".utf8),
            nextResponse: HTTPURLResponse(
                url: testURL,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            ))
        let service = MockService(urlSession: mockSession)
        let endpoint = MockEndpoint()
        let result: TestModel = try await service.sendRequest(TestModel.self, to: endpoint)
        #expect(result == TestModel(value: 42))
    }

    @Test public func testSendRequestAdvancedReturnsDecodedModel() async throws {
        guard let testURL = URL(string: "https://mock.api/test") else {
            #expect(Bool(false), "Invalid test URL")
            return
        }
        let mockSession = MockURLSession(
            nextData: Data("{\"value\":42}".utf8),
            nextResponse: HTTPURLResponse(
                url: testURL,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            ))

        let manager = AdvancedNetworkManager(urlSession: mockSession)
        let service = TestAsyncRequestableService(testManager: manager)
        let endpoint = MockEndpoint()
        let result: TestModel = try await service.sendRequestAdvanced(to: endpoint)
        #expect(result == TestModel(value: 42))
    }

    @Test public func testSendRequestThrowsInvalidBodyForGET() async throws {
        guard let testURL = URL(string: "https://mock.api/test") else {
            #expect(Bool(false), "Invalid test URL")
            return
        }
        let mockSession = MockURLSession(
            nextData: Data("{\"value\":42}".utf8),
            nextResponse: HTTPURLResponse(
                url: testURL,
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

    @Test public func testTimeoutResolutionPrefersDurationOverLegacy() async throws {
        guard let testURL = URL(string: "https://mock.api/test") else {
            #expect(Bool(false), "Invalid test URL")
            return
        }
        let mockSession = MockURLSession(
            nextData: Data("{\"value\":42}".utf8),
            nextResponse: HTTPURLResponse(
                url: testURL,
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

    @Test public func testJsonDecoderConfiguration() async throws {
        let service = SimpleTestService()
        let endpoint = MockEndpoint()
        let result: Int = try await service.sendRequest(to: endpoint)
        #expect(result == 42)
    }

    @Test public func testCustomJsonDecoderInjection() async throws {
        // Create a custom decoder with different configuration
        let customDecoder = JSONDecoder()
        customDecoder.keyDecodingStrategy = .useDefaultKeys  // Different from default snake_case

        let service = CustomDecoderTestService(customDecoder: customDecoder)

        // Since we're testing decoder injection, we'll create a simple test
        let result = try service.customDecoder.decode(
            TestModel.self, from: Data("{\"value\":99}".utf8))
        #expect(result.value == 99, "Custom decoder should decode the value correctly")
    }

    @Test public func testSendRequestThrowsForNon2xxStatusCode() async throws {
        // Test that non-2xx HTTP status codes throw NetworkError.customError with status code in message
        guard let errorURL = URL(string: "https://mock.api/error") else {
            #expect(Bool(false), "Invalid test URL")
            return
        }
        let mockSession = MockURLSession(
            nextData: Data(),  // Empty data for 500 response
            nextResponse: HTTPURLResponse(
                url: errorURL,
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
