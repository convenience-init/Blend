import Foundation
#if canImport(OSLog)
import OSLog
private let asyncNetLogger = Logger(subsystem: "com.convenienceinit.asyncnet", category: "network")
#endif
/// A protocol for performing asynchronous network requests with strict Swift 6 concurrency.
///
/// Conform to `AsyncRequestable` to enable generic, type-safe API requests using async/await.
///
/// - Important: All implementations must use Swift 6 concurrency and actor isolation for thread safety.
/// - Note: Use dependency injection for testability and strict concurrency compliance.
///
/// ### Usage Example
/// ```swift
/// struct UsersEndpoint: Endpoint {
///     var scheme: URLScheme = .https
///     var host: String = "api.example.com"
///     var path: String = "/users"
///     var method: RequestMethod = .GET
/// }
///
/// class UserService: AsyncRequestable {
///     func getUsers() async throws -> [User] {
///         try await sendRequest(to: UsersEndpoint())
///     }
/// }
/// ```
///
/// ### Migration Notes
/// - Legacy body support is provided for backward compatibility. Migrate to `body: Data?` for strict compliance.
/// - See `buildAsyncRequest(for:)` for migration details.

public protocol AsyncRequestable {

	/// Sends an asynchronous network request to the specified endpoint and decodes the response.
	///
	/// - Parameters:
	///   - endPoint: The endpoint to send the request to.
	/// - Returns: The decoded response model of type `ResponseModel`.
	/// - Throws: `NetworkError` if the request fails, decoding fails, or the endpoint is invalid.
	///
	/// ### Example
	/// ```swift
	/// let users: [User] = try await sendRequest(to: UsersEndpoint())
	/// ```
	associatedtype ResponseModel
	func sendRequest<ResponseModel>(to endPoint: Endpoint) async throws -> ResponseModel where ResponseModel: Decodable
}

public extension AsyncRequestable {
	/// Default implementation for sending a network request using URLSession.
	///
	/// - Parameters:
	///   - endPoint: The endpoint to send the request to.
	/// - Returns: The decoded response model of type `ResponseModel`.
	/// - Throws: `NetworkError` if the request fails, decoding fails, or the endpoint is invalid.
	
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
				throw NetworkError.decodingError(underlyingDescription: error.localizedDescription, data: data)
			}
		case 401:
			throw NetworkError.unauthorized
		default:
			throw NetworkError.httpError(statusCode: httpResponse.statusCode, data: data)
		}
	}
	
	/// Advanced sendRequest using AdvancedNetworkManager for deduplication, retry, caching, interceptors
	func sendRequestAdvanced<ResponseModel>(
		to endPoint: Endpoint,
		networkManager: AdvancedNetworkManager = AdvancedNetworkManager(),
		cacheKey: String? = nil,
		retryPolicy: RetryPolicy = .default
	) async throws -> ResponseModel where ResponseModel: Decodable {
		guard var request = buildAsyncRequest(for: endPoint) else {
			throw NetworkError.invalidEndpoint(reason: "Invalid URL components for endpoint: \(endPoint)")
		}
		if let timeout = endPoint.timeout {
			request.timeoutInterval = timeout
		}
		let data = try await networkManager.fetchData(for: request, cacheKey: cacheKey, retryPolicy: retryPolicy)
		do {
			return try JSONDecoder().decode(ResponseModel.self, from: data)
		} catch {
			throw NetworkError.decodingError(underlyingDescription: error.localizedDescription, data: data)
		}
	}
}

private extension AsyncRequestable {
	
	/// Builds a URLRequest from the given endpoint.
	///
	/// - Parameter endPoint: The endpoint to build the request for.
	/// - Returns: A configured URLRequest, or nil if the endpoint is invalid.
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
		if let body = endPoint.body {
			if endPoint.method == .get {
				#if DEBUG
				#if canImport(OSLog)
				asyncNetLogger.warning("GET request to \(url.absoluteString, privacy: .public) with non-nil body will be ignored.")
				#else
				print("[AsyncNet] WARNING: GET request to \(url.absoluteString) with non-nil body will be ignored.")
				#endif
				#endif
				// Ensure no misleading Content-Type header is sent without a body.
				asyncRequest.setValue(nil, forHTTPHeaderField: "Content-Type")
			} else {
				asyncRequest.httpBody = body
			}
		}
		return asyncRequest
	}
}

