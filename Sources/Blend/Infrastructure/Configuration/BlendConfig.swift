import Foundation

/// Errors that can occur when configuring Blend components
public enum BlendConfigError: Error, LocalizedError, Sendable {
    /// The timeout duration is invalid (not finite or not greater than 0)
    case invalidTimeoutDuration(String)
    /// The maximum upload size is invalid (not greater than 0)
    case invalidMaxUploadSize(String)
    /// The maximum image dimension is invalid
    case invalidMaxImageDimension(String)
    /// The maximum image pixels is invalid
    case invalidMaxImagePixels(String)

    public var errorDescription: String? {
        switch self {
        case .invalidTimeoutDuration(let message):
            return "Invalid timeout duration: \(message)"
        case .invalidMaxUploadSize(let message):
            return "Invalid maximum upload size: \(message)"
        case .invalidMaxImageDimension(let message):
            return "Invalid maximum image dimension: \(message)"
        case .invalidMaxImagePixels(let message):
            return "Invalid maximum image pixels: \(message)"
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .invalidTimeoutDuration:
            return "Provide a finite timeout duration greater than 0 seconds."
        case .invalidMaxUploadSize:
            let minMB = Double(BlendConfig.minUploadSize) / 1024.0 / 1024.0
            let maxMB = Double(BlendConfig.maxUploadSize) / 1024.0 / 1024.0
            return
                "Provide a maximum upload size between \(BlendConfig.minUploadSize) - " +
                "\(BlendConfig.maxUploadSize) bytes (\(minMB) - \(maxMB) MB)."
        case .invalidMaxImageDimension:
            return "Provide a maximum image dimension between 1024 and 32768 pixels."
        case .invalidMaxImagePixels:
            let minMPixels = Double(BlendConfig.minImagePixels) / 1024.0 / 1024.0
            let maxMPixels = Double(BlendConfig.maxImagePixels) / 1024.0 / 1024.0
            return
                "Provide a maximum image pixels between \(BlendConfig.minImagePixels) - " +
                "\(BlendConfig.maxImagePixels) pixels (\(minMPixels) - \(maxMPixels) MP)."
        }
    }
}

