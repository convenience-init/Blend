import Foundation

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

// MARK: - Default LRU Cache Implementation
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
        return entry.data
    }
    
    public func set(_ data: Data, forKey key: String) async {
        cache[key] = (data, Date())
        if cache.count > maxSize {
            let oldestKey = cache.min(by: { $0.value.timestamp < $1.value.timestamp })?.key
            if let oldestKey = oldestKey {
                cache.removeValue(forKey: oldestKey)
            }
        }
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
        let key = cacheKey ?? request.url?.absoluteString ?? UUID().uuidString
        if let cached = await cache.get(forKey: key) {
            return cached
        }
        if let task = inFlightTasks[key] {
            return try await task.value
        }
        let newTask = Task<Data, Error> {
            var interceptedRequest = request
            for interceptor in interceptors {
                interceptedRequest = await interceptor.willSend(request: interceptedRequest)
            }
            var lastError: Error?
            // maxRetries means total number of attempts (including the first)
            for attempt in 0..<retryPolicy.maxRetries {
                do {
                    let (data, response) = try await urlSession.data(for: interceptedRequest)
                    for interceptor in interceptors {
                        await interceptor.didReceive(response: response, data: data)
                    }
                    await cache.set(data, forKey: key)
                    return data
                } catch {
                    lastError = error
                    // shouldRetry and backoff use the attempt index (0-based)
                    if let shouldRetry = retryPolicy.shouldRetry, !shouldRetry(error, attempt) {
                        break
                    }
                    let delay = retryPolicy.backoff?(attempt) ?? 0.0
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
            throw lastError ?? NetworkError.customError("Unknown error in AdvancedNetworkManager", details: nil)
        }
        inFlightTasks[key] = newTask
        defer { inFlightTasks.removeValue(forKey: key) }
        return try await newTask.value
    }
}

// MARK: - Retry Policy
public struct RetryPolicy: Sendable {
    public let maxRetries: Int
    public let shouldRetry: (@Sendable (Error, Int) -> Bool)?
    public let backoff: (@Sendable (Int) -> TimeInterval)?
    
    public static let `default` = RetryPolicy(
        maxRetries: 3,
        shouldRetry: { _, _ in true }, // Always allow retry; maxRetries controls total attempts
        backoff: { attempt in pow(2.0, Double(attempt)) + Double.random(in: 0...0.5) }
    )
    
    public init(maxRetries: Int,
                shouldRetry: (@Sendable (Error, Int) -> Bool)? = nil,
                backoff: (@Sendable (Int) -> TimeInterval)? = nil) {
        self.maxRetries = maxRetries
        self.shouldRetry = shouldRetry
        self.backoff = backoff
    }
}

// NetworkError is defined elsewhere
