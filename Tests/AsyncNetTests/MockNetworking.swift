import Foundation
@testable import AsyncNet

/// MockURLSession for unit testing, conforms to URLSessionProtocol
public final class MockURLSession: URLSessionProtocol, Sendable {
    public let nextData: Data?
    public let nextResponse: URLResponse?
    public let nextError: Error?

    public init(nextData: Data? = nil, nextResponse: URLResponse? = nil, nextError: Error? = nil) {
        self.nextData = nextData
        self.nextResponse = nextResponse
        self.nextError = nextError
    }

    public func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        if let error = nextError {
            throw error
        }
        guard let data = nextData, let response = nextResponse else {
            throw NetworkError.noResponse
        }
        return (data, response)
    }
}

/// MockEndpoint for testing Endpoint protocol
public struct MockEndpoint: Endpoint {
    public var scheme: URLScheme = .https
    public var host: String = "mock.api"
    public var path: String = "/test"
    public var method: RequestMethod = .get
    public var headers: [String: String]? = ["Content-Type": "application/json"]
    public var queryItems: [URLQueryItem]? = nil
    public var body: Data? = nil
    public var contentType: String? = "application/json"
    public var timeout: TimeInterval? = nil
    @available(*, deprecated, message: "Use body: Data? instead")
    public var legacyBody: [String: String]? = nil
    public init() {}
}
