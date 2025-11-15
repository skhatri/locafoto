import UIKit

/// Utility for generating thumbnails from image data
/// Includes proper memory management and error handling
enum ThumbnailGenerator {

    /// Generate a thumbnail from image data
    /// - Parameters:
    ///   - data: The original image data
    ///   - size: Maximum dimension for the thumbnail (default: 200)
    ///   - compressionQuality: JPEG compression quality (default: 0.8)
    /// - Returns: Thumbnail image data as JPEG
    /// - Throws: ThumbnailError if generation fails
    static func generate(
        from data: Data,
        size: CGFloat = 200,
        compressionQuality: CGFloat = 0.8
    ) throws -> Data {
        // Validate input
        guard !data.isEmpty else {
            throw ThumbnailError.emptyData
        }

        guard compressionQuality >= 0 && compressionQuality <= 1 else {
            throw ThumbnailError.invalidCompressionQuality
        }

        // Create image from data
        guard let image = UIImage(data: data) else {
            throw ThumbnailError.invalidImageData
        }

        // Calculate thumbnail size maintaining aspect ratio
        let scale = size / max(image.size.width, image.size.height)
        let newSize = CGSize(
            width: image.size.width * scale,
            height: image.size.height * scale
        )

        // Generate thumbnail with proper cleanup
        defer {
            // Ensure graphics context is always cleaned up
            UIGraphicsEndImageContext()
        }

        UIGraphicsBeginImageContextWithOptions(newSize, true, 1.0)
        image.draw(in: CGRect(origin: .zero, size: newSize))

        guard let thumbnail = UIGraphicsGetImageFromCurrentImageContext() else {
            throw ThumbnailError.renderingFailed
        }

        guard let jpegData = thumbnail.jpegData(compressionQuality: compressionQuality) else {
            throw ThumbnailError.compressionFailed
        }

        return jpegData
    }
}

// MARK: - Errors

enum ThumbnailError: LocalizedError {
    case emptyData
    case invalidImageData
    case invalidCompressionQuality
    case renderingFailed
    case compressionFailed

    var errorDescription: String? {
        switch self {
        case .emptyData:
            return "Image data is empty"
        case .invalidImageData:
            return "Cannot create image from data"
        case .invalidCompressionQuality:
            return "Compression quality must be between 0 and 1"
        case .renderingFailed:
            return "Failed to render thumbnail"
        case .compressionFailed:
            return "Failed to compress thumbnail as JPEG"
        }
    }
}
