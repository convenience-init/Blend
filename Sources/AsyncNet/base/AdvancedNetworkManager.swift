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
    // LRU Node for doubly-linked list
    private final class Node: @unchecked Sendable {
        let key: String
        var data: Data
        var prev: Node?
        var next: Node?

        init(key: String, data: Data) {
            self.key = key
            self.data = data
        }
    }

    private var cache: [String: Node] = [:]
    private var head: Node?
    private var tail: Node?
    private let maxSize: Int
    private let expiration: TimeInterval

    public init(maxSize: Int = 100, expiration: TimeInterval = 600) {
        self.maxSize = maxSize
        self.expiration = expiration
    }

    public func get(forKey key: String) async -> Data? {
        guard let node = cache[key] else {
            return nil
        }

        // Move accessed node to head (most recently used)
        moveToHead(node)
        return node.data
    }

    public func set(_ data: Data, forKey key: String) async {
        if let existingNode = cache[key] {
            // Update existing node
            existingNode.data = data
            moveToHead(existingNode)
            return
        }

        // Create new node
        let newNode = Node(key: key, data: data)
        cache[key] = newNode

        // Add to head of list
        addToHead(newNode)

        // Evict if over capacity
        if cache.count > maxSize {
            removeTail()
        }
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
            // Create URLSession with reasonable default timeouts
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = 30.0
            configuration.timeoutIntervalForResource = 300.0 // 5 minutes for resource timeout
            self.urlSession = URLSession(configuration: configuration)
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
                    // Default retry behavior: retry on network errors and timeouts
                    let wrappedError = NetworkError.wrap(error)
                    if case .networkUnavailable = wrappedError {
                        // Continue to retry
                    } else if case .requestTimeout = wrappedError {
                        // Continue to retry timeouts
                    } else if case .transportError = wrappedError {
                        // Continue to retry transport errors
                    } else {
                        // Don't retry other types of errors by default
                        break
                    }
                    let delay = retryPolicy.backoff?(attempt) ?? 0.0
                    let cappedDelay = min(max(delay, 0.0), retryPolicy.maxBackoff)
                    if cappedDelay > 0 {
                        #if canImport(OSLog)
                        asyncNetLogger.debug("Retrying request for key: \(key) after \(cappedDelay) seconds")
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
        
        // Include relevant headers that affect the response
        let relevantHeaders = ["Authorization", "Accept", "Content-Type"]
        let headerString = relevantHeaders.compactMap { header in
            request.allHTTPHeaderFields?[header].map { "\(header):\($0)" }
        }.joined(separator: ",")
        
        // Join components with a separator that's unlikely to appear in URLs or methods
        return [urlString, method, bodyString, headerString].joined(separator: "|")
    }
}

// MARK: - Retry Policy
public struct RetryPolicy: Sendable {
    public let maxRetries: Int
    public let shouldRetry: (@Sendable (Error, Int) -> Bool)?
    public let backoff: (@Sendable (Int) -> TimeInterval)?
    public let maxBackoff: TimeInterval
    public let timeoutInterval: TimeInterval
    
    public static let `default` = RetryPolicy(
        maxRetries: 3,
        shouldRetry: { _, _ in true }, // Always allow retry; maxRetries controls total attempts
        backoff: { attempt in pow(2.0, Double(attempt)) + Double.random(in: 0...0.5) },
        maxBackoff: 60.0,
        timeoutInterval: 30.0
    )
    
    public init(maxRetries: Int,
                shouldRetry: (@Sendable (Error, Int) -> Bool)? = nil,
                backoff: (@Sendable (Int) -> TimeInterval)? = nil,
                maxBackoff: TimeInterval = 60.0,
                timeoutInterval: TimeInterval = 30.0) {
        self.maxRetries = maxRetries
        self.shouldRetry = shouldRetry
        self.backoff = backoff
        self.maxBackoff = maxBackoff
        self.timeoutInterval = timeoutInterval
    }
    
    /// Creates a retry policy with exponential backoff (capped by maxBackoff parameter)
    public static func exponentialBackoff(maxRetries: Int = 3, maxBackoff: TimeInterval = 60.0, timeoutInterval: TimeInterval = 30.0) -> RetryPolicy {
        return RetryPolicy(
            maxRetries: maxRetries,
            shouldRetry: { _, _ in true },
            backoff: { attempt in pow(2.0, Double(attempt)) + Double.random(in: 0...0.5) },
            maxBackoff: maxBackoff,
            timeoutInterval: timeoutInterval
        )
    }
    
    /// Creates a retry policy with custom backoff strategy
    public static func custom(maxRetries: Int = 3, 
                             maxBackoff: TimeInterval = 60.0,
                             timeoutInterval: TimeInterval = 30.0,
                             backoff: @escaping (@Sendable (Int) -> TimeInterval)) -> RetryPolicy {
        return RetryPolicy(
            maxRetries: maxRetries,
            shouldRetry: { _, _ in true },
            backoff: backoff,
            maxBackoff: maxBackoff,
            timeoutInterval: timeoutInterval
        )
    }
}

// NetworkError is defined elsewhere
