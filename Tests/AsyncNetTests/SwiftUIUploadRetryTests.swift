#if canImport(SwiftUI)
    import Foundation
    import Testing
    import SwiftUI
    @testable import AsyncNet

    @Suite("SwiftUI Upload Retry Tests")
    public struct SwiftUIUploadRetryTests {
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
        @Test public func testAsyncNetImageModelUploadRetry() async throws {
            // Guard against nil platform image
            let testData = try Self.getMinimalPNGData()
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
                    url: Self.defaultUploadURL,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )
            else {
                throw NetworkError.customError(
                    "Failed to create HTTPURLResponse for success test", details: nil)
            }
            let mockSession = MockURLSession(scriptedCalls: [
                MockScript(
                    data: Data("Server Error".utf8),
                    response: nil,
                    error: NetworkError.serverError(
                        statusCode: 500, data: Data("Server Error".utf8))
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
            let initialResult: Result<Data, NetworkError> =
                try await performUploadWithTimeout(
                    model: model,
                    image: image,
                    url: Self.defaultUploadURL,
                    timeoutNanoseconds: 5_000_000_000  // 5 seconds
                )

            // Assert the initial result is the expected server error
            switch initialResult {
            case .success:
                throw NetworkError.customError(
                    "Expected initial upload to fail, but it succeeded", details: nil)
            case .failure(let error):
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
                model.isUploading == false, "isUploading should be false after successful upload")
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
#endif
