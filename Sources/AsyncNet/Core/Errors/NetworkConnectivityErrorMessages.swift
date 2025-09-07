import Foundation

/// Network connectivity error message handlers for NetworkError
public enum NetworkConnectivityErrorMessages {
    /// Returns network error descriptions
    public static func networkErrorDescription(for error: NetworkError) -> String {
        switch error {
        case .networkUnavailable:
            return networkConnectivityErrorDescription()
        case .requestTimeout(let duration):
            return timeoutErrorDescription(duration)
        case .invalidEndpoint(let reason):
            return invalidEndpointDescription(reason)
        case .noResponse:
            return noResponseDescription()
        default:
            return "Unknown network error"
        }
    }

    private static func networkConnectivityErrorDescription() -> String {
        return NSLocalizedString(
            "Network unavailable.", tableName: nil, bundle: NetworkError.l10nBundle,
            value: "Network unavailable.",
            comment: "Error message when network is not available")
    }

    private static func noResponseDescription() -> String {
        return NSLocalizedString(
            "No network response.", tableName: nil, bundle: NetworkError.l10nBundle,
            value: "No network response.",
            comment: "Error message when no response is received")
    }

    private static func timeoutErrorDescription(_ duration: TimeInterval) -> String {
        return String(
            format: NSLocalizedString(
                "Request timed out after %.2f seconds.", tableName: nil,
                bundle: NetworkError.l10nBundle,
                value: "Request timed out after %.2f seconds.",
                comment: "Error message for request timeouts with duration"), duration)
    }

    private static func invalidEndpointDescription(_ reason: String) -> String {
        return String(
            format: NSLocalizedString(
                "Invalid endpoint: %@", tableName: nil, bundle: NetworkError.l10nBundle,
                value: "Invalid endpoint: %@",
                comment: "Error message for invalid endpoints with reason"), reason)
    }
}
