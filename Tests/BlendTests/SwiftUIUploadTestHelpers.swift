#if canImport(SwiftUI)
    import Foundation
    import SwiftUI
    @testable import Blend

    /// Shared test utilities for SwiftUI upload tests
    /// Provides common functionality to reduce code duplication across test suites
    public enum SwiftUIUploadTestHelpers {
        /// Default timeout for upload operations in tests (5 seconds)
        public static let defaultTimeoutNanoseconds: UInt64 = 5_000_000_000

        /// Default test upload URL
        public static let defaultUploadURL = URL(string: "https://mock.api/upload")!

        /// Minimal PNG image data encoded as Base64 for testing
        public static let minimalPNGBase64 =
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAACklEQVR4nGMAAQAABQABDQottAAAAABJRU5ErkJggg=="

        /// Decode the minimal PNG Base64 string into Data
        /// - Returns: The decoded Data
        /// - Throws: NetworkError if decoding fails
        public static func decodeMinimalPNGBase64() throws -> Data {
            guard let data = Data(base64Encoded: minimalPNGBase64) else {
                throw NetworkError.customError(
                    "Failed to decode minimalPNGBase64 - invalid Base64 string", details: nil)
            }
            return data
        }

        /// Test-friendly version that throws instead of crashing
        /// - Returns: Minimal PNG data for testing
        /// - Throws: NetworkError if decoding fails
        public static func getMinimalPNGData() throws -> Data {
            try decodeMinimalPNGBase64()
        }

        /// Performs an operation with a timeout using Swift 6 concurrency patterns.
        /// This method races the operation against a timeout to prevent hanging.
        ///
        /// - Parameters:
        ///   - operation: The async operation to perform
        ///   - timeoutNanoseconds: Timeout in nanoseconds
        ///   - timeoutMessage: Custom timeout error message
        /// - Returns: The result of the operation
        /// - Throws: The operation's error or NetworkError on timeout
        @MainActor
        public static func withTimeout<T: Sendable>(
            nanoseconds: UInt64,
            timeoutMessage: String = "Operation timed out",
            operation: @escaping () async throws -> T
        ) async throws -> T {
            // Create operation task
            let operationTask = Task {
                try await operation()
            }

            // Race operation against timeout using task group
            return try await withThrowingTaskGroup(of: T.self) { group in
                // Add operation task
                group.addTask { try await operationTask.value }

                // Add timeout task that throws after delay
                group.addTask {
                    try await Task.sleep(nanoseconds: nanoseconds)
                    throw NetworkError.customError(timeoutMessage, details: nil)
                }

                // Get the first completed task result
                guard let result = try await group.next() else {
                    throw NetworkError.customError("No task completed", details: nil)
                }

                // Clean up remaining tasks
                group.cancelAll()
                operationTask.cancel()

                return result
            }
        }

        /// Performs an image upload with timeout coordination using Swift 6 concurrency patterns.
        /// This method races an upload operation against a timeout to prevent tests from hanging.
        ///
        /// - Parameters:
        ///   - model: The AsyncImageModel to perform upload on
        ///   - image: The platform image to upload
        ///   - url: The upload URL
        ///   - uploadType: The type of upload (.multipart or .base64)
        ///   - timeoutNanoseconds: Timeout in nanoseconds (default: 5 seconds)
        /// - Returns: The response data from the upload.
        /// - Throws: NetworkError if upload fails or times out.
        @MainActor
        public static func performUploadWithTimeout(
            model: AsyncImageModel,
            image: PlatformImage,
            url: URL,
            uploadType: UploadType = .multipart,
            timeoutNanoseconds: UInt64 = defaultTimeoutNanoseconds
        ) async throws -> Data {
            try await withTimeout(nanoseconds: timeoutNanoseconds, timeoutMessage: "Test timeout") {
                try await model.uploadImage(
                    image,
                    to: url,
                    uploadType: uploadType,
                    configuration: UploadConfiguration()
                )
            }
        }
    }
#endif
