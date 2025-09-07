import Foundation
import Testing

@testable import Blend

@Suite("Image Service Error Tests")
public struct ImageServiceErrorTests {
    @Test public func testFetchImageDataNetworkError() async throws {
        let mockSession = MockURLSession(
            nextData: nil, nextResponse: nil, nextError: URLError(.notConnectedToInternet))
        let service = ImageService(
            imageCacheCountLimit: 100,
            imageCacheTotalCostLimit: 50 * 1024 * 1024,
            dataCacheCountLimit: 200,
            dataCacheTotalCostLimit: 100 * 1024 * 1024,
            urlSession: mockSession
        )

        do {
            _ = try await service.fetchImageData(from: "https://mock.api/test")
            #expect(Bool(false), "Expected networkUnavailable but none was thrown")
        } catch let error as NetworkError {
            guard case .networkUnavailable = error else {
                #expect(Bool(false), "Expected networkUnavailable but got \(error)")
                return
            }
        } catch {
            #expect(Bool(false), "Expected NetworkError but got \(error)")
        }
    }

    @Test public func testFetchImageDataHTTPError() async throws {
        let response = HTTPURLResponse(
            url: URL(string: "https://mock.api/test")!,
            statusCode: 404,
            httpVersion: nil,
            headerFields: nil
        )!
        let mockSession = MockURLSession(nextData: Data(), nextResponse: response)
        let service = ImageService(
            imageCacheCountLimit: 100,
            imageCacheTotalCostLimit: 50 * 1024 * 1024,
            dataCacheCountLimit: 200,
            dataCacheTotalCostLimit: 100 * 1024 * 1024,
            urlSession: mockSession
        )

        do {
            _ = try await service.fetchImageData(from: "https://mock.api/test")
            #expect(Bool(false), "Expected notFound but none was thrown")
        } catch let error as NetworkError {
            guard case .notFound(let data, let statusCode) = error else {
                #expect(Bool(false), "Expected notFound but got \(error)")
                return
            }
            #expect(statusCode == 404)
            #expect(data?.isEmpty ?? true)
        } catch {
            #expect(Bool(false), "Expected NetworkError but got \(error)")
        }
    }

    @Test public func testUploadImageDataNetworkError() async throws {
        let mockSession = MockURLSession(
            nextData: nil, nextResponse: nil, nextError: URLError(.notConnectedToInternet))
        let service = ImageService(
            imageCacheCountLimit: 100,
            imageCacheTotalCostLimit: 50 * 1024 * 1024,
            dataCacheCountLimit: 200,
            dataCacheTotalCostLimit: 100 * 1024 * 1024,
            urlSession: mockSession
        )

        let imageData = Data([0xFF, 0xD8, 0xFF, 0xE0])  // JPEG header
        do {
            _ = try await service.uploadImageBase64(
                imageData,
                to: URL(string: "https://mock.api/upload")!
            )
            #expect(Bool(false), "Expected URLError but none was thrown")
        } catch let error as URLError {
            #expect(error.code == .notConnectedToInternet)
        } catch {
            #expect(Bool(false), "Expected URLError but got \(error)")
        }
    }

    @Test public func testUploadImageDataHTTPError() async throws {
        let response = HTTPURLResponse(
            url: URL(string: "https://mock.api/upload")!,
            statusCode: 500,
            httpVersion: nil,
            headerFields: nil
        )!
        let mockSession = MockURLSession(nextData: Data(), nextResponse: response)
        let service = ImageService(
            imageCacheCountLimit: 100,
            imageCacheTotalCostLimit: 50 * 1024 * 1024,
            dataCacheCountLimit: 200,
            dataCacheTotalCostLimit: 100 * 1024 * 1024,
            urlSession: mockSession
        )

        let imageData = Data([0xFF, 0xD8, 0xFF, 0xE0])  // JPEG header
        do {
            _ = try await service.uploadImageBase64(
                imageData,
                to: URL(string: "https://mock.api/upload")!
            )
            #expect(Bool(false), "Expected serverError but none was thrown")
        } catch let error as NetworkError {
            guard case .serverError(let statusCode, let data) = error else {
                #expect(Bool(false), "Expected serverError but got \(error)")
                return
            }
            #expect(statusCode == 500)
            #expect(data?.isEmpty ?? true)
        } catch {
            #expect(Bool(false), "Expected NetworkError but got \(error)")
        }
    }
}
