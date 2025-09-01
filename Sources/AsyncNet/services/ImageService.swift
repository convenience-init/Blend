#if canImport(UIKit)
    import UIKit
    public typealias PlatformImage = UIImage
#elseif canImport(Cocoa)
    import Cocoa
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
        // Check upload size limit (validate post-encoding size since base64 increases size ~33%)
        let maxUploadSize = await AsyncNetConfig.shared.maxUploadSize
        let encodedSize = ((imageData.count + 2) / 3) * 4
        if encodedSize > maxUploadSize {
            #if canImport(OSLog)
                asyncNetLogger.warning(
                    "Upload rejected: Base64-encoded image size \(encodedSize, privacy: .public) bytes exceeds limit of \(maxUploadSize, privacy: .public) bytes (raw size: \(imageData.count, privacy: .public) bytes)"
                )
            #else
                print(
                    "Upload rejected: Base64-encoded image size \(encodedSize) bytes exceeds limit of \(maxUploadSize) bytes (raw size: \(imageData.count) bytes)"
                )
            #endif
            throw NetworkError.payloadTooLarge(size: encodedSize, limit: maxUploadSize)
        }

        // Warn if encoded image is large (base64 adds ~33% overhead)
        let maxRecommendedSize = maxUploadSize / 4 * 3  // ~75% of max to account for base64 overhead
        if encodedSize > maxRecommendedSize {
            #if canImport(OSLog)
                asyncNetLogger.info(
                    "Warning: Large base64-encoded image (\(encodedSize, privacy: .public) bytes, raw: \(imageData.count, privacy: .public) bytes) approaches upload limit. Consider using multipart upload."
                )
            #else
                print(
                    "Warning: Large base64-encoded image (\(encodedSize) bytes, raw: \(imageData.count) bytes) approaches upload limit. Consider using multipart upload."
                )
            #endif
        }

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

        // Create JSON request
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Apply request interceptors
        let interceptors = self.interceptors
        for interceptor in interceptors {
            request = await interceptor.willSend(request: request)
        }

        request.httpBody = try JSONEncoder().encode(payload)

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
        case 401:
            throw NetworkError.unauthorized(data: data, statusCode: httpResponse.statusCode)
        default:
            throw NetworkError.httpError(statusCode: httpResponse.statusCode, data: data)
        }
    }
    // MARK: - Image Uploading

    /// Configuration for image upload operations
    public struct UploadConfiguration: Sendable {
        public let compressionQuality: CGFloat
        public let fieldName: String
        public let fileName: String
        public let additionalFields: [String: String]
        public let mimeType: String

        public init(
            compressionQuality: CGFloat = 0.8,
            fieldName: String = "file",
            fileName: String = "image.jpg",
            additionalFields: [String: String] = [:],
            mimeType: String? = nil
        ) {
            self.compressionQuality = compressionQuality
            self.fieldName = fieldName
            self.fileName = fileName
            self.additionalFields = additionalFields
            // Use provided mimeType or default to image/jpeg for backward compatibility
            self.mimeType = mimeType ?? "image/jpeg"
        }
    }
    /// Returns true if an image is cached for the given key (actor-isolated, Sendable)
    public func isImageCached(forKey key: String) async -> Bool {
        let cacheKey = key as NSString
        // Atomically perform eviction and all cache lookups within actor context
        evictExpiredCache()
        let inLRU = lruDict[cacheKey] != nil
        let inImageCache = imageCache.object(forKey: cacheKey) != nil
        let inDataCache = dataCache.object(forKey: cacheKey) != nil
        let isCached = inImageCache || inDataCache
        // If cached but not in LRU, reinsert to maintain LRU behavior
        if isCached && !inLRU {
            addOrUpdateLRUNode(for: cacheKey)
        }
        return isCached
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
    public struct CacheConfiguration: Sendable {
        public let maxAge: TimeInterval  // seconds
        public let maxLRUCount: Int
        public init(maxAge: TimeInterval = 3600, maxLRUCount: Int = 100) {
            self.maxAge = maxAge
            self.maxLRUCount = maxLRUCount
        }
    }

    private var cacheConfig: CacheConfiguration
    // Efficient O(1) LRU cache tracking
    // NOTE: LRUNode is not Sendable due to mutable properties (prev, next, timestamp).
    // All access and mutation must occur within the ImageService actor for thread safety.
    fileprivate final class LRUNode {
        let key: NSString
        var prev: LRUNode?
        var next: LRUNode?
        var timestamp: TimeInterval  // Access timestamp for LRU ordering
        var insertionTimestamp: TimeInterval  // Insertion timestamp for expiration

        init(key: NSString, timestamp: TimeInterval, insertionTimestamp: TimeInterval) {
            self.key = key
            self.timestamp = timestamp
            self.insertionTimestamp = insertionTimestamp
        }
    }
    private var lruDict: [NSString: LRUNode] = [:]
    private var lruHead: LRUNode?
    private var lruTail: LRUNode?
    // Cache metrics
    public var cacheHits: Int = 0
    public var cacheMisses: Int = 0
    // Retry/backoff configuration
    /// Configuration for retry/backoff logic
    public struct RetryConfiguration: Sendable {
        public let maxAttempts: Int
        public let baseDelay: TimeInterval
        public let jitter: TimeInterval
        /// Optional error filter: only retry for errors matching this predicate
        public let shouldRetry: (@Sendable (Error) -> Bool)?
        /// Optional custom backoff strategy: returns delay for given attempt
        public let backoff: (@Sendable (Int) -> TimeInterval)?

        public init(
            maxAttempts: Int = 3,
            baseDelay: TimeInterval = 0.5,
            jitter: TimeInterval = 0.5,
            shouldRetry: (@Sendable (Error) -> Bool)? = nil,
            backoff: (@Sendable (Int) -> TimeInterval)? = nil
        ) {
            self.maxAttempts = maxAttempts
            self.baseDelay = baseDelay
            self.jitter = jitter
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
                // Custom backoff strategy
                let delay: TimeInterval
                if let backoff = config.backoff {
                    delay = backoff(attempt)
                } else {
                    delay = config.baseDelay * pow(2.0, Double(attempt))
                }
                let jitter = Double.random(in: 0...config.jitter)
                
                // Check for cancellation before sleeping
                try Task.checkCancellation()

                try await Task.sleep(nanoseconds: UInt64((delay + jitter) * 1_000_000_000))
                
                // Check for cancellation before next attempt
                try Task.checkCancellation()

                attempt += 1
                continue
            }
        }
        throw lastError ?? NetworkError.networkUnavailable
    }
    private let imageCache: NSCache<NSString, PlatformImage>
    private let dataCache: NSCache<NSString, NSData>
    private let injectedURLSession: URLSessionProtocol?

    // Computed property that returns the injected session or uses shared default
    private var urlSession: URLSessionProtocol {
        return injectedURLSession ?? sharedURLSession
    }

    // Deduplication: Track in-flight fetchImageData requests by URL string
    private var inFlightImageTasks: [String: Task<Data, Error>] = [:]

    public init(
        imageCacheCountLimit: Int = 100,
        imageCacheTotalCostLimit: Int = 50 * 1024 * 1024,
        dataCacheCountLimit: Int = 200,
        dataCacheTotalCostLimit: Int = 100 * 1024 * 1024,
        urlSession: URLSessionProtocol? = nil
    ) {
        imageCache = NSCache<NSString, PlatformImage>()
        imageCache.countLimit = imageCacheCountLimit  // max number of decoded images
        imageCache.totalCostLimit = imageCacheTotalCostLimit  // max memory for decoded images
        dataCache = NSCache<NSString, NSData>()
        dataCache.countLimit = dataCacheCountLimit  // max number of raw data entries
        dataCache.totalCostLimit = dataCacheTotalCostLimit  // max memory for raw data
        self.cacheConfig = CacheConfiguration(maxLRUCount: imageCacheCountLimit)

        self.interceptors = []

        self.injectedURLSession = urlSession
    }

    /// Convenience initializer for backward compatibility
    /// - Parameters:
    ///   - cacheCountLimit: Shared count limit for both image and data caches (deprecated, use separate parameters)
    ///   - cacheTotalCostLimit: Shared cost limit for both image and data caches (deprecated, use separate parameters)
    ///   - urlSession: Optional URL session for network requests
    @available(
        *, deprecated,
        message:
            "Use init(imageCacheCountLimit:imageCacheTotalCostLimit:dataCacheCountLimit:dataCacheTotalCostLimit:urlSession:) for better cache performance"
    )
    public init(
        cacheCountLimit: Int = 100, cacheTotalCostLimit: Int = 50 * 1024 * 1024,
        urlSession: URLSessionProtocol? = nil
    ) {
        self.init(
            imageCacheCountLimit: cacheCountLimit,
            imageCacheTotalCostLimit: cacheTotalCostLimit,
            dataCacheCountLimit: cacheCountLimit,
            dataCacheTotalCostLimit: cacheTotalCostLimit,
            urlSession: urlSession
        )
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
        async throws
        -> Data
    {
        // Determine which retry configuration to use:
        // 1. Explicitly passed configuration takes precedence
        // 2. Override configuration if set
        // 3. Default configuration as fallback
        let effectiveRetryConfig =
            retryConfig ?? (overrideRetryConfiguration ?? RetryConfiguration())

        let cacheKey = urlString as NSString
        // Check cache for image data, evict expired
        evictExpiredCache()
        if let cachedData = dataCache.object(forKey: cacheKey),
            let node = lruDict[cacheKey],
            Date().timeIntervalSince1970 - node.insertionTimestamp < cacheConfig.maxAge
        {
            moveLRUNodeToHead(node)
            cacheHits += 1
            return cachedData as Data
        }
        cacheMisses += 1

        // Deduplication: Check for in-flight task
        if let existingTask = inFlightImageTasks[urlString] {
            return try await existingTask.value
        }

        // Create new task for this request, with retry/backoff
        let fetchTask = Task<Data, Error> {
            let cacheKey = urlString as NSString
            let data = try await withRetry(config: effectiveRetryConfig) {
                guard let url = URL(string: urlString),
                    let scheme = url.scheme, !scheme.isEmpty,
                    let host = url.host, !host.isEmpty
                else {
                    throw NetworkError.invalidEndpoint(reason: "Invalid image URL: \(urlString)")
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

                case 401:
                    throw NetworkError.unauthorized(data: data, statusCode: httpResponse.statusCode)
                default:
                    throw NetworkError.httpError(statusCode: httpResponse.statusCode, data: data)
                }
            }
            // Cache raw data for future use, assign cost as data length
            self.dataCache.setObject(data as NSData, forKey: cacheKey, cost: data.count)
            addOrUpdateLRUNode(for: cacheKey)
            return data
        }
        inFlightImageTasks[urlString] = fetchTask
        defer { inFlightImageTasks.removeValue(forKey: urlString) }
        return try await fetchTask.value
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
    /// - Returns: JPEG data or nil if conversion fails
    public static func platformImageToData(
        _ image: PlatformImage, compressionQuality: CGFloat = 0.8
    ) -> Data? {
        #if canImport(UIKit)
            return image.jpegData(compressionQuality: compressionQuality)
        #elseif canImport(Cocoa)
            guard let tiffData = image.tiffRepresentation,
                let bitmap = NSBitmapImageRep(data: tiffData)
            else { return nil }
            let properties: [NSBitmapImageRep.PropertyKey: Any] = [
                .compressionFactor: NSNumber(value: Double(compressionQuality))
            ]
            return bitmap.representation(using: .jpeg, properties: properties)
        #else
            return nil
        #endif
    }

    /// Fetches an image and returns it as SwiftUI Image
    /// - Parameter urlString: The URL string for the image
    /// - Returns: A SwiftUI Image
    /// - Throws: NetworkError if the request fails
    #if canImport(SwiftUI)
        public static func swiftUIImage(from data: Data) -> SwiftUI.Image? {
            guard let platformImage = PlatformImage(data: data) else { return nil }
            #if canImport(UIKit)
                return SwiftUI.Image(uiImage: platformImage)
            #elseif canImport(Cocoa)
                return SwiftUI.Image(nsImage: platformImage)
            #endif
        }
    #endif

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
        let maxUploadSize = await AsyncNetConfig.shared.maxUploadSize
        if imageData.count > maxUploadSize {
            #if canImport(OSLog)
                asyncNetLogger.warning(
                    "Upload rejected: Image size \(imageData.count, privacy: .public) bytes exceeds limit of \(maxUploadSize, privacy: .public) bytes"
                )
            #else
                print(
                    "Upload rejected: Image size \(imageData.count) bytes exceeds limit of \(maxUploadSize) bytes"
                )
            #endif
            throw NetworkError.payloadTooLarge(size: imageData.count, limit: maxUploadSize)
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

        var body = Data()

        // Add additional fields
        for (key, value) in configuration.additionalFields {
            let boundaryString = "--\(boundary)\r\n"
            let dispositionString = "Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n"
            let valueString = "\(value)\r\n"

            guard let boundaryData = boundaryString.data(using: .utf8),
                let dispositionData = dispositionString.data(using: .utf8),
                let valueData = valueString.data(using: .utf8)
            else {
                throw NetworkError.invalidEndpoint(
                    reason: "Failed to encode form field '\(key)' with value '\(value)'"
                )
            }
            
            body.append(boundaryData)
            body.append(dispositionData)
            body.append(valueData)
        }

        // Add image data
        // Determine MIME type: prefer configured value, then detect from data, then fallback
        let mimeType: String
        let trimmedConfiguredMimeType = configuration.mimeType.trimmingCharacters(
            in: .whitespacesAndNewlines)
        if !trimmedConfiguredMimeType.isEmpty {
            mimeType = trimmedConfiguredMimeType
        } else {
            mimeType = detectMimeType(from: imageData) ?? "application/octet-stream"
        }

        let imageBoundaryString = "--\(boundary)\r\n"
        let imageDispositionString =
            "Content-Disposition: form-data; name=\"\(configuration.fieldName)\"; filename=\"\(configuration.fileName)\"\r\n"
        let imageTypeString = "Content-Type: \(mimeType)\r\n\r\n"
        let closingBoundaryString = "\r\n--\(boundary)--\r\n"

        guard let imageBoundaryData = imageBoundaryString.data(using: .utf8),
            let imageDispositionData = imageDispositionString.data(using: .utf8),
            let imageTypeData = imageTypeString.data(using: .utf8),
            let closingBoundaryData = closingBoundaryString.data(using: .utf8)
        else {
            throw NetworkError.invalidEndpoint(
                reason:
                    "Failed to encode multipart form data strings for image upload (boundary: '\(boundary)', fieldName: '\(configuration.fieldName)', fileName: '\(configuration.fileName)', mimeType: '\(mimeType)')"
            )
        }
        
        body.append(imageBoundaryData)
        body.append(imageDispositionData)
        body.append(imageTypeData)
        body.append(imageData)
        body.append(closingBoundaryData)

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
        case 401:
            throw NetworkError.unauthorized(data: data, statusCode: httpResponse.statusCode)
        default:
            throw NetworkError.httpError(statusCode: httpResponse.statusCode, data: data)
        }
    }

    // MARK: - Cache Management

    /// Retrieves a cached image for the given key
    /// - Parameter key: The cache key (typically the URL string)
    /// - Returns: The cached image if available
    public func cachedImage(forKey key: String) -> PlatformImage? {
        let cacheKey = key as NSString
        evictExpiredCache()
        if let node = lruDict[cacheKey] {
            moveLRUNodeToHead(node)
            cacheHits += 1
            return imageCache.object(forKey: cacheKey)
        }
        cacheMisses += 1
        return nil
    }

    /// Clears all cached images
    public func clearCache() {
        imageCache.removeAllObjects()
        dataCache.removeAllObjects()
        lruDict.removeAll()
        lruHead = nil
        lruTail = nil
        cacheHits = 0
        cacheMisses = 0
    }

    /// Stores an image in the cache for the given key
    /// - Parameters:
    ///   - image: The image to cache
    ///   - key: The cache key (typically the URL string)
    ///   - data: Optional image data to cache alongside the image
    public func storeImageInCache(_ image: PlatformImage, forKey key: String, data: Data? = nil) {
        let cacheKey = key as NSString
        imageCache.setObject(image, forKey: cacheKey)
        if let data = data {
            dataCache.setObject(data as NSData, forKey: cacheKey, cost: data.count)
        }
        addOrUpdateLRUNode(for: cacheKey)
    }

    /// Removes a specific image from both the image cache and data cache
    ///
    /// This method removes the cached image and its associated data for the given key from all cache layers,
    /// including the LRU tracking. If the key doesn't exist in the cache, this method silently no-ops.
    ///
    /// - Parameter key: The cache key (typically the URL string) used to identify the cached image to remove.
    ///                  Should be the same key used when storing the image.
    public func removeFromCache(key: String) {
        let cacheKey = key as NSString
        imageCache.removeObject(forKey: cacheKey)
        dataCache.removeObject(forKey: cacheKey)
        if let node = lruDict.removeValue(forKey: cacheKey) {
            removeLRUNode(node)
        }
    }

    /// Evict expired cache entries based on maxAge using lazy eviction
    /// Only evicts from the LRU head until finding a non-expired item,
    /// keeping eviction cost proportional to expired items rather than total cache size
    private func evictExpiredCache() {
        let now = Date().timeIntervalSince1970

        // Lazy eviction: only check and evict from LRU head until we find a non-expired item
        while let head = lruHead {
            if now - head.insertionTimestamp >= cacheConfig.maxAge {
                // Head is expired, evict it
                let key = head.key
                imageCache.removeObject(forKey: key)
                dataCache.removeObject(forKey: key)
                lruDict.removeValue(forKey: key)
                removeLRUNode(head)
            } else {
                // Head is not expired, no need to check further (LRU order guarantees this)
                break
            }
        }
    }

    /// Update cache configuration (maxAge, maxLRUCount)
    public func updateCacheConfiguration(_ config: CacheConfiguration) {
        self.cacheConfig = config
        // Evict expired entries first
        evictExpiredCache()
        // Retain only the most recently used items
        var node = lruHead
        var count = 0
        var nodesToEvict: [LRUNode] = []
        var retainedKeys: [NSString] = []
        // Traverse from head, keep first maxLRUCount nodes, collect nodes to evict
        while let current = node {
            count += 1
            if count <= cacheConfig.maxLRUCount {
                retainedKeys.append(current.key)
            } else {
                nodesToEvict.append(current)
            }
            node = current.next
        }
        // Remove evicted nodes after traversal
        for node in nodesToEvict {
            let key = node.key
            imageCache.removeObject(forKey: key)
            dataCache.removeObject(forKey: key)
            lruDict.removeValue(forKey: key)
            removeLRUNode(node)
        }
    }

    // MARK: - Private Helpers

    /// Detects MIME type from image data by examining the file header
    /// - Parameter data: The image data to analyze
    /// - Returns: Detected MIME type string, or nil if detection fails
    private func detectMimeType(from data: Data) -> String? {
        guard !data.isEmpty else { return nil }

        let bytes = [UInt8](data.prefix(min(16, data.count)))

        // JPEG: FF D8 FF (needs at least 3 bytes)
        if data.count >= 3 && bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF {
            return "image/jpeg"
        }

        // PNG: 89 50 4E 47 0D 0A 1A 0A (needs at least 8 bytes)
        if data.count >= 8 && bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E
            && bytes[3] == 0x47 && bytes[4] == 0x0D && bytes[5] == 0x0A && bytes[6] == 0x1A
            && bytes[7] == 0x0A
        {
            return "image/png"
        }

        // GIF: 47 49 46 38 (needs at least 4 bytes)
        if data.count >= 4 && bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46
            && bytes[3] == 0x38
        {
            return "image/gif"
        }

        // WebP: 52 49 46 46 ... 57 45 42 50 (needs at least 12 bytes)
        if data.count >= 12 && bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46
            && bytes[3] == 0x46
        {
            if bytes[8] == 0x57 && bytes[9] == 0x45 && bytes[10] == 0x42 && bytes[11] == 0x50 {
                return "image/webp"
            }
        }

        // HEIC/HEIF: often starts with 'ftyp' box (needs at least 12 bytes)
        if data.count >= 12 {
            // Check for 'ftyp' box: bytes 4-7 should be [0x66, 0x74, 0x79, 0x70]
            if bytes[4] == 0x66 && bytes[5] == 0x74 && bytes[6] == 0x79 && bytes[7] == 0x70 {
                // Check brand (bytes 8-11)
                if data.count >= 16 {
                    let brandBytes = (bytes[8], bytes[9], bytes[10], bytes[11])
                    switch brandBytes {
                    case (0x68, 0x65, 0x69, 0x63):  // "heic"
                        return "image/heic"
                    case (0x68, 0x65, 0x69, 0x78):  // "heix"
                        return "image/heic"
                    case (0x68, 0x65, 0x76, 0x63):  // "hevc"
                        return "image/heic"
                    case (0x68, 0x65, 0x76, 0x78):  // "hevx"
                        return "image/heic"
                    case (0x6d, 0x69, 0x66, 0x31):  // "mif1"
                        return "image/heic"
                    case (0x6d, 0x73, 0x66, 0x31):  // "msf1"
                        return "image/heic"
                    default:
                        break
                    }
                }
            }
        }

        return nil
    }
}

