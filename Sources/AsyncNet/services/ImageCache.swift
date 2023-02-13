#if canImport(UIKit)
import UIKit
#else
import Cocoa
#endif

public final class ImageCache {
	
	typealias Cache = NSCache<NSString, UIImage>
	
	public static let shared = ImageCache()
	
	private init(imageCapacity countLimit: Int = 100, storageLimit totalCostLimit: Int  = (10 * 1024 * 1024)) {
		self.imageCache = Cache()
		self.imageCache.countLimit = countLimit // max number of images in cache, default is 100
		self.imageCache.totalCostLimit = totalCostLimit // max local storage to allocate, default is 10MB
	}
	
	var imageCache: Cache
		
	public func image(forKey key: NSString) -> UIImage? {
		return imageCache.object(forKey: key)
	}
}
