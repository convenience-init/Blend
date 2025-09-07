import Foundation

/// Convenience extensions for NetworkError
extension NetworkError {
    // MARK: - Error Convenience Extensions
    /// Creates a custom error with a formatted message and optional details
    public static func customError(_ message: String, details: String? = nil) -> NetworkError {
        // Use a dedicated custom error case for non-arbitrary error information
        return .customError(message: message, details: details)
    }

    // MARK: - Private Helper Methods
    private final class BundleHelper {}

    internal static let l10nBundle: Bundle = {
        #if SWIFT_PACKAGE
            return Bundle.module
        #else
            return Bundle(for: BundleHelper.self)
        #endif
    }()

    internal static func statusMessage(_ format: String, _ statusCode: Int) -> String {
        return String(
            format: NSLocalizedString(
                format, tableName: nil, bundle: NetworkError.l10nBundle, value: format,
                comment: "Error message for HTTP errors with status code"), statusCode)
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
}

// MARK: - Internal localization helper
extension NetworkError {
    /// Creates a localized string using modern interpolation syntax
    /// - Parameter key: The localization key
    /// - Returns: A localized string with interpolated values
    static func localizedString(
        _ key: String,
        tableName: String? = nil,
        comment: String = ""
    ) -> String {
        return NSLocalizedString(
            key, tableName: tableName, bundle: NetworkError.l10nBundle, value: key, comment: comment
        )
    }
}
