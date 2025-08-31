/// HTTP request methods used by AsyncNet. Raw values match wire format per RFC 7231.
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
		let uppercased = raw.uppercased()
		switch uppercased {
		case "GET":
			self = .get
		case "POST":
			self = .post
		case "DELETE":
			self = .delete
		case "PUT":
			self = .put
		case "PATCH":
			self = .patch
		default:
			return nil
		}
	}
}

