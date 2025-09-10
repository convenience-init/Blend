import Foundation
import Testing

@testable import Blend

#if canImport(Darwin)
    import Darwin.Mach
#endif

/// Get current resident memory size in bytes using Mach task_info API
public func currentResidentSizeBytes() -> UInt64? {
    #if canImport(Darwin)
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(
                    mach_task_self_,
                    task_flavor_t(MACH_TASK_BASIC_INFO),
                    $0,
                    &count)
            }
        }
        return result == KERN_SUCCESS ? UInt64(info.resident_size) : nil
    #else
        return nil
    #endif
}

@Suite("Image Service Performance Tests")
public struct ImageServicePerformanceTests {

    @Test public func testNetworkLatencyColdStart() async throws {
        let imageData = Data([0xFF, 0xD8, 0xFF, 0xE0])
        let response = HTTPURLResponse(
            url: URL(string: "https://mock.api/test")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "image/jpeg"]
        )!
        let mockSession = MockURLSession(nextData: imageData, nextResponse: response)
        let service = ImageService(
            imageCacheCountLimit: 100,
            imageCacheTotalCostLimit: 50 * 1024 * 1024,
            dataCacheCountLimit: 200,
            dataCacheTotalCostLimit: 100 * 1024 * 1024,
            urlSession: mockSession
        )
        let start = ContinuousClock().now
        _ = try await service.fetchImageData(from: "https://mock.api/test")
        let duration = ContinuousClock().now - start
        let elapsedSeconds =
            Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18

        // Be more lenient in CI environments due to resource constraints
        let maxLatency = ProcessInfo.processInfo.environment["CI"] != nil ? 1.0 : 0.5  // 1000ms in CI, 500ms locally

