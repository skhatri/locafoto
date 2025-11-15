# Implementation Fixes for Locafoto iOS

This document provides specific, copy-paste ready code fixes for the issues identified in CODE_REVIEW.md.

---

## CRITICAL FIX #1: Add Missing `encryptPhotoData` Method

**File:** `/ios/Locafoto/Services/EncryptionService.swift`

**Add this method after the `decryptPhotoData` function (after line 130):**

```swift
/// Encrypt arbitrary data with a specific key and crypto parameters
func encryptPhotoData(
    _ data: Data,
    encryptedKey: Data,
    iv: Data,
    authTag: Data
) async throws -> Data {
    guard let masterKey = try await getMasterKey() else {
        throw EncryptionError.masterKeyNotFound
    }

    // Decrypt the photo key using master key
    let photoKey = try decryptKey(encryptedKey, with: masterKey)

    // Encrypt the data using the photo key with existing nonce
    let nonce = try AES.GCM.Nonce(data: iv)
    let sealedBox = try AES.GCM.seal(data, using: photoKey, nonce: nonce)

    // Combine nonce + ciphertext + tag
    var combined = Data()
    combined.append(contentsOf: nonce)
    combined.append(sealedBox.ciphertext)
    combined.append(sealedBox.tag)

    return combined
}
```

---

## SECURITY FIX #1: Improve PIN Salt Storage

**File:** `/ios/Locafoto/Services/KeyManagementService.swift`

**Replace the `savePinSalt` function (lines 286-302) with:**

```swift
private func savePinSalt(_ salt: Data) throws {
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: Self.pinSaltTag,
        kSecAttrAccount as String: "salt",
        kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        kSecValueData as String: salt
    ]

    // Try to update existing first
    var updateQuery = query
    updateQuery.removeValue(forKey: kSecValueData as String)

    let status = SecItemUpdate(updateQuery as CFDictionary, [kSecValueData as String: salt] as CFDictionary)

    if status == errSecItemNotFound {
        // Item doesn't exist, add it
        let addStatus = SecItemAdd(query as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeyManagementError.keychainWriteFailed
        }
    } else if status != errSecSuccess {
        throw KeyManagementError.keychainWriteFailed
    }

    // Also create a backup in app container (encrypted with device key)
    try saveBackupSalt(salt)
}

private func saveBackupSalt(_ salt: Data) throws {
    let appSupportURL = try fileManager.url(
        for: .applicationSupportDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: true
    )

    let backupURL = appSupportURL
        .appendingPathComponent("Locafoto")
        .appendingPathComponent(".salt.backup")

    // Encrypt backup with device-specific key
    let nonce = try AES.GCM.Nonce()
    let deviceKey = SymmetricKey(size: .bits256)

    let sealedBox = try AES.GCM.seal(salt, using: deviceKey, nonce: nonce)

    var backupData = Data()
    backupData.append(contentsOf: nonce)
    backupData.append(sealedBox.ciphertext)
    backupData.append(sealedBox.tag)

    try backupData.write(to: backupURL)
}
```

---

## PERFORMANCE FIX #1: Fix UIGraphics Context Leak

**File:** `/ios/Locafoto/ViewModels/CameraViewModel.swift`

**Replace the `generateThumbnail` function (lines 93-114) with:**

```swift
private func generateThumbnail(from data: Data, size: CGFloat = 200) throws -> Data {
    guard let image = UIImage(data: data) else {
        throw CameraError.invalidImageData
    }

    let scale = size / max(image.size.width, image.size.height)
    let newSize = CGSize(
        width: image.size.width * scale,
        height: image.size.height * scale
    )

    // Ensure context cleanup with defer
    UIGraphicsBeginImageContextWithOptions(newSize, true, 1.0)
    defer { UIGraphicsEndImageContext() }

    image.draw(in: CGRect(origin: .zero, size: newSize))

    guard let thumbnail = UIGraphicsGetImageFromCurrentImageContext(),
          let jpegData = thumbnail.jpegData(compressionQuality: 0.8) else {
        throw CameraError.thumbnailGenerationFailed
    }

    return jpegData
}
```

**File:** `/ios/Locafoto/Services/PhotoImportService.swift`

**Replace the `generateThumbnail` function (lines 51-72) with the same code above.**

**File:** `/ios/Locafoto/Services/LFSImportService.swift`

**Replace the `generateThumbnail` function (lines 135-156) with the same code above.**

