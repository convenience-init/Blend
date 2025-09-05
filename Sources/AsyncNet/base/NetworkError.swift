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
/// - Use `wrapAsync(_:config:)` to convert generic errors to `NetworkError` (config parameter uses default AsyncNetConfig.shared if not specified).
///
/// Enhanced error system for AsyncNet (ASYNC-302)
public enum NetworkError: Error, LocalizedError, Sendable, Equatable {
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

    // MARK: - Private Helper Methods
    private final class BundleHelper {}

    internal static let l10nBundle: Bundle = {
        #if SWIFT_PACKAGE
            return Bundle.module
        #else
            return Bundle(for: BundleHelper.self)
        #endif
    }()

    private static func statusMessage(_ format: String, _ statusCode: Int) -> String {
        return String(
            format: NSLocalizedString(
                format, tableName: nil, bundle: NetworkError.l10nBundle, value: format,
                comment: "Error message for HTTP errors with status code"), statusCode)
    }

    private static func transportErrorDescription(_ code: URLError.Code) -> String {
        // Group related error codes for better organization and reduced complexity
        let connectionErrors: [URLError.Code: String] = [
            .notConnectedToInternet: "Not connected to internet",
            .cannotFindHost: "Cannot find host",
            .cannotConnectToHost: "Cannot connect to host",
            .networkConnectionLost: "Network connection lost",
            .dnsLookupFailed: "DNS lookup failed",
            .internationalRoamingOff: "International roaming off",
            .dataNotAllowed: "Data not allowed",
        ]

        let fileErrors: [URLError.Code: String] = [
            .cannotCreateFile: "Cannot create file",
            .cannotOpenFile: "Cannot open file",
            .cannotCloseFile: "Cannot close file",
            .cannotWriteToFile: "Cannot write to file",
            .cannotRemoveFile: "Cannot remove file",
            .cannotMoveFile: "Cannot move file",
            .fileDoesNotExist: "File does not exist",
            .fileIsDirectory: "File is directory",
            .noPermissionsToReadFile: "No permissions to read file",
        ]

        let securityErrors: [URLError.Code: String] = [
            .secureConnectionFailed: "Secure connection failed",
            .serverCertificateUntrusted: "Server certificate untrusted",
            .serverCertificateHasBadDate: "Server certificate has bad date",
            .serverCertificateHasUnknownRoot: "Server certificate has unknown root",
            .serverCertificateNotYetValid: "Server certificate not yet valid",
            .clientCertificateRejected: "Client certificate rejected",
            .clientCertificateRequired: "Client certificate required",
            .appTransportSecurityRequiresSecureConnection:
                "App Transport Security requires secure connection",
        ]

        let requestErrors: [URLError.Code: String] = [
            .timedOut: "Request timed out",
            .cancelled: "Request cancelled",
            .badURL: "Bad URL",
            .unsupportedURL: "Unsupported URL",
            .requestBodyStreamExhausted: "Request body stream exhausted",
        ]

        let backgroundErrors: [URLError.Code: String] = [
            .backgroundSessionRequiresSharedContainer:
                "Background session requires shared container",
            .backgroundSessionInUseByAnotherProcess: "Background session in use by another process",
            .backgroundSessionWasDisconnected: "Background session was disconnected",
        ]

        let otherErrors: [URLError.Code: String] = [
            .cannotLoadFromNetwork: "Cannot load from network",
            .downloadDecodingFailedMidStream: "Download decoding failed",
            .downloadDecodingFailedToComplete: "Download decoding failed to complete",
            .callIsActive: "Call is active",
            .dataLengthExceedsMaximum: "Data length exceeds maximum",
            .userAuthenticationRequired: "User authentication required",
        ]

        // Check each error group
        if let description = connectionErrors[code] {
            return NSLocalizedString(
                description, tableName: nil, bundle: NetworkError.l10nBundle,
                value: description,
                comment: "User-friendly description for \(code)")
        }

        if let description = fileErrors[code] {
            return NSLocalizedString(
                description, tableName: nil, bundle: NetworkError.l10nBundle,
                value: description,
                comment: "User-friendly description for \(code)")
        }

        if let description = securityErrors[code] {
            return NSLocalizedString(
                description, tableName: nil, bundle: NetworkError.l10nBundle,
                value: description,
                comment: "User-friendly description for \(code)")
        }

        if let description = requestErrors[code] {
            return NSLocalizedString(
                description, tableName: nil, bundle: NetworkError.l10nBundle,
                value: description,
                comment: "User-friendly description for \(code)")
        }

        if let description = backgroundErrors[code] {
            return NSLocalizedString(
                description, tableName: nil, bundle: NetworkError.l10nBundle,
                value: description,
                comment: "User-friendly description for \(code)")
        }

        if let description = otherErrors[code] {
            return NSLocalizedString(
                description, tableName: nil, bundle: NetworkError.l10nBundle,
                value: description,
                comment: "User-friendly description for \(code)")
        }

        // Fallback to a generic description with the raw value for unknown codes
        return String(
            format: NSLocalizedString(
                "Transport error %d", tableName: nil, bundle: NetworkError.l10nBundle,
                value: "Transport error %d",
                comment: "Fallback description for unknown URLError codes"
            ), code.rawValue)
    }

