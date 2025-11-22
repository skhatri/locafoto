import LocalAuthentication
import Security

/// Service for handling biometric authentication (Face ID/Touch ID)
class BiometricService {

    private static let keychainService = "com.locafoto.privatealbum"

    enum BiometricType {
        case none
        case touchID
        case faceID
    }

    enum BiometricError: Error, LocalizedError {
        case notAvailable
        case notEnrolled
        case authenticationFailed
        case userCancelled
        case systemCancelled
        case passcodeNotSet
        case unknown(Error)

        var errorDescription: String? {
            switch self {
            case .notAvailable:
                return "Biometric authentication is not available on this device"
            case .notEnrolled:
                return "No biometric data is enrolled. Please set up Face ID or Touch ID in Settings."
            case .authenticationFailed:
                return "Authentication failed"
            case .userCancelled:
                return "Authentication was cancelled"
            case .systemCancelled:
                return "Authentication was cancelled by the system"
            case .passcodeNotSet:
                return "Device passcode is not set"
            case .unknown(let error):
                return error.localizedDescription
            }
        }
    }

    /// Check what type of biometric is available
    func biometricType() -> BiometricType {
        let context = LAContext()
        var error: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return .none
        }

        switch context.biometryType {
        case .faceID:
            return .faceID
        case .touchID:
            return .touchID
        case .opticID:
            return .faceID // Treat opticID similar to faceID
        case .none:
            return .none
        @unknown default:
            return .none
        }
    }

    /// Check if Face ID specifically is available
    func isFaceIDAvailable() -> Bool {
        return biometricType() == .faceID
    }

    /// Check if any biometric is available
    func isBiometricAvailable() -> Bool {
        return biometricType() != .none
    }

    /// Authenticate using biometrics
    /// - Parameter reason: The reason shown to the user for authentication
    /// - Returns: True if authentication succeeded
    func authenticate(reason: String) async throws -> Bool {
        let context = LAContext()
        var error: NSError?

        // Check if biometrics are available
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            if let error = error {
                throw mapLAError(error)
            }
            throw BiometricError.notAvailable
        }

        // Perform authentication
        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            )
            return success
        } catch let error as LAError {
            throw mapLAError(error)
        } catch {
            throw BiometricError.unknown(error)
        }
    }

    /// Map LAError to BiometricError
    private func mapLAError(_ error: Error) -> BiometricError {
        guard let laError = error as? LAError else {
            return .unknown(error)
        }

        switch laError.code {
        case .biometryNotAvailable:
            return .notAvailable
        case .biometryNotEnrolled:
            return .notEnrolled
        case .authenticationFailed:
            return .authenticationFailed
        case .userCancel:
            return .userCancelled
        case .systemCancel:
            return .systemCancelled
        case .passcodeNotSet:
            return .passcodeNotSet
        default:
            return .unknown(error)
        }
    }

    /// Get human-readable name for the biometric type
    func biometricName() -> String {
        switch biometricType() {
        case .faceID:
            return "Face ID"
        case .touchID:
            return "Touch ID"
        case .none:
            return "Biometrics"
        }
    }

    // MARK: - Keychain with Biometric Protection

    /// Save data to keychain with biometric protection (requires Face ID to access)
    func saveWithBiometricProtection(data: Data, forKey key: String) throws {
        // Create access control with biometric protection
        var error: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(
            kCFAllocatorDefault,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            .biometryCurrentSet,
            &error
        ) else {
            throw BiometricError.notAvailable
        }

        // Delete existing item first
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Add new item with biometric protection
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: key,
            kSecAttrAccessControl as String: access,
            kSecValueData as String: data
        ]

        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw BiometricError.authenticationFailed
        }
    }

    /// Load data from keychain that requires biometric authentication
    func loadWithBiometricProtection(forKey key: String, reason: String) async throws -> Data {
        let context = LAContext()
        context.localizedReason = reason

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecUseAuthenticationContext as String: context
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            if status == errSecItemNotFound {
                throw BiometricError.authenticationFailed
            }
            throw BiometricError.authenticationFailed
        }

        return data
    }

    /// Delete biometric-protected data from keychain
    func deleteWithBiometricProtection(forKey key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: key
        ]

        SecItemDelete(query as CFDictionary)
    }

    /// Check if biometric-protected data exists for key
    func hasProtectedData(forKey key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: key,
            kSecReturnData as String: false
        ]

        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess
    }
}
