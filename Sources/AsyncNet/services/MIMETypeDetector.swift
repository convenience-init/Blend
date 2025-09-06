#if canImport(UIKit)
    import UIKit
    import CoreGraphics
#elseif canImport(AppKit)
    import AppKit
    import CoreGraphics
#endif
#if canImport(UniformTypeIdentifiers)
    import UniformTypeIdentifiers
#endif

/// A utility class for detecting MIME types from image data
/// Supports JPEG, PNG, GIF, WebP, BMP, TIFF, HEIC, and AVIF formats
public enum MIMETypeDetector {
    /// Detects MIME type from image data by examining the file header
    /// - Parameter data: The image data to analyze
    /// - Returns: Detected MIME type string, or nil if detection fails
    public static func detectMimeType(from data: Data) -> String? {
        guard !data.isEmpty else { return nil }

        // Read at least 32 bytes to handle complex signatures
        let bytes = [UInt8](data.prefix(min(32, data.count)))
        let dataCount = data.count

        // Define MIME type detectors as an array of (pattern, mimeType) tuples
        let detectors: [(pattern: [Int: UInt8], minLength: Int, mimeType: String)] = [
            // JPEG: FF D8 FF (SOI marker)
            ([0: 0xFF, 1: 0xD8, 2: 0xFF], 3, "image/jpeg"),
            // PNG: 89 50 4E 47 0D 0A 1A 0A
            (
                [0: 0x89, 1: 0x50, 2: 0x4E, 3: 0x47, 4: 0x0D, 5: 0x0A, 6: 0x1A, 7: 0x0A], 8,
                "image/png"
            ),
            // GIF87a: 47 49 46 38 37 61
            ([0: 0x47, 1: 0x49, 2: 0x46, 3: 0x38, 4: 0x37, 5: 0x61], 6, "image/gif"),
            // GIF89a: 47 49 46 38 39 61
            ([0: 0x47, 1: 0x49, 2: 0x46, 3: 0x38, 4: 0x39, 5: 0x61], 6, "image/gif"),
            // BMP: 42 4D (BM)
            ([0: 0x42, 1: 0x4D], 2, "image/bmp"),
            // TIFF Little Endian: 49 49 2A 00
            ([0: 0x49, 1: 0x49, 2: 0x2A, 3: 0x00], 4, "image/tiff"),
            // TIFF Big Endian: 4D 4D 00 2A
            ([0: 0x4D, 1: 0x4D, 2: 0x00, 3: 0x2A], 4, "image/tiff"),
        ]

        // Check standard patterns
        for (pattern, minLength, mimeType) in detectors {
            guard dataCount >= minLength else { continue }
            let matches = pattern.allSatisfy { offset, expectedByte in
                bytes[offset] == expectedByte
            }
            if matches { return mimeType }
        }

        // Check WebP: RIFF header + WEBP at offset 8
        if dataCount >= 12 && bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46
            && bytes[3] == 0x46
            && bytes[8] == 0x57 && bytes[9] == 0x45 && bytes[10] == 0x42 && bytes[11] == 0x50
        {
            return "image/webp"
        }

        // Check HEIC/HEIF/AVIF: ISO Base Media File Format with 'ftyp' box
        if dataCount >= 12 && bytes[4] == 0x66 && bytes[5] == 0x74 && bytes[6] == 0x79
            && bytes[7] == 0x70
        {
            return detectHEICVariant(from: bytes, dataCount: dataCount)
        }

        // Try platform-specific MIME detection as fallback
        #if canImport(UniformTypeIdentifiers)
            return detectMimeTypeUsingPlatformAPI(from: data)
        #else
            return nil
        #endif
    }

    /// Detects HEIC/AVIF variants from the ftyp box brand bytes
    private static func detectHEICVariant(from bytes: [UInt8], dataCount: Int) -> String? {
        guard dataCount >= 16 else { return nil }

        let brandBytes = (bytes[8], bytes[9], bytes[10], bytes[11])
        switch brandBytes {
        case (0x68, 0x65, 0x69, 0x63), (0x68, 0x65, 0x69, 0x78), (0x68, 0x65, 0x76, 0x63),
            (0x68, 0x65, 0x76, 0x78),
            (0x6d, 0x69, 0x66, 0x31), (0x6d, 0x73, 0x66, 0x31):
            return "image/heic"
        case (0x61, 0x76, 0x69, 0x66), (0x61, 0x76, 0x69, 0x73):
            return "image/avif"
        default:
            // Check compatible brands if available
            if dataCount >= 20 {
                let compatibleBrand1 = (bytes[12], bytes[13], bytes[14], bytes[15])
                let compatibleBrand2 = (bytes[16], bytes[17], bytes[18], bytes[19])

                if compatibleBrand1 == (0x68, 0x65, 0x69, 0x63)
                    || compatibleBrand1 == (0x61, 0x76, 0x69, 0x66)
                    || compatibleBrand2 == (0x68, 0x65, 0x69, 0x63)
                    || compatibleBrand2 == (0x61, 0x76, 0x69, 0x66)
                {
                    return compatibleBrand1 == (0x61, 0x76, 0x69, 0x66)
                        || compatibleBrand1 == (0x61, 0x76, 0x69, 0x73)
                        || compatibleBrand2 == (0x61, 0x76, 0x69, 0x66)
                        || compatibleBrand2 == (0x61, 0x76, 0x69, 0x73)
                        ? "image/avif" : "image/heic"
                }
            }
            return nil
        }
    }

