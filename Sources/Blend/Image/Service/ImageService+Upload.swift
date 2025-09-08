import Foundation

extension ImageService {
    /// Calculates the size of data after base64 encoding
    ///
    /// Base64 encoding converts 3 bytes of input data into 4 bytes of output.
    /// The formula `((rawSize + 2) / 3) * 4` ensures proper handling of:
    /// - **Integer division**: `(rawSize + 2) / 3` rounds up to account for partial groups
    /// - **Padding**: The +2 ensures we don't truncate when rawSize isn't divisible by 3
    /// - **4:3 ratio**: Base64 encodes every 3 input bytes as 4 output bytes
    ///
    /// Examples:
    /// - 0 bytes → 0 bytes (empty input)
    /// - 1 byte → 4 bytes (1 group of 4, with padding)
    /// - 2 bytes → 4 bytes (1 group of 4, with padding)
    /// - 3 bytes → 4 bytes (1 complete group)
    /// - 4 bytes → 8 bytes (1 group + 1 partial group)
    ///
    /// - Parameter rawSize: The size of the raw data in bytes
    /// - Returns: The size of the data after base64 encoding
    private func calculateBase64EncodedSize(_ rawSize: Int) -> Int {
        // Prevent integer overflow for very large input sizes
        // Base64 encoding converts 3 bytes to 4 bytes, so max safe input is (Int.max / 4) * 3
        // Use overflow-safe arithmetic to prevent crashes on edge cases
        let (maxSafeRawSize, overflow) = (Int.max / 4).multipliedReportingOverflow(by: 3)
        guard !overflow, rawSize <= maxSafeRawSize else { return Int.max }
        return ((rawSize + 2) / 3) * 4
    }

