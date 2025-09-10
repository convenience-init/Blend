import Foundation
import Testing

@testable import Blend

/// Unit tests for MockURLSession functionality
@Suite("Mock URL Session Tests")
public struct MockURLSessionTests {
    private var testURL: URL {
        guard let url = URL(string: "https://mock.api/test") else {
            fatalError("Invalid test URL: https://mock.api/test")
        }
        return url
    }

    @Test public func testBasicFunctionality() async {
        // Basic test to ensure MockURLSession works
        let imageData = Data([0xFF, 0xD8, 0xFF, 0xE0])
        let response = HTTPURLResponse(
            url: testURL,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "image/jpeg"]
        )!

        let mockSession = MockURLSession(
            scriptedData: [imageData],
            scriptedResponses: [response],
            scriptedErrors: [nil]
        )

        do {
            let (data, responseResult) = try await mockSession.data(for: URLRequest(url: testURL))
            #expect(data == imageData)
            #expect((responseResult as? HTTPURLResponse)?.statusCode == 200)

            let callCount = await mockSession.callCount
            #expect(callCount == 1)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}
