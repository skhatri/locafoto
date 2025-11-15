# Locafoto iOS Codebase Review

**Date:** 2025-11-15
**Scope:** Security, Performance, Error Handling, Code Quality, Architecture

---

## CRITICAL ISSUES

### 1. Missing `encryptPhotoData` Method
**Severity:** CRITICAL
**Files Affected:** EncryptionService.swift, PhotoImportService.swift, LFSImportService.swift, CameraViewModel.swift

**Issue:** The method `encryptPhotoData()` is called in multiple places but is not defined in `EncryptionService`:

```swift
// PhotoImportService.swift (line 20)
let encryptedThumbnail = try await encryptionService.encryptPhotoData(
    thumbnailData,
    encryptedKey: encryptedPhoto.encryptedKey,
    iv: encryptedPhoto.iv,
    authTag: encryptedPhoto.authTag
)

// LFSImportService.swift (line 46)
let encryptedThumbnail = try await encryptionService.encryptPhotoData(...)

// CameraViewModel.swift (line 71)
let encryptedThumbnail = try await encryptionService.encryptPhotoData(...)
```

**Impact:** Code will not compile. Thumbnails cannot be encrypted.

**Solution:** Add the missing method to EncryptionService:
```swift
/// Encrypt data with a specific key, IV, and auth tag
func encryptPhotoData(
    _ data: Data,
    encryptedKey: Data,
    iv: Data,
    authTag: Data
) async throws -> Data {
    guard let masterKey = try await getMasterKey() else {
        throw EncryptionError.masterKeyNotFound
    }

    let photoKey = try decryptKey(encryptedKey, with: masterKey)
    let nonce = try AES.GCM.Nonce(data: iv)
    let sealedBox = try AES.GCM.seal(data, using: photoKey, nonce: nonce)

    var combined = Data()
    combined.append(contentsOf: nonce)
    combined.append(sealedBox.ciphertext)
    combined.append(sealedBox.tag)

    return combined
}
```

---

## SECURITY ISSUES

### 2. PIN Salt Not Protected from Keychain Deletion
**Severity:** HIGH
**File:** KeyManagementService.swift (line 286-302)

**Issue:** The PIN salt is stored in Keychain but not protected if Keychain is accessed. Deleting the salt would permanently lock out the user.

**Current Code:**
```swift
private func savePinSalt(_ salt: Data) throws {
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: Self.pinSaltTag,
        kSecAttrAccount as String: "salt",
        kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        kSecValueData as String: salt
    ]

    SecItemDelete(query as CFDictionary)  // Deletes existing
    let status = SecItemAdd(query as CFDictionary, nil)
    guard status == errSecSuccess else {
        throw KeyManagementError.keychainWriteFailed
    }
}
```

**Problems:**
1. No backup/recovery mechanism if salt is lost
2. `SecItemDelete` followed by `SecItemAdd` creates a window where salt is missing
3. No validation that salt exists before key operations

**Recommendation:**
- Store salt in two locations (Keychain + encrypted app data backup)
- Use atomic update operation instead of delete + add
- Add recovery mechanism using additional security questions

### 3. Master Key Derivation PBKDF2 Not Using Standard Header
**Severity:** MEDIUM
**File:** KeyManagementService.swift (line 34-66)

**Issue:** Raw PBKDF2 is used without proper versioning/headers. If algorithm changes, old keys cannot be migrated.

**Recommendation:**
```swift
struct DerivedKeyMetadata: Codable {
    let version: Int = 1
    let algorithm: String = "PBKDF2-SHA256"
    let iterations: Int = 100_000
    let saltLength: Int = 32
}

// Store metadata with salt to support future migrations
```

### 4. Sensitive Data (PIN) Not Cleared from Memory
**Severity:** MEDIUM
**File:** KeyManagementService.swift (lines 16-31, 90-93)

**Issue:** PIN strings are passed as parameters and potentially remain in memory after use.

**Current Code:**
```swift
func getMasterKey(pin: String) async throws -> SymmetricKey {
    let salt = try getPinSalt()
    return try deriveMasterKey(from: pin, salt: salt)  // Pin stays in memory
}
```

