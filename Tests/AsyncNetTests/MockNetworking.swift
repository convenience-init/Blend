import Foundation
@testable import AsyncNet

/// MockURLSession for unit testing, conforms to URLSessionProtocol
public actor MockURLSession: URLSessionProtocol {
    /// Scripted responses for multiple calls - arrays allow different results per call
    public let scriptedData: [Data?]
    public let scriptedResponses: [URLResponse?]
    public let scriptedErrors: [Error?]
    private var _callCount: Int = 0
    
    public var callCount: Int {
        _callCount
    }

    /// Initialize with single scripted result (backward compatibility)
    public init(nextData: Data? = nil, nextResponse: URLResponse? = nil, nextError: Error? = nil) {
        self.scriptedData = [nextData]
        self.scriptedResponses = [nextResponse]
        self.scriptedErrors = [nextError]
    }
    
    /// Initialize with multiple scripted results for testing multi-call scenarios
    public init(scriptedData: [Data?], scriptedResponses: [URLResponse?], scriptedErrors: [Error?]) {
        self.scriptedData = scriptedData
        self.scriptedResponses = scriptedResponses
        self.scriptedErrors = scriptedErrors
    }

    public func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let currentCallIndex = _callCount
        _callCount += 1
        
        // Get the scripted error for this call (if any)
        let scriptedError = currentCallIndex < scriptedErrors.count ? scriptedErrors[currentCallIndex] : nil
        if let error = scriptedError {
            throw error
        }
        
        // Get the scripted data and response for this call
        let data = currentCallIndex < scriptedData.count ? scriptedData[currentCallIndex] : nil
        let response = currentCallIndex < scriptedResponses.count ? scriptedResponses[currentCallIndex] : nil
        
        guard let data = data, let response = response else {
            throw NetworkError.custom(
                message: "MockURLSession: No scripted response available for call #\(currentCallIndex + 1)",
                details: "Call count: \(_callCount), Available data: \(scriptedData.count), Available responses: \(scriptedResponses.count)"
            )
        }
        
        return (data, response)
    }
}

/// MockEndpoint for testing Endpoint protocol
public struct MockEndpoint: Endpoint {
    /// Properties are mutable to allow test overrides and convenient configuration in test scenarios.
    public var scheme: URLScheme = .https
    public var host: String = "mock.api"
    public var path: String = "/test"
    public var method: RequestMethod = .get
    public var headers: [String: String]? = ["Content-Type": "application/json"]
    public var queryItems: [URLQueryItem]? = nil
    public var contentType: String? = "application/json"
    public var timeout: TimeInterval? = nil
    public var timeoutDuration: Duration? = nil
    public var body: Data? = nil
    public init() {}
}

// MARK: - Duration Timeout Tests
extension MockEndpoint {
    /// Test endpoint demonstrating Duration-based timeout
    static var withDurationTimeout: MockEndpoint {
        var endpoint = MockEndpoint()
        endpoint.timeoutDuration = .seconds(45)
        return endpoint
    }
    
    /// Test endpoint demonstrating legacy TimeInterval timeout
    static var withLegacyTimeout: MockEndpoint {
        var endpoint = MockEndpoint()
        endpoint.timeout = 30.0
        return endpoint
    }
    
    /// Test endpoint with both timeout types (Duration takes precedence)
    static var withBothTimeouts: MockEndpoint {
        var endpoint = MockEndpoint()
        endpoint.timeoutDuration = .milliseconds(15000) // 15 seconds
        endpoint.timeout = 60.0 // 60 seconds (ignored)
        return endpoint
    }
}
