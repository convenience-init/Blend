import Foundation
import AsyncNet

/// Mock networking utilities for testing AsyncNet components
public actor MockURLSession: URLSessionProtocol {
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

    /// Check if all scripted responses have been consumed
    /// Returns true if callCount >= scriptedScripts.count, indicating all scripts were used
    var allScriptsConsumed: Bool {
        _callCount >= scriptedScripts.count
    }

    /// Initialize with multiple scripted results for testing multi-call scenarios
    init(scriptedData: [Data?], scriptedResponses: [URLResponse?], scriptedErrors: [Error?]) {
        precondition(
            !scriptedData.isEmpty,
            "MockURLSession arrays must not be empty"
        )
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
        precondition(
            !scriptedCalls.isEmpty,
            "MockURLSession scriptedCalls must not be empty"
        )
        self.artificialDelay = 0
        self.scriptedScripts = scriptedCalls
    }

    /// Initialize with a single scripted response that can be repeated for multiple calls
    /// - Parameters:
    ///   - nextData: The data to return for requests
    ///   - nextResponse: The response to return for requests
    ///   - nextError: The error to return for requests (if any)
    ///   - maxCalls: Maximum number of calls to handle (defaults to 4 to handle retries)
    ///   - artificialDelay: Artificial delay in nanoseconds to simulate network latency
    init(
        nextData: Data? = nil,
        nextResponse: URLResponse? = nil,
        nextError: Error? = nil,
        maxCalls: Int = 4,
        artificialDelay: UInt64 = 0
    ) {
        self.artificialDelay = artificialDelay
        precondition(maxCalls > 0, "maxCalls must be a positive nonzero integer, got \(maxCalls)")
        precondition(
            nextData != nil || nextResponse != nil || nextError != nil,
            "MockURLSession.init requires at least one of nextData, nextResponse, or nextError"
        )
        // Create array using Array(repeating:count:) to preserve types and simplify
        scriptedScripts = Array(repeating: (nextData, nextResponse, nextError), count: maxCalls)
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
            !data.isEmpty,
            "MockURLSession arrays must not be empty"
        )
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

    public func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let currentCallIndex = _callCount
        _callCount += 1
        _recordedRequests.append(request)

        // Capture immutable state before suspension to prevent race conditions
        let delay = artificialDelay
        let script: (data: Data?, response: URLResponse?, error: Error?)
        if currentCallIndex < scriptedScripts.count {
            script = scriptedScripts[currentCallIndex]
        } else {
            script = (nil, nil, NetworkError.outOfScriptBounds(call: currentCallIndex))
        }

        // Add artificial delay to simulate network latency
        if delay > 0 {
            try await Task.sleep(nanoseconds: delay)
        }

        // Use captured script instead of reading from actor state after suspension
        if let error = script.error {
            throw error
        }

        // Return scripted data and response
        guard let data = script.data, let response = script.response else {
            let missingData = script.data == nil
            let missingResponse = script.response == nil
            throw NetworkError.invalidMockConfiguration(
                callIndex: currentCallIndex,
                missingData: missingData,
                missingResponse: missingResponse
            )
        }

        // Ensure the response is returned as the correct type
        if let httpResponse = response as? HTTPURLResponse {
            return (data, httpResponse)
        } else {
            return (data, response)
        }
    }
}

/// MockEndpoint for testing Endpoint protocol
struct MockEndpoint: Endpoint, Equatable {
    /// Properties are immutable for thread-safety and Swift 6 concurrency compliance.
    /// Use factory methods or initializers to create configured instances for testing.
    let scheme: URLScheme
    let host: String
    let path: String
    let method: RequestMethod
    let headers: [String: String]?
    let queryItems: [URLQueryItem]?
    let contentType: String?
    let timeout: TimeInterval?
    let timeoutDuration: Duration?
    let body: Data?
    let port: Int?
    let fragment: String?

    init(
        scheme: URLScheme = .https,
        host: String = "mock.api",
        path: String = "/test",
        method: RequestMethod = .get,
        headers: [String: String]? = nil,
        queryItems: [URLQueryItem]? = nil,
        contentType: String? = "application/json",
        timeout: TimeInterval? = nil,
        timeoutDuration: Duration? = nil,
        body: Data? = nil,
        port: Int? = nil,
        fragment: String? = nil
    ) {
        self.scheme = scheme
        self.host = host
        self.path = path
        self.method = method
        self.headers = headers
        self.queryItems = queryItems
        self.contentType = contentType
        self.timeout = timeout
        self.timeoutDuration = timeoutDuration
        self.body = body
        self.port = port
        self.fragment = fragment
    }

    /// Convenience initializer for default test configuration
    init() {
        self.init(
            scheme: .https,
            host: "mock.api",
            path: "/test",
            method: .get,
            headers: nil,
            queryItems: nil,
            contentType: "application/json",
            timeout: nil,
            timeoutDuration: nil,
            body: nil,
            port: nil,
            fragment: nil
        )
    }

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
        return MockEndpoint(timeout: legacy, timeoutDuration: duration)
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
