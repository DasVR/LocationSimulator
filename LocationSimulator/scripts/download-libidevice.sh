#!/bin/bash
set -euo pipefail

# Downloads the official jkcoxson/idevice xcframework for iOS builds.
# Run this before xcodegen generate to ensure the FFI library is present.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST_DIR="${SCRIPT_DIR}/../idevice"
ZIP_PATH="${DEST_DIR}/idevice-xcframework.zip"
XCFRAMEWORK_DIR="${DEST_DIR}/IDevice.xcframework"

VERSION="v0.1.62"
URL="https://github.com/jkcoxson/idevice/releases/download/${VERSION}/idevice-xcframework-${VERSION}.zip"

if [ -d "$XCFRAMEWORK_DIR" ]; then
    echo "IDevice.xcframework already exists. Skipping download."
    exit 0
fi

echo "Downloading idevice xcframework ${VERSION}..."
curl -L -o "$ZIP_PATH" "$URL"

echo "Extracting..."
unzip -q "$ZIP_PATH" -d "$DEST_DIR"
mv "$DEST_DIR/swift/IDevice.xcframework" "$XCFRAMEWORK_DIR"
rm -rf "$DEST_DIR/swift" "$ZIP_PATH"

echo "Done. IDevice.xcframework ready at ${XCFRAMEWORK_DIR}"
