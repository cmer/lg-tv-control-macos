#!/bin/bash

set -e  # Exit on any error

# Store original directory right at the start
ORIGINAL_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Determine current architecture
ARCH=$(uname -m)
if [[ "$ARCH" == "arm64" ]]; then
    TARGET_ARCH="arm64"
    echo "Building for Apple Silicon (arm64)"
elif [[ "$ARCH" == "x86_64" ]]; then
    TARGET_ARCH="x86_64"
    echo "Building for Intel (x86_64)"
else
    echo "Unsupported architecture: $ARCH"
    exit 1
fi

# Create working directory
WORK_DIR=$(mktemp -d)
echo "Working directory: $WORK_DIR"

# Create and activate venv
python3 -m venv "$WORK_DIR/venv"
source "$WORK_DIR/venv/bin/activate"

# Install requirements
pip install pyinstaller bscpylgtv

# Build
cd "$WORK_DIR"
pyinstaller --target-arch $TARGET_ARCH --onefile $(which bscpylgtvcommand)

# Copy the binary to the final location
mkdir -p "$ORIGINAL_DIR/dist"
cp "$WORK_DIR/dist/bscpylgtvcommand" "$ORIGINAL_DIR/dist/bscpylgtvcommand-$TARGET_ARCH"

# Make the binary executable
chmod +x "$ORIGINAL_DIR/dist/bscpylgtvcommand-$TARGET_ARCH"

# Clean up
deactivate
rm -rf "$WORK_DIR"

echo "Done! Binary is at $ORIGINAL_DIR/dist/bscpylgtvcommand-$TARGET_ARCH"
