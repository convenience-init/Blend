import Foundation

/// Thread-safe configuration for AsyncNet networking operations.
///
/// `AsyncNetConfig` provides actor-isolated configuration that can be safely accessed
/// from concurrent contexts without race conditions.
///
/// - Important: Accessing the static shared singleton (`AsyncNetConfig.shared`) is synchronous,
///   but reading instance properties and calling actor-isolated methods require `await`.
///
/// ### Usage Example
/// ```swift
/// // Access the shared singleton (synchronous)
/// let config = AsyncNetConfig.shared
///
/// // Configure timeout duration (requires await)
/// await AsyncNetConfig.shared.setTimeoutDuration(30.0)
///
/// // Read timeout duration (requires await)
/// let timeout = await AsyncNetConfig.shared.timeoutDuration
///
/// // Use in async error wrapping
/// let networkError = await NetworkError.wrapAsync(error, config: AsyncNetConfig.shared)
/// ```
///
/// ### Thread Safety
/// This actor ensures that configuration changes are atomic and visible across all threads.
/// Instance property access and method calls require `await` to maintain isolation, but
/// accessing the shared singleton reference itself is synchronous.
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
        _timeoutDuration
    }

    /// Sets the timeout duration for network requests
    /// - Parameter duration: The timeout duration in seconds (must be finite and > 0)
    public func setTimeoutDuration(_ duration: TimeInterval) {
        precondition(
            duration.isFinite && duration > 0,
            "Timeout duration must be a finite number greater than 0")
        _timeoutDuration = duration
    }

    /// Resets the timeout duration to the default value (60 seconds)
    public func resetTimeoutDuration() {
        _timeoutDuration = 60.0
    }
}
