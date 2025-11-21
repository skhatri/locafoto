#!/usr/bin/env python3
"""
Script to create a sample .locaphoto file for testing AirDrop sharing.

This creates:
1. sample_key.locaphoto - A sample encrypted photo bundle in JSON format
   that can be shared via AirDrop (includes its own encrypted key)
"""

import os
import sys
import json
import base64
import secrets
from datetime import datetime
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.backends import default_backend
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import padding

def generate_symmetric_key():
    """Generate a random 256-bit (32-byte) AES key for photo encryption"""
    return secrets.token_bytes(32)

def generate_rsa_keypair():
    """Generate RSA key pair for encrypting the symmetric key"""
    private_key = rsa.generate_private_key(
        public_exponent=65537,
        key_size=2048,
        backend=default_backend()
    )
    public_key = private_key.public_key()
    return private_key, public_key

def create_sample_image() -> bytes:
    """Create a simple test image (1x1 pixel PNG)"""
    # Minimal valid PNG file (1x1 red pixel)
    png_data = bytes.fromhex(
        '89504e470d0a1a0a'  # PNG signature
        '0000000d49484452000000010000000108020000009077536e'  # IHDR chunk
        '0000000c494441547801636000020000050001a772fd0e'  # IDAT chunk
        '0000000049454e44ae426082'  # IEND chunk
    )
    return png_data

def encrypt_photo(image_data: bytes, symmetric_key: bytes):
    """
    Encrypt photo data using AES-GCM
    Returns: (encrypted_data, iv, auth_tag)
    """
    # Create AES-GCM cipher
    aesgcm = AESGCM(symmetric_key)

    # Generate random nonce/IV (12 bytes for GCM)
    iv = secrets.token_bytes(12)

    # Encrypt the image data
    # AESGCM.encrypt returns: ciphertext + tag (16 bytes)
    encrypted_result = aesgcm.encrypt(iv, image_data, None)

    # Split ciphertext and tag
    ciphertext = encrypted_result[:-16]
    auth_tag = encrypted_result[-16:]

    return ciphertext, iv, auth_tag

def encrypt_symmetric_key(symmetric_key: bytes, public_key):
    """Encrypt the symmetric key with RSA public key"""
    encrypted_key = public_key.encrypt(
        symmetric_key,
        padding.OAEP(
            mgf=padding.MGF1(algorithm=hashes.SHA256()),
            algorithm=hashes.SHA256(),
            label=None
        )
    )
    return encrypted_key

def create_locaphoto_bundle(image_data: bytes, symmetric_key: bytes, public_key):
    """
    Create a .locaphoto bundle in the app's JSON format
    """
    # Encrypt the photo
    encrypted_data, iv, auth_tag = encrypt_photo(image_data, symmetric_key)

    # Encrypt the symmetric key
    encrypted_key = encrypt_symmetric_key(symmetric_key, public_key)

    # Generate a UUID for the photo
    import uuid
    photo_id = str(uuid.uuid4())

    # Create the bundle structure matching SharingService's ShareBundle
    bundle = {
        "version": "1.0",
        "photo": {
            "id": photo_id,
            "encryptedData": base64.b64encode(encrypted_data).decode('utf-8'),
            "encryptedKey": base64.b64encode(encrypted_key).decode('utf-8'),
            "iv": base64.b64encode(iv).decode('utf-8'),
            "authTag": base64.b64encode(auth_tag).decode('utf-8')
        },
        "metadata": {
            "originalSize": len(image_data),
            "captureDate": datetime.utcnow().isoformat() + "Z",
            "width": 1,
            "height": 1,
            "format": "PNG"
        }
    }

    return bundle, photo_id

def main():
    # Generate keys
    print("Generating encryption keys...")
    symmetric_key = generate_symmetric_key()
    private_key, public_key = generate_rsa_keypair()

    # Create output directory
    output_dir = "sample_files"
    os.makedirs(output_dir, exist_ok=True)

    # Create sample image
    print("Creating sample image...")
    image_data = create_sample_image()

    # Create .locaphoto bundle
    print("Creating .locaphoto bundle...")
    bundle, photo_id = create_locaphoto_bundle(image_data, symmetric_key, public_key)

    # Write .locaphoto file (pretty-printed JSON)
    locaphoto_file_path = os.path.join(output_dir, "sample_photo.locaphoto")
    with open(locaphoto_file_path, 'w') as f:
        json.dump(bundle, f, indent=2)

    print(f"\n✓ Created .locaphoto file: {locaphoto_file_path}")
    print(f"  Photo ID: {photo_id}")
    print(f"  File size: {os.path.getsize(locaphoto_file_path)} bytes")
    print(f"  Original image size: {len(image_data)} bytes")
    print(f"  Encrypted data size: {len(base64.b64decode(bundle['photo']['encryptedData']))} bytes")

    # Save the private key for potential decryption testing
    private_key_path = os.path.join(output_dir, "sample_private_key.pem")
    pem = private_key.private_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.NoEncryption()
    )
    with open(private_key_path, 'wb') as f:
        f.write(pem)
    print(f"  Private key saved to: {private_key_path} (for testing only)")

    # Save the symmetric key for reference
    symmetric_key_path = os.path.join(output_dir, "sample_symmetric_key.txt")
    with open(symmetric_key_path, 'w') as f:
        f.write(symmetric_key.hex())
    print(f"  Symmetric key saved to: {symmetric_key_path} (for reference)")

    print("\n" + "="*60)
    print("Sample .locaphoto file created successfully!")
    print("="*60)
    print("\nTo use this file:")
    print(f"1. Share '{locaphoto_file_path}' via AirDrop to your device")
    print(f"2. The Locafoto app should automatically import it")
    print(f"3. No pre-import of keys is needed - the key is bundled in the file")
    print("\n" + "="*60)

if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        import traceback
        traceback.print_exc()
        sys.exit(1)
