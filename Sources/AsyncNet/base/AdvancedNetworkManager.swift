import Foundation
import os

#if canImport(OSLog)
    import OSLog
#endif

#if canImport(CryptoKit)
    import CryptoKit
#endif

#if canImport(CommonCrypto)
    import CommonCrypto
#endif

/// AdvancedNetworkManager provides comprehensive network request management with:
/// - Request deduplication and caching
/// - Retry logic with exponential backoff and jitter
/// - Request/response interception
/// - Thread-safe actor-based implementation
/// - Integration with AsyncNet error handling (NetworkError, AsyncNetConfig)
///
/// Dependencies: NetworkError and AsyncNetConfig are defined in the same AsyncNet module
/// and are accessible without additional imports.

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
/// TestClock provides a controllable clock for deterministic testing.
/// All accesses to the internal time state are synchronized to prevent data races.
///
/// Design Decision: Uses OSAllocatedUnfairLock instead of actor-based isolation
/// - Performance: Extremely lightweight for simple property access (no suspension overhead)
/// - API Stability: Synchronous methods avoid breaking changes in test code
/// - Testing Context: Precision timing is critical for cache expiration tests
/// - Platform Requirements: Requires macOS 13.0+/iOS 16.0+ (acceptable for test infrastructure)
/// - Alternative Considered: Actor isolation would add unnecessary async complexity
///   and performance overhead for this synchronous, high-frequency use case
public final class TestClock: @unchecked Sendable {
    private var _now: ContinuousClock.Instant
    private let lock = OSAllocatedUnfairLock()

    public init() {
        _now = ContinuousClock().now
    }

    /// Returns the current time value in a thread-safe manner
    public func now() -> ContinuousClock.Instant {
        lock.lock()
        defer { lock.unlock() }
        return _now
    }

