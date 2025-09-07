import Foundation
import Testing

@testable import Blend

/// Unit tests for MockURLSession error precedence functionality
@Suite("Mock URL Session Error Precedence Tests")
public struct MockURLSessionErrorPrecedenceTests {
    private var testURL: URL {
        guard let url = URL(string: "https://mock.api/test") else {
            fatalError("Invalid test URL: https://mock.api/test")
        }
        return url
    }

    @Test public func testErrorPrecedenceOverData() async {
        // Test that scripted errors take precedence over scripted data/responses
        let imageData = Data([0xFF, 0xD8, 0xFF, 0xE0])
        let response = HTTPURLResponse(
            url: testURL,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "image/jpeg"]
        )!

        let mockSession = MockURLSession(
            scriptedData: [imageData],  // Valid data present
            scriptedResponses: [response],  // Valid response present
            scriptedErrors: [NetworkError.networkUnavailable]  // But error should take precedence
        )

        // Call should fail with the scripted error, not return the data/response
        await #expect(throws: NetworkError.networkUnavailable) {
            try await mockSession.data(for: URLRequest(url: testURL))
        }

        let callCount = await mockSession.callCount
        #expect(callCount == 1)
    }

    @Test public func testMultiCallScripting() async {
        // Test scenario: first call fails with network error, second call succeeds
        let imageData = Data([0xFF, 0xD8, 0xFF, 0xE0])
        let successResponse = HTTPURLResponse(
            url: testURL,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "image/jpeg"]
        )!

        let mockSession = MockURLSession(
            scriptedData: [nil, imageData],  // First call: no data, Second call: success data
            scriptedResponses: [nil, successResponse],  // First call: no response, Second call: success response
            scriptedErrors: [NetworkError.networkUnavailable, nil]  // First call: error, Second call: no error
        )

        // First call should fail
        await #expect(throws: NetworkError.networkUnavailable) {
            try await mockSession.data(for: URLRequest(url: testURL))
        }

        // Second call should succeed
        do {
            let (data, response) = try await mockSession.data(for: URLRequest(url: testURL))
            #expect(data == imageData)
            #expect((response as? HTTPURLResponse)?.statusCode == 200)
        } catch {
            Issue.record("Unexpected error on second call: \(error)")
        }

        let callCount = await mockSession.callCount
        #expect(callCount == 2)
    }

    @Test public func testOutOfBoundsHandling() async {
        // Test that out-of-bounds calls return appropriate error
        let mockSession = MockURLSession(
            scriptedData: [], scriptedResponses: [], scriptedErrors: [])

        await #expect(throws: NetworkError.outOfScriptBounds(call: 0)) {
            try await mockSession.data(for: URLRequest(url: testURL))
        }
    }

    @Test public func testErrorPrecedenceWithCustomError() async {
        // Test that custom errors take precedence over data/responses
        let imageData = Data([0xFF, 0xD8, 0xFF, 0xE0])
        let response = HTTPURLResponse(
            url: testURL,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "image/jpeg"]
        )!

        let customError = NetworkError.customError(message: "Custom test error", details: nil)
        let mockSession = MockURLSession(
            scriptedData: [imageData],
            scriptedResponses: [response],
            scriptedErrors: [customError]
        )

        await #expect(throws: customError) {
            try await mockSession.data(for: URLRequest(url: testURL))
        }
    }

    @Test public func testErrorPrecedenceInMultiCallScenario() async {
        // Test error precedence in a multi-call scenario with mixed success/error
        let imageData = Data([0xFF, 0xD8, 0xFF, 0xE0])
        let successResponse = HTTPURLResponse(
            url: testURL,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "image/jpeg"]
        )!

        let mockSession = MockURLSession(
            scriptedData: [nil, imageData],
            scriptedResponses: [nil, successResponse],
            scriptedErrors: [NetworkError.networkUnavailable, nil]
        )

        // First call should fail due to error precedence
        await #expect(throws: NetworkError.networkUnavailable) {
            try await mockSession.data(for: URLRequest(url: testURL))
        }

        // Second call should succeed
        do {
            let (data, response) = try await mockSession.data(for: URLRequest(url: testURL))
            #expect(data == imageData)
            #expect((response as? HTTPURLResponse)?.statusCode == 200)
        } catch {
            Issue.record("Unexpected error on second call: \(error)")
        }
    }
}