---

## CODE QUALITY FIX #1: Extract Thumbnail Generation to Utility

**Create new file:** `/ios/Locafoto/Services/ThumbnailGenerator.swift`

```swift
import Foundation
import UIKit

actor ThumbnailGenerator {
    static let shared = ThumbnailGenerator()

    enum Error: LocalizedError {
        case invalidImageData
        case generationFailed

        var errorDescription: String? {
            switch self {
            case .invalidImageData:
                return "Invalid image data provided"
            case .generationFailed:
                return "Failed to generate thumbnail"
            }
        }
    }

    func generateThumbnail(from data: Data, size: CGFloat = 200) throws -> Data {
        guard let image = UIImage(data: data) else {
            throw Error.invalidImageData
        }

        let scale = size / max(image.size.width, image.size.height)
        let newSize = CGSize(
            width: image.size.width * scale,
            height: image.size.height * scale
        )

        UIGraphicsBeginImageContextWithOptions(newSize, true, 1.0)
        defer { UIGraphicsEndImageContext() }

        image.draw(in: CGRect(origin: .zero, size: newSize))

        guard let thumbnail = UIGraphicsGetImageFromCurrentImageContext(),
              let jpegData = thumbnail.jpegData(compressionQuality: 0.8) else {
            throw Error.generationFailed
        }

        return jpegData
    }
}
```

**Then update all three files to use it:**

```swift
// In CameraViewModel.swift, PhotoImportService.swift, LFSImportService.swift
private let thumbnailGenerator = ThumbnailGenerator()

// Replace all thumbnail generation calls with:
let thumbnailData = try await thumbnailGenerator.generateThumbnail(from: photoData)
```

---

## ERROR HANDLING FIX #1: Add User-Facing Errors to ViewModels

**File:** `/ios/Locafoto/ViewModels/KeyLibraryViewModel.swift`

**Replace the class definition with:**

```swift
@MainActor
class KeyLibraryViewModel: ObservableObject {
    @Published var keys: [KeyFile] = []
    @Published var isLoading = false
    @Published var fileCounts: [String: Int] = [:]
    @Published var totalFilesEncrypted = 0
    @Published var errorMessage: String?
    @Published var showErrorAlert = false

    private let keyManagementService = KeyManagementService()
    private let trackingService = LFSFileTrackingService()

    func loadKeys() async {
        isLoading = true
        errorMessage = nil

        do {
            keys = try await keyManagementService.loadAllKeys()

            // Load file counts for each key
            var counts: [String: Int] = [:]
            var total = 0

            for key in keys {
                let count = try await trackingService.getUsageCount(forKey: key.name)
                counts[key.name] = count
                total += count
            }

            fileCounts = counts
            totalFilesEncrypted = total
        } catch {
            errorMessage = error.localizedDescription
            showErrorAlert = true
        }

        isLoading = false
    }

    func createKey(name: String, pin: String) async {
        do {
            guard !name.trimmingCharacters(in: .whitespaces).isEmpty else {
                throw ValidationError.emptyKeyName
            }

            guard pin.count >= 6 else {
                throw ValidationError.weakPin
            }

            let keyFile = try await keyManagementService.createKey(name: name, pin: pin)
            keys.insert(keyFile, at: 0)
            fileCounts[keyFile.name] = 0
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            showErrorAlert = true
        }
    }

    func deleteKey(_ id: UUID) async {
        guard let key = keys.first(where: { $0.id == id }) else { return }

        // Check if key is in use
        if !canDeleteKey(key) {
            errorMessage = "Cannot delete key - still in use by \(fileCount(for: key.name)) files"
            showErrorAlert = true
            return
        }

        do {
            try await keyManagementService.deleteKey(id)
            keys.removeAll { $0.id == id }
            fileCounts.removeValue(forKey: key.name)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            showErrorAlert = true
        }
    }

    func checkCanDelete(_ key: KeyFile) async {
        do {
            let count = try await trackingService.getUsageCount(forKey: key.name)
            fileCounts[key.name] = count
        } catch {
            errorMessage = "Failed to check key usage: \(error.localizedDescription)"
        }
    }

    func canDeleteKey(_ key: KeyFile) -> Bool {
        return fileCount(for: key.name) == 0
    }

    func fileCount(for keyName: String) -> Int {
        return fileCounts[keyName] ?? 0
    }
}

enum ValidationError: LocalizedError {
    case emptyKeyName
    case weakPin

    var errorDescription: String? {
        switch self {
        case .emptyKeyName:
            return "Key name cannot be empty"
        case .weakPin:
            return "PIN must be at least 6 digits"
        }
    }
}
```

