// Equatable conformance for NetworkError for testing and production
extension NetworkError: Equatable {
    public static func == (lhs: NetworkError, rhs: NetworkError) -> Bool {
        switch (lhs, rhs) {
        case (.httpError(let lCode, _), .httpError(let rCode, _)): return lCode == rCode
        case (.decodingError, .decodingError): return true
        case (.networkUnavailable, .networkUnavailable): return true
        case (.requestTimeout, .requestTimeout): return true
        case (.invalidEndpoint(let l), .invalidEndpoint(let r)): return l == r
        case (.unauthorized, .unauthorized): return true
        case (.noResponse, .noResponse): return true
        case (.badMimeType(let l), .badMimeType(let r)): return l == r
        case (.uploadFailed(let l), .uploadFailed(let r)): return l == r
        case (.imageProcessingFailed, .imageProcessingFailed): return true
        case (.cacheError(let l), .cacheError(let r)): return l == r
        case (.transportError(let lCode, _), .transportError(let rCode, _)): return lCode == rCode
        case (.custom(let lMsg, let lDetails), .custom(let rMsg, let rDetails)):
            return lMsg == rMsg && lDetails == rDetails
        default: return false
        }
    }
}


import Foundation

/// Centralized error taxonomy for AsyncNet networking operations.
///
/// `NetworkError` provides comprehensive error handling for all network operations, including HTTP errors, decoding failures, connectivity issues, and migration helpers.
///
/// - Important: All error cases are `Sendable` and support strict Swift 6 concurrency.
/// - Note: Legacy cases are deprecated and provided only for migration purposes. Migrate to specific error cases for strict compliance.
///
/// ### Usage Example
/// ```swift
/// do {
///     let users: [User] = try await userService.getUsers()
/// } catch let error as NetworkError {
///     print("Network error: \(error.message())")
/// }
/// ```
///
/// ### Migration Notes
/// - Migrate all legacy error cases to specific cases for strict concurrency and clarity.
/// - Use `wrap(_:)` to convert generic errors to `NetworkError`.
/// - Transport errors (connection, DNS, etc) are mapped to `.transportError` for strict separation from HTTP status errors.
///
/// Enhanced error system for AsyncNet (ASYNC-302)
public enum NetworkError: Error, LocalizedError, Sendable {
    case custom(message: String, details: String?)
    // MARK: - Specific Error Cases
    /// HTTP error with status code and optional response data (Sendable)
    case httpError(statusCode: Int, data: Data?)
    /// Decoding error with underlying error description and optional data (Sendable)
    case decodingError(underlyingDescription: String, data: Data?)
    case networkUnavailable
    case requestTimeout(duration: TimeInterval)
    case invalidEndpoint(reason: String)
    case unauthorized
    case noResponse
    case badMimeType(String)
    case uploadFailed(String)
    case imageProcessingFailed
    case cacheError(String)
        /// Represents a transport-level error (e.g., connection, timeout, DNS) not classified as HTTP status error.
        /// - Parameters:
        ///   - code: The URLError.Code associated with the transport error.
        ///   - underlying: The original URLError instance.
        case transportError(code: URLError.Code, underlying: URLError)
    // Legacy/deprecated cases removed for strict compliance

    // MARK: - LocalizedError Conformance
    public var errorDescription: String? {
    switch self {
        case .httpError(let statusCode, _):
            return "HTTP error: Status code \(statusCode)"
        case .decodingError(let underlyingDescription, _):
            return "Decoding error: \(underlyingDescription)"
        case .networkUnavailable:
            return "Network unavailable."
        case .requestTimeout(let duration):
            return "Request timed out after \(String(format: "%.2f", duration)) seconds."
        case .invalidEndpoint(let reason):
            return "Invalid endpoint: \(reason)"
        case .unauthorized:
            return "Not authorized."
        case .noResponse:
            return "No network response."
        case .badMimeType(let mimeType):
            return "Unsupported mime type: \(mimeType)"
        case .uploadFailed(let message):
            return "Upload failed: \(message)"
        case .imageProcessingFailed:
            return "Failed to process image data."
        case .cacheError(let message):
            return "Cache error: \(message)"
        case .transportError(let code, let underlying):
            return "Transport error: \(code) - \(underlying.localizedDescription)"
        case .custom(let message, let details):
            if let details = details {
                return "\(message): \(details)"
            } else {
                return message
            }
        }
    }

    public var recoverySuggestion: String? {
        switch self {
    case .httpError(let statusCode, _):
            if statusCode == 401 { return "Check your credentials and try again." }
            if statusCode == 404 { return "Verify the endpoint URL." }
            if statusCode >= 500 { return "Try again later. Server may be down." }
            return "Check the request and try again."
        case .decodingError:
            return "Ensure the response format matches the expected model."
        case .networkUnavailable:
            return "Check your internet connection."
        case .requestTimeout:
            return "Try again with a better connection or increase timeout duration."
        case .invalidEndpoint:
            return "Verify the endpoint configuration."
        case .unauthorized:
            return "Check your authentication and permissions."
        case .noResponse:
            return "Check network connectivity and server status."
        case .badMimeType:
            return "Ensure the server returns a supported image format."
        case .uploadFailed:
            return "Check image format and network connection."
        case .imageProcessingFailed:
            return "Ensure the image data is valid and supported."
        case .cacheError:
            return "Check cache configuration and available memory."
        default:
            return "Please try again or contact support."
        }
    }

    // MARK: - Error Message Helper
    public func message() -> String {
        return errorDescription ?? "An unknown error occurred."
    }
}

// MARK: - Error Convenience Extensions
public extension NetworkError {
    /// Creates a custom error with a formatted message and optional details
    static func customError(_ message: String, details: String? = nil) -> NetworkError {
    // Use a dedicated custom error case for non-arbitrary error information
    return .custom(message: message, details: details)
    }

    /// Wraps a generic error as a network error
    static func wrap(_ error: Error) -> NetworkError {
        if let networkError = error as? NetworkError {
            return networkError
        }
        // If error is URLError, map to networkUnavailable or requestTimeout
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet:
                return .networkUnavailable
            case .timedOut:
                return .requestTimeout(duration: 60.0) // Default timeout duration
            default:
                return .transportError(code: urlError.code, underlying: urlError)
            }
        }
        // Fallback to custom error
    return .custom(message: "Unknown error", details: String(describing: error))
    }
}
