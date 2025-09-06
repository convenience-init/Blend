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
        let key = cacheKey ?? RequestUtilities.generateRequestKey(from: request)
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
                // Create a new request with the retry policy timeout to avoid mutating the original
                let requestWithTimeout = {
                    var newRequest = currentRequest
                    newRequest.timeoutInterval = retryPolicy.timeoutInterval
                    return newRequest
                }()

                do {
                    let (data, response) = try await capturedURLSession.data(
                        for: requestWithTimeout)
                    for interceptor in capturedInterceptors {
                        await interceptor.didReceive(response: response, data: data)
                    }
                    
                    // Validate HTTP response status code
                    if let httpResponse = response as? HTTPURLResponse {
                        try RequestUtilities.validateHTTPResponse(httpResponse, data: data)
                        // Only cache successful responses for safe/idempotent HTTP methods
                        let shouldCache = RequestUtilities.shouldCacheResponse(
                            for: requestWithTimeout, response: httpResponse)
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
                                    "Request succeeded on first attempt for key: \(key, privacy: .private)"
                                )
                            }
                        #endif
                        return data
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
                    
                    // Handle retry logic
                    let shouldContinue = try await RequestUtilities.handleRetryAttempt(
                        error: error, attempt: attempt, retryPolicy: retryPolicy, key: key)
                    if !shouldContinue {
                        break
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

    /// Atomically cancels a task in inFlightTasks if it exists and is not already cancelled
    /// This method ensures thread-safe cancellation by performing the check and cancel as one atomic operation
    private func cancelInFlightTask(forKey key: String) {
        if let storedTask = inFlightTasks[key], !storedTask.isCancelled {
            storedTask.cancel()
        }
    }
}
