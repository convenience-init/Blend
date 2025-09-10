# Error Handling Example

This example demonstrates comprehensive error handling patterns with Blend's `NetworkError` enum and various error scenarios.

## What You'll Learn

- How to handle different types of `NetworkError` cases
- Proper error handling patterns with `do-catch`
- Error recovery strategies
- Custom error types and integration with `NetworkError`
- Platform-specific error handling

## Key Components

### 1. Error Scenarios Demonstrated

- **Network Connectivity**: `NetworkError.networkUnavailable`
- **HTTP Errors**: `NetworkError.httpError(statusCode, data)`
- **Timeout Errors**: `NetworkError.requestTimeout(duration)`
- **Invalid URLs**: `NetworkError.invalidEndpoint(reason)`
- **Authentication**: `NetworkError.unauthorized`
- **JSON Decoding**: `NetworkError.decodingError`
- **Image Processing**: `NetworkError.imageProcessingFailed`
- **Cache Errors**: `NetworkError.cacheError`
- **Transport Errors**: `NetworkError.transportError`

### 2. Error Handling Patterns

#### Basic Error Handling
```swift
do {
    let data = try await service.fetchData()
    print("Success: \(data)")
} catch let error as NetworkError {
    print("Network Error: \(error.message())")
} catch {
    print("Unexpected Error: \(error.localizedDescription)")
}
```

#### Specific Error Cases
```swift
do {
    let result = try await service.makeRequest()
} catch NetworkError.networkUnavailable {
    print("No internet connection")
    // Show offline UI
} catch NetworkError.httpError(let statusCode, _) {
    switch statusCode {
    case 401:
        print("Authentication required")
        // Redirect to login
    case 404:
        print("Resource not found")
        // Show 404 page
    case 500...599:
        print("Server error")
        // Show retry option
    default:
        print("HTTP error: \(statusCode)")
    }
} catch NetworkError.requestTimeout(let duration) {
    print("Request timed out after \(duration) seconds")
    // Offer retry with longer timeout
}
```

#### Error Recovery
```swift
func fetchWithRetry() async throws -> Data {
    do {
        return try await service.fetchData()
    } catch NetworkError.networkUnavailable {
        // Wait for connectivity and retry
        try await Task.sleep(for: .seconds(2))
        return try await service.fetchData()
    } catch NetworkError.httpError(500...599, _) {
        // Retry server errors
        try await Task.sleep(for: .seconds(1))
        return try await service.fetchData()
    }
}
```

## Running the Example

```bash
cd Examples/ErrorHandling
swift run
```

## Expected Output

```
🚀 Blend Error Handling Example
==============================

🧪 Testing Error Scenarios...
==============================

1. Network Unavailable Error
   ❌ Network Error: No internet connection available
   📝 Error Type: networkUnavailable

2. HTTP 404 Error
   ❌ HTTP Error: Resource not found (404)
   📝 Status Code: 404

3. Timeout Error
   ❌ Request timed out after 30.0 seconds
   📝 Timeout Duration: 30.0 seconds

4. Invalid URL Error
   ❌ Invalid endpoint: Invalid URL format
   📝 Reason: Invalid URL format

5. Authentication Error
   ❌ Authentication required (401)
   📝 Error Type: unauthorized

6. JSON Decoding Error
   ❌ Failed to decode response data
   📝 Error Type: decodingError

7. Image Processing Error
   ❌ Failed to process image data
   📝 Error Type: imageProcessingFailed

8. Cache Error
   ❌ Cache operation failed
   📝 Error Type: cacheError

9. Transport Error
   ❌ Network transport error: -1009
   📝 Code: -1009

🔄 Error Recovery Examples
==========================

✅ Recovery from network error after retry
✅ Recovery from server error with backoff

📊 Error Statistics
===================

Total Errors Simulated: 9
Errors Handled: 9
Recovery Attempts: 2
Successful Recoveries: 2

🎉 Error handling demonstration complete!
```

## Error Categories

### Network-Level Errors
- `networkUnavailable`: No internet connection
- `requestTimeout`: Request exceeded time limit
- `transportError`: Low-level network transport failures

### HTTP-Level Errors
- `httpError`: HTTP status codes (400-599)
- `unauthorized`: Authentication failures (401)
- `noResponse`: Server didn't respond

### Data Processing Errors
- `decodingError`: JSON parsing failures
- `invalidEndpoint`: Malformed URLs or endpoints
- `badMimeType`: Unsupported content types

### Image-Specific Errors
- `imageProcessingFailed`: PlatformImage conversion failures
- `uploadFailed`: Image upload failures

### Cache Errors
- `cacheError`: Cache operation failures

## Best Practices Demonstrated

### 1. Specific Error Handling
```swift
catch NetworkError.httpError(let statusCode, let data) {
    // Handle specific HTTP errors
}
```

### 2. Error Recovery
```swift
catch NetworkError.networkUnavailable {
    // Implement retry logic
}
```

### 3. User-Friendly Messages
```swift
print(error.message()) // User-friendly error message
print(error.localizedDescription) // Technical details
```

### 4. Error Logging
```swift
catch let error as NetworkError {
    logger.error("Network error: \(error)")
    // Log additional context
}
```

## Integration with Custom Errors

```swift
enum AppError: Error {
    case network(NetworkError)
    case businessLogic(String)
    case validation(String)
}

func handleAppError(_ error: AppError) {
    switch error {
    case .network(let networkError):
        // Handle network errors
        print("Network: \(networkError.message())")
    case .businessLogic(let message):
        // Handle business logic errors
        print("Business: \(message)")
    case .validation(let message):
        // Handle validation errors
        print("Validation: \(message)")
    }
}
```

## Next Steps

After understanding error handling, check out:
- [Basic Networking](../BasicNetworking/) - Fundamental networking
- [Advanced Networking](../AdvancedNetworking/) - Complex patterns
- [Image Operations](../ImageOperations/) - Image handling
- [SwiftUI Integration](../SwiftUIIntegration/) - UI integration