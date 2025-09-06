import Foundation

/// Protocol for intercepting network requests and responses
/// Allows modification of requests before sending and inspection of responses after receiving
public protocol RequestInterceptor: Sendable {
    /// Called before a request is sent. Can modify the request.
    func willSend(request: URLRequest) async -> URLRequest

    /// Called after a response is received. Can inspect/modify response/data.
    func didReceive(response: URLResponse, data: Data?) async
}
