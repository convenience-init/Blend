import Foundation

/// Shared test utilities for AsyncNet test suite
public enum TestHelpers {
    /// Actor to coordinate continuation resumption and prevent race conditions
    /// between timeout tasks and upload callbacks
    public actor CoordinationActor {
        private var hasResumed = false

        /// Attempts to resume the continuation. Returns true if this call should
        /// actually resume (i.e., it's the first call), false if already resumed.
        public func tryResume() -> Bool {
            if hasResumed {
                return false
            }
            hasResumed = true
            return true
        }
    }
}