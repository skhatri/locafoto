# Locafoto

Privacy-focused iOS photo management with local encryption and secure sharing.

## Overview

Locafoto is an iOS application that puts you in complete control of your photos. Capture photos that never touch your Camera Roll, organize them in encrypted albums, and share them securely with other Locafoto users via AirDrop.

**Core Capabilities:**
- Direct camera capture bypassing Camera Roll
- AES-256-GCM encryption for all photos
- PIN and biometric authentication (Face ID/Touch ID)
- Album organization with multiple sort options
- Photo filters and editing
- Secure AirDrop sharing in two formats (.locaphoto and .lfs)
- External encryption support (encrypt files on your computer, decrypt on your phone)
- Encryption key management with import/export

## Quick Start

### Requirements

- iOS 15.0 or later
- Xcode 15.0+ (for building from source)
- iPhone with camera

### Building from Source

1. Clone the repository
   ```bash
   git clone https://github.com/yourusername/locafoto.git
   cd locafoto
   ```

2. Open in Xcode
   ```bash
   open ios/Locafoto/Locafoto.xcodeproj
   ```

3. Configure signing (select your development team and update bundle identifier if needed)

4. Build and run (Command+R)

5. Set up your PIN on first launch

See [ios/README.md](ios/README.md) for detailed build instructions.

## Key Features

### Privacy-First Photo Capture

Photos captured with Locafoto never touch the system Camera Roll. Using AVFoundation, photos are captured directly to memory, immediately encrypted, and stored in the app's private container.

### Strong Encryption

All photos are encrypted with AES-256-GCM authenticated encryption:
- **Master Key:** Derived from your PIN using PBKDF2 (100,000 iterations) with device-specific salt
- **Photo Keys:** Unique random encryption key per photo
- **Shared Keys:** Named keys for sharing multiple photos with the same encryption
- **Key Storage:** All keys encrypted at rest using the master key
- **Authentication:** Tags prevent tampering

### Album Organization

Create albums to organize your photos:
- Private albums with separate PIN or biometric protection
- Multiple sort options (capture date, import date, size, name)
- Photo sorting within albums
- Batch operations (move, delete, share)

### Dual Sharing Formats

**Standard Format (.locaphoto):**
- Self-contained JSON bundle with photo and encrypted key
- Simple one-tap sharing
- No key management required

**Shared Format (.lfs):**
- Uses named encryption keys
- Multiple photos can share the same key
- Supports external encryption (encrypt files on your computer)
- Import encrypted files via AirDrop

### Biometric Authentication

Optional Face ID or Touch ID support:
- Quick unlock without entering PIN
- Per-album biometric protection
- Fallback to PIN if biometric fails

### Photo Filters

Apply filters to your photos before encryption:
- Monochrome
- Sepia
- Vintage
- Chrome
- and more

## Security Model

### What's Protected

- Photos encrypted with AES-256-GCM
- Master key derived from PIN using PBKDF2 (100,000 iterations)
- All encryption keys encrypted at rest
- Unique encryption key per photo (.locaphoto format)
- Authentication tags prevent tampering
- Photos never leave device unencrypted
- No cloud storage or sync
- No telemetry or tracking

### What's Not Protected

- Weak PINs (use 6+ digit PINs)
- Screenshots or screen recording (iOS limitation)
- Compromised iOS system
- Insecure key sharing (share encryption keys through secure channels only)

### Privacy by Design

1. **Local-First:** All data stays on your device
2. **No Cloud:** No server-side storage or processing
3. **No Tracking:** No analytics or data collection
4. **User Control:** You decide what metadata to preserve
5. **Open Format:** .lfs format is documented and can be used with external tools

## File Formats

### .locaphoto (Standard Format)

Self-contained encrypted photo format:

```
{
  "id": "unique-photo-id",
  "encryptedData": "base64-encoded-ciphertext",
  "encryptedKey": "base64-encoded-key",
  "iv": "base64-encoded-nonce",
  "tag": "base64-encoded-auth-tag",
  "metadata": { ... }
}
```

Use case: Quick sharing between Locafoto users without key management.

### .lfs (Locafoto Shared Format)

Advanced format with shared keys:

```
[Header: 128 bytes - Key Name]
[Encrypted Data: variable length]
[IV/Nonce: 12 bytes]
[Authentication Tag: 16 bytes]
```

