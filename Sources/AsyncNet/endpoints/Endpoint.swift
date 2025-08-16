import Foundation

public enum URLScheme: String {
	case http
	case https
}

public protocol Endpoint {
	var scheme: URLScheme { get }
	var host: String { get }
	var path: String { get }
	var method: RequestMethod { get }
	var headers: [String: String]? { get }
	var queryItems: [URLQueryItem]? { get }
	var body: Data? { get }
	var contentType: String? { get }
	var timeout: TimeInterval? { get }
	// Deprecated: For migration only
	@available(*, deprecated, message: "Use body: Data? instead")
	var legacyBody: [String: String]? { get }
}

