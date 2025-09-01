import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public extension Image {
    /// Cross-platform initializer for PlatformImage
    static func from(platformImage: PlatformImage) -> Image {
#if os(macOS)
        return Image(nsImage: platformImage)
#else
        return Image(uiImage: platformImage)
#endif
    }
}

/// The upload type for image operations in AsyncNet SwiftUI extensions.
///
/// - multipart: Uploads image using multipart form data.
/// - base64: Uploads image as base64 string in JSON payload.
public enum UploadType: String, Sendable {
    case multipart
    case base64
}

/// Observable view model for async image loading and uploading in SwiftUI.
///
/// Use `AsyncImageModel` with `AsyncNetImageView` for robust, actor-isolated image state management, including loading, error, and upload states.
///
/// - Important: Always inject `ImageService` for strict concurrency and testability.
/// - Note: All state properties are actor-isolated and observable for SwiftUI.
///
/// ### Usage Example
/// ```swift
/// @State var model = AsyncImageModel(imageService: imageService)
/// await model.loadImage(from: url)
/// await model.uploadImage(image, to: uploadURL, uploadType: .multipart, configuration: config)
/// ```
@MainActor
public class AsyncImageModel: ObservableObject {
    @Published public var loadedImage: PlatformImage?
    @Published public var isLoading: Bool = false
    @Published public var hasError: Bool = false
    @Published public var isUploading: Bool = false
    @Published public var error: NetworkError?
    private var loadToken: UUID? = nil
    
    private weak var imageService: ImageService?
    
    public init(imageService: ImageService) {
        self.imageService = imageService
    }
    
    public func loadImage(from url: String?) async {
        let token = UUID()
        self.loadToken = token
        
        // Early exit if task is already cancelled
        guard !Task.isCancelled else { 
            if self.loadToken == token {
                self.isLoading = false
                self.loadedImage = nil
                self.hasError = false
                self.error = nil
            }
            return 
        }
        
        guard let url = url else {
            if self.loadToken == token {
                self.hasError = true
                self.isLoading = false
            }
            return
        }
        
        // Check again before starting the network request
        guard !Task.isCancelled else { 
            if self.loadToken == token {
                self.isLoading = false
                self.loadedImage = nil
                self.hasError = false
                self.error = nil
            }
            return 
        }
        
        if self.loadToken == token {
            self.isLoading = true
            self.hasError = false
            self.error = nil
        }
        do {
            guard let imageService = imageService else {
                if self.loadToken == token {
                    self.hasError = true
                    self.error = NetworkError.networkUnavailable
                    self.isLoading = false
                }
                return
            }
            let data = try await imageService.fetchImageData(from: url)
            if self.loadToken == token {
                self.loadedImage = ImageService.platformImage(from: data)
                self.hasError = false
                self.error = nil
            }
        } catch {
            if self.loadToken == token {
                self.hasError = true
                self.error = error as? NetworkError ?? NetworkError.wrap(error)
            }
        }
        if self.loadToken == token {
            self.isLoading = false
        }
    }
    
    /// Uploads an image and calls the result callbacks. Error callback always receives NetworkError.
    public func uploadImage(_ image: PlatformImage, to uploadURL: URL?, uploadType: UploadType, configuration: ImageService.UploadConfiguration, onSuccess: ((Data) -> Void)? = nil, onError: ((NetworkError) -> Void)? = nil) async {
        guard let uploadURL = uploadURL else {
            let error = NetworkError.invalidEndpoint(reason: "Upload URL is required")
            self.error = error
            Task { @MainActor in
                onError?(error)
            }
            return
        }
        isUploading = true
        defer { isUploading = false }
        
        guard let imageData = ImageService.platformImageToData(image, compressionQuality: configuration.compressionQuality) else {
            self.error = NetworkError.imageProcessingFailed
            Task { @MainActor in
                onError?(NetworkError.imageProcessingFailed)
            }
            return
        }
        
        do {
            guard let imageService = imageService else {
                let error = NetworkError.networkUnavailable
                self.error = error
                Task { @MainActor in
                    onError?(error)
                }
                return
            }
            
            let responseData: Data
            switch uploadType {
                case .multipart:
                    responseData = try await imageService.uploadImageMultipart(
                        imageData,
                        to: uploadURL,
                        configuration: configuration
                    )
                case .base64:
                    responseData = try await imageService.uploadImageBase64(
                        imageData,
                        to: uploadURL,
                        configuration: configuration
                    )
            }
            Task { @MainActor in
                onSuccess?(responseData)
            }
        } catch {
            let netError = error as? NetworkError ?? NetworkError.wrap(error)
            self.error = netError
            Task { @MainActor in
                onError?(netError)
            }
        }
    }
}

