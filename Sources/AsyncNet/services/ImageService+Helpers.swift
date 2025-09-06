import Foundation

// MARK: - Private Helpers Extension
extension ImageService {
    // MARK: - Private Helpers

    /// Removes an in-flight task from the tracking dictionary
    /// - Parameter key: The URL string key for the task to remove
    internal func removeInFlightTask(forKey key: String) {
        inFlightImageTasks.removeValue(forKey: key)
    }
}
