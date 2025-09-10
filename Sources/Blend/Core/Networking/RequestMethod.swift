import Foundation

/// HTTP request methods used by Blend. Raw values match wire format per RFC 9110 (HTTP Semantics).
/// This enum is intentionally @frozen for ABI stability and performance. It includes the most commonly
/// used HTTP methods for REST APIs: GET, POST, PUT, DELETE, and PATCH. Additional HTTP methods
/// (HEAD, OPTIONS, TRACE, CONNECT) are not included as they are less commonly used in typical
/// Blend use cases. If additional methods are needed, consider extending the enum in a
/// future major version.
@frozen public enum RequestMethod: String, Sendable {
	case get = "GET"
	case post = "POST"
	case delete = "DELETE"
	case put = "PUT"
	case patch = "PATCH"
}

// MARK: - Case-Insensitive Initialization
extension RequestMethod {
	/// Static locale for case-insensitive string operations
	public static let posixLocale = Locale(identifier: "en_US_POSIX")

	/// Creates a RequestMethod from a case-insensitive string representation
	/// - Parameter raw: The HTTP method string (case-insensitive)
	/// - Returns: The corresponding RequestMethod, or nil if the method is not supported
	@inlinable
	public init?(caseInsensitive raw: String) {
		// Normalize to uppercase for case-insensitive matching
		let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(
			with: Self.posixLocale)
		self.init(rawValue: normalized)
	}
}
