import Foundation
import Testing

@testable import AsyncNet

@Suite("AdvancedNetworkManager LRU Cache Tests")
public struct AdvancedNetworkManagerCacheTests {

    @Test public func testAdvancedNetworkManagerLRUBasicOperations() async {
        let cache = DefaultNetworkCache(maxSize: 3, expiration: 3600.0)

        let data1 = Data([1, 2, 3])
        let data2 = Data([4, 5, 6])
        let data3 = Data([7, 8, 9])
        let data4 = Data([10, 11, 12])

        // Add items
        await cache.set(data1, forKey: "key1")
        await cache.set(data2, forKey: "key2")
        await cache.set(data3, forKey: "key3")

        // Access key1 to make it most recently used
        let retrieved1 = await cache.get(forKey: "key1")
        #expect(retrieved1 == data1)

        // Add key4, should evict key2 (least recently used)
        await cache.set(data4, forKey: "key4")

        // key2 should be evicted
        let retrieved2 = await cache.get(forKey: "key2")
        #expect(retrieved2 == nil)

        // Others should still be there
        let retrieved1Again = await cache.get(forKey: "key1")
        let retrieved3 = await cache.get(forKey: "key3")
        let retrieved4 = await cache.get(forKey: "key4")
        #expect(retrieved1Again == data1)
        #expect(retrieved3 == data3)
        #expect(retrieved4 == data4)
    }

    @Test public func testAdvancedNetworkManagerLRUNodeRemoval() async {
        let cache = DefaultNetworkCache(maxSize: 5, expiration: 3600.0)

        // Add multiple items
        for itemIndex in 1...5 {
            let data = Data([UInt8(itemIndex)])
            await cache.set(data, forKey: "key\(itemIndex)")
        }

        // Remove middle item
        await cache.remove(forKey: "key3")

        // Should be able to add new item without issues
        let data = Data([6])
        await cache.set(data, forKey: "key6")

        // Verify structure integrity
        let retrieved1 = await cache.get(forKey: "key1")
        let retrieved2 = await cache.get(forKey: "key2")
        let retrieved3 = await cache.get(forKey: "key3")
        let retrieved4 = await cache.get(forKey: "key4")
        let retrieved5 = await cache.get(forKey: "key5")
        let retrieved6 = await cache.get(forKey: "key6")

        #expect(retrieved1 == Data([1]))
        #expect(retrieved2 == Data([2]))
        #expect(retrieved3 == nil)  // Should be removed
        #expect(retrieved4 == Data([4]))
        #expect(retrieved5 == Data([5]))
        #expect(retrieved6 == Data([6]))
    }

    @Test public func testAdvancedNetworkManagerLRUExpiration() async {
        // Use a very short expiration for testing
        let cache = DefaultNetworkCache(maxSize: 10, expiration: 0.1)

        let data = Data([1, 2, 3])
        await cache.set(data, forKey: "key1")

        // Should be available immediately
        let retrieved = await cache.get(forKey: "key1")
        #expect(retrieved == data)

        // Wait for expiration
        try? await Task.sleep(nanoseconds: 200_000_000)  // 0.2 seconds

        // Should be expired
        let expired = await cache.get(forKey: "key1")
        #expect(expired == nil)
    }

    @Test public func testAdvancedNetworkManagerLRUClear() async {
        let cache = DefaultNetworkCache(maxSize: 5, expiration: 3600.0)

        // Add items
        for itemIndex in 1...3 {
            let data = Data([UInt8(itemIndex)])
            await cache.set(data, forKey: "key\(itemIndex)")
        }

        // Clear cache
        await cache.clear()

        // All items should be gone
        for itemIndex in 1...3 {
            let retrieved = await cache.get(forKey: "key\(itemIndex)")
            #expect(retrieved == nil)
        }
    }

    @Test public func testAdvancedNetworkManagerLRUStressTest() async {
        let cache = DefaultNetworkCache(maxSize: 100, expiration: 3600.0)

        // Add many items
        for itemIndex in 1...50 {  // Reduced count to avoid timeout
            let data = Data([UInt8(itemIndex % 256)])
            await cache.set(data, forKey: "key\(itemIndex)")
        }

        // Random access pattern
        for _ in 1...25 {  // Reduced count
            let randomKey = "key\(Int.random(in: 1...50))"
            _ = await cache.get(forKey: randomKey)
        }

        // Should still work without crashes
        let testData = Data([255])
        await cache.set(testData, forKey: "test")
        let retrieved = await cache.get(forKey: "test")
        #expect(retrieved == testData)
    }

    @Test public func testAdvancedNetworkManagerLRUConcurrentAccess() async {
        let cache = DefaultNetworkCache(maxSize: 50, expiration: 3600.0)

        // Concurrent operations
        await withTaskGroup(of: Void.self) { group in
            for itemIndex in 1...10 {
                group.addTask {
                    let data = Data([UInt8(itemIndex)])
                    await cache.set(data, forKey: "key\(itemIndex)")
                }
            }

            for itemIndex in 1...10 {
                group.addTask {
                    _ = await cache.get(forKey: "key\(itemIndex)")
                }
            }

            for itemIndex in 11...20 {
                group.addTask {
                    let data = Data([UInt8(itemIndex)])
                    await cache.set(data, forKey: "key\(itemIndex)")
                }
            }
        }

        // Should not have crashed and basic operations should work
        let testData = Data([100])
        await cache.set(testData, forKey: "final")
        let retrieved = await cache.get(forKey: "final")
        #expect(retrieved == testData)
    }
}
