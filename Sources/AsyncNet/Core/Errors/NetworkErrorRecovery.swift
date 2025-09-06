import Foundation

/// NetworkErrorRecovery provides recovery suggestions for NetworkError cases
public enum NetworkErrorRecovery {
    /// Returns the localized recovery suggestion for a NetworkError case
    public static func recoverySuggestion(for error: NetworkError) -> String? {
        switch error {
        case .httpError(let statusCode, _):
            return httpErrorRecoverySuggestion(statusCode: statusCode)
        case .badRequest, .forbidden, .notFound, .rateLimited, .unauthorized:
            return clientErrorRecoverySuggestion(for: error)
        case .serverError(let statusCode, _):
            return serverErrorRecoverySuggestion(statusCode: statusCode)
        case .decodingError, .decodingFailed:
            return decodingErrorRecoverySuggestion(for: error)
        case .networkUnavailable, .requestTimeout, .transportError:
            return networkErrorRecoverySuggestion(for: error)
        case .invalidEndpoint, .noResponse, .badMimeType:
            return connectionErrorRecoverySuggestion(for: error)
        case .uploadFailed, .imageProcessingFailed, .payloadTooLarge:
            return dataErrorRecoverySuggestion(for: error)
        case .cacheError, .invalidBodyForGET, .requestCancelled:
            return requestErrorRecoverySuggestion(for: error)
        case .authenticationFailed, .customError, .outOfScriptBounds, .invalidMockConfiguration:
            return otherErrorRecoverySuggestion(for: error)
        }
    }

    private static func httpErrorRecoverySuggestion(statusCode: Int) -> String {
        return NetworkError.statusMessage("Check server logs for status code %d", statusCode)
    }

    private static func clientErrorRecoverySuggestion(for error: NetworkError) -> String {
        switch error {
        case .badRequest:
            return NSLocalizedString(
                "Verify request parameters and try again.", tableName: nil,
                bundle: NetworkError.l10nBundle,
                value: "Verify request parameters and try again.",
                comment: "Recovery suggestion for bad request errors")
        case .forbidden:
            return NSLocalizedString(
                "Check authentication credentials and permissions.", tableName: nil,
                bundle: NetworkError.l10nBundle,
                value: "Check authentication credentials and permissions.",
                comment: "Recovery suggestion for forbidden errors")
        case .notFound:
            return NSLocalizedString(
                "Verify the resource URL and try again.", tableName: nil,
                bundle: NetworkError.l10nBundle,
                value: "Verify the resource URL and try again.",
                comment: "Recovery suggestion for not found errors")
        case .rateLimited:
            return NSLocalizedString(
                "Wait before retrying the request.", tableName: nil,
                bundle: NetworkError.l10nBundle,
                value: "Wait before retrying the request.",
                comment: "Recovery suggestion for rate limited errors")
        case .unauthorized:
            return NSLocalizedString(
                "Refresh authentication credentials and try again.", tableName: nil,
                bundle: NetworkError.l10nBundle,
                value: "Refresh authentication credentials and try again.",
                comment: "Recovery suggestion for unauthorized errors")
        default:
            return ""
        }
    }

    private static func serverErrorRecoverySuggestion(statusCode: Int) -> String {
        return NetworkError.statusMessage(
            "Contact server administrator for status code %d", statusCode)
    }

    private static func decodingErrorRecoverySuggestion(for error: NetworkError) -> String {
        switch error {
        case .decodingError:
            return NSLocalizedString(
                "Check data format and API response structure.", tableName: nil,
                bundle: NetworkError.l10nBundle,
                value: "Check data format and API response structure.",
                comment: "Recovery suggestion for decoding errors")
        case .decodingFailed:
            return NSLocalizedString(
                "Verify data structure matches expected format.", tableName: nil,
                bundle: NetworkError.l10nBundle,
                value: "Verify data structure matches expected format.",
                comment: "Recovery suggestion for decoding failures")
        default:
            return ""
        }
    }

    private static func networkErrorRecoverySuggestion(for error: NetworkError) -> String {
        switch error {
        case .networkUnavailable:
            return NSLocalizedString(
                "Check network connection and try again.", tableName: nil,
                bundle: NetworkError.l10nBundle,
                value: "Check network connection and try again.",
                comment: "Recovery suggestion for network unavailable")
        case .requestTimeout:
            return NSLocalizedString(
                "Check network connection or try again later.", tableName: nil,
                bundle: NetworkError.l10nBundle,
                value: "Check network connection or try again later.",
                comment: "Recovery suggestion for request timeouts")
        case .transportError:
            return NSLocalizedString(
                "Check network connection and firewall settings.", tableName: nil,
                bundle: NetworkError.l10nBundle,
                value: "Check network connection and firewall settings.",
                comment: "Recovery suggestion for transport errors")
        default:
            return ""
        }
    }

