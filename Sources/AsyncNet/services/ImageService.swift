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
#if canImport(UniformTypeIdentifiers)
    import UniformTypeIdentifiers
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
        let maxSafeRawSize = 50 * 1024 * 1024  // 50MB raw = ~67MB base64
        if imageData.count > maxSafeRawSize {
            throw NetworkError.payloadTooLarge(
                size: imageData.count,
                limit: maxSafeRawSize
            )
        }

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
        // Warn if encoded image is large (base64 adds ~33% overhead)
        let maxUploadSize = await AsyncNetConfig.shared.maxUploadSize
        let encodedSize = ((imageData.count + 2) / 3) * 4
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

        // Determine MIME type: prefer configured value, then detect from data, then fallback
        let mimeType: String
        let trimmedConfiguredMimeType = configuration.mimeType.trimmingCharacters(
            in: .whitespacesAndNewlines)
        if !trimmedConfiguredMimeType.isEmpty {
            mimeType = trimmedConfiguredMimeType
        } else {
            mimeType = detectMimeType(from: imageData) ?? "application/octet-stream"
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

        // Check if we can use streaming upload with concrete URLSession
        if let concreteSession = urlSession as? URLSession {
            // Use streaming upload with concrete URLSession
            let inputStream = MultipartInputStream(
                boundary: boundary,
                fieldName: configuration.fieldName,
                fileName: configuration.fileName,
                mimeType: mimeType,
                additionalFields: configuration.additionalFields,
                imageData: imageData
            )

            // Set the input stream on the request
            request.httpBodyStream = inputStream

            let (data, response) = try await concreteSession.data(for: request)

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
        } else {
            // Fallback: Use regular multipart upload for test/mock sessions
            return try await uploadImageMultipartFallback(
                imageData, to: url, configuration: configuration, boundary: boundary,
                mimeType: mimeType)
        }
    }

    /// Fallback multipart upload for test/mock URLSession implementations
    private func uploadImageMultipartFallback(
        _ imageData: Data,
        to url: URL,
        configuration: UploadConfiguration,
        boundary: String,
        mimeType: String
    ) async throws -> Data {
        // Create multipart body data (not streamed, but still avoids base64 encoding)
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
                throw NetworkError.invalidEndpoint(reason: "Failed to encode multipart data")
            }

            body.append(boundaryData)
            body.append(dispositionData)
            body.append(valueData)
        }

        // Add image data
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
            throw NetworkError.invalidEndpoint(reason: "Failed to encode image multipart data")
        }

        body.append(imageBoundaryData)
        body.append(imageDispositionData)
        body.append(imageTypeData)
        body.append(imageData)
        body.append(closingBoundaryData)

        // Create request with body data
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(
            "multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        // Apply request interceptors
        let interceptors = self.interceptors
        for interceptor in interceptors {
            request = await interceptor.willSend(request: request)
        }

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

    /// Configuration for image upload operations
    public struct UploadConfiguration: Sendable {
        public let compressionQuality: CGFloat
        public let fieldName: String
        public let fileName: String
        public let additionalFields: [String: String]
        public let mimeType: String
        /// Threshold for switching to streaming upload (bytes of base64-encoded data)
        /// Images with encoded size above this threshold will use streaming multipart upload
        /// to avoid memory spikes. Default is 10MB of encoded data (~7.5MB raw).
        public let streamThreshold: Int

        public init(
            compressionQuality: CGFloat = 0.8,
            fieldName: String = "file",
            fileName: String = "image.jpg",
            additionalFields: [String: String] = [:],
            mimeType: String? = nil,
            streamThreshold: Int = 10 * 1024 * 1024  // 10MB encoded = ~7.5MB raw
        ) {
            self.compressionQuality = compressionQuality
            self.fieldName = fieldName
            self.fileName = fileName
            self.additionalFields = additionalFields
            // Use provided mimeType or default to image/jpeg for backward compatibility
            self.mimeType = mimeType ?? "image/jpeg"
            self.streamThreshold = streamThreshold
        }
    }
    /// Returns true if an image is cached for the given key (actor-isolated, Sendable)
    public func isImageCached(forKey key: String) async -> Bool {
        // Atomically check LRU state and expiration to prevent race conditions
        if let node = lruDict[key] {
            let now = Date().timeIntervalSince1970
            // If not expired, check caches immediately while we know LRU state is valid
            if now - node.insertionTimestamp < cacheConfig.maxAge {
                let cacheKey = key
                // Perform cache checks concurrently to prevent race conditions
                async let inImageCache = imageCache.object(forKey: cacheKey) != nil
                async let inDataCache = dataCache.object(forKey: cacheKey) != nil

                // Await the results separately and combine them
                let imageCached = await inImageCache
                let dataCached = await inDataCache
                let isCached = imageCached || dataCached

                // The node is already in LRU, just move it to head if cached
                if isCached {
                    moveLRUNodeToHead(node)
                }

                return isCached
            } else {
                // Node was expired - evict it completely from all caches
                let cacheKey = key
                await imageCache.removeObject(forKey: cacheKey)
                await dataCache.removeObject(forKey: cacheKey)
                lruDict.removeValue(forKey: key)
                removeLRUNode(node)
                // Invalidate heap entry to prevent it from being processed during expiration
                expirationHeap.invalidate(key: key)
                return false
            }
        }

        // Not in LRU at all - definitely not cached
        return false
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

    /// Min-heap for efficient expiration tracking
    /// Stores expiration entries keyed by (insertionTimestamp + maxAge) for O(log n) expiration
    private final class ExpirationHeap {
        private var heap: [ExpirationEntry] = []
        private var keyToIndex: [String: Int] = [:]  // Track position of each key in heap
        private var validCount: Int = 0  // Cached count of valid entries for O(1) access
        private var lastCleanupTime: TimeInterval = 0  // Track last cleanup time
        private let cleanupInterval: TimeInterval = 30.0  // Cleanup every 30 seconds
        private var operationCount: Int = 0  // Track operations since last cleanup
        private let operationsPerCleanup: Int = 100  // Trigger cleanup every 100 operations

        struct ExpirationEntry {
            let expirationTime: TimeInterval
            let key: String  // Changed from NSString to String to prevent memory retention
            var isValid: Bool = true  // Mark as invalid when entry is removed

            init(expirationTime: TimeInterval, key: String) {
                self.expirationTime = expirationTime
                self.key = key
            }
        }

        /// Push a new expiration entry into the heap
        func push(_ entry: ExpirationEntry) {
            heap.append(entry)
            keyToIndex[entry.key] = heap.count - 1
            siftUp(heap.count - 1)
            validCount += 1  // Increment valid count
            operationCount += 1

            // Trigger lightweight cleanup on rapid growth
            if operationCount >= operationsPerCleanup {
                performLightweightCleanup()
            }
        }

        /// Pop the earliest expiring entry (if it's still valid)
        func popExpired(currentTime: TimeInterval) -> ExpirationEntry? {
            while let first = heap.first, first.expirationTime <= currentTime {
                let entry = heap.removeFirst()
                keyToIndex.removeValue(forKey: entry.key)

                // Re-heapify after removal
                if !heap.isEmpty {
                    heap.insert(heap.removeLast(), at: 0)
                    siftDown(0)
                }

                // Only return if entry is still valid (not manually removed)
                if entry.isValid {
                    validCount -= 1  // Decrement valid count for returned entry
                    operationCount += 1
                    return entry
                }
                // Entry was invalid, continue to next
            }
            return nil
        }

        /// Mark an entry as invalid (when manually removed)
        func invalidate(key: String) {
            if let index = keyToIndex[key] {
                if heap[index].isValid {
                    heap[index].isValid = false
                    validCount -= 1  // Decrement valid count
                }
                keyToIndex.removeValue(forKey: key)
                operationCount += 1

                // More aggressive pruning: trigger when invalid ratio >20% or >=100 invalid entries
                let invalidCount = heap.count - validCount
                if heap.count > 0
                    && (Double(invalidCount) / Double(heap.count) > 0.20 || invalidCount >= 100)
                {
                    pruneInvalidEntries()
                }
            }
        }

        /// Prune invalid entries and rebuild heap for efficient memory usage
        /// This method removes all invalid entries and rebuilds the heap structure
        /// to prevent memory retention of invalidated entries
        func pruneInvalidEntries() {
            // Filter out invalid entries and rebuild heap
            let validEntries = heap.filter { $0.isValid }

            // Clear current heap and keyToIndex
            heap.removeAll()
            keyToIndex.removeAll()

            // Rebuild heap with only valid entries
            for entry in validEntries {
                heap.append(entry)
                keyToIndex[entry.key] = heap.count - 1
            }

            // Re-heapify the entire structure
            for i in stride(from: heap.count / 2 - 1, through: 0, by: -1) {
                siftDown(i)
            }

            // Update cached valid count (should match heap.count after pruning)
            validCount = heap.count
            lastCleanupTime = Date().timeIntervalSince1970
            operationCount = 0  // Reset operation counter
        }

        /// Perform lightweight cleanup without full heap rebuild
        /// This is called periodically to prevent excessive memory growth
        private func performLightweightCleanup() {
            let currentTime = Date().timeIntervalSince1970
            let timeSinceLastCleanup = currentTime - lastCleanupTime

            // Only perform cleanup if enough time has passed or we have significant invalid entries
            if timeSinceLastCleanup >= cleanupInterval || operationCount >= operationsPerCleanup {
                let invalidCount = heap.count - validCount

                // More aggressive cleanup thresholds for background cleanup
                if heap.count > 0
                    && (Double(invalidCount) / Double(heap.count) > 0.03 || invalidCount >= 10)
                {
                    pruneInvalidEntries()
                } else {
                    // Even if we don't prune, reset counters to prevent excessive checks
                    operationCount = 0
                    lastCleanupTime = currentTime
                }
            }
        }

        /// Check if heap has any potentially expired entries
        func hasExpiredEntries(currentTime: TimeInterval) -> Bool {
            // Quick check: if no valid entries, no expired entries
            guard validCount > 0 else { return false }

            // Check the root of the heap (earliest expiration)
            return heap.first?.expirationTime ?? .infinity <= currentTime
        }

        /// Get count of valid entries (O(1) with cached value)
        var count: Int {
            return validCount
        }

        private func siftUp(_ index: Int) {
            var childIndex = index
            let child = heap[childIndex]

            while childIndex > 0 {
                let parentIndex = (childIndex - 1) / 2
                let parent = heap[parentIndex]

                if child.expirationTime >= parent.expirationTime {
                    break
                }

                // Swap parent and child
                heap[childIndex] = parent
                heap[parentIndex] = child
                keyToIndex[parent.key] = childIndex
                keyToIndex[child.key] = parentIndex

                childIndex = parentIndex
            }
        }

        private func siftDown(_ index: Int) {
            let count = heap.count
            var parentIndex = index

            while true {
                let leftChildIndex = 2 * parentIndex + 1
                let rightChildIndex = 2 * parentIndex + 2

                var smallestIndex = parentIndex

                if leftChildIndex < count
                    && heap[leftChildIndex].expirationTime < heap[smallestIndex].expirationTime
                {
                    smallestIndex = leftChildIndex
                }

                if rightChildIndex < count
                    && heap[rightChildIndex].expirationTime < heap[smallestIndex].expirationTime
                {
                    smallestIndex = rightChildIndex
                }

                if smallestIndex == parentIndex {
                    break
                }

                // Swap parent and smallest child
                let temp = heap[parentIndex]
                heap[parentIndex] = heap[smallestIndex]
                heap[smallestIndex] = temp
                keyToIndex[temp.key] = smallestIndex
                keyToIndex[heap[parentIndex].key] = parentIndex

                parentIndex = smallestIndex
            }
        }
    }

    private var expirationHeap = ExpirationHeap()

    /// IMPORTANT: This class is NOT thread-safe and must only be accessed within ImageService actor isolation.
    /// All mutations must occur on the ImageService actor's executor for thread safety.
    /// The class is private to prevent external access and misuse.
    ///
    /// Memory Management:
    /// - Weak reference for prev prevents retain cycles in doubly-linked list
    /// - Strong reference for next maintains forward traversal integrity
    /// - Proper cleanup in removeLRUNode prevents retain cycles
    /// - Nodes are only deallocated when removed from lruDict
    private final class LRUNode {
        let key: String  // Modern Swift String instead of NSString
        weak var prev: LRUNode?  // Weak reference to prevent retain cycles
        var next: LRUNode?  // Keep strong references for forward traversal integrity
        let timestamp: TimeInterval  // Immutable - set once on insertion, never updated
        let insertionTimestamp: TimeInterval  // Already immutable

        init(key: String, timestamp: TimeInterval, insertionTimestamp: TimeInterval) {
            self.key = key
            self.timestamp = timestamp
            self.insertionTimestamp = insertionTimestamp
        }

        deinit {
            // With weak prev references, nodes may be deallocated while still in the list
            // The weak prev prevents retain cycles, but nodes may still have next references
            // until the list cleanup happens. This is expected behavior.
        }
    }
    private var lruDict: [String: LRUNode] = [:]
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
                    // Safe exponential backoff calculation to prevent overflow
                    // Compute the maximum exponent that won't exceed config.maxDelay
                    let maxExponent = log2(config.maxDelay / config.baseDelay)
                    let safeExponent = min(Double(attempt), maxExponent)

                    // Use safe multiplication with early exit to avoid overflow
                    var exponential: Double = 1.0
                    for _ in 0..<Int(safeExponent) {
                        exponential *= 2.0
                        // Early exit if we've reached the cap
                        if exponential * config.baseDelay >= config.maxDelay {
                            exponential = config.maxDelay / config.baseDelay
                            break
                        }
                    }

                    delay = config.baseDelay * exponential

                    // Additional safety check for finite values
                    if !delay.isFinite || delay.isNaN {
                        delay = config.maxDelay
                    }
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
        imageCache = Cache<String, SendableImage>(
            countLimit: imageCacheCountLimit, totalCostLimit: imageCacheTotalCostLimit)
        dataCache = Cache<String, SendableData>(
            countLimit: dataCacheCountLimit, totalCostLimit: dataCacheTotalCostLimit)
        self.cacheConfig = CacheConfiguration(maxLRUCount: imageCacheCountLimit)

        self.interceptors = []

        self.injectedURLSession = urlSession
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

        let cacheKey = urlString
        // Check cache for image data, evict expired
        await evictExpiredCache()
        if let cachedData = await dataCache.object(forKey: cacheKey)?.data,
            let node = lruDict[urlString],
            Date().timeIntervalSince1970 - node.insertionTimestamp < cacheConfig.maxAge
        {
            moveLRUNodeToHead(node)
            cacheHits += 1
            return cachedData
        }
        cacheMisses += 1

        // Deduplication: Check for in-flight task
        if let existingTask = inFlightImageTasks[urlString] {
            return try await existingTask.value
        }

        // Set up in-flight task tracking before creating the task
        inFlightImageTasks[urlString] = nil  // Placeholder to ensure the key exists

        // Create new task for this request, with retry/backoff
        let fetchTask = Task<Data, Error> {
            () async throws -> Data in
            // Capture strong reference to self for the entire task execution
            defer {
                // Always remove the task from inFlightImageTasks when it completes
                // This ensures cleanup happens regardless of success, failure, or cancellation
                Task {
                    self.removeInFlightTask(forKey: urlString)
                }
            }

            let data = try await self.withRetry(config: effectiveRetryConfig) {
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
            return data
        }

        // Now set the actual task in the dictionary
        inFlightImageTasks[urlString] = fetchTask

        let data = try await fetchTask.value

        // Cache the data back in the actor context
        await dataCache.setObject(SendableData(data), forKey: cacheKey, cost: data.count)
        await addOrUpdateLRUNode(for: urlString)

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
    /// - Returns: JPEG data or nil if conversion fails
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
            #elseif canImport(AppKit)
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

        // Warn if image is large (base64 encoding will increase size by ~33%)
        let maxRecommendedSize = maxUploadSize / 4 * 3  // ~75% of max to account for base64 overhead
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

        var body = Data()

        // Add additional fields
        for (key, value) in configuration.additionalFields {
            let boundaryString = "--\(boundary)\r\n"
            let dispositionString = "Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n"
            let valueString = "\(value)\r\n"

            // Validate UTF-8 encoding for each component with specific error messages
            guard let boundaryData = boundaryString.data(using: .utf8, allowLossyConversion: false)
            else {
                throw NetworkError.invalidEndpoint(
                    reason:
                        "Failed to encode multipart boundary for form field '\(key)' - contains invalid UTF-8 characters"
                )
            }
            guard
                let dispositionData = dispositionString.data(
                    using: .utf8, allowLossyConversion: false)
            else {
                throw NetworkError.invalidEndpoint(
                    reason:
                        "Failed to encode Content-Disposition header for form field '\(key)' - contains invalid UTF-8 characters"
                )
            }
            guard let valueData = valueString.data(using: .utf8, allowLossyConversion: false) else {
                throw NetworkError.invalidEndpoint(
                    reason:
                        "Failed to encode value for form field '\(key)' with value '\(value)' - contains invalid UTF-8 characters"
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

        // Validate UTF-8 encoding for image multipart components with specific error messages
        guard
            let imageBoundaryData = imageBoundaryString.data(
                using: .utf8, allowLossyConversion: false)
        else {
            throw NetworkError.invalidEndpoint(
                reason:
                    "Failed to encode image boundary - contains invalid UTF-8 characters (boundary: '\(boundary)')"
            )
        }
        guard
            let imageDispositionData = imageDispositionString.data(
                using: .utf8, allowLossyConversion: false)
        else {
            throw NetworkError.invalidEndpoint(
                reason:
                    "Failed to encode image Content-Disposition header - contains invalid UTF-8 characters (fieldName: '\(configuration.fieldName)', fileName: '\(configuration.fileName)')"
            )
        }
        guard let imageTypeData = imageTypeString.data(using: .utf8, allowLossyConversion: false)
        else {
            throw NetworkError.invalidEndpoint(
                reason:
                    "Failed to encode image Content-Type header - contains invalid UTF-8 characters (mimeType: '\(mimeType)')"
            )
        }
        guard
            let closingBoundaryData = closingBoundaryString.data(
                using: .utf8, allowLossyConversion: false)
        else {
            throw NetworkError.invalidEndpoint(
                reason:
                    "Failed to encode closing boundary - contains invalid UTF-8 characters (boundary: '\(boundary)')"
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
        let now = Date().timeIntervalSince1970

        // Atomically check expiration and handle cache state
        if let node = lruDict[key] {
            // Check expiration first to avoid race conditions
            if now - node.insertionTimestamp < cacheConfig.maxAge {
                // Not expired - safe to return cached data
                if let cachedImage = await imageCache.object(forKey: cacheKey) {
                    moveLRUNodeToHead(node)
                    cacheHits += 1
                    return cachedImage.image
                }
            } else {
                // Expired - atomically remove from all caches
                await imageCache.removeObject(forKey: cacheKey)
                await dataCache.removeObject(forKey: cacheKey)
                lruDict.removeValue(forKey: key)
                removeLRUNode(node)
                // Invalidate heap entry to prevent it from being processed during expiration
                expirationHeap.invalidate(key: key)
            }
        }

        // Cache miss - increment counter and return nil
        cacheMisses += 1
        return nil
    }

    /// Clears all cached images
    public func clearCache() async {
        await imageCache.removeAllObjects()
        await dataCache.removeAllObjects()

        // Properly clean up all LRU nodes to prevent any potential retain cycles
        var node = lruHead
        while let current = node {
            let next = current.next
            // Clear strong references, weak references will be cleaned up automatically
            current.next = nil
            node = next
        }

        lruDict.removeAll()
        lruHead = nil
        lruTail = nil
        cacheHits = 0
        cacheMisses = 0
        // Reset expiration heap
        expirationHeap = ExpirationHeap()

        // Validate cleanup in debug builds
        #if DEBUG
            assert(validateLRUListIntegrity(), "LRU list integrity check failed after clearCache")
        #endif
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
        await addOrUpdateLRUNode(for: key)
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
        if let node = lruDict.removeValue(forKey: key) {
            removeLRUNode(node)
        }
        // Invalidate heap entry to prevent it from being processed during expiration
        expirationHeap.invalidate(key: key)
        // Trigger periodic compaction to prevent memory retention
        expirationHeap.pruneInvalidEntries()
    }

    /// Evict expired cache entries based on maxAge using efficient heap-based expiration
    /// The expiration heap allows O(log n) insertions and O(log n) deletions while
    /// efficiently finding and removing expired items regardless of their position in LRU
    private func evictExpiredCache() async {
        let now = Date().timeIntervalSince1970

        // Use heap-based expiration for efficient removal of expired entries
        // This correctly handles cases where expired items are not at the LRU head
        while let expiredEntry = expirationHeap.popExpired(currentTime: now) {
            let key = expiredEntry.key
            let cacheKey = key
            await imageCache.removeObject(forKey: cacheKey)
            await dataCache.removeObject(forKey: cacheKey)
            if let node = lruDict.removeValue(forKey: key) {
                removeLRUNode(node)
            }
        }
    }

    /// Update cache configuration (maxAge, maxLRUCount)
    public func updateCacheConfiguration(_ config: CacheConfiguration) async {
        self.cacheConfig = config
        // Evict expired entries first
        await evictExpiredCache()
        // Retain only the most recently used items
        var node = lruHead
        var count = 0
        var nodesToEvict: [LRUNode] = []
        var retainedKeys: [String] = []
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
            let cacheKey = key
            await imageCache.removeObject(forKey: cacheKey)
            await dataCache.removeObject(forKey: cacheKey)
            lruDict.removeValue(forKey: key)
            removeLRUNode(node)
            // Invalidate heap entry for evicted node
            expirationHeap.invalidate(key: key)
        }
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

    /// Detects MIME type from image data by examining the file header
    /// - Parameter data: The image data to analyze
    /// - Returns: Detected MIME type string, or nil if detection fails
    private func detectMimeType(from data: Data) -> String? {
        guard !data.isEmpty else { return nil }

        // Read at least 32 bytes to handle complex signatures
        let bytes = [UInt8](data.prefix(min(32, data.count)))
        let dataCount = data.count

        // Helper function to safely check byte sequences
        func checkBytes(at indices: [Int], expected: [UInt8]) -> Bool {
            guard indices.count == expected.count else { return false }
            for (i, expectedByte) in expected.enumerated() {
                let byteIndex = indices[i]
                guard byteIndex < bytes.count && bytes[byteIndex] == expectedByte else {
                    return false
                }
            }
            return true
        }

        // JPEG: FF D8 FF (SOI marker)
        if dataCount >= 3 && checkBytes(at: [0, 1, 2], expected: [0xFF, 0xD8, 0xFF]) {
            return "image/jpeg"
        }

        // PNG: 89 50 4E 47 0D 0A 1A 0A
        if dataCount >= 8
            && checkBytes(
                at: [0, 1, 2, 3, 4, 5, 6, 7],
                expected: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        {
            return "image/png"
        }

        // GIF87a: 47 49 46 38 37 61
        if dataCount >= 6
            && checkBytes(
                at: [0, 1, 2, 3, 4, 5],
                expected: [0x47, 0x49, 0x46, 0x38, 0x37, 0x61])
        {
            return "image/gif"
        }

        // GIF89a: 47 49 46 38 39 61
        if dataCount >= 6
            && checkBytes(
                at: [0, 1, 2, 3, 4, 5],
                expected: [0x47, 0x49, 0x46, 0x38, 0x39, 0x61])
        {
            return "image/gif"
        }

        // WebP: RIFF header + WEBP at offset 8
        if dataCount >= 12 && checkBytes(at: [0, 1, 2, 3], expected: [0x52, 0x49, 0x46, 0x46]) {
            if checkBytes(at: [8, 9, 10, 11], expected: [0x57, 0x45, 0x42, 0x50]) {
                return "image/webp"
            }
        }

        // BMP: 42 4D (BM)
        if dataCount >= 2 && checkBytes(at: [0, 1], expected: [0x42, 0x4D]) {
            return "image/bmp"
        }

        // TIFF Little Endian: 49 49 2A 00
        if dataCount >= 4 && checkBytes(at: [0, 1, 2, 3], expected: [0x49, 0x49, 0x2A, 0x00]) {
            return "image/tiff"
        }

        // TIFF Big Endian: 4D 4D 00 2A
        if dataCount >= 4 && checkBytes(at: [0, 1, 2, 3], expected: [0x4D, 0x4D, 0x00, 0x2A]) {
            return "image/tiff"
        }

        // HEIC/HEIF/AVIF: ISO Base Media File Format with 'ftyp' box
        if dataCount >= 12 && checkBytes(at: [4, 5, 6, 7], expected: [0x66, 0x74, 0x79, 0x70]) {
            // Check major brand (bytes 8-11)
            if dataCount >= 16 {
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
                case (0x61, 0x76, 0x69, 0x66):  // "avif"
                    return "image/avif"
                case (0x61, 0x76, 0x69, 0x73):  // "avis"
                    return "image/avif"
                default:
                    // Check compatible brands if available (bytes 12-15, 16-19, etc.)
                    if dataCount >= 20 {
                        let compatibleBrand1 = (bytes[12], bytes[13], bytes[14], bytes[15])
                        let compatibleBrand2 = (bytes[16], bytes[17], bytes[18], bytes[19])

                        // Check for HEIC/AVIF in compatible brands
                        if compatibleBrand1 == (0x68, 0x65, 0x69, 0x63)
                            || compatibleBrand1 == (0x61, 0x76, 0x69, 0x66)
                            || compatibleBrand2 == (0x68, 0x65, 0x69, 0x63)
                            || compatibleBrand2 == (0x61, 0x76, 0x69, 0x66)
                        {
                            return brandBytes == (0x61, 0x76, 0x69, 0x66)
                                || brandBytes == (0x61, 0x76, 0x69, 0x73)
                                ? "image/avif" : "image/heic"
                        }
                    }
                    break
                }
            }
        }

        // Try platform-specific MIME detection as fallback
        #if canImport(UniformTypeIdentifiers)
            return detectMimeTypeUsingPlatformAPI(from: data)
        #else
            return nil
        #endif
    }

    #if canImport(UniformTypeIdentifiers)

        /// Fallback MIME detection using platform APIs with in-memory image source
        private func detectMimeTypeUsingPlatformAPI(from data: Data) -> String? {
            // First attempt: Use CGImageSource to detect image type in-memory
            if let mimeType = detectMimeTypeUsingImageSource(from: data) {
                return mimeType
            }

            // Fallback: Use existing byte-pattern detection if image source fails
            return detectMimeType(from: data)
        }

        /// Detect MIME type using CGImageSource for in-memory processing
        private func detectMimeTypeUsingImageSource(from data: Data) -> String? {
            #if canImport(UIKit) || canImport(AppKit)
                // Create CFData from Data for CoreGraphics compatibility
                guard let cfData = CFDataCreate(kCFAllocatorDefault, [UInt8](data), data.count)
                else {
                    return nil
                }

                // Create image source from data
                guard let imageSource = CGImageSourceCreateWithData(cfData, nil) else {
                    return nil
                }

                // Get the UTI type identifier from the image source
                guard let uti = CGImageSourceGetType(imageSource) as String? else {
                    return nil
                }

                // Convert UTI to MIME type using UTType
                #if canImport(UniformTypeIdentifiers)
                    if let type = UTType(uti) {
                        // Map common image UTIs to MIME types
                        if type.conforms(to: UTType.jpeg) {
                            return "image/jpeg"
                        } else if type.conforms(to: UTType.png) {
                            return "image/png"
                        } else if type.conforms(to: UTType.gif) {
                            return "image/gif"
                        } else if type.conforms(to: UTType.webP) {
                            return "image/webp"
                        } else if type.conforms(to: UTType.bmp) {
                            return "image/bmp"
                        } else if type.conforms(to: UTType.tiff) {
                            return "image/tiff"
                        } else if type.conforms(to: UTType.heic) || type.conforms(to: UTType.heif) {
                            return "image/heic"
                        }
                    }
                #endif

                // Fallback: Direct UTI to MIME mapping for common types
                switch uti {
                case "public.jpeg", "public.jpg":
                    return "image/jpeg"
                case "public.png":
                    return "image/png"
                case "com.compuserve.gif":
                    return "image/gif"
                case "org.webmproject.webp":
                    return "image/webp"
                case "com.microsoft.bmp":
                    return "image/bmp"
                case "public.tiff":
                    return "image/tiff"
                case "public.heic", "public.heif":
                    return "image/heic"
                case "public.avif":
                    return "image/avif"
                default:
                    // For unknown UTIs, try to extract MIME type if it looks like one
                    if uti.hasPrefix("public.") && uti.contains("image") {
                        // Some UTIs might be convertible to MIME types
                        let mimeEquivalent = uti.replacingOccurrences(of: "public.", with: "image/")
                        if mimeEquivalent != uti {
                            return mimeEquivalent
                        }
                    }
                    return nil
                }
            #else
                return nil
            #endif
        }

    #else

        /// Fallback MIME detection for platforms without UniformTypeIdentifiers
        private func detectMimeTypeUsingPlatformAPI(from data: Data) -> String? {
            // Use existing byte-pattern detection as fallback
            return detectMimeType(from: data)
        }

    #endif
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

// MARK: - LRU Helpers (ImageService)
extension ImageService {
    // NOTE: All LRUNode operations must be performed within the ImageService actor
    // for thread safety, as LRUNode is not Sendable due to mutable properties.
    // This design choice prioritizes performance over redundant actor isolation.
    private func addOrUpdateLRUNode(for key: String) async {
        let now = Date().timeIntervalSince1970
        if let node = lruDict[key] {
            // Only move to head on access, do NOT update timestamp
            // Timestamp should only be set on initial insertion to track insertion age
            moveLRUNodeToHead(node)
        } else {
            let node = LRUNode(key: key, timestamp: now, insertionTimestamp: now)
            lruDict[key] = node
            insertLRUNodeAtHead(node)

            // Push expiration entry to heap for efficient expiration tracking
            let expirationTime = now + cacheConfig.maxAge
            let expirationEntry = ExpirationHeap.ExpirationEntry(
                expirationTime: expirationTime, key: key as String)
            expirationHeap.push(expirationEntry)

            // Guard against invalid maxLRUCount values
            let maxCount = max(0, cacheConfig.maxLRUCount)

            // Evict nodes until we're within the configured limit
            while lruDict.count > maxCount, let tail = lruTail {
                let cacheKey = tail.key
                await imageCache.removeObject(forKey: cacheKey)
                await dataCache.removeObject(forKey: cacheKey)
                lruDict.removeValue(forKey: tail.key)
                removeLRUNode(tail)
                // Invalidate heap entry for evicted node
                expirationHeap.invalidate(key: tail.key)
            }
        }
    }
    private func moveLRUNodeToHead(_ node: LRUNode) {
        removeLRUNode(node)
        insertLRUNodeAtHead(node)
    }
    private func insertLRUNodeAtHead(_ node: LRUNode) {
        node.next = lruHead
        node.prev = nil  // prev is weak, so this breaks any existing weak reference
        lruHead?.prev = node  // This creates a weak reference from the old head back to node
        lruHead = node
        if lruTail == nil {
            lruTail = node
        }
    }
    private func removeLRUNode(_ node: LRUNode) {
        // Properly clean up all references to prevent retain cycles
        // This ensures nodes can be deallocated when removed from lruDict

        // Capture strong local references upfront to avoid race conditions
        // where weak references can become nil between checks
        let strongPrev = node.prev  // Capture weak reference as strong local
        let strongNext = node.next  // Capture strong reference as local

        // Handle prev reference using captured strong reference
        if let prevNode = strongPrev {
            prevNode.next = strongNext
        } else {
            // If prev is nil, this node was the head
            lruHead = strongNext
        }

        // Handle next reference using captured strong reference
        if let nextNode = strongNext {
            nextNode.prev = strongPrev  // This creates a weak reference
        } else {
            // If next is nil, this node was the tail
            lruTail = strongPrev  // This is a weak reference, but that's okay
        }

        // Clear our own references to break any remaining links
        node.prev = nil  // This is redundant for weak references but good practice
        node.next = nil
    }

    /// Validates the integrity of the LRU linked list
    /// - Returns: True if the list is valid, false otherwise
    /// - Note: This method is for debugging and should not be called in production
    private func validateLRUListIntegrity() -> Bool {
        var node = lruHead
        var count = 0
        var visitedNodes = Set<ObjectIdentifier>()

        // Traverse forward and check for cycles
        while let current = node {
            let id = ObjectIdentifier(current)
            if visitedNodes.contains(id) {
                // Cycle detected
                return false
            }
            visitedNodes.insert(id)

            // Check bidirectional links (prev is weak, so it might be nil)
            if let prev = current.prev {
                if prev.next !== current {
                    return false  // Broken backward link
                }
            } else if current !== lruHead {
                return false  // Non-head node should have prev (unless garbage collected)
            }

            if let next = current.next {
                if next.prev !== current {
                    return false  // Broken forward link
                }
            } else if current !== lruTail {
                return false  // Non-tail node should have next
            }

            node = current.next
            count += 1

            // Safety check to prevent infinite loops
            if count > lruDict.count + 1 {
                return false  // List is longer than expected
            }
        }

        // Check that head and tail are consistent
        if lruHead == nil && lruTail != nil { return false }
        if lruHead != nil && lruTail == nil { return false }
        if lruHead != nil && lruTail != nil {
            if lruHead?.prev != nil { return false }  // Head should not have prev
            if lruTail?.next != nil { return false }  // Tail should not have next
        }

        return visitedNodes.count == lruDict.count
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

        // Encode standard fields with safe key creation
        guard let fieldNameKey = DynamicCodingKeys(stringValue: "fieldName") else {
            throw EncodingError.invalidValue(
                "fieldName",
                EncodingError.Context(
                    codingPath: [],
                    debugDescription: "Failed to create coding key for fieldName"
                )
            )
        }
        try container.encode(fieldName, forKey: fieldNameKey)

        guard let fileNameKey = DynamicCodingKeys(stringValue: "fileName") else {
            throw EncodingError.invalidValue(
                "fileName",
                EncodingError.Context(
                    codingPath: [],
                    debugDescription: "Failed to create coding key for fileName"
                )
            )
        }
        try container.encode(fileName, forKey: fileNameKey)

        guard let compressionQualityKey = DynamicCodingKeys(stringValue: "compressionQuality")
        else {
            throw EncodingError.invalidValue(
                "compressionQuality",
                EncodingError.Context(
                    codingPath: [],
                    debugDescription: "Failed to create coding key for compressionQuality"
                )
            )
        }
        try container.encode(compressionQuality, forKey: compressionQualityKey)

        guard let dataKey = DynamicCodingKeys(stringValue: "data") else {
            throw EncodingError.invalidValue(
                "data",
                EncodingError.Context(
                    codingPath: [],
                    debugDescription: "Failed to create coding key for data"
                )
            )
        }
        try container.encode(base64Data, forKey: dataKey)

        // Encode additional fields with safe key creation
        for (key, value) in additionalFields {
            guard let additionalKey = DynamicCodingKeys(stringValue: key) else {
                throw EncodingError.invalidValue(
                    key,
                    EncodingError.Context(
                        codingPath: [],
                        debugDescription:
                            "Failed to create coding key for additional field '\(key)'"
                    )
                )
            }
            try container.encode(value, forKey: additionalKey)
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
            #elseif canImport(AppKit)
                self.init(nsImage: platformImage)
            #endif
        }
    }
#endif

/// A Swift 6 compatible actor-based cache implementation
/// Provides thread-safe storage with cost and count limits using structured concurrency
public actor Cache<Key: Hashable & Sendable, Value: Sendable> {
    private var storage: [Key: CacheEntry] = [:]
    private var _totalCost: Int = 0
    private var insertionOrder: [Key] = []  // Track insertion order for FIFO eviction
    public let countLimit: Int?
    public let totalCostLimit: Int?

    public struct CacheEntry: Sendable {
        let value: Value
        let cost: Int

        init(value: Value, cost: Int = 1) {
            self.value = value
            self.cost = cost
        }
    }

    public init(countLimit: Int? = nil, totalCostLimit: Int? = nil) {
        self.countLimit = countLimit
        self.totalCostLimit = totalCostLimit
    }

    /// Get the current count of items
    public var count: Int {
        storage.count
    }

    /// Get the current total cost
    public var totalCost: Int {
        _totalCost
    }

    /// Retrieve an object from the cache
    public func object(forKey key: Key) -> Value? {
        storage[key]?.value
    }

    /// Store an object in the cache with limit enforcement
    public func setObject(_ value: Value, forKey key: Key, cost: Int = 1) {
        let entry = CacheEntry(value: value, cost: cost)

        // Remove existing entry if present to update cost
        if let existingEntry = storage[key] {
            _totalCost -= existingEntry.cost
            // Remove from insertion order (will be re-added at end)
            insertionOrder.removeAll { $0 == key }
        }

        // Enforce count limit by removing oldest items if necessary
        if let countLimit = countLimit {
            while storage.count >= countLimit && !storage.isEmpty {
                evictOldestEntry()
            }
        }

        // Enforce cost limit by removing oldest items if necessary
        if let totalCostLimit = totalCostLimit {
            while _totalCost + cost > totalCostLimit && !storage.isEmpty {
                evictOldestEntry()
            }
        }

        // Add the new entry
        storage[key] = entry
        _totalCost += cost
        insertionOrder.append(key)
    }

    /// Remove an object from the cache
    public func removeObject(forKey key: Key) {
        if let entry = storage.removeValue(forKey: key) {
            _totalCost -= entry.cost
            insertionOrder.removeAll { $0 == key }
        }
    }

    /// Remove all objects from the cache
    public func removeAllObjects() {
        storage.removeAll()
        _totalCost = 0
        insertionOrder.removeAll()
    }

    /// Evict the oldest entry (FIFO eviction)
    private func evictOldestEntry() {
        guard let oldestKey = insertionOrder.first,
            let entry = storage.removeValue(forKey: oldestKey)
        else {
            return
        }
        _totalCost -= entry.cost
        insertionOrder.removeFirst()
    }
}

/// Custom InputStream for streaming multipart/form-data uploads
/// Generates multipart data on-the-fly to avoid memory spikes with large images
private final class MultipartInputStream: InputStream {
    private let boundary: String
    private let fieldName: String
    private let fileName: String
    private let mimeType: String
    private let additionalFields: [String: String]
    private let imageData: Data
    private var currentPart: Int = 0
    private var partOffset: Int = 0
    private var parts: [Data] = []
    private var isOpen: Bool = false

    init(
        boundary: String,
        fieldName: String,
        fileName: String,
        mimeType: String,
        additionalFields: [String: String],
        imageData: Data
    ) {
        self.boundary = boundary
        self.fieldName = fieldName
        self.fileName = fileName
        self.mimeType = mimeType
        self.additionalFields = additionalFields
        self.imageData = imageData
        super.init(data: Data())  // Initialize with empty data, we'll override behavior

        prepareParts()
    }

    private func prepareParts() {
        // Part 1: Additional fields
        for (key, value) in additionalFields {
            let boundaryData = Data("--\(boundary)\r\n".utf8)
            let dispositionData = Data(
                "Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n".utf8)
            let valueData = Data("\(value)\r\n".utf8)

            parts.append(boundaryData)
            parts.append(dispositionData)
            parts.append(valueData)
        }

        // Part 2: Image data header
        let imageBoundaryData = Data("--\(boundary)\r\n".utf8)
        let imageDispositionData = Data(
            "Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(fileName)\"\r\n"
                .utf8)
        let imageTypeData = Data("Content-Type: \(mimeType)\r\n\r\n".utf8)

        parts.append(imageBoundaryData)
        parts.append(imageDispositionData)
        parts.append(imageTypeData)

        // Part 3: Image data (will be streamed in chunks)
        // Part 4: Closing boundary
        let closingBoundaryData = Data("\r\n--\(boundary)--\r\n".utf8)
        parts.append(closingBoundaryData)
    }

    override var hasBytesAvailable: Bool {
        return isOpen
            && (currentPart < parts.count
                || (currentPart == parts.count - 1 && partOffset < imageData.count))
    }

    override func open() {
        isOpen = true
        currentPart = 0
        partOffset = 0
    }

    override func close() {
        isOpen = false
    }

    override func read(_ buffer: UnsafeMutablePointer<UInt8>, maxLength len: Int) -> Int {
        guard isOpen else { return 0 }

        var bytesRead = 0
        var remainingLength = len

        while remainingLength > 0 && hasBytesAvailable {
            if currentPart < parts.count {
                // Reading from pre-built parts
                let part = parts[currentPart]
                let availableInPart = part.count - partOffset
                let bytesToRead = min(remainingLength, availableInPart)

                if bytesToRead > 0 {
                    part.copyBytes(
                        to: buffer.advanced(by: bytesRead),
                        from: partOffset..<partOffset + bytesToRead)
                    partOffset += bytesToRead
                    bytesRead += bytesToRead
                    remainingLength -= bytesToRead
                }

                // Move to next part if current part is exhausted
                if partOffset >= part.count {
                    currentPart += 1
                    partOffset = 0

                    // If we've moved to the image data part, break to handle it separately
                    if currentPart == parts.count - 1 {
                        break
                    }
                }
            } else if currentPart == parts.count - 1 {
                // Reading image data (the last part before closing boundary)
                let availableInImage = imageData.count - partOffset
                let bytesToRead = min(remainingLength, availableInImage)

                if bytesToRead > 0 {
                    imageData.copyBytes(
                        to: buffer.advanced(by: bytesRead),
                        from: partOffset..<partOffset + bytesToRead)
                    partOffset += bytesToRead
                    bytesRead += bytesToRead
                    remainingLength -= bytesToRead
                }

                // If image data is exhausted, move to closing boundary
                if partOffset >= imageData.count {
                    currentPart += 1
                    partOffset = 0
                }
            } else {
                // All parts exhausted
                break
            }
        }

        return bytesRead
    }

    override var streamStatus: Stream.Status {
        if !isOpen {
            return .notOpen
        } else if !hasBytesAvailable {
            return .atEnd
        } else {
            return .open
        }
    }

    override var streamError: Error? {
        return nil
    }
}
