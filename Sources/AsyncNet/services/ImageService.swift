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


public func platformImageToData(_ image: PlatformImage, compressionQuality: CGFloat = 0.8) -> Data? {
#if canImport(UIKit)
    return image.jpegData(compressionQuality: compressionQuality)
#elseif canImport(Cocoa)
    guard let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData) else { return nil }
    let properties: [NSBitmapImageRep.PropertyKey: Any] = [
        .compressionFactor: NSNumber(value: Double(compressionQuality))
    ]
    return bitmap.representation(using: .jpeg, properties: properties)
#else
    return nil
#endif
}

/// Protocol abstraction for URLSession to enable mocking in tests
public protocol URLSessionProtocol: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: URLSessionProtocol {}



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
    // MARK: - Request/Response Interceptor Support
    /// Protocol for request/response interceptors
    public protocol RequestInterceptor: Sendable {
        /// Called before a request is sent. Can modify the request.
        func willSend(request: URLRequest) async -> URLRequest
        /// Called after a response is received. Can inspect/modify response/data.
        func didReceive(response: URLResponse, data: Data?) async
    }

    private var interceptors: [RequestInterceptor] = []

    /// Set interceptors (replaces existing)
    public func setInterceptors(_ interceptors: [RequestInterceptor]) {
        self.interceptors = interceptors
    }
    // MARK: - Enhanced Caching Configuration
    public struct CacheConfiguration: Sendable {
        public let maxAge: TimeInterval // seconds
        public let maxLRUCount: Int
        public init(maxAge: TimeInterval = 3600, maxLRUCount: Int = 100) {
            self.maxAge = maxAge
            self.maxLRUCount = maxLRUCount
        }
    }

    private var cacheConfig: CacheConfiguration
    // LRU tracker: key -> (timestamp, accessIndex)
    private var lruTracker: [NSString: (timestamp: TimeInterval, accessIndex: Int)] = [:]
    private var lruOrder: [NSString] = [] // ordered by most recent access (front = most recent)
    private var lruCounter: Int = 0
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
                lastError = error
                // Custom error filter
                if let shouldRetry = config.shouldRetry {
                    if !shouldRetry(error) { throw error }
                } else if let netErr = error as? NetworkError {
                    switch netErr {
                    case .networkUnavailable, .requestTimeout:
                        break // eligible for retry
                    default:
                        throw error
                    }
                } else {
                    throw error
                }
                // Custom backoff strategy
                let delay: TimeInterval
                if let backoff = config.backoff {
                    delay = backoff(attempt)
                } else {
                    delay = config.baseDelay * pow(2.0, Double(attempt))
                }
                let jitter = Double.random(in: 0...config.jitter)
                try? await Task.sleep(nanoseconds: UInt64((delay + jitter) * 1_000_000_000))
                attempt += 1
                continue
            }
        }
        throw lastError ?? NetworkError.networkUnavailable
    }
    private let imageCache: NSCache<NSString, PlatformImage>
    private let dataCache: NSCache<NSString, NSData>
    private let urlSession: URLSessionProtocol
    // Deduplication: Track in-flight fetchImageData requests by URL string
    private var inFlightImageTasks: [String: Task<Data, Error>] = [:]

    public init(cacheCountLimit: Int = 100, cacheTotalCostLimit: Int = 50 * 1024 * 1024, urlSession: URLSessionProtocol? = nil) {
    imageCache = NSCache<NSString, PlatformImage>()
    imageCache.countLimit = cacheCountLimit // max number of images
    imageCache.totalCostLimit = cacheTotalCostLimit // max 50MB
    dataCache = NSCache<NSString, NSData>()
    dataCache.countLimit = cacheCountLimit
    dataCache.totalCostLimit = cacheTotalCostLimit
        self.cacheConfig = CacheConfiguration(maxLRUCount: cacheCountLimit)

    self.interceptors = []

        if let urlSession = urlSession {
            self.urlSession = urlSession
        } else {
            // Create custom URLSession with caching support
            let configuration = URLSessionConfiguration.default
            configuration.requestCachePolicy = .useProtocolCachePolicy
            configuration.urlCache = URLCache(
                memoryCapacity: 10 * 1024 * 1024, // 10MB memory cache
                diskCapacity: 100 * 1024 * 1024,  // 100MB disk cache
                diskPath: nil
            )
            self.urlSession = URLSession(configuration: configuration)
        }
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
        return try await fetchImageData(from: urlString, retryConfig: RetryConfiguration())

    }

    /// Fetches image data with configurable retry policy
    /// - Parameters:
    ///   - urlString: The URL string for the image
    ///   - retryConfig: Retry/backoff configuration
    /// - Returns: Image data
    /// - Throws: NetworkError if the request fails
    public func fetchImageData(from urlString: String, retryConfig: RetryConfiguration) async throws -> Data {
        let cacheKey = urlString as NSString
        // Check cache for image data, evict expired
        evictExpiredCache()
        if let cachedData = dataCache.object(forKey: cacheKey) {
            if let lruInfo = lruTracker[cacheKey], Date().timeIntervalSince1970 - lruInfo.timestamp < cacheConfig.maxAge {
                updateLRUOrder(for: cacheKey)
                return cachedData as Data
            }
        }

        // Deduplication: Check for in-flight task
        if let existingTask = inFlightImageTasks[urlString] {
            return try await existingTask.value
        }

        // Create new task for this request, with retry/backoff
        let fetchTask = Task<Data, Error> {
            let cacheKey = urlString as NSString
            let data = try await withRetry(config: retryConfig) {
                guard let url = URL(string: urlString),
                      let scheme = url.scheme, !scheme.isEmpty,
                      let host = url.host, !host.isEmpty else {
                    print("DEBUG: Invalid URL detected in fetchImageData: \(urlString)")
                    throw NetworkError.invalidEndpoint(reason: "Invalid image URL: \(urlString)")
                }

                var request = URLRequest(url: url)
                // Interceptor: willSend
                for interceptor in await self.interceptors {
                    request = await interceptor.willSend(request: request)
                }

                let (data, response) = try await self.urlSession.data(for: request)

                // Interceptor: didReceive
                for interceptor in await self.interceptors {
                    await interceptor.didReceive(response: response, data: data)
                }

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw NetworkError.noResponse
                }

                switch httpResponse.statusCode {
                case 200...299:
                    guard let mimeType = httpResponse.mimeType else {
                        throw NetworkError.badMimeType("no mimeType found")
                    }

                    let validMimeTypes = ["image/jpeg", "image/png", "image/gif", "image/webp", "image/heic"]
                    guard validMimeTypes.contains(mimeType) else {
                        throw NetworkError.badMimeType(mimeType)
                    }
                    return data

                case 401:
                    throw NetworkError.unauthorized
                default:
                    throw NetworkError.httpError(statusCode: httpResponse.statusCode, data: data)
                }
            }
            // Cache raw data for future use, assign cost as data length
            self.dataCache.setObject(data as NSData, forKey: cacheKey, cost: data.count)
            updateLRUOrder(for: cacheKey)
            return data
        }
        inFlightImageTasks[urlString] = fetchTask
        defer { inFlightImageTasks.removeValue(forKey: urlString) }
        return try await fetchTask.value
    }




    /// Converts image data to PlatformImage on the @MainActor (UI context)
    /// - Parameter data: Image data
    /// - Returns: PlatformImage (UIImage/NSImage)
    public static func platformImage(from data: Data) -> PlatformImage? {
        return PlatformImage(data: data)
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
    
    // MARK: - Image Uploading
    
    /// Configuration for image upload operations
    public struct UploadConfiguration: Sendable {
        public let fieldName: String
        public let fileName: String
        public let compressionQuality: CGFloat
        public let additionalFields: [String: String]
        
        public init(
            fieldName: String = "image",
            fileName: String = "image.jpg",
            compressionQuality: CGFloat = 0.8,
            additionalFields: [String: String] = [:]
        ) {
            self.fieldName = fieldName
            self.fileName = fileName
            self.compressionQuality = compressionQuality
            self.additionalFields = additionalFields
        }
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
        
        // Create multipart request
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        let boundary = "Boundary-" + UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        
        // Add additional fields
        for (key, value) in configuration.additionalFields {
            guard let boundaryData = "--\(boundary)\r\n".data(using: .utf8) else {
                throw NetworkError.imageProcessingFailed
            }
            body.append(boundaryData)
            guard let dispositionData = "Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n".data(using: .utf8) else {
                throw NetworkError.imageProcessingFailed
            }
            body.append(dispositionData)
            guard let valueData = "\(value)\r\n".data(using: .utf8) else {
                throw NetworkError.imageProcessingFailed
            }
            body.append(valueData)
        }
        
        // Add image data
    guard let imageBoundaryData = "--\(boundary)\r\n".data(using: .utf8) else {
        throw NetworkError.imageProcessingFailed
    }
    body.append(imageBoundaryData)
    guard let imageDispositionData = "Content-Disposition: form-data; name=\"\(configuration.fieldName)\"; filename=\"\(configuration.fileName)\"\r\n".data(using: .utf8) else {
        throw NetworkError.imageProcessingFailed
    }
    body.append(imageDispositionData)
    guard let imageTypeData = "Content-Type: image/jpeg\r\n\r\n".data(using: .utf8) else {
        throw NetworkError.imageProcessingFailed
    }
    body.append(imageTypeData)
    body.append(imageData)
    guard let closingBoundaryData = "\r\n--\(boundary)--\r\n".data(using: .utf8) else {
        throw NetworkError.imageProcessingFailed
    }
    body.append(closingBoundaryData)
        
        request.httpBody = body
        
        let (data, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.noResponse
        }

        switch httpResponse.statusCode {
        case 200...299:
            return data
        case 401:
            throw NetworkError.unauthorized
        default:
            throw NetworkError.httpError(statusCode: httpResponse.statusCode, data: data)
        }
    }
    
    /// Uploads image data as base64 string in JSON payload
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
        // Convert image to base64
        let base64String = imageData.base64EncodedString()
        
        // Create JSON payload
        var payload: [String: Any] = [
            configuration.fieldName: base64String
        ]
        
        // Add additional fields
        for (key, value) in configuration.additionalFields {
            payload[key] = value
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (data, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.noResponse
        }

        switch httpResponse.statusCode {
        case 200...299:
            return data
        case 401:
            throw NetworkError.unauthorized
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
        if let lruInfo = lruTracker[cacheKey], Date().timeIntervalSince1970 - lruInfo.timestamp < cacheConfig.maxAge {
            updateLRUOrder(for: cacheKey)
            return imageCache.object(forKey: cacheKey)
        }
        return nil
    }
    
    /// Clears all cached images
    public func clearCache() {
    imageCache.removeAllObjects()
    dataCache.removeAllObjects()
    lruTracker.removeAll()
    lruOrder.removeAll()
    }
    
    /// Removes a specific image from cache
    /// - Parameter key: The cache key to remove
    public func removeFromCache(key: String) {
    let cacheKey = key as NSString
    imageCache.removeObject(forKey: cacheKey)
    dataCache.removeObject(forKey: cacheKey)
    lruTracker.removeValue(forKey: cacheKey)
    lruOrder.removeAll { $0 == cacheKey }
    }

    /// Update LRU order and timestamp for a cache key
    private func updateLRUOrder(for cacheKey: NSString) {
        lruCounter += 1
        lruTracker[cacheKey] = (timestamp: Date().timeIntervalSince1970, accessIndex: lruCounter)
        lruOrder.removeAll { $0 == cacheKey }
        lruOrder.insert(cacheKey, at: 0)
        // Evict if over LRU count
        while lruOrder.count > cacheConfig.maxLRUCount {
            if let oldest = lruOrder.popLast() {
                imageCache.removeObject(forKey: oldest)
                dataCache.removeObject(forKey: oldest)
                lruTracker.removeValue(forKey: oldest)
            }
        }
    }

    /// Evict expired cache entries based on maxAge
    private func evictExpiredCache() {
        let now = Date().timeIntervalSince1970
        let expiredKeys = lruTracker.filter { now - $0.value.timestamp >= cacheConfig.maxAge }.map { $0.key }
        for key in expiredKeys {
            imageCache.removeObject(forKey: key)
            dataCache.removeObject(forKey: key)
            lruTracker.removeValue(forKey: key)
            lruOrder.removeAll { $0 == key }
        }
    }

    /// Update cache configuration (maxAge, maxLRUCount)
    public func updateCacheConfiguration(_ config: CacheConfiguration) {
        self.cacheConfig = config
        // Evict if new config is more strict
        evictExpiredCache()
        while lruOrder.count > cacheConfig.maxLRUCount {
            if let oldest = lruOrder.popLast() {
                imageCache.removeObject(forKey: oldest)
                dataCache.removeObject(forKey: oldest)
                lruTracker.removeValue(forKey: oldest)
            }
        }
    }
    
    // MARK: - Private Helpers
    
    private func imageToData(_ image: PlatformImage, compressionQuality: CGFloat) throws -> Data {
        #if canImport(UIKit)
        guard let data = image.jpegData(compressionQuality: compressionQuality) else {
            throw NetworkError.imageProcessingFailed
        }
        return data
        #elseif canImport(Cocoa)
        guard let tiffData = image.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData),
              let data = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: compressionQuality]) else {
            throw NetworkError.imageProcessingFailed
        }
        return data
        #endif
    }
}

// MARK: - Data Extension for String Appending
#if !os(Linux)
extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}
#endif

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

