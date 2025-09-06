import Foundation

#if canImport(CoreGraphics)
    import CoreGraphics
#endif

/// A utility class for building multipart form data
/// Handles the construction of multipart/form-data bodies for HTTP uploads
public enum MultipartBuilder {
    /// Builds multipart form data body for image upload
    /// - Parameters:
    ///   - boundary: The multipart boundary string
    ///   - configuration: Upload configuration with field names and additional data
    ///   - imageData: The image data to include in the multipart body
    /// - Returns: Data containing the complete multipart form body
    public static func buildMultipartBody(
        boundary: String,
        configuration: UploadConfiguration,
        imageData: Data
    ) throws -> Data {
        var body = Data()

        // Add additional fields first
        for (key, value) in configuration.additionalFields {
            body.append(Data("--\(boundary)\r\n".utf8))
            body.append(
                Data("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n".utf8))
            body.append(Data("\(value)\r\n".utf8))
        }

        // Add the image data
        body.append(Data("--\(boundary)\r\n".utf8))
        let contentDisposition =
            "Content-Disposition: form-data; name=\"\(configuration.fieldName)\"; "
            + "filename=\"\(configuration.fileName)\"\r\n"
        body.append(Data(contentDisposition.utf8))
        body.append(Data("Content-Type: \(configuration.mimeType)\r\n\r\n".utf8))
        body.append(imageData)
        body.append(Data("\r\n".utf8))

        // Add closing boundary
        body.append(Data("--\(boundary)--\r\n".utf8))

        return body
    }
}

/// Configuration for image upload operations
public struct UploadConfiguration: Sendable {
    public let compressionQuality: CGFloat
    public let fieldName: String
    public let fileName: String
    public let additionalFields: [String: String]
    public let mimeType: String
    /// Threshold for switching to streaming upload (bytes of base64-encoded data)
    /// Images with encoded size above this threshold will use streaming multipart upload
    /// to avoid memory spikes. Default is 10MB of encoded data (~7.5MB raw).
    public let streamThreshold: Int

    public init(
        compressionQuality: CGFloat = 0.8,
        fieldName: String = "file",
        fileName: String = "image.jpg",
        additionalFields: [String: String] = [:],
        mimeType: String? = nil,
        streamThreshold: Int = 10 * 1024 * 1024  // 10MB encoded = ~7.5MB raw
    ) {
        self.compressionQuality = compressionQuality
        self.fieldName = fieldName
        self.fileName = fileName
        self.additionalFields = additionalFields
        // Use provided mimeType or default to image/jpeg for backward compatibility
        self.mimeType = mimeType ?? "image/jpeg"
        self.streamThreshold = streamThreshold
    }
}
