import Foundation

/// LFS (Locafoto Shared) file format specification
///
/// File Structure:
/// ┌─────────────────────────────────────┐
/// │ Header (128 bytes)                  │
/// │ - Key Name (UTF-8 string)           │
/// │   Points to key file in app data    │
/// ├─────────────────────────────────────┤
/// │ Encrypted Data (variable size)      │
/// │ - AES-256-GCM encrypted content     │
/// ├─────────────────────────────────────┤
/// │ IV/Nonce (12 bytes)                 │
/// ├─────────────────────────────────────┤
/// │ Authentication Tag (16 bytes)       │
/// └─────────────────────────────────────┘

struct LFSFile {
    static let headerSize = 128
    static let nonceSize = 12
    static let tagSize = 16

    let keyName: String
    let encryptedData: Data
    let nonce: Data
    let tag: Data

    /// Parse an LFS file from data
    static func parse(from data: Data) throws -> LFSFile {
        guard data.count >= headerSize + nonceSize + tagSize else {
            throw LFSError.invalidFormat
        }

        // Extract key name from first 128 bytes
        let keyNameData = data.prefix(headerSize)
        guard let keyName = String(data: keyNameData, encoding: .utf8)?
            .trimmingCharacters(in: .controlCharacters)
            .trimmingCharacters(in: .whitespaces) else {
            throw LFSError.invalidKeyName
        }

        // Extract encrypted data, nonce, and tag
        let contentStart = headerSize
        let nonceStart = data.count - nonceSize - tagSize
        let tagStart = data.count - tagSize

        let encryptedData = data[contentStart..<nonceStart]
        let nonce = data[nonceStart..<tagStart]
        let tag = data[tagStart...]

        return LFSFile(
            keyName: keyName,
            encryptedData: encryptedData,
            nonce: nonce,
            tag: tag
        )
    }

    /// Create LFS file data for export
    static func create(keyName: String, encryptedData: Data, nonce: Data, tag: Data) throws -> Data {
        var fileData = Data()

        // Create 128-byte header with key name
        var keyNameData = keyName.data(using: .utf8) ?? Data()
        if keyNameData.count > headerSize {
            throw LFSError.keyNameTooLong
        }

        // Pad to 128 bytes with zeros
        while keyNameData.count < headerSize {
            keyNameData.append(0)
        }

        fileData.append(keyNameData)
        fileData.append(encryptedData)
        fileData.append(nonce)
        fileData.append(tag)

        return fileData
    }
}

/// Key file structure
struct KeyFile: Identifiable, Codable {
    let id: UUID
    let name: String
    let createdDate: Date
    let encryptedKeyData: Data  // Key encrypted with master key
    var usageCount: Int
    var lastUsed: Date?

    /// The filename used for storage
    var filename: String {
        "\(id.uuidString).key"
    }
}

enum LFSError: LocalizedError {
    case invalidFormat
    case invalidKeyName
    case keyNameTooLong
    case keyNotFound
    case decryptionFailed

    var errorDescription: String? {
        switch self {
        case .invalidFormat:
            return "Invalid LFS file format"
        case .invalidKeyName:
            return "Invalid key name in LFS file"
        case .keyNameTooLong:
            return "Key name exceeds 128 bytes"
        case .keyNotFound:
            return "Encryption key not found"
        case .decryptionFailed:
            return "Failed to decrypt file"
        }
    }
}
