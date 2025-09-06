import Foundation
import Testing

@testable import AsyncNet

/// Unit tests for MockURLSession error handling
@Suite("Mock URL Session Error Tests")
public struct MockURLSessionErrorTests {
    private let testURL = URL(string: "https://mock.api/test")!

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
}
