#!/bin/bash

# Locafoto CLI Tool
# Usage:
#   ./loco.sh create-key <key-name> [output-file]
#   ./loco.sh encrypt <key-file> <input-file-or-directory> [output-file]
#   ./loco.sh decrypt <key-file> <lfs-file> [output-file]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="${SCRIPT_DIR}/.venv"
PYTHON_SCRIPT="${SCRIPT_DIR}/scripts/loco_helper.py"

# Setup virtual environment if it doesn't exist
setup_venv() {
    if [ ! -d "$VENV_DIR" ]; then
        echo "Creating virtual environment..."
        python3 -m venv "$VENV_DIR"
    fi
    
    # Activate virtual environment
    source "${VENV_DIR}/bin/activate"
    
    # Install/upgrade cryptography if needed
    if ! python3 -c "import cryptography" 2>/dev/null; then
        echo "Installing cryptography library..."
        pip install --quiet --upgrade cryptography
    fi
}

# Setup venv before doing anything
setup_venv

# Use venv's python3
PYTHON="${VENV_DIR}/bin/python3"

# Setup venv before doing anything
setup_venv

# Check if Python script exists, if not create it
if [ ! -f "$PYTHON_SCRIPT" ]; then
    echo "Creating helper Python script..."
    mkdir -p "$(dirname "$PYTHON_SCRIPT")"
    cat > "$PYTHON_SCRIPT" << 'PYTHON_EOF'
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

def decrypt_lfs_file(key_file, lfs_file, output_file):
    """Decrypt an .lfs file and save the decrypted content"""
    # Load key from file
    key_name, key_data = load_key_from_file(key_file)
    
    # Read LFS file
    with open(lfs_file, 'rb') as f:
        lfs_data = f.read()
    
    # Parse LFS file structure
    HEADER_SIZE = 128
    NONCE_SIZE = 12
    TAG_SIZE = 16
    
    if len(lfs_data) < HEADER_SIZE + NONCE_SIZE + TAG_SIZE:
        raise ValueError(f"LFS file too small: {len(lfs_data)} bytes")
    
    # Extract components
    header = lfs_data[:HEADER_SIZE]
    nonce_start = len(lfs_data) - NONCE_SIZE - TAG_SIZE
    tag_start = len(lfs_data) - TAG_SIZE
    
    encrypted_data = lfs_data[HEADER_SIZE:nonce_start]
    nonce = lfs_data[nonce_start:tag_start]
    tag = lfs_data[tag_start:]
    
    # Extract key name from header
    key_name_bytes = header.rstrip(b'\x00')
    parsed_key_name = key_name_bytes.decode('utf-8').strip()
    
    # Verify key name matches
    if parsed_key_name != key_name:
        print(f"⚠️  Warning: Key name mismatch!")
        print(f"   LFS file expects: '{parsed_key_name}'")
        print(f"   Key file has: '{key_name}'")
        print(f"   Continuing anyway...")
    
    # Decrypt using AES-GCM
    aesgcm = AESGCM(key_data)
    
    # Combine ciphertext and tag for decryption
    ciphertext_with_tag = encrypted_data + tag
    
    try:
        decrypted_data = aesgcm.decrypt(nonce, ciphertext_with_tag, None)
    except Exception as e:
        raise ValueError(f"Decryption failed: {e}. Key may be incorrect or file corrupted.")
    
    # Write decrypted file
    with open(output_file, 'wb') as f:
        f.write(decrypted_data)
    
    print(f"✓ Decrypted LFS file: {output_file}")
    print(f"  Input: {lfs_file}")
    print(f"  Key name: {parsed_key_name}")
    print(f"  Decrypted size: {len(decrypted_data)} bytes")
    
    # Try to detect file type
    if decrypted_data.startswith(b'\x89PNG'):
        print(f"  Detected format: PNG")
    elif decrypted_data.startswith(b'\xff\xd8\xff'):
        print(f"  Detected format: JPEG")
    elif decrypted_data.startswith(b'RIFF') and b'WEBP' in decrypted_data[:20]:
        print(f"  Detected format: WEBP")
    elif decrypted_data.startswith(b'ftyp'):
        print(f"  Detected format: HEIC/HEIF")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage:")
        print("  python3 loco_helper.py create-key <key-name> <output-file>")
        print("  python3 loco_helper.py encrypt <key-file> <input-path> <output-file>")
        print("  python3 loco_helper.py decrypt <key-file> <lfs-file> <output-file>")
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
    
    elif command == "decrypt":
        if len(sys.argv) < 4:
            print("Error: Key file and LFS file required")
            print("Usage: python3 loco_helper.py decrypt <key-file> <lfs-file> [output-file]")
            sys.exit(1)
        
        key_file = sys.argv[2]
        lfs_file = sys.argv[3]
        output_file = sys.argv[4] if len(sys.argv) > 4 else None
        
        if not os.path.exists(key_file):
            print(f"❌ Key file not found: {key_file}")
            sys.exit(1)
        
        if not os.path.exists(lfs_file):
            print(f"❌ LFS file not found: {lfs_file}")
            sys.exit(1)
        
        # Determine output file
        if output_file is None:
            output_file = os.path.splitext(lfs_file)[0] + "_decrypted"
            # Try to preserve original extension by checking file type
            # But for now, just use _decrypted suffix
        
        decrypt_lfs_file(key_file, lfs_file, output_file)
    
    else:
        print(f"❌ Unknown command: {command}")
        sys.exit(1)
