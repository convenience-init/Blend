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

/// RequestUtilities provides utility functions for request processing, caching decisions,
/// and HTTP response validation used by AdvancedNetworkManager.
public enum RequestUtilities {
    /// Generates a deterministic cache key from request components
    public static func generateRequestKey(from request: URLRequest) -> String {
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
    public static func generateBodyHash(from body: Data?) -> String {
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
                guard CC_SHA256_Init(&context) == 1 else {
                    // Fallback to simple hash on init failure
                    return "error:sha256-init-failed:\(body.count)"
                }

                // Process body in chunks to avoid CC_LONG overflow
                let chunkSize = Int(CC_LONG.max)
                var remainingData = body

                while !remainingData.isEmpty {
                    let chunk = remainingData.prefix(chunkSize)
                    remainingData = remainingData.dropFirst(chunkSize)

                    let updateResult = chunk.withUnsafeBytes { buffer in
                        CC_SHA256_Update(&context, buffer.baseAddress, CC_LONG(chunk.count))
                    }
                    guard updateResult == 1 else {
                        // Return error indicator immediately - don't continue with bad state
                        return "error:sha256-update-failed:\(body.count)"
                    }
                }

                var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
                guard CC_SHA256_Final(&hash, &context) == 1 else {
                    // Fallback on final failure
                    return "error:sha256-final-failed:\(body.count)"
                }

                return "sha256:\(hash.map { String(format: "%02x", $0) }.joined())"
            }

            var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
            let result = body.withUnsafeBytes { buffer in
                CC_SHA256(buffer.baseAddress, CC_LONG(buffer.count), &hash)
            }
            guard result != nil else {
                // Fallback on direct hash failure
                return "error:sha256-direct-failed:\(body.count)"
            }
            return "sha256:\(hash.map { String(format: "%02x", $0) }.joined())"
        #else
            // Fallback to FNV-1a 64-bit hash over the entire body for better collision resistance
            let fnv1aHash = body.reduce(14_695_981_039_346_656_037) { hash, _ in
                let hash = hash &* 1_099_511_628_211
            }
            return "fallback:\(String(format: "%016llx", fnv1aHash)):\(body.count)"
        #endif
    }

    /// Determines if a response should be cached based on HTTP method and Cache-Control headers
    public static func shouldCacheResponse(for request: URLRequest, response: HTTPURLResponse)
        -> Bool {
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
        let normalizedResponseHeaders = response.allHeaderFields.reduce(into: [String: Any]()) { result, pair in
            if let keyString = pair.key as? String {
                result[keyString.lowercased()] = pair.value
            }
        }

        if let cacheControl = normalizedResponseHeaders["cache-control"] as? String {
            let directives = cacheControl.lowercased()
            let directiveList = directives.split(separator: ",").map {
                $0.trimmingCharacters(in: .whitespaces)
            }
            let hasNoStore = directiveList.contains { $0.hasPrefix("no-store") }
            let hasNoCache = directiveList.contains { $0.hasPrefix("no-cache") }
            let hasPrivate = directiveList.contains { $0.hasPrefix("private") }
            let hasMaxAgeZero = directiveList.contains { directive in
                let components = directive.split(separator: "=", maxSplits: 1)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                return components.count == 2 && components[0] == "max-age" && components[1] == "0"
            }
            if hasNoStore || hasNoCache || hasPrivate || hasMaxAgeZero {
                return false
            }
        }

        return true
    }

    /// Validates HTTP response and throws appropriate NetworkError for non-2xx status codes
    public static func validateHTTPResponse(_ response: HTTPURLResponse, data: Data) throws {
        switch response.statusCode {
        case 200...299:
            return  // Success, no error to throw
        case 400:
            throw NetworkError.badRequest(data: data, statusCode: response.statusCode)
        case 401:
            throw NetworkError.unauthorized(data: data, statusCode: response.statusCode)
        case 403:
            throw NetworkError.forbidden(data: data, statusCode: response.statusCode)
        case 404:
            throw NetworkError.notFound(data: data, statusCode: response.statusCode)
        case 429:
            throw NetworkError.rateLimited(data: data, statusCode: response.statusCode)
        case 500...599:
            throw NetworkError.serverError(statusCode: response.statusCode, data: data)
        default:
            throw NetworkError.httpError(statusCode: response.statusCode, data: data)
        }
    }

    /// Handles retry logic for a failed request attempt
    public static func handleRetryAttempt(
        error: Error, attempt: Int, retryPolicy: RetryPolicy, key: String
    ) async throws -> Bool {
        // Determine if we should retry based on custom logic or default behavior
        let shouldRetryAttempt: Bool
        if let customShouldRetry = retryPolicy.shouldRetry {
            shouldRetryAttempt = customShouldRetry(error, attempt)
        } else {
            // Default behavior: always retry (maxAttempts controls total attempts)
            let wrappedError = await NetworkError.wrapAsync(error, config: AsyncNetConfig.shared)
            #if canImport(OSLog)
                asyncNetLogger.debug(
                    "Default retry behavior triggered for wrapped error: \(wrappedError.localizedDescription, privacy: .public)"
                )
            #endif
            shouldRetryAttempt = true
        }

        // If custom logic says don't retry, break immediately
        if !shouldRetryAttempt {
            return false
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
                    """
                    Retrying request for key: \(key, privacy: .private) after \
                    \(cappedDelay, privacy: .public) seconds
                    """
                )
            #endif
            try await Task.sleep(nanoseconds: UInt64(cappedDelay * 1_000_000_000))
        }

        return true
    }
}
