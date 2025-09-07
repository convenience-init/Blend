#if canImport(SwiftUI)
    import Foundation
    import Testing
    import SwiftUI
    @testable import AsyncNet

    @Suite("SwiftUI Concurrent Loading Tests")
    public struct SwiftUIConcurrentLoadingTests {
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

        private static let concurrentTestURL1 = URL(string: "https://mock.api/test1")!
        private static let concurrentTestURL2 = URL(string: "https://mock.api/test2")!
        private static let concurrentTestURL3 = URL(string: "https://mock.api/test3")!

        @Test public func testAsyncNetImageModelConcurrentLoad() async throws {
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

            // Run concurrent loads and collect timing data
            let timingResults = await performConcurrentLoads(
                models: [model1, model2, model3],
                urls: [Self.concurrentTestURL1, Self.concurrentTestURL2, Self.concurrentTestURL3]
            )

            // Analyze timing results
            try await analyzeConcurrencyResults(
                timingResults, model1: model1, model2: model2, model3: model3)
        }

        /// Performs concurrent image loads and returns timing results
        private func performConcurrentLoads(
            models: [AsyncImageModel],
            urls: [URL]
        ) async -> [String: (start: Date, end: Date)] {
            var timingResults: [String: (start: Date, end: Date)] = [:]

            await withTaskGroup(of: (String, Date, Date).self) { group in
                for (index, model) in models.enumerated() {
                    let url = urls[index]
                    group.addTask {
                        let start = Date()
                        await model.loadImage(from: url.absoluteString)
                        return ("model\(index + 1)", start, Date())
                    }
                }

                for await (modelId, startTime, endTime) in group {
                    timingResults[modelId] = (startTime, endTime)
                }
            }

            return timingResults
        }

        /// Analyzes concurrency timing results and verifies model states
        private func analyzeConcurrencyResults(
            _ timingResults: [String: (start: Date, end: Date)],
            model1: AsyncImageModel, model2: AsyncImageModel, model3: AsyncImageModel
        ) async throws {
            let modelKeys = ["model1", "model2", "model3"]
            let allStartTimes = modelKeys.compactMap { timingResults[$0]?.start }
            let allEndTimes = modelKeys.compactMap { timingResults[$0]?.end }

            #expect(allStartTimes.count == 3, "Should have start times for all 3 models")
            #expect(allEndTimes.count == 3, "Should have end times for all 3 models")

            guard allStartTimes.count == 3 && allEndTimes.count == 3 else {
                Issue.record("Missing timing data for one or more models")
                return
            }

            // Calculate timing metrics
            let durations = modelKeys.compactMap { key -> TimeInterval? in
                guard let (start, end) = timingResults[key] else { return nil }
                return end.timeIntervalSince(start)
            }

            guard durations.count == 3,
                let minStartTime = allStartTimes.min(),
                let maxEndTime = allEndTimes.max()
            else {
                Issue.record("Unable to calculate timing metrics")
                return
            }

            let totalConcurrentTime = maxEndTime.timeIntervalSince(minStartTime)
            let sequentialTime = durations.reduce(0, +)

            // Verify concurrency performance (logged as issue to avoid flaky tests)
            if totalConcurrentTime >= sequentialTime * 0.8 {
                Issue.record(
                    """
                    Concurrent loads did not show expected performance improvement \
                    (total: \(totalConcurrentTime)s, sequential: \(sequentialTime)s, \
                    ratio: \(totalConcurrentTime/sequentialTime)). \
                    This may indicate timing variations under load.
                    """
                )
            }

            // Verify all models loaded successfully
            try await verifyModelStates(model1: model1, model2: model2, model3: model3)
        }

        /// Verifies that all models loaded successfully
        private func verifyModelStates(
            model1: AsyncImageModel, model2: AsyncImageModel, model3: AsyncImageModel
        ) async throws {
            #expect(await model1.error == nil, "Model1 error should be nil after successful load")
            #expect(
                await model1.hasError == false, "Model1 should not have error after successful load"
            )
            #expect(
                await model1.isLoading == false,
                "Model1 should not be loading after successful load"
            )

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
    }
#endif
