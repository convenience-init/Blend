import Testing
import Foundation
// Platform-specific imports for memory usage
#if canImport(Darwin)
import Darwin
#endif
@testable import AsyncNet
#if canImport(UIKit)
import UIKit
#elseif canImport(Cocoa)
import Cocoa
#endif
#if canImport(SwiftUI)
import SwiftUI
#endif


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
        func residentMemory() -> UInt64? {
        #if canImport(Darwin)
            var info = mach_task_basic_info()
            var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
            let kerr = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                    task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
                }
            }
            return kerr == KERN_SUCCESS ? info.resident_size : nil
        #else
            return nil
        #endif
        }
        guard let memBefore = residentMemory() else {
            #expect(Bool(false), "ERROR: Could not read resident memory before fetch")
            return
        }
        _ = try await service.fetchImageData(from: "https://mock.api/test")
        guard let memAfter = residentMemory() else {
            #expect(Bool(false), "ERROR: Could not read resident memory after fetch")
            return
        }
        let memUsed = memAfter > memBefore ? memAfter - memBefore : 0
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
        print("DEBUG: Network call count: \(mockSession.callCount)")
        #expect(hitRate > 0.95)
        #expect(mockSession.callCount == 1)
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
        let _ = try await service.fetchImageData(from: url)
        print("DEBUG: Network call count: \(mockSession.callCount)")
        #expect(mockSession.callCount == 1)
    }
}
