/// HTTP request methods used by AsyncNet. Raw values match wire format per RFC 9110 (HTTP Semantics).
public enum RequestMethod: String, Sendable {
	case get = "GET"
	case post = "POST"
	case delete = "DELETE"
	case put = "PUT"
	case patch = "PATCH"
}

// MARK: - Case-Insensitive Initialization
public extension RequestMethod {
	/// Creates a RequestMethod from a case-insensitive string representation
	/// - Parameter raw: The HTTP method string (case-insensitive)
	/// - Returns: The corresponding RequestMethod, or nil if the method is not supported
	init?(caseInsensitive raw: String) {
		// Normalize to uppercase for case-insensitive matching
		let normalized = raw.uppercased()
		self.init(rawValue: normalized)
	}
}

