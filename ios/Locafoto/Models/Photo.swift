import Foundation

/// Photo model representing an encrypted photo
struct Photo: Identifiable, Codable {
    let id: UUID

    // Encryption data
    var encryptedKeyData: Data
    var ivData: Data
    var authTagData: Data

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
