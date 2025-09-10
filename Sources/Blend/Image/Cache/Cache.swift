import Foundation

/// A thread-safe generic cache implementation with LRU eviction and cost-based limits
/// Provides actor-isolated storage with automatic memory management
public actor Cache<Key: Hashable & Sendable, Value: Sendable> {
    private var storage: [Key: CacheEntry] = [:]
    private var _totalCost: Int = 0
    private var insertionOrder: [Key] = []  // Track access order for LRU eviction
    public let countLimit: Int?
    public let totalCostLimit: Int?

    public struct CacheEntry: Sendable {
        let value: Value
        let cost: Int

        init(value: Value, cost: Int = 1) {
            // Validate cost is non-negative
            self.value = value
            self.cost = max(0, cost)
        }
    }

    public init(countLimit: Int? = nil, totalCostLimit: Int? = nil) {
        // Validate limits are non-negative
        self.countLimit = countLimit.map { max(0, $0) }
        self.totalCostLimit = totalCostLimit.map { max(0, $0) }
    }

    /// Get the current count of items
    public var count: Int {
        storage.count
    }

    /// Get the current total cost
    public var totalCost: Int {
        _totalCost
    }

    /// Retrieve an object from the cache
    public func object(forKey key: Key) -> Value? {
        if let entry = storage[key] {
            // Move to most recent position (LRU: recently accessed items are most recent)
            insertionOrder.removeAll { $0 == key }
            insertionOrder.append(key)
            return entry.value
        }
        return nil
    }

    /// Store an object in the cache with limit enforcement
    public func setObject(_ value: Value, forKey key: Key, cost: Int = 1) {
        // Validate cost is non-negative
        let safeCost = max(0, cost)

        let entry = CacheEntry(value: value, cost: safeCost)

        // Remove existing entry if present to update cost
        if let existingEntry = storage[key] {
            _totalCost -= existingEntry.cost
            // Remove from insertion order (will be re-added at end)
            insertionOrder.removeAll { $0 == key }
        }

        // Enforce count limit by removing oldest items if necessary
        if let countLimit = countLimit {
            while storage.count >= countLimit && !storage.isEmpty {
                evictOldestEntry()
            }
        }

        // Enforce cost limit by removing oldest items if necessary
        if let totalCostLimit = totalCostLimit {
            while _totalCost + safeCost > totalCostLimit && !storage.isEmpty {
                evictOldestEntry()
            }
        }

        // Add the new entry
        storage[key] = entry
        _totalCost += safeCost
        insertionOrder.append(key)
    }

    /// Remove an object from the cache
    public func removeObject(forKey key: Key) {
        if let entry = storage.removeValue(forKey: key) {
            _totalCost -= entry.cost
            insertionOrder.removeAll { $0 == key }
        }
    }

    /// Remove all objects from the cache
    public func removeAllObjects() {
        storage.removeAll()
        _totalCost = 0
        insertionOrder.removeAll()
    }

    /// Evict the oldest entry (FIFO eviction)
    private func evictOldestEntry() {
        guard let oldestKey = insertionOrder.first,
            let entry = storage.removeValue(forKey: oldestKey)
        else {
            return
        }
        _totalCost -= entry.cost
        insertionOrder.removeFirst()
    }
}
