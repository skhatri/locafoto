import Foundation

/// Media type for photos and videos
enum MediaType: String, Codable {
    case photo
    case video
}

/// Photo model representing an encrypted photo or video
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

    // Media properties
    var width: Int32?
    var height: Int32?
    var format: String
    var mediaType: MediaType
    var duration: Double?  // Video duration in seconds

    // Location data
    var latitude: Double?
    var longitude: Double?

    // File paths
    var filePath: String
    var thumbnailPath: String?

    // Organization
    var albumId: UUID  // Every photo belongs to exactly one album
    var tags: [String]
    var isFavorite: Bool
    var isHidden: Bool

    /// Computed property to detect actual media type (handles legacy data)
    var effectiveMediaType: MediaType {
        if mediaType == .video {
            return .video
        }
        // Fallback: detect by format for legacy data
        let videoFormats = ["mp4", "mov", "m4v", "avi", "mkv", "webm", "3gp", "video"]
        if videoFormats.contains(format.lowercased()) {
            return .video
        }
        return .photo
    }

    // Memberwise initializer (required since we have custom decoder)
    init(id: UUID, encryptedKeyData: Data, ivData: Data, authTagData: Data,
         thumbnailEncryptedKeyData: Data? = nil, thumbnailIvData: Data? = nil, thumbnailAuthTagData: Data? = nil,
         captureDate: Date, importDate: Date, modifiedDate: Date,
         originalSize: Int64, encryptedSize: Int64,
         width: Int32? = nil, height: Int32? = nil, format: String,
         mediaType: MediaType = .photo, duration: Double? = nil,
         latitude: Double? = nil, longitude: Double? = nil,
         filePath: String, thumbnailPath: String? = nil,
         albumId: UUID, tags: [String], isFavorite: Bool, isHidden: Bool) {
        self.id = id
        self.encryptedKeyData = encryptedKeyData
        self.ivData = ivData
        self.authTagData = authTagData
        self.thumbnailEncryptedKeyData = thumbnailEncryptedKeyData
        self.thumbnailIvData = thumbnailIvData
        self.thumbnailAuthTagData = thumbnailAuthTagData
        self.captureDate = captureDate
        self.importDate = importDate
        self.modifiedDate = modifiedDate
        self.originalSize = originalSize
        self.encryptedSize = encryptedSize
        self.width = width
        self.height = height
        self.format = format
        self.mediaType = mediaType
        self.duration = duration
        self.latitude = latitude
        self.longitude = longitude
        self.filePath = filePath
        self.thumbnailPath = thumbnailPath
        self.albumId = albumId
        self.tags = tags
        self.isFavorite = isFavorite
        self.isHidden = isHidden
    }

    // Custom decoder for backward compatibility with existing photos
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(UUID.self, forKey: .id)
        encryptedKeyData = try container.decode(Data.self, forKey: .encryptedKeyData)
        ivData = try container.decode(Data.self, forKey: .ivData)
        authTagData = try container.decode(Data.self, forKey: .authTagData)
        thumbnailEncryptedKeyData = try container.decodeIfPresent(Data.self, forKey: .thumbnailEncryptedKeyData)
        thumbnailIvData = try container.decodeIfPresent(Data.self, forKey: .thumbnailIvData)
        thumbnailAuthTagData = try container.decodeIfPresent(Data.self, forKey: .thumbnailAuthTagData)
        captureDate = try container.decode(Date.self, forKey: .captureDate)
        importDate = try container.decode(Date.self, forKey: .importDate)
        modifiedDate = try container.decode(Date.self, forKey: .modifiedDate)
        originalSize = try container.decode(Int64.self, forKey: .originalSize)
        encryptedSize = try container.decode(Int64.self, forKey: .encryptedSize)
        width = try container.decodeIfPresent(Int32.self, forKey: .width)
        height = try container.decodeIfPresent(Int32.self, forKey: .height)
        format = try container.decode(String.self, forKey: .format)

        // Backward compatibility: default to .photo if not present
        mediaType = try container.decodeIfPresent(MediaType.self, forKey: .mediaType) ?? .photo
        duration = try container.decodeIfPresent(Double.self, forKey: .duration)

        // Location data (optional for backward compatibility)
        latitude = try container.decodeIfPresent(Double.self, forKey: .latitude)
        longitude = try container.decodeIfPresent(Double.self, forKey: .longitude)

        filePath = try container.decode(String.self, forKey: .filePath)
        thumbnailPath = try container.decodeIfPresent(String.self, forKey: .thumbnailPath)
        albumId = try container.decode(UUID.self, forKey: .albumId)
        tags = try container.decode([String].self, forKey: .tags)
        isFavorite = try container.decode(Bool.self, forKey: .isFavorite)
        isHidden = try container.decode(Bool.self, forKey: .isHidden)
    }
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
    let mediaType: MediaType
    let duration: Double?  // Video duration in seconds
    let latitude: Double?
    let longitude: Double?

    init(originalSize: Int, captureDate: Date, width: Int?, height: Int?, format: String, mediaType: MediaType = .photo, duration: Double? = nil, latitude: Double? = nil, longitude: Double? = nil) {
        self.originalSize = originalSize
        self.captureDate = captureDate
        self.width = width
        self.height = height
        self.format = format
        self.mediaType = mediaType
        self.duration = duration
        self.latitude = latitude
        self.longitude = longitude
    }
}
