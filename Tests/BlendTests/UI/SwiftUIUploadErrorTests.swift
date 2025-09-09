#if canImport(SwiftUI)

    import Foundation
    import Testing
    import SwiftUI
    @testable import Blend

    @Suite("SwiftUI Upload Error Tests")
    public struct SwiftUIUploadErrorTests {

        @MainActor
        @Test public func testAsyncNetImageModelUploadErrorState() async throws {
            // Create a mock session that returns an upload error
            guard
                let errorResponse = HTTPURLResponse(
                    url: SwiftUIUploadTestHelpers.defaultUploadURL,
                    statusCode: 500,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )
            else {
                throw NetworkError.customError(
                    "Failed to create HTTPURLResponse for upload error test - header fields may be invalid",
                    details: nil)
            }
            let mockSession = MockURLSession(
                nextData: Data("Server Error".utf8), nextResponse: errorResponse)
            let service = ImageService(
                imageCacheCountLimit: 100,
                imageCacheTotalCostLimit: 50 * 1024 * 1024,
                dataCacheCountLimit: 200,
                dataCacheTotalCostLimit: 100 * 1024 * 1024,
                urlSession: mockSession
            )
            let model = AsyncImageModel(imageService: service)

            // Guard against nil platform image
            let testData = try SwiftUIUploadTestHelpers.getMinimalPNGData()
            guard let platformImage = ImageService.platformImage(from: testData) else {
                throw NetworkError.customError(
                    "Failed to create platform image from test data", details: nil)
            }

            // Test the upload by capturing the error through try/catch
            do {
                _ = try await model.uploadImage(
                    platformImage, to: SwiftUIUploadTestHelpers.defaultUploadURL,
                    uploadType: .base64,
                    configuration: UploadConfiguration()
                )
                Issue.record("Expected upload to fail but it succeeded")
            } catch {
                // Assert the error is the expected type
                if let networkError = error as? NetworkError {
                    if case let .serverError(statusCode, _) = networkError {
                        #expect(statusCode == 500, "Should receive HTTP 500 error")
                    } else {
                        Issue.record("Expected server error but got: \(networkError)")
                    }
                } else {
                    Issue.record("Expected NetworkError but got: \(error)")
                }
            }
            
            // Check that the model captured the error after the operation
            #expect(model.hasError, "Model should have error state after failed upload")
            #expect(model.error != nil, "Model should have captured an error")
        }
    }
#endif
