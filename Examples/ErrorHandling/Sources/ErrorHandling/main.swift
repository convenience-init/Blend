import Blend
import Foundation

struct MainApp {
    static func main() async {
        // MARK: - Mock Services for Error Demonstration

        /// Mock service that simulates various error conditions
        class ErrorSimulationService: AsyncRequestable {
            typealias ResponseModel = String

            let errorCase: NetworkError

            init(errorCase: NetworkError) {
                self.errorCase = errorCase
            }

            func sendRequest<T: Decodable>(_ type: T.Type, to endpoint: Endpoint) async throws -> T
            {
                // Simulate different error conditions by throwing the specified NetworkError
                throw errorCase
            }
        }

        /// Mock service that demonstrates error recovery
        class RecoveryService: AsyncRequestable {
            typealias ResponseModel = String

            private var attemptCount = 0
            let shouldRecover: Bool

            init(shouldRecover: Bool = true) {
                self.shouldRecover = shouldRecover
            }

            func sendRequest<T: Decodable>(_ type: T.Type, to endpoint: Endpoint) async throws -> T
            {
                attemptCount += 1

                if shouldRecover && attemptCount == 1 {
                    // First attempt fails
                    throw NetworkError.networkUnavailable
                }

                // Second attempt succeeds
                return "Success after \(attemptCount) attempts" as! T
            }
        }

        // MARK: - Mock Endpoint

        struct MockEndpoint: Endpoint {
            var scheme: URLScheme = .https
            var host: String = "api.example.com"
            var path: String = "/test"
            var method: RequestMethod = .get
            var headers: [String: String]? = nil
            var queryItems: [URLQueryItem]? = nil
            var contentType: String? = nil
            var timeout: TimeInterval? = nil
            var timeoutDuration: Duration? = .seconds(30)
            var body: Data? = nil
            var port: Int? = nil
            var fragment: String? = nil
        }

        // MARK: - Error Handling Examples

        /// Demonstrates basic error handling patterns
        func demonstrateBasicErrorHandling() async {
            blendLogger.info("Network Unavailable Error")
            let service = ErrorSimulationService(errorCase: .networkUnavailable)

            do {
                let _: String = try await service.sendRequest(String.self, to: MockEndpoint())
                blendLogger.warning("Unexpected success")
            } catch let error as NetworkError {
                blendLogger.error("Network Error: \(error.localizedDescription)")
                blendLogger.info("Error Type: networkUnavailable")
            } catch {
                blendLogger.error("Unexpected Error: \(error.localizedDescription)")
            }
        }

        /// Demonstrates HTTP error handling
        func demonstrateHTTPErrorHandling() async {
            blendLogger.info("HTTP 404 Error")
            let service = ErrorSimulationService(
                errorCase: .notFound(data: "Not Found".data(using: .utf8), statusCode: 404))

            do {
                let _: String = try await service.sendRequest(String.self, to: MockEndpoint())
                blendLogger.warning("Unexpected success")
            } catch NetworkError.notFound(_, _) {
                blendLogger.error("HTTP Error: Resource not found (404)")
                blendLogger.info("Status Code: 404")
            } catch {
                blendLogger.error("Unexpected Error: \(error.localizedDescription)")
            }
        }

        /// Demonstrates timeout error handling
        func demonstrateTimeoutErrorHandling() async {
            blendLogger.info("Timeout Error")
            let service = ErrorSimulationService(errorCase: .requestTimeout(duration: 30.0))

            do {
                let _: String = try await service.sendRequest(String.self, to: MockEndpoint())
                blendLogger.warning("Unexpected success")
            } catch NetworkError.requestTimeout(let duration) {
                blendLogger.error("Request timed out after \(duration) seconds")
                blendLogger.info("Timeout Duration: \(duration) seconds")
            } catch {
                blendLogger.error("Unexpected Error: \(error.localizedDescription)")
            }
        }

        /// Demonstrates invalid endpoint error handling
        func demonstrateInvalidURLErrorHandling() async {
            blendLogger.info("Invalid URL Error")
            let service = ErrorSimulationService(
                errorCase: .invalidEndpoint(reason: "Invalid URL format"))

            do {
                let _: String = try await service.sendRequest(String.self, to: MockEndpoint())
                blendLogger.warning("Unexpected success")
            } catch NetworkError.invalidEndpoint(let reason) {
                blendLogger.error("Invalid endpoint: \(reason)")
                blendLogger.info("Reason: \(reason)")
            } catch {
                blendLogger.error("Unexpected Error: \(error.localizedDescription)")
            }
        }

        /// Demonstrates authentication error handling
        func demonstrateAuthErrorHandling() async {
            blendLogger.info("Authentication Error")
            let service = ErrorSimulationService(
                errorCase: .unauthorized(data: nil, statusCode: 401))

            do {
                let _: String = try await service.sendRequest(String.self, to: MockEndpoint())
                blendLogger.warning("Unexpected success")
            } catch NetworkError.unauthorized(_, _) {
                blendLogger.error("Authentication required (401)")
                blendLogger.info("Error Type: unauthorized")
            } catch {
                blendLogger.error("Unexpected Error: \(error.localizedDescription)")
            }
        }

        /// Demonstrates decoding error handling
        func demonstrateDecodingErrorHandling() async {
            blendLogger.info("JSON Decoding Error")
            let decodingError = NSError(
                domain: "Test", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid JSON format"])
            let service = ErrorSimulationService(
                errorCase: .decodingError(
                    underlying: decodingError, data: "invalid json".data(using: .utf8)))

            do {
                let _: String = try await service.sendRequest(String.self, to: MockEndpoint())
                blendLogger.warning("Unexpected success")
            } catch NetworkError.decodingError(let underlying, _) {
                blendLogger.error("Failed to decode response data")
                blendLogger.info("Error Type: decodingError")
                blendLogger.info("Underlying: \(underlying.localizedDescription)")
            } catch {
                blendLogger.error("Unexpected Error: \(error.localizedDescription)")
            }
        }

        /// Demonstrates image processing error handling
        func demonstrateImageErrorHandling() async {
            blendLogger.info("Image Processing Error")
            let service = ErrorSimulationService(errorCase: .imageProcessingFailed)

            do {
                let _: String = try await service.sendRequest(String.self, to: MockEndpoint())
                blendLogger.warning("Unexpected success")
            } catch NetworkError.imageProcessingFailed {
                blendLogger.error("Failed to process image data")
                blendLogger.info("Error Type: imageProcessingFailed")
            } catch {
                blendLogger.error("Unexpected Error: \(error.localizedDescription)")
            }
        }

        /// Demonstrates cache error handling
        func demonstrateCacheErrorHandling() async {
            blendLogger.info("Cache Error")
            let service = ErrorSimulationService(errorCase: .cacheError("Cache write failed"))

            do {
                let _: String = try await service.sendRequest(String.self, to: MockEndpoint())
                blendLogger.warning("Unexpected success")
            } catch NetworkError.cacheError(let details) {
                blendLogger.error("Cache operation failed")
                blendLogger.info("Error Type: cacheError")
                blendLogger.info("Details: \(details)")
            } catch {
                blendLogger.error("Unexpected Error: \(error.localizedDescription)")
            }
        }

        /// Demonstrates transport error handling
        func demonstrateTransportErrorHandling() async {
            blendLogger.info("Transport Error")
            let urlError = URLError(.notConnectedToInternet)
            let service = ErrorSimulationService(
                errorCase: .transportError(code: .notConnectedToInternet, underlying: urlError))

            do {
                let _: String = try await service.sendRequest(String.self, to: MockEndpoint())
                blendLogger.warning("Unexpected success")
            } catch NetworkError.transportError(let code, _) {
                blendLogger.error("Network transport error: \(code.rawValue)")
                blendLogger.info("Code: \(code.rawValue)")
            } catch {
                blendLogger.error("Unexpected Error: \(error.localizedDescription)")
            }
        }

        /// Demonstrates error recovery patterns
        func demonstrateErrorRecovery() async {
            blendLogger.info("Error Recovery Examples")
            blendLogger.info("=======================")

            // Network error recovery - use same instance for retry
            blendLogger.info("Recovery from network error after retry")
            let networkRecoveryService = RecoveryService(shouldRecover: true)

            do {
                // First attempt should fail
                let _: String = try await networkRecoveryService.sendRequest(
                    String.self, to: MockEndpoint())
                blendLogger.warning("Unexpected success on first attempt")
                // Now try again with same instance
                do {
                    let result: String = try await networkRecoveryService.sendRequest(
                        String.self, to: MockEndpoint())
                    blendLogger.info("Recovery successful: \(result)")
                } catch {
                    blendLogger.error("Recovery failed: \(error.localizedDescription)")
                }
            } catch NetworkError.networkUnavailable {
                blendLogger.info("First attempt failed (expected)")
                // Now try again with same instance
                do {
                    let result: String = try await networkRecoveryService.sendRequest(
                        String.self, to: MockEndpoint())
                    blendLogger.info("Recovery successful: \(result)")
                } catch {
                    blendLogger.error("Recovery failed: \(error.localizedDescription)")
                }
            } catch {
                blendLogger.error("Unexpected error: \(error.localizedDescription)")
            }

            // Server error recovery with backoff
            blendLogger.info("Recovery from server error with backoff")
            let serverRecoveryService = RecoveryService(shouldRecover: true)

            do {
                // First attempt should fail
                let _: String = try await serverRecoveryService.sendRequest(
                    String.self, to: MockEndpoint())
                blendLogger.warning("Unexpected success on first attempt")
                // Simulate backoff delay
                try? await Task.sleep(for: .milliseconds(100))
                // Now try again with same instance
                do {
                    let result: String = try await serverRecoveryService.sendRequest(
                        String.self, to: MockEndpoint())
                    blendLogger.info("Recovery successful: \(result)")
                } catch {
                    blendLogger.error("Recovery failed: \(error.localizedDescription)")
                }
            } catch NetworkError.networkUnavailable {
                blendLogger.info("First attempt failed (expected)")
                // Simulate backoff delay
                try? await Task.sleep(for: .milliseconds(100))
                // Now try again with same instance
                do {
                    let result: String = try await serverRecoveryService.sendRequest(
                        String.self, to: MockEndpoint())
                    blendLogger.info("Recovery successful: \(result)")
                } catch {
                    blendLogger.error("Recovery failed: \(error.localizedDescription)")
                }
            } catch {
                blendLogger.error("Unexpected error: \(error.localizedDescription)")
            }
        }

        /// Comprehensive error handling demonstration
        func demonstrateComprehensiveErrorHandling() async {
            blendLogger.info("Error Statistics")
            blendLogger.info("================")

            var totalErrors = 0
            var handledErrors = 0
            var recoveryAttempts = 0
            var successfulRecoveries = 0

            let errorCases: [NetworkError] = [
                .networkUnavailable,
                .notFound(data: "Not Found".data(using: .utf8), statusCode: 404),
                .requestTimeout(duration: 30.0),
                .invalidEndpoint(reason: "Invalid URL format"),
                .unauthorized(data: nil, statusCode: 401),
                .decodingError(
                    underlying: NSError(
                        domain: "Test", code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "Invalid JSON"]),
                    data: "invalid json".data(using: .utf8)),
                .imageProcessingFailed,
                .cacheError("Cache write failed"),
                .transportError(
                    code: .notConnectedToInternet, underlying: URLError(.notConnectedToInternet)),
            ]

            for errorCase in errorCases {
                totalErrors += 1
                let service = ErrorSimulationService(errorCase: errorCase)

                do {
                    let _: String = try await service.sendRequest(String.self, to: MockEndpoint())
                } catch is NetworkError {
                    handledErrors += 1
                } catch {
                    // This shouldn't happen with our mock service
                    blendLogger.error("Unhandled error: \(error.localizedDescription)")
                }
            }

            // Test recovery scenarios
            let recoveryScenarios = [true, true]  // Two recovery attempts
            for shouldRecover in recoveryScenarios {
                recoveryAttempts += 1
                let service = RecoveryService(shouldRecover: shouldRecover)

                do {
                    let _: String = try await service.sendRequest(String.self, to: MockEndpoint())
                    successfulRecoveries += 1
                } catch {
                    // Recovery failed
                }
            }

            blendLogger.info("Total Errors Simulated: \(totalErrors)")
            blendLogger.info("Errors Handled: \(handledErrors)")
            blendLogger.info("Recovery Attempts: \(recoveryAttempts)")
            blendLogger.info("Successful Recoveries: \(successfulRecoveries)")
        }

        print("Starting Blend Error Handling Example...")
        blendLogger.info("Blend Error Handling Example")
        blendLogger.info("============================")

        blendLogger.info("Testing Error Scenarios...")
        blendLogger.info("============================")

        // Demonstrate different error handling patterns
        await demonstrateBasicErrorHandling()
        await demonstrateHTTPErrorHandling()
        await demonstrateTimeoutErrorHandling()
        await demonstrateInvalidURLErrorHandling()
        await demonstrateAuthErrorHandling()
        await demonstrateDecodingErrorHandling()
        await demonstrateImageErrorHandling()
        await demonstrateCacheErrorHandling()
        await demonstrateTransportErrorHandling()

        // Demonstrate error recovery
        await demonstrateErrorRecovery()

        // Show comprehensive statistics
        await demonstrateComprehensiveErrorHandling()

        blendLogger.info("Error handling demonstration complete!")
        print("Example completed!")
    }
}

// Run the example
await MainApp.main()
