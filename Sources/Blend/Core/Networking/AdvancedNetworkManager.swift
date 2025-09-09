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

// MARK: - Advanced Network Manager Actor
/// AdvancedNetworkManager provides comprehensive network request management with:
/// - Request deduplication and caching
/// - Retry logic with exponential backoff and jitter
/// - Request/response interception
/// - Thread-safe actor-based implementation
/// - Integration with Blend error handling (NetworkError, AsyncNetConfig)
///
/// Dependencies: NetworkError and AsyncNetConfig are defined in the same Blend module
/// and are accessible without additional imports.
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

        // Check cache first
        if let cached = await cache.get(forKey: key) {
            #if canImport(OSLog)
                blendLogger.debug("Cache hit for key: \(key, privacy: .private)")
            #endif
            return cached
        }

        // Check for in-flight request deduplication
        if let task = inFlightTasks[key] {
            #if canImport(OSLog)
                blendLogger.debug("Request deduplication for key: \(key, privacy: .private)")
            #endif
            return try await task.value
        }

        // Create and execute new request with retry logic
        return try await executeRequestWithRetry(request, key: key, retryPolicy: retryPolicy)
    }

    private func executeRequestWithRetry(
        _ request: URLRequest, key: String, retryPolicy: RetryPolicy
    ) async throws -> Data {
        // Capture actor-isolated properties before creating Task
        let capturedInterceptors = interceptors
        let capturedURLSession = urlSession
        let capturedCache = cache

        let newTask = Task<Data, Error> {
            var lastError: Error?

            // Perform up to maxAttempts total attempts
            for attempt in 0..<retryPolicy.maxAttempts {
                try Task.checkCancellation()

                do {
                    let (data, response) = try await performSingleRequest(
                        request, attempt: attempt, retryPolicy: retryPolicy,
                        interceptors: capturedInterceptors, urlSession: capturedURLSession)

                    // Cache successful response if appropriate
                    await cacheSuccessfulResponseIfNeeded(
                        data, response: response, for: request, key: key, cache: capturedCache)

                    #if canImport(OSLog)
                        logRequestSuccess(attempt: attempt, key: key)
                    #endif

                    return data
                } catch {
                    lastError = error
                    #if canImport(OSLog)
                        let attemptNum = attempt + 1
                        let prefix = "Request attempt \(attemptNum) failed for key: \(key)"
                        let suffix = "error: \(error.localizedDescription)"
                        blendLogger.warning("\(prefix), \(suffix, privacy: .public)")
                    #endif

                    let shouldContinue = try await RequestUtilities.handleRetryAttempt(
                        error: error, attempt: attempt, retryPolicy: retryPolicy, key: key)
                    if !shouldContinue {
                        break
                    }
                }
            }

            // Handle final error
            return try await handleFinalError(lastError, key: key)
        }

        inFlightTasks[key] = newTask
        defer {
            inFlightTasks.removeValue(forKey: key)
        }

        do {
            return try await newTask.value
        } catch {
            if error is CancellationError {
                cancelInFlightTask(forKey: key)
            }
            throw await NetworkError.wrapAsync(error, config: BlendConfig.shared)
        }
    }

    private func performSingleRequest(
        _ request: URLRequest, attempt: Int, retryPolicy: RetryPolicy,
        interceptors: [NetworkInterceptor], urlSession: URLSessionProtocol
    ) async throws -> (Data, URLResponse) {
        try Task.checkCancellation()

        // Apply interceptor chain
        var currentRequest = request
        for interceptor in interceptors {
            currentRequest = await interceptor.willSend(request: currentRequest)
        }

        // Create request with retry timeout
        let requestWithTimeout = createRequestWithTimeout(currentRequest, retryPolicy: retryPolicy)

        let (data, response) = try await urlSession.data(for: requestWithTimeout)

        // Apply response interceptors
        for interceptor in interceptors {
            await interceptor.didReceive(response: response, data: data)
        }

        // Validate HTTP response
        if let httpResponse = response as? HTTPURLResponse {
            try RequestUtilities.validateHTTPResponse(httpResponse, data: data)
        }

        return (data, response)
    }

    private func createRequestWithTimeout(
        _ request: URLRequest, retryPolicy: RetryPolicy
    ) -> URLRequest {
        var newRequest = request
        newRequest.timeoutInterval = retryPolicy.timeoutInterval
        return newRequest
    }

    private func cacheSuccessfulResponseIfNeeded(
        _ data: Data, response: URLResponse, for request: URLRequest, key: String,
        cache: NetworkCache
    ) async {
        guard let httpResponse = response as? HTTPURLResponse else {
            return
        }

        let shouldCache = RequestUtilities.shouldCacheResponse(for: request, response: httpResponse)
        if shouldCache {
            await cache.set(data, forKey: key)
        }
    }

    private func logRequestSuccess(attempt: Int, key: String) {
        #if canImport(OSLog)
            if attempt > 0 {
                blendLogger.info(
                    "Request succeeded after \(attempt, privacy: .public) retries for key: \(key, privacy: .private)"
                )
            } else {
                blendLogger.debug(
                    "Request succeeded on first attempt for key: \(key, privacy: .private)"
                )
            }
        #endif
    }

    private func handleFinalError(_ lastError: Error?, key: String) async throws -> Data {
        if let lastError = lastError as? CancellationError {
            throw lastError
        }

        #if canImport(OSLog)
            blendLogger.error("All retry attempts exhausted for key: \(key, privacy: .private)")
        #endif

        if let lastError = lastError {
            throw await NetworkError.wrapAsync(lastError, config: BlendConfig.shared)
        } else {
            throw NetworkError.customError("Unknown error in AdvancedNetworkManager", details: nil)
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
