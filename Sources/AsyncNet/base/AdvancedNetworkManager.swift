import Foundation
#if canImport(OSLog)
import OSLog
#endif

// MARK: - Request/Response Interceptor Protocol
public protocol NetworkInterceptor: Sendable {
    func willSend(request: URLRequest) async -> URLRequest
    func didReceive(response: URLResponse?, data: Data?) async
}

// MARK: - Caching Protocol
public protocol NetworkCache: Sendable {
    func get(forKey key: String) async -> Data?
    func set(_ data: Data, forKey key: String) async
    func remove(forKey key: String) async
    func clear() async
}

// MARK: - Default Network Cache Implementation
public actor DefaultNetworkCache: NetworkCache {
    private var cache: [String: (data: Data, timestamp: Date)] = [:]
    private let maxSize: Int
    private let expiration: TimeInterval

    public init(maxSize: Int = 100, expiration: TimeInterval = 600) {
        self.maxSize = maxSize
        self.expiration = expiration
    }

    public func get(forKey key: String) async -> Data? {
        guard let entry = cache[key], Date().timeIntervalSince(entry.timestamp) < expiration else {
            cache.removeValue(forKey: key)
            return nil
        }
        // Update timestamp to mark as recently used
        cache[key] = (entry.data, Date())
        return entry.data
    }

    public func set(_ data: Data, forKey key: String) async {
        if cache.count >= maxSize {
            let oldestKey = cache.min(by: { $0.value.timestamp < $1.value.timestamp })?.key
            if let oldestKey = oldestKey {
                cache.removeValue(forKey: oldestKey)
            }
        }
        cache[key] = (data, Date())
    }

    public func remove(forKey key: String) async {
        cache.removeValue(forKey: key)
    }

    public func clear() async {
        cache.removeAll()
    }
}

// MARK: - Advanced Network Manager Actor
public actor AdvancedNetworkManager {
    private var inFlightTasks: [String: Task<Data, Error>] = [:]
    private let cache: NetworkCache
    private let interceptors: [NetworkInterceptor]
    private let urlSession: URLSessionProtocol

    public init(cache: NetworkCache = DefaultNetworkCache(), interceptors: [NetworkInterceptor] = [], urlSession: URLSessionProtocol? = nil) {
        self.cache = cache
        self.interceptors = interceptors
        if let urlSession = urlSession {
            self.urlSession = urlSession
        } else {
            self.urlSession = URLSession.shared
        }
    }
    
    // MARK: - Request Deduplication, Retry, Backoff, Interceptors
    public func fetchData(for request: URLRequest, cacheKey: String? = nil, retryPolicy: RetryPolicy = .default) async throws -> Data {
        let key = cacheKey ?? generateRequestKey(from: request)
        if let cached = await cache.get(forKey: key) {
            #if canImport(OSLog)
            asyncNetLogger.debug("Cache hit for key: \(key)")
            #endif
            return cached
        }
        if let task = inFlightTasks[key] {
            #if canImport(OSLog)
            asyncNetLogger.debug("Request deduplication for key: \(key)")
            #endif
            return try await task.value
        }
        let newTask = Task<Data, Error> {
            var interceptedRequest = request
            for interceptor in interceptors {
                interceptedRequest = await interceptor.willSend(request: interceptedRequest)
            }
            var lastError: Error?
            // Initial attempt plus maxRetries additional attempts
            for attempt in 0...(retryPolicy.maxRetries) {
                do {
                    let (data, response) = try await urlSession.data(for: interceptedRequest)
                    for interceptor in interceptors {
                        await interceptor.didReceive(response: response, data: data)
                    }
                    // Only cache successful HTTP responses (200-299)
                    if let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) {
                        await cache.set(data, forKey: key)
                    }
                    #if canImport(OSLog)
                    if attempt > 0 {
                        asyncNetLogger.info("Request succeeded after \(attempt) retries for key: \(key)")
                    } else {
                        asyncNetLogger.debug("Request succeeded on first attempt for key: \(key)")
                    }
                    #endif
                    return data
                } catch {
                    lastError = error
                    #if canImport(OSLog)
                    asyncNetLogger.warning("Request attempt \(attempt + 1) failed for key: \(key), error: \(error.localizedDescription)")
                    #endif
                    // shouldRetry and backoff use the attempt index (0-based)
                    if let shouldRetry = retryPolicy.shouldRetry, !shouldRetry(error, attempt) {
                        break
                    }
                    let delay = retryPolicy.backoff?(attempt) ?? 0.0
                    if delay > 0 {
                        #if canImport(OSLog)
                        asyncNetLogger.debug("Retrying request for key: \(key) after \(delay) seconds")
                        #endif
                        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    }
                }
            }
            // If last error is a cancellation, propagate it
            if let lastError = lastError as? CancellationError {
                throw lastError
            }
            #if canImport(OSLog)
            asyncNetLogger.error("All retry attempts exhausted for key: \(key)")
            #endif
            throw lastError ?? NetworkError.customError("Unknown error in AdvancedNetworkManager", details: nil)
        }
        inFlightTasks[key] = newTask
        defer { inFlightTasks.removeValue(forKey: key) }
        return try await newTask.value
    }
    
    /// Generates a deterministic cache key from request components
    func generateRequestKey(from request: URLRequest) -> String {
        let urlString = request.url?.absoluteString ?? ""
        let method = request.httpMethod ?? "GET"
        let bodyString = request.httpBody?.base64EncodedString() ?? ""
        
        // Join components with a separator that's unlikely to appear in URLs or methods
        return [urlString, method, bodyString].joined(separator: "|")
    }
}

// MARK: - Retry Policy
public struct RetryPolicy: Sendable {
    public let maxRetries: Int
    public let shouldRetry: (@Sendable (Error, Int) -> Bool)?
    public let backoff: (@Sendable (Int) -> TimeInterval)?
    public let maxBackoff: TimeInterval
    
    public static let `default` = RetryPolicy(
        maxRetries: 3,
        shouldRetry: { _, _ in true }, // Always allow retry; maxRetries controls total attempts
        backoff: { attempt in min(pow(2.0, Double(attempt)) + Double.random(in: 0...0.5), 60.0) },
        maxBackoff: 60.0
    )
    
    public init(maxRetries: Int,
                shouldRetry: (@Sendable (Error, Int) -> Bool)? = nil,
                backoff: (@Sendable (Int) -> TimeInterval)? = nil,
                maxBackoff: TimeInterval = 60.0) {
        self.maxRetries = maxRetries
        self.shouldRetry = shouldRetry
        self.backoff = backoff
        self.maxBackoff = maxBackoff
    }
    
    /// Creates a retry policy with exponential backoff capped at the specified maximum
    public static func exponentialBackoff(maxRetries: Int = 3, maxBackoff: TimeInterval = 60.0) -> RetryPolicy {
        return RetryPolicy(
            maxRetries: maxRetries,
            shouldRetry: { _, _ in true },
            backoff: { attempt in min(pow(2.0, Double(attempt)) + Double.random(in: 0...0.5), maxBackoff) },
            maxBackoff: maxBackoff
        )
    }
    
    /// Creates a retry policy with custom backoff strategy
    public static func custom(maxRetries: Int = 3, 
                             maxBackoff: TimeInterval = 60.0,
                             backoff: @escaping (@Sendable (Int) -> TimeInterval)) -> RetryPolicy {
        return RetryPolicy(
            maxRetries: maxRetries,
            shouldRetry: { _, _ in true },
            backoff: { attempt in min(backoff(attempt), maxBackoff) },
            maxBackoff: maxBackoff
        )
    }
}

// NetworkError is defined elsewhere
