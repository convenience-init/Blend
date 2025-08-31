import Foundation
@testable import AsyncNet

/// MockURLSession for unit testing, conforms to URLSessionProtocol
actor MockURLSession: URLSessionProtocol {
    /// Scripted responses for multiple calls - arrays allow different results per call
    let scriptedData: [Data?]
    let scriptedResponses: [URLResponse?]
    let scriptedErrors: [Error?]
    private var _callCount: Int = 0
    private var _recordedRequests: [URLRequest] = []
    
    /// Actor-isolated call count for tracking mock network requests.
    /// Must be accessed with `await` from outside the actor due to actor isolation.
    /// Example: `let count = await mockSession.callCount`
    var callCount: Int {
        _callCount
    }
    
    /// Actor-isolated recorded requests for verifying call arguments in tests.
    /// Must be accessed with `await` from outside the actor due to actor isolation.
    /// Example: `let requests = await mockSession.recordedRequests`
    var recordedRequests: [URLRequest] {
        _recordedRequests
    }

    /// Initialize with single scripted result (backward compatibility)
    init(nextData: Data? = nil, nextResponse: URLResponse? = nil, nextError: Error? = nil) {
        self.scriptedData = [nextData]
        self.scriptedResponses = [nextResponse]
        self.scriptedErrors = [nextError]
    }
    
    /// Initialize with multiple scripted results for testing multi-call scenarios
    init(scriptedData: [Data?], scriptedResponses: [URLResponse?], scriptedErrors: [Error?]) {
        self.scriptedData = scriptedData
        self.scriptedResponses = scriptedResponses
        self.scriptedErrors = scriptedErrors
    }
    
    /// Initialize with an array of tuples to keep scripted triples aligned
    /// Each tuple contains (data, response, error) for one mock call
    init(scriptedCalls: [(Data?, URLResponse?, Error?)]) {
        let scriptedData = scriptedCalls.map { $0.0 }
        let scriptedResponses = scriptedCalls.map { $0.1 }
        let scriptedErrors = scriptedCalls.map { $0.2 }
        self.init(scriptedData: scriptedData, scriptedResponses: scriptedResponses, scriptedErrors: scriptedErrors)
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let currentCallIndex = _callCount
        _callCount += 1
        _recordedRequests.append(request)
        
        // Get the scripted error for this call (if any)
        let scriptedError = currentCallIndex < scriptedErrors.count ? scriptedErrors[currentCallIndex] : nil
        if let error = scriptedError {
            throw error
        }
        
        // Get the scripted data and response for this call
        let data = currentCallIndex < scriptedData.count ? scriptedData[currentCallIndex] : nil
        let response = currentCallIndex < scriptedResponses.count ? scriptedResponses[currentCallIndex] : nil
        
        guard let data = data, let response = response else {
            throw NetworkError.outOfScriptBounds(call: currentCallIndex + 1)
        }
        
        return (data, response)
    }
}

/// MockEndpoint for testing Endpoint protocol
struct MockEndpoint: Endpoint {
    /// Properties are mutable to allow test overrides and convenient configuration in test scenarios.
    var scheme: URLScheme = .https
    var host: String = "mock.api"
    var path: String = "/test"
    var method: RequestMethod = .get
    var headers: [String: String]? = nil
    var queryItems: [URLQueryItem]? = nil
    var contentType: String? = "application/json"
    var timeout: TimeInterval? = nil
    var timeoutDuration: Duration? = nil
    var body: Data? = nil
    init() {}
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