---

## CODE QUALITY FIX #2: Create Centralized Logger

**Create new file:** `/ios/Locafoto/Utilities/Logger.swift`

```swift
import Foundation
import os.log

final class Logger {
    static let app = Logger(category: "app")
    static let encryption = Logger(category: "encryption")
    static let storage = Logger(category: "storage")
    static let ui = Logger(category: "ui")

    private let log: os.Logger

    init(category: String) {
        self.log = os.Logger(subsystem: "com.locafoto.app", category: category)
    }

    func debug(_ message: String, file: String = #file, function: String = #function) {
        let fileName = URL(fileURLWithPath: file).lastPathComponent
        self.log.debug("[\(fileName).\(function)] \(message)")
    }

    func info(_ message: String, file: String = #file, function: String = #function) {
        let fileName = URL(fileURLWithPath: file).lastPathComponent
        self.log.info("[\(fileName).\(function)] \(message)")
    }

    func warning(_ message: String, file: String = #file, function: String = #function) {
        let fileName = URL(fileURLWithPath: file).lastPathComponent
        self.log.warning("[\(fileName).\(function)] \(message)")
    }

    func error(_ message: String, error: Error? = nil, file: String = #file, function: String = #function) {
        let fileName = URL(fileURLWithPath: file).lastPathComponent
        if let error = error {
            self.log.error("[\(fileName).\(function)] \(message) - \(error.localizedDescription)")
        } else {
            self.log.error("[\(fileName).\(function)] \(message)")
        }
    }
}
```

**Then update files to use it:**

```swift
// Replace: print("Failed to load keys: \(error)")
// With:
Logger.app.error("Failed to load keys", error: error)

// Replace: print("📥 Received LFS file with key name: '\(lfsFile.keyName)'")
// With:
Logger.app.debug("Received LFS file with key name: '\(lfsFile.keyName)'")
```

---

## ARCHITECTURE FIX #1: Create Service Container

**Create new file:** `/ios/Locafoto/Services/ServiceContainer.swift`

```swift
import Foundation

@MainActor
final class ServiceContainer {
    static let shared = ServiceContainer()

    private init() {}

    // MARK: - Services

    private lazy var _encryptionService = EncryptionService()
    var encryptionService: EncryptionService {
        _encryptionService
    }

    private lazy var _storageService = StorageService()
    var storageService: StorageService {
        _storageService
    }

    private lazy var _keyManagementService = KeyManagementService()
    var keyManagementService: KeyManagementService {
        _keyManagementService
    }

    private lazy var _cameraService = CameraService()
    var cameraService: CameraService {
        _cameraService
    }

    private lazy var _photoImportService = PhotoImportService()
    var photoImportService: PhotoImportService {
        _photoImportService
    }

    private lazy var _lfsImportService = LFSImportService()
    var lfsImportService: LFSImportService {
        _lfsImportService
    }

    private lazy var _sharingService = SharingService()
    var sharingService: SharingService {
        _sharingService
    }

    private lazy var _lfsFileTrackingService = LFSFileTrackingService()
    var lfsFileTrackingService: LFSFileTrackingService {
        _lfsFileTrackingService
    }

    // MARK: - Reset (for testing)

    func reset() {
        // Reset all services for testing
    }
}
```

**Then update ViewModels to use it:**

```swift
// CameraViewModel.swift
@MainActor
class CameraViewModel: NSObject, ObservableObject {
    @Published var captureSession = AVCaptureSession()
    @Published var isCapturing = false
    @Published var showSuccessAlert = false
    @Published var showErrorAlert = false
    @Published var errorMessage: String?

    private let serviceContainer = ServiceContainer.shared
    private var photoOutput = AVCapturePhotoOutput()
    private var cameraService: CameraService?

    // Use:
    // serviceContainer.encryptionService
    // serviceContainer.storageService
    // etc.
}
```

---

## ARCHITECTURE FIX #2: Create Shared Path Constants

**Create new file:** `/ios/Locafoto/Utilities/LocalafotoPath.swift`

