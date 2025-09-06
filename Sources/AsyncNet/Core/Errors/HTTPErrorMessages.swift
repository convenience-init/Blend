import Foundation

/// HTTP error message handlers for NetworkError
public enum HTTPErrorMessages {
    /// Returns HTTP error descriptions
    public static func httpErrorDescription(for error: NetworkError) -> String {
        switch error {
        case .httpError(let statusCode, _), .serverError(let statusCode, _):
            return httpStatusErrorDescription(statusCode)
        case .badRequest(_, let statusCode):
            return httpStatusErrorDescription(statusCode, prefix: "Bad request")
        case .forbidden(_, let statusCode):
            return httpStatusErrorDescription(statusCode, prefix: "Forbidden")
        case .notFound(_, let statusCode):
            return httpStatusErrorDescription(statusCode, prefix: "Not found")
        case .rateLimited(_, let statusCode):
            return httpStatusErrorDescription(statusCode, prefix: "Rate limited")
        case .unauthorized(_, let statusCode):
            return httpStatusErrorDescription(statusCode, prefix: "Not authorized")
        default:
            return "Unknown HTTP error"
        }
    }

    private static func httpStatusErrorDescription(_ statusCode: Int, prefix: String? = nil)
        -> String
    {
        let message = prefix ?? (statusCode >= 500 ? "Server error" : "HTTP error")
        return NetworkError.statusMessage("\(message): Status code %d", statusCode)
    }
}
