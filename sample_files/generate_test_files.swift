#!/usr/bin/env swift

import Foundation
import CryptoKit

// MARK: - LFS File Format

struct LFSFile {
    static let headerSize = 128
    static let nonceSize = 12
    static let tagSize = 16

    static func create(keyName: String, encryptedData: Data, nonce: Data, tag: Data) throws -> Data {
        var fileData = Data()

        // Create 128-byte header with key name
        var keyNameData = keyName.data(using: .utf8) ?? Data()

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

// MARK: - Shared Key File Format (JSON)

struct SharedKeyFile: Codable {
    let name: String
    let keyData: Data
}

// MARK: - Main Script

func main() {
    let scriptDir = URL(fileURLWithPath: #file).deletingLastPathComponent()
    let outputDir = scriptDir.appendingPathComponent("airdrop_test")

    // Create output directory
    let fileManager = FileManager.default
    try? fileManager.createDirectory(at: outputDir, withIntermediateDirectories: true)

    // Generate a random 256-bit key
    let keyData = SymmetricKey(size: .bits256)
    let keyName = "TestKey-\(UUID().uuidString.prefix(8))"

    print("🔑 Generating test key: \(keyName)")

    // Export key data
    let rawKeyData = keyData.withUnsafeBytes { Data($0) }

    // Create .lfkey file (JSON format)
    let sharedKey = SharedKeyFile(name: keyName, keyData: rawKeyData)
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = .prettyPrinted

    do {
        let keyFileData = try encoder.encode(sharedKey)
        let keyFileURL = outputDir.appendingPathComponent("\(keyName).lfkey")
        try keyFileData.write(to: keyFileURL)
        print("✅ Created key file: \(keyFileURL.lastPathComponent)")
    } catch {
        print("❌ Failed to create key file: \(error)")
        return
    }

    // Process each PNG file
    let pngFiles = ["logo1.png", "logo2.png"]

    for pngFile in pngFiles {
        let inputURL = scriptDir.appendingPathComponent(pngFile)

        guard fileManager.fileExists(atPath: inputURL.path) else {
            print("⚠️ File not found: \(pngFile)")
            continue
        }

        do {
            // Read the image data
            let imageData = try Data(contentsOf: inputURL)
            print("📷 Processing \(pngFile) (\(imageData.count) bytes)")

            // Encrypt with AES-GCM
            let nonce = AES.GCM.Nonce()
            let sealedBox = try AES.GCM.seal(imageData, using: keyData, nonce: nonce)

            // Create LFS file
            let lfsData = try LFSFile.create(
                keyName: keyName,
                encryptedData: sealedBox.ciphertext,
                nonce: Data(nonce),
                tag: sealedBox.tag
            )

            // Write .lfs file
            let baseName = (pngFile as NSString).deletingPathExtension
            let lfsFileURL = outputDir.appendingPathComponent("\(baseName).lfs")
            try lfsData.write(to: lfsFileURL)
            print("✅ Created LFS file: \(lfsFileURL.lastPathComponent) (\(lfsData.count) bytes)")

        } catch {
            print("❌ Failed to process \(pngFile): \(error)")
        }
    }

    print("\n📁 Output directory: \(outputDir.path)")
    print("\n📱 To test AirDrop:")
    print("1. First AirDrop the .lfkey file to import the key")
    print("2. Then AirDrop the .lfs files to import encrypted photos")
    print("\nFiles are in: \(outputDir.path)")
}

main()
