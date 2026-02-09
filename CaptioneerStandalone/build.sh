#!/bin/bash
set -euo pipefail

SCHEME="Captioneer"
PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$PROJECT_DIR/build/release"
ARCHIVE_ARM="$BUILD_DIR/Captioneer-arm64.xcarchive"
ARCHIVE_X86="$BUILD_DIR/Captioneer-x86_64.xcarchive"
APP_NAME="Captioneer.app"
OUTPUT_DIR="$BUILD_DIR/universal"
OUTPUT_APP="$OUTPUT_DIR/$APP_NAME"
DMG_NAME="Captioneer.dmg"
DMG_PATH="$BUILD_DIR/$DMG_NAME"

echo "Cleaning previous build..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR" "$OUTPUT_DIR"

echo "Building for arm64..."
xcodebuild archive \
  -project "$PROJECT_DIR/Captioneer.xcodeproj" \
  -scheme "$SCHEME" \
  -configuration Release \
  -archivePath "$ARCHIVE_ARM" \
  -destination "generic/platform=macOS" \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=NO \
  SKIP_INSTALL=NO \
  BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
  -quiet

echo "Building for x86_64..."
xcodebuild archive \
  -project "$PROJECT_DIR/Captioneer.xcodeproj" \
  -scheme "$SCHEME" \
  -configuration Release \
  -archivePath "$ARCHIVE_X86" \
  -destination "generic/platform=macOS" \
  ARCHS=x86_64 \
  ONLY_ACTIVE_ARCH=NO \
  SKIP_INSTALL=NO \
  BUILD_LIBRARY_FOR_DISTRIBUTION=YES \
  -quiet

ARM_APP="$ARCHIVE_ARM/Products/Applications/$APP_NAME"
X86_APP="$ARCHIVE_X86/Products/Applications/$APP_NAME"

echo "Creating universal app..."
cp -R "$ARM_APP" "$OUTPUT_APP"

find "$ARM_APP" -type f | while read -r arm_file; do
  rel="${arm_file#$ARM_APP}"
  x86_file="$X86_APP$rel"
  out_file="$OUTPUT_APP$rel"

  if [ -f "$x86_file" ] && file "$arm_file" | grep -q "Mach-O"; then
    lipo -create "$arm_file" "$x86_file" -output "$out_file" 2>/dev/null || true
  fi
done

echo "Creating DMG..."
rm -f "$DMG_PATH"
DMG_STAGING="$BUILD_DIR/dmg_staging"
rm -rf "$DMG_STAGING"
mkdir -p "$DMG_STAGING"
cp -R "$OUTPUT_APP" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"

hdiutil create \
  -volname "Captioneer" \
  -srcfolder "$DMG_STAGING" \
  -ov \
  -format UDZO \
  "$DMG_PATH" \
  -quiet

rm -rf "$DMG_STAGING"

echo ""
echo "Done."
echo "App: $OUTPUT_APP"
echo "DMG: $DMG_PATH"
echo ""
lipo -info "$OUTPUT_APP/Contents/MacOS/Captioneer"
