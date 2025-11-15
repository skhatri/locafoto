import Foundation

/// Represents an imported .lfs file
struct LFSImportedFile: Identifiable, Codable {
    let id: UUID
    let photoId: UUID  // Reference to the Photo in gallery
    let keyName: String  // Which key was used to decrypt
    let originalFilename: String?
    let importDate: Date
    let fileSize: Int64
}

/// Service for tracking .lfs file imports and key usage
actor LFSFileTrackingService {
    private let fileManager = FileManager.default

    /// Get the tracking directory
    private var trackingDirectory: URL {
        get throws {
            let appSupport = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )

            let trackingDir = appSupport.appendingPathComponent("Locafoto/LFSTracking")

            if !fileManager.fileExists(atPath: trackingDir.path) {
                try fileManager.createDirectory(at: trackingDir, withIntermediateDirectories: true)
            }

            return trackingDir
        }
    }

    /// Track an imported .lfs file
    func trackImport(photoId: UUID, keyName: String, originalFilename: String?, fileSize: Int64) async throws {
        let file = LFSImportedFile(
            id: UUID(),
            photoId: photoId,
            keyName: keyName,
            originalFilename: originalFilename,
            importDate: Date(),
            fileSize: fileSize
        )

        let trackingDir = try trackingDirectory
        let fileURL = trackingDir.appendingPathComponent("\(file.id.uuidString).json")

        let encoder = JSONEncoder()
        let data = try encoder.encode(file)
        try data.write(to: fileURL)
    }

    /// Get all imported .lfs files
    func getAllImports() async throws -> [LFSImportedFile] {
        let trackingDir = try trackingDirectory

        guard fileManager.fileExists(atPath: trackingDir.path) else {
            return []
        }

        let files = try fileManager.contentsOfDirectory(at: trackingDir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }

        var imports: [LFSImportedFile] = []
        for fileURL in files {
            let data = try Data(contentsOf: fileURL)
            let file = try JSONDecoder().decode(LFSImportedFile.self, from: data)
            imports.append(file)
        }

        return imports.sorted { $0.importDate > $1.importDate }
    }

    /// Get imports for a specific key
    func getImports(forKey keyName: String) async throws -> [LFSImportedFile] {
        let allImports = try await getAllImports()
        return allImports.filter { $0.keyName == keyName }
    }

    /// Get count of files using a specific key
    func getUsageCount(forKey keyName: String) async throws -> Int {
        let imports = try await getImports(forKey: keyName)
        return imports.count
    }

    /// Delete tracking for a file
    func deleteTracking(fileId: UUID) async throws {
        let trackingDir = try trackingDirectory
        let fileURL = trackingDir.appendingPathComponent("\(fileId.uuidString).json")

        if fileManager.fileExists(atPath: fileURL.path) {
            try fileManager.removeItem(at: fileURL)
        }
    }

    /// Delete tracking by photo ID
    func deleteTracking(byPhotoId photoId: UUID) async throws {
        let allImports = try await getAllImports()

        for file in allImports where file.photoId == photoId {
            try await deleteTracking(fileId: file.id)
        }
    }

    /// Get total statistics
    func getStatistics() async throws -> LFSStatistics {
        let imports = try await getAllImports()
        let totalFiles = imports.count
        let totalSize = imports.reduce(0) { $0 + $1.fileSize }

        // Count unique keys
        let uniqueKeys = Set(imports.map { $0.keyName })

        return LFSStatistics(
            totalFiles: totalFiles,
            totalSize: totalSize,
            uniqueKeys: uniqueKeys.count
        )
    }
}

struct LFSStatistics {
    let totalFiles: Int
    let totalSize: Int64
    let uniqueKeys: Int
}
