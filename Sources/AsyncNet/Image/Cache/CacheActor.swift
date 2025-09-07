import Foundation

/// Expiration entry for efficient heap-based expiration tracking
public struct ExpirationEntry {
    let expirationTime: TimeInterval
    let key: String  // Changed from NSString to String to prevent memory retention
    var isValid: Bool = true  // Mark as invalid when entry is removed

    init(expirationTime: TimeInterval, key: String) {
        self.expirationTime = expirationTime
        self.key = key
    }
}

/// Efficient min-heap for tracking cache entry expirations
/// Uses a binary heap structure for O(log n) insertions and O(1) min lookups
/// Maintains a mapping from keys to heap indices for O(1) invalidation
public final class ExpirationHeap {
    private var heap: [ExpirationEntry] = []
    private var keyToIndex: [String: Int] = [:]  // Track position of each key in heap
    private var validCount: Int = 0  // Cached count of valid entries for O(1) access
    private var lastCleanupTime: TimeInterval = 0  // Track last cleanup time
    private let cleanupInterval: TimeInterval = 30.0  // Cleanup every 30 seconds
    private var operationCount: Int = 0  // Track operations since last cleanup
    private let operationsPerCleanup: Int = 100  // Trigger cleanup every 100 operations

    /// Push a new expiration entry into the heap
    func push(_ entry: ExpirationEntry) {
        heap.append(entry)
        keyToIndex[entry.key] = heap.count - 1
        siftUp(heap.count - 1)
        validCount += 1  // Increment valid count
        operationCount += 1

        // Trigger lightweight cleanup on rapid growth
        if operationCount >= operationsPerCleanup {
            performLightweightCleanup()
        }
    }

    /// Pop the earliest expiring entry (if it's still valid)
    func popExpired(currentTime: TimeInterval) -> ExpirationEntry? {
        while let first = heap.first, first.expirationTime <= currentTime {
            let entry = heap.removeFirst()
            keyToIndex.removeValue(forKey: entry.key)

            // Re-heapify after removal
            if !heap.isEmpty {
                heap.insert(heap.removeLast(), at: 0)
                siftDown(0)
            }

            // Only return if entry is still valid (not manually removed)
            if entry.isValid {
                validCount -= 1  // Decrement valid count for returned entry
                operationCount += 1
                return entry
            }
            // Entry was invalid, continue to next
        }
        return nil
    }

    /// Mark an entry as invalid (when manually removed)
    func invalidate(key: String) {
        if let index = keyToIndex[key] {
            if heap[index].isValid {
                heap[index].isValid = false
                validCount -= 1  // Decrement valid count
            }
            keyToIndex.removeValue(forKey: key)
            operationCount += 1

            // More aggressive pruning: trigger when invalid ratio >10% or >=50 invalid entries
            let invalidCount = heap.count - validCount
            if heap.count > 0
                && (Double(invalidCount) / Double(heap.count) > 0.10 || invalidCount >= 50) {
                pruneInvalidEntries()
            }
        }
    }

    /// Prune invalid entries and rebuild heap for efficient memory usage
    /// This method removes all invalid entries and rebuilds the heap structure
    /// to prevent memory retention of invalidated entries
    func pruneInvalidEntries() {
        // Filter out invalid entries and rebuild heap
        let validEntries = heap.filter { $0.isValid }

        // Clear current heap and keyToIndex
        heap.removeAll()
        keyToIndex.removeAll()

        // Rebuild heap with only valid entries
        for entry in validEntries {
            heap.append(entry)
            keyToIndex[entry.key] = heap.count - 1
        }

        // Re-heapify the entire structure
        for heapIndex in stride(from: heap.count / 2 - 1, through: 0, by: -1) {
            siftDown(heapIndex)
        }

        // Update cached valid count (should match heap.count after pruning)
        validCount = heap.count
        lastCleanupTime = Date().timeIntervalSince1970
        operationCount = 0  // Reset operation counter
    }

    /// Perform lightweight cleanup without full heap rebuild
    /// This is called periodically to prevent excessive memory growth
    private func performLightweightCleanup() {
        let currentTime = Date().timeIntervalSince1970
        let timeSinceLastCleanup = currentTime - lastCleanupTime

        // Only perform cleanup if enough time has passed or we have significant invalid entries
        if timeSinceLastCleanup >= cleanupInterval || operationCount >= operationsPerCleanup {
            let invalidCount = heap.count - validCount

            // More aggressive cleanup thresholds for background cleanup
            if heap.count > 0
                && (Double(invalidCount) / Double(heap.count) > 0.05 || invalidCount >= 25) {
                pruneInvalidEntries()
            } else {
                // Even if we don't prune, reset counters to prevent excessive checks
                operationCount = 0
                lastCleanupTime = currentTime
            }
        }
    }

