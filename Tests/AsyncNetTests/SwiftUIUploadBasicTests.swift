#if canImport(SwiftUI)
    import Foundation
    import Testing
    import SwiftUI
    @testable import AsyncNet

    /// Actor to coordinate continuation resumption and prevent race conditions
    /// between timeout tasks and upload callbacks
    private actor CoordinationActor {
        private var hasResumed = false

        /// Attempts to resume the continuation. Returns true if this call should
        /// actually resume (i.e., it's the first call), false if already resumed.
        func tryResume() -> Bool {
            if hasResumed {
                return false
            }
            hasResumed = true
            return true
        }
    }

    @Suite("SwiftUI Upload Basic Tests")
    public struct SwiftUIUploadBasicTests {
        private static let minimalPNGBase64 =
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAACklEQVR4nGMAAQAABQABDQottAAAAABJRU5ErkJggg=="

        /// Decode the minimal PNG Base64 string into Data
        /// - Returns: The decoded Data
        /// - Throws: NetworkError if decoding fails
        private static func decodeMinimalPNGBase64() throws -> Data {
            guard let data = Data(base64Encoded: minimalPNGBase64) else {
                throw NetworkError.customError(
                    "Failed to decode minimalPNGBase64 - invalid Base64 string", details: nil)
            }
            return data
        }

        /// Test-friendly version that throws instead of crashing
        public static func getMinimalPNGData() throws -> Data {
            try decodeMinimalPNGBase64()
        }

        private static let defaultUploadURL = URL(string: "https://mock.api/upload")!

        @MainActor
        @Test public func testAsyncNetImageModelErrorStateClearedAfterSuccess() async throws {
            // Guard against nil platform image
            let testData = try Self.getMinimalPNGData()
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
                    url: Self.defaultUploadURL,
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
                    url: Self.defaultUploadURL,
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
            let errorResult = try await performUploadWithTimeout(
                model: model,
                image: image,
                url: Self.defaultUploadURL
            )

            // Verify error occurred
            switch errorResult {
            case .failure:
                break  // Expected error
            case .success:
                throw NetworkError.customError(
                    "Expected upload to fail, but it succeeded", details: nil)
            }
        }

        /// Performs an upload that is expected to succeed and clear error state
        @MainActor
        private func performSuccessUpload(model: AsyncImageModel, image: PlatformImage) async throws {
            let successResult = try await performUploadWithTimeout(
                model: model,
                image: image,
                url: Self.defaultUploadURL
            )

            // Assert the successful result
            switch successResult {
            case .success(let data):
                #expect(
                    String(data: data, encoding: .utf8) == "{\"success\": true}",
                    "Should receive success response")
            case .failure(let error):
                Issue.record("Upload failed unexpectedly: \(error)")
            }

            #expect(
                model.isUploading == false,
                "isUploading should be false after successful upload")
            #expect(model.error == nil, "Error should be nil after successful upload")
        }

        /// Helper method to perform upload with timeout coordination using Swift 6 concurrency patterns
        /// - Parameters:
        ///   - model: The AsyncImageModel to perform upload on
        ///   - image: The platform image to upload
        ///   - url: The upload URL
        ///   - timeoutNanoseconds: Timeout in nanoseconds (default: 5 seconds)
        ///   - Returns: Result containing either the response data or a NetworkError
        @MainActor
        private func performUploadWithTimeout(
            model: AsyncImageModel,
            image: PlatformImage,
            url: URL,
            timeoutNanoseconds: UInt64 = 5_000_000_000  // 5 seconds
        ) async throws -> Result<Data, NetworkError> {
            try await withCheckedThrowingContinuation { continuation in
                let coordinationActor = CoordinationActor()

                // Create timeout task using Swift 6 concurrency patterns
                let timeoutTask = Task {
                    try await Task.sleep(nanoseconds: timeoutNanoseconds)
                    if await coordinationActor.tryResume() {
                        continuation.resume(
                            throwing: NetworkError.customError(
                                "Test timeout", details: "Upload operation took too long"))
                    }
                }

                // Create upload task with proper coordination - capture image safely
                let imageCopy = image
                Task { @MainActor in
                    await model.uploadImage(
                        imageCopy,
                        to: url,
                        uploadType: .multipart,
                        configuration: UploadConfiguration(),
                        onSuccess: { data in
                            timeoutTask.cancel()
                            Task { @MainActor in
                                if await coordinationActor.tryResume() {
                                    continuation.resume(returning: .success(data))
                                }
                            }
                        },
                        onError: { error in
                            timeoutTask.cancel()
                            Task { @MainActor in
                                if await coordinationActor.tryResume() {
                                    continuation.resume(returning: .failure(error))
                                }
                            }
                        }
                    )
                }
            }
        }
    }
#endif
