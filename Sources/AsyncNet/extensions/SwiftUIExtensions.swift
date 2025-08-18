import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

extension Image {
    /// Cross-platform initializer for PlatformImage
    static func from(platformImage: PlatformImage) -> Image {
#if os(macOS)
        return Image(nsImage: platformImage)
#else
        return Image(uiImage: platformImage)
#endif
    }
}
#if canImport(SwiftUI)
import SwiftUI
import Foundation
import Observation


/// The upload type for image operations in AsyncNet SwiftUI extensions.
///
/// - multipart: Uploads image using multipart form data.
/// - base64: Uploads image as base64 string in JSON payload.
enum UploadType: String, Sendable {
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
    /// Observable model for async image loading and uploading in SwiftUI.
    /// Use with @State in views for correct lifecycle management.
    @Observable
    @MainActor
    class AsyncImageModel {
        var loadedImage: PlatformImage?
        var isLoading: Bool = false
        var hasError: Bool = false
        var isUploading: Bool = false
        var error: NetworkError?

        private let imageService: ImageService

        init(imageService: ImageService) {
            self.imageService = imageService
        }

        func loadImage(from url: String?) async {
            guard let url = url else {
                await MainActor.run { self.hasError = true }
                return
            }
            await MainActor.run {
                self.isLoading = true
                self.hasError = false
            }
            do {
                let data = try await imageService.fetchImageData(from: url)
                await MainActor.run {
                    self.loadedImage = ImageService.platformImage(from: data)
                }
            } catch {
                await MainActor.run {
                    self.hasError = true
                    self.error = error as? NetworkError ?? NetworkError.wrap(error)
                }
            }
            await MainActor.run { self.isLoading = false }
        }

            /// Uploads an image and calls the result callbacks. Error callback always receives NetworkError.
            func uploadImage(_ image: PlatformImage, to uploadURL: URL?, uploadType: UploadType, configuration: ImageService.UploadConfiguration, onSuccess: ((Data) -> Void)? = nil, onError: ((NetworkError) -> Void)? = nil) async {
            guard let uploadURL = uploadURL else { return }
            isUploading = true
            guard let imageData = platformImageToData(image, compressionQuality: configuration.compressionQuality) else {
                onError?(NetworkError.imageProcessingFailed)
                isUploading = false
                return
            }
            do {
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
                onSuccess?(responseData)
                } catch {
                    let netError = error as? NetworkError ?? NetworkError.wrap(error)
                    onError?(netError)
                }
            isUploading = false
        }
    }

    /// A complete SwiftUI image view for async image loading and uploading, with progress and error handling.
    ///
    /// Use `AsyncNetImageView` for robust, cross-platform image display and upload in SwiftUI, with support for dependency injection, upload progress, and error states.
    ///
    /// - Important: Always inject `ImageService` for strict concurrency and testability.
    /// - Note: Supports both UIKit (UIImage) and macOS (NSImage) platforms.
    ///
    /// ### Usage Example
    /// ```swift
    /// AsyncNetImageView(
    ///     url: "https://example.com/image.jpg",
    ///     uploadURL: URL(string: "https://api.example.com/upload"),
    ///     uploadType: .multipart,
    ///     configuration: ImageService.UploadConfiguration(),
    ///     onUploadSuccess: { data in print("Upload successful: \(data)") },
    ///     onUploadError: { error in print("Upload failed: \(error)") },
    ///     imageService: imageService
    /// )
    /// ```
    struct AsyncNetImageView: View {
        let url: String?
        let uploadURL: URL?
        let uploadType: UploadType
        let configuration: ImageService.UploadConfiguration
    let onUploadSuccess: ((Data) -> Void)?
    /// Error callback always receives NetworkError
    let onUploadError: ((NetworkError) -> Void)?
        let imageService: ImageService
    /// Use @State for correct SwiftUI lifecycle management of @Observable model
    @State private var model: AsyncImageModel

        init(
            url: String? = nil,
            uploadURL: URL? = nil,
            uploadType: UploadType = .multipart,
            configuration: ImageService.UploadConfiguration = ImageService.UploadConfiguration(),
            onUploadSuccess: ((Data) -> Void)? = nil,
            onUploadError: ((NetworkError) -> Void)? = nil,
            imageService: ImageService
        ) {
            self.url = url
            self.uploadURL = uploadURL
            self.uploadType = uploadType
            self.configuration = configuration
            self.onUploadSuccess = onUploadSuccess
            self.onUploadError = onUploadError
            self.imageService = imageService
            _model = State(wrappedValue: AsyncImageModel(imageService: imageService))
        }

        var body: some View {
            Group {
                if let loadedImage = model.loadedImage {
                    Image.from(platformImage: loadedImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else if model.hasError {
                    ContentUnavailableView(
                        "Image Failed to Load",
                        systemImage: "photo",
                        description: Text("The image could not be downloaded.")
                    )
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
        }
    }
#endif