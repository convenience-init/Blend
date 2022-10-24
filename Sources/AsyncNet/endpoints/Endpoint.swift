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
	var header: [String: String]? { get }
	var queryItems: [URLQueryItem]? { get }
	var body: [String: String]? { get }
}

