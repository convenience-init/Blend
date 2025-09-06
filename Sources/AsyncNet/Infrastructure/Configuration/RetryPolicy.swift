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

// MARK: - Constants

/// Hash multiplier for jitter generation using SplitMix64 algorithm.
/// This constant provides good statistical properties for hash-based randomization.
/// The value is chosen to have high entropy and uniform distribution properties.
private let hashMultiplier: UInt64 = 0x9E37_79B9_7F4A_7C15

// MARK: - Retry Policy
public struct RetryPolicy: Sendable {
    /// Total number of attempts (initial attempt + retries). For example:
    /// - maxAttempts: 1 = 1 total attempt (no retries)
    /// - maxAttempts: 3 = 3 total attempts (1 initial + 2 retries)
    /// - maxAttempts: 5 = 5 total attempts (1 initial + 4 retries)
    public let maxAttempts: Int
    public let shouldRetry: (@Sendable (Error, Int) -> Bool)?
    public let backoff: (@Sendable (Int) -> TimeInterval)?
    public let maxBackoff: TimeInterval
    public let timeoutInterval: TimeInterval
    public let jitterProvider: (@Sendable (Int) -> TimeInterval)?

    public static let `default` = RetryPolicy(
        maxAttempts: 4,  // Total attempts: 1 initial + 3 retries
        shouldRetry: { error, _ in
            // Don't retry HTTP 3xx redirects, 4xx client errors or noResponse errors
            if let networkError = error as? NetworkError {
                switch networkError {
                case .httpError(let statusCode, _):
                    // Don't retry 3xx redirects or 4xx client errors
                    if (300...399).contains(statusCode) || (400...499).contains(statusCode) {
                        return false
                    }
                case .noResponse:
                    // Don't retry when response is not HTTP
                    return false
                default:
                    break
                }
            }
            return true
        },
        backoff: { attempt in
            // Use hash-based jitter for better distribution
            let hash = UInt64(attempt).multipliedFullWidth(by: hashMultiplier).high
            let jitter = Double(hash % 500) / 1000.0  // 0 to 0.5
            return pow(2.0, Double(attempt)) + jitter
        },
        maxBackoff: 60.0,
        timeoutInterval: 30.0
    )

    public init(
        maxAttempts: Int,
        shouldRetry: (@Sendable (Error, Int) -> Bool)? = nil,
        backoff: (@Sendable (Int) -> TimeInterval)? = nil,
        maxBackoff: TimeInterval = 60.0,
        timeoutInterval: TimeInterval = 30.0,
        jitterProvider: (@Sendable (Int) -> TimeInterval)? = nil
    ) {
        self.maxAttempts = maxAttempts
        self.shouldRetry = shouldRetry
        self.backoff = backoff
        self.maxBackoff = maxBackoff
        self.timeoutInterval = timeoutInterval
        self.jitterProvider = jitterProvider
    }

    /// Creates a retry policy with exponential backoff (capped by maxBackoff parameter)
    public static func exponentialBackoff(
        maxAttempts: Int = 4, maxBackoff: TimeInterval = 60.0, timeoutInterval: TimeInterval = 30.0,
        jitterProvider: (@Sendable (Int) -> TimeInterval)? = nil
    ) -> RetryPolicy {
        return RetryPolicy(
            maxAttempts: maxAttempts,
            shouldRetry: { _, _ in true },
            backoff: { attempt in pow(2.0, Double(attempt)) },
            maxBackoff: maxBackoff,
            timeoutInterval: timeoutInterval,
            jitterProvider: jitterProvider
        )
    }

    /// Creates a retry policy with custom backoff strategy
    public static func custom(
        maxAttempts: Int = 4,
        maxBackoff: TimeInterval = 60.0,
        timeoutInterval: TimeInterval = 30.0,
        backoff: @escaping (@Sendable (Int) -> TimeInterval),
        jitterProvider: (@Sendable (Int) -> TimeInterval)? = nil
    ) -> RetryPolicy {
        return RetryPolicy(
            maxAttempts: maxAttempts,
            shouldRetry: { _, _ in true },
            backoff: backoff,
            maxBackoff: maxBackoff,
            timeoutInterval: timeoutInterval,
            jitterProvider: jitterProvider
        )
    }

    /// Creates a retry policy with exponential backoff and custom jitter provider
    public static func exponentialBackoffWithJitter(
        maxAttempts: Int = 4,
        maxBackoff: TimeInterval = 60.0,
        timeoutInterval: TimeInterval = 30.0,
        jitterProvider: @escaping (@Sendable (Int) -> TimeInterval)
    ) -> RetryPolicy {
        return RetryPolicy(
            maxAttempts: maxAttempts,
            shouldRetry: { _, _ in true },
            backoff: { attempt in pow(2.0, Double(attempt)) },
            maxBackoff: maxBackoff,
            timeoutInterval: timeoutInterval,
            jitterProvider: jitterProvider
        )
    }

    /// Creates a retry policy with exponential backoff and seeded RNG for reproducible jitter
    public static func exponentialBackoffWithSeed(
        maxAttempts: Int = 4,
        maxBackoff: TimeInterval = 60.0,
        timeoutInterval: TimeInterval = 30.0,
        seed: UInt64
    ) -> RetryPolicy {
        let jitterProvider: (@Sendable (Int) -> TimeInterval) = { attempt in
            // Use SplitMix64 PRNG for better statistical properties and uniform distribution
            var randomState =
                seed &+ UInt64(attempt).multipliedFullWidth(by: hashMultiplier).high

            // SplitMix64 algorithm - deterministic PRNG with good statistical properties
            randomState = (randomState ^ (randomState >> 30)) &* 0xBF58_476D_1CE4_E5B9
            randomState = (randomState ^ (randomState >> 27)) &* 0x94D0_49BB_1331_11EB
            let randomUInt64 = randomState ^ (randomState >> 31)

            // Scale UInt64 to TimeInterval range [0.0, 0.5)
            return Double(randomUInt64) / Double(UInt64.max) * 0.5
        }

        return RetryPolicy(
            maxAttempts: maxAttempts,
            shouldRetry: { _, _ in true },
            backoff: { attempt in pow(2.0, Double(attempt)) },
            maxBackoff: maxBackoff,
            timeoutInterval: timeoutInterval,
            jitterProvider: jitterProvider
        )
    }
}

// MARK: - Seeded Random Number Generator
/// A seeded random number generator for reproducible jitter in tests
public final class SeededRandomNumberGenerator: RandomNumberGenerator, @unchecked Sendable {
    private var state: UInt64
    private let lock = OSAllocatedUnfairLock()

    public init(seed: UInt64) {
        self.state = seed
    }

    public func next() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        // Simple linear congruential generator for reproducibility
        state = (2_862_933_555_777_941_757 &* state) &+ 3_037_000_493
        return state
    }
}
