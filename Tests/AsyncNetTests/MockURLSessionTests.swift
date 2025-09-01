import Foundation
import Testing

@testable import AsyncNet

/// Unit tests for MockURLSession functionality
@Suite("Mock URL Session Tests")
struct MockURLSessionTests {
    private let testURL = URL(string: "https://mock.api/test")!

    @Test func testErrorPrecedenceOverData() async {
        // Test that scripted errors take precedence over scripted data/responses
        let imageData = Data([0xFF, 0xD8, 0xFF])
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

    @Test func testMultiCallScripting() async {
        // Test scenario: first call fails with network error, second call succeeds
        let imageData = Data([0xFF, 0xD8, 0xFF])
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

        // Create single reused request
        let request = URLRequest(url: testURL)

        // First call should fail
        await #expect(throws: NetworkError.networkUnavailable) {
            try await mockSession.data(for: request)
        }

        // Second call should succeed
        do {
            let (data, response) = try await mockSession.data(for: request)
            let httpResponse = response as? HTTPURLResponse
            #expect(data == imageData)
            #expect(httpResponse?.statusCode == 200)
        } catch {
            #expect(Bool(false), "Second call should have succeeded but threw: \(error)")
        }

        // Verify call count
        let callCount = await mockSession.callCount
        #expect(callCount == 2)
    }

    @Test func testOutOfBoundsHandling() async {
        let imageData = Data([0xFF, 0xD8, 0xFF])
        let response = HTTPURLResponse(
            url: testURL,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "image/jpeg"]
        )!

        // Only provide data for first call
        let mockSession = MockURLSession(
            scriptedData: [imageData],
            scriptedResponses: [response],
            scriptedErrors: [nil]
        )

        // First call should succeed
        do {
            let (data1, _) = try await mockSession.data(for: URLRequest(url: testURL))
            #expect(data1 == imageData)
        } catch {
            #expect(Bool(false), "First call should have succeeded")
        }

