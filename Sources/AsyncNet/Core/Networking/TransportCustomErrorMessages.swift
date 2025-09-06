import Foundation

/// Transport and custom error message handlers for NetworkError
public enum TransportCustomErrorMessages {
    /// Returns transport/custom error descriptions
    public static func transportCustomErrorDescription(for error: NetworkError) -> String {
        switch error {
        case .transportError(let code, let underlying):
            return transportErrorDescription(code, underlying)
        case .customError(let message, let details):
            return customErrorDescription(message, details)
        default:
            return "Unknown transport/custom error"
        }
    }

    private static func transportErrorDescription(_ code: URLError.Code, _ underlying: URLError)
        -> String
    {
        return String(
            format: NSLocalizedString(
                "Network connection error: %@ (%@)", tableName: nil,
                bundle: NetworkError.l10nBundle,
                value: "Network connection error: %@ (%@)",
                comment: "Error message for network connection errors with details"),
            TransportErrorDescriptions.description(for: code), underlying.localizedDescription)
    }

    private static func customErrorDescription(_ message: String, _ details: String?) -> String {
        if let details = details {
            return String(
                format: NSLocalizedString(
                    "%@: %@", tableName: nil, bundle: NetworkError.l10nBundle, value: "%@: %@",
                    comment: "Custom error message with details"), message, details)
        } else {
            return message
        }
    }
}
