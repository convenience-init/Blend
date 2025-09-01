import Foundation

@testable import AsyncNet

/// MockURLSession for unit testing, conforms to URLSessionProtocol
actor MockURLSession: URLSessionProtocol {
    /// Private mutable storage for scripted responses - single array keeps all values aligned
    private var scriptedScripts: [(data: Data?, response: URLResponse?, error: Error?)]
    private var _callCount: Int = 0
    private var _recordedRequests: [URLRequest] = []

    /// Artificial delay to simulate network latency (in nanoseconds)
    /// Used for testing concurrency timing
    private let artificialDelay: UInt64

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

    /// Actor-isolated accessor for the last recorded request to avoid copying the full array.
    /// Must be accessed with `await` from outside the actor due to actor isolation.
    /// Example: `let last = await mockSession.lastRecordedRequest`
    var lastRecordedRequest: URLRequest? {
        _recordedRequests.last
    }

    /// Initialize with single scripted result (backward compatibility)
    init(nextData: Data? = nil, nextResponse: URLResponse? = nil, nextError: Error? = nil) {
        self.artificialDelay = 0
        precondition(
            nextData != nil || nextResponse != nil || nextError != nil,
            "MockNetworking.init requires at least one of nextData, nextResponse, or nextError"
        )
        self.scriptedScripts = [(nextData, nextResponse, nextError)]
    }

    /// Initialize with multiple scripted results for testing multi-call scenarios
    init(scriptedData: [Data?], scriptedResponses: [URLResponse?], scriptedErrors: [Error?]) {
        precondition(
            scriptedData.count == scriptedResponses.count
                && scriptedData.count == scriptedErrors.count,
            "MockURLSession arrays must have equal length. Got data: \(scriptedData.count), responses: \(scriptedResponses.count), errors: \(scriptedErrors.count)"
        )
        self.artificialDelay = 0
        self.scriptedScripts = (0..<scriptedData.count).map { index in
            (scriptedData[index], scriptedResponses[index], scriptedErrors[index])
        }
    }

    /// Initialize with an array of tuples to keep scripted triples aligned
    /// Each tuple contains (data, response, error) for one mock call
    init(scriptedCalls: [(Data?, URLResponse?, Error?)]) {
        self.artificialDelay = 0
        self.scriptedScripts = scriptedCalls
    }

    /// Load a new script sequence for the mock session
    /// This allows reusing the same mock instance with different scripted responses
    /// - Parameters:
    ///   - data: Array of Data responses for each call
    ///   - responses: Array of URLResponse responses for each call
    ///   - errors: Array of Error responses for each call
    ///   - keepPosition: If true, preserves the current call index; if false (default), resets the call index to 0
    func loadScript(
        data: [Data?], responses: [URLResponse?], errors: [Error?], keepPosition: Bool = false
    ) {
        precondition(
            data.count == responses.count && data.count == errors.count,
            "MockURLSession arrays must have equal length. Got data: \(data.count), responses: \(responses.count), errors: \(errors.count)"
        )
        scriptedScripts = (0..<data.count).map { index in
            (data[index], responses[index], errors[index])
        }
        if !keepPosition {
            _callCount = 0
        }
    }

    /// Reset the mock session state for reuse between tests
    /// - Parameter keepScript: If true, preserves the current script; if false, clears all scripted arrays
    func reset(keepScript: Bool = true) {
        _callCount = 0
        _recordedRequests.removeAll()
        if !keepScript {
            scriptedScripts.removeAll()
        }
    }

    /// Initialize with a single scripted response
    /// - Parameters:
    ///   - nextData: The data to return for the next request
    ///   - nextResponse: The response to return for the next request
    ///   - nextError: The error to return for the next request (if any)
    ///   - artificialDelay: Artificial delay in nanoseconds to simulate network latency
    init(
        nextData: Data? = nil,
        nextResponse: URLResponse? = nil,
        nextError: Error? = nil,
        artificialDelay: UInt64 = 0
    ) {
        self.artificialDelay = artificialDelay
        precondition(
            nextData != nil || nextResponse != nil || nextError != nil,
            "MockNetworking.init requires at least one of nextData, nextResponse, or nextError"
        )
        scriptedScripts = [(nextData, nextResponse, nextError)]
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let currentCallIndex = _callCount
        _callCount += 1
        _recordedRequests.append(request)

        // Add artificial delay to simulate network latency
        if artificialDelay > 0 {
            try await Task.sleep(nanoseconds: artificialDelay)
        }

        guard currentCallIndex < scriptedScripts.count else {
            throw NetworkError.outOfScriptBounds(call: currentCallIndex + 1)
        }

        let script = scriptedScripts[currentCallIndex]

        // Check for scripted error first
        if let error = script.error {
            throw error
        }

        // Return scripted data and response
        guard let data = script.data, let response = script.response else {
            throw NetworkError.outOfScriptBounds(call: currentCallIndex + 1)
        }

        return (data, response)
    }
}

/// MockEndpoint for testing Endpoint protocol
struct MockEndpoint: Endpoint, Equatable {
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
    var port: Int? = nil
    var fragment: String? = nil
    init() {}

    /// Equatable conformance for test assertions
    static func == (lhs: MockEndpoint, rhs: MockEndpoint) -> Bool {
        return lhs.scheme == rhs.scheme && lhs.host == rhs.host && lhs.path == rhs.path
            && lhs.method == rhs.method && lhs.headers == rhs.headers
            && lhs.queryItems == rhs.queryItems && lhs.contentType == rhs.contentType
            && lhs.timeout == rhs.timeout && lhs.timeoutDuration == rhs.timeoutDuration
            && lhs.body == rhs.body && lhs.port == rhs.port && lhs.fragment == rhs.fragment
    }
}

// MARK: - Duration Timeout Tests
extension MockEndpoint {
    /// Factory method for creating test endpoints with timeout configurations
    /// - Parameters:
    ///   - duration: Duration-based timeout (takes precedence if both are provided)
    ///   - legacy: Legacy TimeInterval-based timeout
    /// - Returns: Configured MockEndpoint
    static func withTimeout(duration: Duration? = nil, legacy: TimeInterval? = nil) -> MockEndpoint
    {
        var endpoint = MockEndpoint()
        endpoint.timeoutDuration = duration
        endpoint.timeout = legacy
        return endpoint
    }

    /// Test endpoint demonstrating Duration-based timeout
    static var withDurationTimeout: MockEndpoint {
        withTimeout(duration: .seconds(45))
    }

    /// Test endpoint demonstrating legacy TimeInterval timeout
    static var withLegacyTimeout: MockEndpoint {
        withTimeout(legacy: 30.0)
    }

    /// Test endpoint with both timeout types (Duration takes precedence)
    static var withBothTimeouts: MockEndpoint {
        withTimeout(duration: .seconds(15), legacy: 60.0)  // 15 seconds (Duration), 60 seconds (legacy, ignored)
    }
}