**Recommendation:**
```swift
extension String {
    mutating func wipeMemory() {
        _ = self.map { _ in "0" }
        self = ""
    }
}

// Or use SecureString pattern
```

### 5. Duplicate Key Encryption Code Without Deduplication
**Severity:** LOW
**Files:** KeyManagementService.swift, EncryptionService.swift

**Issue:** `encryptKey()` and `decryptKey()` are duplicated in both services.

**Location:**
- KeyManagementService.swift lines 252-282
- EncryptionService.swift lines 135-167

**Recommendation:** Extract to shared utility or base protocol.

### 6. AES-GCM Nonce Collision Risk
**Severity:** MEDIUM
**Files:** EncryptionService.swift (line 81), KeyManagementService.swift (line 254)

**Issue:** Nonce is generated randomly but no tracking to prevent reuse with same key.

```swift
let nonce = try AES.GCM.Nonce()  // Cryptographically weak for repeated use
```

**Recommendation:** Use counter-based nonce or explicitly document single-use requirement.

---

## PERFORMANCE ISSUES

### 7. UIGraphics Context Not Properly Cleaned Up
**Severity:** HIGH
**Files:** CameraViewModel.swift (lines 104-107), PhotoImportService.swift (lines 62-65), LFSImportService.swift (lines 146-149)

**Issue:** Identical thumbnail generation code with potential memory leaks.

**Current Code:**
```swift
UIGraphicsBeginImageContextWithOptions(newSize, true, 1.0)
image.draw(in: CGRect(origin: .zero, size: newSize))
let thumbnail = UIGraphicsGetImageFromCurrentImageContext()
UIGraphicsEndImageContext()  // May not properly release in error cases
```

**Problems:**
1. If error occurs before `UIGraphicsEndImageContext()`, context leaks
2. Large images create temporary uncompressed bitmap contexts in memory
3. JPEG compression happens in-memory multiple times (create + compress)

**Recommendation:**
```swift
private func generateThumbnail(from data: Data, size: CGFloat = 200) throws -> Data {
    guard let image = UIImage(data: data) else {
        throw ThumbnailError.invalidImageData
    }

    let scale = size / max(image.size.width, image.size.height)
    let newSize = CGSize(
        width: image.size.width * scale,
        height: image.size.height * scale
    )

    defer { UIGraphicsEndImageContext() }
    UIGraphicsBeginImageContextWithOptions(newSize, true, 1.0)

    defer { UIGraphicsEndImageContext() }
    image.draw(in: CGRect(origin: .zero, size: newSize))

    guard let thumbnail = UIGraphicsGetImageFromCurrentImageContext(),
          let jpegData = thumbnail.jpegData(compressionQuality: 0.8) else {
        throw ThumbnailError.generationFailed
    }

    return jpegData
}
```

### 8. Full Photo Decryption for Thumbnail Display
**Severity:** HIGH
**File:** LFSImportService.swift (lines 25-41)

**Issue:** Full photo is decrypted to generate thumbnail, wasting resources.

```swift
let decryptedData = try AES.GCM.open(sealedBox, using: encryptionKey)

// Determine if it's an image
guard let image = UIImage(data: decryptedData) else {
    throw LFSError.invalidFormat
}

// Generate thumbnail
let thumbnailData = try generateThumbnail(from: decryptedData)

// Then later, re-encrypt with our own encryption
let encryptedPhoto = try await encryptionService.encryptPhoto(decryptedData)
```

**Problems:**
1. Full high-res image loaded into memory for thumbnail
2. Image decoded twice (for thumbnail, then stored again)
3. No streaming or chunk-based processing for large files

**Recommendation:**
- Store thumbnail separately in LFS format
- Decode only first few bytes to validate format
- Stream large files instead of loading entirely

### 9. Inefficient Photo Loading
**Severity:** MEDIUM
**File:** StorageService.swift (line 122)

**Issue:** Photos are loaded entirely into memory without pagination.

```swift
func loadPhoto(for id: UUID) async throws -> Data {
    let photoDir = try photosSubdirectory
    let photoURL = photoDir.appendingPathComponent("\(id.uuidString).encrypted")

    guard fileManager.fileExists(atPath: photoURL.path) else {
        throw StorageError.photoNotFound
    }

    return try Data(contentsOf: photoURL)  // Loads entire file into memory
}
```

