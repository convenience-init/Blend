import Foundation

/// Data processing error message handlers for NetworkError
public enum DataProcessingErrorMessages {
    /// Returns data processing error descriptions
    public static func dataProcessingErrorDescription(for error: NetworkError) -> String {
        switch error {
        case .decodingError(let underlying, _):
            return decodingErrorDescription(underlying)
        case .decodingFailed(let reason, _, _):
            return decodingFailedDescription(reason)
        case .badMimeType(let mimeType):
            return badMimeTypeDescription(mimeType)
        case .uploadFailed(let message):
            return uploadFailedDescription(message)
        case .imageProcessingFailed:
            return imageProcessingFailedDescription()
        case .cacheError(let message):
            return cacheErrorDescription(message)
        case .invalidBodyForGET:
            return invalidBodyForGETDescription()
        default:
            return "Unknown data processing error"
        }
    }

    private static func decodingErrorDescription(_ underlying: any Error & Sendable) -> String {
        return String(
            format: NSLocalizedString(
                "Decoding error: %@", tableName: nil, bundle: NetworkError.l10nBundle,
                value: "Decoding error: %@",
                comment: "Error message for decoding failures with underlying description"),
            underlying.localizedDescription)
    }

    private static func decodingFailedDescription(_ reason: String) -> String {
        return String(
            format: NSLocalizedString(
                "Decoding failed: %@", tableName: nil, bundle: NetworkError.l10nBundle,
                value: "Decoding failed: %@",
                comment: "Error message for detailed decoding failures"),
            reason)
    }

    private static func badMimeTypeDescription(_ mimeType: String) -> String {
        return String(
            format: NSLocalizedString(
                "Unsupported MIME type: %@", tableName: nil, bundle: NetworkError.l10nBundle,
                value: "Unsupported MIME type: %@",
                comment: "Error message for unsupported MIME types"
            ), mimeType)
    }

    private static func uploadFailedDescription(_ message: String) -> String {
        return String(
            format: NSLocalizedString(
                "Upload failed: %@", tableName: nil, bundle: NetworkError.l10nBundle,
                value: "Upload failed: %@",
                comment: "Error message for upload failures with details"),
            message)
    }

    private static func imageProcessingFailedDescription() -> String {
        return NSLocalizedString(
            "Failed to process image data.", tableName: nil, bundle: NetworkError.l10nBundle,
            value: "Failed to process image data.",
            comment: "Error message for image processing failures")
    }

    private static func cacheErrorDescription(_ message: String) -> String {
        return String(
            format: NSLocalizedString(
                "Cache operation failed: %@", tableName: nil, bundle: NetworkError.l10nBundle,
                value: "Cache operation failed: %@",
                comment: "Error message for cache operation failures with details"),
            message)
    }

    private static func invalidBodyForGETDescription() -> String {
        return NSLocalizedString(
            "GET requests cannot have a body.", tableName: nil, bundle: NetworkError.l10nBundle,
            value: "GET requests cannot have a body.",
            comment: "Error message for invalid body in GET request")
    }
}