    /// Uploads image data as a JSON payload with a base64-encoded image field
    /// - Parameters:
    ///   - imageData: The image data to upload
    ///   - url: The upload endpoint URL
    ///   - configuration: Upload configuration options
    ///   - onProgress: Optional progress callback (0.0 to 1.0)
    /// - Returns: The response data from the server
    /// - Throws: NetworkError if the upload fails
    public func uploadImageBase64(
        _ imageData: Data,
        to url: URL,
        configuration: UploadConfiguration = UploadConfiguration(),
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> Data {
        // Start progress at 0.0
        onProgress?(0.0)

        // Pre-check to avoid memory issues with very large images
        let maxSafeRawSize = await calculateMaxSafeRawSize()
        try validateImageSize(imageData.count, maxSafeRawSize)

        // Progress: validation complete
        onProgress?(0.1)

        // Check upload size limit (validate post-encoding size since base64 increases size ~33%)
        let effectiveMaxUploadSize = await getEffectiveMaxUploadSize()
        let encodedSize = calculateBase64EncodedSize(imageData.count)
        try validateEncodedSize(encodedSize, effectiveMaxUploadSize, imageData.count)

        // Progress: size validation complete
        onProgress?(0.2)

        // Determine upload strategy based on encoded size
        let result = try await selectUploadStrategy(
            imageData: imageData,
            url: url,
            configuration: configuration,
            encodedSize: encodedSize,
            onProgress: onProgress
        )

        // Progress: upload complete
        onProgress?(1.0)

        return result
    }

    /// Calculates the maximum safe raw image size for base64 uploads
    private func calculateMaxSafeRawSize() async -> Int {
        let configMaxUploadSize: Int
        if let instanceMaxUploadSize = maxUploadSize {
            configMaxUploadSize = instanceMaxUploadSize
        } else {
            configMaxUploadSize = await AsyncNetConfig.shared.maxUploadSize
        }

        if configMaxUploadSize > 0 {
            // Base64 encoding increases size by ~33%, so raw limit = configMax * 3/4
            let calculatedRawLimit = Int(Double(configMaxUploadSize) * 3.0 / 4.0)
            return max(calculatedRawLimit, 50 * 1024 * 1024)  // Ensure minimum 50MB fallback
        } else {
            // Fallback to original 50MB default if config is invalid
            return 50 * 1024 * 1024
        }
    }

    /// Gets the effective maximum upload size from configuration
    private func getEffectiveMaxUploadSize() async -> Int {
        if let instanceMaxUploadSize = maxUploadSize {
            return instanceMaxUploadSize
        } else {
            return await AsyncNetConfig.shared.maxUploadSize
        }
    }

    /// Validates the raw image size against limits
    private func validateImageSize(_ imageSize: Int, _ maxSafeRawSize: Int) throws {
        if imageSize > maxSafeRawSize {
            #if canImport(OSLog)
                #if DEBUG
                    blendLogger.warning(
                        """
                        Upload rejected: Image size \(imageSize, privacy: .public) bytes \
                        exceeds raw size limit of \(maxSafeRawSize, privacy: .public) bytes
                        """
                    )
                #else
                    blendLogger.warning(
                        """
                        Upload rejected: Image size \(imageSize, privacy: .private) bytes \
                        exceeds raw size limit of \(maxSafeRawSize, privacy: .private) bytes
                        """
                    )
                #endif
            #else
                print(
                    "Upload rejected: Image size \(imageSize) bytes "
                        + "exceeds raw size limit of \(maxSafeRawSize) bytes"
                )
            #endif
            throw NetworkError.payloadTooLarge(size: imageSize, limit: maxSafeRawSize)
        }
    }

    /// Validates the encoded size against limits
    private func validateEncodedSize(_ encodedSize: Int, _ maxUploadSize: Int, _ rawSize: Int)
        throws
    {
        if encodedSize > maxUploadSize {
            #if canImport(OSLog)
                #if DEBUG
                    let message =
                        "Upload rejected: Base64-encoded image size \(encodedSize) bytes "
                        + "exceeds limit of \(maxUploadSize) bytes "
                        + "(raw size: \(rawSize) bytes)"
                    blendLogger.warning("\(message, privacy: .public)")
                #else
                    let message =
                        "Upload rejected: Base64-encoded image size \(encodedSize) bytes "
                        + "exceeds limit of \(maxUploadSize) bytes "
                        + "(raw size: \(rawSize) bytes)"
                    blendLogger.warning("\(message, privacy: .private)")
                #endif
            #else
                print(
                    "Upload rejected: Base64-encoded image size \(encodedSize) bytes "
                        + "exceeds limit of \(maxUploadSize) bytes "
                        + "(raw size: \(rawSize) bytes)"
                )
            #endif
            throw NetworkError.payloadTooLarge(size: encodedSize, limit: maxUploadSize)
        }
    }

    /// Selects the appropriate upload strategy based on size
    private func selectUploadStrategy(
        imageData: Data,
        url: URL,
        configuration: UploadConfiguration,
        encodedSize: Int,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> Data {
        if encodedSize <= configuration.streamThreshold {
            // Use JSON + base64 for smaller images (existing path)
            return try await uploadImageBase64Small(
                imageData, to: url, configuration: configuration, onProgress: onProgress)
        } else {
            // Use streaming multipart for larger images to avoid memory spikes
            return try await uploadImageBase64Streaming(
                imageData, to: url, configuration: configuration, onProgress: onProgress)
        }
    }

    /// Upload small images using JSON payload with base64 encoding
    private func uploadImageBase64Small(
        _ imageData: Data,
        to url: URL,
        configuration: UploadConfiguration,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> Data {
        // Progress: starting encoding
        onProgress?(0.3)
        
        let base64String = imageData.base64EncodedString()
        
        // Progress: encoding complete
        onProgress?(0.4)
        
        let payload = UploadPayload(
            fieldName: configuration.fieldName,
            fileName: configuration.fileName,
            compressionQuality: configuration.compressionQuality,
            base64Data: base64String,
            additionalFields: configuration.additionalFields
        )

        let jsonPayload = try JSONEncoder().encode(payload)
        try await validateUploadSize(jsonPayload.count, imageData.count)
        
        // Progress: payload prepared
        onProgress?(0.5)

        let request = try await createUploadRequest(
            url: url, body: jsonPayload, contentType: "application/json")
            
        // Progress: request prepared, starting upload
        onProgress?(0.6)

        let (data, response) = try await urlSession.data(for: request)

        // Apply response interceptors
        let interceptors = self.interceptors
        for interceptor in interceptors {
            await interceptor.didReceive(response: response, data: data)
        }
        
        // Progress: upload complete, validating response
        onProgress?(0.9)

        return try validateUploadResponse(data: data, response: response)
    }

    /// Validates upload payload size against limits
    private func validateUploadSize(_ payloadSize: Int, _ imageSize: Int) async throws {
        let effectiveMaxUploadSize: Int
        if let instanceMaxUploadSize = maxUploadSize {
            effectiveMaxUploadSize = instanceMaxUploadSize
        } else {
            effectiveMaxUploadSize = await AsyncNetConfig.shared.maxUploadSize
        }

        if payloadSize > effectiveMaxUploadSize {
            #if DEBUG
                let message =
                    "Upload rejected: JSON payload size \(payloadSize) bytes "
                    + "exceeds limit of \(effectiveMaxUploadSize) bytes "
                    + "(base64 image: \(imageSize) bytes, "
                    + "encoded: \(calculateBase64EncodedSize(imageSize)) bytes)"
                blendLogger.warning("\(message, privacy: .public)")
            #else
                let message =
                    "Upload rejected: JSON payload size \(payloadSize) bytes "
                    + "exceeds limit of \(effectiveMaxUploadSize) bytes "
                    + "(base64 image: \(imageSize) bytes, "
                    + "encoded: \(calculateBase64EncodedSize(imageSize)) bytes)"
                blendLogger.warning("\(message, privacy: .private)")
            #endif
            throw NetworkError.payloadTooLarge(size: payloadSize, limit: effectiveMaxUploadSize)
        }

        // Warn if payload is large
        let maxRecommendedSize = (effectiveMaxUploadSize * 3) / 4
        if payloadSize > maxRecommendedSize {
            #if DEBUG
                let message =
                    "Warning: Large JSON payload (\(payloadSize) bytes, "
                    + "base64 image: \(imageSize) bytes) approaches upload limit. "
                    + "Consider using multipart upload."
                blendLogger.info("\(message, privacy: .public)")
            #else
                let message =
                    "Warning: Large JSON payload (\(payloadSize) bytes, "
                    + "base64 image: \(imageSize) bytes) approaches upload limit. "
                    + "Consider using multipart upload."
                blendLogger.info("\(message, privacy: .private)")
            #endif
        }
    }

    /// Creates upload request with interceptors applied
    private func createUploadRequest(url: URL, body: Data, contentType: String) async throws
        -> URLRequest
    {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        // Apply request interceptors
        let interceptors = self.interceptors
        for interceptor in interceptors {
            request = await interceptor.willSend(request: request)
        }

        return request
    }

    /// Validates upload response and returns data or throws error
    private func validateUploadResponse(data: Data, response: URLResponse) throws -> Data {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.noResponse
        }

        switch httpResponse.statusCode {
        case 200...299:
            return data
        case 400:
            throw NetworkError.badRequest(data: data, statusCode: httpResponse.statusCode)
        case 401:
            throw NetworkError.unauthorized(data: data, statusCode: httpResponse.statusCode)
        case 403:
            throw NetworkError.forbidden(data: data, statusCode: httpResponse.statusCode)
        case 404:
            throw NetworkError.notFound(data: data, statusCode: httpResponse.statusCode)
        case 429:
            throw NetworkError.rateLimited(data: data, statusCode: httpResponse.statusCode)
        case 500...599:
            throw NetworkError.serverError(statusCode: httpResponse.statusCode, data: data)
        default:
            throw NetworkError.httpError(statusCode: httpResponse.statusCode, data: data)
        }
    }

    /// Upload large images using streaming multipart/form-data to avoid memory spikes
    private func uploadImageBase64Streaming(
        _ imageData: Data,
        to url: URL,
        configuration: UploadConfiguration,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> Data {
        // Progress: starting streaming upload
        onProgress?(0.3)
        
        // Log that we're using streaming upload for large images
        let encodedSize = calculateBase64EncodedSize(imageData.count)
        #if canImport(OSLog)
            #if DEBUG
                blendLogger.info(
                    """
                    Using streaming multipart upload for large image \
                    (\(encodedSize, privacy: .public) bytes encoded, \
                    \(imageData.count, privacy: .public) bytes raw) to prevent memory spikes
                    """
                )
            #else
                blendLogger.info(
                    """
                    Using streaming multipart upload for large image \
                    (\(encodedSize, privacy: .private) bytes encoded, \
                    \(imageData.count, privacy: .private) bytes raw) to prevent memory spikes
                    """
                )
            #endif
        #else
            print(
                "Using streaming multipart upload for large image "
                    + "(\(encodedSize) bytes encoded, \(imageData.count) bytes raw) "
                    + "to prevent memory spikes"
            )
        #endif

        // Create multipart request
        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        // Apply request interceptors
        let interceptors = self.interceptors
        for interceptor in interceptors {
            request = await interceptor.willSend(request: request)
        }

        let boundary = "Boundary-" + UUID().uuidString
        request.setValue(
            "multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        // Progress: building multipart body
        onProgress?(0.4)
        
        let body = try MultipartBuilder.buildMultipartBody(
            boundary: boundary, configuration: configuration, imageData: imageData)

        request.httpBody = body
        
        // Progress: request prepared, starting upload
        onProgress?(0.5)

        let (data, response) = try await urlSession.data(for: request)

        // Apply response interceptors
        for interceptor in interceptors {
            await interceptor.didReceive(response: response, data: data)
        }
        
        // Progress: upload complete, validating response
        onProgress?(0.9)

        return try validateUploadResponse(data: data, response: response)
    }

    /// Uploads image data using multipart form data
    /// - Parameters:
    ///   - imageData: The image data to upload
    ///   - url: The upload endpoint URL
    ///   - configuration: Upload configuration options
    ///   - onProgress: Optional progress callback (0.0 to 1.0)
    /// - Returns: The response data from the server
    /// - Throws: NetworkError if the upload fails
    public func uploadImageMultipart(
        _ imageData: Data,
        to url: URL,
        configuration: UploadConfiguration = UploadConfiguration(),
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> Data {
        // Start progress at 0.0
        onProgress?(0.0)
        
        try await validateImageSize(imageData.count)
        
        // Progress: validation complete
        onProgress?(0.2)

        let boundary = "Boundary-" + UUID().uuidString
        
        // Progress: building multipart body
        onProgress?(0.3)
        
        let body = try MultipartBuilder.buildMultipartBody(
            boundary: boundary, configuration: configuration, imageData: imageData)

        // Progress: body prepared
        onProgress?(0.4)
        
        let request = try await createUploadRequest(
            url: url, body: body, contentType: "multipart/form-data; boundary=\(boundary)")
            
        // Progress: request prepared, starting upload
        onProgress?(0.5)

        let (data, response) = try await urlSession.data(for: request)

        // Apply response interceptors
        let interceptors = self.interceptors
        for interceptor in interceptors {
            await interceptor.didReceive(response: response, data: data)
        }
        
        // Progress: upload complete, validating response
        onProgress?(0.9)
        
        let result = try validateUploadResponse(data: data, response: response)
        
        // Progress: fully complete
        onProgress?(1.0)
        
        return result
    }

    /// Validates image size against upload limits
    private func validateImageSize(_ imageSize: Int) async throws {
        let effectiveMaxUploadSize: Int
        if let instanceMaxUploadSize = maxUploadSize {
            effectiveMaxUploadSize = instanceMaxUploadSize
        } else {
            effectiveMaxUploadSize = await AsyncNetConfig.shared.maxUploadSize
        }

        if imageSize > effectiveMaxUploadSize {
            #if DEBUG
                let message =
                    "Upload rejected: Image size \(imageSize) bytes exceeds limit of \(effectiveMaxUploadSize) bytes"
                blendLogger.warning("\(message, privacy: .public)")
            #else
                let message =
                    "Upload rejected: Image size \(imageSize) bytes exceeds limit of \(effectiveMaxUploadSize) bytes"
                blendLogger.warning("\(message, privacy: .private)")
            #endif
            throw NetworkError.payloadTooLarge(size: imageSize, limit: effectiveMaxUploadSize)
        }

        // Warn if image is large
        let maxRecommendedSize = effectiveMaxUploadSize / 4 * 3
        if imageSize > maxRecommendedSize {
            #if DEBUG
                let message =
                    "Warning: Large image (\(imageSize) bytes) approaches upload limit. "
                    + "Base64 encoding will increase size by ~33%."
                blendLogger.info("\(message, privacy: .public)")
            #else
                let message =
                    "Warning: Large image (\(imageSize) bytes) approaches upload limit. "
                    + "Base64 encoding will increase size by ~33%."
                blendLogger.info("\(message, privacy: .private)")
            #endif
        }
    }
}
