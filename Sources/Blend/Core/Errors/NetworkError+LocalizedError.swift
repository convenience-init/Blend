import Foundation

/// LocalizedError conformance for NetworkError
extension NetworkError: LocalizedError {
    // MARK: - LocalizedError Conformance
    public var errorDescription: String? {
        return NetworkErrorMessages.errorDescription(for: self)
    }

    public var recoverySuggestion: String? {
        return NetworkErrorRecovery.recoverySuggestion(for: self)
    }
}
