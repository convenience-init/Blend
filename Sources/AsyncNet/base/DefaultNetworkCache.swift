import Foundation

// MARK: - Default Network Cache Implementation
public actor DefaultNetworkCache: NetworkCache {
    // LRU Node for doubly-linked list
    private final class Node {
        let key: String
        var data: Data
        weak var prev: Node?  // Weak reference to prevent retain cycles
        var next: Node?  // Strong reference for forward traversal integrity
        var timestamp: ContinuousClock.Instant

        init(key: String, data: Data, timestamp: ContinuousClock.Instant) {
            self.key = key
            self.data = data
            self.timestamp = timestamp
        }

        deinit {
            // With weak prev references, nodes may be deallocated while still in the list
            // The weak prev prevents retain cycles, but nodes may still have next references
            // until the list cleanup happens. This is expected behavior.
        }
    }

    private var cache: [String: Node] = [:]
    private var head: Node?
    private var tail: Node?
    private let maxSize: Int
    private let expiration: Duration

    // Time provider for testing - can be overridden
    private let timeProvider: () -> ContinuousClock.Instant

    public init(
        maxSize: Int = 100,
        expiration: TimeInterval = 600
    ) {
        self.maxSize = maxSize
        self.expiration = .seconds(expiration)
        self.timeProvider = { ContinuousClock().now }
    }

    // Test-only initializer
    internal init(
        maxSize: Int = 100,
        expiration: TimeInterval = 600,
        timeProvider: @escaping () -> ContinuousClock.Instant
    ) {
        self.maxSize = maxSize
        self.expiration = .seconds(expiration)
        self.timeProvider = timeProvider
    }

    public func get(forKey key: String) async -> Data? {
        guard let node = cache[key] else {
            return nil
        }

        let now = timeProvider()
        // Check if entry has expired
        if now - node.timestamp >= expiration {
            // Remove expired entry
            removeNode(node)
            cache.removeValue(forKey: key)
            return nil
        }

        // Move accessed node to head (most recently used)
        moveToHead(node)
        return node.data
    }

    public func set(_ data: Data, forKey key: String) async {
        let now = timeProvider()

        if let existingNode = cache[key] {
            // Update existing node with new timestamp
            existingNode.data = data
            existingNode.timestamp = now
            moveToHead(existingNode)
            return
        }

        // Perform lightweight cleanup of expired items before adding new entry
        await performLightweightCleanup()

        // If at max capacity, evict LRU entry before adding new one
        if cache.count >= maxSize {
            removeTail()
        }

        // Create new node with current timestamp
        let newNode = Node(key: key, data: data, timestamp: now)
        cache[key] = newNode

        // Add to head of list
        addToHead(newNode)
    }

    public func remove(forKey key: String) async {
        guard let node = cache[key] else { return }
        removeNode(node)
        cache.removeValue(forKey: key)
    }

    public func clear() async {
        cache.removeAll()
        head = nil
        tail = nil
    }

    /// Performs a comprehensive cleanup of expired entries
    /// This method traverses the entire cache and can be called periodically
    /// or when you want to ensure all expired entries are removed
    public func cleanupExpiredEntries() async {
        let now = timeProvider()
        var nodesToRemove: [Node] = []

        // Collect expired nodes
        for (_, node) in cache {
            if now - node.timestamp >= expiration {
                nodesToRemove.append(node)
            }
        }

        // Remove expired nodes
        for node in nodesToRemove {
            removeNode(node)
            cache.removeValue(forKey: node.key)
        }
    }

    // MARK: - LRU Helper Methods

    private func addToHead(_ node: Node) {
        node.next = head
        node.prev = nil

        if let headNode = head {
            headNode.prev = node
        } else {
            tail = node
        }

        head = node
    }

    private func moveToHead(_ node: Node) {
        // If already head, no need to move
        if node === head {
            return
        }

        // Remove from current position
        removeNode(node)

        // Add to head
        addToHead(node)
    }

    private func removeNode(_ node: Node) {
        // Capture strong local references upfront to avoid race conditions
        // where weak references can become nil between checks
        let strongPrev = node.prev  // Capture weak reference as strong local
        let strongNext = node.next  // Capture strong reference as local
        let currentTail = tail  // Capture current tail reference

        // Handle prev reference using captured strong reference
        if let prevNode = strongPrev {
            prevNode.next = strongNext
        } else {
            // Node is head
            head = strongNext
        }

        // Handle next reference using captured strong reference
        if let nextNode = strongNext {
            nextNode.prev = strongPrev  // This creates a weak reference
        } else {
            // Node is tail - update tail to the captured previous node
            if node === currentTail {
                tail = strongPrev
            }
        }

        // Clear references to prevent any remaining links
        node.prev = nil
        node.next = nil
    }

    private func removeTail() {
        guard let tailNode = tail else { return }

        // Capture strong reference to prev before it might become nil
        let strongPrev = tailNode.prev

        if let prevNode = strongPrev {
            prevNode.next = nil
            tail = prevNode
        } else {
            // Only one node in list
            head = nil
            tail = nil
        }

        cache.removeValue(forKey: tailNode.key)
    }

    private func performLightweightCleanup() async {
        let now = timeProvider()
        var nodesToRemove: [Node] = []
        let initialCount = cache.count  // Capture stable count before cleanup
        let cleanupLimit = max(1, min(10, initialCount / 4))  // Check up to 25% or 10 entries, minimum 1
        var checked = 0

        // Start from tail and work backwards, checking for expired entries
        var current = tail
        while let node = current, checked < cleanupLimit {
            if now - node.timestamp >= expiration {
                nodesToRemove.append(node)
            }
            current = node.prev
            checked += 1
        }

        // Remove expired nodes
        for node in nodesToRemove {
            removeNode(node)
            cache.removeValue(forKey: node.key)
        }
    }
}
