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

/// The upload type for image operations.
///
/// - multipart: Uploads image using multipart form data.
///   - Recommended for large images and production use.
///   - Better performance for files over 1MB.
///   - Supports streaming upload for better memory efficiency.
/// - base64: Uploads image as base64 string in JSON payload.
///   - Best for small images in JSON APIs.
///   - Suitable for images under 1MB.
///   - Convenient when the entire payload needs to be JSON.
public enum UploadType: String, Sendable {
    case multipart
    case base64
}

/// Observable view model for async image loading and uploading in SwiftUI.
///
/// Use `AsyncImageModel` with `BlendImageView` for robust, actor-isolated image state
/// management, including loading, error, and upload states.
///
/// - Important: Always inject `ImageService` for strict concurrency and testability.
/// - Note: All state properties are actor-isolated and observable for SwiftUI.
/// - Note: Supports progress tracking during image uploads via optional progress handlers.
///
/// ### Usage Example
/// ```swift
/// @State var model = AsyncImageModel(imageService: imageService)
/// await model.loadImage(from: url)
///
/// // Upload with progress tracking
/// let result = try await model.uploadImage(
///     image,
///     to: uploadURL,
///     uploadType: .multipart,
///     configuration: config
/// ) { progress in
///     print("Upload progress: \(progress * 100)%")
/// }
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
                    await self?.handleImageLoadError(
                        NetworkError.invalidEndpoint(reason: "URL is required"))
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

                self?.handleImageLoadSuccess(data)
            } catch is CancellationError {
                self?.handleImageLoadCancellation()
            } catch {
                await self?.handleImageLoadError(error)
            }
        }

        // Atomically swap the new task into taskBox and get the previous task
        let previousTask = await taskBox.setTask(task)

        // Cancel the previous task if it exists (it was replaced by our new task)
        previousTask?.cancel()

        // Await the local task (not the taskBox's current task)
        await task.value
    }

    /// Handles successful image loading
    @MainActor
    private func handleImageLoadSuccess(_ data: Data) {
        self.loadedImage = ImageService.platformImage(from: data)
        self.hasError = false
        self.error = nil
        self.isLoading = false
    }

    /// Handles task cancellation cleanup
    @MainActor
    private func handleImageLoadCancellation() {
        self.isLoading = false
        self.loadedImage = nil
        self.hasError = false
        self.error = nil
    }

    /// Handles image loading errors
    @MainActor
    private func handleImageLoadError(_ error: Error) async {
        let wrappedError = await NetworkError.wrapAsync(error, config: BlendConfig.shared)
        self.hasError = true
        self.error = wrappedError
        self.isLoading = false
    }

    /// Uploads an image and returns the response data. Throws NetworkError on failure.
    ///
    /// This method can be used without progress tracking, or with progress callbacks by passing
    /// a closure to the optional `onProgress` parameter.
    ///
    /// **Example: Simple upload**
    /// ```
    /// let responseData = try await uploadImage(
    ///     myImage,
    ///     to: uploadURL,
    ///     uploadType: .multipart,
    ///     configuration: config
    /// )
    /// ```
    ///
    /// **Example: Upload with progress tracking**
    /// ```
    /// let responseData = try await uploadImage(
    ///     myImage,
    ///     to: uploadURL,
    ///     uploadType: .base64,
    ///     configuration: config,
    ///     onProgress: { progress in
    ///         print("Upload progress: \(progress * 100)%")
    ///     }
    /// )
    /// ```
    ///
    /// Use the simple upload when you do not need to track progress. Use the progress-tracking variant to provide user feedback during long uploads.
    ///
    /// - Parameters:
    ///   - image: The PlatformImage to upload
    ///   - uploadURL: The URL to upload the image to (required)
    ///   - uploadType: The type of upload (.multipart or .base64)
    ///   - configuration: Upload configuration including field names and compression
    ///   - onProgress: Optional progress handler called during upload (0.0 to 1.0).
    ///     - **Thread Safety**: Handler is `@Sendable` and may be called from background threads.
    ///       Avoid direct UI updates; use `@MainActor` or `DispatchQueue.main` for UI work.
    ///     - **Performance**: Keep lightweight as it's called during I/O operations.
    /// - Returns: The response data from the upload endpoint
    /// - Throws: NetworkError if the upload fails
    public func uploadImage(
        _ image: PlatformImage, to uploadURL: URL, uploadType: UploadType,
        configuration: UploadConfiguration,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> Data {
        // Set uploading state and ensure cleanup on exit
        isUploading = true
        defer {
            // Always reset uploading state after operation completes
            isUploading = false
        }

        guard
            let imageData = ImageService.platformImageToData(
                image, compressionQuality: configuration.compressionQuality)
        else {
            let error = NetworkError.imageProcessingFailed
            self.hasError = true
            self.error = error
            throw error
        }

        do {
            let responseData: Data
            let validatedProgressHandler = createValidatedProgressHandler(onProgress)

            switch uploadType {
            case .multipart:
                responseData = try await imageService.uploadImageMultipart(
                    imageData,
                    to: uploadURL,
                    configuration: configuration,
                    onProgress: validatedProgressHandler
                )
            case .base64:
                responseData = try await imageService.uploadImageBase64(
                    imageData,
                    to: uploadURL,
                    configuration: configuration,
                    onProgress: validatedProgressHandler
                )
            }
            self.error = nil  // Clear any previous error on successful upload
            return responseData
        } catch {
            let netError: NetworkError
            if let existingError = error as? NetworkError {
                netError = existingError
            } else {
                netError = await NetworkError.wrapAsync(error, config: BlendConfig.shared)
            }
            self.hasError = true
            self.error = netError
            throw netError
        }
    }

    /// Creates a validated progress handler that ensures progress values are within 0.0 to 1.0 range
    /// - Parameter originalHandler: The original progress handler to wrap
    /// - Returns: A validated progress handler or nil if originalHandler is nil
    private func createValidatedProgressHandler(_ originalHandler: (@Sendable (Double) -> Void)?)
        -> (@Sendable (Double) -> Void)?
    {
        guard let originalHandler = originalHandler else { return nil }

        return { progress in
            // Validate progress is within valid range (0.0 to 1.0) and call handler
            let validatedProgress = Self.clampProgress(progress)
            originalHandler(validatedProgress)
        }
    }

    /// Utility function to clamp progress between 0.0 and 1.0
    /// - Parameter progress: The progress value to clamp
    /// - Returns: The clamped progress value between 0.0 and 1.0
    private static nonisolated func clampProgress(_ progress: Double) -> Double {
        return min(max(progress, 0.0), 1.0)
    }
}

