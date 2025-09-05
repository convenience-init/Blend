import Foundation
#if canImport(OSLog)
import OSLog
#endif
/// Public logger for AsyncNet library consumers to access internal logging.
///
/// This logger can be used to:
/// - Attach custom log handlers for debugging
/// - Route AsyncNet logs to your application's logging system
/// - Monitor network request lifecycle and performance
///
/// Example usage:
/// ```swift
/// // Attach a custom log handler
/// asyncNetLogger.log(level: .debug, "Custom debug message")
///
/// // Or use OSLog's built-in methods
/// asyncNetLogger.info("Network request started")
/// asyncNetLogger.error("Network request failed: \(error)")
/// ```
#if canImport(OSLog)
public let asyncNetLogger = Logger(subsystem: "com.convenienceinit.asyncnet", category: "network")
#endif
/// A protocol for performing asynchronous network requests with strict Swift 6 concurrency.
///
/// Conform to `AsyncRequestable` to enable generic, type-safe API requests using async/await.
///
/// - Important: All implementations must use Swift 6 concurrency and actor isolation for thread safety.
/// - Note: Use dependency injection for testability and strict concurrency compliance.
///
/// ## Choosing the Right Protocol
///
/// AsyncNet provides two protocols for different service complexity levels:
///
/// ### AsyncRequestable (Basic)
/// **Use when:** Your service only needs a single response type
/// ```swift
/// class SimpleService: AsyncRequestable {
///     typealias ResponseModel = User
///     // Single response type for all operations
/// }
/// ```
///
/// ### AdvancedAsyncRequestable (Enhanced)
/// **Use when:** Your service needs multiple response types for complex patterns
/// ```swift
/// class ComplexService: AdvancedAsyncRequestable {
///     typealias ResponseModel = [UserSummary]     // For lists
///     typealias SecondaryResponseModel = UserDetails // For details
///     // Multiple response types with convenience methods
/// }
/// ```
///
/// ## When to Choose AdvancedAsyncRequestable
/// - **Master-detail patterns** (list view + detail view)
/// - **CRUD operations** with different response types
/// - **Generic service composition** requirements
/// - **Type-safe service hierarchies** with multiple response contracts
/// - **Multi-response services** requiring both primary and secondary data types
///
/// For advanced use cases requiring multiple response types, see `AdvancedAsyncRequestable`.
///
/// ## Design Philosophy: Associated Types for Protocol Composition
///
/// This protocol uses associated types as a workaround for Swift's protocol inheritance limitations.
/// The `ResponseModel` associated type enables powerful protocol composition patterns:
///
/// ### Use Case: Service-Specific Response Types
/// ```swift
/// protocol UserServiceProtocol {
///     associatedtype UserResponse: Decodable
///     associatedtype ProfileResponse: Decodable
///
///     func getUsers() async throws -> UserResponse
///     func getProfile(userId: String) async throws -> ProfileResponse
/// }
///
/// protocol UserService: UserServiceProtocol, AsyncRequestable
/// where UserResponse == APIResponse<[User]>, ProfileResponse == APIResponse<UserProfile> {
///     // Service methods automatically constrained to specific response types
/// }
/// ```
///
/// ### Benefits of This Pattern
/// - **Type Safety**: Services clearly define their response type contracts
/// - **Protocol Composition**: Build complex service hierarchies without direct inheritance
/// - **Breaking Change Avoidance**: Evolve service interfaces without changing implementations
/// - **Testability**: Easy to mock services with specific type constraints
/// - **Documentation**: Self-documenting APIs through associated type names
///
/// ### Usage Example
/// ```swift
/// struct UsersEndpoint: Endpoint {
///     var scheme: URLScheme = .https
///     var host: String = "api.example.com"
///     var path: String = "/users"
///     var method: RequestMethod = .get
/// }
///
/// class UserService: AsyncRequestable {
///     typealias ResponseModel = [User] // Documents the primary response type
///
///     func getUsers() async throws -> [User] {
///         try await sendRequest(to: UsersEndpoint())
///     }
/// }
/// ```
public protocol AsyncRequestable {
	associatedtype ResponseModel: Decodable
	
	func sendRequest<ResponseModel>(
		to endPoint: Endpoint,
		session: URLSessionProtocol
	) async throws -> ResponseModel where ResponseModel: Decodable
	
	var jsonDecoder: JSONDecoder { get }
	
	var networkManager: AdvancedNetworkManager { get }
}

public extension AsyncRequestable {
	/// Default implementation for sending a network request using URLSession.
	///
	/// - Parameters:
	///   - endPoint: The endpoint to send the request to.
	/// - Returns: The decoded response model of the specified type.
	/// - Throws: `NetworkError` if the request fails, decoding fails, or the endpoint is invalid.
	
