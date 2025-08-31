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
    /// Decoding error with underlying error and optional data (Sendable)
    case decodingError(underlying: Error, data: Data?)
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
    /// Represents a transport-level error (e.g., connection, timeout, DNS) not classified as HTTP status error.
    /// - Parameters:
    ///   - code: The URLError.Code associated with the transport error.
    ///   - underlying: The original URLError instance.
    case transportError(code: URLError.Code, underlying: URLError)
    /// Error case for out-of-script-bounds issues, carrying the call number.
    case outOfScriptBounds(call: Int)

    // MARK: - Private Helper Methods
    private static func statusMessage(_ formatKey: String, _ statusCode: Int) -> String {
        return String(format: NSLocalizedString(formatKey, comment: "Error message for HTTP errors with status code"), statusCode)
    }

    private static func transportErrorDescription(_ code: URLError.Code) -> String {
        switch code {
        case .notConnectedToInternet:
            return NSLocalizedString("Not connected to internet", comment: "User-friendly description for URLError.Code.notConnectedToInternet")
        case .timedOut:
            return NSLocalizedString("Request timed out", comment: "User-friendly description for URLError.Code.timedOut")
        case .cannotFindHost:
            return NSLocalizedString("Cannot find host", comment: "User-friendly description for URLError.Code.cannotFindHost")
        case .cannotConnectToHost:
            return NSLocalizedString("Cannot connect to host", comment: "User-friendly description for URLError.Code.cannotConnectToHost")
        case .networkConnectionLost:
            return NSLocalizedString("Network connection lost", comment: "User-friendly description for URLError.Code.networkConnectionLost")
        case .dnsLookupFailed:
            return NSLocalizedString("DNS lookup failed", comment: "User-friendly description for URLError.Code.dnsLookupFailed")
        case .cancelled:
            return NSLocalizedString("Request cancelled", comment: "User-friendly description for URLError.Code.cancelled")
        case .badURL:
            return NSLocalizedString("Bad URL", comment: "User-friendly description for URLError.Code.badURL")
        case .unsupportedURL:
            return NSLocalizedString("Unsupported URL", comment: "User-friendly description for URLError.Code.unsupportedURL")
        case .userAuthenticationRequired:
            return NSLocalizedString("User authentication required", comment: "User-friendly description for URLError.Code.userAuthenticationRequired")
        case .secureConnectionFailed:
            return NSLocalizedString("Secure connection failed", comment: "User-friendly description for URLError.Code.secureConnectionFailed")
        case .serverCertificateUntrusted:
            return NSLocalizedString("Server certificate untrusted", comment: "User-friendly description for URLError.Code.serverCertificateUntrusted")
        case .serverCertificateHasBadDate:
            return NSLocalizedString("Server certificate has bad date", comment: "User-friendly description for URLError.Code.serverCertificateHasBadDate")
        case .serverCertificateHasUnknownRoot:
            return NSLocalizedString("Server certificate has unknown root", comment: "User-friendly description for URLError.Code.serverCertificateHasUnknownRoot")
        case .serverCertificateNotYetValid:
            return NSLocalizedString("Server certificate not yet valid", comment: "User-friendly description for URLError.Code.serverCertificateNotYetValid")
        case .clientCertificateRejected:
            return NSLocalizedString("Client certificate rejected", comment: "User-friendly description for URLError.Code.clientCertificateRejected")
        case .clientCertificateRequired:
            return NSLocalizedString("Client certificate required", comment: "User-friendly description for URLError.Code.clientCertificateRequired")
        case .cannotLoadFromNetwork:
            return NSLocalizedString("Cannot load from network", comment: "User-friendly description for URLError.Code.cannotLoadFromNetwork")
        case .cannotCreateFile:
            return NSLocalizedString("Cannot create file", comment: "User-friendly description for URLError.Code.cannotCreateFile")
        case .cannotOpenFile:
            return NSLocalizedString("Cannot open file", comment: "User-friendly description for URLError.Code.cannotOpenFile")
        case .cannotCloseFile:
            return NSLocalizedString("Cannot close file", comment: "User-friendly description for URLError.Code.cannotCloseFile")
        case .cannotWriteToFile:
            return NSLocalizedString("Cannot write to file", comment: "User-friendly description for URLError.Code.cannotWriteToFile")
        case .cannotRemoveFile:
            return NSLocalizedString("Cannot remove file", comment: "User-friendly description for URLError.Code.cannotRemoveFile")
        case .cannotMoveFile:
            return NSLocalizedString("Cannot move file", comment: "User-friendly description for URLError.Code.cannotMoveFile")
        case .downloadDecodingFailedMidStream:
            return NSLocalizedString("Download decoding failed", comment: "User-friendly description for URLError.Code.downloadDecodingFailedMidStream")
        case .downloadDecodingFailedToComplete:
            return NSLocalizedString("Download decoding failed to complete", comment: "User-friendly description for URLError.Code.downloadDecodingFailedToComplete")
        case .internationalRoamingOff:
            return NSLocalizedString("International roaming off", comment: "User-friendly description for URLError.Code.internationalRoamingOff")
        case .callIsActive:
            return NSLocalizedString("Call is active", comment: "User-friendly description for URLError.Code.callIsActive")
        case .dataNotAllowed:
            return NSLocalizedString("Data not allowed", comment: "User-friendly description for URLError.Code.dataNotAllowed")
        case .requestBodyStreamExhausted:
            return NSLocalizedString("Request body stream exhausted", comment: "User-friendly description for URLError.Code.requestBodyStreamExhausted")
        case .appTransportSecurityRequiresSecureConnection:
            return NSLocalizedString("App Transport Security requires secure connection", comment: "User-friendly description for URLError.Code.appTransportSecurityRequiresSecureConnection")
        case .fileDoesNotExist:
            return NSLocalizedString("File does not exist", comment: "User-friendly description for URLError.Code.fileDoesNotExist")
        case .fileIsDirectory:
            return NSLocalizedString("File is directory", comment: "User-friendly description for URLError.Code.fileIsDirectory")
        case .noPermissionsToReadFile:
            return NSLocalizedString("No permissions to read file", comment: "User-friendly description for URLError.Code.noPermissionsToReadFile")
        case .dataLengthExceedsMaximum:
            return NSLocalizedString("Data length exceeds maximum", comment: "User-friendly description for URLError.Code.dataLengthExceedsMaximum")
        case .backgroundSessionRequiresSharedContainer:
            return NSLocalizedString("Background session requires shared container", comment: "User-friendly description for URLError.Code.backgroundSessionRequiresSharedContainer")
        case .backgroundSessionInUseByAnotherProcess:
            return NSLocalizedString("Background session in use by another process", comment: "User-friendly description for URLError.Code.backgroundSessionInUseByAnotherProcess")
        case .backgroundSessionWasDisconnected:
            return NSLocalizedString("Background session was disconnected", comment: "User-friendly description for URLError.Code.backgroundSessionWasDisconnected")
        default:
            // Fallback to a generic description with the raw value for unknown codes
            return String(format: NSLocalizedString("Transport error %d", comment: "Fallback description for unknown URLError codes"), code.rawValue)
        }
    }

    // MARK: - LocalizedError Conformance
    public var errorDescription: String? {
    switch self {
        case .httpError(let statusCode, _):
            return NetworkError.statusMessage("HTTP error: Status code %d", statusCode)
        case .decodingError(let underlying, _):
            return String(format: NSLocalizedString("Decoding error: %@", comment: "Error message for decoding failures with underlying description"), underlying.localizedDescription)
        case .networkUnavailable:
            return NSLocalizedString("Network unavailable.", comment: "Error message when network is not available")
        case .requestTimeout(let duration):
            return String(format: NSLocalizedString("Request timed out after %.2f seconds.", comment: "Error message for request timeouts with duration"), duration)
        case .invalidEndpoint(let reason):
            return String(format: NSLocalizedString("Invalid endpoint: %@", comment: "Error message for invalid endpoints with reason"), reason)
        case .unauthorized(_, _):
            return NSLocalizedString("Not authorized.", comment: "Error message for unauthorized access")
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
        case .invalidBodyForGET:
            return NSLocalizedString("GET requests cannot have a body.", comment: "Error message for invalid body in GET request")
        case .requestCancelled:
            return NSLocalizedString("Request was cancelled.", comment: "Error message for cancelled requests")
        case .authenticationFailed:
            return NSLocalizedString("Authentication failed.", comment: "Error message for authentication failures")
        case .transportError(let code, let underlying):
            return String(format: NSLocalizedString("Transport error: %@ - %@", comment: "Error message for transport errors with code and description"), NetworkError.transportErrorDescription(code), underlying.localizedDescription)
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
            return NSLocalizedString("Please try again or contact support.", comment: "Recovery suggestion for custom errors")
        case .httpError(let statusCode, _):
            switch statusCode {
            case 400: return NSLocalizedString("Check the request parameters and format.", comment: "Recovery suggestion for HTTP 400 Bad Request errors")
            case 401: return NSLocalizedString("Check your credentials and try again.", comment: "Recovery suggestion for HTTP 401 Unauthorized errors")
            case 403: return NSLocalizedString("Check your permissions for this resource.", comment: "Recovery suggestion for HTTP 403 Forbidden errors")
            case 404: return NSLocalizedString("Verify the endpoint URL and resource exists.", comment: "Recovery suggestion for HTTP 404 Not Found errors")
            case 429: return NSLocalizedString("Wait before making another request or reduce request frequency.", comment: "Recovery suggestion for HTTP 429 Too Many Requests errors")
            case 500..<600: return NSLocalizedString("Try again later. The server encountered an error.", comment: "Recovery suggestion for HTTP 5xx Server errors")
            default: return NSLocalizedString("Check the request and try again.", comment: "Recovery suggestion for general HTTP errors")
            }
        case .decodingError:
            return NSLocalizedString("Ensure the response format matches the expected model.", comment: "Recovery suggestion for decoding errors")
        case .networkUnavailable:
            return NSLocalizedString("Check your internet connection.", comment: "Recovery suggestion for network unavailable errors")
        case .requestTimeout:
            return NSLocalizedString("Try again with a better connection or increase timeout duration.", comment: "Recovery suggestion for request timeout errors")
        case .invalidEndpoint:
            return NSLocalizedString("Verify the endpoint configuration.", comment: "Recovery suggestion for invalid endpoint errors")
        case .unauthorized:
            return NSLocalizedString("Check your authentication and permissions.", comment: "Recovery suggestion for unauthorized access errors")
        case .noResponse:
            return NSLocalizedString("Check network connectivity and server status.", comment: "Recovery suggestion for no response errors")
        case .badMimeType:
            return NSLocalizedString("Ensure the server returns a supported content format.", comment: "Recovery suggestion for unsupported MIME type errors")
        case .uploadFailed:
            return NSLocalizedString("Check content format and network connection.", comment: "Recovery suggestion for upload failure errors")
        case .imageProcessingFailed:
            return NSLocalizedString("Ensure the content data is valid and supported.", comment: "Recovery suggestion for image processing failure errors")
        case .cacheError:
            return NSLocalizedString("Check cache configuration and available memory.", comment: "Recovery suggestion for cache error issues")
        case .invalidBodyForGET:
            return NSLocalizedString("Remove the body from GET requests or use a different HTTP method.", comment: "Recovery suggestion for invalid body in GET request errors")
        case .requestCancelled:
            return NSLocalizedString("The request was cancelled before completion.", comment: "Recovery suggestion for cancelled requests")
        case .authenticationFailed:
            return NSLocalizedString("Verify your credentials and try again.", comment: "Recovery suggestion for authentication failures")
        case .transportError:
            return NSLocalizedString("Check network configuration and try again.", comment: "Recovery suggestion for transport layer errors")
        case .outOfScriptBounds:
            return NSLocalizedString("Check the mock script configuration and ensure sufficient responses are provided.", comment: "Recovery suggestion for out-of-script-bounds mock errors")
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
        // Fallback to custom error
    return .custom(message: "Unknown error", details: String(describing: error))
    }

    /// Default timeout duration used when wrapping URLError.timedOut
    /// This value can be configured at runtime to adjust the default timeout duration
    /// used when creating requestTimeout errors from URLError.timedOut instances.
    /// Note: Access to this property should be synchronized by the caller if used in concurrent contexts.
    nonisolated(unsafe) static var defaultTimeoutDuration: TimeInterval = 60.0
}