/// A complete SwiftUI image view for async image loading and uploading, with progress and error handling.
///
/// Use `BlendImageView` for robust, cross-platform image display and upload in SwiftUI,
/// with support for dependency injection, upload progress, and error states.
///
/// - Important: Always inject `ImageService` for strict concurrency and testability.
/// - Note: Supports both UIKit (UIImage) and macOS (NSImage) platforms. The view
///   automatically reloads when the URL changes.
public struct BlendImageView: View {
    private let url: String?
    private let uploadURL: URL?
    private let uploadType: UploadType
    private let configuration: UploadConfiguration
    private let imageService: ImageService
    private let autoUpload: Bool
    /// Use @State for correct SwiftUI lifecycle management of @Observable model
    @State private var model: AsyncImageModel
    /// Prevents multiple auto-upload attempts
    @State private var hasAttemptedAutoUpload: Bool = false

    public init(
        url: String? = nil,
        uploadURL: URL? = nil,
        uploadType: UploadType = .multipart,
        configuration: UploadConfiguration = UploadConfiguration(),
        autoUpload: Bool = false,
        imageService: ImageService
    ) {
        self.url = url
        self.uploadURL = uploadURL
        self.uploadType = uploadType
        self.configuration = configuration
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
                        Button(
                            action: {
                                Task {
                                    await performUpload(expectedUrl: url)
                                }
                            },
                            label: {
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
                                        ? LocalizedStringKey("Uploading")
                                        : LocalizedStringKey("Upload")
                                )
                            }
                        )
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
            if model.loadedImage != nil && autoUpload && uploadURL != nil && !hasAttemptedAutoUpload
            {
                hasAttemptedAutoUpload = true
                await performUpload(expectedUrl: url)
            }
        }
    }

    /// Performs the image upload with proper error handling
    private func performUpload(expectedUrl: String? = nil) async {
        await performUpload(expectedUrl: expectedUrl, onProgress: nil)
    }

    /// Performs the image upload with progress tracking and proper error handling
    private func performUpload(
        expectedUrl: String? = nil, onProgress: (@Sendable (Double) -> Void)? = nil
    ) async {
        // If expectedUrl is provided, ensure it still matches
        if let expectedUrl = expectedUrl, expectedUrl != url {
            return
        }
        guard let loadedImage = model.loadedImage, let uploadURL = uploadURL else {
            // Log error for debugging but don't throw since this is a UI helper function
            #if DEBUG
                blendLogger.error("Upload failed: No image loaded or upload URL not set")
            #else
                blendLogger.error("Upload failed")
            #endif
            return
        }

        do {
            let result = try await model.uploadImage(
                loadedImage,
                to: uploadURL,
                uploadType: uploadType,
                configuration: configuration,
                onProgress: onProgress
            )
            // Upload successful - result contains response data
            // In a real app, you might want to handle the response data here
            #if DEBUG
                blendLogger.info("Upload successful: \(result.count) bytes received")
            #else
                blendLogger.info("Upload successful")
            #endif
        } catch {
            // Upload failed - error is already handled by AsyncImageModel
            // The model's error state is updated, which will be reflected in the UI
            #if DEBUG
                blendLogger.error("Upload failed: \(error.localizedDescription)")
            #else
                blendLogger.error("Upload failed")
            #endif
        }
    }

    /// Public method to programmatically trigger image upload with optional progress tracking.
    ///
    /// This method can be used without progress tracking, or with progress callbacks by passing
    /// a closure to the optional `onProgress` parameter.
    ///
    /// **Example: Simple upload**
    /// ```
    /// let result = try await imageView.uploadImage()
    /// ```
    ///
    /// **Example: Upload with progress tracking**
    /// ```
    /// let result = try await imageView.uploadImage { progress in
    ///     print("Upload progress: \(progress * 100)%")
    /// }
    /// ```
    ///
    /// - Parameter onProgress: Optional progress handler called during upload (0.0 to 1.0).
    ///     - **Thread Safety**: Handler is `@Sendable` and may be called from background threads.
    ///       Avoid direct UI updates; use `@MainActor` or `DispatchQueue.main` for UI work.
    ///     - **Performance**: Keep lightweight as it's called during I/O operations.
    /// - Returns: The response data from the upload endpoint
    /// - Throws: NetworkError if the upload fails or no image is loaded
    @MainActor
    public func uploadImage(onProgress: (@Sendable (Double) -> Void)? = nil) async throws -> Data {
        guard let loadedImage = model.loadedImage else {
            throw NetworkError.invalidEndpoint(reason: "No image loaded")
        }
        guard let uploadURL = uploadURL else {
            throw NetworkError.invalidEndpoint(reason: "Upload URL not set")
        }

        return try await model.uploadImage(
            loadedImage,
            to: uploadURL,
            uploadType: uploadType,
            configuration: configuration,
            onProgress: onProgress
        )
    }
}