    /// Detects MIME type using CGImageSource for in-memory processing
    private static func detectMimeTypeUsingImageSource(from data: Data) -> String? {
        #if canImport(UIKit) || canImport(AppKit)
            // Create CFData from Data for CoreGraphics compatibility
            let cfData: CFData? = data.withUnsafeBytes { buffer in
                guard let baseAddress = buffer.baseAddress else { return nil }
                return CFDataCreate(
                    kCFAllocatorDefault, baseAddress.assumingMemoryBound(to: UInt8.self),
                    data.count)
            }
            guard let cfData = cfData else { return nil }

            // Create image source from data
            guard let imageSource = CGImageSourceCreateWithData(cfData, nil) else { return nil }

            // Get the UTI type identifier from the image source
            guard let uti = CGImageSourceGetType(imageSource) as String? else { return nil }

            // Convert UTI to MIME type
            return mapUTIToMIMEType(uti)
        #else
            return nil
        #endif
    }

    /// Maps a UTI string to its corresponding MIME type
    private static func mapUTIToMIMEType(_ uti: String) -> String? {
        // Direct UTI to MIME mapping for common types
        let utiMappings: [String: String] = [
            "public.jpeg": "image/jpeg",
            "public.jpg": "image/jpeg",
            "public.png": "image/png",
            "com.compuserve.gif": "image/gif",
            "org.webmproject.webp": "image/webp",
            "com.microsoft.bmp": "image/bmp",
            "public.tiff": "image/tiff",
            "public.heic": "image/heic",
            "public.heif": "image/heic",
            "public.avif": "image/avif",
        ]

        // Check direct mappings first
        if let mimeType = utiMappings[uti] {
            return mimeType
        }

        // Try UTType-based mapping if available
        #if canImport(UniformTypeIdentifiers)
            if let type = UTType(uti) {
                return mapUTTypeToMIMEType(type)
            }
        #endif

        // For unknown UTIs, try to extract MIME type if it looks like one
        if uti.hasPrefix("public.") && uti.contains("image") {
            let mimeEquivalent = uti.replacingOccurrences(of: "public.", with: "image/")
            if mimeEquivalent != uti {
                return mimeEquivalent
            }
        }
        return nil
    }

    /// Maps a UTType to its corresponding MIME type
    private static func mapUTTypeToMIMEType(_ type: UTType) -> String? {
        if type.conforms(to: UTType.jpeg) {
            return "image/jpeg"
        } else if type.conforms(to: UTType.png) {
            return "image/png"
        } else if type.conforms(to: UTType.gif) {
            return "image/gif"
        } else if type.conforms(to: UTType.webP) {
            return "image/webp"
        } else if type.conforms(to: UTType.bmp) {
            return "image/bmp"
        } else if type.conforms(to: UTType.tiff) {
            return "image/tiff"
        } else if type.conforms(to: UTType.heic) || type.conforms(to: UTType.heif) {
            return "image/heic"
        }
        return nil
    }

    /// Detects MIME type using platform-specific APIs (UniformTypeIdentifiers)
    /// - Parameter data: The data to analyze for MIME type detection
    /// - Returns: Detected MIME type string, or nil if detection fails
    private static func detectMimeTypeUsingPlatformAPI(from data: Data) -> String? {
        #if canImport(UniformTypeIdentifiers)
            // Create a temporary file URL to use with UTType
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("tmp")

            do {
                // Write data to temporary file
                try data.write(to: tempURL)

                // Use UTType to detect the file type
                if let type = UTType(filenameExtension: tempURL.pathExtension) {
                    // Try to get MIME type from UTType
                    return type.preferredMIMEType
                }

                // Fallback: try to create UTType from the file URL
                if let type = UTType(filenameExtension: tempURL.pathExtension) {
                    return type.preferredMIMEType
                }

                // Clean up temporary file
                try? FileManager.default.removeItem(at: tempURL)

            } catch {
                // Clean up temporary file on error
                try? FileManager.default.removeItem(at: tempURL)
            }
        #endif
        return nil
    }
}