	/// Default JSONDecoder configuration for AsyncNet.
	/// 
	/// This decoder is configured with:
	/// - `dateDecodingStrategy`: `.iso8601` for standard date handling
	/// - `keyDecodingStrategy`: `.convertFromSnakeCase` for API compatibility
	/// 
	/// Use this as a starting point for custom decoders or inject entirely custom decoders via the jsonDecoder property.
	/// 
	/// ### Example
	/// ```swift
	/// let customDecoder = AsyncRequestable.defaultJSONDecoder
	/// customDecoder.dateDecodingStrategy = .deferredToDate // Customize as needed
	/// ```
	static var defaultJSONDecoder: JSONDecoder {
		let decoder = JSONDecoder()
		decoder.dateDecodingStrategy = .iso8601
		decoder.keyDecodingStrategy = .convertFromSnakeCase
		return decoder
	}
	
	/// Default implementation of jsonDecoder using the standard AsyncNet configuration.
	/// 
	/// Conforming types can override this property to provide custom decoders for testing
	/// or different runtime contexts while maintaining the same interface.
	var jsonDecoder: JSONDecoder {
		Self.defaultJSONDecoder
	}
	
	/// Default implementation of networkManager using the shared instance.
	///
	/// This ensures all services use the same AdvancedNetworkManager instance by default,
	/// providing consistent caching and deduplication behavior across the application.
	/// Override this property to provide custom network managers for testing or specific requirements.
	var networkManager: AdvancedNetworkManager {
		sharedNetworkManager
	}
	
	func sendRequest<ResponseModel>(
		to endPoint: Endpoint,
		session: URLSessionProtocol = URLSession.shared
	) async throws -> ResponseModel
	where ResponseModel: Decodable {
		let request = try buildURLRequest(from: endPoint)
		let (data, response) = try await session.data(for: request)
		guard let httpResponse = response as? HTTPURLResponse else {
			throw NetworkError.noResponse
		}
		switch httpResponse.statusCode {
		case 200 ... 299:
			do {
				return try jsonDecoder.decode(ResponseModel.self, from: data)
			} catch {
				throw NetworkError.decodingError(underlying: error, data: data)
			}
		case 400:
			throw NetworkError.badRequest(data: data, statusCode: httpResponse.statusCode)
		case 401:
			throw NetworkError.unauthorized(data: data, statusCode: httpResponse.statusCode)
		case 403:
			throw NetworkError.forbidden(data: data, statusCode: httpResponse.statusCode)
		case 404:
			throw NetworkError.notFound(data: data, statusCode: httpResponse.statusCode)
		case 429:
			throw NetworkError.rateLimited(data: data, statusCode: httpResponse.statusCode)
		case 500 ... 599:
			throw NetworkError.serverError(statusCode: httpResponse.statusCode, data: data)
		default:
			throw NetworkError.httpError(statusCode: httpResponse.statusCode, data: data)
		}
	}
	
	/// Builds a URLRequest from the given endpoint with proper validation and configuration.
	///
	/// This method centralizes the common request building logic used across different service implementations,
	/// ensuring consistency and reducing code duplication.
	///
	/// - Parameter endPoint: The endpoint to build the request for.
	/// - Returns: A configured URLRequest.
	/// - Throws: `NetworkError.invalidEndpoint` if the endpoint configuration is invalid.
	func buildURLRequest(from endPoint: Endpoint) throws -> URLRequest {
		// Validate GET requests don't have a body
		if endPoint.method == .get && endPoint.body != nil {
			throw NetworkError.invalidEndpoint(
				reason:
					"GET requests must not have a body. Remove the body parameter or use a different HTTP method like POST."
			)
		}
		
		// Build URL from Endpoint properties
		var components = URLComponents()
		components.scheme = endPoint.scheme.rawValue
		components.host = endPoint.host
		components.path = endPoint.normalizedPath
		components.queryItems = endPoint.queryItems
		
		if let port = endPoint.port {
			components.port = port
		}
		
		if let fragment = endPoint.fragment {
			components.fragment = fragment
		}
		
		guard let url = components.url else {
			throw NetworkError.invalidEndpoint(reason: "Invalid endpoint URL")
		}
		
		var request = URLRequest(url: url)
		request.httpMethod = endPoint.method.rawValue
		
		if let resolvedHeaders = endPoint.resolvedHeaders {
			for (key, value) in resolvedHeaders {
				request.setValue(value, forHTTPHeaderField: key)
			}
		}
		
		// Only set httpBody for non-GET methods
		if let body = endPoint.body, endPoint.method != .get {
			request.httpBody = body
		}
		
		// Resolve timeout: timeoutDuration takes precedence over legacy timeout
		if let timeoutDuration = endPoint.timeoutDuration {
			// Convert Duration to TimeInterval (seconds) with full precision
			let components = timeoutDuration.components
			let timeoutSeconds = TimeInterval(components.seconds) + TimeInterval(components.attoseconds) / 1e18
			guard timeoutSeconds > 0 else {
				throw NetworkError.invalidEndpoint(reason: "Timeout duration must be positive")
			}
			request.timeoutInterval = timeoutSeconds
		} else if let legacyTimeout = endPoint.timeout {
			guard legacyTimeout > 0 else {
				throw NetworkError.invalidEndpoint(reason: "Timeout must be positive")
			}
			request.timeoutInterval = legacyTimeout
		}
		
		return request
	}
	
