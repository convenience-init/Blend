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
///               The `headers` property is an exception - it may be mutable during endpoint construction but must be
///               treated as effectively immutable once the endpoint is used for network requests. Thread-safety is
///               ensured through the `Sendable` requirement and value semantics of `[String: String]`.
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
///
/// // For dynamic header construction, use immutable patterns:
/// struct DynamicEndpoint: Endpoint {
///     let scheme: URLScheme
///     let host: String
///     let path: String
///     let method: RequestMethod
///     let headers: [String: String]?  // Immutable after construction
///     let queryItems: [URLQueryItem]?
///     let contentType: String?
///     let timeout: TimeInterval?
///     let timeoutDuration: Duration?
///     let body: Data?
///     let port: Int?
///     let fragment: String?
///
///     init(token: String, additionalHeaders: [String: String] = [:]) {
///         self.scheme = .https
///         self.host = "api.example.com"
///         self.path = "/users"
///         self.method = .get
///         // Build headers immutably during initialization
///         self.headers = ["Authorization": "Bearer \(token)"].merging(additionalHeaders) { $1 }
///         self.queryItems = nil
///         self.contentType = "application/json"
///         self.timeout = nil
///         self.timeoutDuration = .seconds(30)
///         self.body = nil
///         self.port = nil
///         self.fragment = nil
///     }
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

	/// Optional port number for the endpoint URL
	var port: Int? { get }

	/// Optional fragment identifier for the endpoint URL
	var fragment: String? { get }

	@available(*, deprecated, message: "Use `headers`")
	var header: [String: String]? { get }
}

// MARK: - Header Normalization
extension Endpoint {
	@available(*, deprecated, message: "Use `headers`")
	public var header: [String: String]? {
		get { headers }
	}

	/// Returns a normalized headers dictionary that merges `headers` with `contentType`.
	///
	/// This computed property provides a single source of truth for HTTP headers by:
	/// - Starting with all headers from the `headers` property
	/// - Canonicalizing any existing "content-type" key to "Content-Type" (case-insensitive)
	/// - Trimming header keys and values, dropping headers with empty/whitespace-only keys or values
	/// - Rejecting headers containing any ASCII C0 control characters (0x00–0x1F) and DEL (0x7F) to prevent header injection attacks
	/// - Only injecting `contentType` as "Content-Type" if no case-insensitive "content-type" key exists after normalization
	/// - Ensuring consistent casing for the Content-Type header only (other header names retain their original casing)
	///
	/// Use this property in request building instead of manually handling both `headers` and `contentType`.
	public var resolvedHeaders: [String: String]? {
		guard headers != nil || contentType != nil else { return nil }

		let normalizedHeaders = headers ?? [:]

		// First pass: canonicalize all header keys with case-insensitive de-duplication and trim values
		var canonicalizedHeaders: [String: String] = [:]
		var normalizedKeyMap: [String: String] = [:]  // normalized key -> canonical key

		for (key, value) in normalizedHeaders {
			// Trim both key and value (only whitespace, not control characters)
			let trimmedKey = key.trimmingCharacters(in: .whitespaces)
			let trimmedValue = value.trimmingCharacters(in: .whitespaces)

			// Skip headers with empty/whitespace-only keys
			guard !trimmedKey.isEmpty else { continue }

			// Skip headers with empty/whitespace-only values
			guard !trimmedValue.isEmpty else { continue }

			// Create character set for ASCII C0 control characters (0x00–0x1F) and DEL (0x7F)
			let forbiddenCharacters = CharacterSet(charactersIn: "\u{00}"..."\u{1F}").union(
				CharacterSet(charactersIn: "\u{7F}"))

			// Reject headers containing any C0 control characters or DEL (header injection protection)
			guard
				!trimmedKey.contains(where: {
					$0.unicodeScalars.contains(where: { forbiddenCharacters.contains($0) })
				})
					&& !trimmedValue.contains(where: {
						$0.unicodeScalars.contains(where: { forbiddenCharacters.contains($0) })
					})
			else { continue }

			// RFC 9110: Header field names MUST NOT contain ":" (colon) character
			guard !trimmedKey.contains(":") else { continue }

			// Create normalized key for case-insensitive comparison
			let normalizedKey = trimmedKey.lowercased()

			// Determine canonical key: use first-seen casing, but ensure Content-Type is always canonical
			let canonicalKey: String
			if normalizedKey == "content-type" {
				canonicalKey = "Content-Type"
			} else if let existingCanonicalKey = normalizedKeyMap[normalizedKey] {
				canonicalKey = existingCanonicalKey
			} else {
				canonicalKey = trimmedKey
			}

			// Store mapping for future de-duplication
			normalizedKeyMap[normalizedKey] = canonicalKey

			// Set the header value (last value wins for duplicates)
			canonicalizedHeaders[canonicalKey] = trimmedValue
		}

		// Check if any existing header key matches "content-type" case-insensitively after normalization
		let hasContentType = canonicalizedHeaders.keys.contains {
			$0.caseInsensitiveCompare("content-type") == .orderedSame
		}

		// Only add contentType if no existing content-type header exists, contentType is non-nil with non-empty trimmed value,
		// and there's an actual request body present and non-empty, and contentType doesn't contain control characters
		if !hasContentType,
			let contentType = contentType?.trimmingCharacters(in: .whitespaces),
			!contentType.isEmpty,
			let body = body, !body.isEmpty,
			!contentType.unicodeScalars.contains(where: {
				CharacterSet(charactersIn: "\u{00}"..."\u{1F}").union(
					CharacterSet(charactersIn: "\u{7F}")
				).contains($0)
			})
		{
			canonicalizedHeaders["Content-Type"] = contentType
		}

		return canonicalizedHeaders.isEmpty ? nil : canonicalizedHeaders
	}

	/// Returns the effective timeout value, preferring `timeoutDuration` over `timeout` for type safety.
	///
	/// This computed property provides a unified timeout interface that:
	/// - Uses `timeoutDuration` if provided (modern, type-safe Duration API)
	/// - Falls back to `timeout` if `timeoutDuration` is nil (backward compatibility)
	/// - Returns `nil` if both are nil (uses URLSession default)
	/// - Returns `nil` for non-positive timeoutDuration values (uses URLSession default)
	/// - Sanitizes legacy `timeout` values to ignore non-positive values
	///
	/// The Duration is converted to TimeInterval (seconds) for URLRequest compatibility.
	public var effectiveTimeout: TimeInterval? {
		if let timeoutDuration = timeoutDuration {
			let components = timeoutDuration.components
			let seconds =
				TimeInterval(components.seconds) + TimeInterval(components.attoseconds) / 1e18
			return seconds > 0 ? seconds : nil
		}
		if let t = timeout, t > 0 { return t }
		return nil
	}

	/// Returns the path with a leading slash, ensuring consistent URL construction.
	///
	/// This computed property normalizes the path by:
	/// - Adding a leading "/" if the path doesn't already start with one
	/// - Returning the original path if it already starts with "/"
	/// - Preventing subtle URL construction bugs from missing leading slashes
	///
	/// Use this property instead of `path` when building URLs to ensure consistency.
	public var normalizedPath: String {
		path.hasPrefix("/") ? path : "/" + path
	}
}
