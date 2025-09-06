import Foundation

/// Centralized error taxonomy for AsyncNet networking operations.
///
/// `NetworkError` provides comprehensive error handling for all network operations,
/// including HTTP errors, decoding failures, connectivity issues, and transport errors.
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
/// - Use `wrapAsync(_:config:)` to convert generic errors to `NetworkError`
/// (config parameter uses default AsyncNetConfig.shared if not specified).
///
/// Enhanced error system for AsyncNet (ASYNC-302)
public enum NetworkError: Error, Sendable {
    case customError(message: String, details: String?)
    // MARK: - Specific Error Cases
    /// HTTP error with status code and optional response data (Sendable)
    case httpError(statusCode: Int, data: Data?)
    /// Bad request error (400) with optional response data and status code
    case badRequest(data: Data?, statusCode: Int)
    /// Forbidden error (403) with optional response data and status code
    case forbidden(data: Data?, statusCode: Int)
    /// Not found error (404) with optional response data and status code
    case notFound(data: Data?, statusCode: Int)
    /// Rate limited error (429) with optional response data and status code
    case rateLimited(data: Data?, statusCode: Int)
    /// Server error (5xx) with status code and optional response data
    case serverError(statusCode: Int, data: Data?)
    /// Decoding error with underlying error and optional data (Sendable)
    case decodingError(underlying: any Error & Sendable, data: Data?)
    /// Dedicated decoding failure with detailed context and underlying DecodingError
    case decodingFailed(reason: String, underlying: any Error & Sendable, data: Data?)
    case networkUnavailable
    case requestTimeout(duration: TimeInterval)
    case invalidEndpoint(reason: String)
    case unauthorized(data: Data?, statusCode: Int)
    case noResponse
    case badMimeType(String)
    case uploadFailed(String)
    case imageProcessingFailed
    case cacheError(String)
    case invalidBodyForGET
    case requestCancelled
    case authenticationFailed
    /// Payload too large error with actual size and configured limit
    case payloadTooLarge(size: Int, limit: Int)
    /// Error case for invalid mock configuration with call index and missing components
    case invalidMockConfiguration(callIndex: Int, missingData: Bool, missingResponse: Bool)
    /// Represents a transport-level error (e.g., connection, timeout, DNS) not classified as HTTP status error.
    /// - Parameters:
    ///   - code: The URLError.Code associated with the transport error.
    ///   - underlying: The original URLError instance.
    case transportError(code: URLError.Code, underlying: URLError)
    /// Error case for out-of-script-bounds issues, carrying the call number.
    case outOfScriptBounds(call: Int)
}
