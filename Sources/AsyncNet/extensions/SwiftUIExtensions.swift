#if canImport(SwiftUI)
import SwiftUI
import Foundation

// MARK: - AsyncImageLoader View Modifier
public struct AsyncImageLoader: ViewModifier {
    let url: String?
    let placeholder: AnyView
    let errorView: AnyView
    
    @State private var loadedImage: PlatformImage?
    @State private var isLoading = false
    @State private var hasError = false
    
    public func body(content: Content) -> some View {
        Group {
            if let loadedImage = loadedImage {
                SwiftUI.Image(platformImage: loadedImage)
                    .resizable()
            } else if hasError {
                errorView
            } else if isLoading {
                placeholder
            } else {
                placeholder
            }
        }
        .task {
            await loadImage()
        }
    }
    
    @MainActor
    private func loadImage() async {
        guard let url = url else {
            hasError = true
            return
        }
        
        isLoading = true
        hasError = false
        
        do {
            loadedImage = try await ImageService.shared.fetchImage(from: url)
        } catch {
            hasError = true
        }
        
        isLoading = false
    }
}

public extension View {
    /// Loads an image asynchronously and displays it with customizable placeholder and error views
    /// - Parameters:
    ///   - url: The URL string of the image to load
    ///   - placeholder: The view to show while loading (default: ProgressView)
    ///   - errorView: The view to show on error (default: system photo icon)
    /// - Returns: A view that displays the loaded image, placeholder, or error view
    func asyncImage(
        from url: String?,
        placeholder: some View = ProgressView().controlSize(.large),
        errorView: some View = Image(systemName: "photo").foregroundStyle(.secondary)
    ) -> some View {
        self.modifier(AsyncImageLoader(
            url: url,
            placeholder: AnyView(placeholder),
            errorView: AnyView(errorView)
        ))
    }
}

// MARK: - Image Upload View Modifier
public struct ImageUploader: ViewModifier {
    let uploadURL: URL
    let configuration: ImageService.UploadConfiguration
    let uploadType: UploadType
    let onSuccess: (Data) -> Void
    let onError: (Error) -> Void
    
    @State private var isUploading = false
    
    public enum UploadType: Sendable {
        case multipart
        case base64
    }
    
    public func body(content: Content) -> some View {
        content
            .overlay(
                Group {
                    if isUploading {
                        ProgressView("Uploading...")
                            .padding()
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            )
    }
    
    @MainActor
    public func uploadImage(_ image: PlatformImage) async {
        isUploading = true
        
        do {
            let responseData: Data
            switch uploadType {
            case .multipart:
                responseData = try await ImageService.shared.uploadImageMultipart(
                    image,
                    to: uploadURL,
                    configuration: configuration
                )
            case .base64:
                responseData = try await ImageService.shared.uploadImageBase64(
                    image,
                    to: uploadURL,
                    configuration: configuration
                )
            }
            onSuccess(responseData)
        } catch {
            onError(error)
        }
        
        isUploading = false
    }
}

public extension View {
    /// Adds image upload capability to a view
    /// - Parameters:
    ///   - uploadURL: The URL to upload images to
    ///   - uploadType: Whether to use multipart or base64 upload
    ///   - configuration: Upload configuration options
    ///   - onSuccess: Callback for successful uploads
    ///   - onError: Callback for upload errors
    /// - Returns: A view with upload capability and loading overlay
    func imageUploader(
        uploadURL: URL,
        uploadType: ImageUploader.UploadType = .multipart,
        configuration: ImageService.UploadConfiguration = ImageService.UploadConfiguration(),
        onSuccess: @escaping (Data) -> Void,
        onError: @escaping (Error) -> Void
    ) -> some View {
        self.modifier(ImageUploader(
            uploadURL: uploadURL,
            configuration: configuration,
            uploadType: uploadType,
            onSuccess: onSuccess,
            onError: onError
        ))
    }
}

// MARK: - Combined Image View with Loading and Upload
public struct AsyncNetImageView: View {
    let url: String?
    let uploadURL: URL?
    let uploadType: ImageUploader.UploadType
    let configuration: ImageService.UploadConfiguration
    let onUploadSuccess: ((Data) -> Void)?
    let onUploadError: ((Error) -> Void)?
    
    @State private var loadedImage: PlatformImage?
    @State private var isLoading = false
    @State private var hasError = false
    @State private var isUploading = false
    
    public init(
        url: String? = nil,
        uploadURL: URL? = nil,
        uploadType: ImageUploader.UploadType = .multipart,
        configuration: ImageService.UploadConfiguration = ImageService.UploadConfiguration(),
        onUploadSuccess: ((Data) -> Void)? = nil,
        onUploadError: ((Error) -> Void)? = nil
    ) {
        self.url = url
        self.uploadURL = uploadURL
        self.uploadType = uploadType
        self.configuration = configuration
        self.onUploadSuccess = onUploadSuccess
        self.onUploadError = onUploadError
    }
    
    public var body: some View {
        Group {
            if let loadedImage = loadedImage {
                SwiftUI.Image(platformImage: loadedImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else if hasError {
                ContentUnavailableView(
                    "Image Failed to Load",
                    systemImage: "photo",
                    description: Text("The image could not be downloaded.")
                )
            } else if isLoading {
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
                if isUploading {
                    ProgressView("Uploading...")
                        .padding()
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                }
            }
        )
        .task {
            await loadImage()
        }
    }
    
    @MainActor
    private func loadImage() async {
        guard let url = url else { return }
        
        isLoading = true
        hasError = false
        
        do {
            loadedImage = try await ImageService.shared.fetchImage(from: url)
        } catch {
            hasError = true
        }
        
        isLoading = false
    }
    
    @MainActor
    public func uploadImage(_ image: PlatformImage) async {
        guard let uploadURL = uploadURL else { return }
        
        isUploading = true
        
        do {
            let responseData: Data
            switch uploadType {
            case .multipart:
                responseData = try await ImageService.shared.uploadImageMultipart(
                    image,
                    to: uploadURL,
                    configuration: configuration
                )
            case .base64:
                responseData = try await ImageService.shared.uploadImageBase64(
                    image,
                    to: uploadURL,
                    configuration: configuration
                )
            }
            onUploadSuccess?(responseData)
        } catch {
            onUploadError?(error)
        }
        
        isUploading = false
    }
}

#endif