**Recommendation:**
- Use `InputStream` for streaming decryption
- Implement chunked loading for large images

### 10. Keychain Queries Unoptimized
**Severity:** LOW
**File:** KeyManagementService.swift (lines 304-320), EncryptionService.swift (lines 24-45)

**Issue:** No caching of keychain queries. PIN salt and master key accessed frequently without caching.

**Recommendation:**
```swift
private var cachedMasterKey: SymmetricKey?
private var cachedPinSalt: Data?

// Invalidate cache after operations
```

---

## ERROR HANDLING ISSUES

### 11. Silent Failures in ViewModels
**Severity:** MEDIUM
**Files:** KeyLibraryViewModel.swift, GalleryViewModel.swift, LFSLibraryViewModel.swift

**Issue:** Errors are logged to console but not presented to user.

```swift
// KeyLibraryViewModel.swift (lines 31-36)
} catch {
    print("Failed to load keys: \(error)")
    keys = []
    fileCounts = [:]
    totalFilesEncrypted = 0
}
```

**Problems:**
1. User doesn't know operation failed
2. No error recovery options
3. Inconsistent state (empty arrays suggest no data)

**Recommendation:**
```swift
@Published var errorMessage: String?
@Published var showErrorAlert = false

func loadKeys() async {
    isLoading = true
    do {
        keys = try await keyManagementService.loadAllKeys()
        errorMessage = nil
    } catch {
        errorMessage = error.localizedDescription
        showErrorAlert = true
        keys = []  // Keep previous state instead
    }
    isLoading = false
}
```

### 12. File Operation Errors Silently Ignored
**Severity:** MEDIUM
**File:** StorageService.swift (line 153-154), LFSImportService.swift (line 86)

**Issue:** File deletion errors are caught but not logged or reported.

```swift
// StorageService.swift
try? fileManager.removeItem(at: photoURL)  // Silently fails
try? fileManager.removeItem(at: thumbURL)

// LFSImportService.swift
try? FileManager.default.removeItem(at: url)  // Cleanup failure ignored
```

**Recommendation:**
```swift
do {
    try fileManager.removeItem(at: photoURL)
} catch {
    // Log but don't fail - photo data is deleted, metadata is cleanup
    print("Warning: Failed to delete photo file: \(error)")
}
```

### 13. Missing Validation for LFS File Structure
**Severity:** MEDIUM
**File:** LFSFile.swift (lines 30-58)

**Issue:** Minimal validation of LFS file format.

```swift
static func parse(from data: Data) throws -> LFSFile {
    guard data.count >= headerSize + nonceSize + tagSize else {
        throw LFSError.invalidFormat
    }

    let keyNameData = data.prefix(headerSize)
    guard let keyName = String(data: keyNameData, encoding: .utf8)?
        .trimmingCharacters(in: .controlCharacters)
        .trimmingCharacters(in: .whitespaces) else {
        throw LFSError.invalidKeyName
    }
    // No check for empty keyName, special characters, etc.
}
```

**Recommendation:**
- Validate key name is not empty
- Check for valid UTF-8 (reject invalid sequences)
- Add version/magic number to format

---

## CODE QUALITY ISSUES

### 14. Inconsistent File Path Handling
**Severity:** MEDIUM
**Files:** StorageService.swift, LFSFileTrackingService.swift, KeyManagementService.swift

**Issue:** Directory paths constructed differently in each service.

```swift
// StorageService.swift (line 17)
let locafotoDir = appSupport.appendingPathComponent("Locafoto")

// KeyManagementService.swift (line 214)
let keysDir = appSupport.appendingPathComponent("Locafoto/Keys")

// LFSFileTrackingService.swift (line 27)
let trackingDir = appSupport.appendingPathComponent("Locafoto/LFSTracking")
```

**Recommendation:** Create shared path utility:
```swift
struct LocalafotoPath {
    static let basePath = "Locafoto"
    static let keysPath = "Locafoto/Keys"
    static let photosPath = "Locafoto/Photos"
    static let trackingPath = "Locafoto/LFSTracking"
}
```

### 15. Duplicate Thumbnail Generation Code
**Severity:** LOW
**Files:** CameraViewModel.swift, PhotoImportService.swift, LFSImportService.swift

