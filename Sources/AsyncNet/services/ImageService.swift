#if canImport(UIKit)
import UIKit
#else
import Cocoa
#endif

public typealias ImageCache = NSCache<NSString, UIImage>

public final class ImageService {
	
	public static let shared = ImageService()
	
	private init() {
		self.imageCache = ImageCache()
		self.imageCache.countLimit = 100 // max number of images
		self.imageCache.totalCostLimit = 10 * 1024 * 1024 // max 10MB used
	}
	
	public var imageCache: ImageCache
		
	public func image(forKey key: NSString) -> UIImage? {
		return imageCache.object(forKey: key)
	}
}
