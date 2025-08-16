#if canImport(UIKit)
import UIKit
public typealias PlatformImage = UIImage
#elseif canImport(Cocoa)
import Cocoa
public typealias PlatformImage = NSImage
#endif
#if canImport(SwiftUI)
import SwiftUI
#endif


@MainActor
public func platformImageToData(_ image: PlatformImage, compressionQuality: CGFloat = 0.8) -> Data? {
#if canImport(UIKit)
    return image.jpegData(compressionQuality: compressionQuality)
#elseif canImport(Cocoa)
    guard let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData) else { return nil }
    return bitmap.representation(using: .jpeg, properties: [:])
#else
    return nil
#endif
}

/// Protocol abstraction for URLSession to enable mocking in tests
public protocol URLSessionProtocol: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: URLSessionProtocol {}



/// A comprehensive image service that provides downloading, uploading, and caching capabilities
/// with support for both UIKit and SwiftUI platforms.

public actor ImageService {
    private let imageCache: NSCache<NSString, PlatformImage>
    private let urlSession: URLSessionProtocol

    public init(cacheCountLimit: Int = 100, cacheTotalCostLimit: Int = 50 * 1024 * 1024, urlSession: URLSessionProtocol? = nil) {
        imageCache = NSCache<NSString, PlatformImage>()
        imageCache.countLimit = cacheCountLimit // max number of images
        imageCache.totalCostLimit = cacheTotalCostLimit // max 50MB

        if let urlSession = urlSession {
            self.urlSession = urlSession
        } else {
            // Create custom URLSession with caching support
            let configuration = URLSessionConfiguration.default
            configuration.requestCachePolicy = .useProtocolCachePolicy
            configuration.urlCache = URLCache(
                memoryCapacity: 10 * 1024 * 1024, // 10MB memory cache
                diskCapacity: 100 * 1024 * 1024,  // 100MB disk cache
                diskPath: nil
            )
            self.urlSession = URLSession(configuration: configuration)
        }
    }
    
    // MARK: - Image Fetching
    
    /// Fetches an image from the specified URL with caching support
    /// - Parameter urlString: The URL string for the image
    /// - Returns: A platform-specific image
    /// - Throws: NetworkError if the request fails
    /// Fetches image data from the specified URL with caching support
    /// - Parameter urlString: The URL string for the image
    /// - Returns: Image data
    /// - Throws: NetworkError if the request fails
    public func fetchImageData(from urlString: String) async throws -> Data {
        let cacheKey = urlString as NSString
        // Check cache for image data
        if let cachedImage = imageCache.object(forKey: cacheKey),
           let imageData = cachedImage.pngData() ?? cachedImage.jpegData(compressionQuality: 1.0) {
            return imageData
        }

        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL(urlString)
        }

        let request = URLRequest(url: url)
        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.decode
        }

        switch httpResponse.statusCode {
        case 200...299:
            guard let mimeType = httpResponse.mimeType else {
                throw NetworkError.badMimeType("no mimeType found")
            }

            let validMimeTypes = ["image/jpeg", "image/png", "image/gif", "image/webp", "image/heic"]
            guard validMimeTypes.contains(mimeType) else {
                throw NetworkError.badMimeType(mimeType)
            }

            // Cache image as PlatformImage for future use
            if let image = PlatformImage(data: data) {
                imageCache.setObject(image, forKey: cacheKey)
            }
            return data

        case 401:
            throw NetworkError.unauthorized
        default:
            throw NetworkError.unknown
        }
    }

    /// Converts image data to PlatformImage on the @MainActor (UI context)
    /// - Parameter data: Image data
    /// - Returns: PlatformImage (UIImage/NSImage)
    @MainActor
    public static func platformImage(from data: Data) -> PlatformImage? {
        return PlatformImage(data: data)
    }
    
    /// Fetches an image and returns it as SwiftUI Image
    /// - Parameter urlString: The URL string for the image
    /// - Returns: A SwiftUI Image
    /// - Throws: NetworkError if the request fails
    #if canImport(SwiftUI)
    @MainActor
    public static func swiftUIImage(from data: Data) -> SwiftUI.Image? {
        guard let platformImage = PlatformImage(data: data) else { return nil }
        return SwiftUI.Image(platformImage: platformImage)
    }
    #endif
    
    // MARK: - Image Uploading
    
    /// Configuration for image upload operations
    public struct UploadConfiguration: Sendable {
        public let fieldName: String
        public let fileName: String
        public let compressionQuality: CGFloat
        public let additionalFields: [String: String]
        
        public init(
            fieldName: String = "image",
            fileName: String = "image.jpg",
            compressionQuality: CGFloat = 0.8,
            additionalFields: [String: String] = [:]
        ) {
            self.fieldName = fieldName
            self.fileName = fileName
            self.compressionQuality = compressionQuality
            self.additionalFields = additionalFields
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
        
        // Create multipart request
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        let boundary = "Boundary-" + UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        
        // Add additional fields
        for (key, value) in configuration.additionalFields {
            body.append("--\(boundary)\r\n")
            body.append("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n")
            body.append("\(value)\r\n")
        }
        
        // Add image data
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"\(configuration.fieldName)\"; filename=\"\(configuration.fileName)\"\r\n")
        body.append("Content-Type: image/jpeg\r\n\r\n")
        body.append(imageData)
        body.append("\r\n--\(boundary)--\r\n")
        
        request.httpBody = body
        
        let (data, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.decode
        }
        
        switch httpResponse.statusCode {
        case 200...299:
            return data
        case 401:
            throw NetworkError.unauthorized
        default:
            throw NetworkError.unknown
        }
    }
    
    /// Uploads image data as base64 string in JSON payload
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
        // Convert image to base64
        let base64String = imageData.base64EncodedString()
        
        // Create JSON payload
        var payload: [String: Any] = [
            configuration.fieldName: base64String
        ]
        
        // Add additional fields
        for (key, value) in configuration.additionalFields {
            payload[key] = value
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        
        let (data, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.decode
        }
        
        switch httpResponse.statusCode {
        case 200...299:
            return data
        case 401:
            throw NetworkError.unauthorized
        default:
            throw NetworkError.unknown
        }
    }
    
    // MARK: - Cache Management
    
    /// Retrieves a cached image for the given key
    /// - Parameter key: The cache key (typically the URL string)
    /// - Returns: The cached image if available
    public func cachedImage(forKey key: String) -> PlatformImage? {
        return imageCache.object(forKey: key as NSString)
    }
    
    /// Clears all cached images
    public func clearCache() {
        imageCache.removeAllObjects()
    }
    
    /// Removes a specific image from cache
    /// - Parameter key: The cache key to remove
    public func removeFromCache(key: String) {
        imageCache.removeObject(forKey: key as NSString)
    }
    
    // MARK: - Private Helpers
    
    private func imageToData(_ image: PlatformImage, compressionQuality: CGFloat) throws -> Data {
        #if canImport(UIKit)
        guard let data = image.jpegData(compressionQuality: compressionQuality) else {
            throw NetworkError.decode
        }
        return data
        #elseif canImport(Cocoa)
        guard let tiffData = image.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData),
              let data = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: compressionQuality]) else {
            throw NetworkError.decode
        }
        return data
        #endif
    }
}

// MARK: - Data Extension for String Appending
private extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}

// MARK: - SwiftUI Image Extension
#if canImport(SwiftUI)
extension SwiftUI.Image {
    /// Creates a SwiftUI Image from a platform-specific image
    /// - Parameter platformImage: The UIImage or NSImage to convert
    public init(platformImage: PlatformImage) {
        #if canImport(UIKit)
        self.init(uiImage: platformImage)
        #elseif canImport(Cocoa)
        self.init(nsImage: platformImage)
        #endif
    }
}
#endif