**Key Features:**
- Multiple files can use the same encryption key
- Files can be encrypted outside the app
- Keys must exist in app before import
- Standard AES-256-GCM format compatible with any crypto library

## Using External Encryption

You can encrypt files on your computer and import them to Locafoto:

### Step 1: Create and Import Encryption Key

In Locafoto:
- Open Keys tab
- Tap "+" → "Create New Key"
- Name it (e.g., "my-documents")
- Export and save the key securely

### Step 2: Encrypt Files on Your Computer

Python example:
```python
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
import os

# Read key
with open('my-key.txt', 'r') as f:
    key = bytes.fromhex(f.read().strip())

# Encrypt file
with open('document.pdf', 'rb') as f:
    data = f.read()

aesgcm = AESGCM(key)
nonce = os.urandom(12)
ciphertext = aesgcm.encrypt(nonce, data, None)

# Extract tag (last 16 bytes)
tag = ciphertext[-16:]
encrypted_data = ciphertext[:-16]

# Create .lfs file
key_name = b'my-documents'
header = key_name + b'\x00' * (128 - len(key_name))
lfs_data = header + encrypted_data + nonce + tag

with open('document.lfs', 'wb') as f:
    f.write(lfs_data)
```

### Step 3: Import via AirDrop

AirDrop the .lfs file to your iPhone. Locafoto will automatically decrypt it using the matching key.

## Architecture

### Tech Stack

- Platform: iOS 15.0+
- Language: Swift 5.9+
- UI Framework: SwiftUI
- Concurrency: Swift Async/Await + Actors
- Encryption: CryptoKit (AES-256-GCM)
- Key Derivation: CommonCrypto (PBKDF2)
- Camera: AVFoundation
- Import: PhotoKit (PHPicker)
- Biometrics: LocalAuthentication (Face ID/Touch ID)

### MVVM Architecture

```
Views (SwiftUI)
    ↓
ViewModels (State + Business Logic)
    ↓
Services (Core Functionality)
    ↓
Data Layer (FileSystem + Keychain)
```

**Services:**
- CameraService: Photo capture with AVFoundation
- EncryptionService: AES-256-GCM encryption/decryption
- StorageService: File system operations
- KeyManagementService: Encryption key management
- SharingService: AirDrop integration
- BiometricService: Face ID/Touch ID authentication
- AlbumService: Album organization
- FilterService: Photo filters

## Project Structure

```
locafoto/
├── docs/                    # Technical documentation
│   └── TECHNICAL_SPEC.md
├── ios/                     # iOS application
│   └── Locafoto/
│       ├── App/             # App entry point + PIN flow
│       ├── Views/           # SwiftUI views
│       ├── ViewModels/      # MVVM view models
│       ├── Services/        # Core services
│       ├── Models/          # Data models
│       └── Resources/       # Configuration
├── CLAUDE.md                # AI assistant guide
└── README.md                # This file
```

## FAQ

**Can photos really bypass the Camera Roll?**

Yes. Using AVFoundation's AVCaptureSession directly, photos are captured to memory and never saved to the system Camera Roll.

**What if I forget my PIN?**

All photos and keys are permanently inaccessible. There is no recovery mechanism by design. Choose a memorable PIN.

**How do I share encryption keys securely?**

Export the key, then share via a secure channel like Signal or encrypted email. Never share keys via SMS or unencrypted messaging.

**Can I use .lfs files without Locafoto?**

Yes. The .lfs format uses standard AES-256-GCM. You can write your own encryption/decryption tools using any crypto library.

**What's the difference between .locaphoto and .lfs?**

- .locaphoto: Self-contained, unique key per photo, simple sharing
- .lfs: Shared keys, external encryption support, bulk operations, compatible with external tools

**Does Locafoto support biometric authentication?**

Yes. You can use Face ID or Touch ID to unlock the app and individual albums as an alternative to PIN entry.

## Contributing

See [CLAUDE.md](CLAUDE.md) for development guidelines and project conventions.

For detailed technical specifications, see [docs/TECHNICAL_SPEC.md](docs/TECHNICAL_SPEC.md).

## Note on Screenshots

This README currently uses text-based diagrams. Screenshots showing the actual app interface would provide better context. To add screenshots:

1. Create a `screenshots/` directory in the project root
2. Take screenshots of key features (camera view, gallery, album management, settings)
3. Add images with descriptive names (e.g., `gallery-view.png`, `camera-capture.png`)
4. Update this README with image references

---

**Your photos, your device, your keys, your control.**
