import Foundation

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
