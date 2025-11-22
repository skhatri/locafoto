#!/usr/bin/env swift

import Foundation
import CryptoKit
import CommonCrypto

// MARK: - LFS File Format

struct LFSFileFormat {
    static let headerSize = 128
    static let nonceSize = 12
    static let tagSize = 16

    static func create(keyName: String, encryptedData: Data, nonce: Data, tag: Data) throws -> Data {
        var fileData = Data()

        // Create 128-byte header with key name
        var keyNameData = keyName.data(using: .utf8) ?? Data()
        if keyNameData.count > headerSize {
            throw NSError(domain: "LFS", code: 1, userInfo: [NSLocalizedDescriptionKey: "Key name too long"])
        }

        // Pad to 128 bytes with zeros
        while keyNameData.count < headerSize {
            keyNameData.append(0)
        }

        fileData.append(keyNameData)
        fileData.append(encryptedData)
        fileData.append(nonce)
        fileData.append(tag)

        return fileData
    }
}

// MARK: - Key File Structure

struct KeyFile: Codable {
    let id: UUID
    let name: String
    let createdDate: Date
    let encryptedKeyData: Data
    var usageCount: Int
    var lastUsed: Date?
}

// MARK: - Shared Key File Structure (for .lfkey files)

struct SharedKeyFile: Codable {
    let name: String
    let keyData: Data
}

// MARK: - ShareBundle Structure (for .locaphoto files)

struct ShareBundle: Codable {
    let version: String

    struct PhotoData: Codable {
        let id: String
        let encryptedData: String
        let encryptedKey: String
        let iv: String
        let authTag: String
    }

    struct Metadata: Codable {
        let originalSize: Int
        let captureDate: String
        let width: Int?
        let height: Int?
        let format: String
    }

    let photo: PhotoData
    let metadata: Metadata
}

// MARK: - Key Derivation (must match app's PBKDF2)

func deriveMasterKey(from pin: String, salt: Data) throws -> SymmetricKey {
    guard let pinData = pin.data(using: .utf8) else {
        throw NSError(domain: "KeyGen", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid PIN"])
    }

    let iterations: UInt32 = 100_000
    var derivedKeyData = Data(count: 32)

    let result = derivedKeyData.withUnsafeMutableBytes { derivedKeyBytes in
        salt.withUnsafeBytes { saltBytes in
            pinData.withUnsafeBytes { pinBytes in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    pinBytes.baseAddress?.assumingMemoryBound(to: Int8.self),
                    pinData.count,
                    saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                    salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                    iterations,
                    derivedKeyBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                    32
                )
            }
        }
    }

    guard result == kCCSuccess else {
        throw NSError(domain: "KeyGen", code: 2, userInfo: [NSLocalizedDescriptionKey: "Key derivation failed"])
    }

    return SymmetricKey(data: derivedKeyData)
}

func encryptKey(_ key: SymmetricKey, with masterKey: SymmetricKey) throws -> Data {
    let keyData = key.withUnsafeBytes { Data($0) }
    let nonce = AES.GCM.Nonce()
    let sealedBox = try AES.GCM.seal(keyData, using: masterKey, nonce: nonce)

    var combined = Data()
    combined.append(contentsOf: nonce)
    combined.append(sealedBox.ciphertext)
    combined.append(sealedBox.tag)

    return combined
}

/// Create a .locaphoto file (JSON bundle format)
func createLocaphotoFile(
    imageData: Data,
    encryptionKey: SymmetricKey,
    masterKey: SymmetricKey
) throws -> (Data, UUID) {
    let photoId = UUID()

    // Encrypt photo data
    let photoNonce = AES.GCM.Nonce()
    let photoSealedBox = try AES.GCM.seal(imageData, using: encryptionKey, nonce: photoNonce)

    // Encrypt the photo key with master key
    let encryptedKeyData = try encryptKey(encryptionKey, with: masterKey)

    // Create the bundle
    let bundle = ShareBundle(
        version: "1.0",
        photo: ShareBundle.PhotoData(
            id: photoId.uuidString,
            encryptedData: photoSealedBox.ciphertext.base64EncodedString(),
            encryptedKey: encryptedKeyData.base64EncodedString(),
            iv: Data(photoNonce).base64EncodedString(),
            authTag: photoSealedBox.tag.base64EncodedString()
        ),
        metadata: ShareBundle.Metadata(
            originalSize: imageData.count,
            captureDate: ISO8601DateFormatter().string(from: Date()),
            width: nil,
            height: nil,
            format: "PNG"
        )
    )

    let encoder = JSONEncoder()
    encoder.outputFormatting = .prettyPrinted
    let jsonData = try encoder.encode(bundle)

    return (jsonData, photoId)
}

// MARK: - Main Generation Logic

