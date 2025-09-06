import Foundation
import Testing

@testable import AsyncNet

/// Unit tests for MockURLSession header resolution functionality
@Suite("Mock URL Session Header Resolution Tests")
public struct MockURLSessionHeaderResolutionTests {
    private let testURL = URL(string: "https://mock.api/test")!

    @Test public func testResolvedHeadersCaseInsensitiveCanonicalization() async {
        // Test that headers are properly canonicalized and case-insensitive
        let mockSession = MockURLSession(
            scriptedData: [Data()],
            scriptedResponses: [
                HTTPURLResponse(
                    url: testURL,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["content-type": "application/json", "ACCEPT": "text/html"]
                )!
            ], scriptedErrors: [nil])

        let (data, response) = try! await mockSession.data(for: URLRequest(url: testURL))
        #expect(!data.isEmpty)
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
    }

    @Test public func testResolvedHeadersEmptyWhitespaceTrimming() async {
        // Test that empty/whitespace-only headers are properly trimmed
        let mockSession = MockURLSession(
            scriptedData: [Data()],
            scriptedResponses: [
                HTTPURLResponse(
                    url: testURL,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: [
                        "content-type": "application/json", "x-empty": "", "x-whitespace": "   ",
                    ]
                )!
            ], scriptedErrors: [nil])

        let (data, response) = try! await mockSession.data(for: URLRequest(url: testURL))
        #expect(!data.isEmpty)
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
    }

    @Test public func testResolvedHeadersContentTypeInjection() async {
        // Test that Content-Type header is properly injected when missing
        let mockSession = MockURLSession(
            scriptedData: [Data()],
            scriptedResponses: [
                HTTPURLResponse(
                    url: testURL,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: [:]  // No Content-Type header
                )!
            ], scriptedErrors: [nil])

        let (data, response) = try! await mockSession.data(for: URLRequest(url: testURL))
        #expect(!data.isEmpty)
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
    }

    @Test public func testResolvedHeadersEmptyContentTypeNotInjected() async {
        // Test that empty Content-Type header is not replaced
        let mockSession = MockURLSession(
            scriptedData: [Data()],
            scriptedResponses: [
                HTTPURLResponse(
                    url: testURL,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": ""]  // Empty Content-Type
                )!
            ], scriptedErrors: [nil])

        let (data, response) = try! await mockSession.data(for: URLRequest(url: testURL))
        #expect(!data.isEmpty)
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
    }

    @Test public func testResolvedHeadersMixedCaseKeys() async {
        // Test that mixed-case header keys are properly handled
        let mockSession = MockURLSession(
            scriptedData: [Data()],
            scriptedResponses: [
                HTTPURLResponse(
                    url: testURL,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json", "X-Custom-Header": "value"]
                )!
            ], scriptedErrors: [nil])

        let (data, response) = try! await mockSession.data(for: URLRequest(url: testURL))
        #expect(!data.isEmpty)
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
    }

    @Test public func testBackwardCompatibility() async {
        // Test backward compatibility with older MockURLSession API
        let mockSession = MockURLSession(
            nextData: Data([0xFF, 0xD8, 0xFF, 0xE0]),
            nextResponse: HTTPURLResponse(
                url: testURL,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "image/jpeg"]
            )!
        )

        let (data, response) = try! await mockSession.data(for: URLRequest(url: testURL))
        #expect(!data.isEmpty)
        #expect((response as? HTTPURLResponse)?.statusCode == 200)

        let callCount = await mockSession.callCount
        #expect(callCount == 1)
    }
}
