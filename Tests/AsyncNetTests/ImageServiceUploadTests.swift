import Foundation
import Testing

@testable import AsyncNet

@Suite("Image Service Upload Tests")
public struct ImageServiceUploadTests {
    @Test public func testUploadImageDataSuccess() async throws {
        // Prepare mock response for successful upload
        let response = HTTPURLResponse(
            url: URL(string: "https://mock.api/upload")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        let mockSession = MockURLSession(nextData: Data(), nextResponse: response)
        let service = ImageService(
            imageCacheCountLimit: 100,
            imageCacheTotalCostLimit: 50 * 1024 * 1024,
            dataCacheCountLimit: 200,
            dataCacheTotalCostLimit: 100 * 1024 * 1024,
            urlSession: mockSession
        )

        let imageData = Data([0xFF, 0xD8, 0xFF, 0xE0])  // JPEG header
        let result = try await service.uploadImageBase64(
            imageData,
            to: URL(string: "https://mock.api/upload")!
        )
        #expect(result == imageData)
    }

    @Test public func testUploadImageDataInvalidURL() async throws {
        let mockSession = MockURLSession(nextData: Data(), nextResponse: nil)
        let service = ImageService(
            imageCacheCountLimit: 100,
            imageCacheTotalCostLimit: 50 * 1024 * 1024,
            dataCacheCountLimit: 200,
            dataCacheTotalCostLimit: 100 * 1024 * 1024,
            urlSession: mockSession
        )

        let imageData = Data([0xFF, 0xD8, 0xFF, 0xE0])  // JPEG header
        do {
            _ = try await service.uploadImageBase64(
                imageData,
                to: URL(string: "not a url")!
            )
            #expect(Bool(false), "Expected invalidEndpoint error but none was thrown")
        } catch let error as NetworkError {
            guard case .invalidEndpoint(let reason) = error else {
                #expect(Bool(false), "Expected invalidEndpoint error but got \(error)")
                return
            }
            #expect(
                reason.contains("Invalid upload URL"),
                "Error reason should mention invalid upload URL")
            #expect(
                reason.contains("not a url"), "Error reason should contain the invalid URL string")
        } catch {
            #expect(Bool(false), "Expected NetworkError but got \(error)")
        }
    }
}
