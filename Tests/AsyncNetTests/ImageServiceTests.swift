import Foundation
import Testing

@testable import AsyncNet

@Suite public struct ImageServiceTests {

    @Test public func testFetchImageDataUnauthorized() async throws {
        let imageData = Data([0xFF, 0xD8, 0xFF, 0xE0])
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

    @Test public func testFetchImageDataBadMimeType() async throws {
        let imageData = Data([0xFF, 0xD8, 0xFF, 0xE0])
        let response = HTTPURLResponse(
            url: URL(string: "https://mock.api/test")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: [
                "Content-Type": "application/octet-stream", "Mime-Type": "application/octet-stream"
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

    @Test public func testUploadImageMultipartSuccess() async throws {
        let imageData = Data([0xFF, 0xD8, 0xFF, 0xE0])
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
    }

    @Test public func testUploadImageMultipartRequestValidation() async throws {
        let imageData = Data([0xFF, 0xD8, 0xFF, 0xE0])
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

        _ = try await service.uploadImageMultipart(
            imageData, to: URL(string: "https://mock.api/upload")!)

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
    }

    @Test public func testUploadImageMultipartBodyValidation() async throws {
        let imageData = Data([0xFF, 0xD8, 0xFF, 0xE0])
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

        _ = try await service.uploadImageMultipart(
            imageData, to: URL(string: "https://mock.api/upload")!)

        let recordedRequests = await mockSession.recordedRequests
        let request = recordedRequests[0]

        // Check request body
        guard let body = request.httpBody else {
            #expect(Bool(false), "Request should have a body")
            return
        }
        #expect(body.count > 0, "Request body should not be empty")

        // Verify image data is present in the body
        #expect(body.range(of: imageData) != nil, "Body should contain the original image data")
    }

    @Test public func testUploadImageMultipartBoundaryValidation() async throws {
        let imageData = Data([0xFF, 0xD8, 0xFF, 0xE0])
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

        _ = try await service.uploadImageMultipart(
            imageData, to: URL(string: "https://mock.api/upload")!)

        let recordedRequests = await mockSession.recordedRequests
        let request = recordedRequests[0]
        let contentType = request.value(forHTTPHeaderField: "Content-Type")!
        let body = request.httpBody!

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
            body.range(of: startingBoundary) != nil,
            "Body should contain starting boundary marker")

        // Check for closing boundary marker
        let closingBoundary = Data("--\(boundary)--".utf8)
        #expect(
            body.range(of: closingBoundary) != nil,
            "Body should contain closing boundary marker")
    }

    @Test public func testUploadImageMultipartStructureValidation() async throws {
        let imageData = Data([0xFF, 0xD8, 0xFF, 0xE0])
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

        _ = try await service.uploadImageMultipart(
            imageData, to: URL(string: "https://mock.api/upload")!)

        let recordedRequests = await mockSession.recordedRequests
        let request = recordedRequests[0]
        let body = request.httpBody!

        // Look for Content-Disposition header
        let dispositionMarker = Data("Content-Disposition: form-data".utf8)
        #expect(
            body.range(of: dispositionMarker) != nil,
            "Body should contain form-data disposition")

        // Look for name="file" parameter in disposition
        let nameFileMarker = Data("name=\"file\"".utf8)
        #expect(
            body.range(of: nameFileMarker) != nil, "Body should contain name=\"file\" parameter"
        )

        // Look for filename parameter
        let filenameMarker = Data("filename=".utf8)
        #expect(body.range(of: filenameMarker) != nil, "Body should contain filename parameter")

        // Look for Content-Type header
        let contentTypeMarker = Data("Content-Type:".utf8)
        #expect(
            body.range(of: contentTypeMarker) != nil,
            "Body should contain content-type for the file")
    }
}