    /// Advances the clock by the specified duration in a thread-safe manner
    public func advance(by duration: Duration) {
        lock.lock()
        defer { lock.unlock() }
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
        var nodesToRemove: [Node] = []
        let initialCount = cache.count  // Capture stable count before cleanup
        let cleanupLimit = max(1, min(10, initialCount / 4))  // Check up to 25% or 10 entries, minimum 1
        var checked = 0
        var visitedNodes = Set<ObjectIdentifier>()

        // Start from tail and work backwards, checking for expired entries
        var current = tail
        while let node = current, checked < cleanupLimit {
            // Cycle detection: break if we've seen this node before
            let nodeId = ObjectIdentifier(node)
            if visitedNodes.contains(nodeId) {
                break
            }
            visitedNodes.insert(nodeId)

            if now - node.timestamp >= expiration {
                nodesToRemove.append(node)
            }
            current = node.prev
            checked += 1
        }

        // Remove expired nodes
        for node in nodesToRemove {
            removeNode(node)
            cache.removeValue(forKey: node.key)
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
                asyncNetLogger.debug("Cache hit for key: \(key, privacy: .private)")
            #endif
            return cached
        }
        if let task = inFlightTasks[key] {
            #if canImport(OSLog)
                asyncNetLogger.debug("Request deduplication for key: \(key, privacy: .private)")
            #endif
            return try await task.value
        }
        // Capture actor-isolated properties before creating Task to avoid isolation violations
        let capturedInterceptors = interceptors
        let capturedURLSession = urlSession
        let capturedCache = cache
        let newTask = Task<Data, Error> {
            // Check for cancellation at the start
            try Task.checkCancellation()

            var lastError: Error?
            // Perform up to maxAttempts total attempts (including the initial attempt)
            for attempt in 0..<retryPolicy.maxAttempts {
                // Check for cancellation before each retry attempt
                try Task.checkCancellation()

                // Create fresh request for each attempt, then apply interceptor chain
                var currentRequest = request
                for interceptor in capturedInterceptors {
                    currentRequest = await interceptor.willSend(request: currentRequest)
                }
                // Set timeout from retry policy for this attempt on the final intercepted request
                currentRequest.timeoutInterval = retryPolicy.timeoutInterval

                do {
                    let (data, response) = try await capturedURLSession.data(
                        for: currentRequest)
                    for interceptor in capturedInterceptors {
                        await interceptor.didReceive(response: response, data: data)
                    }
                    
                    // Validate HTTP response status code
                    if let httpResponse = response as? HTTPURLResponse {
                        switch httpResponse.statusCode {
                        case 200...299:
                            // Only cache successful responses for safe/idempotent HTTP methods
                            let shouldCache = shouldCacheResponse(
                                for: currentRequest, response: httpResponse)
                            if shouldCache {
                                await capturedCache.set(data, forKey: key)
                            }
                            #if canImport(OSLog)
                                if attempt > 0 {
                                    asyncNetLogger.info(
                                        "Request succeeded after \(attempt, privacy: .public) retries for key: \(key, privacy: .private)"
                                    )
                                } else {
                                    asyncNetLogger.debug(
                                        "Request succeeded on first attempt for key: \(key, privacy: .private)")
                                }
                            #endif
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
                            throw NetworkError.notFound(
                                data: data, statusCode: httpResponse.statusCode)
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
                    } else {
                        // Non-HTTP response: return data without caching
                        #if canImport(OSLog)
                            asyncNetLogger.debug(
                                "Non-HTTP response received for key: \(key, privacy: .private)")
                        #endif
                        return data
                    }
                } catch {
                    lastError = error
                    #if canImport(OSLog)
                        asyncNetLogger.warning(
                            "Request attempt \(attempt + 1, privacy: .public) failed for key: \(key, privacy: .private), error: \(error.localizedDescription, privacy: .public)"
                        )
                    #endif
                    // shouldRetry and backoff use the attempt index (0-based)
                    // Determine if we should retry based on custom logic or default behavior
                    let shouldRetryAttempt: Bool
                    if let customShouldRetry = retryPolicy.shouldRetry {
                        shouldRetryAttempt = customShouldRetry(error, attempt)
                    } else {
                        // Default behavior: always retry (maxAttempts controls total attempts)
                        let wrappedError = await NetworkError.wrapAsync(
                            error, config: AsyncNetConfig.shared)
                        #if canImport(OSLog)
                            asyncNetLogger.debug(
                                "Default retry behavior triggered for wrapped error: \(wrappedError.localizedDescription, privacy: .public)"
                            )
                        #endif
                        shouldRetryAttempt = true
                    }

                    // If custom logic says don't retry, break immediately
                    if !shouldRetryAttempt {
                        break
                    }

                    // Apply backoff with jitter for both custom and default retry paths
                    var delay = retryPolicy.backoff?(attempt) ?? 0.0
                    // Apply jitter if provider is specified (user is responsible for avoiding double jitter)
                    if let jitterProvider = retryPolicy.jitterProvider {
                        delay += jitterProvider(attempt)
                    }
                    let cappedDelay = min(max(delay, 0.0), retryPolicy.maxBackoff)
                    // Only sleep if this is not the final attempt
                    if attempt + 1 < retryPolicy.maxAttempts && cappedDelay > 0 {
                        #if canImport(OSLog)
                            asyncNetLogger.debug(
                                "Retrying request for key: \(key, privacy: .private) after \(cappedDelay, privacy: .public) seconds")
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
                asyncNetLogger.error(
                    "All retry attempts exhausted for key: \(key, privacy: .private)")
            #endif
            // Wrap non-cancellation errors consistently in NetworkError
            if let lastError = lastError {
                throw await NetworkError.wrapAsync(lastError, config: AsyncNetConfig.shared)
            } else {
                throw NetworkError.customError(
                    "Unknown error in AdvancedNetworkManager", details: nil)
            }
        }
        inFlightTasks[key] = newTask
        defer {
            inFlightTasks.removeValue(forKey: key)
        }

        do {
            return try await newTask.value
        } catch {
            // If this task was cancelled, cancel the stored task and clean up
            if error is CancellationError {
                // Atomically cancel the stored task in inFlightTasks to ensure proper cancellation
                cancelInFlightTask(forKey: key)
                // Note: Task removal is handled by the defer block above
            }
            // Wrap non-cancellation errors consistently in NetworkError
            throw await NetworkError.wrapAsync(error, config: AsyncNetConfig.shared)
        }
    }

    /// Generates a deterministic cache key from request components
    private func generateRequestKey(from request: URLRequest) -> String {
        let urlString = request.url?.absoluteString ?? ""
        let method = request.httpMethod ?? "GET"

        // Generate body hash instead of including raw body to avoid PII leakage
        let bodyHash = generateBodyHash(from: request.httpBody)

        // Filter out sensitive headers that could contain PII or credentials
        let sensitiveHeaders: Set<String> = [
            "authorization", "cookie", "set-cookie", "x-api-key", "x-auth-token",
            "x-csrf-token", "x-xsrf-token", "proxy-authorization",
            "x-session-id", "x-user-id", "x-access-token", "x-refresh-token",
            "authentication", "www-authenticate", "x-forwarded-for", "x-real-ip",
            "x-authorization", "api-key", "bearer",
            // Additional common auth headers
            "x-bearer-token", "x-api-token", "x-auth-key", "x-access-key",
            "x-secret-key", "x-private-key", "x-client-id", "x-client-secret",
            "x-app-key", "x-app-secret", "x-token", "x-auth", "x-api-secret",
            // Lowercase variants for consistency
            "bearer-token", "api-token", "auth-key", "access-key",
            "secret-key", "private-key", "client-id", "client-secret",
            "app-key", "app-secret", "token", "auth", "api-secret"
        ]

        // Include only non-sensitive headers, normalized to lowercase and sorted
        var headersString = ""
        if let headers = request.allHTTPHeaderFields {
            let filteredHeaders = headers.filter { header in
                !sensitiveHeaders.contains(header.key.lowercased())
            }
            let sortedHeaders = filteredHeaders.sorted(by: {
                $0.key.lowercased() < $1.key.lowercased()
            })
            headersString = sortedHeaders.map { "\($0.key.lowercased()):\($0.value)" }.joined(
                separator: ";")
        }

        return "\(method)|\(urlString)|\(bodyHash)|\(headersString)"
    }

    /// Generates a secure hash of the request body for cache key purposes
    private func generateBodyHash(from body: Data?) -> String {
        guard let body = body, !body.isEmpty else {
            return "empty"
        }

        #if canImport(CryptoKit)
            let hash = SHA256.hash(data: body)
            return "sha256:\(hash.map { String(format: "%02x", $0) }.joined())"
        #elseif canImport(CommonCrypto)
            // Use CommonCrypto's CC_SHA256 when available
            
            // Check for potential overflow when casting body.count to CC_LONG
            guard body.count <= CC_LONG.max else {
                // Handle large buffers by hashing incrementally to avoid overflow
                var context = CC_SHA256_CTX()
                CC_SHA256_Init(&context)

                // Process body in chunks to avoid CC_LONG overflow
                let chunkSize = Int(CC_LONG.max)
                var remainingData = body

                while !remainingData.isEmpty {
                    let chunk = remainingData.prefix(chunkSize)
                    remainingData = remainingData.dropFirst(chunkSize)

                    chunk.withUnsafeBytes { buffer in
                        _ = CC_SHA256_Update(&context, buffer.baseAddress, CC_LONG(chunk.count))
                    }
                }

                var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
                CC_SHA256_Final(&hash, &context)

                return "sha256:\(hash.map { String(format: "%02x", $0) }.joined())"
            }

            var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
            body.withUnsafeBytes { buffer in
                _ = CC_SHA256(buffer.baseAddress, CC_LONG(buffer.count), &hash)
            }
            return "sha256:\(hash.map { String(format: "%02x", $0) }.joined())"
        #else
            // Fallback to FNV-1a 64-bit hash over the entire body for better collision resistance
            let fnv1aHash = body.reduce(14695981039346656037) { hash, byte in
                let hash = hash ^ UInt64(byte)
                return hash &* 1099511628211
            }
            return "fallback:\(String(format: "%016llx", fnv1aHash)):\(body.count)"
        #endif
    }

    /// Determines if a response should be cached based on HTTP method and Cache-Control headers
    private func shouldCacheResponse(for request: URLRequest, response: HTTPURLResponse) -> Bool {
        // Only cache responses for safe/idempotent HTTP methods
        let method = request.httpMethod?.uppercased() ?? "GET"
        let safeMethods = ["GET", "HEAD"]
        guard safeMethods.contains(method) else {
            return false
        }

        // Don't cache if request contains Authorization header (case-insensitive)
        if let requestHeaders = request.allHTTPHeaderFields {
            let hasAuthorization = requestHeaders.keys.contains {
                $0.lowercased() == "authorization"
            }
            if hasAuthorization {
                return false
            }
        }

        // Check Cache-Control headers (case-insensitive)
        let normalizedResponseHeaders = response.allHeaderFields.reduce(into: [String: Any]()) {
            result, pair in
            if let keyString = pair.key as? String {
                result[keyString.lowercased()] = pair.value
            }
        }

        if let cacheControl = normalizedResponseHeaders["cache-control"] as? String {
            let directives = cacheControl.lowercased()

            // Don't cache if no-store, no-cache, private directives are present, or max-age=0
            if directives.contains("no-store") || directives.contains("no-cache")
                || directives.contains("private") || directives.contains("max-age=0")
            {
                return false
            }
        }

        return true
    }

    /// Atomically cancels a task in inFlightTasks if it exists and is not already cancelled
    /// This method ensures thread-safe cancellation by performing the check and cancel as one atomic operation
    private func cancelInFlightTask(forKey key: String) {
        if let storedTask = inFlightTasks[key], !storedTask.isCancelled {
            storedTask.cancel()
        }
    }
}

// MARK: - Retry Policy
public struct RetryPolicy: Sendable {
    /// Total number of attempts (initial attempt + retries). For example:
    /// - maxAttempts: 1 = 1 total attempt (no retries)
    /// - maxAttempts: 3 = 3 total attempts (1 initial + 2 retries)
    /// - maxAttempts: 5 = 5 total attempts (1 initial + 4 retries)
    public let maxAttempts: Int
    public let shouldRetry: (@Sendable (Error, Int) -> Bool)?
    public let backoff: (@Sendable (Int) -> TimeInterval)?
    public let maxBackoff: TimeInterval
    public let timeoutInterval: TimeInterval
    public let jitterProvider: (@Sendable (Int) -> TimeInterval)?

    public static let `default` = RetryPolicy(
        maxAttempts: 4,  // Total attempts: 1 initial + 3 retries
        shouldRetry: { error, _ in
            // Don't retry HTTP 3xx redirects, 4xx client errors or noResponse errors
            if let networkError = error as? NetworkError {
                switch networkError {
                case .httpError(let statusCode, _):
                    // Don't retry 3xx redirects or 4xx client errors
                    if (300...399).contains(statusCode) || (400...499).contains(statusCode) {
                        return false
                    }
                case .noResponse:
                    // Don't retry when response is not HTTP
                    return false
                default:
                    break
                }
            }
            return true
        },
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
        maxAttempts: Int,
        shouldRetry: (@Sendable (Error, Int) -> Bool)? = nil,
        backoff: (@Sendable (Int) -> TimeInterval)? = nil,
        maxBackoff: TimeInterval = 60.0,
        timeoutInterval: TimeInterval = 30.0,
        jitterProvider: (@Sendable (Int) -> TimeInterval)? = nil
    ) {
        self.maxAttempts = maxAttempts
        self.shouldRetry = shouldRetry
        self.backoff = backoff
        self.maxBackoff = maxBackoff
        self.timeoutInterval = timeoutInterval
        self.jitterProvider = jitterProvider
    }

    /// Creates a retry policy with exponential backoff (capped by maxBackoff parameter)
    public static func exponentialBackoff(
        maxAttempts: Int = 4, maxBackoff: TimeInterval = 60.0, timeoutInterval: TimeInterval = 30.0,
        jitterProvider: (@Sendable (Int) -> TimeInterval)? = nil
    ) -> RetryPolicy {
        return RetryPolicy(
            maxAttempts: maxAttempts,
            shouldRetry: { _, _ in true },
            backoff: { attempt in pow(2.0, Double(attempt)) },
            maxBackoff: maxBackoff,
            timeoutInterval: timeoutInterval,
            jitterProvider: jitterProvider
        )
    }

    /// Creates a retry policy with custom backoff strategy
    public static func custom(
        maxAttempts: Int = 4,
        maxBackoff: TimeInterval = 60.0,
        timeoutInterval: TimeInterval = 30.0,
        backoff: @escaping (@Sendable (Int) -> TimeInterval),
        jitterProvider: (@Sendable (Int) -> TimeInterval)? = nil
    ) -> RetryPolicy {
        return RetryPolicy(
            maxAttempts: maxAttempts,
            shouldRetry: { _, _ in true },
            backoff: backoff,
            maxBackoff: maxBackoff,
            timeoutInterval: timeoutInterval,
            jitterProvider: jitterProvider
        )
    }

    /// Creates a retry policy with exponential backoff and custom jitter provider
    public static func exponentialBackoffWithJitter(
        maxAttempts: Int = 4,
        maxBackoff: TimeInterval = 60.0,
        timeoutInterval: TimeInterval = 30.0,
        jitterProvider: @escaping (@Sendable (Int) -> TimeInterval)
    ) -> RetryPolicy {
        return RetryPolicy(
            maxAttempts: maxAttempts,
            shouldRetry: { _, _ in true },
            backoff: { attempt in pow(2.0, Double(attempt)) },
            maxBackoff: maxBackoff,
            timeoutInterval: timeoutInterval,
            jitterProvider: jitterProvider
        )
    }

    /// Creates a retry policy with exponential backoff and seeded RNG for reproducible jitter
    public static func exponentialBackoffWithSeed(
        maxAttempts: Int = 4,
        maxBackoff: TimeInterval = 60.0,
        timeoutInterval: TimeInterval = 30.0,
        seed: UInt64
    ) -> RetryPolicy {
        let jitterProvider: (@Sendable (Int) -> TimeInterval) = { attempt in
            // Use SplitMix64 PRNG for better statistical properties and uniform distribution
            let combinedSeed = seed &+ UInt64(attempt)

            // SplitMix64 algorithm - deterministic PRNG with good statistical properties
            var z = combinedSeed &+ 0x9E37_79B9_7F4A_7C15
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            let randomUInt64 = z ^ (z >> 31)

            // Scale UInt64 to TimeInterval range [0.0, 0.5)
            return Double(randomUInt64) / Double(UInt64.max) * 0.5
        }

        return RetryPolicy(
            maxAttempts: maxAttempts,
            shouldRetry: { _, _ in true },
            backoff: { attempt in pow(2.0, Double(attempt)) },
            maxBackoff: maxBackoff,
            timeoutInterval: timeoutInterval,
            jitterProvider: jitterProvider
        )
    }
}

/// Example: Create a retry policy with deterministic jitter for testing
/// ```swift
/// let policy = RetryPolicy.exponentialBackoffWithJitter(maxAttempts: 3) { attempt in
///     return Double(attempt) * 0.1 // Deterministic jitter based on attempt
/// }
/// ```
///
/// Example: Create a retry policy with seeded jitter for reproducible tests
/// ```swift
/// let policy = RetryPolicy.exponentialBackoffWithSeed(maxAttempts: 3, seed: 12345)
/// ```
// MARK: - Seeded Random Number Generator
/// A seeded random number generator for reproducible jitter in tests
public final class SeededRandomNumberGenerator: RandomNumberGenerator, @unchecked Sendable {
    private var state: UInt64
    private let lock = OSAllocatedUnfairLock()

    public init(seed: UInt64) {
        self.state = seed
    }

    public func next() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        // Simple linear congruential generator for reproducibility
        state = (2_862_933_555_777_941_757 &* state) &+ 3_037_000_493
        return state
    }
}