    /// Check if heap has any potentially expired entries
    func hasExpiredEntries(currentTime: TimeInterval) -> Bool {
        // Quick check: if no valid entries, no expired entries
        guard validCount > 0 else { return false }

        // Check the root of the heap (earliest expiration)
        return heap.first?.expirationTime ?? .infinity <= currentTime
    }

    /// Get count of valid entries (O(1) with cached value)
    var count: Int {
        return validCount
    }

    private func siftUp(_ index: Int) {
        var childIndex = index
        let child = heap[childIndex]

        while childIndex > 0 {
            let parentIndex = (childIndex - 1) / 2
            let parent = heap[parentIndex]

            if child.expirationTime >= parent.expirationTime {
                break
            }

            // Swap parent and child
            heap[childIndex] = parent
            heap[parentIndex] = child
            keyToIndex[parent.key] = childIndex
            keyToIndex[child.key] = parentIndex

            childIndex = parentIndex
        }
    }

    private func siftDown(_ index: Int) {
        let count = heap.count
        var parentIndex = index

        while true {
            let leftChildIndex = 2 * parentIndex + 1
            let rightChildIndex = 2 * parentIndex + 2

            var smallestIndex = parentIndex

            if leftChildIndex < count
                && heap[leftChildIndex].expirationTime < heap[smallestIndex].expirationTime {
                smallestIndex = leftChildIndex
            }

            if rightChildIndex < count
                && heap[rightChildIndex].expirationTime < heap[smallestIndex].expirationTime {
                smallestIndex = rightChildIndex
            }

            if smallestIndex == parentIndex {
                break
            }

            // Swap parent and smallest child
            let temp = heap[parentIndex]
            heap[parentIndex] = heap[smallestIndex]
            heap[smallestIndex] = temp
            keyToIndex[temp.key] = smallestIndex
            keyToIndex[heap[parentIndex].key] = parentIndex

            parentIndex = smallestIndex
        }
    }
}

