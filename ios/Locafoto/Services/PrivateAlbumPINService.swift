import Foundation
import Security
import CryptoKit

/// Service for managing the app PIN used for private album authentication
/// This is separate from the key management PIN
class PrivateAlbumPINService {

    private static let keychainService = "com.locafoto.privatealbum.pin"
    private static let pinKey = "app_pin"
    private static let pinSaltKey = "app_pin_salt"

    enum PINError: LocalizedError {
        case pinNotSet
        case invalidPIN
        case keychainError
        case hashingFailed

        var errorDescription: String? {
            switch self {
            case .pinNotSet:
                return "PIN has not been set up"
            case .invalidPIN:
                return "Invalid PIN"
            case .keychainError:
                return "Failed to access keychain"
            case .hashingFailed:
                return "Failed to hash PIN"
            }
        }
    }

    // MARK: - Public Methods

    /// Check if app PIN has been set up
    func isPINSetUp() -> Bool {
        return loadFromKeychain(key: Self.pinKey) != nil
    }

    /// Set up a new app PIN
    func setPIN(_ pin: String) throws {
        guard pin.count >= 4 && pin.count <= 8 else {
            throw PINError.invalidPIN
        }

        // Generate random salt
        let salt = generateSalt()

        // Hash the PIN with salt
        guard let hashedPIN = hashPIN(pin, salt: salt) else {
            throw PINError.hashingFailed
        }

        // Save to keychain
        try saveToKeychain(data: hashedPIN, key: Self.pinKey)
        try saveToKeychain(data: salt, key: Self.pinSaltKey)
    }

    /// Verify the entered PIN
    func verifyPIN(_ pin: String) -> Bool {
        guard let storedHash = loadFromKeychain(key: Self.pinKey),
              let salt = loadFromKeychain(key: Self.pinSaltKey) else {
            return false
        }

        guard let enteredHash = hashPIN(pin, salt: salt) else {
            return false
        }

        return storedHash == enteredHash
    }

    /// Change the PIN (requires old PIN verification)
    func changePIN(oldPIN: String, newPIN: String) throws {
        guard verifyPIN(oldPIN) else {
            throw PINError.invalidPIN
        }

        try setPIN(newPIN)
    }

    /// Reset PIN (removes all PIN data)
    func resetPIN() {
        deleteFromKeychain(key: Self.pinKey)
        deleteFromKeychain(key: Self.pinSaltKey)
    }

    // MARK: - PIN-Protected Key Storage

    /// Encrypt data with PIN and store in keychain
    func saveWithPINProtection(data: Data, forKey key: String, pin: String) throws {
        guard verifyPIN(pin) else {
            throw PINError.invalidPIN
        }

        // Derive encryption key from PIN
        guard let salt = loadFromKeychain(key: Self.pinSaltKey),
              let encryptionKey = deriveKey(from: pin, salt: salt) else {
            throw PINError.hashingFailed
        }

        // Encrypt the data
        let nonce = try AES.GCM.Nonce()
        let sealedBox = try AES.GCM.seal(data, using: encryptionKey, nonce: nonce)

        // Combine nonce + ciphertext + tag
        var combined = Data()
        combined.append(contentsOf: nonce)
        combined.append(sealedBox.ciphertext)
        combined.append(sealedBox.tag)

        // Save to keychain
        try saveToKeychain(data: combined, key: key)
    }

    /// Load and decrypt data protected by PIN
    func loadWithPINProtection(forKey key: String, pin: String) throws -> Data {
        guard verifyPIN(pin) else {
            throw PINError.invalidPIN
        }

        guard let encryptedData = loadFromKeychain(key: key) else {
            throw PINError.keychainError
        }

        // Derive decryption key from PIN
        guard let salt = loadFromKeychain(key: Self.pinSaltKey),
              let decryptionKey = deriveKey(from: pin, salt: salt) else {
            throw PINError.hashingFailed
        }

        // Extract nonce, ciphertext, and tag
        let nonceSize = 12
        let tagSize = 16

        guard encryptedData.count >= nonceSize + tagSize else {
            throw PINError.keychainError
        }

        let nonce = try AES.GCM.Nonce(data: encryptedData.prefix(nonceSize))
        let ciphertext = encryptedData.dropFirst(nonceSize).dropLast(tagSize)
        let tag = encryptedData.suffix(tagSize)

        let sealedBox = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)
        let decryptedData = try AES.GCM.open(sealedBox, using: decryptionKey)

        return decryptedData
    }

    /// Delete PIN-protected data
    func deleteWithPINProtection(forKey key: String) {
        deleteFromKeychain(key: key)
    }

    /// Check if PIN-protected data exists
    func hasProtectedData(forKey key: String) -> Bool {
        return loadFromKeychain(key: key) != nil
    }

    // MARK: - Private Helpers

    private func generateSalt() -> Data {
        var salt = Data(count: 32)
        _ = salt.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!)
        }
        return salt
    }

    private func hashPIN(_ pin: String, salt: Data) -> Data? {
        guard let pinData = pin.data(using: .utf8) else { return nil }

        var combined = salt
        combined.append(pinData)

        let hash = SHA256.hash(data: combined)
        return Data(hash)
    }

    private func deriveKey(from pin: String, salt: Data) -> SymmetricKey? {
        guard let pinData = pin.data(using: .utf8) else { return nil }

        // Simple key derivation using SHA256
        // In production, consider using PBKDF2 or Argon2
        var combined = salt
        combined.append(pinData)
        combined.append(salt) // Double salt for key derivation

        let hash = SHA256.hash(data: combined)
        return SymmetricKey(data: hash)
    }

    // MARK: - Keychain Operations

    private func saveToKeychain(data: Data, key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: key
        ]

        // Delete existing item
        SecItemDelete(query as CFDictionary)

        // Add new item
        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw PINError.keychainError
        }
    }

    private func loadFromKeychain(key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }

        return data
    }

    private func deleteFromKeychain(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: key
        ]

        SecItemDelete(query as CFDictionary)
    }
}
