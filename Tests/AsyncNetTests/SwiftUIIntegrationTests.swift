import Foundation
import Testing

#if canImport(SwiftUI)
    import SwiftUI
    @testable import AsyncNet
#endif

#if canImport(SwiftUI)
    @Suite("AsyncImageModel Tests")
    struct SwiftUIIntegrationTests {
        static let minimalPNGBase64 =
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAACklEQVR4nGMAAQAABQABDQottAAAAABJRU5ErkJggg=="

        static let minimalPNGData: Data = {
            guard let data = Data(base64Encoded: minimalPNGBase64) else {
                fatalError("Failed to decode minimalPNGBase64 - invalid Base64 string")
            }
            return data
        }()

        private static let defaultTestURL = URL(string: "https://mock.api/test")!
        private static let defaultUploadURL = URL(string: "https://mock.api/upload")!
        private static let defaultFailURL = URL(string: "https://mock.api/fail")!
        private static let concurrentTestURL1 = URL(string: "https://mock.api/test1")!
        private static let concurrentTestURL2 = URL(string: "https://mock.api/test2")!
        private static let concurrentTestURL3 = URL(string: "https://mock.api/test3")!

        private func makeMockSession(
            data: Data = Self.minimalPNGData,
            url: URL = Self.defaultTestURL,
            statusCode: Int = 200,
            headers: [String: String] = ["Content-Type": "image/png"],
            artificialDelay: UInt64 = 100_000_000  // 100ms default delay for stable timing
        ) -> MockURLSession {
            guard
                let response = HTTPURLResponse(
                    url: url,
                    statusCode: statusCode,
                    httpVersion: nil,
                    headerFields: headers
                )
            else {
                fatalError(
                    "Failed to create HTTPURLResponse with headers: \(headers) - header fields may be invalid"
                )
            }
            return MockURLSession(
                nextData: data, nextResponse: response, artificialDelay: artificialDelay)
        }

        @MainActor
        @Test func testAsyncNetImageModelLoadingState() async {
            let mockSession = makeMockSession()
            let service = ImageService(urlSession: mockSession)
            // Test AsyncImageModel state transitions during successful image loading
            let model = AsyncImageModel(imageService: service)
            await model.loadImage(from: Self.defaultTestURL.absoluteString)
            #expect(model.error == nil, "Error should be nil after successful load")
            #expect(model.loadedImage != nil)
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
            let service = ImageService(urlSession: mockSession)
            let model = AsyncImageModel(imageService: service)
            await model.loadImage(from: Self.defaultTestURL.absoluteString)
            #expect(model.loadedImage == nil)
            #expect(model.hasError == true)
            #expect(
                model.error == NetworkError.networkUnavailable,
                "Should have networkUnavailable error")
            #expect(model.isLoading == false, "Loading flag should be false after failed load")
        }

        @Test func testAsyncNetImageModelConcurrentLoad() async {
            let imageData = Self.minimalPNGData

            // Create separate mock sessions and services for each concurrent load
            let mockSession1 = makeMockSession(
                data: imageData, url: Self.concurrentTestURL1)
            let mockSession2 = makeMockSession(
                data: imageData, url: Self.concurrentTestURL2)
            let mockSession3 = makeMockSession(
                data: imageData, url: Self.concurrentTestURL3)

            let service1 = ImageService(urlSession: mockSession1)
            let service2 = ImageService(urlSession: mockSession2)
            let service3 = ImageService(urlSession: mockSession3)

            let model1 = await AsyncImageModel(imageService: service1)
            let model2 = await AsyncImageModel(imageService: service2)
            let model3 = await AsyncImageModel(imageService: service3)

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

            // Verify that loads actually ran concurrently by checking timing overlap
            let model1Duration = endTimes["model1"]!.timeIntervalSince(startTimes["model1"]!)
            let model2Duration = endTimes["model2"]!.timeIntervalSince(startTimes["model2"]!)
            let model3Duration = endTimes["model3"]!.timeIntervalSince(startTimes["model3"]!)

            // Calculate overlap periods
            let earliestStart = startTimes.values.min()!
            let latestEnd = endTimes.values.max()!
            let totalConcurrentTime = latestEnd.timeIntervalSince(earliestStart)

            // The concurrent execution should take less time than sequential execution
            let sequentialTime = model1Duration + model2Duration + model3Duration
            #expect(
                totalConcurrentTime < sequentialTime * 0.8,
                "Concurrent loads should complete faster than sequential execution")

            // Verify all models loaded successfully
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
                fatalError(
                    "Failed to create HTTPURLResponse for upload error test - header fields may be invalid"
                )
            }
            let mockSession = MockURLSession(
                nextData: Data("Server Error".utf8), nextResponse: errorResponse)
            let service = ImageService(urlSession: mockSession)
            let model = AsyncImageModel(imageService: service)

            // Guard against nil platform image
            guard let platformImage = ImageService.platformImage(from: Self.minimalPNGData) else {
                throw NetworkError.customError(
                    "Failed to create platform image from test data", details: nil)
            }

            // Use withCheckedThrowingContinuation to properly handle the error with timeout protection
            let result: NetworkError = try await withCheckedThrowingContinuation { continuation in
                var hasResumed = false

                // Timeout task to prevent hanging
                let timeoutTask = Task {
                    try await Task.sleep(nanoseconds: 5_000_000_000)  // 5 second timeout
                    if !hasResumed {
                        hasResumed = true
                        continuation.resume(
                            throwing: NetworkError.customError(
                                "Test timeout", details: "Upload operation took too long"))
                    }
                }

                Task {
                    await model.uploadImage(
                        platformImage,
                        to: Self.defaultUploadURL,
                        uploadType: .multipart,
                        configuration: ImageService.UploadConfiguration(),
                        onSuccess: { _ in
                            timeoutTask.cancel()
                            if !hasResumed {
                                hasResumed = true
                                continuation.resume(
                                    throwing: NetworkError.customError(
                                        "Unexpected success in error test", details: nil))
                            }
                        },
                        onError: { error in
                            timeoutTask.cancel()
                            if !hasResumed {
                                hasResumed = true
                                continuation.resume(returning: error)
                            }
                        }
                    )
                }
            }

            // Assert the continuation result is the expected error type
            if case let .httpError(statusCode, _) = result {
                #expect(statusCode == 500, "Should receive HTTP 500 error")
            } else {
                Issue.record("Expected HTTP error but got: \(result)")
            }

            // Assert that model.isUploading is false
            #expect(model.isUploading == false, "isUploading should be false after error")

            // Now test that error state is cleared after a successful upload
            // Create a successful mock session for the retry
            let successResponse = HTTPURLResponse(
                url: Self.defaultUploadURL,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            let successSession = MockURLSession(
                nextData: Data("{\"success\": true}".utf8), nextResponse: successResponse)
            let successService = ImageService(urlSession: successSession)
            let successModel = AsyncImageModel(imageService: successService)

            // Perform successful upload
            let successResult: Result<Data, NetworkError> =
                try await withCheckedThrowingContinuation { continuation in
                    var hasResumed = false

                    Task {
                        await successModel.uploadImage(
                            platformImage,
                            to: Self.defaultUploadURL,
                            uploadType: .multipart,
                            configuration: ImageService.UploadConfiguration(),
                            onSuccess: { data in
                                if !hasResumed {
                                    hasResumed = true
                                    continuation.resume(returning: .success(data))
                                }
                            },
                            onError: { error in
                                if !hasResumed {
                                    hasResumed = true
                                    continuation.resume(returning: .failure(error))
                                }
                            }
                        )
                    }
                }

            // Assert successful upload
            switch successResult {
            case .success(let data):
                #expect(
                    String(data: data, encoding: .utf8) == "{\"success\": true}",
                    "Should receive success response")
            case .failure(let error):
                Issue.record("Expected successful upload but got error: \(error)")
            }

            // Assert that error state is cleared after successful upload
            #expect(successModel.error == nil, "Error should be nil after successful upload")
            #expect(
                successModel.hasError == false, "hasError should be false after successful upload")
            #expect(
                successModel.isUploading == false,
                "isUploading should remain false after successful upload")
        }

        @MainActor
        @Test func testAsyncNetImageModelRetryFunctionality() async {
            // Create a mock session that fails multiple times (to exhaust ImageService's built-in retries), then succeeds
            let failResponse = HTTPURLResponse(
                url: Self.defaultFailURL,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "image/png"]
            )!
            let successResponse = HTTPURLResponse(
                url: Self.defaultTestURL,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "image/png"]
            )!

            // ImageService has built-in retry logic (3 attempts by default), so we need to provide enough failures
            // followed by a success. The pattern will be: fail, fail, fail (exhaust retries), then success on retry
            let session = MockURLSession(scriptedCalls: [
                (nil, nil, NetworkError.networkUnavailable),  // First attempt fails
                (nil, nil, NetworkError.networkUnavailable),  // Second attempt fails
                (nil, nil, NetworkError.networkUnavailable),  // Third attempt fails
                (Self.minimalPNGData, successResponse, nil),  // Fourth attempt succeeds
            ])
            let service = ImageService(urlSession: session)
            let model = AsyncImageModel(imageService: service)

            // Initial failed load (this will exhaust the built-in retries and fail)
            await model.loadImage(from: Self.defaultFailURL.absoluteString)
            #expect(model.loadedImage == nil, "Should have no image after failed load")
            #expect(model.hasError == true, "Should have error after failed load")
            #expect(
                model.error == NetworkError.networkUnavailable,
                "Should have networkUnavailable error on failure")
            #expect(
                model.isLoading == false, "Loading flag should be false after failed load")

            // Now simulate a successful retry on the same model instance
            // This will use the success response from the mock session
            await model.loadImage(from: Self.defaultTestURL.absoluteString)
            #expect(model.error == nil, "Error should be nil after successful retry")
            #expect(model.loadedImage != nil, "Should have loaded image after successful retry")
            #expect(model.hasError == false, "hasError should be false after successful retry")
            #expect(model.isLoading == false, "isLoading should be false after successful retry")
        }
    }
#endif