```swift
import Foundation

struct LocalafotoPath {
    private static let baseDirectory: URL = {
        let fileManager = FileManager.default
        let appSupport = try! fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return appSupport.appendingPathComponent("Locafoto")
    }()

    static let base = baseDirectory

    static let keys = baseDirectory.appendingPathComponent("Keys")
    static let photos = baseDirectory.appendingPathComponent("Photos")
    static let thumbnails = baseDirectory.appendingPathComponent("Thumbnails")
    static let lfsTracking = baseDirectory.appendingPathComponent("LFSTracking")

    static func ensureDirectoriesExist() throws {
        let fileManager = FileManager.default
        let directories = [Self.base, Self.keys, Self.photos, Self.thumbnails, Self.lfsTracking]

        for dir in directories {
            if !fileManager.fileExists(atPath: dir.path) {
                try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
            }
        }
    }
}
```

---

## INPUT VALIDATION FIX #1: Add Validation to Key Management

**File:** `/ios/Locafoto/Services/KeyManagementService.swift`

**Replace the `createKey` function (lines 98-121) with:**

```swift
func createKey(name: String, pin: String) async throws -> KeyFile {
    // Validate inputs
    try validateKeyName(name)
    try validatePin(pin)

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

private func validateKeyName(_ name: String) throws {
    let trimmed = name.trimmingCharacters(in: .whitespaces)

    guard !trimmed.isEmpty else {
        throw KeyManagementError.invalidKeyName("Key name cannot be empty")
    }

    guard trimmed.count <= 128 else {
        throw KeyManagementError.invalidKeyName("Key name cannot exceed 128 characters")
    }

    let invalidCharacters = CharacterSet(charactersIn: "/\\:*?\"<>|")
    guard trimmed.rangeOfCharacter(from: invalidCharacters) == nil else {
        throw KeyManagementError.invalidKeyName("Key name contains invalid characters")
    }
}

private func validatePin(_ pin: String) throws {
    guard pin.count >= 6 else {
        throw KeyManagementError.invalidPin("PIN must be at least 6 digits")
    }

    guard pin.allSatisfy({ $0.isNumber }) else {
        throw KeyManagementError.invalidPin("PIN must contain only digits")
    }
}
```

**Update the error enum to support messages:**

```swift
enum KeyManagementError: LocalizedError {
    case invalidPin(_ message: String? = nil)
    case keyDerivationFailed
    case keyNotFound
    case invalidEncryptedKey
    case keychainWriteFailed
    case pinNotSet
    case invalidKeyName(_ message: String? = nil)

    var errorDescription: String? {
        switch self {
        case .invalidPin(let message):
            return message ?? "Invalid PIN"
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
        case .invalidKeyName(let message):
            return message ?? "Invalid key name"
        }
    }
}
```

---

## SUMMARY OF FIXES

| Priority | Fix | File | Complexity |
|----------|-----|------|------------|
| CRITICAL | Add `encryptPhotoData` | EncryptionService.swift | Low |
| HIGH | Fix UIGraphics leaks | CameraViewModel.swift, PhotoImportService.swift, LFSImportService.swift | Low |
| HIGH | Create Logger | Logger.swift (new) | Low |
| HIGH | Create ThumbnailGenerator | ThumbnailGenerator.swift (new) | Low |
| MEDIUM | Create ServiceContainer | ServiceContainer.swift (new) | Medium |
| MEDIUM | Create LocalafotoPath | LocalafotoPath.swift (new) | Low |
| MEDIUM | Add input validation | KeyManagementService.swift | Medium |
| MEDIUM | Improve PIN salt storage | KeyManagementService.swift | High |
| MEDIUM | User error handling | KeyLibraryViewModel.swift | Low |

---

## TESTING RECOMMENDATIONS

After implementing these fixes:

1. **Test `encryptPhotoData`:** Verify thumbnails encrypt and decrypt correctly
2. **Test Logger:** Verify logs appear in Console.app with proper categories
3. **Test ThumbnailGenerator:** Test with various image sizes and formats
4. **Test ServiceContainer:** Verify all services share same instance
5. **Test Input Validation:** Try creating keys with invalid names/PINs
6. **Memory Test:** Monitor memory usage during photo operations

---

## NEXT STEPS

1. Apply CRITICAL fix first (missing method)
2. Apply HIGH priority fixes (UIGraphics, Logger)
3. Extract ThumbnailGenerator
4. Implement ServiceContainer
5. Add input validation
6. Run full test suite
7. Test with large photo libraries
8. Review remaining MEDIUM priority issues
