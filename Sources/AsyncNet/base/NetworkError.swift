
public enum NetworkError: Error {
	case decode
	case offLine
	case unauthorized
	case custom(msg: String?)
	case unknown
	case invalidURL(String)
	case networkError(Error)
	case noResponse
	case decodingError(Error)
	case badStatusCode(String)
	case badMimeType(String)
	
	public func message() -> String {
		switch self {
			case .offLine:
				return "Cannot establish a network connection."
			case .unauthorized:
				return "Not Authorized!"
			case .invalidURL(let message):
				return "invalidURL: \(message)"
			case .networkError(let error):
				return error.localizedDescription
			case .noResponse:
				return "no network response"
			case .decodingError(let error):
				return "decoding error: \(error)"
			case .badStatusCode(let message):
				return "bad status code: \(message)"
			case .badMimeType(let mimeType):
				return "bad mime type: \(mimeType)"
			case let .custom(msg: message):
				return message ?? "Please try again."
			default:
				return "An unknown error occurred."
		}
	}
}
