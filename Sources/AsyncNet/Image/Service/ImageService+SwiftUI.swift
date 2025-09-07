#if canImport(SwiftUI)
    import SwiftUI
#endif

/// SwiftUI extensions for ImageService
extension ImageService {
    /// Fetches an image and returns it as SwiftUI Image
    /// - Parameter urlString: The URL string for the image
    /// - Returns: A SwiftUI Image
    /// - Throws: NetworkError if the request fails
    #if canImport(SwiftUI)
        static func swiftUIImage(from data: Data) -> SwiftUI.Image? {
            guard let platformImage = PlatformImage(data: data) else { return nil }
            #if canImport(UIKit)
                return SwiftUI.Image(uiImage: platformImage)
            #elseif canImport(AppKit)
                return SwiftUI.Image(nsImage: platformImage)
            #endif
        }
    #endif
}
