# Locafoto Technical Specification

**Version:** 1.0
**Last Updated:** 2025-11-15
**Status:** Initial Design

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Core Features](#core-features)
3. [Architecture Overview](#architecture-overview)
4. [Photo Capture System](#photo-capture-system)
5. [Encryption System](#encryption-system)
6. [AirDrop Sharing](#airdrop-sharing)
7. [Data Storage](#data-storage)
8. [Security Considerations](#security-considerations)
9. [Implementation Roadmap](#implementation-roadmap)

---

## Executive Summary

Locafoto is a privacy-focused iOS photo management application that enables users to:
- Capture photos directly without saving to Camera Roll
- Import existing photos from Camera Roll
- Store photos with local encryption
- Share encrypted photos via AirDrop with other Locafoto users

**Key Privacy Feature:** Photos can be captured and stored exclusively within the app, never touching the system Camera Roll, providing complete privacy and control.

---

## Core Features

### 1. Photo Capture (Without Camera Roll)

**Capability:** Capture photos directly into the app using AVFoundation, completely bypassing the Camera Roll.

**User Benefits:**
- Complete privacy - photos never leave the app
- No clutter in Camera Roll
- Immediate encryption at capture time
- Faster workflow (no save/import cycle)

**Technical Approach:**
- Use `AVCaptureSession` with `AVCapturePhotoOutput`
- Process photo data in memory
- Encrypt immediately upon capture
- Store in app's private container

### 2. Photo Import (From Camera Roll)

**Capability:** Import existing photos from Camera Roll into encrypted storage.

**User Benefits:**
- Migrate existing photos to private storage
- Selective import with preview
- Optional: Delete from Camera Roll after import

**Technical Approach:**
- Use `PHPickerViewController` (iOS 14+) for privacy-friendly selection
- Read photo data and metadata
- Encrypt and store in app container
- Optionally delete original (with user confirmation)

### 3. Local Encryption

**Capability:** All photos stored with strong encryption using device-specific keys.

**User Benefits:**
- Photos unreadable without app
- Secure even if device is jailbroken
- Protection against unauthorized access

**Technical Approach:**
- AES-256-GCM encryption for photo data
- ChaCha20-Poly1305 as alternative for performance
- Keys stored in iOS Keychain
- Per-photo encryption with unique keys
- Master key derived from device-specific data

### 4. AirDrop Sharing (Encrypted)

**Capability:** Share encrypted photos with other Locafoto users via AirDrop.

**User Benefits:**
- Share without uploading to cloud
- Direct device-to-device transfer
- Photos remain encrypted during transfer
- Only Locafoto users can decrypt

**Technical Approach:**
- Custom UTI (Uniform Type Identifier) registration
- UIActivityViewController for AirDrop
- Share encrypted bundle with metadata
- Key exchange mechanism for decryption

---

## Architecture Overview

### Technology Stack

**Platform:** iOS 15.0+
**Language:** Swift 5.9+
**UI Framework:** SwiftUI
**Concurrency:** Swift Async/Await + Actors

**Key Frameworks:**
- **AVFoundation** - Camera capture
- **PhotoKit** - Camera Roll access
- **CryptoKit** - Encryption/decryption
- **CoreData** - Metadata storage
- **UniformTypeIdentifiers** - Custom file type registration

### App Architecture

```
┌─────────────────────────────────────────────────┐
│                    SwiftUI Views                 │
│  (CameraView, GalleryView, SettingsView, etc.)  │
└─────────────────┬───────────────────────────────┘
                  │
┌─────────────────▼───────────────────────────────┐
│              ViewModels (MVVM)                   │
│   (CameraViewModel, GalleryViewModel, etc.)     │
└─────────────────┬───────────────────────────────┘
                  │
┌─────────────────▼───────────────────────────────┐
│                Service Layer                     │
│  ┌──────────────┐  ┌──────────────┐            │
│  │ PhotoCapture │  │ PhotoImport  │            │
│  │   Service    │  │   Service    │            │
│  └──────────────┘  └──────────────┘            │
│  ┌──────────────┐  ┌──────────────┐            │
│  │  Encryption  │  │   Sharing    │            │
│  │   Service    │  │   Service    │            │
│  └──────────────┘  └──────────────┘            │
└─────────────────┬───────────────────────────────┘
                  │
┌─────────────────▼───────────────────────────────┐
│              Storage Layer                       │
│  ┌──────────────┐  ┌──────────────┐            │
│  │   CoreData   │  │  FileSystem  │            │
│  │  (Metadata)  │  │  (Encrypted) │            │
│  └──────────────┘  └──────────────┘            │
│  ┌──────────────┐                               │
│  │   Keychain   │                               │
│  │    (Keys)    │                               │
│  └──────────────┘                               │
└─────────────────────────────────────────────────┘
```

---

## Photo Capture System

### Direct Camera Capture (Bypassing Camera Roll)

**Implementation Strategy:**

```swift
// High-level flow
1. Request camera permission
2. Set up AVCaptureSession
3. Configure photo output settings
4. Capture photo to memory buffer
5. Process image data
6. Encrypt immediately
7. Save to app container
8. Never write to Camera Roll
```

**Key Components:**

#### CameraService

```swift
actor CameraService {
    private var captureSession: AVCaptureSession?
    private var photoOutput: AVCapturePhotoOutput?

    func setupCamera() async throws
    func capturePhoto() async throws -> Data
    func stopCamera()
}
```

**Permissions Required:**
- `NSCameraUsageDescription` in Info.plist
- Runtime permission request

**Image Processing Pipeline:**
1. Capture RAW photo data
2. Extract EXIF metadata (optional)
3. Generate thumbnail
4. Compress to desired format (JPEG/HEIC)
5. Pass to encryption service

### Camera Roll Import

**Implementation Strategy:**

```swift
// High-level flow
1. Request photo library permission
2. Present PHPickerViewController
3. User selects photos
4. Load photo data asynchronously
5. Extract metadata
6. Encrypt each photo
7. Save to app container
8. Optionally: Delete from Camera Roll
```

**Key Components:**

#### PhotoImportService

```swift
actor PhotoImportService {
    func presentPicker() -> PHPickerViewController
    func importPhotos(_ results: [PHPickerResult]) async throws -> [ImportedPhoto]
    func deleteFromCameraRoll(_ identifiers: [String]) async throws
}
```

**Permissions Required:**
- `NSPhotoLibraryUsageDescription` in Info.plist
- Runtime permission request (read)
- Additional permission for deletion (if implemented)

---

## Encryption System

### Encryption Architecture

**Approach:** Hybrid encryption with unique per-photo keys

**Components:**
1. **Master Key:** Device-specific, stored in Keychain
2. **Photo Keys:** Unique per photo, encrypted with Master Key
3. **Encrypted Photo Data:** AES-256-GCM encrypted
4. **Metadata:** Stored separately in CoreData

### Encryption Specification

#### Algorithm Selection

**Photo Data Encryption:**
- **Primary:** AES-256-GCM (Galois/Counter Mode)
- **Alternative:** ChaCha20-Poly1305 (for performance)
- **Authenticated Encryption:** Prevents tampering

**Key Derivation:**
- **HKDF** (HMAC-based Key Derivation Function)
- **Source:** Device ID + App-specific salt
- **Storage:** iOS Keychain with kSecAttrAccessibleWhenUnlockedThisDeviceOnly

#### Encryption Flow

```
┌──────────────┐
│  Photo Data  │
└──────┬───────┘
       │
       ▼
┌──────────────────────┐
│  Generate Random     │
│  Symmetric Key       │
│  (256-bit)           │
└──────┬───────────────┘
       │
       ▼
┌──────────────────────┐
│  Encrypt Photo       │
│  AES-256-GCM         │
│  + Authentication    │
└──────┬───────────────┘
       │
       ▼
┌──────────────────────┐     ┌──────────────────┐
│  Encrypted Photo     │     │  Encrypt Key     │
│  (File System)       │     │  with Master Key │
└──────────────────────┘     └────────┬─────────┘
                                      │
                                      ▼
                             ┌──────────────────┐
                             │  Store Encrypted │
                             │  Key in CoreData │
                             └──────────────────┘
```

#### Data Structure

**Encrypted Photo File Format:**

```
┌────────────────────────────────────────┐
│ Header (64 bytes)                      │
├────────────────────────────────────────┤
│ - Magic Number (4 bytes): "LOCA"      │
│ - Version (2 bytes): 0x0001           │
│ - Algorithm (1 byte): 0x01 (AES-GCM)  │
│ - Reserved (1 byte)                   │
│ - IV/Nonce (12 bytes)                 │
│ - Original Size (8 bytes)             │
│ - Timestamp (8 bytes)                 │
│ - Reserved (28 bytes)                 │
├────────────────────────────────────────┤
│ Encrypted Data (variable)              │
├────────────────────────────────────────┤
│ Authentication Tag (16 bytes)          │
└────────────────────────────────────────┘
```

### Implementation

#### EncryptionService

```swift
actor EncryptionService {
    // Master key management
    func initializeMasterKey() async throws
    func getMasterKey() async throws -> SymmetricKey

    // Photo encryption
    func encryptPhoto(_ data: Data) async throws -> EncryptedPhoto
    func decryptPhoto(_ encryptedPhoto: EncryptedPhoto) async throws -> Data

    // Key management
    func generatePhotoKey() -> SymmetricKey
    func encryptKey(_ key: SymmetricKey, with masterKey: SymmetricKey) throws -> Data
    func decryptKey(_ encryptedKey: Data, with masterKey: SymmetricKey) throws -> SymmetricKey
}

struct EncryptedPhoto {
    let id: UUID
    let encryptedData: Data
    let encryptedKey: Data
    let iv: Data
    let authTag: Data
    let metadata: PhotoMetadata
}

struct PhotoMetadata {
    let originalSize: Int
    let captureDate: Date
    let width: Int?
    let height: Int?
    let format: String
}
```

---

## AirDrop Sharing

### Sharing Architecture

**Goal:** Share encrypted photos between Locafoto users via AirDrop while maintaining encryption.

### Custom UTI Registration

**Info.plist Configuration:**

```xml
<key>UTExportedTypeDeclarations</key>
<array>
    <dict>
        <key>UTTypeIdentifier</key>
        <string>com.locafoto.encrypted-photo</string>
        <key>UTTypeDescription</key>
        <string>Locafoto Encrypted Photo</string>
        <key>UTTypeConformsTo</key>
        <array>
            <string>public.data</string>
        </array>
        <key>UTTypeTagSpecification</key>
        <dict>
            <key>public.filename-extension</key>
            <array>
                <string>locaphoto</string>
            </array>
            <key>public.mime-type</key>
            <array>
                <string>application/x-locafoto-photo</string>
            </array>
        </dict>
    </dict>
</array>
```

### Sharing Flow

```
Sender Device                           Receiver Device
─────────────                           ───────────────

┌─────────────────┐
│ User selects    │
│ photo to share  │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Create share    │
│ bundle with:    │
│ - Encrypted data│
│ - Metadata      │
│ - Key (wrapped) │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Export to temp  │
│ .locaphoto file │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Present         │
│ UIActivity      │
│ (AirDrop)       │
└────────┬────────┘
         │
         │ AirDrop Transfer
         │ ─────────────────────────────►
                                         │
                                         ▼
                                  ┌─────────────────┐
                                  │ Receive file    │
                                  │ via Document    │
                                  │ Handler         │
                                  └────────┬────────┘
                                           │
                                           ▼
                                  ┌─────────────────┐
                                  │ Parse bundle    │
                                  │ Verify format   │
                                  └────────┬────────┘
                                           │
                                           ▼
                                  ┌─────────────────┐
                                  │ Unwrap key      │
                                  │ with Master Key │
                                  └────────┬────────┘
                                           │
                                           ▼
                                  ┌─────────────────┐
                                  │ Import to       │
                                  │ local gallery   │
                                  └─────────────────┘
```

### Key Exchange Strategy

**Option 1: Shared Master Key (Initial Implementation)**
- All Locafoto instances share same master key derivation
- Simplest implementation
- Photos encrypted with device-specific key
- Receiver can decrypt using their master key

**Option 2: Public Key Cryptography (Future Enhancement)**
- Each device has public/private key pair
- Share encrypted symmetric key using recipient's public key
- More secure, supports selective sharing
- Requires key distribution mechanism

**Initial Implementation: Option 1**

Rationale: Simpler for MVP, all Locafoto users can share with each other seamlessly.

### Implementation

#### SharingService

```swift
actor SharingService {
    // Export for sharing
    func createShareBundle(for photo: EncryptedPhoto) async throws -> URL
    func presentShareSheet(for bundleURL: URL) -> UIActivityViewController

    // Import from share
    func handleIncomingShare(from url: URL) async throws -> ImportedPhoto
    func importSharedPhoto(_ photo: ImportedPhoto) async throws
}

// Document handling
class DocumentHandler {
    func application(_ app: UIApplication,
                    open url: URL,
                    options: [UIApplication.OpenURLOptionsKey : Any]) -> Bool
}
```

**Share Bundle Format (.locaphoto file):**

```json
{
  "version": "1.0",
  "photo": {
    "id": "uuid-string",
    "encryptedData": "base64-encoded-encrypted-photo",
    "encryptedKey": "base64-encoded-encrypted-key",
    "iv": "base64-encoded-iv",
    "authTag": "base64-encoded-tag"
  },
  "metadata": {
    "originalSize": 2048576,
    "captureDate": "2025-11-15T10:30:00Z",
    "width": 4032,
    "height": 3024,
    "format": "HEIC"
  },
  "signature": "sha256-hash-of-bundle"
}
```

---

## Data Storage

### Storage Architecture

**Three-tier storage:**

1. **Encrypted Photo Files** - File System
2. **Photo Metadata** - CoreData
3. **Encryption Keys** - Keychain

### File System Layout

```
App Container/
└── Library/
    └── Application Support/
        └── Locafoto/
            ├── Photos/
            │   ├── 2025/
            │   │   ├── 11/
            │   │   │   ├── {uuid}.encrypted
            │   │   │   └── {uuid}.encrypted
            │   │   └── 12/
            │   └── 2026/
            └── Thumbnails/
                └── {uuid}.thumb
```

**File Naming:**
- Photos: `{UUID}.encrypted`
- Thumbnails: `{UUID}.thumb` (also encrypted)
- Organized by year/month for performance

### CoreData Schema

```swift
@Model
class Photo {
    @Attribute(.unique) var id: UUID
    var encryptedKeyData: Data
    var ivData: Data
    var authTagData: Data

    var captureDate: Date
    var importDate: Date
    var modifiedDate: Date

    var originalSize: Int64
    var encryptedSize: Int64

    var width: Int32?
    var height: Int32?
    var format: String

    var filePath: String
    var thumbnailPath: String?

    var tags: [String]
    var isFavorite: Bool
    var isHidden: Bool

    @Relationship(deleteRule: .cascade) var album: Album?
}

@Model
class Album {
    @Attribute(.unique) var id: UUID
    var name: String
    var createdDate: Date
    var coverPhotoID: UUID?

    @Relationship(deleteRule: .nullify, inverse: \Photo.album)
    var photos: [Photo]
}
```

### Keychain Storage

**Master Key Storage:**

```swift
let query: [String: Any] = [
    kSecClass as String: kSecClassKey,
    kSecAttrApplicationTag as String: "com.locafoto.masterkey",
    kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
    kSecValueData as String: masterKeyData
]
```

**Security Attributes:**
- `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` - Never backed up, device-specific
- `kSecAttrSynchronizable`: false - Never sync to iCloud
- `kSecUseDataProtectionKeychain`: true - Enhanced protection

---

## Security Considerations

### Threat Model

**Protected Against:**
1. **Device theft** - Photos encrypted, keys in Keychain
2. **Unauthorized app access** - App sandbox isolation
3. **iCloud backup exposure** - Keys never backed up
4. **Jailbreak/root access** - Strong encryption even with file access
5. **Man-in-the-middle** - AirDrop uses encrypted channel
6. **Tampering** - Authentication tags verify integrity

**Not Protected Against:**
1. **Device unlock + app access** - User must protect device password
2. **Backup of entire device** - Encrypted photos backed up (keys are not)
3. **Screenshot/screen recording** - OS-level capability
4. **Compromised iOS system** - Relies on iOS security

### Security Best Practices

#### Key Management

✅ **DO:**
- Use iOS Keychain for all keys
- Generate cryptographically random keys
- Use device-specific key derivation
- Never log or print keys
- Clear key material from memory after use

❌ **DON'T:**
- Store keys in UserDefaults or files
- Use predictable key derivation
- Synchronize keys to iCloud
- Hardcode any cryptographic material

#### Encryption

✅ **DO:**
- Use authenticated encryption (GCM mode)
- Generate unique IV/nonce per encryption
- Verify authentication tags before decryption
- Use standard algorithms (AES-256, ChaCha20)

❌ **DON'T:**
- Reuse IVs/nonces
- Use ECB mode
- Implement custom crypto
- Skip authentication

#### Data Handling

✅ **DO:**
- Minimize time decrypted data in memory
- Use autoreleasepool for large operations
- Securely delete temporary files
- Validate all incoming data

❌ **DON'T:**
- Keep decrypted photos in memory unnecessarily
- Write decrypted data to temp files
- Trust file extensions for validation
- Skip input validation

### Privacy Considerations

**Camera Roll Bypass:**
- Completely optional - user choice
- Clear UI indication of where photos are stored
- Explain privacy benefits

**AirDrop Sharing:**
- Only share what user explicitly selects
- No automatic cloud upload
- Encrypted during transfer
- Only Locafoto users can decrypt

**Metadata:**
- Strip EXIF location data (optional)
- User control over what metadata to preserve
- No telemetry or analytics on photo content

---

## Implementation Roadmap

### Phase 1: Core Foundation (Week 1-2)

**Goals:**
- Basic app structure
- Camera capture working
- Local storage (unencrypted first)

**Deliverables:**
- [ ] SwiftUI app scaffold
- [ ] Camera permission flow
- [ ] AVFoundation camera capture
- [ ] Save photos to app container
- [ ] Display gallery of captured photos
- [ ] CoreData schema implementation

### Phase 2: Encryption (Week 3-4)

**Goals:**
- Implement encryption system
- Secure key management

**Deliverables:**
- [ ] EncryptionService implementation
- [ ] Keychain integration
- [ ] Master key generation/storage
- [ ] Encrypt photos on capture
- [ ] Decrypt for viewing
- [ ] Migration: encrypt existing photos

### Phase 3: Import Feature (Week 5)

**Goals:**
- Import from Camera Roll
- Optional deletion

**Deliverables:**
- [ ] PHPicker integration
- [ ] Batch import flow
- [ ] Progress indicator
- [ ] Optional Camera Roll deletion
- [ ] Import confirmation UI

### Phase 4: AirDrop Sharing (Week 6-7)

**Goals:**
- Share encrypted photos
- Receive shared photos

**Deliverables:**
- [ ] Custom UTI registration
- [ ] Share bundle creation
- [ ] UIActivityViewController integration
- [ ] Document handler
- [ ] Import shared photos
- [ ] Error handling for invalid shares

### Phase 5: Polish & Features (Week 8+)

**Goals:**
- UI refinement
- Additional features
- Testing

**Deliverables:**
- [ ] Albums/organization
- [ ] Search functionality
- [ ] Favorite/hide photos
- [ ] Settings screen
- [ ] Export to Camera Roll (decrypted)
- [ ] Comprehensive testing
- [ ] Performance optimization
- [ ] App Store preparation

---

## Technical Questions & Answers

### Q: Can we completely prevent photos from going to Camera Roll?

**A: YES!** By using `AVCaptureSession` directly instead of `UIImagePickerController`, you have complete control over the photo data. The photo exists only in memory and can be saved exclusively to your app's container.

**Implementation:**
```swift
// This captures photo without saving anywhere
let photoOutput = AVCapturePhotoOutput()
let photoSettings = AVCapturePhotoSettings()

// Capture to memory
photoOutput.capturePhoto(with: photoSettings, delegate: self)

// In delegate:
func photoOutput(_ output: AVCapturePhotoOutput,
                didFinishProcessingPhoto photo: AVCapturePhoto,
                error: Error?) {
    guard let imageData = photo.fileDataRepresentation() else { return }

    // imageData is in memory - never saved to Camera Roll
    // Now encrypt and save to your app container
    await encryptAndSave(imageData)
}
```

### Q: Can users still access Camera Roll if needed?

**A: YES!** You can provide both options:
- **Capture in app** - Never touches Camera Roll (private)
- **Import from Camera Roll** - For existing photos
- **Export to Camera Roll** - If user wants to share elsewhere

### Q: What happens if app is deleted?

**A:** All photos and keys are permanently deleted. This is a feature:
- User must backup if they want persistence
- Could implement encrypted backup to iCloud (future)
- Could implement export all photos feature

### Q: Performance with large libraries?

**A:**
- Encryption/decryption is fast with hardware acceleration
- Lazy loading and pagination for gallery
- Thumbnail generation for smooth scrolling
- Background processing for batch operations

### Q: Storage size impact?

**A:**
- Encrypted files are slightly larger (metadata + auth tag)
- Overhead: ~80 bytes per photo
- Negligible for typical photo sizes (2-10 MB)

---

## Next Steps

1. **Review this specification** - Provide feedback/questions
2. **Set up iOS project** - Create Xcode project structure
3. **Implement Phase 1** - Basic camera capture
4. **Iterate and refine** - Build incrementally

---

## Appendix

### Useful Resources

- [Apple CryptoKit Documentation](https://developer.apple.com/documentation/cryptokit)
- [AVFoundation Camera Capture](https://developer.apple.com/documentation/avfoundation/cameras_and_media_capture)
- [PHPicker Documentation](https://developer.apple.com/documentation/photokit/phpickerviewcontroller)
- [iOS App Security Best Practices](https://developer.apple.com/documentation/security)

### Glossary

- **AES-256-GCM:** Advanced Encryption Standard with 256-bit key in Galois/Counter Mode
- **UTI:** Uniform Type Identifier - iOS system for declaring file types
- **HKDF:** HMAC-based Key Derivation Function
- **IV:** Initialization Vector (also called nonce in GCM)
- **Authentication Tag:** Cryptographic checksum proving data integrity
- **AVFoundation:** Apple's framework for audiovisual media
- **PhotoKit:** Apple's framework for accessing the photo library

---

**Document Status:** Living document - update as decisions are made and implementation progresses.
