import Foundation

/// Represents the URL scheme for an endpoint.
///
/// - Note: This enum covers only HTTP and HTTPS schemes for standard web API requests.
///         Use `.https` for secure requests. All production endpoints should prefer HTTPS.
///         WebSocket schemes (ws/wss) are not supported by this enum and would require
///         a separate implementation with different connection and messaging semantics.
public enum URLScheme: String, Sendable {
	case http
	case https
}

/// A protocol defining the structure of a network endpoint for use with AsyncNet.
///
/// Conform to `Endpoint` to specify all necessary components for a network request, including scheme, host, path, method, headers, query items, and body.
///
/// - Important: All properties must be thread-safe and immutable for strict Swift 6 concurrency compliance.
/// - Note: Use `body: Data?` for request payloads.
/// - Note: The `path` property must start with "/" (e.g., "/users", "/api/v1/posts").
///         Callers are responsible for supplying the leading slash.
/// - Note: The `timeout` property is specified in seconds as a `TimeInterval`.
///         When `nil`, the default timeout provided by the underlying URLSession will be used.
/// - Note: The `timeoutDuration` property provides a modern, type-safe Duration API.
///         When provided, it takes precedence over `timeout` for better type safety.
/// - Note: Use `resolvedHeaders` for the normalized, merged view of headers that properly handles
///         Content-Type precedence and prevents case-insensitive header collisions.
///
/// ### Usage Example
/// ```swift
/// struct UsersEndpoint: Endpoint {
///     var scheme: URLScheme = .https
///     var host: String = "api.example.com"
///     var path: String = "/users"  // Must start with "/"
///     var method: RequestMethod = .get  // Use lowercase enum cases
///     var headers: [String: String]? = ["Authorization": "Bearer token"]
///     var queryItems: [URLQueryItem]? = nil
///     var body: Data? = nil
///     var contentType: String? = "application/json"  // Only used if no Content-Type in headers
///     
///     // Modern Duration-based timeout (preferred):
///     var timeoutDuration: Duration? = .seconds(30)
///     
///     // Legacy TimeInterval timeout (for backward compatibility):
///     var timeout: TimeInterval? = nil  // Not used when timeoutDuration is provided
///     
///     // Use resolvedHeaders for normalized header handling:
///     // var allHeaders = resolvedHeaders  // Merges headers + contentType safely
/// }
/// ```
public protocol Endpoint: Sendable {
	var scheme: URLScheme { get }
	var host: String { get }
	var path: String { get }
	var method: RequestMethod { get }
	var headers: [String: String]? { get }
	var queryItems: [URLQueryItem]? { get }
	var contentType: String? { get }
	var timeout: TimeInterval? { get }
	var timeoutDuration: Duration? { get }
	var body: Data? { get }
}

// MARK: - Header Normalization
public extension Endpoint {
	/// Returns a normalized headers dictionary that merges `headers` with `contentType`.
	///
	/// This computed property provides a single source of truth for HTTP headers by:
	/// - Starting with all headers from the `headers` property
	/// - Only injecting `contentType` as "Content-Type" if no case-insensitive "content-type" key exists
	/// - Ensuring consistent header name casing for HTTP compliance
	///
	/// Use this property in request building instead of manually handling both `headers` and `contentType`.
	var resolvedHeaders: [String: String]? {
		guard headers != nil || contentType != nil else { return nil }
		
		var normalizedHeaders = headers ?? [:]
		
		// Check if any existing header key matches "content-type" case-insensitively
		let hasContentType = normalizedHeaders.keys.contains { $0.caseInsensitiveCompare("content-type") == .orderedSame }
		
		// Only add contentType if no existing content-type header exists
		if !hasContentType, let contentType = contentType {
			normalizedHeaders["Content-Type"] = contentType
		}
		
		return normalizedHeaders.isEmpty ? nil : normalizedHeaders
	}
	
	/// Returns the effective timeout value, preferring `timeoutDuration` over `timeout` for type safety.
	///
	/// This computed property provides a unified timeout interface that:
	/// - Uses `timeoutDuration` if provided (modern, type-safe Duration API)
	/// - Falls back to `timeout` if `timeoutDuration` is nil (backward compatibility)
	/// - Returns `nil` if both are nil (uses URLSession default)
	///
	/// The Duration is converted to TimeInterval (seconds) for URLRequest compatibility.
	var effectiveTimeout: TimeInterval? {
		if let timeoutDuration = timeoutDuration {
			return timeoutDuration / .seconds(1)
		}
		return timeout
	}
}

