#if canImport(SwiftUI)
import SwiftUI
import Foundation
import Observation

enum UploadType: String, Sendable {
    case multipart
    case base64
}

    @Observable
    @MainActor
    final class AsyncImageModel {
        var loadedImage: PlatformImage?
        var isLoading: Bool = false
        var hasError: Bool = false
        var isUploading: Bool = false
        var error: Error?

        private let imageService: ImageService

        init(imageService: ImageService) {
            self.imageService = imageService
        }

        func loadImage(from url: String?) async {
            guard let url = url else {
                hasError = true
                return
            }
            isLoading = true
            hasError = false
            do {
                let data = try await imageService.fetchImageData(from: url)
                loadedImage = ImageService.platformImage(from: data)
            } catch {
                hasError = true
                self.error = error
            }
            isLoading = false
        }

        func uploadImage(_ image: PlatformImage, to uploadURL: URL?, uploadType: UploadType, configuration: ImageService.UploadConfiguration, onSuccess: ((Data) -> Void)? = nil, onError: ((Error) -> Void)? = nil) async {
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
                onError?(error)
            }
            isUploading = false
        }
    }

    struct AsyncNetImageView: View {
        let url: String?
        let uploadURL: URL?
        let uploadType: UploadType
        let configuration: ImageService.UploadConfiguration
        let onUploadSuccess: ((Data) -> Void)?
        let onUploadError: ((Error) -> Void)?
        let imageService: ImageService
        @State var model: AsyncImageModel

        init(
            url: String? = nil,
            uploadURL: URL? = nil,
            uploadType: UploadType = .multipart,
            configuration: ImageService.UploadConfiguration = ImageService.UploadConfiguration(),
            onUploadSuccess: ((Data) -> Void)? = nil,
            onUploadError: ((Error) -> Void)? = nil,
            imageService: ImageService
        ) {
            self.url = url
            self.uploadURL = uploadURL
            self.uploadType = uploadType
            self.configuration = configuration
            self.onUploadSuccess = onUploadSuccess
            self.onUploadError = onUploadError
            self.imageService = imageService
            _model = State(initialValue: AsyncImageModel(imageService: imageService))
        }

        var body: some View {
            Group {
                if let loadedImage = model.loadedImage {
                    SwiftUI.Image(platformImage: loadedImage)
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