// MARK: - LRU Helpers (ImageService)
extension ImageService {
    // NOTE: All LRUNode operations must be performed within the ImageService actor
    // for thread safety, as LRUNode is not Sendable due to mutable properties.
    private func addOrUpdateLRUNode(for key: NSString) {
        let now = Date().timeIntervalSince1970
        if let node = lruDict[key] {
            // Only move to head on access, do NOT update timestamp
            // Timestamp should only be set on initial insertion to track insertion age
            moveLRUNodeToHead(node)
        } else {
            let node = LRUNode(key: key, timestamp: now, insertionTimestamp: now)
            lruDict[key] = node
            insertLRUNodeAtHead(node)

            // Guard against invalid maxLRUCount values
            let maxCount = max(0, cacheConfig.maxLRUCount)

            // Evict nodes until we're within the configured limit
            while lruDict.count > maxCount, let tail = lruTail {
                imageCache.removeObject(forKey: tail.key)
                dataCache.removeObject(forKey: tail.key)
                lruDict.removeValue(forKey: tail.key)
                removeLRUNode(tail)
            }
        }
    }
    private func moveLRUNodeToHead(_ node: LRUNode) {
        removeLRUNode(node)
        insertLRUNodeAtHead(node)
    }
    private func insertLRUNodeAtHead(_ node: LRUNode) {
        node.next = lruHead
        node.prev = nil
        lruHead?.prev = node
        lruHead = node
        if lruTail == nil {
            lruTail = node
        }
    }
    private func removeLRUNode(_ node: LRUNode) {
        if node.prev != nil {
            node.prev?.next = node.next
        } else {
            lruHead = node.next
        }
        if node.next != nil {
            node.next?.prev = node.prev
        } else {
            lruTail = node.prev
        }
        node.prev = nil
        node.next = nil
    }
}