	/// Sends an asynchronous network request using AdvancedNetworkManager with enhanced features.
	///
	/// This method provides advanced networking capabilities including request deduplication, intelligent caching,
	/// configurable retry policies with backoff strategies, and request/response interceptors for cross-cutting concerns.
	///
	/// - Parameters:
	///   - endPoint: The endpoint to send the request to, containing URL components, HTTP method, headers, and optional body.
	///   - cacheKey: Optional string key for caching the response. When provided:
	///     - Responses are cached using this key for future identical requests
	///     - Subsequent requests with the same key return cached data instantly
	///     - Useful for frequently accessed data that doesn't change often
	///     - If not provided, uses the request URL as the cache key
	///   - retryPolicy: The retry strategy to use when requests fail. Built-in options:
	///     - `.default`: 4 total attempts with exponential backoff (recommended for most cases)
	///     - Custom policies can specify max retries, retry conditions, and backoff timing
	///     - Set to `RetryPolicy(maxAttempts: 1)` to disable retries entirely
	///
	/// - Returns: The decoded response model of type `ResponseModel`, automatically decoded from JSON.
	///
	/// - Throws:
	///   - `NetworkError.invalidEndpoint` if the endpoint URL cannot be constructed or if attempting to send a body with a GET request
	///   - `NetworkError.decodingError` if the response cannot be decoded to the expected type
	///   - `NetworkError.httpError` for HTTP status codes outside 200-299 range
	///   - `CancellationError` if the request is cancelled
	///   - Other network-related errors from the underlying URLSession
	///
	/// ### Usage Example
	/// ```swift
	/// // Using default shared network manager
	/// let user: User = try await service.sendRequestAdvanced(
	///     to: UsersEndpoint(),
	///     cacheKey: "user-profile-\(userId)",
	///     retryPolicy: RetryPolicy(maxAttempts: 6, backoff: { attempt in pow(1.5, Double(attempt)) })
	/// )
	///
	/// // Using custom network manager (injected via service property)
	/// class CustomService: AsyncRequestable {
	///     let customManager = AdvancedNetworkManager(
	///         cache: DefaultNetworkCache(maxSize: 500, expiration: 1800),
	///         interceptors: [LoggingInterceptor()]
	///     )
	///
	///     var networkManager: AdvancedNetworkManager {
	///         customManager
	///     }
	/// }
	/// ```
	///
	/// ### Advanced Features
	/// - **Request Deduplication**: Multiple identical requests return the same result
	/// - **Intelligent Caching**: Automatic cache invalidation and memory management
	/// - **Retry with Backoff**: Exponential backoff prevents server overload
	/// - **Interceptors**: Clean separation of cross-cutting concerns
	func sendRequestAdvanced<ResponseModel>(
		to endPoint: Endpoint,
		cacheKey: String? = nil,
		retryPolicy: RetryPolicy = .default
	) async throws -> ResponseModel where ResponseModel: Decodable {
		let request = try buildURLRequest(from: endPoint)
		let data = try await networkManager.fetchData(for: request, cacheKey: cacheKey, retryPolicy: retryPolicy)
		// Note: HTTP response status validation is performed by AdvancedNetworkManager.fetchData
		// which throws appropriate NetworkError instances for non-2xx status codes
		do {
			return try jsonDecoder.decode(ResponseModel.self, from: data)
		} catch {
			throw NetworkError.decodingError(underlying: error, data: data)
		}
	}
}

/// Protocol abstraction for URLSession to enable mocking in tests
public protocol URLSessionProtocol: Sendable {
	func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: URLSessionProtocol {
}

/// Configuration for the shared network cache
private struct NetworkCacheConfig {
	/// Maximum number of cache entries (default: 100)
	let maxSize: Int
	/// Cache expiration time in seconds (default: 600 = 10 minutes)
	let expiration: TimeInterval
	
	/// Initialize from environment variables with validation and defaults
	static func fromEnvironment() -> NetworkCacheConfig {
		let environment = ProcessInfo.processInfo.environment
		
		// Parse maxSize from environment with validation
		let maxSize: Int
		if let maxSizeString = environment["ASYNCNET_CACHE_MAX_SIZE"],
			let parsedSize = Int(maxSizeString),
			parsedSize > 0
		{
			maxSize = parsedSize
		} else {
			maxSize = 100  // Default value
		}
		
		// Parse expiration from environment with validation
		let expiration: TimeInterval
		if let expirationString = environment["ASYNCNET_CACHE_EXPIRATION"],
			let parsedExpiration = TimeInterval(expirationString),
			parsedExpiration > 0
		{
			expiration = parsedExpiration
		} else {
			expiration = 600.0  // Default: 10 minutes
		}
		
		return NetworkCacheConfig(maxSize: maxSize, expiration: expiration)
	}
}

/// Shared AdvancedNetworkManager instance for default usage across all services.
/// This ensures consistent caching and deduplication behavior when no custom manager is provided.
private let sharedNetworkManager: AdvancedNetworkManager = {
	let config = NetworkCacheConfig.fromEnvironment()
	let cache = DefaultNetworkCache(maxSize: config.maxSize, expiration: config.expiration)
	return AdvancedNetworkManager(cache: cache, interceptors: [], urlSession: nil)
}()