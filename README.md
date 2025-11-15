# Locafoto 🔒

Privacy-focused iOS photo management app with local encryption, PIN-based security, and secure sharing via AirDrop.

## Overview

Locafoto is an iOS application that gives you complete control over your photos with military-grade encryption. Capture photos that never touch your Camera Roll, store them with AES-256 encryption, and share them securely with other Locafoto users via AirDrop using two different encryption schemes.

### Key Features

✅ **PIN-Based Security** - Master key derived from your PIN using PBKDF2
✅ **Direct Camera Capture** - Take photos that bypass Camera Roll entirely
✅ **Local Encryption** - AES-256-GCM encryption for all photos
✅ **Camera Roll Import** - Import and encrypt existing photos
✅ **Secure Gallery** - View your encrypted photos with fast thumbnails
✅ **Dual Sharing Modes** - Share via .locaphoto or .lfs formats
✅ **External Encryption Support** - Import .lfs files encrypted outside the app
✅ **Key Management** - Create and manage encryption keys with PIN protection
✅ **Complete Privacy** - No cloud, no tracking, no data collection

## Why Locafoto?

### The Problem

When you take a photo on your iPhone:
- It's automatically saved to Camera Roll
- It's visible to any app with photo access
- It might sync to iCloud
- You can't prevent it from being stored unencrypted
- Sharing encrypted photos is complex

### The Solution

Locafoto gives you a choice:
- **Capture photos directly** - Never saved to Camera Roll
- **Encrypt everything** - Photos stored with AES-256-GCM encryption
- **PIN-protected keys** - Master key derived from your PIN
- **Share securely** - Two encryption formats (.locaphoto and .lfs)
- **External encryption** - Encrypt files on your computer, import via AirDrop
- **Key sharing** - Share encryption keys with trusted contacts
- **Full control** - You decide what happens to your photos

## Quick Start

### Requirements

- iOS 15.0 or later
- Xcode 15.0+ (for building from source)
- An iPhone with a camera

### Building from Source

1. **Clone the repository**
   ```bash
   git clone https://github.com/yourusername/locafoto.git
   cd locafoto
   ```

2. **Open in Xcode**
   ```bash
   open ios/Locafoto/Locafoto.xcodeproj
   ```

3. **Configure signing**
   - Select your development team
   - Update bundle identifier if needed

4. **Build and run** (⌘R)

5. **Set up PIN** - First launch will prompt you to create a PIN

See [ios/README.md](ios/README.md) for detailed build instructions.

## How It Works

### PIN-Based Master Key

```
User enters PIN
       ↓
PBKDF2 with salt (100,000 iterations)
       ↓
Derive 256-bit master key
       ↓
Master key encrypts all encryption keys
       ↓
Keys stored encrypted at rest
```

**Security:** Your PIN never leaves the device. The master key is derived fresh each time using PBKDF2 with 100,000 iterations, making brute-force attacks computationally expensive.

### Camera Capture (No Camera Roll!)

```
User presses capture
       ↓
AVFoundation captures to memory
       ↓
Photo data never saved to Camera Roll
       ↓
Immediately encrypted with AES-256-GCM
       ↓
Stored in app's private container
```

**Your photos never touch the system Camera Roll!**

### Encryption Architecture

- **Algorithm:** AES-256-GCM (authenticated encryption)
- **Master Key:** Derived from PIN using PBKDF2, device-specific salt
- **Photo Keys (`.locaphoto`):** Unique random key per photo
- **Shared Keys (`.lfs`):** Named keys for sharing encrypted files
- **Key Encryption:** All keys encrypted with master key at rest
- **Integrity:** Authentication tags prevent tampering

## File Formats

### .locaphoto Format (Standard)

Simple encrypted photo format with embedded key:

```
┌─────────────────────────────────┐
│ JSON Bundle                     │
├─────────────────────────────────┤
│ - Photo ID                      │
│ - Encrypted photo data (base64) │
│ - Encrypted key (base64)        │
│ - IV/nonce (base64)             │
│ - Auth tag (base64)             │
│ - Metadata                      │
└─────────────────────────────────┘
```

**Use case:** Quick sharing between Locafoto users. Self-contained, no key management needed.

### .lfs Format (Locafoto Shared) - NEW! 🚀

Advanced format for external encryption and key sharing:

```
┌─────────────────────────────────┐
│ Header (128 bytes)              │
│ - Key Name (UTF-8 string)       │
│   Points to key file in app     │
├─────────────────────────────────┤
│ Encrypted Data (variable)       │
│ - AES-256-GCM encrypted content │
├─────────────────────────────────┤
│ IV/Nonce (12 bytes)             │
├─────────────────────────────────┤
│ Authentication Tag (16 bytes)   │
└─────────────────────────────────┘
```

**Key Features:**
1. **Key Pointer:** First 128 bytes contain the name of the encryption key
2. **External Encryption:** Files can be encrypted outside the app (e.g., on your computer)
3. **Key Sharing:** Multiple files can use the same encryption key
4. **Key Management:** Keys must exist in app before import
5. **Flexibility:** Share the key once, share many encrypted files

**Use cases:**
- Encrypt sensitive documents on your computer, import to phone
- Share an encryption key with trusted contacts
- Encrypt multiple photos with the same key for batch operations
- Build your own encryption tools that work with Locafoto

## Using .lfs Files

### Scenario 1: Encrypting Files Externally

You can encrypt files on your computer using standard AES-256-GCM and share them to your phone:

