import Foundation

/// Authentication and authorization error message handlers for NetworkError
public enum AuthErrorMessages {
    /// Returns auth error descriptions
    public static func authErrorDescription(for error: NetworkError) -> String {
        switch error {
        case .requestCancelled:
            return requestCancelledDescription()
        case .authenticationFailed:
            return authenticationFailedDescription()
        default:
            return "Unknown auth error"
        }
    }

    private static func requestCancelledDescription() -> String {
        return NSLocalizedString(
            "Request was cancelled.", tableName: nil, bundle: NetworkError.l10nBundle,
            value: "Request was cancelled.",
            comment: "Error message for cancelled requests")
    }

    private static func authenticationFailedDescription() -> String {
        return NSLocalizedString(
            "Authentication failed.", tableName: nil, bundle: NetworkError.l10nBundle,
            value: "Authentication failed.",
            comment: "Error message for authentication failures")
    }
}