**Issue:** Thumbnail generation repeated 3 times with identical code (lines 93-114, 51-72, 135-156).

**Recommendation:** Extract to shared utility:
```swift
// ThumbnailGenerator.swift
actor ThumbnailGenerator {
    static let shared = ThumbnailGenerator()

    func generateThumbnail(from data: Data, size: CGFloat = 200) throws -> Data {
        // Shared implementation
    }
}
```

### 16. No Input Validation
**Severity:** MEDIUM
**Files:** KeyLibraryViewModel.swift, ImportViewModel.swift

**Issue:** User input not validated before service calls.

```swift
// KeyLibraryViewModel.swift (line 43)
func createKey(name: String, pin: String) async {
    do {
        let keyFile = try await keyManagementService.createKey(name: name, pin: pin)
        // No checks for empty name, PIN strength, etc.
    }
}

// KeyManagementService.swift (line 98)
func createKey(name: String, pin: String) async throws -> KeyFile {
    // Only generates key, doesn't validate inputs
}
```

**Recommendation:**
```swift
enum ValidationError: LocalizedError {
    case emptyKeyName
    case weakPin
    case invalidKeyName

    var errorDescription: String? {
        switch self {
        case .emptyKeyName:
            return "Key name cannot be empty"
        case .weakPin:
            return "PIN must be at least 6 digits"
        case .invalidKeyName:
            return "Key name contains invalid characters"
        }
    }
}

func createKey(name: String, pin: String) async throws -> KeyFile {
    guard !name.trimmingCharacters(in: .whitespaces).isEmpty else {
        throw ValidationError.emptyKeyName
    }

    guard pin.count >= 6 && pin.allSatisfy({ $0.isNumber }) else {
        throw ValidationError.weakPin
    }

    // Continue with creation
}
```

### 17. No Logger Infrastructure
**Severity:** MEDIUM
**Files:** All files with `print()` statements

**Issue:** `print()` statements scattered throughout, no structured logging.

```swift
// KeyLibraryViewModel.swift
print("Failed to load keys: \(error)")

// LFSImportService.swift
print("📥 Received LFS file with key name: '\(lfsFile.keyName)'")
```

**Problems:**
1. No log levels
2. No filtering capability
3. Logs appear in production builds
4. Hard to aggregate or search logs

**Recommendation:**
```swift
import os.log

final class Logger {
    static let app = Logger(category: "app")
    private let log: os.Logger

    init(category: String) {
        self.log = os.Logger(subsystem: "com.locafoto.app", category: category)
    }

    func debug(_ message: String) {
        log.debug("\(message)")
    }

    func error(_ message: String, error: Error? = nil) {
        log.error("\(message) - \(error?.localizedDescription ?? "")")
    }
}

// Usage
Logger.app.debug("Received LFS file with key name: '\(lfsFile.keyName)'")
```

### 18. Tight Coupling to Specific Services
**Severity:** MEDIUM
**Files:** ViewModels

**Issue:** ViewModels directly instantiate services, hard to test.

```swift
// CameraViewModel.swift (lines 14-15)
private var encryptionService = EncryptionService()
private var storageService = StorageService()
```

**Problems:**
1. Cannot mock for testing
2. Cannot swap implementations
3. Hard to manage lifetimes

**Recommendation:**
```swift
protocol EncryptionServiceProtocol {
    func encryptPhoto(_ photoData: Data) async throws -> EncryptedPhoto
}

@MainActor
class CameraViewModel: ObservableObject {
    let encryptionService: EncryptionServiceProtocol
    let storageService: StorageServiceProtocol

    init(
        encryptionService: EncryptionServiceProtocol = EncryptionService(),
        storageService: StorageServiceProtocol = StorageService()
    ) {
        self.encryptionService = encryptionService
        self.storageService = storageService
    }
}
```

---

## ARCHITECTURE ISSUES

### 19. No Dependency Injection Container
**Severity:** MEDIUM

**Issue:** Services instantiated separately in each ViewModel, duplicated across app.

**Current Pattern:**
```swift
class CameraViewModel: ObservableObject {
    private let encryptionService = EncryptionService()  // New instance
}

class ImportViewModel: ObservableObject {
    private let importService = PhotoImportService()    // Another instance
}
```