1. **Create encryption key** (on computer)
   ```bash
   # Generate 256-bit key
   openssl rand -hex 32 > my-key.txt
   ```

2. **Encrypt a file** (on computer - Python example)
   ```python
   from cryptography.hazmat.primitives.ciphers.aead import AESGCM
   import os

   # Read key
   with open('my-key.txt', 'r') as f:
       key_hex = f.read().strip()
       key = bytes.fromhex(key_hex)

   # Read file to encrypt
   with open('photo.jpg', 'rb') as f:
       data = f.read()

   # Encrypt
   aesgcm = AESGCM(key)
   nonce = os.urandom(12)
   ciphertext = aesgcm.encrypt(nonce, data, None)

   # Extract tag (last 16 bytes of ciphertext)
   tag = ciphertext[-16:]
   encrypted_data = ciphertext[:-16]

   # Create .lfs file
   key_name = b'my-photos-key'
   header = key_name + b'\x00' * (128 - len(key_name))  # Pad to 128 bytes
   lfs_data = header + encrypted_data + nonce + tag

   with open('photo.lfs', 'wb') as f:
       f.write(lfs_data)
   ```

3. **Import key to Locafoto**
   - Open Locafoto → Keys tab
   - Tap "+" → "Import Key File"
   - Enter name: "my-photos-key"
   - Paste hex key from my-key.txt
   - Tap "Import"

4. **Share .lfs file via AirDrop**
   - AirDrop photo.lfs to your iPhone
   - Locafoto automatically intercepts and decrypts
   - Photo appears in your gallery!

### Scenario 2: Sharing with Trusted Contacts

1. **Create a shared key**
   - Keys tab → "+" → "Create New Key"
   - Name it (e.g., "family-photos")
   - Export and share this key with trusted contacts (securely!)

2. **Export photos as .lfs**
   - View photo → Share button
   - Choose "Share as .lfs"
   - Select "family-photos" key
   - AirDrop to contacts

3. **Recipients import**
   - They must import the same key first
   - AirDrop .lfs file
   - Automatic decryption using their copy of the key

## Security

### What's Protected

✅ Master key derived from PIN using PBKDF2 (100,000 iterations)
✅ All encryption keys encrypted at rest
✅ Photos encrypted with AES-256-GCM
✅ Unique encryption key per photo (.locaphoto)
✅ Named keys for shared encryption (.lfs)
✅ Authentication tags prevent tampering
✅ Photos never leave device unencrypted
✅ PIN never stored, only salt
✅ No cloud upload or sync
✅ No telemetry or tracking

### What's Not Protected

⚠️ Device unlock + app unlock with correct PIN
⚠️ Screenshots/screen recording (OS-level limitation)
⚠️ Compromised iOS system (relies on iOS security)
⚠️ Weak PINs (use 6+ digit PINs)
⚠️ Key sharing security (securely share encryption keys out-of-band)

### PIN Security

- **PBKDF2:** 100,000 iterations with SHA-256
- **Salt:** 32-byte random salt, unique per device
- **No storage:** PIN never stored, re-derived each time
- **Key derivation:** Fresh master key on each unlock
- **Rate limiting:** (planned) Exponential backoff on failed attempts

### Privacy by Design

1. **Local-First** - All data stays on device
2. **No Cloud** - No server-side storage or processing
3. **No Tracking** - No analytics, telemetry, or data collection
4. **Open Format** - .lfs format is documented and interoperable
5. **User Control** - You choose what to preserve (metadata, etc.)
6. **External Tools** - Build your own encryption tools

## Architecture

### Tech Stack

- **Platform:** iOS 15.0+
- **Language:** Swift 5.9+
- **UI:** SwiftUI
- **Concurrency:** Swift Async/Await + Actors
- **Encryption:** CryptoKit (AES-256-GCM)
- **Key Derivation:** CommonCrypto (PBKDF2)
- **Camera:** AVFoundation
- **Import:** PhotoKit (PHPicker)

### Project Structure

```
locafoto/
├── docs/               # Technical documentation
│   └── TECHNICAL_SPEC.md
├── ios/                # iOS application
│   └── Locafoto/
│       ├── App/        # App entry point + PIN flow
│       ├── Views/      # SwiftUI views
│       ├── ViewModels/ # MVVM view models
│       ├── Services/   # Core services
│       ├── Models/     # Data models
│       └── Resources/  # Configuration
├── CLAUDE.md           # AI assistant guide
└── README.md           # This file
```

## FAQ

### Q: Can photos really bypass the Camera Roll?

**A: Yes!** By using AVFoundation's `AVCaptureSession` directly, photos are captured to memory and never saved to the system Camera Roll.

### Q: What if I forget my PIN?

**A:** All photos and keys are permanently inaccessible. There is no recovery mechanism by design. Choose a memorable PIN!

### Q: How do I share encryption keys securely?

**A:** Export the key, then share via a secure channel (Signal, encrypted email, in person). Never share keys via SMS or unencrypted messaging.

### Q: Can I use .lfs files without Locafoto?

**A:** Yes! The .lfs format uses standard AES-256-GCM. Write your own tools using any crypto library.

### Q: What's the difference between .locaphoto and .lfs?

**A:**
- **.locaphoto:** Self-contained, unique key per photo, simple sharing
- **.lfs:** Shared keys, external encryption support, bulk operations

---

**Built with privacy in mind** 🔒

*Your photos, your device, your keys, your control.*