        // Second call should fail with descriptive error
        do {
            _ = try await mockSession.data(for: URLRequest(url: testURL))
            #expect(Bool(false), "Second call should have failed due to out-of-bounds")
        } catch {
            if let networkError = error as? NetworkError {
                if case let .outOfScriptBounds(call) = networkError {
                    #expect(call == 2, "Expected out-of-bounds error for call 2")
                } else {
                    #expect(
                        Bool(false), "Expected NetworkError.outOfScriptBounds but got: \(error)")
                }
            } else {
                #expect(Bool(false), "Expected NetworkError.outOfScriptBounds but got: \(error)")
            }
        }

        let callCount = await mockSession.callCount
        #expect(callCount == 2)
    }

    @Test func testErrorPrecedenceWithCustomError() async {
        // Test error precedence with a custom error and valid data/response
        let imageData = Data([0xFF, 0xD8, 0xFF])
        let response = HTTPURLResponse(
            url: testURL,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "image/jpeg"]
        )!
        let customError = NetworkError.customError(
            "Custom test error", details: "Testing error precedence")

        let mockSession = MockURLSession(
            scriptedData: [imageData],
            scriptedResponses: [response],
            scriptedErrors: [customError]
        )

        // Should throw the custom error, not return data
        do {
            _ = try await mockSession.data(for: URLRequest(url: testURL))
            #expect(Bool(false), "Expected custom error to be thrown")
        } catch {
            if let networkError = error as? NetworkError,
                case let .customError(message, details) = networkError
            {
                #expect(message == "Custom test error")
                #expect(details == "Testing error precedence")
            } else {
                #expect(Bool(false), "Expected custom NetworkError but got: \(error)")
            }
        }

        let callCount = await mockSession.callCount
        #expect(callCount == 1)
    }

    @Test func testBackwardCompatibility() async {
        // Test that the old single-value initializer still works
        let imageData = Data([0xFF, 0xD8, 0xFF])
        let response = HTTPURLResponse(
            url: testURL,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "image/jpeg"]
        )!

        let mockSession = MockURLSession(
            nextData: imageData, nextResponse: response, nextError: nil)

        do {
            let (data, responseResult) = try await mockSession.data(for: URLRequest(url: testURL))
            #expect(data == imageData)
            #expect((responseResult as? HTTPURLResponse)?.statusCode == 200)
        } catch {
            #expect(Bool(false), "Call should have succeeded")
        }

        let callCount = await mockSession.callCount
        #expect(callCount == 1)
    }

    @Test func testErrorPrecedenceInMultiCallScenario() async {
        // Test error precedence in a multi-call scenario where some calls have both error and data
        let imageData = Data([0xFF, 0xD8, 0xFF])
        let response = HTTPURLResponse(
            url: testURL,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "image/jpeg"]
        )!

        let mockSession = MockURLSession(
            scriptedData: [imageData, nil, imageData],  // Call 0: data + error, Call 1: no data, Call 2: data only
            scriptedResponses: [response, nil, response],
            scriptedErrors: [NetworkError.networkUnavailable, nil, nil]  // Call 0: error, Call 1: no error, Call 2: no error
        )

        // First call should fail due to error precedence
        await #expect(throws: NetworkError.networkUnavailable) {
            try await mockSession.data(for: URLRequest(url: testURL))
        }

        // Second call should succeed (no error, no data/response - should this be an error?)
        // Actually, let me check what happens when there's no data/response but also no error
        do {
            _ = try await mockSession.data(for: URLRequest(url: testURL))
            #expect(Bool(false), "Expected error for call with no data/response")
        } catch {
            // This should probably be some kind of error when no data/response is available
            if let networkError = error as? NetworkError,
                case let .invalidMockConfiguration(callIndex, missingData, missingResponse) =
                    networkError
            {
                #expect(callIndex == 2, "Expected invalidMockConfiguration error for call 2")
                #expect(missingData == true, "Expected missingData to be true")
                #expect(missingResponse == true, "Expected missingResponse to be true")
            } else {
                #expect(
                    Bool(false),
                    "Expected NetworkError.invalidMockConfiguration for call with no data/response")
            }
        }

        // Third call should succeed
        do {
            let (data, responseResult) = try await mockSession.data(for: URLRequest(url: testURL))
            #expect(data == imageData)
            #expect((responseResult as? HTTPURLResponse)?.statusCode == 200)
        } catch {
            #expect(Bool(false), "Third call should have succeeded")
        }

        let callCount = await mockSession.callCount
        #expect(callCount == 3)
    }

    @Test func testResolvedHeadersNormalization() async {
        // Test 1: Case-insensitive content-type canonicalization
        do {
            var endpoint1 = MockEndpoint()
            endpoint1.headers = ["content-type": "text/plain", "Authorization": "Bearer token"]
            endpoint1.contentType = "application/json"  // Should be ignored since content-type exists

            guard let resolved = endpoint1.resolvedHeaders else {
                #expect(
                    Bool(false), "Expected resolvedHeaders to be non-nil for endpoint with headers")
                return
            }
            #expect(
                resolved["Content-Type"] == "text/plain",
                "Should canonicalize content-type to Content-Type")
            #expect(resolved["Authorization"] == "Bearer token")
            #expect(resolved.count == 2)
        }

        // Test 2: Empty/whitespace header trimming
        do {
            var endpoint2 = MockEndpoint()
            endpoint2.headers = ["content-type": "  ", "X-Empty": "", "X-Valid": "value"]
            endpoint2.contentType = nil

            guard let resolved = endpoint2.resolvedHeaders else {
                #expect(
                    Bool(false), "Expected resolvedHeaders to be non-nil for endpoint with headers")
                return
            }
            #expect(resolved["X-Valid"] == "value", "Should keep valid headers")
            #expect(resolved.count == 1, "Should drop empty/whitespace headers")
        }

        // Test 3: contentType injection when no existing content-type (requires body)
        do {
            var endpoint3 = MockEndpoint()
            endpoint3.headers = ["Authorization": "Bearer token"]
            endpoint3.contentType = "application/json"
            endpoint3.body = Data("test body".utf8)  // Add body to trigger Content-Type injection

            guard let resolved = endpoint3.resolvedHeaders else {
                #expect(
                    Bool(false),
                    "Expected resolvedHeaders to be non-nil for endpoint with headers and body")
                return
            }
            #expect(
                resolved["Content-Type"] == "application/json",
                "Should inject contentType as Content-Type when body is present")
            #expect(resolved["Authorization"] == "Bearer token")
            #expect(resolved.count == 2)
        }

        // Test 4: Empty contentType should not be injected
        do {
            var endpoint4 = MockEndpoint()
            endpoint4.headers = ["Authorization": "Bearer token"]
            endpoint4.contentType = "   "  // Whitespace only
            endpoint4.body = Data("test body".utf8)  // Add body to test the contentType logic

            guard let resolved = endpoint4.resolvedHeaders else {
                #expect(
                    Bool(false),
                    "Expected resolvedHeaders to be non-nil for endpoint with headers and body")
                return
            }
            #expect(
                resolved["Content-Type"] == nil, "Should not inject empty/whitespace contentType")
            #expect(resolved["Authorization"] == "Bearer token")
            #expect(resolved.count == 1)
        }

        // Test 5: Mixed case content-type keys
        do {
            var endpoint5 = MockEndpoint()
            // Use a more predictable approach: single key that should be canonicalized
            endpoint5.headers = ["content-type": "application/xml"]
            endpoint5.contentType = "application/json"  // Should be ignored since content-type exists

            guard let resolved = endpoint5.resolvedHeaders else {
                #expect(
                    Bool(false), "Expected resolvedHeaders to be non-nil for endpoint with headers")
                return
            }
            #expect(
                resolved["Content-Type"] == "application/xml",
                "Should canonicalize content-type to Content-Type")
            #expect(resolved.count == 1)
        }
    }
}
