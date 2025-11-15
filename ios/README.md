# Locafoto iOS App

Privacy-focused photo management app with local encryption and secure AirDrop sharing.

## Features

### ✅ Implemented (Proof of Concept)

1. **Direct Camera Capture** - Capture photos without saving to Camera Roll
   - Uses AVFoundation's AVCaptureSession
   - Photos stay in memory, never touch system photo library
   - Immediate encryption upon capture

2. **Local Encryption** - AES-256-GCM encryption for all photos
   - Master key stored in iOS Keychain
   - Unique per-photo encryption keys
   - Authenticated encryption with integrity verification

3. **Camera Roll Import** - Import existing photos with encryption
   - PHPicker integration for privacy-friendly selection
   - Batch import support
   - Progress tracking

4. **AirDrop Sharing** - Share encrypted photos between Locafoto users
   - Custom .locaphoto file format
   - Encrypted during transfer
   - Only Locafoto apps can decrypt

5. **Secure Gallery** - View encrypted photos
   - Thumbnail generation for performance
   - On-demand decryption
   - Fast scrolling with lazy loading

## Project Structure

```
ios/Locafoto/
├── App/
│   └── LocafotoApp.swift          # Main app entry point
├── Views/
│   ├── ContentView.swift          # Main tab view
│   ├── CameraView.swift           # Camera capture UI
│   ├── GalleryView.swift          # Photo gallery
│   ├── ImportView.swift           # Import from Camera Roll
│   └── SettingsView.swift         # App settings
├── ViewModels/
│   ├── CameraViewModel.swift      # Camera logic
│   ├── GalleryViewModel.swift     # Gallery logic
│   └── ImportViewModel.swift      # Import logic
├── Services/
│   ├── CameraService.swift        # Camera capture (AVFoundation)
│   ├── EncryptionService.swift    # Encryption/decryption (CryptoKit)
│   ├── SharingService.swift       # AirDrop sharing
│   ├── PhotoImportService.swift   # Camera Roll import
│   └── StorageService.swift       # File system storage
├── Models/
│   └── Photo.swift                # Photo data models
└── Resources/
    └── Info.plist                 # App configuration & permissions
```

## Tech Stack

- **Platform:** iOS 15.0+
- **Language:** Swift 5.9+
- **UI:** SwiftUI
- **Concurrency:** Swift Async/Await + Actors
- **Frameworks:**
  - AVFoundation - Camera capture
  - CryptoKit - Encryption
  - PhotoKit - Camera Roll access
  - UniformTypeIdentifiers - Custom file types

## Key Implementation Details

### Camera Capture (No Camera Roll)

```swift
// CameraService.swift - Captures photo to memory only
func capturePhoto(output: AVCapturePhotoOutput) async throws -> Data {
    // Photo data stays in memory - never saved to Camera Roll
    let photoData = photo.fileDataRepresentation()
    return photoData // Will be encrypted immediately
}
```

**Answer to "Can we prevent Camera Roll storage?"**
✅ **YES!** By using `AVCaptureSession` directly, photos never touch the Camera Roll.

### Encryption Architecture

```
Photo Capture/Import
        ↓
  Generate Random Key (256-bit)
        ↓
  Encrypt Photo with AES-256-GCM
        ↓
  Encrypt Key with Master Key
        ↓
  Store: Encrypted Photo + Encrypted Key
```

- **Master Key:** Stored in iOS Keychain, never leaves device
- **Photo Keys:** Unique per photo, encrypted with master key
- **Algorithm:** AES-256-GCM (authenticated encryption)

### AirDrop Sharing (.locaphoto format)

```json
{
  "version": "1.0",
  "photo": {
    "id": "uuid",
    "encryptedData": "base64...",
    "encryptedKey": "base64...",
    "iv": "base64...",
    "authTag": "base64..."
  },
  "metadata": { ... }
}
```

Photos shared via AirDrop remain encrypted. Only Locafoto can decrypt them.

## Building the Project

### Requirements

- Xcode 15.0+
- iOS 15.0+ device or simulator
- Apple Developer account (for device deployment)

### Setup

1. Open Xcode and create a new iOS App project:
   - Name: Locafoto
   - Bundle ID: com.yourcompany.locafoto
   - Interface: SwiftUI
   - Language: Swift

2. Replace the default files with the ones from this repository

3. Update signing & capabilities:
   - Select your development team
   - Enable capabilities:
     - [ ] App Sandbox (off - not needed for iOS)
     - [x] Keychain Sharing (optional, for iCloud sync later)

4. Build and run (⌘R)

### Permissions

The app will request:
- **Camera Access** - To capture photos
- **Photo Library Access** - To import from Camera Roll

### Testing

**Camera Capture:**
1. Open Camera tab
2. Point at something
3. Tap capture button
4. Photo is encrypted and saved (never in Camera Roll!)
5. View in Gallery tab

**Import:**
1. Open Import tab
2. Tap "Select Photos"
3. Choose photos from Camera Roll
4. Photos are imported and encrypted
5. View in Gallery tab

**AirDrop Sharing:**
1. Open Gallery tab
2. Tap a photo to view full size
3. Tap share button (top right)
4. Select AirDrop
5. Send to another device with Locafoto
6. Receiving device auto-imports the encrypted photo

## Security Features

- ✅ AES-256-GCM encryption
- ✅ Unique keys per photo
- ✅ Master key in Keychain (device-specific)
- ✅ Authenticated encryption (prevents tampering)
- ✅ Photos never leave device unencrypted
- ✅ No cloud upload
- ✅ No telemetry or tracking

## Future Enhancements

- [ ] CoreData integration (replace in-memory storage)
- [ ] Albums and organization
- [ ] Search functionality
- [ ] Face detection and tagging
- [ ] Export to Camera Roll (decrypted)
- [ ] Encrypted iCloud backup
- [ ] Public key encryption for selective sharing
- [ ] Video support
- [ ] Biometric authentication

## Privacy by Design

1. **No Camera Roll Storage** - Photos captured in-app never touch Camera Roll
2. **Local-First** - All data stored on device
3. **End-to-End Encryption** - Photos encrypted immediately
4. **No Cloud** - No server-side storage or processing
5. **Metadata Control** - User chooses what to preserve
6. **Open Format** - .locaphoto format is documented

## Known Limitations (POC)

1. **In-Memory Storage** - Photo metadata stored in memory (use CoreData in production)
2. **No Persistence** - Metadata lost on app restart (use CoreData)
3. **No Albums** - All photos in one gallery
4. **No Search** - Can't search by date, tag, etc.
5. **Basic UI** - Minimal styling and polish
6. **No Error Recovery** - Limited error handling
7. **No Background Processing** - Import/encryption blocks UI

## Production Checklist

Before shipping to App Store:

- [ ] Replace in-memory storage with CoreData
- [ ] Add comprehensive error handling
- [ ] Implement background processing for imports
- [ ] Add unit tests (CryptoKit, services)
- [ ] Add UI tests (camera, gallery flows)
- [ ] Performance testing (large libraries)
- [ ] Memory profiling (prevent leaks)
- [ ] Security audit
- [ ] Privacy policy
- [ ] App Store screenshots and description
- [ ] TestFlight beta testing

## Contributing

See [CLAUDE.md](../../CLAUDE.md) for development guidelines and conventions.

## License

TBD

---

**Built with privacy in mind** 🔒
