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
        let imageData = Data([0xFF, 0xD8, 0xFF, 0xE0])  // JPEG header
        let mockSession = MockURLSession(nextData: imageData, nextResponse: response)
        let service = ImageService(
            imageCacheCountLimit: 100,
            imageCacheTotalCostLimit: 50 * 1024 * 1024,
            dataCacheCountLimit: 200,
            dataCacheTotalCostLimit: 100 * 1024 * 1024,
            urlSession: mockSession
        )

        let result = try await service.uploadImageBase64(
            imageData,
            to: URL(string: "https://mock.api/upload")!
        )
        #expect(result == imageData)
    }

    @Test public func testUploadImageDataInvalidURL() async throws {
        let imageData = Data([0xFF, 0xD8, 0xFF, 0xE0])  // JPEG header
        let mockSession = MockURLSession(
            nextData: imageData,
            nextResponse: nil,
            nextError: NetworkError.invalidMockConfiguration(callIndex: 0, missingData: false, missingResponse: true)
        )
        let service = ImageService(
            imageCacheCountLimit: 100,
            imageCacheTotalCostLimit: 50 * 1024 * 1024,
            dataCacheCountLimit: 200,
            dataCacheTotalCostLimit: 100 * 1024 * 1024,
            urlSession: mockSession
        )

        do {
            _ = try await service.uploadImageBase64(
                imageData,
                to: URL(string: "https://mock.api/upload")!
            )
            #expect(Bool(false), "Expected invalidMockConfiguration error but none was thrown")
        } catch let error as NetworkError {
            guard case .invalidMockConfiguration = error else {
                #expect(Bool(false), "Expected invalidMockConfiguration error but got \(error)")
                return
            }
        } catch {
            #expect(Bool(false), "Expected NetworkError but got \(error)")
        }
    }
}
