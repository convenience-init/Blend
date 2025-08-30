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
///
/// ### Usage Example
/// ```swift
/// struct UsersEndpoint: Endpoint {
///     var scheme: URLScheme = .https
///     var host: String = "api.example.com"
///     var path: String = "/users"
///     var method: RequestMethod = .GET
///     var headers: [String: String]? = ["Authorization": "Bearer token"]
///     var queryItems: [URLQueryItem]? = nil
///     var body: Data? = nil
///     var contentType: String? = "application/json"
///     var timeout: TimeInterval? = 30
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
	var body: Data? { get }
}

