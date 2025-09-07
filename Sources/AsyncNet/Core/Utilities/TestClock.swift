import Foundation
import os

#if canImport(OSLog)
    import OSLog
#endif

#if canImport(CryptoKit)
    import CryptoKit
#endif

#if canImport(CommonCrypto)
    import CommonCrypto
#endif

// MARK: - Test Clock for Deterministic Testing
/// TestClock provides a controllable clock for deterministic testing.
/// All accesses to the internal time state are synchronized to prevent data races.
///
/// Design Decision: Uses OSAllocatedUnfairLock instead of actor-based isolation
/// - Performance: Extremely lightweight for simple property access (no suspension overhead)
/// - API Stability: Synchronous methods avoid breaking changes in test code
/// - Testing Context: Precision timing is critical for cache expiration tests
/// - Platform Requirements: Requires macOS 13.0+/iOS 16.0+ (acceptable for test infrastructure)
/// - Alternative Considered: Actor isolation would add unnecessary async complexity
///   and performance overhead for this synchronous, high-frequency use case
public final class TestClock: @unchecked Sendable {
    private var _now: ContinuousClock.Instant
    private let lock = OSAllocatedUnfairLock()

    public init() {
        _now = ContinuousClock().now
    }

    /// Returns the current time value in a thread-safe manner
    public func now() -> ContinuousClock.Instant {
        lock.lock()
        defer { lock.unlock() }
        return _now
    }

    /// Advances the clock by the specified duration in a thread-safe manner
    public func advance(by duration: Duration) {
        lock.lock()
        defer { lock.unlock() }
        _now = _now.advanced(by: duration)
    }
}
