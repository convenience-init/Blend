import Testing
import Foundation
@testable import AsyncNet
#if canImport(UIKit)
import UIKit
#elseif canImport(Cocoa)
import Cocoa
#endif
#if canImport(SwiftUI)
import SwiftUI
#endif

// Equatable conformance for NetworkError for testing
extension NetworkError: Equatable {
    public static func == (lhs: NetworkError, rhs: NetworkError) -> Bool {
        switch (lhs, rhs) {
        case (.decode, .decode): return true
        case (.offLine, .offLine): return true
        case (.unauthorized, .unauthorized): return true
        case (.custom(let l), .custom(let r)): return l == r
        case (.unknown, .unknown): return true
        case (.invalidURL(let l), .invalidURL(let r)): return l == r
        case (.networkError, .networkError): return true // ignore error details
        case (.noResponse, .noResponse): return true
        case (.decodingError, .decodingError): return true
        case (.badStatusCode(let l), .badStatusCode(let r)): return l == r
        case (.badMimeType(let l), .badMimeType(let r)): return l == r
        case (.uploadFailed(let l), .uploadFailed(let r)): return l == r
        case (.imageProcessingFailed, .imageProcessingFailed): return true
        case (.cacheError(let l), .cacheError(let r)): return l == r
        default: return false
        }
    }
}

@Suite("Image Service Tests")
struct ImageServiceTests {

    @Test func testFetchImageDataSuccess() async throws {
        // Prepare mock image data and response
        let imageData = Data([0xFF, 0xD8, 0xFF]) // JPEG header
        let response = HTTPURLResponse(
            url: URL(string: "https://mock.api/test")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "image/jpeg", "Mime-Type": "image/jpeg"]
        )!
        let mockSession = MockURLSession(nextData: imageData, nextResponse: response)
    let service = ImageService(urlSession: mockSession)
        let result = try await service.fetchImageData(from: "https://mock.api/test")
        #expect(result == imageData)
    }

    @Test func testFetchImageDataInvalidURL() async throws {
        let mockSession = MockURLSession()
        let service = ImageService(urlSession: mockSession)
        do {
            _ = try await service.fetchImageData(from: "not a url")
            #expect(Bool(false))
        } catch let error as NetworkError {
            #expect(error == .noResponse)
        }
    }

    @Test func testFetchImageDataUnauthorized() async throws {
        let imageData = Data([0xFF, 0xD8, 0xFF])
        let response = HTTPURLResponse(
            url: URL(string: "https://mock.api/test")!,
            statusCode: 401,
            httpVersion: nil,
            headerFields: ["Content-Type": "image/jpeg"]
        )!
        let mockSession = MockURLSession(nextData: imageData, nextResponse: response)
    let service = ImageService(urlSession: mockSession)
        do {
            _ = try await service.fetchImageData(from: "https://mock.api/test")
            #expect(Bool(false))
        } catch let error as NetworkError {
            #expect(error == .unauthorized)
        }
    }

    @Test func testFetchImageDataBadMimeType() async throws {
        let imageData = Data([0xFF, 0xD8, 0xFF])
        let response = HTTPURLResponse(
            url: URL(string: "https://mock.api/test")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/octet-stream", "Mime-Type": "application/octet-stream"]
        )!
        let mockSession = MockURLSession(nextData: imageData, nextResponse: response)
    let service = ImageService(urlSession: mockSession)
        do {
            _ = try await service.fetchImageData(from: "https://mock.api/test")
            #expect(Bool(false))
        } catch let error as NetworkError {
            #expect(error == .badMimeType("application/octet-stream"))
        }
    }

    @Test func testUploadImageMultipartSuccess() async throws {
        let imageData = Data([0xFF, 0xD8, 0xFF])
        let response = HTTPURLResponse(
            url: URL(string: "https://mock.api/upload")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        let mockSession = MockURLSession(nextData: imageData, nextResponse: response)
    let service = ImageService(urlSession: mockSession)
        let result = try await service.uploadImageMultipart(imageData, to: URL(string: "https://mock.api/upload")!)
        #expect(result == imageData)
    }

    @Test func testUploadImageBase64Success() async throws {
        let imageData = Data([0xFF, 0xD8, 0xFF])
        let response = HTTPURLResponse(
            url: URL(string: "https://mock.api/upload")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        let mockSession = MockURLSession(nextData: imageData, nextResponse: response)
    let service = ImageService(urlSession: mockSession)
        let result = try await service.uploadImageBase64(imageData, to: URL(string: "https://mock.api/upload")!)
        #expect(result == imageData)
    }

}