    private static func decodingErrorReason(_ error: DecodingError) -> String {
        func pathDescription(from codingPath: [CodingKey]) -> String {
            if codingPath.isEmpty {
                return "root"
            }

            // Build path components, handling both string keys and array indices
            var pathComponents: [String] = []

            for key in codingPath {
                if let intValue = key.intValue {
                    // Array index - format as "[index]" and attach to previous component if present
                    let indexComponent = "[\(intValue)]"
                    if let lastIndex = pathComponents.indices.last {
                        // Attach to the previous component (e.g., "items[0]")
                        pathComponents[lastIndex] += indexComponent
                    } else {
                        // If this is the first component, just use the index
                        pathComponents.append(indexComponent)
                    }
                } else if !key.stringValue.isEmpty {
                    // Regular string key (e.g., "items", "name")
                    pathComponents.append(key.stringValue)
                }
                // Skip keys that have neither stringValue nor intValue
            }

            // Join components with "." and handle empty result
            let joinedPath = pathComponents.joined(separator: ".")
            return joinedPath.isEmpty ? "root" : joinedPath
        }

        switch error {
        case .dataCorrupted(let context):
            let pathDescription = pathDescription(from: context.codingPath)
            return "Data corrupted at '\(pathDescription)': \(context.debugDescription)"
        case .keyNotFound(let key, let context):
            let pathDescription = pathDescription(from: context.codingPath)
            return
                "Required key '\(key.stringValue)' not found at '\(pathDescription)': \(context.debugDescription)"
        case .typeMismatch(let type, let context):
            let pathDescription = pathDescription(from: context.codingPath)
            return
                "Type mismatch at '\(pathDescription)', expected \(type): \(context.debugDescription)"
        case .valueNotFound(let type, let context):
            let pathDescription = pathDescription(from: context.codingPath)
            return
                "Value not found at '\(pathDescription)', expected \(type): \(context.debugDescription)"
        @unknown default:
            return "Unknown decoding error: \(error.localizedDescription)"
        }
    }

