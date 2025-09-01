import Foundation

/// Errors that can occur when configuring AsyncNet components
public enum AsyncNetConfigError: Error, LocalizedError, Sendable {
    /// The timeout duration is invalid (not finite or not greater than 0)
    case invalidTimeoutDuration(String)
    /// The maximum upload size is invalid (not greater than 0)
    case invalidMaxUploadSize(String)

    public var errorDescription: String? {
        switch self {
        case .invalidTimeoutDuration(let message):
            return "Invalid timeout duration: \(message)"
        case .invalidMaxUploadSize(let message):
            return "Invalid maximum upload size: \(message)"
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .invalidTimeoutDuration:
            return "Provide a finite timeout duration greater than 0 seconds."
        case .invalidMaxUploadSize:
            return "Provide a maximum upload size greater than 0 bytes."
        }
    }
}

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
/// // Configure timeout duration (requires await and can throw)
/// do {
///     try await AsyncNetConfig.shared.setTimeoutDuration(30.0)
/// } catch {
///     print("Failed to set timeout duration: \(error)")
/// }
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
    public static let defaultTimeout: TimeInterval = 60.0

    /// Default maximum upload size for image uploads (in bytes)
    public static let defaultMaxUploadSize: Int = 10 * 1024 * 1024  // 10MB

    /// Default timeout duration for network requests (in seconds)
    private var _timeoutDuration: TimeInterval = AsyncNetConfig.defaultTimeout

    /// Maximum upload size for image uploads (in bytes)
    private var _maxUploadSize: Int = AsyncNetConfig.defaultMaxUploadSize

    /// Private initializer to enforce singleton pattern
    private init() {
        // Initialize maxUploadSize from environment variable if available
        if let envValue = ProcessInfo.processInfo.environment["ASYNC_NET_MAX_UPLOAD_SIZE"],
            let size = Int(envValue), size > 0
        {
            _maxUploadSize = size
        }
    }

    /// Test-only initializer for creating isolated instances in tests
    /// - Parameter timeoutDuration: Initial timeout duration for testing
    /// - Note: This initializer is only available during testing to allow for isolated test instances
    #if DEBUG || TESTING
        internal init(timeoutDuration: TimeInterval = AsyncNetConfig.defaultTimeout) {
            self._timeoutDuration = timeoutDuration
        }
    #endif

    /// Gets the current timeout duration
    /// - Returns: The timeout duration in seconds
    public var timeoutDuration: TimeInterval {
        _timeoutDuration
    }

    /// Gets the current maximum upload size
    /// - Returns: The maximum upload size in bytes
    public var maxUploadSize: Int {
        _maxUploadSize
    }

    /// Sets the timeout duration for network requests
    /// - Parameter duration: The timeout duration in seconds (must be finite and > 0)
    /// - Throws: AsyncNetConfigError.invalidTimeoutDuration if the duration is invalid
    public func setTimeoutDuration(_ duration: TimeInterval) throws(AsyncNetConfigError) {
        guard duration.isFinite && duration > 0 else {
            throw .invalidTimeoutDuration(
                "Duration must be a finite number greater than 0, got \(duration)")
        }
        _timeoutDuration = duration
    }

    /// Sets the maximum upload size for image uploads
    /// - Parameter size: The maximum upload size in bytes (must be > 0)
    /// - Throws: AsyncNetConfigError.invalidMaxUploadSize if the size is invalid
    public func setMaxUploadSize(_ size: Int) throws(AsyncNetConfigError) {
        guard size > 0 else {
            throw .invalidMaxUploadSize(
                "Size must be greater than 0, got \(size)")
        }
        _maxUploadSize = size
    }

    /// Resets the timeout duration to the configured default (see AsyncNetConfig.defaultTimeout)
    public func resetTimeoutDuration() {
        _timeoutDuration = AsyncNetConfig.defaultTimeout
    }

    /// Resets the maximum upload size to the configured default (see AsyncNetConfig.defaultMaxUploadSize)
    public func resetMaxUploadSize() {
        _maxUploadSize = AsyncNetConfig.defaultMaxUploadSize
    }
}
