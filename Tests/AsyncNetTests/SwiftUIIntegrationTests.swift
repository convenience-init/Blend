import Foundation
import Testing
import SwiftUI
@testable import AsyncNet

/// Actor to coordinate continuation resumption and prevent race conditions
/// between timeout tasks and upload callbacks
private actor CoordinationActor {
    private var hasResumed = false

    /// Attempts to resume the continuation. Returns true if this call should
    /// actually resume (i.e., it's the first call), false if already resumed.
    func tryResume() -> Bool {
        if hasResumed {
            return false
        }
        hasResumed = true
        return true
    }
}

/// MockURLSession for testing concurrent loads with multiple URLs
private actor ConcurrentMockSession: URLSessionProtocol {
    private let imageData: Data
    private let supportedURLs: [URL]
    private var _callCount: Int = 0
    private let artificialDelay: UInt64 = 100_000_000  // 100ms delay for stable timing

    init(imageData: Data, urls: [URL]) {
        self.imageData = imageData
        self.supportedURLs = urls
    }

    /// Thread-safe getter for call count (safe to call after concurrent work completes)
    var callCount: Int {
        _callCount
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        // Thread-safe increment of call count
        _callCount += 1

        // Add artificial delay to simulate network latency
        if artificialDelay > 0 {
            try await Task.sleep(nanoseconds: artificialDelay)
        }

        // Verify the request URL is one of our supported URLs
        guard let requestURL = request.url,
            supportedURLs.contains(where: { $0.absoluteString == requestURL.absoluteString })
        else {
            throw NetworkError.customError(
                "Unsupported URL: \(request.url?.absoluteString ?? "nil")",
                details: nil
            )
        }

        // Create HTTP response for the requested URL
        guard
            let response = HTTPURLResponse(
                url: requestURL,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "image/png"]
            )
        else {
            throw NetworkError.customError(
                "Failed to create HTTPURLResponse for URL: \(requestURL.absoluteString)",
                details: nil
            )
        }

        return (imageData, response)
    }
}

@Suite("SwiftUI Integration Tests")
public struct SwiftUIIntegrationTests {
    // This suite now contains only integration tests that require coordination
    // between multiple components. Individual feature tests have been moved to:
    // - SwiftUIBasicLoadingTests.swift
    // - SwiftUIConcurrentLoadingTests.swift
    // - SwiftUIUploadTests.swift
}