    // MARK: - LocalizedError Conformance
    public var errorDescription: String? {
        switch self {
        case .httpError(let statusCode, _):
            return NetworkError.statusMessage("HTTP error: Status code %d", statusCode)
        case .badRequest(_, let statusCode):
            return String(
                format: NSLocalizedString(
                    "Bad request (status %d).", tableName: nil, bundle: NetworkError.l10nBundle,
                    value: "Bad request (status %d).",
                    comment: "Error message for HTTP 400 Bad Request errors"), statusCode)
        case .forbidden(_, let statusCode):
            return String(
                format: NSLocalizedString(
                    "Forbidden (status %d).", tableName: nil, bundle: NetworkError.l10nBundle,
                    value: "Forbidden (status %d).",
                    comment: "Error message for HTTP 403 Forbidden errors"), statusCode)
        case .notFound(_, let statusCode):
            return String(
                format: NSLocalizedString(
                    "Not found (status %d).", tableName: nil, bundle: NetworkError.l10nBundle,
                    value: "Not found (status %d).",
                    comment: "Error message for HTTP 404 Not Found errors"), statusCode)
        case .rateLimited(_, let statusCode):
            return String(
                format: NSLocalizedString(
                    "Rate limited (status %d).", tableName: nil, bundle: NetworkError.l10nBundle,
                    value: "Rate limited (status %d).",
                    comment: "Error message for HTTP 429 Rate Limited errors"), statusCode)
        case .serverError(let statusCode, _):
            return NetworkError.statusMessage("Server error: Status code %d", statusCode)
        case .decodingError(let underlying, _):
            return String(
                format: NSLocalizedString(
                    "Decoding error: %@", tableName: nil, bundle: NetworkError.l10nBundle,
                    value: "Decoding error: %@",
                    comment: "Error message for decoding failures with underlying description"),
                underlying.localizedDescription)
        case .decodingFailed(let reason, _, _):
            return String(
                format: NSLocalizedString(
                    "Decoding failed: %@", tableName: nil, bundle: NetworkError.l10nBundle,
                    value: "Decoding failed: %@",
                    comment: "Error message for detailed decoding failures"),
                reason)
        case .networkUnavailable:
            return NSLocalizedString(
                "Network unavailable.", tableName: nil, bundle: NetworkError.l10nBundle,
                value: "Network unavailable.",
                comment: "Error message when network is not available")
        case .requestTimeout(let duration):
            return String(
                format: NSLocalizedString(
                    "Request timed out after %.2f seconds.", tableName: nil,
                    bundle: NetworkError.l10nBundle,
                    value: "Request timed out after %.2f seconds.",
                    comment: "Error message for request timeouts with duration"), duration)
        case .invalidEndpoint(let reason):
            return String(
                format: NSLocalizedString(
                    "Invalid endpoint: %@", tableName: nil, bundle: NetworkError.l10nBundle,
                    value: "Invalid endpoint: %@",
                    comment: "Error message for invalid endpoints with reason"), reason)
        case .unauthorized(_, let statusCode):
            return String(
                format: NSLocalizedString(
                    "Not authorized (status %d).", tableName: nil, bundle: NetworkError.l10nBundle,
                    value: "Not authorized (status %d).",
                    comment: "Error message for unauthorized access with HTTP status code"),
                statusCode)
        case .noResponse:
            return NSLocalizedString(
                "No network response.", tableName: nil, bundle: NetworkError.l10nBundle,
                value: "No network response.",
                comment: "Error message when no response is received")
        case .badMimeType(let mimeType):
            return String(
                format: NSLocalizedString(
                    "Unsupported MIME type: %@", tableName: nil, bundle: NetworkError.l10nBundle,
                    value: "Unsupported MIME type: %@",
                    comment: "Error message for unsupported MIME types"
                ), mimeType)
        case .uploadFailed(let message):
            return String(
                format: NSLocalizedString(
                    "Upload failed: %@", tableName: nil, bundle: NetworkError.l10nBundle,
                    value: "Upload failed: %@",
                    comment: "Error message for upload failures with details"),
                message)
        case .imageProcessingFailed:
            return NSLocalizedString(
                "Failed to process image data.", tableName: nil, bundle: NetworkError.l10nBundle,
                value: "Failed to process image data.",
                comment: "Error message for image processing failures")
        case .cacheError(let message):
            return String(
                format: NSLocalizedString(
                    "Cache operation failed: %@", tableName: nil, bundle: NetworkError.l10nBundle,
                    value: "Cache operation failed: %@",
                    comment: "Error message for cache operation failures with details"),
                message)
        case .invalidBodyForGET:
            return NSLocalizedString(
                "GET requests cannot have a body.", tableName: nil, bundle: NetworkError.l10nBundle,
                value: "GET requests cannot have a body.",
                comment: "Error message for invalid body in GET request")
        case .requestCancelled:
            return NSLocalizedString(
                "Request was cancelled.", tableName: nil, bundle: NetworkError.l10nBundle,
                value: "Request was cancelled.",
                comment: "Error message for cancelled requests")
        case .authenticationFailed:
            return NSLocalizedString(
                "Authentication failed.", tableName: nil, bundle: NetworkError.l10nBundle,
                value: "Authentication failed.",
                comment: "Error message for authentication failures")
        case .transportError(let code, let underlying):
            return String(
                format: NSLocalizedString(
                    "Network connection error: %@ (%@)", tableName: nil,
                    bundle: NetworkError.l10nBundle,
                    value: "Network connection error: %@ (%@)",
                    comment: "Error message for network connection errors with details"),
                NetworkError.transportErrorDescription(code), underlying.localizedDescription)
        case .customError(let message, let details):
            if let details = details {
                return String(
                    format: NSLocalizedString(
                        "%@: %@", tableName: nil, bundle: NetworkError.l10nBundle, value: "%@: %@",
                        comment: "Custom error message with details"), message, details)
            } else {
                return message
            }
        case .outOfScriptBounds(let call):
            return String(
                format: NSLocalizedString(
                    "Out of script bounds: Call %d", tableName: nil,
                    bundle: NetworkError.l10nBundle,
                    value: "Out of script bounds: Call %d",
                    comment: "Error message for out-of-script-bounds with call number"), call)
        case .payloadTooLarge(let size, let limit):
            return String(
                format: NSLocalizedString(
                    "Payload too large: %d B exceeds %d B limit.", tableName: nil,
                    bundle: NetworkError.l10nBundle,
                    value: "Payload too large: %d B exceeds %d B limit.",
                    comment: "Error message for payload too large"),
                size, limit)
        case .invalidMockConfiguration(let callIndex, let missingData, let missingResponse):
            var missingComponents: [String] = []
            if missingData { missingComponents.append("data") }
            if missingResponse { missingComponents.append("response") }
            let componentsString = missingComponents.joined(separator: " and ")
            return String(
                format: NSLocalizedString(
                    "Test configuration error at call %d: missing %@.", tableName: nil,
                    bundle: NetworkError.l10nBundle,
                    value: "Test configuration error at call %d: missing %@.",
                    comment: "Error message for test configuration errors with details"
                ),
                callIndex, componentsString
            )
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .customError:
            return NSLocalizedString(
                "Please try again or contact support.", tableName: nil,
                bundle: NetworkError.l10nBundle,
                value: "Please try again or contact support.",
                comment: "Recovery suggestion for custom errors")
        case .httpError(let statusCode, _):
            return recoverySuggestionForHTTPStatus(statusCode)
        case .badRequest, .decodingError, .decodingFailed:
            return NSLocalizedString(
                "Check the request parameters and format.", tableName: nil,
                bundle: NetworkError.l10nBundle,
                value: "Check the request parameters and format.",
                comment: "Recovery suggestion for request/format errors")
        case .forbidden, .unauthorized:
            return NSLocalizedString(
                "Check your permissions for this resource.", tableName: nil,
                bundle: NetworkError.l10nBundle,
                value: "Check your permissions for this resource.",
                comment: "Recovery suggestion for authorization errors")
        case .notFound:
            return NSLocalizedString(
                "Verify the endpoint URL and resource exists.", tableName: nil,
                bundle: NetworkError.l10nBundle,
                value: "Verify the endpoint URL and resource exists.",
                comment: "Recovery suggestion for not found errors")
        case .rateLimited:
            return NSLocalizedString(
                "Wait before making another request or reduce request frequency.", tableName: nil,
                bundle: NetworkError.l10nBundle,
                value: "Wait before making another request or reduce request frequency.",
                comment: "Recovery suggestion for rate limited errors")
        case .serverError:
            return NSLocalizedString(
                "Try again later. The server encountered an error.", tableName: nil,
                bundle: NetworkError.l10nBundle,
                value: "Try again later. The server encountered an error.",
                comment: "Recovery suggestion for server errors")
        case .networkUnavailable:
            return NSLocalizedString(
                "Check your internet connection.", tableName: nil, bundle: NetworkError.l10nBundle,
                value: "Check your internet connection.",
                comment: "Recovery suggestion for network unavailable errors")
        case .requestTimeout:
            return NSLocalizedString(
                "Try again with a better connection or increase timeout duration.", tableName: nil,
                bundle: NetworkError.l10nBundle,
                value: "Try again with a better connection or increase timeout duration.",
                comment: "Recovery suggestion for request timeout errors")
        case .invalidEndpoint:
            return NSLocalizedString(
                "Verify the endpoint configuration.", tableName: nil,
                bundle: NetworkError.l10nBundle,
                value: "Verify the endpoint configuration.",
                comment: "Recovery suggestion for invalid endpoint errors")
        case .noResponse:
            return NSLocalizedString(
                "Check network connectivity and server status.", tableName: nil,
                bundle: NetworkError.l10nBundle,
                value: "Check network connectivity and server status.",
                comment: "Recovery suggestion for no response errors")
        case .badMimeType:
            return NSLocalizedString(
                "Ensure the server returns a supported content format.", tableName: nil,
                bundle: NetworkError.l10nBundle,
                value: "Ensure the server returns a supported content format.",
                comment: "Recovery suggestion for unsupported MIME type errors")
        case .uploadFailed:
            return NSLocalizedString(
                "Check content format and network connection.", tableName: nil,
                bundle: NetworkError.l10nBundle,
                value: "Check content format and network connection.",
                comment: "Recovery suggestion for upload failure errors")
        case .imageProcessingFailed:
            return NSLocalizedString(
                "Ensure the content data is valid and supported.", tableName: nil,
                bundle: NetworkError.l10nBundle,
                value: "Ensure the content data is valid and supported.",
                comment: "Recovery suggestion for image processing failure errors")
        case .cacheError:
            return NSLocalizedString(
                "Check cache configuration and available memory.", tableName: nil,
                bundle: NetworkError.l10nBundle,
                value: "Check cache configuration and available memory.",
                comment: "Recovery suggestion for cache error issues")
        case .invalidBodyForGET:
            return NSLocalizedString(
                "Remove the body from GET requests or use a different HTTP method.", tableName: nil,
                bundle: NetworkError.l10nBundle,
                value: "Remove the body from GET requests or use a different HTTP method.",
                comment: "Recovery suggestion for invalid body in GET request errors")
        case .requestCancelled:
            return NSLocalizedString(
                "Check cancellation logic and consider retrying if appropriate.", tableName: nil,
                bundle: NetworkError.l10nBundle,
                value: "Check cancellation logic and consider retrying if appropriate.",
                comment:
                    "Recovery suggestion for cancelled requests - verify logic and retry if needed")
        case .authenticationFailed:
            return NSLocalizedString(
                "Verify your credentials and try again.", tableName: nil,
                bundle: NetworkError.l10nBundle,
                value: "Verify your credentials and try again.",
                comment: "Recovery suggestion for authentication failures")
        case .transportError:
            return NSLocalizedString(
                "Check network configuration and try again.", tableName: nil,
                bundle: NetworkError.l10nBundle,
                value: "Check network configuration and try again.",
                comment: "Recovery suggestion for transport layer errors")
        case .outOfScriptBounds:
            return NSLocalizedString(
                "Check the mock script configuration and ensure sufficient responses are provided.",
                tableName: nil, bundle: NetworkError.l10nBundle,
                value:
                    "Check the mock script configuration and ensure sufficient responses are provided.",
                comment: "Recovery suggestion for out-of-script-bounds mock errors")
        case .payloadTooLarge:
            return NSLocalizedString(
                "Reduce the payload size or use multipart upload for large files.", tableName: nil,
                bundle: NetworkError.l10nBundle,
                value: "Reduce the payload size or use multipart upload for large files.",
                comment: "Recovery suggestion for payload too large errors")
        case .invalidMockConfiguration:
            return NSLocalizedString(
                "Check the mock script configuration and ensure all calls have both data and response configured.",
                tableName: nil, bundle: NetworkError.l10nBundle,
                value:
                    "Check the mock script configuration and ensure all calls have both data and response configured.",
                comment: "Recovery suggestion for invalid mock configuration errors")
        }
    }

