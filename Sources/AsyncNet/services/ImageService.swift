import Foundation
#if os(iOS)
import UIKit
#endif
#if os(macOS)
import Cocoa
#endif
public final class ImageService {
	
	public static let shared = ImageService()
	
	private init() {
		imageCache = NSCache<NSString, UIImage>()
		imageCache.countLimit = 100 // max number of images
		imageCache.totalCostLimit = 10 * 1024 * 1024 // max 10MB used
	}
	
	private var imageCache: NSCache<NSString, UIImage>
	
	@MainActor public func fetchImage(from endPoint: String) async throws -> UIImage {
		var fetchedImage: UIImage!
		
		guard let url = URL(string: endPoint) else { throw NetworkError.invalidURL("") }
		
		let request = URLRequest(url: url)
		
		let (data, response) = try await URLSession.shared.data(for: request)
		
		guard let response = response as? HTTPURLResponse else { throw NetworkError.decode }
		
		switch response.statusCode {
			case 200 ... 299:
				do {
					guard let mimeType = response.mimeType else {
						throw NetworkError.badMimeType("no mimeType found")
					}
					
					var isValidImage = false
					
					switch mimeType {
						case "image/jpeg":
							isValidImage = true
						case "image/png":
							isValidImage = true
						default:
							isValidImage = false
					}
					
					if !isValidImage {
						throw NetworkError.badMimeType(mimeType)
					}
					
					let image = UIImage(data: data)
					
					if let image = image {
						ImageService.shared.imageCache.setObject(image, forKey: endPoint as NSString)
					}
					if let image = image {
						fetchedImage = image }
				}
				catch { throw NetworkError.decode }
				
			case 401:
				throw NetworkError.unauthorized
				
			default:
				throw NetworkError.unknown
		}
		return fetchedImage
	}
	
	public func image(forKey key: NSString) -> UIImage? {
		return imageCache.object(forKey: key)
	}
}
