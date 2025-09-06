#if canImport(SwiftUI)
    import Foundation
    import Testing
    import SwiftUI
    @testable import AsyncNet

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

    @Suite("SwiftUI Basic Loading Tests")
    public struct SwiftUIBasicLoadingTests {
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

        /// Static property that decodes the Base64 data, using Issue.record if decoding fails
        private static let minimalPNGData: Data = {
            do {
                return try decodeMinimalPNGBase64()
            } catch {
                Issue.record("Failed to decode minimalPNGBase64 - invalid Base64 string")
                // Fatal error is appropriate here as this is test infrastructure
                fatalError("Test infrastructure error: Failed to decode minimalPNGBase64")
            }
        }()

        private static let defaultTestURL = URL(string: "https://mock.api/test")!

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
        @Test public func testAsyncNetImageModelLoadingState() async throws {
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
        @Test public func testAsyncNetImageModelErrorState() async {
            // Create mock session that returns the same error for multiple calls (to handle retries)
            let mockSession = MockURLSession(scriptedCalls: [
                MockScript(data: nil, response: nil, error: NetworkError.networkUnavailable),
                MockScript(data: nil, response: nil, error: NetworkError.networkUnavailable),
                MockScript(data: nil, response: nil, error: NetworkError.networkUnavailable)
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
    }
#endif