    private func recoverySuggestionForHTTPStatus(_ statusCode: Int) -> String {
        switch statusCode {
        case 400:
            return NSLocalizedString(
                "Check the request parameters and format.", tableName: nil,
                bundle: NetworkError.l10nBundle,
                value: "Check the request parameters and format.",
                comment: "Recovery suggestion for HTTP 400 Bad Request errors")
        case 401:
            return NSLocalizedString(
                "Check your credentials and try again.", tableName: nil,
                bundle: NetworkError.l10nBundle,
                value: "Check your credentials and try again.",
                comment: "Recovery suggestion for HTTP 401 Unauthorized errors")
        case 403:
            return NSLocalizedString(
                "Check your permissions for this resource.", tableName: nil,
                bundle: NetworkError.l10nBundle,
                value: "Check your permissions for this resource.",
                comment: "Recovery suggestion for HTTP 403 Forbidden errors")
        case 404:
            return NSLocalizedString(
                "Verify the endpoint URL and resource exists.", tableName: nil,
                bundle: NetworkError.l10nBundle,
                value: "Verify the endpoint URL and resource exists.",
                comment: "Recovery suggestion for HTTP 404 Not Found errors")
        case 429:
            return NSLocalizedString(
                "Wait before making another request or reduce request frequency.",
                tableName: nil, bundle: NetworkError.l10nBundle,
                value: "Wait before making another request or reduce request frequency.",
                comment: "Recovery suggestion for HTTP 429 Too Many Requests errors")
        case 500..<600:
            return NSLocalizedString(
                "Try again later. The server encountered an error.", tableName: nil,
                bundle: NetworkError.l10nBundle,
                value: "Try again later. The server encountered an error.",
                comment: "Recovery suggestion for HTTP 5xx Server errors")
        default:
            return NSLocalizedString(
                "Check the request and try again.", tableName: nil,
                bundle: NetworkError.l10nBundle,
                value: "Check the request and try again.",
                comment: "Recovery suggestion for general HTTP errors")
        }
    }
}

