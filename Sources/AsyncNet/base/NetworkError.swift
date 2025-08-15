import Foundation

public enum NetworkError: Error, Sendable {
    case decode
    case offLine
    case unauthorized
    case custom(msg: String?)
    case unknown
    case invalidURL(String)
    case networkError(Error)
    case noResponse
    case decodingError(Error)
    case badStatusCode(String)
    case badMimeType(String)
    case uploadFailed(String)
    case imageProcessingFailed
    case cacheError(String)
    
    public func message() -> String {
        switch self {
        case .offLine:
            return "Cannot establish a network connection."
        case .unauthorized:
            return "Not Authorized!"
        case .invalidURL(let message):
            return "Invalid URL: \(message)"
        case .networkError(let error):
            return error.localizedDescription
        case .noResponse:
            return "No network response"
        case .decodingError(let error):
            return "Decoding error: \(error)"
        case .badStatusCode(let message):
            return "Bad status code: \(message)"
        case .badMimeType(let mimeType):
            return "Unsupported mime type: \(mimeType)"
        case .uploadFailed(let message):
            return "Upload failed: \(message)"
        case .imageProcessingFailed:
            return "Failed to process image data"
        case .cacheError(let message):
            return "Cache error: \(message)"
        case let .custom(msg: message):
            return message ?? "Please try again."
        default:
            return "An unknown error occurred."
        }
    }
}

// MARK: - Error Convenience Extensions
public extension NetworkError {
    /// Creates a custom error with a formatted message
    static func customError(_ message: String, details: String? = nil) -> NetworkError {
        let fullMessage = details != nil ? "\(message): \(details!)" : message
        return .custom(msg: fullMessage)
    }
    
    /// Wraps a generic error as a network error
    static func wrap(_ error: Error) -> NetworkError {
        if let networkError = error as? NetworkError {
            return networkError
        }
        return .networkError(error)
    }
}
