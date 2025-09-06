#if canImport(UIKit)
    import UIKit
    public typealias PlatformImage = UIImage
#elseif canImport(AppKit)
    import AppKit
    public typealias PlatformImage = NSImage
#endif
#if canImport(SwiftUI)
    import SwiftUI
#endif

/// Shared URLSession instance with optimized caching configuration
/// Created outside actor isolation to avoid expensive actor-hop overhead
private let sharedURLSession: URLSession = {
    let configuration = URLSessionConfiguration.default
    configuration.requestCachePolicy = .useProtocolCachePolicy
    configuration.urlCache = URLCache(
        memoryCapacity: 10 * 1024 * 1024,  // 10MB memory cache
        diskCapacity: 100 * 1024 * 1024,  // 100MB disk cache
        diskPath: nil
    )
    return URLSession(configuration: configuration)
}()

/// A comprehensive, actor-isolated image service for downloading, uploading, and caching images.
///
/// `ImageService` provides strict Swift 6 concurrency, dependency injection, platform abstraction (UIKit/SwiftUI), request/response interceptors, LRU caching, retry/backoff, and deduplication for all image operations.
///
/// - Important: All APIs are actor-isolated and Sendable for thread safety and strict concurrency compliance.
/// - Note: Use dependency injection for testability and platform abstraction. Supports UIKit (UIImage) and macOS (NSImage).
///
/// ### Usage Example
/// ```swift
/// let imageService = ImageService()
/// let image = try await imageService.fetchImageData(from: "https://example.com/image.jpg")
/// let swiftUIImage = try await ImageService.swiftUIImage(from: image)
/// ```
///
/// ### Best Practices
/// - Always inject `ImageService` for strict concurrency and testability.
/// - Use interceptors for request/response customization.
/// - Configure cache and retry policies for optimal performance.
/// - Use platformImageToData for cross-platform image conversion.
///
/// ### Migration Notes
/// - All legacy synchronous APIs are replaced by async/await and actor isolation.
/// - Use SwiftUI.Image(platformImage:) for cross-platform SwiftUI integration.
public actor ImageService {
    /// Uploads image data as a JSON payload with a base64-encoded image field
    /// - Parameters:
    ///   - imageData: The image data to upload
    ///   - url: The upload endpoint URL
    ///   - configuration: Upload configuration options
    /// - Returns: The response data from the server
    /// - Throws: NetworkError if the upload fails
    public func uploadImageBase64(
        _ imageData: Data,
        to url: URL,
        configuration: UploadConfiguration = UploadConfiguration()
    ) async throws -> Data {
        // Pre-check to avoid memory issues with very large images
        // Calculate raw data limit from configured max upload size, accounting for base64 expansion
        let configMaxUploadSize: Int
        if let instanceMaxUploadSize = maxUploadSize {
            configMaxUploadSize = instanceMaxUploadSize
        } else {
            configMaxUploadSize = await AsyncNetConfig.shared.maxUploadSize
        }
        let maxSafeRawSize: Int
        if configMaxUploadSize > 0 {
            // Base64 encoding increases size by ~33%, so raw limit = configMax * 3/4
            let calculatedRawLimit = Int(Double(configMaxUploadSize) * 3.0 / 4.0)
            maxSafeRawSize = max(calculatedRawLimit, 50 * 1024 * 1024)  // Ensure minimum 50MB fallback
        } else {
            // Fallback to original 50MB default if config is invalid
            maxSafeRawSize = 50 * 1024 * 1024
        }

        if imageData.count > maxSafeRawSize {
            #if canImport(OSLog)
                asyncNetLogger.warning(
                    "Upload rejected: Image size \(imageData.count, privacy: .public) bytes exceeds raw size limit of \(maxSafeRawSize, privacy: .public) bytes"
                )
            #else
                print(
                    "Upload rejected: Image size \(imageData.count) bytes exceeds raw size limit of \(maxSafeRawSize) bytes"
                )
            #endif
            throw NetworkError.payloadTooLarge(size: imageData.count, limit: maxSafeRawSize)
        }

        // Check upload size limit (validate post-encoding size since base64 increases size ~33%)
        let effectiveMaxUploadSize: Int
        if let instanceMaxUploadSize = maxUploadSize {
            effectiveMaxUploadSize = instanceMaxUploadSize
        } else {
            effectiveMaxUploadSize = await AsyncNetConfig.shared.maxUploadSize
        }
        let encodedSize = ((imageData.count + 2) / 3) * 4
        if encodedSize > effectiveMaxUploadSize {
            #if canImport(OSLog)
                asyncNetLogger.warning(
                    "Upload rejected: Base64-encoded image size \(encodedSize, privacy: .public) bytes exceeds limit of \(effectiveMaxUploadSize, privacy: .public) bytes (raw size: \(imageData.count, privacy: .public) bytes)"
                )
            #else
                print(
                    "Upload rejected: Base64-encoded image size \(encodedSize) bytes exceeds limit of \(effectiveMaxUploadSize) bytes (raw size: \(imageData.count) bytes)"
                )
            #endif
            throw NetworkError.payloadTooLarge(size: encodedSize, limit: effectiveMaxUploadSize)
        }

        // Determine upload strategy based on encoded size
        if encodedSize <= configuration.streamThreshold {
            // Use JSON + base64 for smaller images (existing path)
            return try await uploadImageBase64Small(
                imageData, to: url, configuration: configuration)
        } else {
            // Use streaming multipart for larger images to avoid memory spikes
            return try await uploadImageBase64Streaming(
                imageData, to: url, configuration: configuration)
        }
    }

    /// Upload small images using JSON payload with base64 encoding
    private func uploadImageBase64Small(
        _ imageData: Data,
        to url: URL,
        configuration: UploadConfiguration
    ) async throws -> Data {
        // Encode image data as base64 string
        let base64String = imageData.base64EncodedString()

        // Create type-safe payload using Codable
        let payload = UploadPayload(
            fieldName: configuration.fieldName,
            fileName: configuration.fileName,
            compressionQuality: configuration.compressionQuality,
            base64Data: base64String,
            additionalFields: configuration.additionalFields
        )

        // Validate the final JSON payload size against upload limits
        let effectiveMaxUploadSize: Int
        if let instanceMaxUploadSize = maxUploadSize {
            effectiveMaxUploadSize = instanceMaxUploadSize
        } else {
            effectiveMaxUploadSize = await AsyncNetConfig.shared.maxUploadSize
        }
        let jsonPayload = try JSONEncoder().encode(payload)
        let finalPayloadSize = jsonPayload.count

        if finalPayloadSize > effectiveMaxUploadSize {
            #if canImport(OSLog)
                asyncNetLogger.warning(
                    "Upload rejected: JSON payload size \(finalPayloadSize, privacy: .public) bytes exceeds limit of \(effectiveMaxUploadSize, privacy: .public) bytes (base64 image: \(imageData.count, privacy: .public) bytes, encoded: \(((imageData.count + 2) / 3) * 4, privacy: .public) bytes)"
                )
            #else
                print(
                    "Upload rejected: JSON payload size \(finalPayloadSize) bytes exceeds limit of \(effectiveMaxUploadSize) bytes (base64 image: \(imageData.count) bytes, encoded: \(((imageData.count + 2) / 3) * 4) bytes)"
                )
            #endif
            throw NetworkError.payloadTooLarge(
                size: finalPayloadSize, limit: effectiveMaxUploadSize)
        }

        // Warn if payload is large (accounts for JSON overhead + base64 encoding)
        let maxRecommendedSize = (effectiveMaxUploadSize * 3) / 4  // ~75% of max to account for JSON + base64 overhead
        if finalPayloadSize > maxRecommendedSize {
            #if canImport(OSLog)
                asyncNetLogger.info(
                    "Warning: Large JSON payload (\(finalPayloadSize, privacy: .public) bytes, base64 image: \(imageData.count, privacy: .public) bytes) approaches upload limit. Consider using multipart upload."
                )
            #else
                print(
                    "Warning: Large JSON payload (\(finalPayloadSize) bytes, base64 image: \(imageData.count) bytes) approaches upload limit. Consider using multipart upload."
                )
            #endif
        }

        // Create JSON request
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Apply request interceptors
        let interceptors = self.interceptors
        for interceptor in interceptors {
            request = await interceptor.willSend(request: request)
        }

        request.httpBody = jsonPayload

        let (data, response) = try await urlSession.data(for: request)

        // Apply response interceptors
        for interceptor in interceptors {
            await interceptor.didReceive(response: response, data: data)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.noResponse
        }
        switch httpResponse.statusCode {
        case 200...299:
            return data
        case 400:
            throw NetworkError.badRequest(data: data, statusCode: httpResponse.statusCode)
        case 401:
            throw NetworkError.unauthorized(data: data, statusCode: httpResponse.statusCode)
        case 403:
            throw NetworkError.forbidden(data: data, statusCode: httpResponse.statusCode)
        case 404:
            throw NetworkError.notFound(data: data, statusCode: httpResponse.statusCode)
        case 429:
            throw NetworkError.rateLimited(data: data, statusCode: httpResponse.statusCode)
        case 500...599:
            throw NetworkError.serverError(statusCode: httpResponse.statusCode, data: data)
        default:
            throw NetworkError.httpError(statusCode: httpResponse.statusCode, data: data)
        }
    }

    /// Upload large images using streaming multipart/form-data to avoid memory spikes
    private func uploadImageBase64Streaming(
        _ imageData: Data,
        to url: URL,
        configuration: UploadConfiguration
    ) async throws -> Data {
        // Log that we're using streaming upload for large images
        let encodedSize = ((imageData.count + 2) / 3) * 4
        #if canImport(OSLog)
            asyncNetLogger.info(
                "Using streaming multipart upload for large image (\(encodedSize, privacy: .public) bytes encoded, \(imageData.count, privacy: .public) bytes raw) to prevent memory spikes"
            )
        #else
            print(
                "Using streaming multipart upload for large image (\(encodedSize) bytes encoded, \(imageData.count) bytes raw) to prevent memory spikes"
            )
        #endif

        // Create multipart request
        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        // Apply request interceptors
        let interceptors = self.interceptors
        for interceptor in interceptors {
            request = await interceptor.willSend(request: request)
        }

        let boundary = "Boundary-" + UUID().uuidString
        request.setValue(
            "multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let body = try MultipartBuilder.buildMultipartBody(
            boundary: boundary, configuration: configuration, imageData: imageData)

        request.httpBody = body

        let (data, response) = try await urlSession.data(for: request)

        // Apply response interceptors
        for interceptor in interceptors {
            await interceptor.didReceive(response: response, data: data)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.noResponse
        }

        switch httpResponse.statusCode {
        case 200...299:
            return data
        case 400:
            throw NetworkError.badRequest(data: data, statusCode: httpResponse.statusCode)
        case 401:
            throw NetworkError.unauthorized(data: data, statusCode: httpResponse.statusCode)
        case 403:
            throw NetworkError.forbidden(data: data, statusCode: httpResponse.statusCode)
        case 404:
            throw NetworkError.notFound(data: data, statusCode: httpResponse.statusCode)
        case 429:
            throw NetworkError.rateLimited(data: data, statusCode: httpResponse.statusCode)
        case 500...599:
            throw NetworkError.serverError(statusCode: httpResponse.statusCode, data: data)
        default:
            throw NetworkError.httpError(statusCode: httpResponse.statusCode, data: data)
        }
    }
    // MARK: - Image Uploading

    /// Returns true if an image is cached for the given key (actor-isolated, Sendable)
    public func isImageCached(forKey key: String) async -> Bool {
        return await cacheActor.isImageCached(forKey: key)
    }
    // cacheHits and cacheMisses are public actor variables for test access
    // MARK: - Request/Response Interceptor Support

    private var interceptors: [RequestInterceptor] = []

    /// Set interceptors (replaces existing)
    public func setInterceptors(_ interceptors: [RequestInterceptor]) {
        self.interceptors = interceptors
    }

    /// Test-only stored property for overriding default retry configuration
    private var overrideRetryConfiguration: RetryConfiguration?

    /// Set retry configuration for testing purposes
    public func setRetryConfiguration(_ config: RetryConfiguration) {
        self.overrideRetryConfiguration = config
    }

    /// Clear the override retry configuration (for testing)
    public func clearRetryConfiguration() {
        self.overrideRetryConfiguration = nil
    }

    // MARK: - Enhanced Caching Configuration
    public typealias CacheConfiguration = CacheActor.CacheConfiguration

    // Retry/backoff configuration
    /// Configuration for retry/backoff logic
    public struct RetryConfiguration: Sendable {
        public let maxAttempts: Int
        public let baseDelay: TimeInterval
        public let jitter: TimeInterval
        /// Maximum delay between retry attempts (prevents unbounded exponential growth)
        public let maxDelay: TimeInterval
        /// Optional error filter: only retry for errors matching this predicate
        public let shouldRetry: (@Sendable (Error) -> Bool)?
        /// Optional custom backoff strategy: returns delay for given attempt
        public let backoff: (@Sendable (Int) -> TimeInterval)?

        public init(
            maxAttempts: Int = 3,
            baseDelay: TimeInterval = 0.5,
            jitter: TimeInterval = 0.5,
            maxDelay: TimeInterval = 30.0,
            shouldRetry: (@Sendable (Error) -> Bool)? = nil,
            backoff: (@Sendable (Int) -> TimeInterval)? = nil
        ) {
            self.maxAttempts = maxAttempts
            self.baseDelay = baseDelay
            self.jitter = jitter
            self.maxDelay = maxDelay
            self.shouldRetry = shouldRetry
            self.backoff = backoff
        }
    }

    // Helper for exponential backoff with jitter
    private func withRetry<T: Sendable>(
        config: RetryConfiguration = RetryConfiguration(),
        operation: @Sendable @escaping () async throws -> T
    ) async throws -> T {
        var attempt = 0
        var lastError: Error?
        while attempt < config.maxAttempts {
            // Check for cancellation before starting each operation
            try Task.checkCancellation()

            do {
                return try await operation()
            } catch {
                let wrappedError = await NetworkError.wrapAsync(
                    error, config: AsyncNetConfig.shared)
                lastError = wrappedError
                // Custom error filter
                if let shouldRetry = config.shouldRetry {
                    if !shouldRetry(wrappedError) { throw wrappedError }
                } else {
                    switch wrappedError {
                    case .networkUnavailable, .requestTimeout:
                        break  // eligible for retry
                    default:
                        throw wrappedError
                    }
                }
                // Check if this would be the final attempt - if so, don't sleep, just throw
                if attempt + 1 >= config.maxAttempts {
                    throw wrappedError
                }

                // Custom backoff strategy
                var delay: TimeInterval
                if let backoff = config.backoff {
                    delay = backoff(attempt)
                } else {
                    // Simplified exponential backoff with safe overflow handling
                    let exponent = min(Double(attempt), 10.0)  // Cap exponent to prevent overflow
                    let exponential = pow(2.0, exponent)
                    delay = min(config.baseDelay * exponential, config.maxDelay)
                }

                // Cap the delay to prevent unbounded exponential growth
                let cappedDelay = min(delay, config.maxDelay)
                let jitter = Double.random(in: 0...config.jitter)
                let totalDelay = cappedDelay + jitter

                // Check for cancellation before sleeping
                try Task.checkCancellation()

                // Safe conversion to nanoseconds with overflow protection
                // Clamp to a reasonable maximum (24 hours) to prevent overflow
                let maxReasonableDelay: TimeInterval = 24 * 60 * 60  // 24 hours
                let safeDelay = min(max(totalDelay, 0.0), maxReasonableDelay)

                // Additional validation before nanosecond conversion
                guard safeDelay.isFinite && !safeDelay.isNaN else {
                    throw NetworkError.customError(
                        "Invalid delay calculation",
                        details: "Delay became non-finite: \(totalDelay)"
                    )
                }

                let nanoseconds = UInt64(safeDelay * 1_000_000_000)

                try await Task.sleep(nanoseconds: nanoseconds)

                // Check for cancellation before next attempt
                try Task.checkCancellation()

                attempt += 1
                continue
            }
        }
        throw lastError ?? NetworkError.networkUnavailable
    }
    private let imageCache: Cache<String, SendableImage>
    private let dataCache: Cache<String, SendableData>
    private let injectedURLSession: URLSessionProtocol?

    // Cache actor for LRU and expiration management
    private let cacheActor: CacheActor

    // Computed property that returns the injected session or uses shared default
    private var urlSession: URLSessionProtocol {
        return injectedURLSession ?? sharedURLSession
    }

    // Deduplication: Track in-flight fetchImageData requests by URL string
    private var inFlightImageTasks: [String: Task<Data, Error>] = [:]

    /// Per-instance maximum upload size override (nil means use global AsyncNetConfig.shared.maxUploadSize)
    private let maxUploadSize: Int?

    // Cache metrics
    public var cacheHits: Int = 0
    public var cacheMisses: Int = 0

    public init(
        imageCacheCountLimit: Int = 100,
        imageCacheTotalCostLimit: Int = 50 * 1024 * 1024,
        dataCacheCountLimit: Int = 200,
        dataCacheTotalCostLimit: Int = 100 * 1024 * 1024,
        urlSession: URLSessionProtocol? = nil,
        maxUploadSize: Int? = nil
    ) {
        imageCache = Cache<String, SendableImage>(
            countLimit: imageCacheCountLimit, totalCostLimit: imageCacheTotalCostLimit)
        dataCache = Cache<String, SendableData>(
            countLimit: dataCacheCountLimit, totalCostLimit: dataCacheTotalCostLimit)
        self.cacheActor = CacheActor(
            cacheConfig: CacheConfiguration(maxLRUCount: imageCacheCountLimit))

        self.interceptors = []

        self.injectedURLSession = urlSession
        self.maxUploadSize = maxUploadSize
    }

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
                            "image/jpeg", "image/png", "image/gif", "image/webp", "image/heic"
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

    /// Uploads image data using multipart form data
    /// - Parameters:
    ///   - imageData: The image data to upload
    ///   - url: The upload endpoint URL
    ///   - configuration: Upload configuration options
    /// - Returns: The response data from the server
    /// - Throws: NetworkError if the upload fails
    public func uploadImageMultipart(
        _ imageData: Data,
        to url: URL,
        configuration: UploadConfiguration = UploadConfiguration()
    ) async throws -> Data {
        // Check upload size limit
        let effectiveMaxUploadSize: Int
        if let instanceMaxUploadSize = maxUploadSize {
            effectiveMaxUploadSize = instanceMaxUploadSize
        } else {
            effectiveMaxUploadSize = await AsyncNetConfig.shared.maxUploadSize
        }
        if imageData.count > effectiveMaxUploadSize {
            #if canImport(OSLog)
                asyncNetLogger.warning(
                    "Upload rejected: Image size \(imageData.count, privacy: .public) bytes exceeds limit of \(effectiveMaxUploadSize, privacy: .public) bytes"
                )
            #else
                print(
                    "Upload rejected: Image size \(imageData.count) bytes exceeds limit of \(effectiveMaxUploadSize) bytes"
                )
            #endif
            throw NetworkError.payloadTooLarge(size: imageData.count, limit: effectiveMaxUploadSize)
        }

        // Warn if image is large (base64 encoding will increase size by ~33%)
        let maxRecommendedSize = effectiveMaxUploadSize / 4 * 3  // ~75% of max to account for base64 overhead
        if imageData.count > maxRecommendedSize {
            #if canImport(OSLog)
                asyncNetLogger.info(
                    "Warning: Large image (\(imageData.count, privacy: .public) bytes) approaches upload limit. Base64 encoding will increase size by ~33%."
                )
            #else
                print(
                    "Warning: Large image (\(imageData.count) bytes) approaches upload limit. Base64 encoding will increase size by ~33%."
                )
            #endif
        }

        // Create multipart request
        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        // Apply request interceptors
        let interceptors = self.interceptors
        for interceptor in interceptors {
            request = await interceptor.willSend(request: request)
        }

        let boundary = "Boundary-" + UUID().uuidString
        request.setValue(
            "multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let body = try MultipartBuilder.buildMultipartBody(
            boundary: boundary, configuration: configuration, imageData: imageData)

        request.httpBody = body

        let (data, response) = try await urlSession.data(for: request)

        // Apply response interceptors
        for interceptor in interceptors {
            await interceptor.didReceive(response: response, data: data)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.noResponse
        }

        switch httpResponse.statusCode {
        case 200...299:
            return data
        case 400:
            throw NetworkError.badRequest(data: data, statusCode: httpResponse.statusCode)
        case 401:
            throw NetworkError.unauthorized(data: data, statusCode: httpResponse.statusCode)
        case 403:
            throw NetworkError.forbidden(data: data, statusCode: httpResponse.statusCode)
        case 404:
            throw NetworkError.notFound(data: data, statusCode: httpResponse.statusCode)
        case 429:
            throw NetworkError.rateLimited(data: data, statusCode: httpResponse.statusCode)
        case 500...599:
            throw NetworkError.serverError(statusCode: httpResponse.statusCode, data: data)
        default:
            throw NetworkError.httpError(statusCode: httpResponse.statusCode, data: data)
        }
    }
    // MARK: - Cache Management

    /// Retrieves a cached image for the given key
    /// - Parameter key: The cache key (typically the URL string)
    /// - Returns: The cached image if available
    public func cachedImage(forKey key: String) async -> PlatformImage? {
        let cacheKey = key

        // Check with CacheActor first
        let isValid = await cacheActor.isImageCached(forKey: key)
        if !isValid {
            return nil
        }

        // If valid, retrieve from actual cache
        if let cachedImage = await imageCache.object(forKey: cacheKey) {
            return cachedImage.image
        }

        return nil
    }

    /// Clears all cached images
    public func clearCache() async {
        await imageCache.removeAllObjects()
        await dataCache.removeAllObjects()
        await cacheActor.clearCache()
    }

    /// Stores an image in the cache for the given key
    /// - Parameters:
    ///   - image: The image to cache
    ///   - key: The cache key (typically the URL string)
    ///   - data: Optional image data to cache alongside the image
    public func storeImageInCache(_ image: PlatformImage, forKey key: String, data: Data? = nil)
        async
    {
        let cacheKey = key
        await imageCache.setObject(SendableImage(image), forKey: cacheKey)
        if let data = data {
            await dataCache.setObject(SendableData(data), forKey: cacheKey, cost: data.count)
        }
        await cacheActor.storeImageInCache(forKey: key)
    }

    /// Removes a specific image from both the image cache and data cache
    ///
    /// This method removes the cached image and its associated data for the given key from all cache layers,
    /// including the LRU tracking. If the key doesn't exist in the cache, this method silently no-ops.
    ///
    /// - Parameter key: The cache key (typically the URL string) used to identify the cached image to remove.
    ///                  Should be the same key used when storing the image.
    public func removeFromCache(key: String) async {
        let cacheKey = key
        await imageCache.removeObject(forKey: cacheKey)
        await dataCache.removeObject(forKey: cacheKey)
        await cacheActor.removeFromCache(key: key)
    }

    /// Evict expired cache entries based on maxAge using efficient heap-based expiration
    /// The expiration heap allows O(log n) insertions and O(log n) deletions while
    /// efficiently finding and removing expired items regardless of their position in LRU
    private func evictExpiredCache() async {
        await cacheActor.evictExpiredCache()
    }

    /// Update cache configuration (maxAge, maxLRUCount)
    public func updateCacheConfiguration(_ config: CacheConfiguration) async {
        await cacheActor.updateCacheConfiguration(config)
    }

    // MARK: - Private Helpers

    /// Removes an in-flight task from the tracking dictionary
    /// - Parameter key: The URL string key for the task to remove
    private func removeInFlightTask(forKey key: String) {
        inFlightImageTasks.removeValue(forKey: key)
    }

    /// Cleanup in-flight tasks when the service is deallocated
    deinit {
        // Cancel all in-flight tasks and clear the dictionary
        for (_, task) in inFlightImageTasks {
            task.cancel()
        }
        inFlightImageTasks.removeAll()
    }
}

/// Wrapper for non-Sendable image types to make them usable in Swift 6 concurrency
/// This is safe because images are immutable once created and thread-safe for reading
public struct SendableImage: @unchecked Sendable {
    public let image: PlatformImage

    public init(_ image: PlatformImage) {
        self.image = image
    }
}

/// Wrapper for non-Sendable data types to make them usable in Swift 6 concurrency
/// This is safe because Data/NSData are immutable once created and thread-safe for reading
public struct SendableData: @unchecked Sendable {
    public let data: Data

    public init(_ data: Data) {
        self.data = data
    }
}
