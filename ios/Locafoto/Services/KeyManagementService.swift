import Foundation
import CryptoKit

/// Service for managing encryption keys with PIN-based master key
actor KeyManagementService {
    private static let keysDirectory = "Keys"
    private static let masterKeyTag = "com.locafoto.pin.masterkey"
    private static let pinSaltTag = "com.locafoto.pin.salt"

    private let fileManager = FileManager.default

    // MARK: - Master Key (PIN-based)

    /// Initialize master key from PIN
    /// This should be called when user sets up PIN for first time
    func initializeMasterKey(pin: String) async throws {
        // Validate PIN
        try validatePin(pin)

        // Generate a random salt for PIN derivation
        var salt = Data(count: 32)
        _ = salt.withUnsafeMutableBytes { saltBytes in
            SecRandomCopyBytes(kSecRandomDefault, 32, saltBytes.baseAddress!)
        }

        // Save salt to keychain
        try savePinSalt(salt)

        // Derive master key from PIN + salt
        let masterKey = try deriveMasterKey(from: pin, salt: salt)

        // Save master key to memory (not persisted - derived from PIN each time)
        // For now, we'll re-derive it each time it's needed
    }

    /// Derive master key from PIN and salt using PBKDF2
    private func deriveMasterKey(from pin: String, salt: Data) throws -> SymmetricKey {
        guard let pinData = pin.data(using: .utf8) else {
            throw KeyManagementError.invalidPin
        }

        // Use PBKDF2 with 100,000 iterations for strong key derivation
        let iterations = 100_000

        var derivedKeyData = Data(count: 32) // 256 bits
        let result = derivedKeyData.withUnsafeMutableBytes { derivedKeyBytes in
            salt.withUnsafeBytes { saltBytes in
                pinData.withUnsafeBytes { pinBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        pinBytes.baseAddress?.assumingMemoryBound(to: Int8.self),
                        pinData.count,
                        saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        UInt32(iterations),
                        derivedKeyBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        32
                    )
                }
            }
        }

        guard result == kCCSuccess else {
            throw KeyManagementError.keyDerivationFailed
        }

        return SymmetricKey(data: derivedKeyData)
    }

    /// Verify PIN by attempting to derive key and decrypt a test key
    func verifyPin(_ pin: String) async throws -> Bool {
        // Validate PIN
        try validatePin(pin)

        let salt = try getPinSalt()
        let masterKey = try deriveMasterKey(from: pin, salt: salt)

        // Try to decrypt a known key to verify PIN is correct
        let keys = try await loadAllKeys()
        guard let testKey = keys.first else {
            // No keys exist yet, PIN is valid by default
            return true
        }

        // Try to decrypt the key - if it fails, PIN is wrong
        do {
            _ = try await decryptKey(testKey.encryptedKeyData, with: masterKey)
            return true
        } catch {
            return false
        }
    }

    /// Get master key from PIN
    func getMasterKey(pin: String) async throws -> SymmetricKey {
        // Validate PIN
        try validatePin(pin)

        let salt = try getPinSalt()
        return try deriveMasterKey(from: pin, salt: salt)
    }

    // MARK: - Key Management

    /// Create a new encryption key
    func createKey(name: String, pin: String) async throws -> KeyFile {
        // Validate inputs
        try validatePin(pin)
        try await validateKeyName(name)

        let masterKey = try await getMasterKey(pin: pin)

        // Generate new random key
        let encryptionKey = SymmetricKey(size: .bits256)

        // Encrypt the key with master key
        let encryptedKeyData = try encryptKey(encryptionKey, with: masterKey)

        // Create key file metadata
        let keyFile = KeyFile(
            id: UUID(),
            name: name,
            createdDate: Date(),
            encryptedKeyData: encryptedKeyData,
            usageCount: 0,
            lastUsed: nil
        )

        // Save key file
        try await saveKeyFile(keyFile)

        return keyFile
    }

    /// Import a key that was shared externally
    func importKey(name: String, keyData: Data, pin: String) async throws -> KeyFile {
        // Validate inputs
        try validatePin(pin)
        try await validateKeyName(name)
        try validateKeyData(keyData)

        let masterKey = try await getMasterKey(pin: pin)

        // Create symmetric key from data
        let encryptionKey = SymmetricKey(data: keyData)

        // Encrypt the key with master key
        let encryptedKeyData = try encryptKey(encryptionKey, with: masterKey)

        // Create key file metadata
        let keyFile = KeyFile(
            id: UUID(),
            name: name,
            createdDate: Date(),
            encryptedKeyData: encryptedKeyData,
            usageCount: 0,
            lastUsed: nil
        )

        // Save key file
        try await saveKeyFile(keyFile)

        return keyFile
    }

    /// Get an encryption key by name
    func getKey(byName name: String, pin: String) async throws -> SymmetricKey {
        let masterKey = try await getMasterKey(pin: pin)
        let keyFile = try await loadKeyFile(byName: name)

        // Decrypt the key
        let encryptionKey = try await decryptKey(keyFile.encryptedKeyData, with: masterKey)

        // Update usage statistics
        var updatedKeyFile = keyFile
        updatedKeyFile.usageCount += 1
        updatedKeyFile.lastUsed = Date()
        try await saveKeyFile(updatedKeyFile)

        return encryptionKey
    }

    /// Get an encryption key by ID
    func getKey(byId id: UUID, pin: String) async throws -> SymmetricKey {
        let masterKey = try await getMasterKey(pin: pin)
        let keyFile = try await loadKeyFile(byId: id)

        // Decrypt the key
        return try await decryptKey(keyFile.encryptedKeyData, with: masterKey)
    }

    /// Load all key files
    func loadAllKeys() async throws -> [KeyFile] {
        let keysDir = try getKeysDirectory()

        guard fileManager.fileExists(atPath: keysDir.path) else {
            return []
        }

        let keyFiles = try fileManager.contentsOfDirectory(at: keysDir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "key" }

        var keys: [KeyFile] = []
        for keyFileURL in keyFiles {
            let data = try Data(contentsOf: keyFileURL)
            let keyFile = try JSONDecoder().decode(KeyFile.self, from: data)
            keys.append(keyFile)
        }

        return keys.sorted { $0.createdDate > $1.createdDate }
    }

    /// Delete a key
    func deleteKey(_ id: UUID) async throws {
        let keysDir = try getKeysDirectory()
        let keyFileURL = keysDir.appendingPathComponent("\(id.uuidString).key")

        try fileManager.removeItem(at: keyFileURL)
    }

    // MARK: - Validation

    /// Validate PIN meets security requirements
    private func validatePin(_ pin: String) throws {
        guard !pin.isEmpty else {
            throw KeyManagementError.invalidPin
        }

        guard pin.count >= 4 else {
            throw KeyManagementError.pinTooShort
        }

        guard pin.count <= 32 else {
            throw KeyManagementError.pinTooLong
        }
    }

    /// Validate key name meets requirements
    private func validateKeyName(_ name: String) async throws {
        guard !name.isEmpty else {
            throw KeyManagementError.invalidKeyName
        }

        guard name.count <= 64 else {
            throw KeyManagementError.keyNameTooLong
        }

        // Check for path traversal and invalid filename characters
        let invalidCharacters = CharacterSet(charactersIn: "/\\")
        if name.rangeOfCharacter(from: invalidCharacters) != nil || name.contains("..") {
            throw KeyManagementError.keyNameContainsInvalidCharacters
        }

        // Check for control characters
        let controlCharacters = CharacterSet.controlCharacters
        if name.rangeOfCharacter(from: controlCharacters) != nil {
            throw KeyManagementError.keyNameContainsInvalidCharacters
        }

        // Check for duplicate names
        let existingKeys = try await loadAllKeys()
        if existingKeys.contains(where: { $0.name == name }) {
            throw KeyManagementError.duplicateKeyName
        }
    }

    /// Validate key data is correct size for AES-256
    private func validateKeyData(_ keyData: Data) throws {
        guard keyData.count == 32 else {
            throw KeyManagementError.invalidKeyData
        }
    }

    // MARK: - Private Helpers

    private func getKeysDirectory() throws -> URL {
        let appSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        let keysDir = appSupport.appendingPathComponent("Locafoto/Keys")

        if !fileManager.fileExists(atPath: keysDir.path) {
            try fileManager.createDirectory(at: keysDir, withIntermediateDirectories: true)
        }

        return keysDir
    }

    private func saveKeyFile(_ keyFile: KeyFile) async throws {
        let keysDir = try getKeysDirectory()
        let fileURL = keysDir.appendingPathComponent(keyFile.filename)

        let encoder = JSONEncoder()
        let data = try encoder.encode(keyFile)
        try data.write(to: fileURL)
    }

    private func loadKeyFile(byName name: String) async throws -> KeyFile {
        let keys = try await loadAllKeys()
        guard let keyFile = keys.first(where: { $0.name == name }) else {
            throw KeyManagementError.keyNotFound
        }
        return keyFile
    }

    private func loadKeyFile(byId id: UUID) async throws -> KeyFile {
        let keysDir = try getKeysDirectory()
        let fileURL = keysDir.appendingPathComponent("\(id.uuidString).key")

        guard fileManager.fileExists(atPath: fileURL.path) else {
            throw KeyManagementError.keyNotFound
        }

        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(KeyFile.self, from: data)
    }

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

    private func decryptKey(_ encryptedKey: Data, with masterKey: SymmetricKey) async throws -> SymmetricKey {
        let nonceSize = 12
        let tagSize = 16

        guard encryptedKey.count >= nonceSize + tagSize else {
            throw KeyManagementError.invalidEncryptedKey
        }

        let nonce = try AES.GCM.Nonce(data: encryptedKey.prefix(nonceSize))
        let ciphertext = encryptedKey.dropFirst(nonceSize).dropLast(tagSize)
        let tag = encryptedKey.suffix(tagSize)

        let sealedBox = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)
        let keyData = try AES.GCM.open(sealedBox, using: masterKey)

        return SymmetricKey(data: keyData)
    }

    // MARK: - Keychain Helpers for PIN Salt

    private func savePinSalt(_ salt: Data) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.pinSaltTag,
            kSecAttrAccount as String: "salt",
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecValueData as String: salt
        ]

        // Delete existing first
        SecItemDelete(query as CFDictionary)

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeyManagementError.keychainWriteFailed
        }
    }

    private func getPinSalt() throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.pinSaltTag,
            kSecAttrAccount as String: "salt",
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let saltData = result as? Data else {
            throw KeyManagementError.pinNotSet
        }

        return saltData
    }

    /// Check if PIN has been set up
    func isPinSet() async -> Bool {
        do {
            _ = try getPinSalt()
            return true
        } catch {
            return false
        }
    }
}