    private static func connectionErrorRecoverySuggestion(for error: NetworkError) -> String {
        switch error {
        case .invalidEndpoint:
            return NSLocalizedString(
                "Verify endpoint configuration and URL format.", tableName: nil,
                bundle: NetworkError.l10nBundle,
                value: "Verify endpoint configuration and URL format.",
                comment: "Recovery suggestion for invalid endpoints")
        case .noResponse:
            return NSLocalizedString(
                "Check network connection and server availability.", tableName: nil,
                bundle: NetworkError.l10nBundle,
                value: "Check network connection and server availability.",
                comment: "Recovery suggestion for no response")
        case .badMimeType:
            return NSLocalizedString(
                "Verify content type matches expected format.", tableName: nil,
                bundle: NetworkError.l10nBundle,
                value: "Verify content type matches expected format.",
                comment: "Recovery suggestion for bad MIME type")
        default:
            return ""
        }
    }

    private static func dataErrorRecoverySuggestion(for error: NetworkError) -> String {
        switch error {
        case .uploadFailed:
            return NSLocalizedString(
                "Check file size, network connection, and try again.", tableName: nil,
                bundle: NetworkError.l10nBundle,
                value: "Check file size, network connection, and try again.",
                comment: "Recovery suggestion for upload failures")
        case .imageProcessingFailed:
            return NSLocalizedString(
                "Verify image format and data integrity.", tableName: nil,
                bundle: NetworkError.l10nBundle,
                value: "Verify image format and data integrity.",
                comment: "Recovery suggestion for image processing failures")
        case .payloadTooLarge:
            return NSLocalizedString(
                "Reduce payload size or contact administrator for limit increase.", tableName: nil,
                bundle: NetworkError.l10nBundle,
                value: "Reduce payload size or contact administrator for limit increase.",
                comment: "Recovery suggestion for payload too large")
        default:
            return ""
        }
    }

    private static func requestErrorRecoverySuggestion(for error: NetworkError) -> String {
        switch error {
        case .cacheError:
            return NSLocalizedString(
                "Clear cache and try again.", tableName: nil,
                bundle: NetworkError.l10nBundle,
                value: "Clear cache and try again.",
                comment: "Recovery suggestion for cache errors")
        case .invalidBodyForGET:
            return NSLocalizedString(
                "Remove request body for GET requests.", tableName: nil,
                bundle: NetworkError.l10nBundle,
                value: "Remove request body for GET requests.",
                comment: "Recovery suggestion for invalid body in GET request")
        case .requestCancelled:
            return NSLocalizedString(
                "Retry the request if needed.", tableName: nil,
                bundle: NetworkError.l10nBundle,
                value: "Retry the request if needed.",
                comment: "Recovery suggestion for cancelled requests")
        default:
            return ""
        }
    }

    private static func otherErrorRecoverySuggestion(for error: NetworkError) -> String {
        switch error {
        case .authenticationFailed:
            return NSLocalizedString(
                "Verify credentials and authentication method.", tableName: nil,
                bundle: NetworkError.l10nBundle,
                value: "Verify credentials and authentication method.",
                comment: "Recovery suggestion for authentication failures")
        case .customError:
            return NSLocalizedString(
                "Review error details and take appropriate action.", tableName: nil,
                bundle: NetworkError.l10nBundle,
                value: "Review error details and take appropriate action.",
                comment: "Recovery suggestion for custom errors")
        case .outOfScriptBounds:
            return NSLocalizedString(
                "Check mock data configuration for sufficient test cases.", tableName: nil,
                bundle: NetworkError.l10nBundle,
                value: "Check mock data configuration for sufficient test cases.",
                comment: "Recovery suggestion for out-of-script-bounds")
        case .invalidMockConfiguration:
            return NSLocalizedString(
                "Add missing test data and response configurations.", tableName: nil,
                bundle: NetworkError.l10nBundle,
                value: "Add missing test data and response configurations.",
                comment: "Recovery suggestion for invalid mock configuration")
        default:
            return ""
        }
    }
}
