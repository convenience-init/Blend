// swift-tools-version: 6.0
//
//  ImageService+Upload.swift
//  AsyncNet
//
//  Created by AsyncNet Team
//
//  This file contains the image upload functionality for ImageService.
//  Extracted to reduce the main ImageService file size and improve maintainability.

import Foundation

extension ImageService {
    /// Uploads image data as a JSON payload with a base64-encoded image field
    /// - Parameters:
    ///   - imageData: The image data to upload
    ///   - url: The upload endpoint URL
    ///   - configuration: Upload configuration options
    /// - Returns: The response data from the server
    /// - Throws: NetworkError if the upload fails
    public func uploadImageBase64(
        _ imageData: Data,
        to url: URL,
        configuration: UploadConfiguration = UploadConfiguration()
    ) async throws -> Data {
        // Pre-check to avoid memory issues with very large images
        // Calculate raw data limit from configured max upload size, accounting for base64 expansion
        let configMaxUploadSize: Int
        if let instanceMaxUploadSize = maxUploadSize {
            configMaxUploadSize = instanceMaxUploadSize
        } else {
            configMaxUploadSize = await AsyncNetConfig.shared.maxUploadSize
        }
        let maxSafeRawSize: Int
        if configMaxUploadSize > 0 {
            // Base64 encoding increases size by ~33%, so raw limit = configMax * 3/4
            let calculatedRawLimit = Int(Double(configMaxUploadSize) * 3.0 / 4.0)
            maxSafeRawSize = max(calculatedRawLimit, 50 * 1024 * 1024)  // Ensure minimum 50MB fallback
        } else {
            // Fallback to original 50MB default if config is invalid
            maxSafeRawSize = 50 * 1024 * 1024
        }

        if imageData.count > maxSafeRawSize {
            #if canImport(OSLog)
                asyncNetLogger.warning(
                    "Upload rejected: Image size \(imageData.count, privacy: .public) bytes exceeds raw size limit of \(maxSafeRawSize, privacy: .public) bytes"
                )
            #else
                print(
                    "Upload rejected: Image size \(imageData.count) bytes exceeds raw size limit of \(maxSafeRawSize) bytes"
                )
            #endif
            throw NetworkError.payloadTooLarge(size: imageData.count, limit: maxSafeRawSize)
        }

        // Check upload size limit (validate post-encoding size since base64 increases size ~33%)
        let effectiveMaxUploadSize: Int
        if let instanceMaxUploadSize = maxUploadSize {
            effectiveMaxUploadSize = instanceMaxUploadSize
        } else {
            effectiveMaxUploadSize = await AsyncNetConfig.shared.maxUploadSize
        }
        let encodedSize = ((imageData.count + 2) / 3) * 4
        if encodedSize > effectiveMaxUploadSize {
            #if canImport(OSLog)
                asyncNetLogger.warning(
                    "Upload rejected: Base64-encoded image size \(encodedSize, privacy: .public) bytes exceeds limit of \(effectiveMaxUploadSize, privacy: .public) bytes (raw size: \(imageData.count, privacy: .public) bytes)"
                )
            #else
                print(
                    "Upload rejected: Base64-encoded image size \(encodedSize) bytes exceeds limit of \(effectiveMaxUploadSize) bytes (raw size: \(imageData.count) bytes)"
                )
            #endif
            throw NetworkError.payloadTooLarge(size: encodedSize, limit: effectiveMaxUploadSize)
        }

        // Determine upload strategy based on encoded size
        if encodedSize <= configuration.streamThreshold {
            // Use JSON + base64 for smaller images (existing path)
            return try await uploadImageBase64Small(
                imageData, to: url, configuration: configuration)
        } else {
            // Use streaming multipart for larger images to avoid memory spikes
            return try await uploadImageBase64Streaming(
                imageData, to: url, configuration: configuration)
        }
    }