PYTHON_EOF
    chmod +x "$PYTHON_SCRIPT"
fi

# Check if Python 3 is available
if ! command -v python3 &> /dev/null; then
    echo "❌ Error: python3 is required but not found"
    echo "Please install Python 3"
    exit 1
fi

# Parse command
COMMAND="${1:-}"

case "$COMMAND" in
    create-key)
        if [ -z "${2:-}" ]; then
            echo "Usage: $0 create-key <key-name> [output-file]"
            echo ""
            echo "Examples:"
            echo "  $0 create-key MyKey"
            echo "  $0 create-key MyKey mykey.lfkey"
            exit 1
        fi
        
        KEY_NAME="$2"
        OUTPUT_FILE="${3:-${KEY_NAME}.lfkey}"
        
        # Ensure .lfkey extension
        if [[ ! "$OUTPUT_FILE" =~ \.lfkey$ ]]; then
            OUTPUT_FILE="${OUTPUT_FILE}.lfkey"
        fi
        
        "$PYTHON" "$PYTHON_SCRIPT" create-key "$KEY_NAME" "$OUTPUT_FILE"
        ;;
    
    encrypt)
        if [ -z "${2:-}" ] || [ -z "${3:-}" ]; then
            echo "Usage: $0 encrypt <key-file> <input-file-or-directory> [output-file-or-directory]"
            echo ""
            echo "Examples:"
            echo "  $0 encrypt MyKey.lfkey photo.jpg"
            echo "  $0 encrypt MyKey.lfkey photo.jpg encrypted.lfs"
            echo "  $0 encrypt MyKey.lfkey ./photos/"
            echo "  $0 encrypt MyKey.lfkey ./photos/ ./encrypted/"
            exit 1
        fi
        
        KEY_FILE="$2"
        INPUT_PATH="$3"
        OUTPUT_PATH="${4:-}"
        
        if [ ! -f "$KEY_FILE" ]; then
            echo "❌ Error: Key file not found: $KEY_FILE"
            echo ""
            echo "Create a key file first with:"
            echo "  $0 create-key <key-name>"
            exit 1
        fi
        
        if [ ! -e "$INPUT_PATH" ]; then
            echo "❌ Error: Input path not found: $INPUT_PATH"
            exit 1
        fi
        
        "$PYTHON" "$PYTHON_SCRIPT" encrypt "$KEY_FILE" "$INPUT_PATH" "$OUTPUT_PATH"
        ;;
    
    decrypt)
        if [ -z "${2:-}" ] || [ -z "${3:-}" ]; then
            echo "Usage: $0 decrypt <key-file> <lfs-file> [output-file]"
            echo ""
            echo "Examples:"
            echo "  $0 decrypt MyKey.lfkey photo.lfs"
            echo "  $0 decrypt MyKey.lfkey photo.lfs decrypted.jpg"
            exit 1
        fi
        
        KEY_FILE="$2"
        LFS_FILE="$3"
        OUTPUT_FILE="${4:-}"
        
        if [ ! -f "$KEY_FILE" ]; then
            echo "❌ Error: Key file not found: $KEY_FILE"
            exit 1
        fi
        
        if [ ! -f "$LFS_FILE" ]; then
            echo "❌ Error: LFS file not found: $LFS_FILE"
            exit 1
        fi
        
        "$PYTHON" "$PYTHON_SCRIPT" decrypt "$KEY_FILE" "$LFS_FILE" "$OUTPUT_FILE"
        ;;
    
    *)
        echo "Locafoto CLI Tool"
        echo ""
        echo "Usage:"
        echo "  $0 create-key <key-name> [output-file]"
        echo "  $0 encrypt <key-file> <input-file-or-directory> [output-file-or-directory]"
        echo "  $0 decrypt <key-file> <lfs-file> [output-file]"
        echo ""
        echo "Commands:"
        echo "  create-key    Create a new encryption key file (.lfkey)"
        echo "  encrypt       Encrypt file(s) using a key file to create .lfs file(s)"
        echo "  decrypt       Decrypt an .lfs file to validate and extract content"
        echo ""
        echo "Examples:"
        echo "  $0 create-key MyKey"
        echo "  $0 encrypt MyKey.lfkey photo.jpg"
        echo "  $0 encrypt MyKey.lfkey ./photos/ ./encrypted/"
        echo "  $0 decrypt MyKey.lfkey photo.lfs"
        echo "  $0 decrypt MyKey.lfkey photo.lfs decrypted.jpg"
        exit 1
        ;;
esac

