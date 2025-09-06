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

@Suite("SwiftUI Integration Tests")
public struct SwiftUIIntegrationTests {
    // This suite now contains only integration tests that require coordination
    // between multiple components. Individual feature tests have been moved to:
    // - SwiftUIBasicLoadingTests.swift
    // - SwiftUIConcurrentLoadingTests.swift
    // - SwiftUIUploadTests.swift
}
