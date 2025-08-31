import Foundation
#if canImport(OSLog)
import OSLog
internal let asyncNetLogger = Logger(subsystem: "com.convenienceinit.asyncnet", category: "network")
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
	
	/// A configured JSONDecoder for consistent decoding across the AsyncNet module.
	/// 
	/// This decoder is configured with:
	/// - `dateDecodingStrategy`: `.iso8601` for standard date handling
	/// - `keyDecodingStrategy`: `.convertFromSnakeCase` for API compatibility
	/// 
	/// Override this property in conforming types to customize decoding behavior.
	var jsonDecoder: JSONDecoder {
		let decoder = JSONDecoder()
		decoder.dateDecodingStrategy = .iso8601
		decoder.keyDecodingStrategy = .convertFromSnakeCase
		return decoder
	}
	
	func sendRequest<ResponseModel>(to endPoint: Endpoint) async throws -> ResponseModel where ResponseModel: Decodable {
		guard var request = try buildAsyncRequest(for: endPoint) else {
			throw NetworkError.invalidEndpoint(reason: "Invalid URL components for endpoint: \(endPoint)")
		}
		let session = URLSession.shared
		if let timeout = endPoint.effectiveTimeout {
			request.timeoutInterval = timeout
		}
		let (data, response) = try await session.data(for: request)
		guard let httpResponse = response as? HTTPURLResponse else {
			throw NetworkError.noResponse
		}
		switch httpResponse.statusCode {
		case 200 ... 299:
			do {
				return try jsonDecoder.decode(ResponseModel.self, from: data)
			} catch {
				throw NetworkError.decodingError(underlyingDescription: error.localizedDescription, data: data)
			}
		case 400:
			throw NetworkError.badRequest(data: data, statusCode: httpResponse.statusCode)
		case 401:
			throw NetworkError.unauthorized
		case 403:
			throw NetworkError.forbidden(data: data, statusCode: httpResponse.statusCode)
		case 404:
			throw NetworkError.notFound(data: data, statusCode: httpResponse.statusCode)
		case 429:
			throw NetworkError.rateLimited(data: data, statusCode: httpResponse.statusCode)
		case 500 ... 599:
			throw NetworkError.serverError(data: data, statusCode: httpResponse.statusCode)
		default:
			throw NetworkError.httpError(statusCode: httpResponse.statusCode, data: data)
		}
	}
	
	/// Builds a URLRequest from the given endpoint.
	///
	/// - Parameter endPoint: The endpoint to build the request for.
	/// - Returns: A configured URLRequest, or nil if the endpoint is invalid.
	/// - Throws: `NetworkError` if the endpoint configuration is invalid.
	private func buildAsyncRequest(for endPoint: Endpoint) throws -> URLRequest? {
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
		asyncRequest.allHTTPHeaderFields = endPoint.resolvedHeaders
		asyncRequest.httpMethod = endPoint.method.rawValue
		if let body = endPoint.body {
			if endPoint.method == .get {
				throw NetworkError.invalidBodyForGET
			} else {
				asyncRequest.httpBody = body
			}
		}
		return asyncRequest
	}
	
	/// Sends an asynchronous network request using AdvancedNetworkManager with enhanced features.
	///
	/// This method provides advanced networking capabilities including request deduplication, intelligent caching,
	/// configurable retry policies with backoff strategies, and request/response interceptors for cross-cutting concerns.
	///
	/// - Parameters:
	///   - endPoint: The endpoint to send the request to, containing URL components, HTTP method, headers, and optional body.
	///   - networkManager: The `AdvancedNetworkManager` instance to use for the request. Supply a custom manager when you need:
	///     - Custom caching behavior (different cache size/expiration)
	///     - Request/response interceptors (logging, authentication, metrics)
	///     - Custom URLSession (for testing or specific networking requirements)
	///     - If not provided, uses default `AdvancedNetworkManager()` with standard caching and no interceptors.
	///   - cacheKey: Optional string key for caching the response. When provided:
	///     - Responses are cached using this key for future identical requests
	///     - Subsequent requests with the same key return cached data instantly
	///     - Useful for frequently accessed data that doesn't change often
	///     - If not provided, uses the request URL as the cache key
	///   - retryPolicy: The retry strategy to use when requests fail. Built-in options:
	///     - `.default`: 3 retries with exponential backoff (recommended for most cases)
	///     - Custom policies can specify max retries, retry conditions, and backoff timing
	///     - Set to `RetryPolicy(maxRetries: 0)` to disable retries entirely
	///
	/// - Returns: The decoded response model of type `ResponseModel`, automatically decoded from JSON.
	///
	/// - Throws:
	///   - `NetworkError.invalidEndpoint` if the endpoint URL cannot be constructed
	///   - `NetworkError.invalidBodyForGET` if attempting to send a body with a GET request
	///   - `NetworkError.decodingError` if the response cannot be decoded to the expected type
	///   - `NetworkError.httpError` for HTTP status codes outside 200-299 range
	///   - `CancellationError` if the request is cancelled
	///   - Other network-related errors from the underlying URLSession
	///
	/// ### Usage Example
	/// ```swift
	/// // Custom network manager with larger cache and logging interceptor
	/// let cache = DefaultNetworkCache(maxSize: 500, expiration: 1800) // 30min expiration
	/// let interceptors: [NetworkInterceptor] = [LoggingInterceptor()]
	/// let manager = AdvancedNetworkManager(cache: cache, interceptors: interceptors)
	///
	/// // Request with custom cache key and retry policy
	/// let user: User = try await service.sendRequestAdvanced(
	///     to: UsersEndpoint(),
	///     networkManager: manager,
	///     cacheKey: "user-profile-\(userId)",
	///     retryPolicy: RetryPolicy(maxRetries: 5, backoff: { attempt in pow(1.5, Double(attempt)) })
	/// )
	/// ```
	///
	/// ### Advanced Features
	/// - **Request Deduplication**: Multiple identical requests return the same result
	/// - **Intelligent Caching**: Automatic cache invalidation and memory management
	/// - **Retry with Backoff**: Exponential backoff prevents server overload
	/// - **Interceptors**: Clean separation of cross-cutting concerns
	func sendRequestAdvanced<ResponseModel>(
		to endPoint: Endpoint,
		networkManager: AdvancedNetworkManager = AdvancedNetworkManager(),
		cacheKey: String? = nil,
		retryPolicy: RetryPolicy = .default
	) async throws -> ResponseModel where ResponseModel: Decodable {
		guard var request = try buildAsyncRequest(for: endPoint) else {
			throw NetworkError.invalidEndpoint(reason: "Invalid URL components for endpoint: \(endPoint)")
		}
		if let timeout = endPoint.effectiveTimeout {
			request.timeoutInterval = timeout
		}
		let data = try await networkManager.fetchData(for: request, cacheKey: cacheKey, retryPolicy: retryPolicy)
		do {
			return try jsonDecoder.decode(ResponseModel.self, from: data)
		} catch {
			throw NetworkError.decodingError(underlyingDescription: error.localizedDescription, data: data)
		}
	}
}

