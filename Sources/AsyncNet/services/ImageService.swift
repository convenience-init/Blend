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
    // MARK: - Image Uploading

    /// Returns true if an image is cached for the given key (actor-isolated, Sendable)
    public func isImageCached(forKey key: String) async -> Bool {
        return await cacheActor.isImageCached(forKey: key)
    }
    // cacheHits and cacheMisses are public actor variables for test access
    // MARK: - Request/Response Interceptor Support

    var interceptors: [RequestInterceptor] = []

    /// Set interceptors (replaces existing)
    public func setInterceptors(_ interceptors: [RequestInterceptor]) {
        self.interceptors = interceptors
    }

    /// Test-only stored property for overriding default retry configuration
    internal var overrideRetryConfiguration: RetryConfiguration?

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
    internal func withRetry<T: Sendable>(
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
    internal let imageCache: Cache<String, SendableImage>
    internal let dataCache: Cache<String, SendableData>
    internal let injectedURLSession: URLSessionProtocol?

    // Cache actor for LRU and expiration management
    internal let cacheActor: CacheActor

    // Computed property that returns the injected session or uses shared default
    var urlSession: URLSessionProtocol {
        return injectedURLSession ?? sharedURLSession
    }

    // Deduplication: Track in-flight fetchImageData requests by URL string
    internal var inFlightImageTasks: [String: Task<Data, Error>] = [:]

    /// Per-instance maximum upload size override (nil means use global AsyncNetConfig.shared.maxUploadSize)
    internal let maxUploadSize: Int?

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
