import Foundation

public protocol AsyncRequestable {
	associatedtype ResponseModel
	func sendRequest<ResponseModel>(to endPoint: Endpoint) async throws -> ResponseModel where ResponseModel: Decodable
}

public extension AsyncRequestable {
	
	func sendRequest<ResponseModel>(to endPoint: Endpoint) async throws -> ResponseModel where ResponseModel: Decodable {
		guard var request = buildAsyncRequest(for: endPoint) else {
			throw NetworkError.invalidEndpoint(reason: "Invalid URL components for endpoint: \(endPoint)")
		}
		let session = URLSession.shared
		if let timeout = endPoint.timeout {
			request.timeoutInterval = timeout
		}
		let (data, response) = try await session.data(for: request)
		guard let httpResponse = response as? HTTPURLResponse else {
			throw NetworkError.noResponse
		}
		switch httpResponse.statusCode {
		case 200 ... 299:
			do {
				return try JSONDecoder().decode(ResponseModel.self, from: data)
			} catch {
				throw NetworkError.decodingError(underlying: error, data: data)
			}
		case 401:
			throw NetworkError.unauthorized
		default:
			throw NetworkError.httpError(statusCode: httpResponse.statusCode, data: data, request: request)
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
		asyncRequest.allHTTPHeaderFields = endPoint.headers
		asyncRequest.httpMethod = endPoint.method.rawValue
		if let contentType = endPoint.contentType {
			asyncRequest.setValue(contentType, forHTTPHeaderField: "Content-Type")
		}
		if let body = endPoint.body, endPoint.method != .get {
			asyncRequest.httpBody = body
		}
		// Migration: Support legacyBody for backward compatibility
		// WARNING: The following block uses a deprecated property (legacyBody) for migration purposes only.
		// The deprecation warning is expected and safe to ignore until migration is complete.
		// Remove this block and legacyBody property after all clients have migrated to body: Data?
		#if compiler(>=5.6)
		if let legacyBody = endPoint.legacyBody, endPoint.body == nil, endPoint.method != .get {
			asyncRequest.httpBody = try? JSONSerialization.data(withJSONObject: legacyBody, options: [])
		}
		#endif
		return asyncRequest
	}
}

