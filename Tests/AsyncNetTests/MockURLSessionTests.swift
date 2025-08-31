import Foundation
import Testing
@testable import AsyncNet

/// Unit tests for MockURLSession functionality
@Suite("Mock URL Session Tests")
struct MockURLSessionTests {
    @Test func testMultiCallScripting() async {
        // Test scenario: first call fails with network error, second call succeeds
        let imageData = Data([0xFF, 0xD8, 0xFF])
        let successResponse = HTTPURLResponse(
            url: URL(string: "https://mock.api/test")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "image/jpeg"]
        )!

        let mockSession = MockURLSession(
            scriptedData: [nil, imageData], // First call: no data, Second call: success data
            scriptedResponses: [nil, successResponse], // First call: no response, Second call: success response
            scriptedErrors: [NetworkError.networkUnavailable, nil] // First call: error, Second call: no error
        )

        // Create single reused request
        let request = URLRequest(url: URL(string: "https://mock.api/test")!)

        // First call should fail
        await #expect(throws: NetworkError.networkUnavailable) {
            try await mockSession.data(for: request)
        }

        // Second call should succeed
        do {
            let (data, response) = try await mockSession.data(for: request)
            #expect(data == imageData)
            #expect((response as? HTTPURLResponse)?.statusCode == 200)
        } catch {
            #expect(Bool(false), "Second call should have succeeded")
        }

        // Verify call count
        let callCount = await mockSession.callCount
        #expect(callCount == 2)
    }

    @Test func testOutOfBoundsHandling() async {
        let imageData = Data([0xFF, 0xD8, 0xFF])
        let response = HTTPURLResponse(
            url: URL(string: "https://mock.api/test")!,
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
            let (data1, _) = try await mockSession.data(for: URLRequest(url: URL(string: "https://mock.api/test")!))
            #expect(data1 == imageData)
        } catch {
            #expect(Bool(false), "First call should have succeeded")
        }

        // Second call should fail with descriptive error
        do {
            _ = try await mockSession.data(for: URLRequest(url: URL(string: "https://mock.api/test")!))
            #expect(Bool(false), "Second call should have failed due to out-of-bounds")
        } catch {
            if let networkError = error as? NetworkError {
                switch networkError {
                case .outOfScriptBounds(let call):
                    #expect(call == 2)
                default:
                    #expect(Bool(false), "Expected outOfScriptBounds error for out-of-bounds")
                }
            } else {
                #expect(Bool(false), "Expected NetworkError but got: \(error)")
            }
        }

        let callCount = await mockSession.callCount
        #expect(callCount == 2)
    }

    @Test func testBackwardCompatibility() async {
        // Test that the old single-value initializer still works
        let imageData = Data([0xFF, 0xD8, 0xFF])
        let response = HTTPURLResponse(
            url: URL(string: "https://mock.api/test")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "image/jpeg"]
        )!

        let mockSession = MockURLSession(nextData: imageData, nextResponse: response, nextError: nil)

        do {
            let (data, responseResult) = try await mockSession.data(for: URLRequest(url: URL(string: "https://mock.api/test")!))
            #expect(data == imageData)
            #expect((responseResult as? HTTPURLResponse)?.statusCode == 200)
        } catch {
            #expect(Bool(false), "Call should have succeeded")
        }

        let callCount = await mockSession.callCount
        #expect(callCount == 1)
    }

    @Test func testResolvedHeadersNormalization() async {
        // Test content-type canonicalization and trimming
        var endpoint = MockEndpoint()
        
        // Test 1: Case-insensitive content-type canonicalization
        endpoint.headers = ["content-type": "text/plain", "Authorization": "Bearer token"]
        endpoint.contentType = "application/json" // Should be ignored since content-type exists
        
        var resolved = endpoint.resolvedHeaders
        #expect(resolved?["Content-Type"] == "text/plain", "Should canonicalize content-type to Content-Type")
        #expect(resolved?["Authorization"] == "Bearer token")
        #expect(resolved?.count == 2)
        
        // Test 2: Empty/whitespace header trimming
        endpoint.headers = ["content-type": "  ", "X-Empty": "", "X-Valid": "value"]
        endpoint.contentType = nil
        
        resolved = endpoint.resolvedHeaders
        #expect(resolved?["X-Valid"] == "value", "Should keep valid headers")
        #expect(resolved?.count == 1, "Should drop empty/whitespace headers")
        
        // Test 3: contentType injection when no existing content-type
        endpoint.headers = ["Authorization": "Bearer token"]
        endpoint.contentType = "application/json"
        
        resolved = endpoint.resolvedHeaders
        #expect(resolved?["Content-Type"] == "application/json", "Should inject contentType as Content-Type")
        #expect(resolved?["Authorization"] == "Bearer token")
        #expect(resolved?.count == 2)
        
        // Test 4: Empty contentType should not be injected
        endpoint.headers = ["Authorization": "Bearer token"]
        endpoint.contentType = "   " // Whitespace only
        
        resolved = endpoint.resolvedHeaders
        #expect(resolved?["Content-Type"] == nil, "Should not inject empty/whitespace contentType")
        #expect(resolved?["Authorization"] == "Bearer token")
        #expect(resolved?.count == 1)
        
        // Test 5: Mixed case content-type keys
        endpoint.headers = ["CONTENT-TYPE": "text/html", "content-type": "application/xml"] // Last one wins in dict
        endpoint.contentType = "application/json" // Should be ignored
        
        resolved = endpoint.resolvedHeaders
        #expect(resolved?["Content-Type"] == "application/xml", "Should handle mixed case and canonicalize")
        #expect(resolved?.count == 1)
    }
}