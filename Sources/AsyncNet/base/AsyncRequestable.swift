import UIKit

public protocol AsyncRequestable {
	associatedtype ResponseModel
	
	func sendRequest<ResponseModel>(to endPoint: Endpoint) async throws -> ResponseModel where ResponseModel: Decodable
}

public extension AsyncRequestable {
	
	var imageService: ImageService { return ImageService.shared }
	
	@MainActor func fetchImage(from endPoint: String) async throws -> UIImage {
		
		var fetchedImage: UIImage!
				
		guard let url = URL(string: endPoint) else {
			throw NetworkError.invalidURL("\(endPoint)")
		}
		
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
	
}

public extension AsyncRequestable {
	
	func sendRequest<ResponseModel>(to endPoint: Endpoint) async throws -> ResponseModel where ResponseModel: Decodable {
		
		guard let request = buildAsyncRequest(for: endPoint) else { throw NetworkError.invalidURL("\(endPoint.host + endPoint.path)") }
		
		let (data, response) = try await URLSession.shared.data(for: request)
		
		guard let response = response as? HTTPURLResponse else { throw NetworkError.decode }
		
		switch response.statusCode {
			case 200 ... 299:
				do {
					return try JSONDecoder().decode(ResponseModel.self, from: data)
				}
				catch { throw NetworkError.decode }
			case 401:
				throw NetworkError.unauthorized
			default:
				throw NetworkError.unknown
		}
	}
}

private extension AsyncRequestable {
	
	private func buildAsyncRequest(for endPoint: Endpoint) -> URLRequest? {
		
		var components = URLComponents()
		components.scheme = endPoint.scheme.rawValue
		components.host = endPoint.host
		components.path = endPoint.path
		if let queryItems = endPoint.queryItems {
			components.queryItems = queryItems
		}
		
		guard let url = components.url else {
			return nil
		}
		
		var asyncRequest = URLRequest(url: url)
		asyncRequest.allHTTPHeaderFields = endPoint.header
		asyncRequest.httpMethod = endPoint.method.rawValue
		if let body = endPoint.body, endPoint.method != .get {
			asyncRequest.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [])
		}
		return asyncRequest
	}
}

