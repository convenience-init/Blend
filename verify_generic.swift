import Foundation

// Test that the generic sendRequest signature works correctly
struct TestModel: Decodable, Equatable {
    let value: Int
}

struct TestEndpoint: Endpoint {
    var scheme: URLScheme = .https
    var host: String = "api.test.com"
    var path: String = "/test"
    var method: RequestMethod = .get
}

// Mock session for testing
class MockURLSession: URLSessionProtocol {
    let nextData: Data
    let nextResponse: URLResponse

    init(nextData: Data, nextResponse: URLResponse) {
        self.nextData = nextData
        self.nextResponse = nextResponse
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        return (nextData, nextResponse)
    }
}

// Test service using the generic signature
struct TestService: AdvancedAsyncRequestable {
    typealias ResponseModel = TestModel
    typealias SecondaryResponseModel = TestModel

    let urlSession: URLSessionProtocol

    func sendRequest<ResponseModel>(to endPoint: Endpoint) async throws -> ResponseModel
    where ResponseModel: Decodable {
        // Build URL
        var components = URLComponents()
        components.scheme = endPoint.scheme.rawValue
        components.host = endPoint.host
        components.path = endPoint.normalizedPath
        guard let url = components.url else {
            throw NSError(domain: "TestError", code: 1, userInfo: nil)
        }

        let request = URLRequest(url: url)
        let (data, response) = try await urlSession.data(for: request)

        if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            throw NSError(domain: "HTTPError", code: httpResponse.statusCode, userInfo: nil)
        }

        return try JSONDecoder().decode(ResponseModel.self, from: data)
    }
}

// Test the functionality
func testGenericSendRequest() async {
    let mockSession = MockURLSession(
        nextData: Data("{\"value\":42}".utf8),
        nextResponse: HTTPURLResponse(
            url: URL(string: "https://api.test.com/test")!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
    )

    let service = TestService(urlSession: mockSession)
    let endpoint = TestEndpoint()

    do {
        // Test fetchList (uses ResponseModel = TestModel)
        let listResult: TestModel = try await service.fetchList(from: endpoint)
        print("✅ fetchList result: \(listResult)")

        // Test fetchDetails (uses SecondaryResponseModel = TestModel)
        let detailResult: TestModel = try await service.fetchDetails(from: endpoint)
        print("✅ fetchDetails result: \(detailResult)")

        // Test direct generic call
        let directResult: TestModel = try await service.sendRequest(to: endpoint)
        print("✅ Direct sendRequest result: \(directResult)")

        print("🎉 All tests passed! Generic sendRequest signature is working correctly.")
    } catch {
        print("❌ Test failed: \(error)")
    }
}

// Run the test
Task {
    await testGenericSendRequest()
}