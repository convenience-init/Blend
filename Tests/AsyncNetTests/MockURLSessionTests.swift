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

        // First call should fail
        do {
            _ = try await mockSession.data(for: URLRequest(url: URL(string: "https://mock.api/test")!))
            #expect(Bool(false), "First call should have failed")
        } catch {
            if let networkError = error as? NetworkError {
                #expect(networkError == .networkUnavailable)
            } else {
                #expect(Bool(false), "Expected NetworkError but got: \(error)")
            }
        }

        // Second call should succeed
        do {
            let (data, response) = try await mockSession.data(for: URLRequest(url: URL(string: "https://mock.api/test")!))
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
                case .custom(let message, let details):
                    #expect(message.contains("No scripted response available"))
                    #expect(details?.contains("Call count: 2") == true)
                default:
                    #expect(Bool(false), "Expected custom error for out-of-bounds")
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
}