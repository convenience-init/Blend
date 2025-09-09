#if canImport(SwiftUI)
    import Foundation
    import Testing
    import SwiftUI
    @testable import Blend

    @Suite("SwiftUI Upload Basic Tests")
    public struct SwiftUIUploadBasicTests {
        @MainActor
        @Test public func testAsyncNetImageModelErrorStateClearedAfterSuccess() async throws {
            // Guard against nil platform image
            let testData = try SwiftUIUploadTestHelpers.getMinimalPNGData()
            guard let platformImage = ImageService.platformImage(from: testData) else {
                throw NetworkError.customError(
                    "Failed to create platform image from test data", details: nil)
            }

            // First, trigger an error state
            let errorModel = try await createErrorServiceAndModel()
            try await performErrorUpload(model: errorModel, image: platformImage)

            // Now test that error state is cleared after a successful upload
            let successModel = try await createSuccessServiceAndModel()
            try await performSuccessUpload(model: successModel, image: platformImage)
        }

        /// Creates a service and model configured to return upload errors
        @MainActor
        private func createErrorServiceAndModel() async throws -> AsyncImageModel {
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
            let errorSession = MockURLSession(
                nextData: Data("Server Error".utf8), nextResponse: errorResponse)
            let errorService = ImageService(
                imageCacheCountLimit: 100,
                imageCacheTotalCostLimit: 50 * 1024 * 1024,
                dataCacheCountLimit: 200,
                dataCacheTotalCostLimit: 100 * 1024 * 1024,
                urlSession: errorSession
            )
            return AsyncImageModel(imageService: errorService)
        }

        /// Creates a service and model configured to return successful uploads
        @MainActor
        private func createSuccessServiceAndModel() async throws -> AsyncImageModel {
            guard
                let successResponse = HTTPURLResponse(
                    url: SwiftUIUploadTestHelpers.defaultUploadURL,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )
            else {
                Issue.record("Failed to create HTTPURLResponse for successful upload test")
                throw NetworkError.customError(
                    "Failed to create success response", details: nil)
            }
            let successSession = MockURLSession(
                nextData: Data("{\"success\": true}".utf8), nextResponse: successResponse)
            let successService = ImageService(
                imageCacheCountLimit: 100,
                imageCacheTotalCostLimit: 50 * 1024 * 1024,
                dataCacheCountLimit: 200,
                dataCacheTotalCostLimit: 100 * 1024 * 1024,
                urlSession: successSession
            )
            return AsyncImageModel(imageService: successService)
        }

        /// Performs an upload that is expected to fail
        @MainActor
        private func performErrorUpload(model: AsyncImageModel, image: PlatformImage) async throws {
            do {
                _ = try await SwiftUIUploadTestHelpers.performUploadWithTimeout(
                    model: model,
                    image: image,
                    url: SwiftUIUploadTestHelpers.defaultUploadURL
                )
                throw NetworkError.customError(
                    "Expected upload to fail, but it succeeded", details: nil)
            } catch {
                // Expected error occurred - test passes
            }
        }

        /// Performs an upload that is expected to succeed and clear error state
        @MainActor
        private func performSuccessUpload(model: AsyncImageModel, image: PlatformImage) async throws {
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
                model.isUploading == false,
                "isUploading should be false after successful upload")
            #expect(model.error == nil, "Error should be nil after successful upload")
        }
    }
#endif
