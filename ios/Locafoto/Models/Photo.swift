import Foundation

/// Photo model representing an encrypted photo
struct Photo: Identifiable, Codable {
    let id: UUID

    // Encryption data (for main photo)
    var encryptedKeyData: Data
    var ivData: Data
    var authTagData: Data

    // Thumbnail encryption data (optional for backward compatibility)
    // If nil, thumbnail uses main photo encryption info
    var thumbnailEncryptedKeyData: Data?
    var thumbnailIvData: Data?
    var thumbnailAuthTagData: Data?

    // Timestamps
    var captureDate: Date
    var importDate: Date
    var modifiedDate: Date

    // Size information
    var originalSize: Int64
    var encryptedSize: Int64

    // Image properties
    var width: Int32?
    var height: Int32?
    var format: String

    // File paths
    var filePath: String
    var thumbnailPath: String?

    // Organization
    var albumId: UUID  // Every photo belongs to exactly one album
    var tags: [String]
    var isFavorite: Bool
    var isHidden: Bool
}

/// Encrypted photo data structure
struct EncryptedPhoto {
    let id: UUID
    let encryptedData: Data
    let encryptedKey: Data
    let iv: Data
    let authTag: Data
    
    // Thumbnail encryption info (optional - if nil, thumbnail uses main photo encryption)
    let thumbnailEncryptedKey: Data?
    let thumbnailIv: Data?
    let thumbnailAuthTag: Data?
    
    let metadata: PhotoMetadata
}

/// Photo metadata
struct PhotoMetadata {
    let originalSize: Int
    let captureDate: Date
    let width: Int?
    let height: Int?
    let format: String
}
