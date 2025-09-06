import Foundation

// MARK: - Cache Management Extension
extension ImageService {
    // MARK: - Cache Management

    /// Retrieves a cached image for the given key
    /// - Parameter key: The cache key (typically the URL string)
    /// - Returns: The cached image if available
    public func cachedImage(forKey key: String) async -> PlatformImage? {
        let cacheKey = key

        // Check with CacheActor first
        let isValid = await cacheActor.isImageCached(forKey: key)
        if !isValid {
            return nil
        }

        // If valid, retrieve from actual cache
        if let cachedImage = await imageCache.object(forKey: cacheKey) {
            return cachedImage.image
        }

        return nil
    }

    /// Clears all cached images
    public func clearCache() async {
        await imageCache.removeAllObjects()
        await dataCache.removeAllObjects()
        await cacheActor.clearCache()
    }

    /// Stores an image in the cache for the given key
    /// - Parameters:
    ///   - image: The image to cache
    ///   - key: The cache key (typically the URL string)
    ///   - data: Optional image data to cache alongside the image
    public func storeImageInCache(_ image: PlatformImage, forKey key: String, data: Data? = nil) async {
        let cacheKey = key
        await imageCache.setObject(SendableImage(image), forKey: cacheKey)
        if let data = data {
            await dataCache.setObject(SendableData(data), forKey: cacheKey, cost: data.count)
        }
        await cacheActor.storeImageInCache(forKey: key)
    }

    /// Removes a specific image from both the image cache and data cache
    ///
    /// This method removes the cached image and its associated data for the given key from all cache layers,
    /// including the LRU tracking. If the key doesn't exist in the cache, this method silently no-ops.
    ///
    /// - Parameter key: The cache key (typically the URL string) used to identify the cached image to remove.
    ///                  Should be the same key used when storing the image.
    public func removeFromCache(key: String) async {
        let cacheKey = key
        await imageCache.removeObject(forKey: cacheKey)
        await dataCache.removeObject(forKey: cacheKey)
        await cacheActor.removeFromCache(key: key)
    }

    /// Evict expired cache entries based on maxAge using efficient heap-based expiration
    /// The expiration heap allows O(log n) insertions and O(log n) deletions while
    /// efficiently finding and removing expired items regardless of their position in LRU
    internal func evictExpiredCache() async {
        await cacheActor.evictExpiredCache()
    }

    /// Update cache configuration (maxAge, maxLRUCount)
    public func updateCacheConfiguration(_ config: CacheConfiguration) async {
        await cacheActor.updateCacheConfiguration(config)
    }
}
