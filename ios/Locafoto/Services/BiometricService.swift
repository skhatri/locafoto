import LocalAuthentication

/// Service for handling biometric authentication (Face ID/Touch ID)
class BiometricService {

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
}
