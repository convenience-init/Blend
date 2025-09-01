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

// MARK: - Test Clock for Deterministic Testing
public final class TestClock: @unchecked Sendable {
    private var _now: ContinuousClock.Instant = .now

    public init() {}

    public func now() -> ContinuousClock.Instant {
        _now
    }

    public func advance(by duration: Duration) {
        _now = _now.advanced(by: duration)
    }
}

// MARK: - Default Network Cache Implementation
public actor DefaultNetworkCache: NetworkCache {
    // LRU Node for doubly-linked list
    private final class Node {
        let key: String
        var data: Data
        var prev: Node?
        var next: Node?
        var timestamp: ContinuousClock.Instant

        init(key: String, data: Data, timestamp: ContinuousClock.Instant) {
            self.key = key
            self.data = data
            self.timestamp = timestamp
        }
    }

    private var cache: [String: Node] = [:]
    private var head: Node?
    private var tail: Node?
    private let maxSize: Int
    private let expiration: Duration

    // Time provider for testing - can be overridden
    private let timeProvider: () -> ContinuousClock.Instant

    public init(
        maxSize: Int = 100,
        expiration: TimeInterval = 600
    ) {
        self.maxSize = maxSize
        self.expiration = .seconds(expiration)
        self.timeProvider = { ContinuousClock().now }
    }

    // Test-only initializer
    internal init(
        maxSize: Int = 100,
        expiration: TimeInterval = 600,
        timeProvider: @escaping () -> ContinuousClock.Instant
    ) {
        self.maxSize = maxSize
        self.expiration = .seconds(expiration)
        self.timeProvider = timeProvider
    }

    public func get(forKey key: String) async -> Data? {
        guard let node = cache[key] else {
            return nil
        }

        let now = timeProvider()
        // Check if entry has expired
        if now - node.timestamp >= expiration {
            // Remove expired entry
            removeNode(node)
            cache.removeValue(forKey: key)
            return nil
        }

        // Move accessed node to head (most recently used)
        moveToHead(node)
        return node.data
    }

    public func set(_ data: Data, forKey key: String) async {
        let now = timeProvider()

        if let existingNode = cache[key] {
            // Update existing node with new timestamp
            existingNode.data = data
            existingNode.timestamp = now
            moveToHead(existingNode)
            return
        }

        // Perform lightweight cleanup of expired items before adding new entry
        await performLightweightCleanup()

        // If at max capacity, evict LRU entry before adding new one
        if cache.count >= maxSize {
            removeTail()
        }

        // Create new node with current timestamp
        let newNode = Node(key: key, data: data, timestamp: now)
        cache[key] = newNode

        // Add to head of list
        addToHead(newNode)
    }

    public func remove(forKey key: String) async {
        guard let node = cache[key] else { return }
        removeNode(node)
        cache.removeValue(forKey: key)
    }

    public func clear() async {
        cache.removeAll()
        head = nil
        tail = nil
    }

    /// Performs a comprehensive cleanup of expired entries
    /// This method traverses the entire cache and can be called periodically
    /// or when you want to ensure all expired entries are removed
    public func cleanupExpiredEntries() async {
        let now = timeProvider()
        var nodesToRemove: [Node] = []

        // Collect expired nodes
        for (_, node) in cache {
            if now - node.timestamp >= expiration {
                nodesToRemove.append(node)
            }
        }

        // Remove expired nodes
        for node in nodesToRemove {
            removeNode(node)
            cache.removeValue(forKey: node.key)
        }
    }

    // MARK: - LRU Helper Methods

    private func addToHead(_ node: Node) {
        node.next = head
        node.prev = nil

        if let headNode = head {
            headNode.prev = node
        } else {
            tail = node
        }

        head = node
    }

    private func moveToHead(_ node: Node) {
        // If already head, no need to move
        if node === head {
            return
        }

        // Remove from current position
        removeNode(node)

        // Add to head
        addToHead(node)
    }

    private func removeNode(_ node: Node) {
        if let prev = node.prev {
            prev.next = node.next
        } else {
            // Node is head
            head = node.next
        }

        if let next = node.next {
            next.prev = node.prev
        } else {
            // Node is tail
            tail = node.prev
        }

        node.prev = nil
        node.next = nil
    }

    private func removeTail() {
        guard let tailNode = tail else { return }

        if let prev = tailNode.prev {
            prev.next = nil
            tail = prev
        } else {
            // Only one node
            head = nil
            tail = nil
        }

        cache.removeValue(forKey: tailNode.key)
    }

    private func performLightweightCleanup() async {
        let now = timeProvider()

        // Lightweight cleanup: only check and remove expired entries from the tail
        // This is efficient since expired entries tend to be older (towards the tail)
        while let tailNode = tail {
            if now - tailNode.timestamp >= expiration {
                removeTail()
            } else {
                // Tail is not expired, no need to check further
                break
            }
        }
    }
}

