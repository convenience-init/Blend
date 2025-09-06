import Foundation
#if canImport(OSLog)
import OSLog
#endif

/// Public logger for AsyncNet library consumers to access internal logging.
///
/// This logger can be used to:
/// - Attach custom log handlers for debugging
/// - Route AsyncNet logs to your application's logging system
/// - Monitor network request lifecycle and performance
///
/// Example usage:
/// ```swift
/// // Attach a custom log handler
/// asyncNetLogger.log(level: .debug, "Custom debug message")
///
/// // Or use OSLog's built-in methods
/// asyncNetLogger.info("Network request started")
/// asyncNetLogger.error("Network request failed: \(error)")
/// ```
#if canImport(OSLog)
public let asyncNetLogger = Logger(subsystem: "com.convenienceinit.asyncnet", category: "network")
#endif