/// MARK: - Error Convenience Extensions
extension NetworkError {
    /// Creates a custom error with a formatted message and optional details
    public static func customError(_ message: String, details: String? = nil) -> NetworkError {
        // Use a dedicated custom error case for non-arbitrary error information
        return .customError(message: message, details: details)
    }

    /// Wraps an Error into a NetworkError with configurable timeout duration.
    /// This async version allows for thread-safe configuration of timeout behavior.
    /// - Parameters:
    ///   - error: The error to wrap
    ///   - config: The configuration to use for timeout duration
    /// - Returns: A NetworkError representation of the input error
    @available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
    public static func wrapAsync(_ error: Error, config: AsyncNetConfig) async -> NetworkError {
        // If error is already a NetworkError, return it as-is
        if let networkError = error as? NetworkError {
            return networkError
        }

        switch error {
        case let urlError as URLError:
            return NetworkError.map(urlError: urlError, timeout: await config.timeoutDuration)
        case let decodingError as DecodingError:
            let reason = NetworkError.decodingErrorReason(decodingError)
            return .decodingFailed(reason: reason, underlying: decodingError, data: nil)
        default:
            return .customError(message: "Unknown error", details: String(describing: error))
        }
    }

    /// Maps a URLError to the appropriate NetworkError with the specified timeout duration.
    ///
    /// This helper function centralizes the URLError-to-NetworkError mapping logic
    /// to ensure consistent behavior between synchronous and asynchronous error wrapping.
    ///
    /// - Parameters:
    ///   - urlError: The URLError to map
    ///   - timeout: The timeout duration to use for timeout errors
    /// - Returns: The appropriate NetworkError for the given URLError
    private static func map(urlError: URLError, timeout: TimeInterval = 60.0) -> NetworkError {
        switch urlError.code {
        case .notConnectedToInternet:
            return .networkUnavailable
        case .timedOut:
            return .requestTimeout(duration: timeout)
        case .cannotFindHost:
            return .invalidEndpoint(reason: "Host not found")
        case .cannotConnectToHost:
            return .transportError(code: urlError.code, underlying: urlError)
        case .networkConnectionLost:
            return .transportError(code: urlError.code, underlying: urlError)
        case .dnsLookupFailed:
            return .invalidEndpoint(reason: "DNS lookup failed")
        case .cancelled:
            return .requestCancelled
        case .badURL:
            return .invalidEndpoint(reason: "Bad URL")
        case .unsupportedURL:
            return .invalidEndpoint(reason: "Unsupported URL")
        case .userAuthenticationRequired:
            return .authenticationFailed
        case .secureConnectionFailed:
            return .transportError(code: urlError.code, underlying: urlError)
        case .serverCertificateUntrusted:
            return .transportError(code: urlError.code, underlying: urlError)
        default:
            return .transportError(code: urlError.code, underlying: urlError)
        }
    }
}