        // Record timing information for test visibility
        #expect(
            elapsedSeconds < maxLatency,
            """
            Cold start latency should be less than \(Int(maxLatency * 1000))ms in \
            \(ProcessInfo.processInfo.environment["CI"] != nil ? "CI" : "local") environment, \
            was \(elapsedSeconds * 1000)ms
            """
        )

        #expect(duration < .milliseconds(Int(maxLatency * 1000)))  // Adjust timeout based on environment
    }

    @Test public func testCachingAvoidsRepeatedNetworkCalls() async throws {
        let imageData = Data(repeating: 0xFF, count: 1024 * 1024)  // 1MB image
        let response = HTTPURLResponse(
            url: URL(string: "https://mock.api/test")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "image/jpeg"]
        )!
        let mockSession = MockURLSession(nextData: imageData, nextResponse: response)
        let service = ImageService(
            imageCacheCountLimit: 100,
            imageCacheTotalCostLimit: 50 * 1024 * 1024,
            dataCacheCountLimit: 200,
            dataCacheTotalCostLimit: 100 * 1024 * 1024,
            urlSession: mockSession
        )

        // Test that caching works by making multiple requests
        let url = "https://mock.api/test"

        // First request (cache miss)
        let result1 = try await service.fetchImageData(from: url)
        #expect(result1 == imageData)

        // Second request (should be cache hit)
        let result2 = try await service.fetchImageData(from: url)
        #expect(result2 == imageData)

        // Third request (should still be cache hit)
        let result3 = try await service.fetchImageData(from: url)
        #expect(result3 == imageData)

        // Verify that only 1 network call was made despite 3 requests
        #expect(await mockSession.callCount == 1)

        // Verify that the cache is working by checking recorded requests
        let recordedRequests = await mockSession.recordedRequests
        #expect(recordedRequests.count == 1, "Only one network request should have been made")
    }

    @Test public func testCachingMemoryUsage() async throws {
        let imageData = Data(repeating: 0xFF, count: 1024 * 1024)  // 1MB image
        let response = HTTPURLResponse(
            url: URL(string: "https://mock.api/test")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "image/jpeg"]
        )!
        let mockSession = MockURLSession(nextData: imageData, nextResponse: response)
        let service = ImageService(
            imageCacheCountLimit: 100,
            imageCacheTotalCostLimit: 50 * 1024 * 1024,
            dataCacheCountLimit: 200,
            dataCacheTotalCostLimit: 100 * 1024 * 1024,
            urlSession: mockSession
        )

        // Test memory usage during caching operations
        let url = "https://mock.api/test"

        // Sample memory before operations
        #if canImport(Darwin)
            let memoryBefore = currentResidentSizeBytes()
        #endif

        // First request (cache miss)
        let result1 = try await service.fetchImageData(from: url)
        #expect(result1 == imageData)

        // Second request (should be cache hit)
        let result2 = try await service.fetchImageData(from: url)
        #expect(result2 == imageData)

        // Third request (should still be cache hit)
        let result3 = try await service.fetchImageData(from: url)
        #expect(result3 == imageData)

        // Sample memory after operations
        #if canImport(Darwin)
            if let memoryBefore = memoryBefore, let memoryAfter = currentResidentSizeBytes() {
                let memoryDelta = Int64(memoryAfter) - Int64(memoryBefore)
                // Allow some memory growth but ensure it's reasonable
                // In CI environments, be more lenient due to different memory characteristics
                let maxMemoryGrowth =
                    ProcessInfo.processInfo.environment["CI"] != nil
                    ? 200 * 1024 * 1024 : 25 * 1024 * 1024  // 200MB in CI, 25MB locally

                // Skip test if memory delta is unreasonably negative (likely measurement error)
                if memoryDelta < -50 * 1024 * 1024 {  // -50MB threshold for measurement errors
                    print("Skipping memory test due to measurement anomaly: \(memoryDelta) bytes")
                    return
                }

                #expect(
                    abs(memoryDelta) < maxMemoryGrowth,
                    """
                    Memory growth should be reasonable during caching operations. \
                    Delta: \(memoryDelta) bytes (\(Double(memoryDelta) / 1024 / 1024) MB), \
                    limit: \(Double(maxMemoryGrowth) / 1024 / 1024) MB
                    """
                )
            } else {
                // Skip test if memory measurement fails
                print("Skipping memory test due to measurement failure")
            }
        #endif
    }

    @Test public func testCacheHitRate() async throws {
        let imageData = Data([0xFF, 0xD8, 0xFF, 0xE0])
        let response = HTTPURLResponse(
            url: URL(string: "https://mock.api/test")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "image/jpeg"]
        )!
        let mockSession = MockURLSession(nextData: imageData, nextResponse: response)
        let service = ImageService(
            imageCacheCountLimit: 100,
            imageCacheTotalCostLimit: 50 * 1024 * 1024,
            dataCacheCountLimit: 200,
            dataCacheTotalCostLimit: 100 * 1024 * 1024,
            urlSession: mockSession
        )
        let url = "https://mock.api/test"

        // Make multiple requests to the same URL
        for _ in 0..<20 {
            _ = try await service.fetchImageData(from: url)
        }

        // Verify that only 1 network call was made (caching worked)
        #expect(await mockSession.callCount == 1)
    }

    @Test public func testConcurrentRequestHandling() async throws {
        let imageData = Data([0xFF, 0xD8, 0xFF, 0xE0])
        let response = HTTPURLResponse(
            url: URL(string: "https://mock.api/test")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "image/jpeg"]
        )!
        let mockSession = MockURLSession(nextData: imageData, nextResponse: response)
        let service = ImageService(
            imageCacheCountLimit: 100,
            imageCacheTotalCostLimit: 50 * 1024 * 1024,
            dataCacheCountLimit: 200,
            dataCacheTotalCostLimit: 100 * 1024 * 1024,
            urlSession: mockSession
        )
        let url = "https://mock.api/test"
        let concurrentRequests = 100
        let maxConcurrentTasks = 10
        var results = [Bool](repeating: false, count: concurrentRequests)

        // Use deterministic concurrency limiting with TaskGroup
        try await withThrowingTaskGroup(of: (Int, Bool).self) { group in
            var activeTasks = 0

            for requestIndex in 0..<concurrentRequests {
                // If we've reached the concurrency limit, wait for a task to complete
                while activeTasks >= maxConcurrentTasks {
                    if let completedResult = try await group.next() {
                        let (completedIndex, success) = completedResult
                        results[completedIndex] = success
                        activeTasks -= 1
                    } else {
                        // Group is empty, break out of waiting
                        break
                    }
                }

                // Add the next task
                group.addTask {
                    let result = try await service.fetchImageData(from: url)
                    let success = result == imageData
                    return (requestIndex, success)
                }
                activeTasks += 1
            }

            // Collect remaining results
            for try await (resultIndex, success) in group {
                results[resultIndex] = success
            }
        }
        let successCount = results.filter { $0 }.count

        // Record concurrent request results for test visibility
        #expect(
            successCount == concurrentRequests,
            "All \(concurrentRequests) concurrent requests should succeed, got \(successCount) successes"
        )
    }
}
