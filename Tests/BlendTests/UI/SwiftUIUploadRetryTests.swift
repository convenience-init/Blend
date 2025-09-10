#if canImport(SwiftUI)
    import Foundation
    import Testing
    import SwiftUI
    @testable import Blend

    @Suite("SwiftUI Upload Retry Tests")
    public struct SwiftUIUploadRetryTests {
        @MainActor
        @Test public func testBlendImageModelUploadRetry() async throws {
            // Guard against nil platform image
            let testData = try SwiftUIUploadTestHelpers.getMinimalPNGData()
            guard let platformImage = ImageService.platformImage(from: testData) else {
                throw NetworkError.customError(
                    "Failed to create platform image from test data", details: nil)
            }

            let model = try await createRetryServiceAndModel()

            // Initial upload attempt - should fail with server error
            try await performInitialFailingUpload(model: model, image: platformImage)

            // Successful upload retry - should succeed
            try await performSuccessfulRetryUpload(model: model, image: platformImage)
        }

        /// Creates a service and model configured for retry testing (error then success)
        @MainActor
        private func createRetryServiceAndModel() async throws -> AsyncImageModel {
            guard
                let successResponse = HTTPURLResponse(
                    url: SwiftUIUploadTestHelpers.defaultUploadURL,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )
            else {
                throw NetworkError.customError(
                    "Failed to create HTTPURLResponse for success test", details: nil)
            }
            let errorResponse = HTTPURLResponse(
                url: SwiftUIUploadTestHelpers.defaultUploadURL,
                statusCode: 500,
                httpVersion: nil,
                headerFields: nil
            )

            let mockSession = MockURLSession(scriptedCalls: [
                MockScript(
                    data: Data("Server Error".utf8),
                    response: errorResponse,
                    error: nil
                ),
                MockScript(
                    data: Data("{\"success\": true}".utf8),
                    response: successResponse,
                    error: nil
                ),
            ])
            let service = ImageService(
                imageCacheCountLimit: 100,
                imageCacheTotalCostLimit: 50 * 1024 * 1024,
                dataCacheCountLimit: 200,
                dataCacheTotalCostLimit: 100 * 1024 * 1024,
                urlSession: mockSession
            )
            return AsyncImageModel(imageService: service)
        }

        /// Performs the initial upload attempt that should fail
        @MainActor
        private func performInitialFailingUpload(model: AsyncImageModel, image: PlatformImage)
            async throws
        {
            do {
                _ = try await SwiftUIUploadTestHelpers.performUploadWithTimeout(
                    model: model,
                    image: image,
                    url: SwiftUIUploadTestHelpers.defaultUploadURL,
                    timeoutNanoseconds: 5_000_000_000  // 5 seconds
                )
                throw NetworkError.customError(
                    "Expected initial upload to fail, but it succeeded", details: nil)
            } catch let error as NetworkError {
                #expect(
                    error
                        == NetworkError.serverError(
                            statusCode: 500, data: Data("Server Error".utf8)),
                    "Initial upload should fail with server error")
            }
        }

        /// Performs the successful retry upload
        @MainActor
        private func performSuccessfulRetryUpload(model: AsyncImageModel, image: PlatformImage)
            async throws
        {
            do {
                let successResult = try await SwiftUIUploadTestHelpers.performUploadWithTimeout(
                    model: model,
                    image: image,
                    url: SwiftUIUploadTestHelpers.defaultUploadURL
                )
                #expect(
                    String(data: successResult, encoding: .utf8) == "{\"success\": true}",
                    "Should receive success response")
            } catch {
                Issue.record("Upload failed unexpectedly: \(error)")
            }

            #expect(
                model.isUploading == false, "isUploading should be false after successful upload")
            #expect(model.error == nil, "Error should be nil after successful upload")
        }
    }
#endif