func main() {
    let fileManager = FileManager.default

    // Configuration
    let testPin = "1234"  // The PIN users must enter when importing
    let testKeyName = "TestKey"

    // Get project directory (current working directory)
    let projectDir = fileManager.currentDirectoryPath

    // Paths
    let logo1Path = "\(projectDir)/logo1.png"
    let logo2Path = "\(projectDir)/logo2.png"
    let outputDir = "\(projectDir)/sample_files"

    // Create output directory
    do {
        try fileManager.createDirectory(atPath: outputDir, withIntermediateDirectories: true)
    } catch {
        print("Failed to create output directory: \(error)")
        exit(1)
    }

    // Generate a fixed salt for reproducibility
    // In real app, this is random and stored in Keychain
    let salt = Data(repeating: 0x42, count: 32)  // Fixed salt for test data

    // Derive master key from test PIN
    guard let masterKey = try? deriveMasterKey(from: testPin, salt: salt) else {
        print("Failed to derive master key")
        exit(1)
    }

    // Generate the encryption key for LFS files
    let lfsEncryptionKey = SymmetricKey(size: .bits256)

    // Extract raw key bytes for sharing
    let rawKeyData = lfsEncryptionKey.withUnsafeBytes { Data($0) }

    // Create SharedKeyFile structure (for .lfkey import)
    let sharedKeyFile = SharedKeyFile(
        name: testKeyName,
        keyData: rawKeyData
    )

    // Save shared key file as JSON
    let encoder = JSONEncoder()
    encoder.outputFormatting = .prettyPrinted

    guard let sharedKeyFileData = try? encoder.encode(sharedKeyFile) else {
        print("Failed to encode shared key file")
        exit(1)
    }

    let lfkeyPath = "\(outputDir)/\(testKeyName).lfkey"
    do {
        try sharedKeyFileData.write(to: URL(fileURLWithPath: lfkeyPath))
        print("Created lfkey file: \(lfkeyPath)")
    } catch {
        print("Failed to write lfkey file: \(error)")
        exit(1)
    }

    // Process each logo file
    let logos = [
        ("logo1", logo1Path),
        ("logo2", logo2Path)
    ]

    for (name, path) in logos {
        guard fileManager.fileExists(atPath: path) else {
            print("Warning: \(path) not found, skipping")
            continue
        }

        guard let imageData = fileManager.contents(atPath: path) else {
            print("Failed to read \(path)")
            continue
        }

        // Create LFS file
        do {
            let nonce = AES.GCM.Nonce()
            let sealedBox = try AES.GCM.seal(imageData, using: lfsEncryptionKey, nonce: nonce)

            let lfsData = try LFSFileFormat.create(
                keyName: testKeyName,
                encryptedData: sealedBox.ciphertext,
                nonce: Data(nonce),
                tag: sealedBox.tag
            )

            let lfsPath = "\(outputDir)/\(name).lfs"
            try lfsData.write(to: URL(fileURLWithPath: lfsPath))
            print("Created LFS file: \(lfsPath)")
        } catch {
            print("Failed to create LFS for \(name): \(error)")
        }
    }

    // Also save the salt (needed for the app to import the key)
    let saltPath = "\(outputDir)/test_salt.bin"
    do {
        try salt.write(to: URL(fileURLWithPath: saltPath))
        print("Created salt file: \(saltPath)")
    } catch {
        print("Failed to write salt: \(error)")
    }

    // Create README
    let readme = """
    # Locafoto Sample Files

    Generated: \(Date())

    ## Files

    ### Key File
    - `\(testKeyName).lfkey` - Encryption key (AirDrop this first)

    ### LFS Files
    - `logo1.lfs` - Encrypted logo1 image
    - `logo2.lfs` - Encrypted logo2 image

    ## Usage

    ### Key Name: `\(testKeyName)`

    ## Importing (Simple Steps)

    1. Install and open Locafoto on your device
    2. Set up any PIN you want
    3. **AirDrop `\(testKeyName).lfkey`** to import the key
    4. **AirDrop `logo1.lfs` and `logo2.lfs`** to import the photos
    5. The images will appear in the gallery

    The app will automatically match the LFS files with the imported key by name.

    ## Notes

    - The `.lfkey` file contains the raw encryption key
    - When imported, it gets encrypted with your device's master key
    - You can reuse this key to encrypt more files later

    ## Regenerating

    Run from project root:
    ```
    swift tools/generate_test_data.swift
    ```

    """

    let readmePath = "\(outputDir)/README.md"
    do {
        try readme.write(toFile: readmePath, atomically: true, encoding: .utf8)
        print("Created README: \(readmePath)")
    } catch {
        print("Failed to write README: \(error)")
    }

    print("\nDone! Test data created in: \(outputDir)")
    print("\nTo use: Create a key named '\(testKeyName)' in the app, then AirDrop the .lfs files")
}

main()
