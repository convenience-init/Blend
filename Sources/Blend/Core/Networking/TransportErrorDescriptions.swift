import Foundation

/// TransportErrorDescriptions provides user-friendly descriptions for URLError codes
/// used by NetworkError for consistent error messaging across the library.
public enum TransportErrorDescriptions {
    /// Connection-related error descriptions
    private static let connectionErrors: [URLError.Code: String] = [
        .notConnectedToInternet: "Not connected to internet",
        .cannotFindHost: "Cannot find host",
        .cannotConnectToHost: "Cannot connect to host",
        .networkConnectionLost: "Network connection lost",
        .dnsLookupFailed: "DNS lookup failed",
        .internationalRoamingOff: "International roaming off",
        .dataNotAllowed: "Data not allowed"
    ]

    /// File-related error descriptions
    private static let fileErrors: [URLError.Code: String] = [
        .cannotCreateFile: "Cannot create file",
        .cannotOpenFile: "Cannot open file",
        .cannotCloseFile: "Cannot close file",
        .cannotWriteToFile: "Cannot write to file",
        .cannotRemoveFile: "Cannot remove file",
        .cannotMoveFile: "Cannot move file",
        .fileDoesNotExist: "File does not exist",
        .fileIsDirectory: "File is directory",
        .noPermissionsToReadFile: "No permissions to read file"
    ]

    /// Security-related error descriptions
    private static let securityErrors: [URLError.Code: String] = [
        .secureConnectionFailed: "Secure connection failed",
        .serverCertificateUntrusted: "Server certificate untrusted",
        .serverCertificateHasBadDate: "Server certificate has bad date",
        .serverCertificateHasUnknownRoot: "Server certificate has unknown root",
        .serverCertificateNotYetValid: "Server certificate not yet valid",
        .clientCertificateRejected: "Client certificate rejected",
        .clientCertificateRequired: "Client certificate required",
        .appTransportSecurityRequiresSecureConnection:
            "App Transport Security requires secure connection"
    ]

    /// Request-related error descriptions
    private static let requestErrors: [URLError.Code: String] = [
        .timedOut: "Request timed out",
        .cancelled: "Request cancelled",
        .badURL: "Bad URL",
        .unsupportedURL: "Unsupported URL",
        .requestBodyStreamExhausted: "Request body stream exhausted"
    ]

    /// Background session error descriptions
    private static let backgroundErrors: [URLError.Code: String] = [
        .backgroundSessionRequiresSharedContainer:
            "Background session requires shared container",
        .backgroundSessionInUseByAnotherProcess: "Background session in use by another process",
        .backgroundSessionWasDisconnected: "Background session was disconnected"
    ]

    /// Other miscellaneous error descriptions
    private static let otherErrors: [URLError.Code: String] = [
        .cannotLoadFromNetwork: "Cannot load from network",
        .downloadDecodingFailedMidStream: "Download decoding failed",
        .downloadDecodingFailedToComplete: "Download decoding failed to complete",
        .callIsActive: "Call is active",
        .dataLengthExceedsMaximum: "Data length exceeds maximum",
        .userAuthenticationRequired: "User authentication required"
    ]

    /// Helper function to localize error descriptions
    private static func localizedDescription(for description: String, code: URLError.Code) -> String {
        NSLocalizedString(
            description, tableName: nil, bundle: NetworkError.l10nBundle,
            value: description,
            comment: "User-friendly description for \(code)")
    }

    /// Returns a localized, user-friendly description for a URLError code
    public static func description(for code: URLError.Code) -> String {
        // Check each error group in order of likelihood
        let allErrorGroups = [
            connectionErrors, fileErrors, securityErrors,
            requestErrors, backgroundErrors, otherErrors
        ]

        for errorGroup in allErrorGroups {
            if let description = errorGroup[code] {
                return localizedDescription(for: description, code: code)
            }
        }

        // Fallback to a generic description with the raw value for unknown codes
        return String(
            format: NSLocalizedString(
                "Transport error %d", tableName: nil, bundle: NetworkError.l10nBundle,
                value: "Transport error %d",
                comment: "Fallback description for unknown URLError codes"
            ), code.rawValue)
    }
}