// MARK: - Equatable Conformance
extension NetworkError {
    public static func == (lhs: NetworkError, rhs: NetworkError) -> Bool {
        switch (lhs, rhs) {
        case (.custom(let lhsMessage, let lhsDetails), .custom(let rhsMessage, let rhsDetails)):
            return lhsMessage == rhsMessage && lhsDetails == rhsDetails
        case (.httpError(let lhsStatus, let lhsData), .httpError(let rhsStatus, let rhsData)):
            return lhsStatus == rhsStatus && lhsData == rhsData
        case (.decodingError(let lhsError, let lhsData), .decodingError(let rhsError, let rhsData)):
            // Compare error types and descriptions since Error is not Equatable
            return type(of: lhsError) == type(of: rhsError) && 
                   lhsError.localizedDescription == rhsError.localizedDescription && 
                   lhsData == rhsData
        case (.networkUnavailable, .networkUnavailable):
            return true
        case (.requestTimeout(let lhsDuration), .requestTimeout(let rhsDuration)):
            return lhsDuration == rhsDuration
        case (.invalidEndpoint(let lhsReason), .invalidEndpoint(let rhsReason)):
            return lhsReason == rhsReason
        case (.unauthorized(let lhsData, let lhsStatusCode), .unauthorized(let rhsData, let rhsStatusCode)):
            return lhsData == rhsData && lhsStatusCode == rhsStatusCode
        case (.noResponse, .noResponse):
            return true
        case (.badMimeType(let lhsType), .badMimeType(let rhsType)):
            return lhsType == rhsType
        case (.uploadFailed(let lhsMessage), .uploadFailed(let rhsMessage)):
            return lhsMessage == rhsMessage
        case (.imageProcessingFailed, .imageProcessingFailed):
            return true
        case (.cacheError(let lhsMessage), .cacheError(let rhsMessage)):
            return lhsMessage == rhsMessage
        case (.invalidBodyForGET, .invalidBodyForGET):
            return true
        case (.requestCancelled, .requestCancelled):
            return true
        case (.authenticationFailed, .authenticationFailed):
            return true
        case (.transportError(let lhsCode, let lhsUnderlying), .transportError(let rhsCode, let rhsUnderlying)):
            return lhsCode == rhsCode && lhsUnderlying == rhsUnderlying
        case (.outOfScriptBounds(let lhsCall), .outOfScriptBounds(let rhsCall)):
            return lhsCall == rhsCall
        default:
            return false
        }
    }
}
