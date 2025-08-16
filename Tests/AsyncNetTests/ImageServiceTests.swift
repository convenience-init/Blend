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
        case (.httpError(let lCode, _, _), .httpError(let rCode, _, _)): return lCode == rCode
        case (.decodingError, .decodingError): return true
        case (.networkUnavailable, .networkUnavailable): return true
        case (.requestTimeout, .requestTimeout): return true
        case (.invalidEndpoint(let l), .invalidEndpoint(let r)): return l == r
        case (.unauthorized, .unauthorized): return true
        case (.noResponse, .noResponse): return true
        case (.badMimeType(let l), .badMimeType(let r)): return l == r
        case (.uploadFailed(let l), .uploadFailed(let r)): return l == r
        case (.imageProcessingFailed, .imageProcessingFailed): return true
        case (.cacheError(let l), .cacheError(let r)): return l == r
        // Legacy cases
        case (.decode, .decode): return true
        case (.offLine, .offLine): return true
        case (.custom(let l), .custom(let r)): return l == r
        case (.unknown, .unknown): return true
        case (.invalidURL(let l), .invalidURL(let r)): return l == r
        case (.networkError, .networkError): return true
        case (.badStatusCode(let l), .badStatusCode(let r)): return l == r
        case (.decodingErrorLegacy, .decodingErrorLegacy): return true
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
            print("DEBUG: testFetchImageDataInvalidURL caught error: \(error)")
            #expect(error == .invalidEndpoint(reason: "Invalid image URL: not a url"))
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
@Suite("Image Service Performance Benchmarks")
struct ImageServicePerformanceTests {

    @Test func testNetworkLatencyColdStart() async throws {
        let imageData = Data([0xFF, 0xD8, 0xFF])
        let response = HTTPURLResponse(
            url: URL(string: "https://mock.api/test")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "image/jpeg"]
        )!
        let mockSession = MockURLSession(nextData: imageData, nextResponse: response)
        let service = ImageService(urlSession: mockSession)
        let start = Date()
        try await Task.sleep(nanoseconds: 50_000_000) // 50ms artificial delay
        _ = try await service.fetchImageData(from: "https://mock.api/test")
        let elapsed = Date().timeIntervalSince(start)
        print("DEBUG: Cold start latency: \(elapsed * 1000) ms")
        #expect(elapsed < 0.1) // <100ms
    }

    @Test func testMemoryUsageDuringCaching() async throws {
        let imageData = Data(repeating: 0xFF, count: 1024 * 1024) // 1MB image
        let response = HTTPURLResponse(
            url: URL(string: "https://mock.api/test")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "image/jpeg"]
        )!
        let mockSession = MockURLSession(nextData: imageData, nextResponse: response)
        let service = ImageService(urlSession: mockSession)
        let memBefore = ProcessInfo.processInfo.physicalMemory
        _ = try await service.fetchImageData(from: "https://mock.api/test")
        let memAfter = ProcessInfo.processInfo.physicalMemory
        let memUsed = memAfter - memBefore
        print("DEBUG: Memory used for caching: \(memUsed / 1024 / 1024) MB")
        #expect(memUsed < 2 * 1024 * 1024) // <2MB
    }

    @Test func testCacheHitRate() async throws {
        let imageData = Data([0xFF, 0xD8, 0xFF])
        let response = HTTPURLResponse(
            url: URL(string: "https://mock.api/test")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "image/jpeg"]
        )!
        let mockSession = MockURLSession(nextData: imageData, nextResponse: response)
        let service = ImageService(urlSession: mockSession)
        let url = "https://mock.api/test"
        var hits = 0
        let total = 20
        for _ in 0..<total {
            let result = try await service.fetchImageData(from: url)
            if result == imageData { hits += 1 }
        }
        let hitRate = Double(hits) / Double(total)
        print("DEBUG: Cache hit rate: \(hitRate * 100)%")
        #expect(hitRate > 0.95)
    }

    @Test func testConcurrentRequestHandling() async throws {
        let imageData = Data([0xFF, 0xD8, 0xFF])
        let response = HTTPURLResponse(
            url: URL(string: "https://mock.api/test")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "image/jpeg"]
        )!
        let mockSession = MockURLSession(nextData: imageData, nextResponse: response)
        let service = ImageService(urlSession: mockSession)
        let url = "https://mock.api/test"
        let concurrentRequests = 100
        var results = [Bool](repeating: false, count: concurrentRequests)
        await withTaskGroup(of: (Int, Bool).self) { group in
            for i in 0..<concurrentRequests {
                group.addTask {
                    let result = try? await service.fetchImageData(from: url)
                    return (i, result == imageData)
                }
            }
            for await (i, success) in group {
                results[i] = success
            }
        }
        let successCount = results.filter { $0 }.count
        print("DEBUG: Concurrent request successes: \(successCount)/\(concurrentRequests)")
        #expect(successCount == concurrentRequests)
    }

    @Test func testCacheEfficiency() async throws {
        let imageData = Data([0xFF, 0xD8, 0xFF])
        let response = HTTPURLResponse(
            url: URL(string: "https://mock.api/test")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "image/jpeg"]
        )!
        let mockSession = MockURLSession(nextData: imageData, nextResponse: response)
        let service = ImageService(urlSession: mockSession)
        let url = "https://mock.api/test"
        // First request (cache miss)
        let _ = try await service.fetchImageData(from: url)
        // Second request (should be cache hit)
        let start = Date()
        let _ = try await service.fetchImageData(from: url)
        let elapsed = Date().timeIntervalSince(start)
        print("DEBUG: Cache hit latency: \(elapsed * 1000) ms")
        #expect(elapsed < 0.01) // <10ms for cache hit
    }
}
