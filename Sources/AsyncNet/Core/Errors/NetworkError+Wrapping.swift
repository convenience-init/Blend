import Foundation

/// NetworkError wrapping logic extracted to reduce file size
extension NetworkError {
    /// Wraps an Error into a NetworkError with configurable timeout duration.
    /// This async version allows for thread-safe configuration of timeout behavior.
    /// - Parameters:
    ///   - error: The error to wrap
    ///   - config: The configuration to use for timeout duration
    /// - Returns: A NetworkError representation of the input error
    @available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
    public static func wrapAsync(_ error: Error, config: AsyncNetConfig) async -> NetworkError {
        // If error is already a NetworkError, return it as-is
        if let networkError = error as? NetworkError {
            return networkError
        }

        switch error {
        case let urlError as URLError:
            return NetworkError.map(urlError: urlError, timeout: await config.timeoutDuration)
        case let decodingError as DecodingError:
            let reason = decodingError.localizedDescription
            return .decodingFailed(reason: reason, underlying: decodingError, data: nil)
        default:
            return .customError(message: "Unknown error", details: String(describing: error))
        }
    }

    /// Maps a URLError to the appropriate NetworkError with the specified timeout duration.
    ///
    /// This helper function centralizes the URLError-to-NetworkError mapping logic
    /// to ensure consistent behavior between synchronous and asynchronous error wrapping.
    ///
    /// - Parameters:
    ///   - urlError: The URLError to map
    ///   - timeout: The timeout duration to use for timeout errors
    /// - Returns: The appropriate NetworkError for the given URLError
    private static func map(urlError: URLError, timeout: TimeInterval = 60.0) -> NetworkError {
        switch urlError.code {
        case .notConnectedToInternet:
            return .networkUnavailable
        case .timedOut:
            return .requestTimeout(duration: timeout)
        case .cannotFindHost, .dnsLookupFailed:
            return .invalidEndpoint(
                reason: urlError.code == .cannotFindHost ? "Host not found" : "DNS lookup failed")
        case .cannotConnectToHost, .networkConnectionLost, .secureConnectionFailed,
            .serverCertificateUntrusted:
            return .transportError(code: urlError.code, underlying: urlError)
        case .cancelled:
            return .requestCancelled
        case .badURL, .unsupportedURL:
            return .invalidEndpoint(
                reason: urlError.code == .badURL ? "Bad URL" : "Unsupported URL")
        case .userAuthenticationRequired:
            return .authenticationFailed
        default:
            return .transportError(code: urlError.code, underlying: urlError)
        }
    }
}