// MARK: - Advanced Network Manager Actor
public actor AdvancedNetworkManager {
    private var inFlightTasks: [String: Task<Data, Error>] = [:]
    private let cache: NetworkCache
    private let interceptors: [NetworkInterceptor]
    private let urlSession: URLSessionProtocol

    public init(
        cache: NetworkCache = DefaultNetworkCache(), interceptors: [NetworkInterceptor] = [],
        urlSession: URLSessionProtocol? = nil
    ) {
        self.cache = cache
        self.interceptors = interceptors
        if let urlSession = urlSession {
            self.urlSession = urlSession
        } else {
            // Create URLSession with reasonable default timeouts
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = 30.0
            configuration.timeoutIntervalForResource = 300.0  // 5 minutes for resource timeout
            self.urlSession = URLSession(configuration: configuration)
        }
    }

    // MARK: - Request Deduplication, Retry, Backoff, Interceptors
    public func fetchData(
        for request: URLRequest, cacheKey: String? = nil, retryPolicy: RetryPolicy = .default
    ) async throws -> Data {
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
            // Set timeout from retry policy
            interceptedRequest.timeoutInterval = retryPolicy.timeoutInterval

            var lastError: Error?
            // Initial attempt plus maxRetries additional attempts
            for attempt in 0...(retryPolicy.maxRetries) {
                do {
                    let (data, response) = try await urlSession.data(for: interceptedRequest)
                    for interceptor in interceptors {
                        await interceptor.didReceive(response: response, data: data)
                    }
                    // Only cache successful HTTP responses (200-299)
                    if let httpResponse = response as? HTTPURLResponse,
                        (200...299).contains(httpResponse.statusCode)
                    {
                        await cache.set(data, forKey: key)
                    }
                    #if canImport(OSLog)
                        if attempt > 0 {
                            asyncNetLogger.info(
                                "Request succeeded after \(attempt) retries for key: \(key)")
                        } else {
                            asyncNetLogger.debug(
                                "Request succeeded on first attempt for key: \(key)")
                        }
                    #endif
                    return data
                } catch {
                    lastError = error
                    #if canImport(OSLog)
                        asyncNetLogger.warning(
                            "Request attempt \(attempt + 1) failed for key: \(key), error: \(error.localizedDescription)"
                        )
                    #endif
                    // shouldRetry and backoff use the attempt index (0-based)
                    // Determine if we should retry based on custom logic or default behavior
                    let shouldRetryAttempt: Bool
                    if let customShouldRetry = retryPolicy.shouldRetry {
                        shouldRetryAttempt = customShouldRetry(error, attempt)
                    } else {
                        // Default behavior: always retry (maxRetries controls total attempts)
                        _ = await NetworkError.wrapAsync(error, config: AsyncNetConfig.shared)
                        shouldRetryAttempt = true
                    }

                    // If custom logic says don't retry, break immediately
                    if !shouldRetryAttempt {
                        break
                    }

                    // Apply backoff with jitter for both custom and default retry paths
                    var delay = retryPolicy.backoff?(attempt) ?? 0.0
                    // Apply additional jitter if provided separately
                    if let jitterProvider = retryPolicy.jitterProvider {
                        delay += jitterProvider(attempt)
                    }
                    let cappedDelay = min(max(delay, 0.0), retryPolicy.maxBackoff)
                    // Only sleep if this is not the final attempt
                    if attempt < retryPolicy.maxRetries && cappedDelay > 0 {
                        #if canImport(OSLog)
                            asyncNetLogger.debug(
                                "Retrying request for key: \(key) after \(cappedDelay) seconds")
                        #endif
                        try await Task.sleep(nanoseconds: UInt64(cappedDelay * 1_000_000_000))
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
            throw lastError
                ?? NetworkError.customError("Unknown error in AdvancedNetworkManager", details: nil)
        }
        inFlightTasks[key] = newTask
        defer { inFlightTasks.removeValue(forKey: key) }
        return try await newTask.value
    }

    /// Generates a deterministic cache key from request components
    private func generateRequestKey(from request: URLRequest) -> String {
        let urlString = request.url?.absoluteString ?? ""
        let method = request.httpMethod ?? "GET"
        let bodyString = request.httpBody?.base64EncodedString() ?? ""

        // Include relevant headers that affect the response
        var headersString = ""
        if let headers = request.allHTTPHeaderFields {
            let sortedHeaders = headers.sorted(by: { $0.key < $1.key })
            headersString = sortedHeaders.map { "\($0.key):\($0.value)" }.joined(separator: ";")
        }

        return "\(method)|\(urlString)|\(bodyString)|\(headersString)"
    }
}

// MARK: - Retry Policy
public struct RetryPolicy: Sendable {
    public let maxRetries: Int
    public let shouldRetry: (@Sendable (Error, Int) -> Bool)?
    public let backoff: (@Sendable (Int) -> TimeInterval)?
    public let maxBackoff: TimeInterval
    public let timeoutInterval: TimeInterval
    public let jitterProvider: (@Sendable (Int) -> TimeInterval)?

    public static let `default` = RetryPolicy(
        maxRetries: 3,
        shouldRetry: { _, _ in true },  // Always allow retry; maxRetries controls total attempts
        backoff: { attempt in
            // Use hash-based jitter for better distribution
            let hash = UInt64(attempt).multipliedFullWidth(by: 0x9E37_79B9_7F4A_7C15).high
            let jitter = Double(hash % 500) / 1000.0  // 0 to 0.5
            return pow(2.0, Double(attempt)) + jitter
        },
        maxBackoff: 60.0,
        timeoutInterval: 30.0
    )

    public init(
        maxRetries: Int,
        shouldRetry: (@Sendable (Error, Int) -> Bool)? = nil,
        backoff: (@Sendable (Int) -> TimeInterval)? = nil,
        maxBackoff: TimeInterval = 60.0,
        timeoutInterval: TimeInterval = 30.0,
        jitterProvider: (@Sendable (Int) -> TimeInterval)? = nil
    ) {
        self.maxRetries = maxRetries
        self.shouldRetry = shouldRetry
        self.backoff = backoff
        self.maxBackoff = maxBackoff
        self.timeoutInterval = timeoutInterval
        self.jitterProvider = jitterProvider
    }

    /// Creates a retry policy with exponential backoff (capped by maxBackoff parameter)
    public static func exponentialBackoff(
        maxRetries: Int = 3, maxBackoff: TimeInterval = 60.0, timeoutInterval: TimeInterval = 30.0,
        jitterProvider: (@Sendable (Int) -> TimeInterval)? = nil
    ) -> RetryPolicy {
        let defaultJitter: (@Sendable (Int) -> TimeInterval) = { attempt in
            // Deterministic jitter based on attempt number: sin(attempt) * 0.25 + 0.25
            // This gives values between 0 and 0.5, similar to the original random range
            return sin(Double(attempt)) * 0.25 + 0.25
        }

        let jitter = jitterProvider ?? defaultJitter

        return RetryPolicy(
            maxRetries: maxRetries,
            shouldRetry: { _, _ in true },
            backoff: { attempt in pow(2.0, Double(attempt)) + jitter(attempt) },
            maxBackoff: maxBackoff,
            timeoutInterval: timeoutInterval,
            jitterProvider: jitterProvider
        )
    }

    /// Creates a retry policy with custom backoff strategy
    public static func custom(
        maxRetries: Int = 3,
        maxBackoff: TimeInterval = 60.0,
        timeoutInterval: TimeInterval = 30.0,
        backoff: @escaping (@Sendable (Int) -> TimeInterval),
        jitterProvider: (@Sendable (Int) -> TimeInterval)? = nil
    ) -> RetryPolicy {
        return RetryPolicy(
            maxRetries: maxRetries,
            shouldRetry: { _, _ in true },
            backoff: backoff,
            maxBackoff: maxBackoff,
            timeoutInterval: timeoutInterval,
            jitterProvider: jitterProvider
        )
    }

    /// Creates a retry policy with exponential backoff and custom jitter provider
    public static func exponentialBackoffWithJitter(
        maxRetries: Int = 3,
        maxBackoff: TimeInterval = 60.0,
        timeoutInterval: TimeInterval = 30.0,
        jitterProvider: @escaping (@Sendable (Int) -> TimeInterval)
    ) -> RetryPolicy {
        return RetryPolicy(
            maxRetries: maxRetries,
            shouldRetry: { _, _ in true },
            backoff: { attempt in pow(2.0, Double(attempt)) + jitterProvider(attempt) },
            maxBackoff: maxBackoff,
            timeoutInterval: timeoutInterval,
            jitterProvider: jitterProvider
        )
    }

    /// Creates a retry policy with exponential backoff and seeded RNG for reproducible jitter
    public static func exponentialBackoffWithSeed(
        maxRetries: Int = 3,
        maxBackoff: TimeInterval = 60.0,
        timeoutInterval: TimeInterval = 30.0,
        seed: UInt64
    ) -> RetryPolicy {
        let jitterProvider: (@Sendable (Int) -> TimeInterval) = { attempt in
            // Use a deterministic hash of seed + attempt for reproducible jitter
            let hash = seed &+ UInt64(attempt)
            // Convert hash to a value between 0 and 0.5
            return Double(hash % 500) / 1000.0
        }

        return RetryPolicy(
            maxRetries: maxRetries,
            shouldRetry: { _, _ in true },
            backoff: { attempt in pow(2.0, Double(attempt)) + jitterProvider(attempt) },
            maxBackoff: maxBackoff,
            timeoutInterval: timeoutInterval,
            jitterProvider: jitterProvider
        )
    }
}

/// Example: Create a retry policy with deterministic jitter for testing
/// ```swift
/// let policy = RetryPolicy.exponentialBackoffWithJitter(maxRetries: 3) { attempt in
///     return Double(attempt) * 0.1 // Deterministic jitter based on attempt
/// }
/// ```
///
/// Example: Create a retry policy with seeded jitter for reproducible tests
/// ```swift
/// let policy = RetryPolicy.exponentialBackoffWithSeed(maxRetries: 3, seed: 12345)
/// ```
// MARK: - Seeded Random Number Generator
/// A seeded random number generator for reproducible jitter in tests
public final class SeededRandomNumberGenerator: RandomNumberGenerator, @unchecked Sendable {
    private var state: UInt64
    private let lock = NSLock()

    public init(seed: UInt64) {
        self.state = seed
    }

    public func next() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        // Simple linear congruential generator for reproducibility
        state = 2_862_933_555_777_941_757 * state + 3_037_000_493
        return state
    }
}

// NetworkError is defined elsewhere
