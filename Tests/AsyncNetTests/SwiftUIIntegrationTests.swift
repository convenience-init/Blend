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
    @Test func testAsyncNetImageViewLoadingState() async {
        // Minimal valid PNG image (1x1 transparent pixel)
        let minimalPNG: [UInt8] = [
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
        let mockSession = MockURLSession(nextData: Data(minimalPNG), nextResponse: HTTPURLResponse(
            url: URL(string: "https://mock.api/test")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "image/png"]
        ))
        let service = ImageService(urlSession: mockSession)
    // View initialization not needed for logic test
        // Simulate loading state
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
        let minimalPNG: [UInt8] = [
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
        let mockSession = MockURLSession(nextData: Data(minimalPNG), nextResponse: HTTPURLResponse(
            url: URL(string: "https://mock.api/test")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "image/png"]
        ))
        let service = ImageService(urlSession: mockSession)
        let model = AsyncImageModel(imageService: service)
    async let load1: Void = model.loadImage(from: "https://mock.api/test")
    async let load2: Void = model.loadImage(from: "https://mock.api/test")
    async let load3: Void = model.loadImage(from: "https://mock.api/test")
    _ = await (load1, load2, load3)
        #expect(model.loadedImage != nil)
        #expect(model.hasError == false)
        #expect(model.isLoading == false)
    }
    
    @Test func testAsyncNetImageViewUploadErrorState() async {
        let minimalPNG: [UInt8] = [
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
        let mockSession = MockURLSession(nextData: Data(minimalPNG), nextResponse: HTTPURLResponse(
            url: URL(string: "https://mock.api/test")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "image/png"]
        ))
        let service = ImageService(urlSession: mockSession)
        let model = AsyncImageModel(imageService: service)
        // Simulate upload error (invalid URL)
        await model.uploadImage(
            ImageService.platformImage(from: Data(minimalPNG))!,
            to: nil,
            uploadType: .multipart,
            configuration: ImageService.UploadConfiguration(),
            onSuccess: { _ in },
            onError: { error in #expect(error == NetworkError.imageProcessingFailed) }
        )
        #expect(model.isUploading == false)
    }
}
#endif