    /// Upload small images using JSON payload with base64 encoding
    private func uploadImageBase64Small(
        _ imageData: Data,
        to url: URL,
        configuration: UploadConfiguration
    ) async throws -> Data {
        // Encode image data as base64 string
        let base64String = imageData.base64EncodedString()

        // Create type-safe payload using Codable
        let payload = UploadPayload(
            fieldName: configuration.fieldName,
            fileName: configuration.fileName,
            compressionQuality: configuration.compressionQuality,
            base64Data: base64String,
            additionalFields: configuration.additionalFields
        )

        // Validate the final JSON payload size against upload limits
        let effectiveMaxUploadSize: Int
        if let instanceMaxUploadSize = maxUploadSize {
            effectiveMaxUploadSize = instanceMaxUploadSize
        } else {
            effectiveMaxUploadSize = await AsyncNetConfig.shared.maxUploadSize
        }
        let jsonPayload = try JSONEncoder().encode(payload)
        let finalPayloadSize = jsonPayload.count

        if finalPayloadSize > effectiveMaxUploadSize {
            #if canImport(OSLog)
                asyncNetLogger.warning(
                    "Upload rejected: JSON payload size \(finalPayloadSize, privacy: .public) bytes exceeds limit of \(effectiveMaxUploadSize, privacy: .public) bytes (base64 image: \(imageData.count, privacy: .public) bytes, encoded: \(((imageData.count + 2) / 3) * 4, privacy: .public) bytes)"
                )
            #else
                print(
                    "Upload rejected: JSON payload size \(finalPayloadSize) bytes exceeds limit of \(effectiveMaxUploadSize) bytes (base64 image: \(imageData.count) bytes, encoded: \(((imageData.count + 2) / 3) * 4) bytes)"
                )
            #endif
            throw NetworkError.payloadTooLarge(
                size: finalPayloadSize, limit: effectiveMaxUploadSize)
        }

        // Warn if payload is large (accounts for JSON overhead + base64 encoding)
        let maxRecommendedSize = (effectiveMaxUploadSize * 3) / 4  // ~75% of max to account for JSON + base64 overhead
        if finalPayloadSize > maxRecommendedSize {
            #if canImport(OSLog)
                asyncNetLogger.info(
                    "Warning: Large JSON payload (\(finalPayloadSize, privacy: .public) bytes, base64 image: \(imageData.count, privacy: .public) bytes) approaches upload limit. Consider using multipart upload."
                )
            #else
                print(
                    "Warning: Large JSON payload (\(finalPayloadSize) bytes, base64 image: \(imageData.count) bytes) approaches upload limit. Consider using multipart upload."
                )
            #endif
        }

        // Create JSON request
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Apply request interceptors
        let interceptors = self.interceptors
        for interceptor in interceptors {
            request = await interceptor.willSend(request: request)
        }

        request.httpBody = jsonPayload

        let (data, response) = try await urlSession.data(for: request)

        // Apply response interceptors
        for interceptor in interceptors {
            await interceptor.didReceive(response: response, data: data)
        }

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
        configuration: UploadConfiguration
    ) async throws -> Data {
        // Log that we're using streaming upload for large images
        let encodedSize = ((imageData.count + 2) / 3) * 4
        #if canImport(OSLog)
            asyncNetLogger.info(
                "Using streaming multipart upload for large image (\(encodedSize, privacy: .public) bytes encoded, \(imageData.count, privacy: .public) bytes raw) to prevent memory spikes"
            )
        #else
            print(
                "Using streaming multipart upload for large image (\(encodedSize) bytes encoded, \(imageData.count) bytes raw) to prevent memory spikes"
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

        let body = try MultipartBuilder.buildMultipartBody(
            boundary: boundary, configuration: configuration, imageData: imageData)

        request.httpBody = body

        let (data, response) = try await urlSession.data(for: request)

        // Apply response interceptors
        for interceptor in interceptors {
            await interceptor.didReceive(response: response, data: data)
        }

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

    /// Uploads image data using multipart form data
    /// - Parameters:
    ///   - imageData: The image data to upload
    ///   - url: The upload endpoint URL
    ///   - configuration: Upload configuration options
    /// - Returns: The response data from the server
    /// - Throws: NetworkError if the upload fails
    public func uploadImageMultipart(
        _ imageData: Data,
        to url: URL,
        configuration: UploadConfiguration = UploadConfiguration()
    ) async throws -> Data {
        // Check upload size limit
        let effectiveMaxUploadSize: Int
        if let instanceMaxUploadSize = maxUploadSize {
            effectiveMaxUploadSize = instanceMaxUploadSize
        } else {
            effectiveMaxUploadSize = await AsyncNetConfig.shared.maxUploadSize
        }
        if imageData.count > effectiveMaxUploadSize {
            #if canImport(OSLog)
                asyncNetLogger.warning(
                    "Upload rejected: Image size \(imageData.count, privacy: .public) bytes exceeds limit of \(effectiveMaxUploadSize, privacy: .public) bytes"
                )
            #else
                print(
                    "Upload rejected: Image size \(imageData.count) bytes exceeds limit of \(effectiveMaxUploadSize) bytes"
                )
            #endif
            throw NetworkError.payloadTooLarge(size: imageData.count, limit: effectiveMaxUploadSize)
        }

        // Warn if image is large (base64 encoding will increase size by ~33%)
        let maxRecommendedSize = effectiveMaxUploadSize / 4 * 3  // ~75% of max to account for base64 overhead
        if imageData.count > maxRecommendedSize {
            #if canImport(OSLog)
                asyncNetLogger.info(
                    "Warning: Large image (\(imageData.count, privacy: .public) bytes) approaches upload limit. Base64 encoding will increase size by ~33%."
                )
            #else
                print(
                    "Warning: Large image (\(imageData.count) bytes) approaches upload limit. Base64 encoding will increase size by ~33%."
                )
            #endif
        }

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

        let body = try MultipartBuilder.buildMultipartBody(
            boundary: boundary, configuration: configuration, imageData: imageData)

        request.httpBody = body

        let (data, response) = try await urlSession.data(for: request)

        // Apply response interceptors
        for interceptor in interceptors {
            await interceptor.didReceive(response: response, data: data)
        }

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
}
