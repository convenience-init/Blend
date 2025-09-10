import Foundation
#if canImport(OSLog)
import OSLog
#endif

/// Public logger for internal Blend library diagnostics and debugging.
///
/// This logger is intended primarily for internal diagnostics and debugging, and is **not recommended for production use**.
/// **Privacy Warning:** Do not log sensitive or personally identifiable information (PII) using this logger.
/// Logs may be visible in console output or system logs, depending on platform.
///
/// ### Logging Levels
/// - `debug`: Detailed diagnostic information, intended for development and debugging only.
/// - `info`: General informational messages about network activity.
/// - `warning`: Non-critical issues that may require attention.
/// - `error`: Errors or failures in network operations.
///
/// ### Platform Behavior
/// - On Apple platforms with OSLog support, logs are routed via `OSLog` and may be visible in system logs.
/// - On other platforms, logs are printed to the console.
///
/// ### Production Safety
/// - This logger is **not suitable for production app logging**. For production, use your application's logging system and ensure compliance with privacy requirements.
/// - You may attach custom log handlers to route Blend logs to your own logging infrastructure.
///
/// ### Logger Customization
/// For custom subsystem requirements, create your own logger instance:
/// ```swift
/// // Create custom logger with your own subsystem
/// let customLogger = Logger(subsystem: "com.yourcompany.yourapp.blend", category: "network")
/// // Use customLogger instead of blendLogger
/// ```
///
/// ### Example usage:
/// ```swift
/// // Attach a custom log handler
/// blendLogger.log(level: .debug, "Custom debug message")
///
/// // Or use OSLog's built-in methods
/// blendLogger.info("Network request started")
/// blendLogger.error("Network request failed: \(error)")
/// ```
#if canImport(OSLog)
    /// The Blend logger instance. Uses a generic subsystem to avoid namespace conflicts.
    /// For custom subsystem requirements, create your own Logger instance as shown above.
    public let blendLogger = Logger(subsystem: "blend.network", category: "network")
#else
/// Fallback logger for platforms without OSLog support
public struct BlendLogger {
    public func log(level: String, _ message: String) {
        print("[Blend] [\(level.uppercased())] \(message)")
    }

    public func info(_ message: String) {
        log(level: "info", message)
    }

    public func error(_ message: String) {
        log(level: "error", message)
    }

    public func warning(_ message: String) {
        log(level: "warning", message)
    }

    public func debug(_ message: String) {
        log(level: "debug", message)
    }
}

    /// The Blend logger instance for platforms without OSLog support.
public let blendLogger = BlendLogger()
#endif
