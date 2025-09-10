import Foundation
import Testing

@testable import Blend

@Suite("Cache Actor Tests")
public struct CacheActorTests {

    // MARK: - Cache Actor Tests

    @Test public func testCacheActorBasicOperations() async {
        let cache = Cache<String, SendableData>(countLimit: 3, totalCostLimit: 1000)

        let data1 = SendableData(Data([1, 2, 3]))
        let data2 = SendableData(Data([4, 5, 6]))
        let data3 = SendableData(Data([7, 8, 9]))
        let data4 = SendableData(Data([10, 11, 12]))

        // Add items
        await cache.setObject(data1, forKey: "key1", cost: 1)
        await cache.setObject(data2, forKey: "key2", cost: 1)
        await cache.setObject(data3, forKey: "key3", cost: 1)

        // Access key1 to make it most recently used
        let retrieved1 = await cache.object(forKey: "key1")
        #expect(retrieved1?.data == data1.data)

        // Add key4, should evict key2 (least recently used)
        await cache.setObject(data4, forKey: "key4", cost: 1)

        // key2 should be evicted
        let retrieved2 = await cache.object(forKey: "key2")
        #expect(retrieved2 == nil)

        // Others should still be there
        let retrieved1Again = await cache.object(forKey: "key1")
        let retrieved3 = await cache.object(forKey: "key3")
        let retrieved4 = await cache.object(forKey: "key4")
        #expect(retrieved1Again?.data == data1.data)
        #expect(retrieved3?.data == data3.data)
        #expect(retrieved4?.data == data4.data)
    }

    @Test public func testCacheActorRemoveOperations() async {
        let cache = Cache<String, SendableData>(countLimit: 5, totalCostLimit: 1000)

        // Add multiple items
        for itemIndex in 1...5 {
            let data = SendableData(Data([UInt8(itemIndex)]))
            await cache.setObject(data, forKey: "key\(itemIndex)", cost: 1)
        }

        // Remove middle item
        await cache.removeObject(forKey: "key3")

        // Should be able to add new item without issues
        let data = SendableData(Data([6]))
        await cache.setObject(data, forKey: "key6", cost: 1)

        // Verify structure integrity
        let retrieved1 = await cache.object(forKey: "key1")
        let retrieved2 = await cache.object(forKey: "key2")
        let retrieved3 = await cache.object(forKey: "key3")
        let retrieved4 = await cache.object(forKey: "key4")
        let retrieved5 = await cache.object(forKey: "key5")
        let retrieved6 = await cache.object(forKey: "key6")

        #expect(retrieved1?.data == Data([1]))
        #expect(retrieved2?.data == Data([2]))
        #expect(retrieved3 == nil)  // Should be removed
        #expect(retrieved4?.data == Data([4]))
        #expect(retrieved5?.data == Data([5]))
        #expect(retrieved6?.data == Data([6]))
    }
}
