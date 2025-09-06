import Foundation

/// NetworkErrorMessages provides localized error descriptions for NetworkError cases
public enum NetworkErrorMessages {
    /// Returns the localized error description for a NetworkError case
    public static func errorDescription(for error: NetworkError) -> String? {
        // Dispatch to category-specific handlers to reduce cyclomatic complexity
        switch error {
        case .httpError, .badRequest, .forbidden, .notFound, .rateLimited, .serverError,
            .unauthorized:
            return HTTPErrorMessages.httpErrorDescription(for: error)
        case .decodingError, .decodingFailed, .badMimeType, .uploadFailed,
            .imageProcessingFailed, .cacheError, .invalidBodyForGET:
            return DataProcessingErrorMessages.dataProcessingErrorDescription(for: error)
        case .networkUnavailable, .requestTimeout, .invalidEndpoint, .noResponse:
            return NetworkConnectivityErrorMessages.networkErrorDescription(for: error)
        case .requestCancelled, .authenticationFailed:
            return AuthErrorMessages.authErrorDescription(for: error)
        case .transportError, .customError:
            return TransportCustomErrorMessages.transportCustomErrorDescription(for: error)
        case .outOfScriptBounds, .payloadTooLarge, .invalidMockConfiguration:
            return TestErrorMessages.testErrorDescription(for: error)
        }
    }
}
