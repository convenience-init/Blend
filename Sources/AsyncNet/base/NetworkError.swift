

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
///
/// Enhanced error system for AsyncNet (ASYNC-302)
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
///
/// Enhanced error system for AsyncNet (ASYNC-302)
public enum NetworkError: Error, LocalizedError, Sendable {
    // MARK: - Specific Error Cases
    case httpError(statusCode: Int, data: Data?, request: URLRequest?)
    case decodingError(underlying: Error, data: Data?)
    case networkUnavailable
    case requestTimeout(duration: TimeInterval)
    case invalidEndpoint(reason: String)
    case unauthorized
    case noResponse
    case badMimeType(String)
    case uploadFailed(String)
    case imageProcessingFailed
    case cacheError(String)
    // MARK: - Legacy Cases (deprecated, for migration)
    @available(*, deprecated, message: "Use specific error cases instead.")
    case decode
    @available(*, deprecated, message: "Use networkUnavailable instead.")
    case offLine
    @available(*, deprecated, message: "Use invalidEndpoint instead.")
    case invalidURL(String)
    @available(*, deprecated, message: "Use httpError instead.")
    case badStatusCode(String)
    @available(*, deprecated, message: "Use decodingError instead.")
    case decodingErrorLegacy(Error)
    @available(*, deprecated, message: "Use customError instead.")
    case custom(msg: String?)
    @available(*, deprecated, message: "Use specific error cases instead.")
    case unknown
    @available(*, deprecated, message: "Use httpError/networkUnavailable instead.")
    case networkError(Error)

    // MARK: - LocalizedError Conformance
    public var errorDescription: String? {
        switch self {
        case .httpError(let statusCode, _, _):
            return "HTTP error: Status code \(statusCode)"
        case .decodingError(let underlying, _):
            return "Decoding error: \(underlying.localizedDescription)"
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
        // Legacy cases
        case .decode:
            return "Decoding error (legacy)."
        case .offLine:
            return "Network unavailable (legacy)."
        case .invalidURL(let message):
            return "Invalid URL: \(message)"
        case .badStatusCode(let message):
            return "Bad status code: \(message)"
        case .decodingErrorLegacy(let error):
            return "Decoding error (legacy): \(error.localizedDescription)"
        case .custom(let msg):
            return msg ?? "Custom error."
        case .unknown:
            return "Unknown error."
        case .networkError(let error):
            return error.localizedDescription
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .httpError(let statusCode, _, _):
            if statusCode == 401 { return "Check your credentials and try again." }
            if statusCode == 404 { return "Verify the endpoint URL." }
            if statusCode >= 500 { return "Try again later. Server may be down." }
            return "Check the request and try again."
        case .decodingError:
            return "Ensure the response format matches the expected model."
        case .networkUnavailable, .offLine:
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
    /// Creates a custom error with a formatted message
    static func customError(_ message: String, details: String? = nil) -> NetworkError {
        let fullMessage = details != nil ? "\(message): \(details!)" : message
        // Use invalidEndpoint for endpoint errors, otherwise fallback to httpError 400
        if message.lowercased().contains("endpoint") {
            return .invalidEndpoint(reason: fullMessage)
        }
        return .httpError(statusCode: 400, data: nil, request: nil)
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
                return .httpError(statusCode: urlError.errorCode, data: nil, request: nil)
            }
        }
        // Fallback to decodingError
        return .decodingError(underlying: error, data: nil)
    }
}
