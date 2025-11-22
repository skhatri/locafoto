import Foundation

/// Album model for grouping photos with a key
struct Album: Identifiable, Codable {
    let id: UUID
    var name: String
    var keyName: String  // The encryption key used for this album
    var createdDate: Date
    var modifiedDate: Date
    var isMain: Bool  // Is this the main/default album

    // Cached thumbnail photo IDs (first and last photo for overlay effect)
    var firstPhotoId: UUID?
    var lastPhotoId: UUID?
    var photoCount: Int

    init(id: UUID = UUID(), name: String, keyName: String, isMain: Bool = false) {
        self.id = id
        self.name = name
        self.keyName = keyName
        self.createdDate = Date()
        self.modifiedDate = Date()
        self.isMain = isMain
        self.firstPhotoId = nil
        self.lastPhotoId = nil
        self.photoCount = 0
    }
}
