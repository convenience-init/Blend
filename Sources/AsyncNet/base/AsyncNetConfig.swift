import Foundation

/// Thread-safe configuration for AsyncNet networking operations.
///
/// `AsyncNetConfig` provides actor-isolated configuration that can be safely accessed
/// from concurrent contexts without race conditions.
///
/// - Important: All properties are actor-isolated and require `await` for access.
///
/// ### Usage Example
/// ```swift
/// // Configure timeout duration
/// await AsyncNetConfig.shared.setTimeoutDuration(30.0)
///
/// // Use in async error wrapping
/// let networkError = await NetworkError.wrapAsync(error, config: AsyncNetConfig.shared)
/// ```
///
/// ### Thread Safety
/// This actor ensures that configuration changes are atomic and visible across all threads.
/// All access to configuration properties requires `await` to maintain isolation.
///
/// Enhanced configuration system for AsyncNet (ASYNC-302)
@available(macOS 10.15, iOS 13.0, watchOS 6.0, tvOS 13.0, *)
public actor AsyncNetConfig {
    /// Shared instance for global configuration access
    public static let shared = AsyncNetConfig()

    /// Default timeout duration for network requests (in seconds)
    private var _timeoutDuration: TimeInterval = 60.0

    /// Private initializer to enforce singleton pattern
    private init() {}

    /// Test-only initializer for creating isolated instances in tests
    /// - Parameter timeoutDuration: Initial timeout duration for testing
    internal init(timeoutDuration: TimeInterval = 60.0) {
        self._timeoutDuration = timeoutDuration
    }

    /// Gets the current timeout duration
    /// - Returns: The timeout duration in seconds
    public var timeoutDuration: TimeInterval {
        get { _timeoutDuration }
    }

    /// Sets the timeout duration for network requests
    /// - Parameter duration: The timeout duration in seconds (must be > 0)
    public func setTimeoutDuration(_ duration: TimeInterval) {
        precondition(duration > 0, "Timeout duration must be greater than 0")
        _timeoutDuration = duration
    }

    /// Resets the timeout duration to the default value (60 seconds)
    public func resetTimeoutDuration() {
        _timeoutDuration = 60.0
    }
}