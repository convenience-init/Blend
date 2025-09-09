import Foundation
#if canImport(OSLog)
import OSLog
#endif

/// Public logger for Blend library consumers to access internal logging.
///
/// This logger can be used to:
/// - Attach custom log handlers for debugging
/// - Route Blend logs to your application's logging system
/// - Monitor network request lifecycle and performance
///
/// Example usage:
/// ```swift
/// // Attach a custom log handler
/// blendLogger.log(level: .debug, "Custom debug message")
///
/// // Or use OSLog's built-in methods
/// blendLogger.info("Network request started")
/// blendLogger.error("Network request failed: \(error)")
/// ```
#if canImport(OSLog)
public let blendLogger = Logger(subsystem: "com.convenienceinit.blend", category: "network")
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

public let blendLogger = BlendLogger()
#endif
