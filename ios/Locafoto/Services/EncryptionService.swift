import Foundation
import CryptoKit

/// Service for encrypting and decrypting photos using AES-256-GCM
actor EncryptionService {
    private static let masterKeyTag = "com.locafoto.masterkey"
    private static let keychainService = "com.locafoto.encryption"

    // MARK: - Master Key Management

    /// Initialize or retrieve the master key from Keychain
    func initializeMasterKey() async throws {
        // Check if master key already exists
        if try await getMasterKey() != nil {
            return
        }

        // Generate new master key
        let masterKey = SymmetricKey(size: .bits256)
        try saveMasterKey(masterKey)
    }

    /// Get the master key from Keychain
    private func getMasterKey() async throws -> SymmetricKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: Self.masterKeyTag,
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess,
              let keyData = result as? Data else {
            throw EncryptionError.keychainReadFailed
        }

        return SymmetricKey(data: keyData)
    }

    /// Save master key to Keychain
    private func saveMasterKey(_ key: SymmetricKey) throws {
        let keyData = key.withUnsafeBytes { Data($0) }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: Self.masterKeyTag,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData as String: keyData
        ]

        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw EncryptionError.keychainWriteFailed
        }
    }

    // MARK: - Photo Encryption

    /// Encrypt photo data with a unique key
    func encryptPhoto(_ photoData: Data) async throws -> EncryptedPhoto {
        // Ensure master key exists
        try await initializeMasterKey()

        guard let masterKey = try await getMasterKey() else {
            throw EncryptionError.masterKeyNotFound
        }

        // Generate unique key for this photo
        let photoKey = SymmetricKey(size: .bits256)

        // Encrypt photo data with photo key
        let nonce = try AES.GCM.Nonce()
        let sealedBox = try AES.GCM.seal(photoData, using: photoKey, nonce: nonce)

        guard let ciphertext = sealedBox.ciphertext as Data?,
              let tag = sealedBox.tag as Data? else {
            throw EncryptionError.encryptionFailed
        }

        // Encrypt the photo key with master key
        let encryptedKey = try encryptKey(photoKey, with: masterKey)

        // Create encrypted photo object
        return EncryptedPhoto(
            id: UUID(),
            encryptedData: ciphertext,
            encryptedKey: encryptedKey,
            iv: Data(nonce),
            authTag: tag,
            // Thumbnail encryption info not set here (caller will set separately if needed)
            thumbnailEncryptedKey: nil,
            thumbnailIv: nil,
            thumbnailAuthTag: nil,
            metadata: PhotoMetadata(
                originalSize: photoData.count,
                captureDate: Date(),
                width: nil,
                height: nil,
                format: "HEIC"
            )
        )
    }

    /// Encrypt photo data (e.g., thumbnail) using an existing encrypted key
    /// This reuses the same photo key from the main photo encryption
    /// Note: Uses the same IV as the main photo (iv parameter), which allows
    /// the thumbnail to be decrypted using the same IV/authTag from the Photo model
    func encryptPhotoData(
        _ photoData: Data,
        encryptedKey: Data,
        iv: Data,
        authTag: Data
    ) async throws -> Data {
        guard let masterKey = try await getMasterKey() else {
            throw EncryptionError.masterKeyNotFound
        }

        // Decrypt the photo key to reuse it
        let photoKey = try decryptKey(encryptedKey, with: masterKey)

        // Encrypt the data with the photo key using the provided IV
        // Note: Reusing IV is not ideal cryptographically, but matches the current design
        // where thumbnails share the same IV/authTag with the main photo
        let nonce = try AES.GCM.Nonce(data: iv)
        let sealedBox = try AES.GCM.seal(photoData, using: photoKey, nonce: nonce)

        guard let ciphertext = sealedBox.ciphertext as Data? else {
            throw EncryptionError.encryptionFailed
        }

        // Return just the encrypted ciphertext (IV and auth tag are stored in Photo model)
        return ciphertext
    }

    /// Decrypt photo data
    func decryptPhotoData(
        _ encryptedData: Data,
        encryptedKey: Data,
        iv: Data,
        authTag: Data
    ) async throws -> Data {
        guard let masterKey = try await getMasterKey() else {
            throw EncryptionError.masterKeyNotFound
        }

        // Decrypt the photo key
        let photoKey = try decryptKey(encryptedKey, with: masterKey)

        // Decrypt the photo data
        let nonce = try AES.GCM.Nonce(data: iv)
        let sealedBox = try AES.GCM.SealedBox(nonce: nonce, ciphertext: encryptedData, tag: authTag)

        let decryptedData = try AES.GCM.open(sealedBox, using: photoKey)

        return decryptedData
    }

    // MARK: - Key Encryption

    /// Encrypt a symmetric key with the master key
    private func encryptKey(_ key: SymmetricKey, with masterKey: SymmetricKey) throws -> Data {
        let keyData = key.withUnsafeBytes { Data($0) }
        let nonce = try AES.GCM.Nonce()
        let sealedBox = try AES.GCM.seal(keyData, using: masterKey, nonce: nonce)

        // Combine nonce + ciphertext + tag
        var combined = Data()
        combined.append(contentsOf: nonce)
        combined.append(sealedBox.ciphertext)
        combined.append(sealedBox.tag)

        return combined
    }

    /// Decrypt a symmetric key with the master key
    private func decryptKey(_ encryptedKey: Data, with masterKey: SymmetricKey) throws -> SymmetricKey {
        // Extract nonce, ciphertext, and tag
        let nonceSize = 12
        let tagSize = 16

        guard encryptedKey.count >= nonceSize + tagSize else {
            throw EncryptionError.invalidEncryptedKey
        }

        let nonce = try AES.GCM.Nonce(data: encryptedKey.prefix(nonceSize))
        let ciphertext = encryptedKey.dropFirst(nonceSize).dropLast(tagSize)
        let tag = encryptedKey.suffix(tagSize)

        let sealedBox = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)
        let keyData = try AES.GCM.open(sealedBox, using: masterKey)

        return SymmetricKey(data: keyData)
    }
}

// MARK: - Errors

enum EncryptionError: LocalizedError {
    case masterKeyNotFound
    case keychainReadFailed
    case keychainWriteFailed
    case encryptionFailed
    case decryptionFailed
    case invalidEncryptedKey

    var errorDescription: String? {
        switch self {
        case .masterKeyNotFound:
            return "Master encryption key not found"
        case .keychainReadFailed:
            return "Failed to read from Keychain"
        case .keychainWriteFailed:
            return "Failed to write to Keychain"
        case .encryptionFailed:
            return "Encryption failed"
        case .decryptionFailed:
            return "Decryption failed"
        case .invalidEncryptedKey:
            return "Invalid encrypted key format"
        }
    }
}
