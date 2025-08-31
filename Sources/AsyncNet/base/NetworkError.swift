import Foundation

/// Centralized error taxonomy for AsyncNet networking operations.
///
/// `NetworkError` provides comprehensive error handling for all network operations, including HTTP errors, decoding failures, connectivity issues, and transport errors.
///
/// - Important: All error cases are `Sendable` and support strict Swift 6 concurrency.
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
///
/// Enhanced error system for AsyncNet (ASYNC-302)
public enum NetworkError: Error, LocalizedError, Sendable, Equatable {
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
    case badRequest(data: Data?, statusCode: Int)
    case forbidden(data: Data?, statusCode: Int)
    case notFound(data: Data?, statusCode: Int)
    case rateLimited(data: Data?, statusCode: Int)
    case serverError(data: Data?, statusCode: Int)
    case noResponse
    case badMimeType(String)
    case uploadFailed(String)
    case imageProcessingFailed
    case cacheError(String)
    case invalidBodyForGET
    /// Represents a transport-level error (e.g., connection, timeout, DNS) not classified as HTTP status error.
    /// - Parameters:
    ///   - code: The URLError.Code associated with the transport error.
    ///   - underlying: The original URLError instance.
    case transportError(code: URLError.Code, underlying: URLError)
    /// Error case for out-of-script-bounds issues, carrying the call number.
    case outOfScriptBounds(call: Int)

    // MARK: - LocalizedError Conformance
    public var errorDescription: String? {
    switch self {
        case .httpError(let statusCode, _):
            return String(format: NSLocalizedString("HTTP error: Status code %d", comment: "Error message for HTTP errors with status code"), statusCode)
        case .decodingError(let underlyingDescription, _):
            return String(format: NSLocalizedString("Decoding error: %@", comment: "Error message for decoding failures with underlying description"), underlyingDescription)
        case .networkUnavailable:
            return NSLocalizedString("Network unavailable.", comment: "Error message when network is not available")
        case .requestTimeout(let duration):
            return String(format: NSLocalizedString("Request timed out after %.2f seconds.", comment: "Error message for request timeouts with duration"), duration)
        case .invalidEndpoint(let reason):
            return String(format: NSLocalizedString("Invalid endpoint: %@", comment: "Error message for invalid endpoints with reason"), reason)
        case .unauthorized:
            return NSLocalizedString("Not authorized.", comment: "Error message for unauthorized access")
        case .badRequest(_, let statusCode):
            return String(format: NSLocalizedString("Bad request: Status code %d", comment: "Error message for bad requests with status code"), statusCode)
        case .forbidden(_, let statusCode):
            return String(format: NSLocalizedString("Forbidden: Status code %d", comment: "Error message for forbidden access with status code"), statusCode)
        case .notFound(_, let statusCode):
            return String(format: NSLocalizedString("Not found: Status code %d", comment: "Error message for not found resources with status code"), statusCode)
        case .rateLimited(_, let statusCode):
            return String(format: NSLocalizedString("Rate limited: Status code %d", comment: "Error message for rate limiting with status code"), statusCode)
        case .serverError(_, let statusCode):
            return String(format: NSLocalizedString("Server error: Status code %d", comment: "Error message for server errors with status code"), statusCode)
        case .noResponse:
            return NSLocalizedString("No network response.", comment: "Error message when no response is received")
        case .badMimeType(let mimeType):
            return String(format: NSLocalizedString("Unsupported MIME type: %@", comment: "Error message for unsupported MIME types"), mimeType)
        case .uploadFailed(let message):
            return String(format: NSLocalizedString("Upload failed: %@", comment: "Error message for upload failures with details"), message)
        case .imageProcessingFailed:
            return NSLocalizedString("Failed to process image data.", comment: "Error message for image processing failures")
        case .cacheError(let message):
            return String(format: NSLocalizedString("Cache error: %@", comment: "Error message for cache errors with details"), message)
        case .transportError(let code, let underlying):
            return String(format: NSLocalizedString("Transport error: %d - %@", comment: "Error message for transport errors with code and description"), code.rawValue, underlying.localizedDescription)
        case .invalidBodyForGET:
            return NSLocalizedString("GET requests cannot have a body.", comment: "Error message for invalid body in GET request")
        case .custom(let message, let details):
            if let details = details {
                return String(format: NSLocalizedString("%@: %@", comment: "Custom error message with details"), message, details)
            } else {
                return NSLocalizedString(message, comment: "Custom error message")
            }
        case .outOfScriptBounds(let call):
            return String(format: NSLocalizedString("Out of script bounds: Call %d", comment: "Error message for out-of-script-bounds with call number"), call)
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .custom:
            return "Please try again or contact support."
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
        case .badRequest:
            return "Check the request parameters and format."
        case .forbidden:
            return "Check your permissions for this resource."
        case .notFound:
            return "Verify the endpoint URL and resource exists."
        case .rateLimited:
            return "Wait before making another request or reduce request frequency."
        case .serverError:
            return "Try again later. The server encountered an error."
        case .noResponse:
            return "Check network connectivity and server status."
        case .badMimeType:
            return "Ensure the server returns a supported content format."
        case .uploadFailed:
            return "Check content format and network connection."
        case .imageProcessingFailed:
            return "Ensure the content data is valid and supported."
        case .cacheError:
            return "Check cache configuration and available memory."
        case .transportError:
            return "Check network configuration and try again."
        case .invalidBodyForGET:
            return "Remove the body from GET requests or use a different HTTP method."
        case .outOfScriptBounds:
            return "Check the mock script configuration and ensure sufficient responses are provided."
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
                return .requestTimeout(duration: NetworkError.defaultTimeoutDuration)
            case .cannotFindHost:
                return .invalidEndpoint(reason: "Host not found")
            case .cannotConnectToHost:
                return .networkUnavailable
            case .networkConnectionLost:
                return .networkUnavailable
            case .dnsLookupFailed:
                return .invalidEndpoint(reason: "DNS lookup failed")
            case .secureConnectionFailed:
                return .transportError(code: urlError.code, underlying: urlError)
            case .serverCertificateUntrusted:
                return .transportError(code: urlError.code, underlying: urlError)
            default:
                return .transportError(code: urlError.code, underlying: urlError)
            }
        }
        // Fallback to custom error
    return .custom(message: "Unknown error", details: String(describing: error))
    }

    /// Default timeout duration used when wrapping URLError.timedOut
    static let defaultTimeoutDuration: TimeInterval = 60.0
}
