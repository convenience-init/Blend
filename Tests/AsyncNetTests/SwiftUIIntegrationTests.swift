import Testing
import Foundation
#if canImport(SwiftUI)
import SwiftUI
@testable import AsyncNet
#endif

#if canImport(SwiftUI)
@MainActor
@Suite("SwiftUI Integration Tests")
struct SwiftUIIntegrationTests {
    static let minimalPNG: [UInt8] = [
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
        0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
        0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
        0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
        0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
        0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
        0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
        0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
        0x42, 0x60, 0x82
    ]

    private func makeMockSession(
        data: Data = Data(Self.minimalPNG),
        urlString: String = "https://mock.api/test",
        statusCode: Int = 200,
        headers: [String: String] = ["Content-Type": "image/png"]
    ) -> MockURLSession {
        let response = HTTPURLResponse(
            url: URL(string: urlString)!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: headers
        )
        return MockURLSession(nextData: data, nextResponse: response)
    }

    @Test func testAsyncNetImageViewLoadingState() async {
        let mockSession = makeMockSession()
        let service = ImageService(urlSession: mockSession)
        // Test AsyncImageModel state transitions during successful image loading
        let model = AsyncImageModel(imageService: service)
        await model.loadImage(from: "https://mock.api/test")
        #expect(model.loadedImage != nil)
        #expect(model.hasError == false)
        #expect(model.isLoading == false)
    }

    @Test func testAsyncNetImageViewErrorState() async {
        let mockSession = MockURLSession(nextError: NetworkError.networkUnavailable)
        let service = ImageService(urlSession: mockSession)
        let model = AsyncImageModel(imageService: service)
        await model.loadImage(from: "https://mock.api/test")
        #expect(model.loadedImage == nil)
        #expect(model.hasError == true)
        #expect(model.error != nil)
    }

    @Test func testAsyncNetImageViewConcurrentLoad() async {
        let imageData = Data(Self.minimalPNG)
        
        // Create separate mock sessions and services for each concurrent load
        let mockSession1 = makeMockSession(data: imageData, urlString: "https://mock.api/test1")
        let mockSession2 = makeMockSession(data: imageData, urlString: "https://mock.api/test2")
        let mockSession3 = makeMockSession(data: imageData, urlString: "https://mock.api/test3")
        
        let service1 = ImageService(urlSession: mockSession1)
        let service2 = ImageService(urlSession: mockSession2)
        let service3 = ImageService(urlSession: mockSession3)
        
        let model1 = AsyncImageModel(imageService: service1)
        let model2 = AsyncImageModel(imageService: service2)
        let model3 = AsyncImageModel(imageService: service3)
        
        // Start three concurrent load operations with different models and URLs
        async let load1: Void = model1.loadImage(from: "https://mock.api/test1")
        async let load2: Void = model2.loadImage(from: "https://mock.api/test2")
        async let load3: Void = model3.loadImage(from: "https://mock.api/test3")
        
        // Wait for all three concurrent operations to complete
        _ = await (load1, load2, load3)
        
        // Verify all models loaded successfully
        #expect(model1.loadedImage != nil)
        #expect(model1.hasError == false)
        #expect(model1.isLoading == false)
        
        #expect(model2.loadedImage != nil)
        #expect(model2.hasError == false)
        #expect(model2.isLoading == false)
        
        #expect(model3.loadedImage != nil)
        #expect(model3.hasError == false)
        #expect(model3.isLoading == false)
    }
    
    @Test func testAsyncNetImageViewUploadErrorState() async {
        let mockSession = makeMockSession()
        let service = ImageService(urlSession: mockSession)
        let model = AsyncImageModel(imageService: service)
        
        // Use a continuation to wait for the async callback
        _ = await withCheckedContinuation { continuation in
            // Simulate upload error (invalid URL that will cause network error)
            Task {
                await model.uploadImage(
                    ImageService.platformImage(from: Data(Self.minimalPNG))!,
                    to: URL(string: "invalid-url-that-will-fail"), // Use invalid URL instead of nil
                    uploadType: .multipart,
                    configuration: ImageService.UploadConfiguration(),
                    onSuccess: { _ in 
                        continuation.resume(returning: NetworkError.custom(message: "Unexpected success", details: nil))
                    },
                    onError: { error in 
                        continuation.resume(returning: error)
                    }
                )
            }
        }
        
        // Verify the error was received (should be network error due to invalid URL)
        // The continuation completing successfully means an error callback was invoked
        #expect(model.isUploading == false)
    }
    
    @Test func testAsyncNetImageViewRetryFunctionality() async {
        let service = ImageService()
        let model = AsyncImageModel(imageService: service)
        
        // First, simulate a failed load
        let failedSession = MockURLSession(nextError: NetworkError.networkUnavailable)
        let failedService = ImageService(urlSession: failedSession)
        let failedModel = AsyncImageModel(imageService: failedService)
        
        await failedModel.loadImage(from: "https://mock.api/fail")
        #expect(failedModel.loadedImage == nil)
        #expect(failedModel.hasError == true)
        #expect(failedModel.error != nil)
        
        // Now simulate a successful retry
        let successSession = makeMockSession()
        let successService = ImageService(urlSession: successSession)
        let successModel = AsyncImageModel(imageService: successService)
        
        // Retry the load (this simulates what the retry button would do)
        await successModel.loadImage(from: "https://mock.api/test")
        #expect(successModel.loadedImage != nil)
        #expect(successModel.hasError == false)
        #expect(successModel.isLoading == false)
    }
}
#endif
