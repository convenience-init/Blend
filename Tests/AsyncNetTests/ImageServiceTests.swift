import Foundation
import Testing

@testable import AsyncNet

#if canImport(Darwin)
    import Darwin
    import Darwin.Mach

    /// Get current resident memory size in bytes using Mach APIs
    func currentResidentSizeBytes() -> UInt64? {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<mach_task_basic_info_data_t>.size / MemoryLayout<natural_t>.size)
        let kerr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return kerr == KERN_SUCCESS ? UInt64(info.resident_size) : nil
    }
#endif

@Suite("Image Service Tests")
struct ImageServiceTests {

    @Test func testFetchImageDataSuccess() async throws {
        // Prepare mock image data and response
        let imageData = Data([0xFF, 0xD8, 0xFF])  // JPEG header
        let response = HTTPURLResponse(
            url: URL(string: "https://mock.api/test")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "image/jpeg", "Mime-Type": "image/jpeg"]
        )!
        let mockSession = MockURLSession(nextData: imageData, nextResponse: response)
        let service = ImageService(
            imageCacheCountLimit: 100,
            imageCacheTotalCostLimit: 50 * 1024 * 1024,
            dataCacheCountLimit: 200,
            dataCacheTotalCostLimit: 100 * 1024 * 1024,
            urlSession: mockSession
        )
        let result = try await service.fetchImageData(from: "https://mock.api/test")
        #expect(result == imageData)
    }

    @Test func testFetchImageDataInvalidURL() async throws {
        let mockSession = MockURLSession(nextData: Data(), nextResponse: nil)
        let service = ImageService(
            imageCacheCountLimit: 100,
            imageCacheTotalCostLimit: 50 * 1024 * 1024,
            dataCacheCountLimit: 200,
            dataCacheTotalCostLimit: 100 * 1024 * 1024,
            urlSession: mockSession
        )

        do {
            _ = try await service.fetchImageData(from: "not a url")
            #expect(Bool(false), "Expected invalidEndpoint error but none was thrown")
        } catch let error as NetworkError {
            guard case .invalidEndpoint(let reason) = error else {
                #expect(Bool(false), "Expected invalidEndpoint error but got \(error)")
                return
            }
            #expect(
                reason.contains("Invalid image URL"),
                "Error reason should mention invalid image URL")
            #expect(
                reason.contains("not a url"), "Error reason should contain the invalid URL string")
        } catch {
            #expect(Bool(false), "Expected NetworkError but got \(error)")
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
        let service = ImageService(
            imageCacheCountLimit: 100,
            imageCacheTotalCostLimit: 50 * 1024 * 1024,
            dataCacheCountLimit: 200,
            dataCacheTotalCostLimit: 100 * 1024 * 1024,
            urlSession: mockSession
        )
        await #expect(throws: NetworkError.unauthorized(data: imageData, statusCode: 401)) {
            _ = try await service.fetchImageData(from: "https://mock.api/test")
        }
    }

    @Test func testFetchImageDataBadMimeType() async throws {
        let imageData = Data([0xFF, 0xD8, 0xFF])
        let response = HTTPURLResponse(
            url: URL(string: "https://mock.api/test")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: [
                "Content-Type": "application/octet-stream", "Mime-Type": "application/octet-stream",
            ]
        )!
        let mockSession = MockURLSession(nextData: imageData, nextResponse: response)
        let service = ImageService(
            imageCacheCountLimit: 100,
            imageCacheTotalCostLimit: 50 * 1024 * 1024,
            dataCacheCountLimit: 200,
            dataCacheTotalCostLimit: 100 * 1024 * 1024,
            urlSession: mockSession
        )

        do {
            _ = try await service.fetchImageData(from: "https://mock.api/test")
            #expect(Bool(false), "Expected badMimeType error but none was thrown")
        } catch let error as NetworkError {
            guard case .badMimeType(let mimeType) = error else {
                #expect(Bool(false), "Expected badMimeType error but got \(error)")
                return
            }
            #expect(
                mimeType == "application/octet-stream", "MIME type should match the response header"
            )
        } catch {
            #expect(Bool(false), "Expected NetworkError but got \(error)")
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
        let service = ImageService(
            imageCacheCountLimit: 100,
            imageCacheTotalCostLimit: 50 * 1024 * 1024,
            dataCacheCountLimit: 200,
            dataCacheTotalCostLimit: 100 * 1024 * 1024,
            urlSession: mockSession
        )
        let result = try await service.uploadImageMultipart(
            imageData, to: URL(string: "https://mock.api/upload")!)
        #expect(result == imageData)

        // Verify request was formed correctly
        let recordedRequests = await mockSession.recordedRequests
        #expect(recordedRequests.count == 1, "Should have made exactly one request")

        let request = recordedRequests[0]
        #expect(request.httpMethod == "POST", "HTTP method should be POST")

        // Verify the request URL
        let expectedURL = URL(string: "https://mock.api/upload")!
        #expect(request.url == expectedURL, "Request URL should match the expected upload endpoint")

        // Check Content-Type header
        guard let contentType = request.value(forHTTPHeaderField: "Content-Type") else {
            #expect(Bool(false), "Content-Type header should be present")
            return
        }
        #expect(
            contentType.hasPrefix("multipart/form-data"),
            "Content-Type should start with multipart/form-data")
        #expect(contentType.contains("boundary="), "Content-Type should contain boundary parameter")

        // Check request body
        guard let body = request.httpBody else {
            #expect(Bool(false), "Request should have a body")
            return
        }
        #expect(body.count > 0, "Request body should not be empty")

        // Check for multipart markers in raw bytes
        let bodyData = body

        // Parse boundary from Content-Type header
        guard let boundaryRange = contentType.range(of: "boundary=") else {
            #expect(Bool(false), "Content-Type should contain boundary parameter")
            return
        }
        let boundaryStart = boundaryRange.upperBound

        // Find the end of the boundary value (either next ';' or end of string)
        let boundaryEnd: String.Index
        if let semicolonIndex = contentType[boundaryStart...].firstIndex(of: ";") {
            boundaryEnd = semicolonIndex
        } else {
            boundaryEnd = contentType.endIndex
        }

        // Extract and clean the boundary value
        var boundary = String(contentType[boundaryStart..<boundaryEnd])
        boundary = boundary.trimmingCharacters(in: .whitespacesAndNewlines)
        boundary = boundary.trimmingCharacters(in: CharacterSet(charactersIn: "\""))

        #expect(!boundary.isEmpty, "Boundary should not be empty")

        // Check for starting boundary marker
        let startingBoundary = Data("--\(boundary)".utf8)
        #expect(
            bodyData.range(of: startingBoundary) != nil,
            "Body should contain starting boundary marker")

        // Check for closing boundary marker
        let closingBoundary = Data("--\(boundary)--".utf8)
        #expect(
            bodyData.range(of: closingBoundary) != nil,
            "Body should contain closing boundary marker")

        // Look for Content-Disposition header
        let dispositionMarker = Data("Content-Disposition: form-data".utf8)
        #expect(
            bodyData.range(of: dispositionMarker) != nil,
            "Body should contain form-data disposition")

        // Look for name="file" parameter in disposition
        let nameFileMarker = Data("name=\"file\"".utf8)
        #expect(
            bodyData.range(of: nameFileMarker) != nil, "Body should contain name=\"file\" parameter"
        )

        // Look for filename parameter
        let filenameMarker = Data("filename=".utf8)
        #expect(bodyData.range(of: filenameMarker) != nil, "Body should contain filename parameter")

        // Look for Content-Type header
        let contentTypeMarker = Data("Content-Type:".utf8)
        #expect(
            bodyData.range(of: contentTypeMarker) != nil,
            "Body should contain content-type for the file")

        // Verify image data is present in the body
        #expect(bodyData.range(of: imageData) != nil, "Body should contain the original image data")
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
        let service = ImageService(
            imageCacheCountLimit: 100,
            imageCacheTotalCostLimit: 50 * 1024 * 1024,
            dataCacheCountLimit: 200,
            dataCacheTotalCostLimit: 100 * 1024 * 1024,
            urlSession: mockSession
        )
        let result = try await service.uploadImageBase64(
            imageData, to: URL(string: "https://mock.api/upload")!)
        #expect(result == imageData)

        // Verify request was formed correctly
        let recordedRequests = await mockSession.recordedRequests
        #expect(recordedRequests.count == 1, "Should have made exactly one request")

        let request = recordedRequests[0]
        #expect(request.httpMethod == "POST", "HTTP method should be POST")

        // Verify the request URL
        let expectedURL = URL(string: "https://mock.api/upload")!
        #expect(request.url == expectedURL, "Request URL should match the expected upload endpoint")

        // Check Content-Type header
        let contentType = request.value(forHTTPHeaderField: "Content-Type")
        #expect(contentType == "application/json", "Content-Type should be application/json")

        // Check request body
        guard let body = request.httpBody else {
            #expect(Bool(false), "Request should have a body")
            return
        }
        #expect(body.count > 0, "Request body should not be empty")

        // Parse and validate JSON structure
        let jsonObject = try JSONSerialization.jsonObject(with: body, options: []) as? [String: Any]
        guard let json = jsonObject else {
            #expect(Bool(false), "Request body should be valid JSON")
            return
        }

        // Check for expected fields
        #expect(json["fieldName"] as? String == "file", "Should contain fieldName field")
        #expect(json["fileName"] as? String == "image.jpg", "Should contain fileName field")

        // Check compressionQuality with floating-point tolerance
        if let compressionQuality = json["compressionQuality"] as? Double {
            #expect(
                abs(compressionQuality - 0.8) < 1e-10,
                "Should contain compressionQuality field with value close to 0.8")
        } else {
            #expect(Bool(false), "Should contain compressionQuality field as Double")
        }

        #expect(json["data"] != nil, "Should contain data field with base64 content")

        // Verify base64 data is present and non-empty
        if let base64String = json["data"] as? String {
            #expect(!base64String.isEmpty, "Base64 data should not be empty")
            // Verify it's valid base64
            let decodedData = Data(base64Encoded: base64String)
            #expect(decodedData != nil, "Base64 data should be valid")
            #expect(
                decodedData == imageData,
                "Decoded data should match original image data byte-for-byte")
        } else {
            #expect(Bool(false), "Data field should be a string")
        }
    }

    @Test func testUploadImageMultipartPayloadTooLarge() async throws {
        // Use defer to ensure config is always restored, even if test fails
        defer {
            Task {
                await AsyncNetConfig.shared.resetMaxUploadSize()
            }
        }

        // Set a small but valid max upload size for testing (minimum is 1024 bytes = 1KB)
        try await AsyncNetConfig.shared.setMaxUploadSize(1024)  // 1KB

        let largeImageData = Data(repeating: 0xFF, count: 2048)  // 2KB, exceeds 1KB limit
        let mockResponse = HTTPURLResponse(
            url: URL(string: "https://mock.api/upload")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )
        let mockSession = MockURLSession(nextData: Data(), nextResponse: mockResponse)
        let service = ImageService(
            imageCacheCountLimit: 100,
            imageCacheTotalCostLimit: 50 * 1024 * 1024,
            dataCacheCountLimit: 200,
            dataCacheTotalCostLimit: 100 * 1024 * 1024,
            urlSession: mockSession
        )

        // Assert that uploadImageMultipart throws NetworkError.payloadTooLarge with expected size/limit
        await #expect(throws: NetworkError.payloadTooLarge(size: 2048, limit: 1024)) {
            _ = try await service.uploadImageMultipart(
                largeImageData, to: URL(string: "https://mock.api/upload")!)
        }

        // Assert that MockURLSession recorded no request/was not invoked
        // This ensures the network layer was never called when the pre-check failed
        #expect(
            await mockSession.callCount == 0,
            "Network layer should not be invoked when payload size exceeds limit")
        #expect(
            await mockSession.recordedRequests.isEmpty,
            "No network requests should be recorded when payload size exceeds limit")
    }

    @Test func testUploadImageBase64PayloadTooLarge() async throws {
        // Use defer to ensure config is always restored, even if test fails
        defer {
            Task {
                await AsyncNetConfig.shared.resetMaxUploadSize()
            }
        }

        // Set a small but valid max upload size for testing (minimum is 1024 bytes = 1KB)
        try await AsyncNetConfig.shared.setMaxUploadSize(1024)  // 1KB

        let largeImageData = Data(repeating: 0xFF, count: 2048)  // 2KB, exceeds 1KB limit
        let mockSession = MockURLSession(nextData: Data(), nextResponse: nil)
        let service = ImageService(
            imageCacheCountLimit: 100,
            imageCacheTotalCostLimit: 50 * 1024 * 1024,
            dataCacheCountLimit: 200,
            dataCacheTotalCostLimit: 100 * 1024 * 1024,
            urlSession: mockSession
        )

        // Test that uploadImageBase64 throws NetworkError.payloadTooLarge
        do {
            _ = try await service.uploadImageBase64(
                largeImageData, to: URL(string: "https://mock.api/upload")!)
            #expect(Bool(false), "Expected payloadTooLarge error but none was thrown")
        } catch let error as NetworkError {
            // Verify the error is payloadTooLarge with correct properties
            guard case .payloadTooLarge(let reportedSize, let reportedLimit) = error else {
                #expect(Bool(false), "Expected payloadTooLarge error, got: \(error)")
                return
            }

            // Verify the limit matches our configured value
            #expect(reportedLimit == 1024, "Error limit should match configured max upload size")

            // Verify the reported size is reasonable (should be >= original data size or at least > limit)
            #expect(
                reportedSize >= largeImageData.count || reportedSize > reportedLimit,
                "Reported size (\(reportedSize)) should be >= original data size (\(largeImageData.count)) or > limit (\(reportedLimit))")
        } catch {
            #expect(
                Bool(false), "Expected NetworkError.payloadTooLarge, got different error: \(error)")
        }

        // Assert that MockURLSession recorded zero network requests
        // This ensures the network layer was never called when the pre-check failed
        #expect(
            await mockSession.callCount == 0,
            "Network layer should not be invoked when payload size exceeds limit")
        #expect(
            await mockSession.recordedRequests.isEmpty,
            "No network requests should be recorded when payload size exceeds limit")
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
        print("DEBUG: Cold start latency: \(elapsedSeconds * 1000) ms")
        #expect(duration < .seconds(0.1))  // <100ms for mock network call
    }

    @Test func testCachingAvoidsRepeatedNetworkCalls() async throws {
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

    @Test func testCachingMemoryUsage() async throws {
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
                print(
                    "DEBUG: Memory delta during caching test: \(memoryDelta) bytes (\(Double(memoryDelta) / 1024 / 1024) MB)"
                )
                // Allow some memory growth but ensure it's reasonable (less than 10MB growth for 1MB cached data)
                #expect(
                    abs(memoryDelta) < 10 * 1024 * 1024,
                    "Memory growth should be reasonable during caching operations")
            }
        #endif
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

    @Test func testConcurrentRequestHandling() async throws {
        let imageData = Data([0xFF, 0xD8, 0xFF])
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
        await withTaskGroup(of: (Int, Bool).self) { group in
            var activeTasks = 0

            for i in 0..<concurrentRequests {
                // If we've reached the concurrency limit, wait for a task to complete
                while activeTasks >= maxConcurrentTasks {
                    if let completedResult = await group.next() {
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
                    let result = try? await service.fetchImageData(from: url)
                    let success = result == imageData
                    return (i, success)
                }
                activeTasks += 1
            }

            // Collect remaining results
            for await (i, success) in group {
                results[i] = success
            }
        }
        let successCount = results.filter { $0 }.count
        print("DEBUG: Concurrent request successes: \(successCount)/\(concurrentRequests)")
        #expect(successCount == concurrentRequests)
    }
}