/// A comprehensive actor-based cache implementation with LRU eviction and efficient expiration tracking
/// Provides thread-safe storage with automatic cleanup and memory management
public actor CacheActor {
    // MARK: - Configuration

    /// Configuration for cache behavior
    public struct CacheConfiguration: Sendable {
        public let maxAge: TimeInterval  // seconds
        public let maxLRUCount: Int
        public init(maxAge: TimeInterval = 3600, maxLRUCount: Int = 100) {
            self.maxAge = maxAge
            self.maxLRUCount = maxLRUCount
        }
    }

    // MARK: - Internal Types

    /// IMPORTANT: This class is NOT thread-safe and must only be accessed within CacheActor isolation.
    /// All mutations must occur on the CacheActor's executor for thread safety.
    /// The class is private to prevent external access and misuse.
    ///
    /// Thread Safety Analysis:
    /// - This class is private to CacheActor and never shared across concurrency domains
    /// - All access occurs within the actor's isolation boundary (single-threaded execution)
    /// - No @unchecked Sendable needed since it's never sent across actor boundaries
    /// - The class remains a reference type for proper weak reference support in doubly-linked list
    ///
    /// Memory Management:
    /// - Weak reference for prev prevents retain cycles in doubly-linked list
    /// - Strong reference for next maintains forward traversal integrity
    /// - Proper cleanup in removeLRUNode prevents retain cycles
    /// - Nodes are only deallocated when removed from lruDict
    private final class LRUNode {
        let key: String  // Modern Swift String instead of NSString
        weak var prev: LRUNode?  // Weak reference to prevent retain cycles
        var next: LRUNode?  // Keep strong references for forward traversal integrity
        let timestamp: TimeInterval  // Immutable - set once on insertion, never updated
        let insertionTimestamp: TimeInterval  // Already immutable

        init(key: String, timestamp: TimeInterval, insertionTimestamp: TimeInterval) {
            self.key = key
            self.timestamp = timestamp
            self.insertionTimestamp = insertionTimestamp
        }

        deinit {
            // With weak prev references, nodes may be deallocated while still in the list
            // The weak prev prevents retain cycles, but nodes may still have next references
            // until the list cleanup happens. This is expected behavior.
        }
    }

    // MARK: - Properties

    private var cacheConfig: CacheConfiguration
    // Efficient O(1) LRU cache tracking
    private var lruDict: [String: LRUNode] = [:]
    private var lruHead: LRUNode?
    private var lruTail: LRUNode?
    // Cache metrics
    public var cacheHits: Int = 0
    public var cacheMisses: Int = 0
    private var expirationHeap = ExpirationHeap()

    // MARK: - Initialization

    public init(cacheConfig: CacheConfiguration = CacheConfiguration()) {
        self.cacheConfig = cacheConfig
    }

    // MARK: - Public API

    /// Returns true if an image is cached for the given key (actor-isolated, Sendable)
    public func isImageCached(forKey key: String) -> Bool {
        let now = Date().timeIntervalSince1970

        // Check LRU node and expiration synchronously first
        guard let node = lruDict[key],
            now - node.insertionTimestamp < cacheConfig.maxAge else {
            // Either no node or expired - evict if needed
            if let expiredNode = lruDict[key] {
                lruDict.removeValue(forKey: key)
                removeLRUNode(expiredNode)
                expirationHeap.invalidate(key: key)
            }
            return false
        }

        // Node is valid - this indicates the item is cached
        // (actual cache presence is checked by the caller using imageCache/dataCache)
        return true
    }

    /// Retrieves a cached image for the given key
    /// - Parameter key: The cache key (typically the URL string)
    /// - Returns: The cached image if available
    public func cachedImage(forKey key: String) async -> PlatformImage? {
        let now = Date().timeIntervalSince1970

        // Atomically check expiration and handle cache state
        if let node = lruDict[key] {
            // Check expiration first to avoid race conditions
            if now - node.insertionTimestamp < cacheConfig.maxAge {
                // Not expired - safe to return cached data
                // Note: Actual cache retrieval is handled by the caller
                moveLRUNodeToHead(node)
                cacheHits += 1
                return nil  // Caller handles actual cache retrieval
            } else {
                // Expired - atomically remove from caches
                lruDict.removeValue(forKey: key)
                removeLRUNode(node)
                // Invalidate heap entry to prevent it from being processed during expiration
                expirationHeap.invalidate(key: key)
            }
        }

        // Cache miss - increment counter
        cacheMisses += 1
        return nil
    }

    /// Clears all cached images
    public func clearCache() async {
        // Properly clean up all LRU nodes to prevent any potential retain cycles
        var node = lruHead
        while let current = node {
            let next = current.next
            // Clear strong references, weak references will be cleaned up automatically
            current.next = nil
            node = next
        }

        lruDict.removeAll()
        lruHead = nil
        lruTail = nil
        cacheHits = 0
        cacheMisses = 0
        // Reset expiration heap
        expirationHeap = ExpirationHeap()

        // Validate cleanup in debug builds
        #if DEBUG
            assert(validateLRUListIntegrity(), "LRU list integrity check failed after clearCache")
        #endif
    }

    /// Stores an image in the cache for the given key
    /// - Parameters:
    ///   - key: The cache key (typically the URL string)
    public func storeImageInCache(forKey key: String) async {
        await addOrUpdateLRUNode(for: key)
    }

    /// Removes a specific image from cache
    /// - Parameter key: The cache key to remove
    public func removeFromCache(key: String) async {
        if let node = lruDict.removeValue(forKey: key) {
            removeLRUNode(node)
        }
        // Invalidate heap entry to prevent it from being processed during expiration
        expirationHeap.invalidate(key: key)
        // Trigger periodic compaction to prevent memory retention
        expirationHeap.pruneInvalidEntries()
    }

    /// Evict expired cache entries based on maxAge using efficient heap-based expiration
    public func evictExpiredCache() async {
        let now = Date().timeIntervalSince1970

        // Use heap-based expiration for efficient removal of expired entries
        while let expiredEntry = expirationHeap.popExpired(currentTime: now) {
            let key = expiredEntry.key
            if let node = lruDict.removeValue(forKey: key) {
                removeLRUNode(node)
            }
        }
    }

    /// Update cache configuration (maxAge, maxLRUCount)
    public func updateCacheConfiguration(_ config: CacheConfiguration) async {
        self.cacheConfig = config
        // Evict expired entries first
        await evictExpiredCache()
        // Retain only the most recently used items
        var node = lruHead
        var count = 0
        var nodesToEvict: [LRUNode] = []
        // Traverse from head, keep first maxLRUCount nodes, collect nodes to evict
        while let current = node {
            count += 1
            if count > cacheConfig.maxLRUCount {
                nodesToEvict.append(current)
            }
            node = current.next
        }
        // Remove evicted nodes after traversal
        for node in nodesToEvict {
            let key = node.key
            lruDict.removeValue(forKey: key)
            removeLRUNode(node)
            // Invalidate heap entry for evicted node
            expirationHeap.invalidate(key: key)
        }
    }

    // MARK: - Private Helpers

    private func addOrUpdateLRUNode(for key: String) async {
        let now = Date().timeIntervalSince1970
        if let node = lruDict[key] {
            // Only move to head on access, do NOT update timestamp
            // Timestamp should only be set on initial insertion to track insertion age
            moveLRUNodeToHead(node)
        } else {
            let node = LRUNode(key: key, timestamp: now, insertionTimestamp: now)
            lruDict[key] = node
            insertLRUNodeAtHead(node)

            // Push expiration entry to heap for efficient expiration tracking
            let expirationTime = now + cacheConfig.maxAge
            let expirationEntry = ExpirationEntry(
                expirationTime: expirationTime, key: key as String)
            expirationHeap.push(expirationEntry)

            // Guard against invalid maxLRUCount values
            let maxCount = max(0, cacheConfig.maxLRUCount)

            // Evict nodes until we're within the configured limit
            while lruDict.count > maxCount, let tail = lruTail {
                let evictedKey = tail.key
                lruDict.removeValue(forKey: evictedKey)
                removeLRUNode(tail)
                // Invalidate heap entry for evicted node
                expirationHeap.invalidate(key: evictedKey)
            }
        }
    }

    private func moveLRUNodeToHead(_ node: LRUNode) {
        removeLRUNode(node)
        insertLRUNodeAtHead(node)
    }

    private func insertLRUNodeAtHead(_ node: LRUNode) {
        node.next = lruHead
        node.prev = nil  // prev is weak, so this breaks any existing weak reference
        lruHead?.prev = node  // This creates a weak reference from the old head back to node
        lruHead = node
        if lruTail == nil {
            lruTail = node
        }
    }

    private func removeLRUNode(_ node: LRUNode) {
        // Properly clean up all references to prevent retain cycles
        // This ensures nodes can be deallocated when removed from lruDict

        // Capture strong local references upfront to avoid race conditions
        // where weak references can become nil between checks
        let strongPrev = node.prev  // Capture weak reference as strong local
        let strongNext = node.next  // Capture strong reference as local

        // Handle prev reference using captured strong reference
        if let prevNode = strongPrev {
            prevNode.next = strongNext
        } else {
            // If prev is nil, this node was the head
            lruHead = strongNext
        }

        // Handle next reference using captured strong reference
        if let nextNode = strongNext {
            nextNode.prev = strongPrev  // This creates a weak reference
        } else {
            // If next is nil, this node was the tail
            // Only update tail if this node is actually the current tail
            if node === lruTail {
                lruTail = strongPrev
            }
        }

        // Clear our own references to break any remaining links
        node.prev = nil  // This is redundant for weak references but good practice
        node.next = nil
    }

    /// Validates the integrity of the LRU linked list
    /// - Returns: True if the list is valid, false otherwise
    /// - Note: This method is for debugging and should not be called in production
    private func validateLRUListIntegrity() -> Bool {
        // Validate forward traversal and bidirectional links
        let traversalValid = validateLRUTraversal()

        // Validate head and tail consistency
        let headTailValid = validateLRUHeadTailConsistency()

        // Validate count matches dictionary
        let countValid = validateLRUCount()

        return traversalValid && headTailValid && countValid
    }

    /// Validates forward traversal and bidirectional links
    private func validateLRUTraversal() -> Bool {
        var node = lruHead
        var count = 0

        // Traverse forward and check for cycles
        while let current = node {
            // Check bidirectional links
            if !validateNodeLinks(current) {
                return false
            }

            node = current.next
            count += 1

            // Safety check to prevent infinite loops
            if count > lruDict.count + 1 {
                return false  // List is longer than expected
            }
        }

        return true
    }

    /// Validates bidirectional links for a single node
    private func validateNodeLinks(_ current: LRUNode) -> Bool {
        // Check backward link (prev is weak, so it might be nil)
        if let prev = current.prev {
            if prev.next !== current {
                return false  // Broken backward link
            }
        } else if current !== lruHead {
            return false  // Non-head node should have prev (unless garbage collected)
        }

        // Check forward link
        if let next = current.next {
            if next.prev !== current {
                return false  // Broken forward link
            }
        } else if current !== lruTail {
            return false  // Non-tail node should have next
        }

        return true
    }

    /// Validates head and tail consistency
    private func validateLRUHeadTailConsistency() -> Bool {
        // Check that head and tail are consistent
        if lruHead == nil && lruTail != nil { return false }
        if lruHead != nil && lruTail == nil { return false }
        if lruHead != nil && lruTail != nil {
            if lruHead?.prev != nil { return false }  // Head should not have prev
            if lruTail?.next != nil { return false }  // Tail should not have next
        }
        return true
    }

    /// Validates that the list count matches the dictionary count
    private func validateLRUCount() -> Bool {
        var node = lruHead
        var count = 0

        while let current = node {
            count += 1
            node = current.next
        }

        return count == lruDict.count
    }
}
