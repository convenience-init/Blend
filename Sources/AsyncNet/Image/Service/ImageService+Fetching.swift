import Foundation

#if canImport(UIKit)
    import UIKit
#endif
#if canImport(AppKit)
    import AppKit
#endif

// MARK: - Image Fetching Extension
extension ImageService {
    // MARK: - Image Fetching

    /// Fetches an image from the specified URL with caching support
    /// - Parameter urlString: The URL string for the image
    /// - Returns: A platform-specific image
    /// - Throws: NetworkError if the request fails
    /// Fetches image data from the specified URL with caching support
    /// - Parameter urlString: The URL string for the image
    /// - Returns: Image data
    /// - Throws: NetworkError if the request fails
    public func fetchImageData(from urlString: String) async throws -> Data {
        return try await fetchImageData(from: urlString, retryConfig: nil)
    }

    /// Fetches image data with configurable retry policy
    /// - Parameters:
    ///   - urlString: The URL string for the image
    ///   - retryConfig: Optional retry/backoff configuration. If nil, uses override configuration or default.
    /// - Returns: Image data
    /// - Throws: NetworkError if the request fails
    public func fetchImageData(from urlString: String, retryConfig: RetryConfiguration?)
        async throws -> Data {
        let effectiveRetryConfig =
            retryConfig ?? (overrideRetryConfiguration ?? RetryConfiguration())
        let cacheKey = urlString

        // Check cache first
        if let cachedData = try await checkCache(for: urlString, cacheKey: cacheKey) {
            return cachedData
        }

        // Handle deduplication and fetch
        return try await fetchWithDeduplication(
            urlString: urlString, cacheKey: cacheKey, retryConfig: effectiveRetryConfig)
    }

    /// Checks cache for existing image data
    private func checkCache(for urlString: String, cacheKey: String) async throws -> Data? {
        await evictExpiredCache()
        if let cachedData = await dataCache.object(forKey: cacheKey)?.data,
            await cacheActor.isImageCached(forKey: urlString) {
            await cacheActor.storeImageInCache(forKey: urlString)  // Update LRU
            cacheHits += 1
            return cachedData
        }
        cacheMisses += 1
        return nil
    }

    /// Handles deduplication and performs the actual network fetch
    private func fetchWithDeduplication(
        urlString: String, cacheKey: String, retryConfig: RetryConfiguration
    ) async throws -> Data {
        // Deduplication: Check for existing task or create new one
        let fetchTask: Task<Data, Error>
        if let existingTask = inFlightImageTasks[urlString] {
            return try await existingTask.value
        } else {
            fetchTask = Task {
                defer { self.removeInFlightTask(forKey: urlString) }
                return try await self.performNetworkFetch(
                    urlString: urlString, retryConfig: retryConfig)
            }

            if let existingTask = inFlightImageTasks.updateValue(fetchTask, forKey: urlString) {
                fetchTask.cancel()
                return try await existingTask.value
            }
        }

        let data = try await fetchTask.value

        // Cache the result
        await dataCache.setObject(SendableData(data), forKey: cacheKey, cost: data.count)
        await cacheActor.storeImageInCache(forKey: urlString)

        return data
    }

    /// Performs the actual network request with retry logic
    private func performNetworkFetch(urlString: String, retryConfig: RetryConfiguration)
        async throws -> Data {
        try await withRetry(config: retryConfig) {
            guard let url = URL(string: urlString), let scheme = url.scheme,
                !scheme.isEmpty, let host = url.host, !host.isEmpty
            else {
                throw NetworkError.invalidEndpoint(reason: "Invalid image URL: \(urlString)")
            }

            var request = URLRequest(url: url)
            let interceptors = await self.interceptors
            for interceptor in interceptors {
                request = await interceptor.willSend(request: request)
            }

            let (data, response) = try await self.urlSession.data(for: request)
            return try await self.validateResponse(data: data, response: response)
        }
    }

    /// Validates HTTP response and returns data or throws appropriate error
    private func validateResponse(data: Data, response: URLResponse) throws -> Data {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.noResponse
        }

        return try validateHTTPStatus(data: data, response: httpResponse)
    }

    /// Validates HTTP status code and processes response accordingly
    private func validateHTTPStatus(data: Data, response: HTTPURLResponse) throws -> Data {
        switch response.statusCode {
        case 200...299:
            return try validateImageResponse(data: data, response: response)
        case 400:
            throw NetworkError.badRequest(data: data, statusCode: response.statusCode)
        case 401:
            throw NetworkError.unauthorized(data: data, statusCode: response.statusCode)
        case 403:
            throw NetworkError.forbidden(data: data, statusCode: response.statusCode)
        case 404:
            throw NetworkError.notFound(data: data, statusCode: response.statusCode)
        case 429:
            throw NetworkError.rateLimited(data: data, statusCode: response.statusCode)
        case 500...599:
            throw NetworkError.serverError(statusCode: response.statusCode, data: data)
        default:
            throw NetworkError.httpError(statusCode: response.statusCode, data: data)
        }
    }

    /// Validates image response for successful HTTP status codes
    private func validateImageResponse(data: Data, response: HTTPURLResponse) throws -> Data {
        guard let mimeType = response.mimeType else {
            throw NetworkError.badMimeType("no mimeType found")
        }

        let validMimeTypes = [
            "image/jpeg", "image/png", "image/gif", "image/webp", "image/heic"
        ]
        guard validMimeTypes.contains(mimeType) else {
            throw NetworkError.badMimeType(mimeType)
        }
        return data
    }

    /// Converts image data to PlatformImage
    /// - Parameter data: Image data
    /// - Returns: PlatformImage (UIImage/NSImage)
    /// - Note: This method runs on the current actor. If the result is used for UI updates,
    ///   ensure the call is dispatched to the main actor.
    public static func platformImage(from data: Data) -> PlatformImage? {
        return PlatformImage(data: data)
    }

    /// Converts a PlatformImage to JPEG data with specified compression quality
    /// - Parameters:
    ///   - image: The platform image to convert
    ///   - compressionQuality: JPEG compression quality (0.0 to 1.0, default 0.8)
    ///   - Returns: JPEG data or nil if conversion fails
    public static func platformImageToData(
        _ image: PlatformImage, compressionQuality: CGFloat = 0.8
    ) -> Data? {
        #if canImport(UIKit)
            return image.jpegData(compressionQuality: compressionQuality)
        #elseif canImport(AppKit)
            guard let tiffData = image.tiffRepresentation,
                let bitmap = NSBitmapImageRep(data: tiffData)
            else { return nil }
            let properties: [NSBitmapImageRep.PropertyKey: Any] = [
                .compressionFactor: compressionQuality
            ]
            return bitmap.representation(
                using: NSBitmapImageRep.FileType.jpeg, properties: properties)
        #else
            return nil
        #endif
    }
}
