#!/usr/bin/env python3
"""
Helper script for loco.sh to create .lfkey and .lfs files
"""

import os
import sys
import json
import base64
import secrets
from pathlib import Path
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

def create_key_file(key_name, output_file):
    """Create a .lfkey file (JSON format)"""
    # Generate a random 256-bit (32-byte) AES key
    key_data = secrets.token_bytes(32)
    
    # Create SharedKeyFile structure
    shared_key = {
        "name": key_name,
        "keyData": base64.b64encode(key_data).decode('utf-8')
    }
    
    # Write JSON file
    with open(output_file, 'w') as f:
        json.dump(shared_key, f, indent=2)
    
    print(f"✓ Created key file: {output_file}")
    print(f"  Key name: {key_name}")
    print(f"  Key (hex): {key_data.hex()}")
    print(f"  Key length: {len(key_data)} bytes (256 bits)")
    
    return key_data

def encrypt_file(key_name, key_data, input_path, output_file):
    """Create an .lfs file from an input file"""
    # Read input file
    if os.path.isdir(input_path):
        # If directory, process all image files
        image_extensions = {'.jpg', '.jpeg', '.png', '.heic', '.heif', '.webp'}
        files = [f for f in Path(input_path).iterdir() 
                 if f.suffix.lower() in image_extensions]
        
        if not files:
            print(f"❌ No image files found in directory: {input_path}")
            sys.exit(1)
        
        print(f"Found {len(files)} image file(s) to encrypt")
        
        # Create output directory if it doesn't exist
        output_dir = Path(output_file).parent if os.path.dirname(output_file) else Path('.')
        output_dir.mkdir(parents=True, exist_ok=True)
        
        for img_file in files:
            output_path = output_dir / f"{img_file.stem}.lfs"
            encrypt_single_file(key_name, key_data, str(img_file), str(output_path))
    else:
        encrypt_single_file(key_name, key_data, input_path, output_file)

def encrypt_single_file(key_name, key_data, input_file, output_file):
    """Encrypt a single file and create .lfs file"""
    # Read input file
    with open(input_file, 'rb') as f:
        file_data = f.read()
    
    # Create AES-GCM cipher
    aesgcm = AESGCM(key_data)
    
    # Generate random nonce (12 bytes for GCM)
    nonce = secrets.token_bytes(12)
    
    # Encrypt the file data
    # AESGCM.encrypt returns: ciphertext + tag (16 bytes)
    encrypted_result = aesgcm.encrypt(nonce, file_data, None)
    
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
    
    # Write LFS file
    with open(output_file, 'wb') as f:
        f.write(lfs_data)
    
    print(f"✓ Created LFS file: {output_file}")
    print(f"  Input: {input_file}")
    print(f"  Key name: {key_name}")
    print(f"  File size: {len(lfs_data)} bytes")
    print(f"    - Header: 128 bytes")
    print(f"    - Encrypted data: {len(ciphertext)} bytes")
    print(f"    - Nonce: 12 bytes")
    print(f"    - Tag: 16 bytes")

def load_key_from_file(key_file):
    """Load key data from a .lfkey file"""
    with open(key_file, 'r') as f:
        shared_key = json.load(f)
    
    key_data = base64.b64decode(shared_key['keyData'])
    key_name = shared_key['name']
    
    return key_name, key_data

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage:")
        print("  python3 loco_helper.py create-key <key-name> <output-file>")
        print("  python3 loco_helper.py encrypt <key-file> <input-path> <output-file>")
        sys.exit(1)
    
    command = sys.argv[1]
    
    if command == "create-key":
        if len(sys.argv) < 3:
            print("Error: Key name required")
            print("Usage: python3 loco_helper.py create-key <key-name> [output-file]")
            sys.exit(1)
        
        key_name = sys.argv[2]
        output_file = sys.argv[3] if len(sys.argv) > 3 else f"{key_name}.lfkey"
        
        if not output_file.endswith('.lfkey'):
            output_file += '.lfkey'
        
        create_key_file(key_name, output_file)
    
    elif command == "encrypt":
        if len(sys.argv) < 4:
            print("Error: Key file and input path required")
            print("Usage: python3 loco_helper.py encrypt <key-file> <input-path> [output-file]")
            sys.exit(1)
        
        key_file = sys.argv[2]
        input_path = sys.argv[3]
        output_file = sys.argv[4] if len(sys.argv) > 4 else None
        
        if not os.path.exists(key_file):
            print(f"❌ Key file not found: {key_file}")
            sys.exit(1)
        
        if not os.path.exists(input_path):
            print(f"❌ Input path not found: {input_path}")
            sys.exit(1)
        
        # Load key from file
        key_name, key_data = load_key_from_file(key_file)
        
        # Determine output file
        if output_file is None:
            if os.path.isdir(input_path):
                output_file = f"{os.path.basename(input_path)}_encrypted"
            else:
                output_file = os.path.splitext(input_path)[0] + ".lfs"
        
        encrypt_file(key_name, key_data, input_path, output_file)
    
    else:
        print(f"❌ Unknown command: {command}")
        sys.exit(1)
