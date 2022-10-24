import Foundation

public protocol AsyncRequestable {
	associatedtype ResponseModel
	func sendRequest<ResponseModel>(to endPoint: Endpoint) async throws -> ResponseModel where ResponseModel: Decodable
}

public extension AsyncRequestable {
	
	func sendRequest<ResponseModel>(to endPoint: Endpoint) async throws -> ResponseModel where ResponseModel: Decodable {
		
		guard let request = buildAsyncRequest(for: endPoint) else { throw NetworkError.invalidURL("") }
		
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

