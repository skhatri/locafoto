# Locafoto 🔒

Privacy-focused iOS photo management app with local encryption and secure sharing.

## Overview

Locafoto is an iOS application that gives you complete control over your photos with military-grade encryption. Capture photos that never touch your Camera Roll, store them with AES-256 encryption, and share them securely with other Locafoto users via AirDrop.

### Key Features

✅ **Direct Camera Capture** - Take photos that bypass Camera Roll entirely
✅ **Local Encryption** - AES-256-GCM encryption for all photos
✅ **Camera Roll Import** - Import and encrypt existing photos
✅ **Secure Gallery** - View your encrypted photos with fast thumbnails
✅ **AirDrop Sharing** - Share encrypted photos with other Locafoto users
✅ **Complete Privacy** - No cloud, no tracking, no data collection

## Why Locafoto?

### The Problem

When you take a photo on your iPhone:
- It's automatically saved to Camera Roll
- It's visible to any app with photo access
- It might sync to iCloud
- You can't prevent it from being stored unencrypted

### The Solution

Locafoto gives you a choice:
- **Capture photos directly** - Never saved to Camera Roll
- **Encrypt everything** - Photos stored with AES-256-GCM encryption
- **Share securely** - AirDrop encrypted photos to other Locafoto users
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

See [ios/README.md](ios/README.md) for detailed build instructions.

## How It Works

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

### Encryption

- **Algorithm:** AES-256-GCM (authenticated encryption)
- **Master Key:** Stored in iOS Keychain, device-specific
- **Photo Keys:** Unique random key per photo
- **Key Encryption:** Photo keys encrypted with master key
- **Integrity:** Authentication tags prevent tampering

### Sharing via AirDrop

```
Select photo to share
       ↓
Create .locaphoto bundle (encrypted)
       ↓
Share via AirDrop
       ↓
Receiving Locafoto app decrypts
       ↓
Photo imported to receiver's gallery
```

Photos remain encrypted during transfer!

## Architecture

### Tech Stack

- **Platform:** iOS 15.0+
- **Language:** Swift 5.9+
- **UI:** SwiftUI
- **Concurrency:** Swift Async/Await + Actors
- **Encryption:** CryptoKit (AES-256-GCM)
- **Camera:** AVFoundation
- **Import:** PhotoKit (PHPicker)

### Project Structure

```
locafoto/
├── docs/               # Technical documentation
│   └── TECHNICAL_SPEC.md
├── ios/                # iOS application
│   └── Locafoto/
│       ├── App/        # App entry point
│       ├── Views/      # SwiftUI views
│       ├── ViewModels/ # MVVM view models
│       ├── Services/   # Core services
│       ├── Models/     # Data models
│       └── Resources/  # Configuration
├── CLAUDE.md           # AI assistant guide
└── README.md           # This file
```

## Security

### What's Protected

✅ Photos encrypted with AES-256-GCM
✅ Master key stored in iOS Keychain (device-specific)
✅ Unique encryption key per photo
✅ Authentication tags prevent tampering
✅ Photos never leave device unencrypted
✅ No cloud upload or sync
✅ No telemetry or tracking

### What's Not Protected

⚠️ Device unlock + app access (use Face ID/Touch ID lock)
⚠️ Screenshots/screen recording (OS-level limitation)
⚠️ Compromised iOS system (relies on iOS security)

### Privacy by Design

1. **Local-First** - All data stays on device
2. **No Cloud** - No server-side storage or processing
3. **No Tracking** - No analytics, telemetry, or data collection
4. **Open Format** - .locaphoto format is documented
5. **User Control** - You choose what to preserve (metadata, etc.)

## Documentation

- **[Technical Specification](docs/TECHNICAL_SPEC.md)** - Detailed architecture and implementation
- **[iOS README](ios/README.md)** - iOS-specific build and development guide
- **[CLAUDE.md](CLAUDE.md)** - AI assistant development guide

## Roadmap

### Current Status: Proof of Concept ✅

**Implemented:**
- [x] Direct camera capture (no Camera Roll)
- [x] AES-256-GCM encryption
- [x] Camera Roll import
- [x] Secure gallery with thumbnails
- [x] AirDrop sharing (.locaphoto format)

### Planned Enhancements

**v1.0 (Production Ready):**
- [ ] CoreData integration (persistent metadata)
- [ ] Albums and organization
- [ ] Search functionality
- [ ] Biometric authentication
- [ ] Export to Camera Roll (optional)
- [ ] Comprehensive testing
- [ ] App Store submission

**v1.1 (Enhanced Features):**
- [ ] Face detection and tagging
- [ ] Encrypted iCloud backup
- [ ] Video support
- [ ] Batch operations
- [ ] Advanced sharing controls

**v2.0 (Advanced):**
- [ ] Public key encryption for selective sharing
- [ ] Multi-device sync (encrypted)
- [ ] Secure photo vault
- [ ] Advanced privacy features

## Contributing

We welcome contributions! Please see [CLAUDE.md](CLAUDE.md) for development guidelines.

### Development Setup

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Write tests
5. Submit a pull request

### Code Standards

- Follow Swift API Design Guidelines
- Use SwiftUI for all UI
- Prefer async/await over callbacks
- Write descriptive commit messages
- Include tests for new features

## FAQ

### Q: Can photos really bypass the Camera Roll?

**A: Yes!** By using AVFoundation's `AVCaptureSession` directly, photos are captured to memory and never saved to the system Camera Roll. You have complete control over where they go.

### Q: What happens if I delete the app?

**A:** All photos and encryption keys are permanently deleted. Make sure to export any photos you want to keep before deleting the app.

### Q: Can I share with non-Locafoto users?

**A:** Currently, only Locafoto users can decrypt shared photos. You can export photos to Camera Roll (decrypted) to share them normally.

### Q: How secure is the encryption?

**A:** Locafoto uses AES-256-GCM, the same encryption used by the military and financial institutions. The master key is stored in the iOS Keychain and never leaves your device.

### Q: Where are my photos stored?

**A:** In the app's private container, encrypted on disk. They're backed up to iCloud if you have device backup enabled, but the encryption keys are NOT backed up.

### Q: Can I use this for sensitive photos?

**A:** Yes! That's exactly what it's designed for. Photos are encrypted immediately upon capture and never stored unencrypted.

## License

[To be determined]

## Acknowledgments

- Built with SwiftUI and CryptoKit
- Inspired by privacy-focused applications
- Designed for security and user control

---

**Built with privacy in mind** 🔒

*Your photos, your device, your control.*