// MARK: - Type-Safe JSON Encoding

/// Protocol for request/response interceptors
public protocol RequestInterceptor: Sendable {
    /// Called before a request is sent. Can modify the request.
    func willSend(request: URLRequest) async -> URLRequest
    /// Called after a response is received. Can inspect/modify response/data.
    func didReceive(response: URLResponse, data: Data?) async
}

/// Dynamic coding keys for handling additional fields in JSON encoding
private struct DynamicCodingKeys: CodingKey {
    var stringValue: String
    var intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}

/// Type-safe payload structure for base64 image uploads
private struct UploadPayload: Encodable {
    let fieldName: String
    let fileName: String
    let compressionQuality: CGFloat
    let base64Data: String
    let additionalFields: [String: String]

    private enum CodingKeys: String, CodingKey {
        case fieldName
        case fileName
        case compressionQuality
        case base64Data
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicCodingKeys.self)

        // Encode standard fields
        try container.encode(fieldName, forKey: DynamicCodingKeys(stringValue: "fieldName")!)
        try container.encode(fileName, forKey: DynamicCodingKeys(stringValue: "fileName")!)
        try container.encode(
            compressionQuality, forKey: DynamicCodingKeys(stringValue: "compressionQuality")!)
        try container.encode(base64Data, forKey: DynamicCodingKeys(stringValue: "data")!)

        // Encode additional fields
        for (key, value) in additionalFields {
            try container.encode(value, forKey: DynamicCodingKeys(stringValue: key)!)
        }
    }
}

// MARK: - SwiftUI Image Extension
#if canImport(SwiftUI)
    extension SwiftUI.Image {
        /// Creates a SwiftUI Image from a platform-specific image
        /// - Parameter platformImage: The UIImage or NSImage to convert
        public init(platformImage: PlatformImage) {
            #if canImport(UIKit)
                self.init(uiImage: platformImage)
            #elseif canImport(Cocoa)
                self.init(nsImage: platformImage)
            #endif
        }
    }
#endif
