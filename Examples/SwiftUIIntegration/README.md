# SwiftUI Integration Example

This example demonstrates how to integrate Blend's networking and image capabilities with SwiftUI for modern, reactive user interfaces.

## What You'll Learn

- How to use `AsyncImageModel` for reactive image loading
- How to integrate networking services with SwiftUI view models
- How to handle loading states and errors in SwiftUI
- How to use Blend's SwiftUI view extensions

## Key Components

### 1. View Model with Networking
```swift
@MainActor
class PhotoGalleryViewModel: ObservableObject {
    @Published var photos: [Photo] = []
    @Published var isLoading = false
    @Published var error: NetworkError?

    private let photoService = PhotoService()
    let imageService = ImageService()

    func loadPhotos() async {
        // Reactive state management with proper error handling
    }
}
```

### 2. Async Image Loading
```swift
Rectangle()
    .asyncImage(
        from: photo.thumbnailUrl,
        imageService: imageService,
        placeholder: ProgressView().controlSize(.small),
        errorView: Image(systemName: "photo")
    )
```

### 3. Reactive Error Handling
```swift
if let error = viewModel.error {
    VStack {
        Image(systemName: "exclamationmark.triangle")
        Text("Failed to load photos")
        Text(error.message())
        Button("Retry") { /* retry logic */ }
    }
}
```

## Features Demonstrated

- ✅ **Reactive State Management**: `@Published` properties with `@StateObject`
- ✅ **Async Image Loading**: Automatic thumbnail loading with caching
- ✅ **Error Handling**: User-friendly error display with retry functionality
- ✅ **Loading States**: Progress indicators during network operations
- ✅ **SwiftUI Integration**: Native SwiftUI patterns with Blend components

## Running the Example

```bash
cd Examples/SwiftUIIntegration
swift run
```

**Note**: This example creates a macOS app. For iOS, you would need to modify the platform settings and use appropriate iOS-specific UI components.

## Architecture Patterns

### MVVM with Networking
```
View → ViewModel → Service → Network
    ↑         ↑         ↑
  State   Business   Data
  Mgmt    Logic    Access
```

### Reactive Error Handling
- Errors are converted to user-friendly messages
- UI automatically updates when error state changes
- Retry functionality allows users to recover from failures

### Image Caching
- Thumbnails are automatically cached by `ImageService`
- Subsequent loads are instant from cache
- Memory and disk caching with configurable limits

## Next Steps

After this example, explore:
- [Image Operations](../ImageOperations/) - Advanced image upload/download
- [Error Handling](../ErrorHandling/) - Comprehensive error scenarios
- [Advanced Networking](../AdvancedNetworking/) - Complex service patterns

## Platform Notes

This example is configured for macOS. For iOS deployment:
1. Update `Package.swift` platform to `.iOS(.v18)`
2. Modify UI components for iOS-specific patterns
3. Add iOS-specific permissions if needed