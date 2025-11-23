import Foundation

/// Sorting options for photos within albums
enum PhotoSortOption: String, CaseIterable {
    case captureDateDesc = "capture_desc"
    case captureDateAsc = "capture_asc"
    case importDateDesc = "import_desc"
    case importDateAsc = "import_asc"
    case sizeDesc = "size_desc"
    case sizeAsc = "size_asc"

    var displayName: String {
        switch self {
        case .captureDateDesc: return "Capture Date (Newest)"
        case .captureDateAsc: return "Capture Date (Oldest)"
        case .importDateDesc: return "Import Date (Newest)"
        case .importDateAsc: return "Import Date (Oldest)"
        case .sizeDesc: return "Size (Largest)"
        case .sizeAsc: return "Size (Smallest)"
        }
    }

    var iconName: String {
        switch self {
        case .captureDateDesc, .captureDateAsc: return "camera"
        case .importDateDesc, .importDateAsc: return "square.and.arrow.down"
        case .sizeDesc, .sizeAsc: return "externaldrive"
        }
    }
}

/// Sorting options for albums
enum AlbumSortOption: String, CaseIterable {
    case modifiedDateDesc = "modified_desc"
    case modifiedDateAsc = "modified_asc"
    case createdDateDesc = "created_desc"
    case createdDateAsc = "created_asc"
    case nameAsc = "name_asc"
    case nameDesc = "name_desc"
    case photoCountDesc = "photo_count_desc"
    case photoCountAsc = "photo_count_asc"

    var displayName: String {
        switch self {
        case .modifiedDateDesc: return "Modified (Newest)"
        case .modifiedDateAsc: return "Modified (Oldest)"
        case .createdDateDesc: return "Created (Newest)"
        case .createdDateAsc: return "Created (Oldest)"
        case .nameAsc: return "Name (A-Z)"
        case .nameDesc: return "Name (Z-A)"
        case .photoCountDesc: return "Photos (Most)"
        case .photoCountAsc: return "Photos (Least)"
        }
    }

    var iconName: String {
        switch self {
        case .modifiedDateDesc, .modifiedDateAsc: return "clock.arrow.circlepath"
        case .createdDateDesc, .createdDateAsc: return "calendar"
        case .nameAsc, .nameDesc: return "textformat"
        case .photoCountDesc, .photoCountAsc: return "photo.stack"
        }
    }
}

/// Album model for grouping photos with a key
struct Album: Identifiable, Codable {
    let id: UUID
    var name: String
    var keyName: String  // The encryption key used for this album
    var createdDate: Date
    var modifiedDate: Date
    var isMain: Bool  // Is this the main/default album
    var isPrivate: Bool  // Private albums require Face ID/PIN to access

    // Cached thumbnail photo IDs (first and last photo for overlay effect)
    var firstPhotoId: UUID?
    var lastPhotoId: UUID?
    var photoCount: Int

    init(id: UUID = UUID(), name: String, keyName: String, isMain: Bool = false, isPrivate: Bool = false) {
        self.id = id
        self.name = name
        self.keyName = keyName
        self.createdDate = Date()
        self.modifiedDate = Date()
        self.isMain = isMain
        self.isPrivate = isPrivate
        self.firstPhotoId = nil
        self.lastPhotoId = nil
        self.photoCount = 0
    }

    // Custom decoder for backward compatibility with albums that don't have newer fields
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        keyName = try container.decode(String.self, forKey: .keyName)
        createdDate = try container.decode(Date.self, forKey: .createdDate)
        modifiedDate = try container.decode(Date.self, forKey: .modifiedDate)
        isMain = try container.decode(Bool.self, forKey: .isMain)
        
        // Backward compatibility: if isPrivate is missing, default to false
        isPrivate = try container.decodeIfPresent(Bool.self, forKey: .isPrivate) ?? false
        
        firstPhotoId = try container.decodeIfPresent(UUID.self, forKey: .firstPhotoId)
        lastPhotoId = try container.decodeIfPresent(UUID.self, forKey: .lastPhotoId)
        
        // Backward compatibility: if photoCount is missing, default to 0
        photoCount = try container.decodeIfPresent(Int.self, forKey: .photoCount) ?? 0
    }
}
