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
        async throws -> Data
    {
        // Determine which retry configuration to use:
        // 1. Explicitly passed configuration takes precedence
        // 2. Override configuration if set
        // 3. Default configuration as fallback
        let effectiveRetryConfig =
            retryConfig ?? (overrideRetryConfiguration ?? RetryConfiguration())

        let cacheKey = urlString
        // Check cache for image data, evict expired
        await evictExpiredCache()
        if let cachedData = await dataCache.object(forKey: cacheKey)?.data,
            await cacheActor.isImageCached(forKey: urlString)
        {
            await cacheActor.storeImageInCache(forKey: urlString)  // Update LRU
            cacheHits += 1
            return cachedData
        }
        cacheMisses += 1

        // Deduplication: Atomically check for existing task or store new task
        // This prevents race conditions where multiple concurrent calls could create duplicate tasks
        let fetchTask: Task<Data, Error>
        if let existingTask = inFlightImageTasks[urlString] {
            // Existing task found, use it
            return try await existingTask.value
        } else {
            // No existing task, create new one
            fetchTask = Task<Data, Error> {
                () async throws -> Data in
                // Capture strong reference to self for the entire task execution
                defer {
                    // Always remove the task from inFlightImageTasks when it completes
                    // This ensures cleanup happens regardless of success, failure, or cancellation
                    self.removeInFlightTask(forKey: urlString)
                }

                let data = try await self.withRetry(config: effectiveRetryConfig) {
                    guard let url = URL(string: urlString),
                        let scheme = url.scheme, !scheme.isEmpty,
                        let host = url.host, !host.isEmpty
                    else {
                        throw NetworkError.invalidEndpoint(
                            reason: "Invalid image URL: \(urlString)")
                    }

                    var request = URLRequest(url: url)
                    // Apply request interceptors
                    let interceptors = await self.interceptors
                    for interceptor in interceptors {
                        request = await interceptor.willSend(request: request)
                    }

                    let (data, response) = try await self.urlSession.data(for: request)
                    guard let httpResponse = response as? HTTPURLResponse else {
                        throw NetworkError.noResponse
                    }

                    switch httpResponse.statusCode {
                    case 200...299:
                        guard let mimeType = httpResponse.mimeType else {
                            throw NetworkError.badMimeType("no mimeType found")
                        }

                        let validMimeTypes = [
                            "image/jpeg", "image/png", "image/gif", "image/webp", "image/heic",
                        ]
                        guard validMimeTypes.contains(mimeType) else {
                            throw NetworkError.badMimeType(mimeType)
                        }
                        return data

                    case 400:
                        throw NetworkError.badRequest(
                            data: data, statusCode: httpResponse.statusCode)
                    case 401:
                        throw NetworkError.unauthorized(
                            data: data, statusCode: httpResponse.statusCode)
                    case 403:
                        throw NetworkError.forbidden(
                            data: data, statusCode: httpResponse.statusCode)
                    case 404:
                        throw NetworkError.notFound(data: data, statusCode: httpResponse.statusCode)
                    case 429:
                        throw NetworkError.rateLimited(
                            data: data, statusCode: httpResponse.statusCode)
                    case 500...599:
                        throw NetworkError.serverError(
                            statusCode: httpResponse.statusCode, data: data)
                    default:
                        throw NetworkError.httpError(
                            statusCode: httpResponse.statusCode, data: data)
                    }
                }
                return data
            }

            // Atomically store the task - if another task was stored concurrently, use that instead
            if let existingTask = inFlightImageTasks.updateValue(fetchTask, forKey: urlString) {
                // Another task was stored concurrently, cancel our task and use the existing one
                fetchTask.cancel()
                return try await existingTask.value
            }
        }

        let data = try await fetchTask.value

        // Cache the data back in the actor context
        await dataCache.setObject(SendableData(data), forKey: cacheKey, cost: data.count)
        await cacheActor.storeImageInCache(forKey: urlString)

        return data
    }

    /// Converts image data to PlatformImage
    /// - Parameter data: Image data
    /// - Returns: PlatformImage (UIImage/NSImage)
    /// - Note: This method runs on the current actor. If the result is used for UI updates, ensure the call is dispatched to the main actor.
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