/// MARK: - Equatable Conformance
extension NetworkError {
    public static func == (lhs: NetworkError, rhs: NetworkError) -> Bool {
        switch (lhs, rhs) {
        case (
            .customError(let lhsMessage, let lhsDetails),
            .customError(let rhsMessage, let rhsDetails)
        ):
            return lhsMessage == rhsMessage && lhsDetails == rhsDetails

        // Group HTTP error cases with data and status codes
        case (.httpError(let lhsStatus, let lhsData), .httpError(let rhsStatus, let rhsData)),
            (.badRequest(let lhsData, let lhsStatus), .badRequest(let rhsData, let rhsStatus)),
            (.forbidden(let lhsData, let lhsStatus), .forbidden(let rhsData, let rhsStatus)),
            (.notFound(let lhsData, let lhsStatus), .notFound(let rhsData, let rhsStatus)),
            (.rateLimited(let lhsData, let lhsStatus), .rateLimited(let rhsData, let rhsStatus)),
            (.unauthorized(let lhsData, let lhsStatus), .unauthorized(let rhsData, let rhsStatus)):
            return compareHTTPErrorVariants(
                lhsData: lhsData, lhsStatus: lhsStatus, rhsData: rhsData, rhsStatus: rhsStatus)

        // Group server and decoding error cases
        case (.serverError(let lhsStatus, let lhsData), .serverError(let rhsStatus, let rhsData)):
            return lhsStatus == rhsStatus && lhsData == rhsData
        case (.decodingError(let lhsError, let lhsData), .decodingError(let rhsError, let rhsData)):
            return compareDecodingErrors(
                lhsError: lhsError, lhsData: lhsData, rhsError: rhsError, rhsData: rhsData)
        case (
            .decodingFailed(let lhsReason, let lhsError, let lhsData),
            .decodingFailed(let rhsReason, let rhsError, let rhsData)
        ):
            return compareDecodingFailedErrors(
                lhsReason: lhsReason, lhsError: lhsError, lhsData: lhsData, rhsReason: rhsReason,
                rhsError: rhsError, rhsData: rhsData)

        // Group simple cases without associated values
        case (.networkUnavailable, .networkUnavailable),
            (.noResponse, .noResponse),
            (.imageProcessingFailed, .imageProcessingFailed),
            (.invalidBodyForGET, .invalidBodyForGET),
            (.requestCancelled, .requestCancelled),
            (.authenticationFailed, .authenticationFailed):
            return true

        // Group simple cases with single values
        case (.requestTimeout(let lhsDuration), .requestTimeout(let rhsDuration)):
            return lhsDuration == rhsDuration
        case (.invalidEndpoint(let lhsReason), .invalidEndpoint(let rhsReason)):
            return lhsReason == rhsReason
        case (.badMimeType(let lhsType), .badMimeType(let rhsType)):
            return lhsType == rhsType
        case (.uploadFailed(let lhsMessage), .uploadFailed(let rhsMessage)):
            return lhsMessage == rhsMessage
        case (.cacheError(let lhsMessage), .cacheError(let rhsMessage)):
            return lhsMessage == rhsMessage
        case (.transportError(let lhsCode, _), .transportError(let rhsCode, _)):
            return lhsCode == rhsCode
        case (.outOfScriptBounds(let lhsCall), .outOfScriptBounds(let rhsCall)):
            return lhsCall == rhsCall
        case (
            .payloadTooLarge(let lhsSize, let lhsLimit), .payloadTooLarge(let rhsSize, let rhsLimit)
        ):
            return lhsSize == rhsSize && lhsLimit == rhsLimit
        case (
            .invalidMockConfiguration(let lhsCallIndex, let lhsMissingData, let lhsMissingResponse),
            .invalidMockConfiguration(let rhsCallIndex, let rhsMissingData, let rhsMissingResponse)
        ):
            return lhsCallIndex == rhsCallIndex && lhsMissingData == rhsMissingData
                && lhsMissingResponse == rhsMissingResponse

        default:
            return false
        }
    }

