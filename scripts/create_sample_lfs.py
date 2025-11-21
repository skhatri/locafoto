#!/usr/bin/env python3
"""
Script to create a sample key file and .lfs file for testing AirDrop sharing.

This creates:
1. sample_key.txt - A hex-encoded 256-bit AES key that can be imported into the app
2. sample_photo.lfs - A sample encrypted photo file that can be shared via AirDrop
"""

import os
import sys
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.backends import default_backend
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.kdf.pbkdf2 import PBKDF2HMAC
import secrets

# Sample key name (must be <= 128 bytes)
KEY_NAME = "SampleKey"

def generate_key():
    """Generate a random 256-bit (32-byte) AES key"""
    return secrets.token_bytes(32)

def create_lfs_file(key_name: str, encryption_key: bytes, image_data: bytes) -> bytes:
    """
    Create an LFS file with the specified format:
    - 128 bytes: Key name (UTF-8, padded with zeros)
    - Variable: Encrypted data
    - 12 bytes: Nonce/IV
    - 16 bytes: Authentication tag
    """
    # Create AES-GCM cipher
    aesgcm = AESGCM(encryption_key)
    
    # Generate random nonce (12 bytes for GCM)
    nonce = secrets.token_bytes(12)
    
    # Encrypt the image data
    # AESGCM.encrypt returns: ciphertext + tag (16 bytes)
    encrypted_result = aesgcm.encrypt(nonce, image_data, None)
    
    # Split ciphertext and tag
    # The last 16 bytes are the authentication tag
    ciphertext = encrypted_result[:-16]
    tag = encrypted_result[-16:]
    
    # Create header with key name (128 bytes, padded with zeros)
    key_name_bytes = key_name.encode('utf-8')
    if len(key_name_bytes) > 128:
        raise ValueError(f"Key name too long: {len(key_name_bytes)} bytes (max 128)")
    
    header = key_name_bytes + b'\x00' * (128 - len(key_name_bytes))
    
    # Assemble LFS file
    lfs_data = header + ciphertext + nonce + tag
    
    return lfs_data

def create_sample_image() -> bytes:
    """Create a simple test image (1x1 pixel PNG)"""
    # Minimal valid PNG file (1x1 red pixel)
    # PNG signature + IHDR + IDAT + IEND chunks
    png_data = bytes.fromhex(
        '89504e470d0a1a0a'  # PNG signature
        '0000000d49484452000000010000000108020000009077536e'  # IHDR chunk
        '0000000a49444154789c63000100000005ffff00ff00000000'  # IDAT chunk
        '0a49444154789c63000100000005ffff00ff00000000'  # (continued)
        '0000000049454e44ae426082'  # IEND chunk
    )
    return png_data

def main():
    # Generate encryption key
    key = generate_key()
    key_hex = key.hex()
    
    # Create output directory
    output_dir = "sample_files"
    os.makedirs(output_dir, exist_ok=True)
    
    # Create sample image
    print("Creating sample image...")
    image_data = create_sample_image()
    
    # Create LFS file
    print(f"Creating LFS file with key name: '{KEY_NAME}'...")
    lfs_data = create_lfs_file(KEY_NAME, key, image_data)
    
    # Write key file (hex format for import)
    key_file_path = os.path.join(output_dir, "sample_key.txt")
    with open(key_file_path, 'w') as f:
        f.write(key_hex)
    print(f"✓ Created key file: {key_file_path}")
    print(f"  Key (hex): {key_hex}")
    print(f"  Key length: {len(key)} bytes (256 bits)")
    
    # Write LFS file
    lfs_file_path = os.path.join(output_dir, "sample_photo.lfs")
    with open(lfs_file_path, 'wb') as f:
        f.write(lfs_data)
    print(f"✓ Created LFS file: {lfs_file_path}")
    print(f"  File size: {len(lfs_data)} bytes")
    print(f"  - Header: 128 bytes")
    print(f"  - Encrypted data: {len(lfs_data) - 128 - 12 - 16} bytes")
    print(f"  - Nonce: 12 bytes")
    print(f"  - Tag: 16 bytes")
    
    print("\n" + "="*60)
    print("Sample files created successfully!")
    print("="*60)
    print("\nTo use these files:")
    print(f"1. Import the key '{KEY_NAME}' into the app:")
    print(f"   - Open the app and go to the Keys tab")
    print(f"   - Tap '+' and select 'Import Key File'")
    print(f"   - Key name: {KEY_NAME}")
    print(f"   - Paste the hex key from: {key_file_path}")
    print(f"   - The hex key is: {key_hex}")
    print(f"\n2. Share the LFS file via AirDrop:")
    print(f"   - Share '{lfs_file_path}' via AirDrop to your device")
    print(f"   - The app should automatically import it if the key is present")
    print("\n" + "="*60)

if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)

