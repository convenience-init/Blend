import Foundation
import Testing

@testable import AsyncNet

@Suite("Image Service Basic Tests")
public struct ImageServiceBasicTests {
    @Test public func testFetchImageDataSuccess() async throws {
        // Prepare mock image data and response
        let imageData = Data([0xFF, 0xD8, 0xFF, 0xE0])  // JPEG header
        let response = HTTPURLResponse(
            url: URL(string: "https://mock.api/test")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "image/jpeg", "Mime-Type": "image/jpeg"]
        )!
        let mockSession = MockURLSession(nextData: imageData, nextResponse: response)
        let service = ImageService(
            imageCacheCountLimit: 100,
            imageCacheTotalCostLimit: 50 * 1024 * 1024,
            dataCacheCountLimit: 200,
            dataCacheTotalCostLimit: 100 * 1024 * 1024,
            urlSession: mockSession
        )
        let result = try await service.fetchImageData(from: "https://mock.api/test")
        #expect(result == imageData)
    }

    @Test public func testFetchImageDataInvalidURL() async throws {
        let mockSession = MockURLSession(nextData: Data(), nextResponse: nil)
        let service = ImageService(
            imageCacheCountLimit: 100,
            imageCacheTotalCostLimit: 50 * 1024 * 1024,
            dataCacheCountLimit: 200,
            dataCacheTotalCostLimit: 100 * 1024 * 1024,
            urlSession: mockSession
        )

        do {
            _ = try await service.fetchImageData(from: "not a url")
            #expect(Bool(false), "Expected invalidEndpoint error but none was thrown")
        } catch let error as NetworkError {
            guard case .invalidEndpoint(let reason) = error else {
                #expect(Bool(false), "Expected invalidEndpoint error but got \(error)")
                return
            }
            #expect(
                reason.contains("Invalid image URL"),
                "Error reason should mention invalid image URL")
            #expect(
                reason.contains("not a url"), "Error reason should contain the invalid URL string")
        } catch {
            #expect(Bool(false), "Expected NetworkError but got \(error)")
        }
    }
}