/// Thread-safe configuration for Blend networking operations.
///
/// `BlendConfig` provides actor-isolated configuration that can be safely accessed
/// from concurrent contexts without race conditions.
///
/// - Important: Accessing the static shared singleton (`BlendConfig.shared`) is synchronous,
///   but reading instance properties and calling actor-isolated methods require `await`.
///
/// ### Usage Example
/// ```swift
/// // Access the shared singleton (synchronous)
/// let config = BlendConfig.shared
///
/// // Configure timeout duration (requires await and can throw)
/// do {
///     try await BlendConfig.shared.setTimeoutDuration(30.0)
/// } catch {
///     print("Failed to set timeout duration: \(error)")
/// }
///
/// // Read timeout duration (requires await)
/// let timeout = await BlendConfig.shared.timeoutDuration
///
/// // Use in async error wrapping
/// let networkError = await NetworkError.wrapAsync(error, config: BlendConfig.shared)
/// ```
///
/// ### Thread Safety
/// This actor ensures that configuration changes are atomic and visible across all threads.
/// Instance property access and method calls require `await` to maintain isolation, but
/// accessing the shared singleton reference itself is synchronous.
///
/// Enhanced configuration system for Blend networking operations
public actor BlendConfig {
    /// Shared instance for global configuration access
    public static let shared = BlendConfig()

    /// Default timeout duration for network requests (in seconds)
    public static let defaultTimeout: TimeInterval = 60.0

    /// Default maximum upload size for image uploads (in bytes)
    public static let defaultMaxUploadSize: Int = 10 * 1024 * 1024  // 10MB

    /// Minimum allowed upload size (1 KB)
    public static let minUploadSize: Int = 1024  // 1KB

    /// Maximum allowed upload size (100 MB)
    public static let maxUploadSize: Int = 100 * 1024 * 1024  // 100MB

    /// Default maximum image dimension (pixels per side)
    public static let defaultMaxImageDimension: Int = 16384  // 16K pixels

    /// Minimum allowed image dimension (pixels per side)
    public static let minImageDimension: Int = 1024  // 1K pixels

    /// Maximum allowed image dimension (pixels per side)
    public static let maxImageDimension: Int = 32768  // 32K pixels

    /// Default maximum total image pixels
    public static let defaultMaxImagePixels: Int = 100 * 1024 * 1024  // 100M pixels

    /// Minimum allowed total image pixels
    public static let minImagePixels: Int = 1024 * 1024  // 1M pixels

    /// Maximum allowed total image pixels
    public static let maxImagePixels: Int = 400 * 1024 * 1024  // 400M pixels

    /// Default timeout duration for network requests (in seconds)
    private var _timeoutDuration: TimeInterval = BlendConfig.defaultTimeout

    /// Maximum upload size for image uploads (in bytes)
    private var _maxUploadSize: Int = BlendConfig.defaultMaxUploadSize

    /// Initial effective maximum upload size (captures environment override or default)
    private var _initialMaxUploadSize: Int = BlendConfig.defaultMaxUploadSize

    /// Maximum image dimension (pixels per side)
    private var _maxImageDimension: Int = BlendConfig.defaultMaxImageDimension

    /// Initial effective maximum image dimension (captures environment override or default)
    private var _initialMaxImageDimension: Int = BlendConfig.defaultMaxImageDimension

    /// Maximum total image pixels
    private var _maxImagePixels: Int = BlendConfig.defaultMaxImagePixels

    /// Initial effective maximum image pixels (captures environment override or default)
    private var _initialMaxImagePixels: Int = BlendConfig.defaultMaxImagePixels

    /// Private initializer to enforce singleton pattern
    private init() {
        // Initialize maxUploadSize from environment variable if available
        if let envValue = ProcessInfo.processInfo.environment["ASYNC_NET_MAX_UPLOAD_SIZE"] {
            if let size = Int(envValue) {
                if size >= BlendConfig.minUploadSize && size <= BlendConfig.maxUploadSize {
                    _maxUploadSize = size
                } else {
                    // Log warning for out-of-bounds values
                    let minMB = Double(BlendConfig.minUploadSize) / 1024.0 / 1024.0
                    let maxMB = Double(BlendConfig.maxUploadSize) / 1024.0 / 1024.0
                    let providedMB = Double(size) / 1024.0 / 1024.0

                    #if DEBUG
                    print(
                        "Warning: ASYNC_NET_MAX_UPLOAD_SIZE value \(size) bytes (\(providedMB) MB) is out of range. "
                            + "Valid range is \(BlendConfig.minUploadSize) - \(BlendConfig.maxUploadSize) bytes "
                            + "(\(minMB) - \(maxMB) MB). Using default: \(BlendConfig.defaultMaxUploadSize) bytes.")
                    #endif
                }
            } else {
                // Log warning for invalid integer parsing
                #if DEBUG
                print(
                    "Warning: ASYNC_NET_MAX_UPLOAD_SIZE value '\(envValue)' is not a valid integer. "
                        + "Using default: \(BlendConfig.defaultMaxUploadSize) bytes.")
                #endif
            }
        }

        // Capture the initial effective value (environment override or default)
        _initialMaxUploadSize = _maxUploadSize

        // Initialize maxImageDimension from environment variable if available
        if let envValue = ProcessInfo.processInfo.environment["ASYNC_NET_MAX_IMAGE_DIMENSION"] {
            if let dimension = Int(envValue) {
                if dimension >= BlendConfig.minImageDimension && dimension <= BlendConfig.maxImageDimension {
                    _maxImageDimension = dimension
                } else {
                    // Log warning for out-of-bounds values
                    #if DEBUG
                    print(
                        "Warning: ASYNC_NET_MAX_IMAGE_DIMENSION value \(dimension) is out of range. "
                            + "Valid range is \(BlendConfig.minImageDimension) - \(BlendConfig.maxImageDimension) pixels. "
                            + "Using default: \(BlendConfig.defaultMaxImageDimension) pixels.")
                    #endif
                }
            } else {
                // Log warning for invalid integer parsing
                #if DEBUG
                print(
                    "Warning: ASYNC_NET_MAX_IMAGE_DIMENSION value '\(envValue)' is not a valid integer. "
                        + "Using default: \(BlendConfig.defaultMaxImageDimension) pixels.")
                #endif
            }
        }

        // Initialize maxImagePixels from environment variable if available
        if let envValue = ProcessInfo.processInfo.environment["ASYNC_NET_MAX_IMAGE_PIXELS"] {
            if let pixels = Int(envValue) {
                if pixels >= BlendConfig.minImagePixels && pixels <= BlendConfig.maxImagePixels {
                    _maxImagePixels = pixels
                } else {
                    // Log warning for out-of-bounds values
                    let minMPixels = Double(BlendConfig.minImagePixels) / 1024.0 / 1024.0
                    let maxMPixels = Double(BlendConfig.maxImagePixels) / 1024.0 / 1024.0
                    let providedMPixels = Double(pixels) / 1024.0 / 1024.0
                    #if DEBUG
                    print(
                        "Warning: ASYNC_NET_MAX_IMAGE_PIXELS value \(pixels) pixels (\(providedMPixels) MP) is out of range. "
                            + "Valid range is \(BlendConfig.minImagePixels) - \(BlendConfig.maxImagePixels) pixels "
                            + "(\(minMPixels) - \(maxMPixels) MP). Using default: \(BlendConfig.defaultMaxImagePixels) pixels.")
                    #endif
                }
            } else {
                // Log warning for invalid integer parsing
                #if DEBUG
                print(
                    "Warning: ASYNC_NET_MAX_IMAGE_PIXELS value '\(envValue)' is not a valid integer. "
                        + "Using default: \(BlendConfig.defaultMaxImagePixels) pixels.")
                #endif
            }
        }

        // Capture the initial effective values (environment override or default)
        _initialMaxImageDimension = _maxImageDimension
        _initialMaxImagePixels = _maxImagePixels
    }

    /// Test-only initializer for creating isolated instances in tests
    /// - Parameter timeoutDuration: Initial timeout duration for testing
    /// - Note: This initializer is only available during testing to allow for isolated test instances
    #if DEBUG || TESTING
        internal init(timeoutDuration: TimeInterval = BlendConfig.defaultTimeout) {
            self._timeoutDuration = timeoutDuration
            self._maxUploadSize = BlendConfig.defaultMaxUploadSize
            self._initialMaxUploadSize = BlendConfig.defaultMaxUploadSize
            self._maxImageDimension = BlendConfig.defaultMaxImageDimension
            self._initialMaxImageDimension = BlendConfig.defaultMaxImageDimension
            self._maxImagePixels = BlendConfig.defaultMaxImagePixels
            self._initialMaxImagePixels = BlendConfig.defaultMaxImagePixels
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

    /// Gets the current maximum image dimension
    /// - Returns: The maximum image dimension in pixels per side
    public var maxImageDimension: Int {
        _maxImageDimension
    }

    /// Gets the current maximum total image pixels
    /// - Returns: The maximum total image pixels
    public var maxImagePixels: Int {
        _maxImagePixels
    }

    /// Sets the timeout duration for network requests
    /// - Parameter duration: The timeout duration in seconds (must be finite and > 0)
    /// - Throws: BlendConfigError.invalidTimeoutDuration if the duration is invalid
    public func setTimeoutDuration(_ duration: TimeInterval) throws(BlendConfigError) {
        guard duration.isFinite && duration > 0 else {
            throw .invalidTimeoutDuration(
                "Duration must be a finite number greater than 0, got \(duration)")
        }
        _timeoutDuration = duration
    }

    /// Sets the maximum upload size for image uploads
    /// - Parameter size: The maximum upload size in bytes (must be between 1KB and 100MB)
    /// - Throws: BlendConfigError.invalidMaxUploadSize if the size is invalid
    public func setMaxUploadSize(_ size: Int) throws(BlendConfigError) {
        guard size >= BlendConfig.minUploadSize && size <= BlendConfig.maxUploadSize else {
            let minMB = Double(BlendConfig.minUploadSize) / 1024.0 / 1024.0
            let maxMB = Double(BlendConfig.maxUploadSize) / 1024.0 / 1024.0
            let providedMB = Double(size) / 1024.0 / 1024.0
            throw .invalidMaxUploadSize(
                "Size must be between \(BlendConfig.minUploadSize) - \(BlendConfig.maxUploadSize) bytes " +
                "(\(minMB) - \(maxMB) MB), got \(size) bytes (\(providedMB) MB)"
            )
        }
        _maxUploadSize = size
    }

    /// Sets the maximum image dimension
    /// - Parameter dimension: The maximum image dimension in pixels per side (must be between 1K and 32K)
    /// - Throws: BlendConfigError.invalidMaxImageDimension if the dimension is invalid
    public func setMaxImageDimension(_ dimension: Int) throws(BlendConfigError) {
        guard dimension >= BlendConfig.minImageDimension && dimension <= BlendConfig.maxImageDimension else {
            throw .invalidMaxImageDimension(
                "Dimension must be between \(BlendConfig.minImageDimension) - \(BlendConfig.maxImageDimension) pixels, got \(dimension) pixels"
            )
        }
        _maxImageDimension = dimension
    }

    /// Sets the maximum total image pixels
    /// - Parameter pixels: The maximum total image pixels (must be between 1M and 400M)
    /// - Throws: BlendConfigError.invalidMaxImagePixels if the pixels value is invalid
    public func setMaxImagePixels(_ pixels: Int) throws(BlendConfigError) {
        guard pixels >= BlendConfig.minImagePixels && pixels <= BlendConfig.maxImagePixels else {
            let minMPixels = Double(BlendConfig.minImagePixels) / 1024.0 / 1024.0
            let maxMPixels = Double(BlendConfig.maxImagePixels) / 1024.0 / 1024.0
            let providedMPixels = Double(pixels) / 1024.0 / 1024.0
            throw .invalidMaxImagePixels(
                "Pixels must be between \(BlendConfig.minImagePixels) - \(BlendConfig.maxImagePixels) pixels " +
                "(\(minMPixels) - \(maxMPixels) MP), got \(pixels) pixels (\(providedMPixels) MP)"
            )
        }
        _maxImagePixels = pixels
    }

    /// Resets the timeout duration to the configured default (see AsyncNetConfig.defaultTimeout)
    public func resetTimeoutDuration() {
        _timeoutDuration = BlendConfig.defaultTimeout
    }

    /// Resets the maximum upload size to the initial runtime-configured value (preserves environment overrides)
    public func resetMaxUploadSize() {
        _maxUploadSize = _initialMaxUploadSize
    }

    /// Resets the maximum image dimension to the initial runtime-configured value (preserves environment overrides)
    public func resetMaxImageDimension() {
        _maxImageDimension = _initialMaxImageDimension
    }

    /// Resets the maximum image pixels to the initial runtime-configured value (preserves environment overrides)
    public func resetMaxImagePixels() {
        _maxImagePixels = _initialMaxImagePixels
    }
}