    /// Helper function to compare HTTP error variants with data and status codes
    private static func compareHTTPErrorVariants(
        lhsData: Data?, lhsStatus: Int, rhsData: Data?, rhsStatus: Int
    ) -> Bool {
        return lhsStatus == rhsStatus && lhsData == rhsData
    }

    /// Helper function to compare decoding errors
    private static func compareDecodingErrors(
        lhsError: Error, lhsData: Data?, rhsError: Error, rhsData: Data?
    ) -> Bool {
        let lhsNSError = lhsError as NSError
        let rhsNSError = rhsError as NSError
        return type(of: lhsError) == type(of: rhsError)
            && lhsNSError.domain == rhsNSError.domain && lhsNSError.code == rhsNSError.code
            && lhsData == rhsData
    }

    /// Helper function to compare decoding failed errors
    private static func compareDecodingFailedErrors(
        lhsReason: String, lhsError: Error, lhsData: Data?, rhsReason: String, rhsError: Error,
        rhsData: Data?
    ) -> Bool {
        let lhsNSError = lhsError as NSError
        let rhsNSError = rhsError as NSError
        return lhsReason == rhsReason && type(of: lhsError) == type(of: rhsError)
            && lhsNSError.domain == rhsNSError.domain && lhsNSError.code == rhsNSError.code
            && lhsData == rhsData
    }
}

/// MARK: - Internal localization helper
internal extension NetworkError {
    /// Creates a localized string using modern interpolation syntax
    /// - Parameter key: The localization key
    /// - Returns: A localized string with interpolated values
    static func localizedString(
        _ key: String,
        tableName: String? = nil,
        comment: String = ""
    ) -> String {
        return NSLocalizedString(
            key, tableName: tableName, bundle: NetworkError.l10nBundle, value: key, comment: comment)
    }
}