**Recommendation:** Implement service container:
```swift
@MainActor
class ServiceContainer {
    static let shared = ServiceContainer()

    lazy var encryptionService = EncryptionService()
    lazy var storageService = StorageService()
    lazy var keyManagementService = KeyManagementService()

    // All ViewModels share same instances
}

class CameraViewModel: ObservableObject {
    private let encryptionService = ServiceContainer.shared.encryptionService
}
```

### 20. No Abstraction for File Operations
**Severity:** MEDIUM
**Files:** StorageService.swift, KeyManagementService.swift, LFSFileTrackingService.swift

**Issue:** Direct `FileManager` usage not abstracted, hard to test or substitute.

**Recommendation:**
```swift
protocol FileStorageProtocol {
    func write(_ data: Data, to url: URL) throws
    func read(from url: URL) throws -> Data
    func delete(at url: URL) throws
    func fileExists(at url: URL) -> Bool
}

class FileSystemStorage: FileStorageProtocol {
    private let fileManager = FileManager.default

    func write(_ data: Data, to url: URL) throws {
        try data.write(to: url)
    }

    // Implement other methods...
}
```

### 21. Actor Misuse - Unnecessary Actor Annotations
**Severity:** LOW
**Files:** All Services

**Issue:** Most services marked as `actor` but used synchronously from main thread.

```swift
actor StorageService {
    func savePhoto(_ encryptedPhoto: EncryptedPhoto, thumbnail: Data) async throws {
        // Mostly file I/O that doesn't benefit from actor isolation
    }
}
```

**Impact:** Adds overhead without benefit if not leveraging concurrent access.

**Recommendation:** Use `nonisolated` for thread-safe operations or remove `actor` if sequential.

### 22. In-Memory Photo Store Not Production-Ready
**Severity:** HIGH
**File:** StorageService.swift (lines 163-186)

**Issue:** Photo metadata stored in-memory array, lost on app termination.

```swift
actor PhotoStore {
    static let shared = PhotoStore()
    private var photos: [Photo] = []  // Lost on app close!

    func add(_ photo: Photo) throws {
        photos.append(photo)  // Not persisted
    }
}
```

**Problems:**
1. No persistence between app launches
2. No query capabilities
3. Performance degrades with large collections

**Recommendation:** Migrate to CoreData or SQLite:
```swift
// Use CoreData @FetchRequest in views
@FetchRequest(
    entity: PhotoEntity.entity(),
    sortDescriptors: [NSSortDescriptor(keyPath: \PhotoEntity.captureDate, ascending: false)]
) var photos: FetchedResults<PhotoEntity>
```

---

## SUMMARY TABLE

| Category | Issue | Severity | File(s) |
|----------|-------|----------|---------|
| **Critical** | Missing `encryptPhotoData` method | CRITICAL | EncryptionService.swift |
| Security | PIN salt deletion vulnerability | HIGH | KeyManagementService.swift |
| Security | No memory clearing for PIN | MEDIUM | KeyManagementService.swift |
| Performance | UIGraphics context leaks | HIGH | Multiple ViewModels |
| Performance | Full photo decryption for thumbnail | HIGH | LFSImportService.swift |
| Error Handling | Silent failures in ViewModels | MEDIUM | Multiple ViewModels |
| Code Quality | No input validation | MEDIUM | Multiple files |
| Code Quality | Duplicate code (thumbnail generation) | LOW | 3 files |
| Architecture | In-memory photo store | HIGH | StorageService.swift |
| Architecture | No dependency injection | MEDIUM | All ViewModels |

---

## RECOMMENDED PRIORITY

1. **Immediate (Blocking Release):**
   - Add missing `encryptPhotoData` method
   - Fix in-memory photo store with CoreData
   - Fix UIGraphics context leaks

2. **High Priority:**
   - Add input validation
   - Implement error presentation to users
   - Add logging infrastructure
   - Fix PIN memory security

3. **Medium Priority:**
   - Extract duplicate code
   - Implement dependency injection
   - Optimize thumbnail handling
   - Add LFS file validation

4. **Low Priority:**
   - Consolidate file path handling
   - Review actor usage
   - Cache keychain queries
