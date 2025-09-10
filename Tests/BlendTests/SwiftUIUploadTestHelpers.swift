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
        ///   - nanoseconds: Timeout in nanoseconds
        ///   - timeoutMessage: Custom timeout error message
        ///   - operation: The async operation to perform
        /// - Returns: The result of the operation
        /// - Throws: The operation's error or NetworkError on timeout
        @MainActor
        public static func withTimeout<T: Sendable>(
            nanoseconds: UInt64,
            timeoutMessage: String = "Operation timed out",
            operation: @escaping () async throws -> T
        ) async throws -> T {
            // Create a task for the operation that will be cancelled on timeout
            let operationTask = Task {
                try await operation()
            }

            // Create a timeout task with proper cancellation handling
            let timeoutTask = Task {
                try await Task.sleep(nanoseconds: nanoseconds)
                // If we reach here without cancellation, the timeout occurred
                return true
            }

            // Ensure both tasks are cancelled when this function exits
            defer {
                operationTask.cancel()
                timeoutTask.cancel()
            }

            do {
                // Wait for either the operation to complete or timeout
                let result = try await operationTask.value

                // If we get here, operation completed successfully
                return result
            } catch is CancellationError {
                // Check if timeout occurred by awaiting the timeout task
                do {
                    _ = try await timeoutTask.value
                    // If timeout task completed successfully, timeout occurred
                    throw NetworkError.customError(timeoutMessage, details: nil)
                } catch {
                    // Timeout task was cancelled, operation was cancelled for other reasons
                    throw CancellationError()
                }
            } catch {
                // Operation failed
                throw error
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