/// A complete SwiftUI image view for async image loading and uploading, with progress and error handling.
///
/// Use `AsyncNetImageView` for robust, cross-platform image display and upload in SwiftUI, with support for dependency injection, upload progress, and error states.
///
/// - Important: Always inject `ImageService` for strict concurrency and testability.
/// - Note: Supports both UIKit (UIImage) and macOS (NSImage) platforms. The view automatically reloads when the URL changes.
///
/// ### Usage Example
/// ```swift
/// AsyncNetImageView(
///     url: "https://example.com/image.jpg",
///     uploadURL: URL(string: "https://api.example.com/upload"),
///     uploadType: .multipart,
///     configuration: ImageService.UploadConfiguration(),
///     autoUpload: true, // Automatically upload after loading
///     onUploadSuccess: { data in print("Upload successful: \(data)") },
///     onUploadError: { error in print("Upload failed: \(error)") },
///     imageService: imageService
/// )
///
/// // Or trigger upload programmatically:
/// let imageView = AsyncNetImageView(/* parameters */)
/// let success = await imageView.uploadImage()
/// ```
public struct AsyncNetImageView: View {
    let url: String?
    let uploadURL: URL?
    let uploadType: UploadType
    let configuration: ImageService.UploadConfiguration
    let onUploadSuccess: ((Data) -> Void)?
    /// Error callback always receives NetworkError
    let onUploadError: ((NetworkError) -> Void)?
    let imageService: ImageService
    let autoUpload: Bool
    /// Use @StateObject for correct SwiftUI lifecycle management of @Observable model
    @StateObject internal var model: AsyncImageModel
    
    public init(
        url: String? = nil,
        uploadURL: URL? = nil,
        uploadType: UploadType = .multipart,
        configuration: ImageService.UploadConfiguration = ImageService.UploadConfiguration(),
        onUploadSuccess: ((Data) -> Void)? = nil,
        onUploadError: ((NetworkError) -> Void)? = nil,
        autoUpload: Bool = false,
        imageService: ImageService
    ) {
        self.url = url
        self.uploadURL = uploadURL
        self.uploadType = uploadType
        self.configuration = configuration
        self.onUploadSuccess = onUploadSuccess
        self.onUploadError = onUploadError
        self.autoUpload = autoUpload
        self.imageService = imageService
        self._model = StateObject(wrappedValue: AsyncImageModel(imageService: imageService))
    }
    
    public var body: some View {
        Group {
            if let loadedImage = model.loadedImage {
                ZStack(alignment: .bottomTrailing) {
                    Image.from(platformImage: loadedImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                    
                    // Upload button overlay when uploadURL is provided
                    if uploadURL != nil {
                        Button(action: {
                            Task {
                                await performUpload()
                            }
                        }) {
                            Image(systemName: model.isUploading ? "arrow.up.circle.fill" : "arrow.up.circle")
                                .font(.title2)
                                .foregroundStyle(model.isUploading ? .blue : .white)
                                .padding(8)
                                .background(.ultraThinMaterial, in: Circle())
                                .shadow(radius: 2)
                        }
                        .disabled(model.isUploading)
                        .padding(12)
                        .transition(.scale.combined(with: .opacity))
                    }
                }
            } else if model.hasError {
                ContentUnavailableView {
                    Label("Image Failed to Load", systemImage: "photo")
                } description: {
                    Text("The image could not be downloaded.")
                } actions: {
                    Button("Retry") {
                        Task {
                            await model.loadImage(from: url)
                        }
                    }
                }
            } else if model.isLoading {
                ProgressView("Loading...")
                    .controlSize(.large)
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.tertiary)
                    .overlay(
                        Image(systemName: "photo")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                    )
            }
        }
        .overlay(
            Group {
                if model.isUploading {
                    ProgressView("Uploading...")
                        .padding()
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                }
            }
        )
        .task {
            await model.loadImage(from: url)
        }
        .task(id: url) {
            await model.loadImage(from: url)
        }
        .task(id: model.loadedImage) {
            // Auto-upload after image loads if enabled
            if autoUpload, model.loadedImage != nil, uploadURL != nil {
                await performUpload()
            }
        }
    }
    
    /// Performs the image upload with proper error handling
    private func performUpload() async {
        guard let loadedImage = model.loadedImage, let uploadURL = uploadURL else { return }
        
        await model.uploadImage(
            loadedImage,
            to: uploadURL,
            uploadType: uploadType,
            configuration: configuration,
            onSuccess: onUploadSuccess,
            onError: onUploadError
        )
    }
    
    /// Public method to programmatically trigger image upload
    /// - Returns: True if upload was initiated, false if no image loaded or uploadURL not set
    public func uploadImage() async -> Bool {
        guard model.loadedImage != nil, uploadURL != nil else { return false }
        await performUpload()
        return true
    }
}
