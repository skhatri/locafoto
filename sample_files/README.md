# Sample Files for Testing AirDrop Sharing

This directory contains sample files for testing the Locafoto app's AirDrop sharing functionality.

## Files

### For .lfs (Locafoto Shared) Format Testing
- **sample_key.txt** - A 256-bit AES encryption key in hexadecimal format (64 characters)
- **sample_photo.lfs** - A sample encrypted photo file in LFS (Locafoto Shared) format

### For .locaphoto Format Testing
- **sample_photo.locaphoto** - A sample encrypted photo bundle in JSON format (self-contained with encrypted key)
- **sample_private_key.pem** - RSA private key for testing decryption (testing only, not needed for normal use)
- **sample_symmetric_key.txt** - Symmetric AES key for reference (testing only)

## Usage Instructions

### Testing .lfs Format (with separate key file)

#### Step 1: Import the Key into the App

1. Open the Locafoto app on your iOS device
2. Navigate to the **Keys** tab
3. Tap the **+** button in the top right
4. Select **"Import Key File"**
5. Enter the following:
   - **Key Name**: `SampleKey`
   - **Key Data (Hex)**: Copy and paste the entire contents of `sample_key.txt`
6. Tap **"Import"**

#### Step 2: Share the LFS File via AirDrop

1. On your Mac, locate the file `sample_files/sample_photo.lfs`
2. Right-click (or Control-click) the file and select **Share** → **AirDrop**
3. Select your iOS device from the AirDrop menu
4. Accept the AirDrop on your iOS device
5. The Locafoto app should automatically detect the `.lfs` file and import it

#### Expected Behavior

- The app should recognize the `.lfs` file format
- If the key `SampleKey` is already imported, the file should decrypt successfully
- The photo should appear in your Gallery
- The photo should also appear in the LFS Library tab

### Testing .locaphoto Format (self-contained)

#### Step 1: Share the .locaphoto File via AirDrop

1. On your Mac, locate the file `sample_files/sample_photo.locaphoto`
2. Right-click (or Control-click) the file and select **Share** → **AirDrop**
3. Select your iOS device from the AirDrop menu
4. Accept the AirDrop on your iOS device
5. The Locafoto app should automatically import it

#### Expected Behavior

- The app should recognize the `.locaphoto` file format
- No pre-import of keys is needed - the encrypted key is bundled in the file
- The photo should appear in your Gallery
- The file is decrypted using the app's master encryption system

## File Format Details

### LFS File Structure

The `.lfs` file follows this binary format:
- **Header** (128 bytes): Key name (UTF-8 string) padded with null bytes
- **Encrypted Data** (variable): AES-256-GCM encrypted image data
- **Nonce/IV** (12 bytes): Random initialization vector
- **Authentication Tag** (16 bytes): GCM authentication tag

### Key File Format (for .lfs)

The key file is a simple text file containing:
- 64 hexadecimal characters (32 bytes = 256 bits)
- No spaces or line breaks
- Represents a raw AES-256 encryption key

### .locaphoto File Structure

The `.locaphoto` file is a JSON document with this structure:
```json
{
  "version": "1.0",
  "photo": {
    "id": "UUID",
    "encryptedData": "base64-encoded encrypted image data",
    "encryptedKey": "base64-encoded RSA-encrypted symmetric key",
    "iv": "base64-encoded initialization vector",
    "authTag": "base64-encoded authentication tag"
  },
  "metadata": {
    "originalSize": number,
    "captureDate": "ISO8601 date",
    "width": number,
    "height": number,
    "format": "string"
  }
}
```

The photo data is encrypted with AES-256-GCM using a random symmetric key, and that symmetric key is encrypted with an RSA public key stored in the app.

## Troubleshooting

### For .lfs Files
- **Key not found error**: Make sure you imported the key with the exact name "SampleKey" (case-sensitive)
- **Decryption failed**: Verify the key hex string was copied correctly (should be exactly 64 characters)
- **File not recognized**: Ensure the file has the `.lfs` extension
- **AirDrop not working**: Check that both devices have AirDrop enabled and are nearby

### For .locaphoto Files
- **File not recognized**: Ensure the file has the `.locaphoto` extension
- **Import failed**: Check that the JSON structure is valid
- **Decryption error**: Ensure the app has the correct RSA private key configured
- **AirDrop not working**: Check that both devices have AirDrop enabled and are nearby

## Regenerating Files

To create new sample files with different keys or images, run:

```bash
# For .lfs format (requires key import)
python3 scripts/create_sample_lfs.py

# For .locaphoto format (self-contained)
python3 scripts/create_sample_locaphoto.py

# Or regenerate all sample files
python3 scripts/create_sample_lfs.py
python3 scripts/create_sample_locaphoto.py
```

These scripts will regenerate the files with new random encryption keys.

**Note:** You'll need the `cryptography` Python package installed:
```bash
python3 -m venv venv
source venv/bin/activate
pip install cryptography
python3 scripts/create_sample_lfs.py
python3 scripts/create_sample_locaphoto.py
```

