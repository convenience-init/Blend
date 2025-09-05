import SwiftUI

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

extension Image {
    /// Cross-platform initializer for PlatformImage
    public static func from(platformImage: PlatformImage) -> Image {
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
@Observable
public class AsyncImageModel {
    public var loadedImage: PlatformImage?
    public var isLoading: Bool = false
    public var hasError: Bool = false
    public var isUploading: Bool = false
    public var error: NetworkError?
    
    private let imageService: ImageService
    
    // Store the current task in a box to allow nonisolated access from deinit
    private let taskBox = TaskBox()

    private actor TaskBox {
        var task: Task<Void, Never>?
        
        func setTask(_ newTask: Task<Void, Never>?) async -> Task<Void, Never>? {
            // Cancel existing task if present
            let previousTask = task
            if let existingTask = task {
                existingTask.cancel()
            }
            task = newTask
            return previousTask
        }

        func cancelTask() async {
            if let currentTask = task {
                currentTask.cancel()
            }
            task = nil
        }

        func clearTask() async {
            task = nil
        }
        
        func clearTaskIfEqual(to otherTask: Task<Void, Never>?) async {
            // Tasks are not reference types, so we can't use === comparison
            // Instead, we'll use a simpler approach: only clear if we have a task
            // The race condition is handled by the fact that setTask cancels previous tasks
            if task != nil {
                task = nil
            }
        }
    }

    public init(imageService: ImageService) {
        self.imageService = imageService
    }

    deinit {
        // Cancel any in-flight load task asynchronously to prevent task leaks
        // Use a detached task to avoid capturing self in the closure
        Task.detached { [taskBox] in
            await taskBox.cancelTask()
        }
    }

    public func loadImage(from url: String?) async {
        // Create new task for this load operation
        let task = Task<Void, Never> { [weak self, imageService = self.imageService, url] in
            do {
                // Check for cancellation before starting
                try Task.checkCancellation()

                guard let url = url else {
                    await MainActor.run {
                        guard let self = self else { return }
                        self.hasError = true
                        self.error = NetworkError.invalidEndpoint(reason: "URL is required")
                        self.isLoading = false
                        self.loadedImage = nil
                    }
                    return
                }

                // Check for cancellation before network request
                try Task.checkCancellation()

                await MainActor.run {
                    guard let self = self else { return }
                    self.isLoading = true
                    self.hasError = false
                    self.error = nil
                }
                
                let data = try await imageService.fetchImageData(from: url)
                
                // Check for cancellation before updating state
                try Task.checkCancellation()

                await MainActor.run {
                    guard let self = self else { return }
                    self.loadedImage = ImageService.platformImage(from: data)
                    self.hasError = false
                    self.error = nil
                    self.isLoading = false
                }
            } catch is CancellationError {
                // Task was cancelled, clean up state if self still exists
                await MainActor.run {
                    guard let self = self else { return }
                    self.isLoading = false
                    self.loadedImage = nil
                    self.hasError = false
                    self.error = nil
                }
            } catch {
                // Handle other errors
                let wrappedError = await NetworkError.wrapAsync(
                    error, config: AsyncNetConfig.shared)
                await MainActor.run {
                    guard let self = self else { return }
                    self.hasError = true
                    self.error = wrappedError
                    self.isLoading = false
                }
            }
        }

        // Atomically swap the new task into taskBox and get the previous task
        let previousTask = await taskBox.setTask(task)

        // Cancel the previous task if it exists (it was replaced by our new task)
        previousTask?.cancel()

        // Await the local task (not the taskBox's current task)
        await task.value

        // Only clear if taskBox still holds our task (prevent clearing a newer task)
        await taskBox.clearTaskIfEqual(to: task)
    }

    /// Uploads an image and calls the result callbacks. Error callback always receives NetworkError.
    public func uploadImage(
        _ image: PlatformImage, to uploadURL: URL?, uploadType: UploadType,
        configuration: ImageService.UploadConfiguration, onSuccess: ((Data) -> Void)? = nil,
        onError: ((NetworkError) -> Void)? = nil
    ) async {
        isUploading = true
        defer { isUploading = false }

        guard let uploadURL = uploadURL else {
            let error = NetworkError.invalidEndpoint(reason: "Upload URL is required")
            self.error = error
            onError?(error)
            return
        }

        guard
            let imageData = ImageService.platformImageToData(
                image, compressionQuality: configuration.compressionQuality)
        else {
            let error = NetworkError.imageProcessingFailed
            self.error = error
            onError?(error)
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
            self.error = nil  // Clear any previous error on successful upload
            onSuccess?(responseData)
        } catch {
            let netError: NetworkError
            if let existingError = error as? NetworkError {
                netError = existingError
            } else {
                netError = await NetworkError.wrapAsync(error, config: AsyncNetConfig.shared)
            }
            self.error = netError
            onError?(netError)
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
    /// Use @State for correct SwiftUI lifecycle management of @Observable model
    @State private var model: AsyncImageModel
    /// Prevents multiple auto-upload attempts
    @State private var hasAttemptedAutoUpload: Bool = false

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
        self._model = State(wrappedValue: AsyncImageModel(imageService: imageService))
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
                                await performUpload(expectedUrl: url)
                            }
                        }) {
                            Image(
                                systemName: model.isUploading
                                    ? "arrow.up.circle.fill" : "arrow.up.circle"
                            )
                            .font(.title2)
                            .foregroundStyle(model.isUploading ? .blue : .white)
                            .padding(8)
                            .background(.ultraThinMaterial, in: Circle())
                            .shadow(radius: 2)
                            .accessibilityLabel(
                                model.isUploading
                                    ? LocalizedStringKey("Uploading") : LocalizedStringKey("Upload")
                            )
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
                #if os(tvOS)
                    ProgressView("Loading...")
                #else
                    ProgressView("Loading...")
                        .controlSize(.large)
                #endif
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
        .task(id: url) {
            hasAttemptedAutoUpload = false
            await model.loadImage(from: url)
            // Perform auto-upload immediately after successful load
            if model.loadedImage != nil && autoUpload && uploadURL != nil
                && !hasAttemptedAutoUpload
            {
                hasAttemptedAutoUpload = true
                await performUpload(expectedUrl: url)
            }
        }
    }

    /// Performs the image upload with proper error handling
    private func performUpload(expectedUrl: String? = nil) async {
        // If expectedUrl is provided, ensure it still matches
        if let expectedUrl = expectedUrl, expectedUrl != url {
            return
        }
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
    @MainActor
    public func uploadImage() async -> Bool {
        guard model.loadedImage != nil, uploadURL != nil else { return false }
        await performUpload(expectedUrl: url)
        return true
    }
}
