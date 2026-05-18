#!/bin/bash
set -e

SCHEME="LocationSimulator"
ARCHIVE_PATH="build/${SCHEME}.xcarchive"
EXPORT_PATH="build/ipa"

# Clean previous builds
rm -rf "$ARCHIVE_PATH" "$EXPORT_PATH"

# Archive
xcodebuild archive \
    -scheme "$SCHEME" \
    -destination 'generic/platform=iOS' \
    -archivePath "$ARCHIVE_PATH" \
    -configuration Release \
    CODE_SIGN_IDENTITY="iPhone Developer" \
    CODE_SIGN_STYLE=Manual

# Export IPA
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_PATH" \
    -exportOptionsPlist "scripts/exportOptions.plist"

echo "IPA built at: ${EXPORT_PATH}/${SCHEME}.ipa"
