import Foundation
import OSLog

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
public let blendLogger = Logger(subsystem: "com.convenienceinit.asyncnet", category: "network")
