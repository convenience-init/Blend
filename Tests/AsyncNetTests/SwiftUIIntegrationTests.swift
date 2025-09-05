import Foundation
import Testing

#if canImport(SwiftUI)
    import SwiftUI
    @testable import AsyncNet
#endif

#if canImport(SwiftUI)
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

    /// MockURLSession for testing concurrent loads with multiple URLs
    private actor ConcurrentMockSession: URLSessionProtocol {
        private let imageData: Data
        private let supportedURLs: [URL]
        private var _callCount: Int = 0
        private let artificialDelay: UInt64 = 100_000_000  // 100ms delay for stable timing

        init(imageData: Data, urls: [URL]) {
            self.imageData = imageData
            self.supportedURLs = urls
        }

        /// Thread-safe getter for call count (safe to call after concurrent work completes)
        var callCount: Int {
            _callCount
        }

        func data(for request: URLRequest) async throws -> (Data, URLResponse) {
            // Thread-safe increment of call count
            _callCount += 1

            // Add artificial delay to simulate network latency
            if artificialDelay > 0 {
                try await Task.sleep(nanoseconds: artificialDelay)
            }

            // Verify the request URL is one of our supported URLs
            guard let requestURL = request.url,
                supportedURLs.contains(where: { $0.absoluteString == requestURL.absoluteString })
            else {
                throw NetworkError.customError(
                    "Unsupported URL: \(request.url?.absoluteString ?? "nil")",
                    details: nil
                )
            }

            // Create HTTP response for the requested URL
            guard
                let response = HTTPURLResponse(
                    url: requestURL,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "image/png"]
                )
            else {
                throw NetworkError.customError(
                    "Failed to create HTTPURLResponse for URL: \(requestURL.absoluteString)",
                    details: nil
                )
            }

            return (imageData, response)
        }
    }

    @Suite("AsyncImageModel Tests")
    struct SwiftUIIntegrationTests {
        static let minimalPNGBase64 =
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAACklEQVR4nGMAAQAABQABDQottAAAAABJRU5ErkJggg=="

        /// Test-friendly version that throws instead of crashing
        static func getMinimalPNGData() throws -> Data {
            guard let data = Data(base64Encoded: minimalPNGBase64) else {
                throw NetworkError.customError(
                    "Failed to decode minimalPNGBase64 - invalid Base64 string", details: nil)
            }
            return data
        }

        /// Static property that decodes the Base64 data, using Issue.record if decoding fails
        private static let minimalPNGData: Data = {
            guard let data = Data(base64Encoded: minimalPNGBase64) else {
                Issue.record("Failed to decode minimalPNGBase64 - invalid Base64 string")
                // Fatal error is appropriate here as this is test infrastructure
                fatalError("Test infrastructure error: Failed to decode minimalPNGBase64")
            }
            return data
        }()

        private static let defaultTestURL = URL(string: "https://mock.api/test")!
        private static let defaultUploadURL = URL(string: "https://mock.api/upload")!
        private static let defaultFailURL = URL(string: "https://mock.api/fail")!
        private static let defaultFailRetryURL = URL(string: "https://mock.api/fail-retry")!
        private static let concurrentTestURL1 = URL(string: "https://mock.api/test1")!
        private static let concurrentTestURL2 = URL(string: "https://mock.api/test2")!
        private static let concurrentTestURL3 = URL(string: "https://mock.api/test3")!

        private func makeMockSession(
            data: Data? = nil,
            url: URL = Self.defaultTestURL,
            statusCode: Int = 200,
            headers: [String: String] = ["Content-Type": "image/png"],
            artificialDelay: UInt64 = 100_000_000  // 100ms default delay for stable timing
        ) throws -> MockURLSession {
            let dataToUse = data ?? Self.minimalPNGData
            guard
                let response = HTTPURLResponse(
                    url: url,
                    statusCode: statusCode,
                    httpVersion: nil,
                    headerFields: headers
                )
            else {
                throw NetworkError.customError(
                    "Failed to create HTTPURLResponse with headers: \(headers) - header fields may be invalid",
                    details: nil)
            }
            return MockURLSession(
                nextData: dataToUse, nextResponse: response, artificialDelay: artificialDelay)
        }

        @MainActor
        @Test func testAsyncNetImageModelLoadingState() async throws {
            let mockSession = try makeMockSession()
            let service = ImageService(
                imageCacheCountLimit: 100,
                imageCacheTotalCostLimit: 50 * 1024 * 1024,
                dataCacheCountLimit: 200,
                dataCacheTotalCostLimit: 100 * 1024 * 1024,
                urlSession: mockSession
            )
            let model = AsyncImageModel(imageService: service)
            // Test AsyncImageModel state transitions during successful image loading
            await model.loadImage(from: Self.defaultTestURL.absoluteString)
            #expect(model.error == nil, "Error should be nil after successful load")
            #expect(model.loadedImage != nil)
            // Verify the loaded image is actually displayable by checking its properties
            if let loadedImage = model.loadedImage {
                #expect(
                    loadedImage.cgImage != nil,
                    "Loaded image should have valid underlying CGImage data")
                #expect(
                    loadedImage.size.width > 0 && loadedImage.size.height > 0,
                    "Loaded image should have valid dimensions")
            }
            #expect(model.hasError == false)
            #expect(model.isLoading == false)
        }

        @MainActor
        @Test func testAsyncNetImageModelErrorState() async {
            // Create mock session that returns the same error for multiple calls (to handle retries)
            let mockSession = MockURLSession(scriptedCalls: [
                (nil, nil, NetworkError.networkUnavailable),
                (nil, nil, NetworkError.networkUnavailable),
                (nil, nil, NetworkError.networkUnavailable),
            ])
            let service = ImageService(
                imageCacheCountLimit: 100,
                imageCacheTotalCostLimit: 50 * 1024 * 1024,
                dataCacheCountLimit: 200,
                dataCacheTotalCostLimit: 100 * 1024 * 1024,
                urlSession: mockSession
            )
            let model = AsyncImageModel(imageService: service)
            await model.loadImage(from: Self.defaultTestURL.absoluteString)
            #expect(model.loadedImage == nil)
            #expect(model.hasError == true)
            #expect(
                model.error == NetworkError.networkUnavailable,
                "Should have networkUnavailable error")
            #expect(model.isLoading == false, "Loading flag should be false after failed load")
        }

        @Test func testAsyncNetImageModelConcurrentLoad() async throws {
            let imageData = try Self.getMinimalPNGData()

            // Create a single mock session that can handle all three URLs
            let mockSession = ConcurrentMockSession(
                imageData: imageData,
                urls: [Self.concurrentTestURL1, Self.concurrentTestURL2, Self.concurrentTestURL3]
            )

            // Create a single ImageService instance to test concurrency within one service
            let service = ImageService(
                imageCacheCountLimit: 100,
                imageCacheTotalCostLimit: 50 * 1024 * 1024,
                dataCacheCountLimit: 200,
                dataCacheTotalCostLimit: 100 * 1024 * 1024,
                urlSession: mockSession
            )

            // Initialize all models with the same service instance
            let model1 = await MainActor.run { AsyncImageModel(imageService: service) }
            let model2 = await MainActor.run { AsyncImageModel(imageService: service) }
            let model3 = await MainActor.run { AsyncImageModel(imageService: service) }

            // Track timing to verify true concurrency
            var startTimes: [String: Date] = [:]
            var endTimes: [String: Date] = [:]

            // Use TaskGroup to run concurrent loads off the main actor
            await withTaskGroup(of: (String, Date, Date).self) { group in
                // Add tasks for each model load
                group.addTask {
                    let loadStart = Date()
                    await model1.loadImage(from: Self.concurrentTestURL1.absoluteString)
                    let loadEnd = Date()
                    return ("model1", loadStart, loadEnd)
                }

                group.addTask {
                    let loadStart = Date()
                    await model2.loadImage(from: Self.concurrentTestURL2.absoluteString)
                    let loadEnd = Date()
                    return ("model2", loadStart, loadEnd)
                }

                group.addTask {
                    let loadStart = Date()
                    await model3.loadImage(from: Self.concurrentTestURL3.absoluteString)
                    let loadEnd = Date()
                    return ("model3", loadStart, loadEnd)
                }

                // Collect timing results
                for await (modelId, startTime, endTime) in group {
                    startTimes[modelId] = startTime
                    endTimes[modelId] = endTime
                }
            }

            // Calculate durations and total concurrent time
            // Safely collect timing data using compactMap
            let modelKeys = ["model1", "model2", "model3"]
            let allStartTimes = modelKeys.compactMap { startTimes[$0] }
            let allEndTimes = modelKeys.compactMap { endTimes[$0] }

            // Assert we have timing data for all expected models
            #expect(allStartTimes.count == 3, "Should have start times for all 3 models")
            #expect(allEndTimes.count == 3, "Should have end times for all 3 models")

            guard allStartTimes.count == 3 && allEndTimes.count == 3 else {
                Issue.record("Missing timing data for one or more models")
                return
            }

            // Calculate individual durations by iterating through modelKeys
            // This ensures each duration is paired with the correct model key
            var model1Duration: TimeInterval = 0
            var model2Duration: TimeInterval = 0
            var model3Duration: TimeInterval = 0

            for modelKey in modelKeys {
                guard let start = startTimes[modelKey], let end = endTimes[modelKey] else {
                    Issue.record("Missing timing data for model: \(modelKey)")
                    continue
                }

                let duration = end.timeIntervalSince(start)
                switch modelKey {
                case "model1":
                    model1Duration = duration
                case "model2":
                    model2Duration = duration
                case "model3":
                    model3Duration = duration
                default:
                    Issue.record("Unexpected model key: \(modelKey)")
                }
            }

            // Calculate total concurrent time (max end time - min start time)
            guard let minStartTime = allStartTimes.min(),
                let maxEndTime = allEndTimes.max()
            else {
                Issue.record("Unable to calculate min/max times from timing arrays")
                return
            }

            let totalConcurrentTime = maxEndTime.timeIntervalSince(minStartTime)

            // Verify that loads actually ran concurrently by checking timing overlap
            // The concurrent execution should take less time than sequential execution
            let sequentialTime = model1Duration + model2Duration + model3Duration

            // Relaxed performance check - concurrent execution should be at least 20% faster
            // This is logged as an issue rather than a test failure to avoid flaky tests
            if totalConcurrentTime >= sequentialTime * 0.8 {
                Issue.record(
                    "Concurrent loads did not show expected performance improvement (total: \(totalConcurrentTime)s, sequential: \(sequentialTime)s, ratio: \(totalConcurrentTime/sequentialTime)). This may indicate timing variations under load."
                )
            }

            // Verify all models loaded successfully - this is the critical functional test
            #expect(await model1.error == nil, "Model1 error should be nil after successful load")
            #expect(
                await model1.hasError == false, "Model1 should not have error after successful load"
            )
            #expect(
                await model1.isLoading == false,
                "Model1 should not be loading after successful load")

            #expect(await model2.error == nil, "Model2 error should be nil after successful load")
            #expect(
                await model2.hasError == false, "Model2 should not have error after successful load"
            )
            #expect(
                await model2.isLoading == false,
                "Model2 should not be loading after successful load")

            #expect(await model3.error == nil, "Model3 error should be nil after successful load")
            #expect(
                await model3.hasError == false, "Model3 should not have error after successful load"
            )
            #expect(
                await model3.isLoading == false,
                "Model3 should not be loading after successful load")
        }

        @MainActor
        @Test func testAsyncNetImageModelUploadErrorState() async throws {
            // Create a mock session that returns an upload error
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
            let testData = try Self.getMinimalPNGData()
            guard let platformImage = ImageService.platformImage(from: testData) else {
                throw NetworkError.customError(
                    "Failed to create platform image from test data", details: nil)
            }

            // Extract the error from the result for error case
            let result: NetworkError
            var capturedResult: Result<Data, NetworkError>?

            capturedResult = try await performUploadWithTimeout(
                model: model,
                image: platformImage,
                url: Self.defaultUploadURL
            )
            
            switch capturedResult {
            case .failure(let error):
                result = error
            case .success, .none:
                throw NetworkError.customError(
                    "Expected upload to fail, but it succeeded", details: nil)
            }

            // Assert the continuation result is the expected error type
            if case let .serverError(statusCode, _) = result {
                #expect(statusCode == 500, "Should receive HTTP 500 error")
            } else {
                Issue.record("Expected server error but got: \(result)")
            }

            // Assert that model.isUploading is false
            #expect(model.isUploading == false, "isUploading should be false after error")

            // Now test that error state is cleared after a successful upload
            // Create a successful mock session for the retry
            guard
                let successResponse = HTTPURLResponse(
                    url: Self.defaultUploadURL,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )
            else {
                Issue.record("Failed to create HTTPURLResponse for successful upload test")
                return
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
            let successModel = AsyncImageModel(imageService: successService)

            // Perform successful upload using the helper method
            let successResult = try await performUploadWithTimeout(
                model: successModel,
                image: platformImage,
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
                successModel.isUploading == false,
                "isUploading should be false after successful upload")
            #expect(successModel.error == nil, "Error should be nil after successful upload")
        }

        /// Helper method to perform upload with timeout coordination using Swift 6 concurrency patterns
        /// - Parameters:
        ///   - model: The AsyncImageModel to perform upload on
        ///   - image: The platform image to upload
        ///   - url: The upload URL
        ///   - timeoutNanoseconds: Timeout in nanoseconds (default: 5 seconds)
        /// - Returns: Result containing either the response data or a NetworkError
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
                        configuration: ImageService.UploadConfiguration(),
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

        @MainActor
        @Test func testAsyncNetImageModelUploadRetry() async throws {
            // Create a mock session that returns an upload error, then success
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
                (
                    Data("Server Error".utf8), nil,
                    NetworkError.serverError(
                        statusCode: 500, data: "Server Error".data(using: .utf8))
                ),
                (Data("{\"success\": true}".utf8), successResponse, nil)
            ])
            let service = ImageService(
                imageCacheCountLimit: 100,
                imageCacheTotalCostLimit: 50 * 1024 * 1024,
                dataCacheCountLimit: 200,
                dataCacheTotalCostLimit: 100 * 1024 * 1024,
                urlSession: mockSession
            )
            let model = AsyncImageModel(imageService: service)

            // Guard against nil platform image
            let testData = try Self.getMinimalPNGData()
            guard let platformImage = ImageService.platformImage(from: testData) else {
                throw NetworkError.customError(
                    "Failed to create platform image from test data", details: nil)
            }

            // Initial upload attempt - should fail with server error
            let initialResult: Result<Data, NetworkError> =
                try await performUploadWithTimeout(
                    model: model,
                    image: platformImage,
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
                            statusCode: 500, data: "Server Error".data(using: .utf8)),
                    "Initial upload should fail with server error")
            }

            // Successful upload retry - should succeed
            let successResult: Result<Data, NetworkError> =
                try await performUploadWithTimeout(
                    model: model,
                    image: platformImage,
                    url: Self.defaultUploadURL,
                    timeoutNanoseconds: 5_000_000_000  // 5 seconds
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
    }
#endif