// Import CommonCrypto for PBKDF2
import CommonCrypto

enum KeyManagementError: LocalizedError {
    case invalidPin
    case pinTooShort
    case pinTooLong
    case keyDerivationFailed
    case keyNotFound
    case invalidEncryptedKey
    case keychainWriteFailed
    case pinNotSet
    case invalidKeyName
    case keyNameTooLong
    case keyNameContainsInvalidCharacters
    case duplicateKeyName
    case invalidKeyData

    var errorDescription: String? {
        switch self {
        case .invalidPin:
            return "Invalid PIN"
        case .pinTooShort:
            return "PIN must be at least 4 characters"
        case .pinTooLong:
            return "PIN must be no more than 32 characters"
        case .keyDerivationFailed:
            return "Failed to derive key from PIN"
        case .keyNotFound:
            return "Encryption key not found"
        case .invalidEncryptedKey:
            return "Invalid encrypted key format"
        case .keychainWriteFailed:
            return "Failed to save PIN salt to Keychain"
        case .pinNotSet:
            return "PIN has not been set up"
        case .invalidKeyName:
            return "Key name cannot be empty"
        case .keyNameTooLong:
            return "Key name must be no more than 64 characters"
        case .keyNameContainsInvalidCharacters:
            return "Key name contains invalid characters (/, \\, .., or control characters)"
        case .duplicateKeyName:
            return "A key with this name already exists"
        case .invalidKeyData:
            return "Key data must be exactly 32 bytes (256 bits)"
        }
    }
}
