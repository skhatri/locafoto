import Foundation
import CryptoKit

/// Service for managing encryption keys for private albums
/// Private album keys are encrypted with biometric (Face ID) or app PIN
class PrivateAlbumKeyService {

    private let biometricService = BiometricService()
    private let pinService = PrivateAlbumPINService()
    private let keyManagementService = KeyManagementService()

    private static let keyPrefix = "private_album_key_"

    enum PrivateAlbumKeyError: LocalizedError {
        case faceIDNotAvailable
        case pinNotSetUp
        case authenticationRequired
        case keyNotFound
        case encryptionFailed
        case decryptionFailed
        case albumNotPrivate

        var errorDescription: String? {
            switch self {
            case .faceIDNotAvailable:
                return "Face ID is not available"
            case .pinNotSetUp:
                return "App PIN has not been set up"
            case .authenticationRequired:
                return "Authentication required to access private album"
            case .keyNotFound:
                return "Album key not found"
            case .encryptionFailed:
                return "Failed to encrypt album key"
            case .decryptionFailed:
                return "Failed to decrypt album key"
            case .albumNotPrivate:
                return "Album is not marked as private"
            }
        }
    }

    // MARK: - Authentication Type

    enum AuthType {
        case faceID
        case pin
    }

    /// Determine which authentication type to use
    func getAvailableAuthType() -> AuthType {
        if biometricService.isFaceIDAvailable() {
            return .faceID
        }
        return .pin
    }

    /// Check if authentication is configured (Face ID available or PIN set up)
    func isAuthenticationConfigured() -> Bool {
        if biometricService.isFaceIDAvailable() {
            return true
        }
        return pinService.isPINSetUp()
    }

    // MARK: - Enable/Disable Private Mode

    /// Enable private mode for an album - encrypts the album key with biometric or PIN
    func enablePrivateMode(for album: Album, currentAppPin: String) async throws {
        // Get the album's encryption key
        let keyData = try await keyManagementService.getKey(byName: album.keyName, pin: currentAppPin)
            .withUnsafeBytes { Data($0) }

        let protectedKeyId = Self.keyPrefix + album.id.uuidString

        // Encrypt the key with biometric or PIN
        if biometricService.isFaceIDAvailable() {
            // Use Face ID protection
            try biometricService.saveWithBiometricProtection(data: keyData, forKey: protectedKeyId)
        } else {
            // Use PIN protection
            guard pinService.isPINSetUp() else {
                throw PrivateAlbumKeyError.pinNotSetUp
            }

            // Get the app PIN for private albums (user must enter it)
            // For now, we'll use a placeholder that requires the PIN to be passed in
            throw PrivateAlbumKeyError.pinNotSetUp
        }
    }

    /// Enable private mode with PIN (when Face ID is not available)
    func enablePrivateModeWithPIN(for album: Album, currentAppPin: String, privateAlbumPIN: String) async throws {
        // Get the album's encryption key
        let keyData = try await keyManagementService.getKey(byName: album.keyName, pin: currentAppPin)
            .withUnsafeBytes { Data($0) }

        let protectedKeyId = Self.keyPrefix + album.id.uuidString

        // Encrypt the key with app PIN
        try pinService.saveWithPINProtection(data: keyData, forKey: protectedKeyId, pin: privateAlbumPIN)
    }

    /// Disable private mode - decrypts the album key and stores it normally
    func disablePrivateMode(for album: Album, pin: String? = nil) async throws {
        let protectedKeyId = Self.keyPrefix + album.id.uuidString

        // Check which protection was used
        if biometricService.hasProtectedData(forKey: protectedKeyId) {
            // Remove biometric-protected key
            biometricService.deleteWithBiometricProtection(forKey: protectedKeyId)
        } else if pinService.hasProtectedData(forKey: protectedKeyId) {
            // Remove PIN-protected key
            pinService.deleteWithPINProtection(forKey: protectedKeyId)
        }
        // The original key in KeyManagementService remains unchanged
    }

    // MARK: - Access Private Album

    /// Authenticate and get the decrypted key for a private album using Face ID
    func getPrivateAlbumKeyWithFaceID(for album: Album) async throws -> SymmetricKey {
        guard album.isPrivate else {
            throw PrivateAlbumKeyError.albumNotPrivate
        }

        let protectedKeyId = Self.keyPrefix + album.id.uuidString

        // Authenticate with Face ID and retrieve key
        do {
            let keyData = try await biometricService.loadWithBiometricProtection(
                forKey: protectedKeyId,
                reason: "Authenticate to access \(album.name)"
            )
            return SymmetricKey(data: keyData)
        } catch {
            throw PrivateAlbumKeyError.authenticationRequired
        }
    }

    /// Authenticate and get the decrypted key for a private album using PIN
    func getPrivateAlbumKeyWithPIN(for album: Album, pin: String) throws -> SymmetricKey {
        guard album.isPrivate else {
            throw PrivateAlbumKeyError.albumNotPrivate
        }

        let protectedKeyId = Self.keyPrefix + album.id.uuidString

        // Verify PIN and retrieve key
        do {
            let keyData = try pinService.loadWithPINProtection(forKey: protectedKeyId, pin: pin)
            return SymmetricKey(data: keyData)
        } catch {
            throw PrivateAlbumKeyError.authenticationRequired
        }
    }

    /// Check if private album has Face ID-protected key
    func isProtectedWithFaceID(albumId: UUID) -> Bool {
        let protectedKeyId = Self.keyPrefix + albumId.uuidString
        return biometricService.hasProtectedData(forKey: protectedKeyId)
    }

    /// Check if private album has PIN-protected key
    func isProtectedWithPIN(albumId: UUID) -> Bool {
        let protectedKeyId = Self.keyPrefix + albumId.uuidString
        return pinService.hasProtectedData(forKey: protectedKeyId)
    }

    // MARK: - Cleanup

    /// Remove all private album key data (for app reset)
    func removeAllPrivateAlbumKeys(for albumIds: [UUID]) {
        for albumId in albumIds {
            let protectedKeyId = Self.keyPrefix + albumId.uuidString
            biometricService.deleteWithBiometricProtection(forKey: protectedKeyId)
            pinService.deleteWithPINProtection(forKey: protectedKeyId)
        }
    }
}
