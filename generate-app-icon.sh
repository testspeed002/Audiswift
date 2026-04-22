#!/bin/bash
# generate-app-icon.sh
# Usage: ./generate-app-icon.sh /path/to/your/icon-1024x1024.png

INPUT_IMAGE="$1"

if [ -z "$INPUT_IMAGE" ]; then
    echo "Usage: ./generate-app-icon.sh /path/to/your/icon-1024x1024.png"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ICONSET_DIR="$SCRIPT_DIR/Resources/AppIcon.appiconset"
TEMP_DIR="$SCRIPT_DIR/temp_icons"

mkdir -p "$TEMP_DIR"

# Resize image to all required sizes
sips -z 16 16 "$INPUT_IMAGE" --out "$TEMP_DIR/icon_16x16.png"
sips -z 32 32 "$INPUT_IMAGE" --out "$TEMP_DIR/icon_16x16@2x.png"
sips -z 32 32 "$INPUT_IMAGE" --out "$TEMP_DIR/icon_32x32.png"
sips -z 64 64 "$INPUT_IMAGE" --out "$TEMP_DIR/icon_32x32@2x.png"
sips -z 128 128 "$INPUT_IMAGE" --out "$TEMP_DIR/icon_128x128.png"
sips -z 256 256 "$INPUT_IMAGE" --out "$TEMP_DIR/icon_128x128@2x.png"
sips -z 256 256 "$INPUT_IMAGE" --out "$TEMP_DIR/icon_256x256.png"
sips -z 512 512 "$INPUT_IMAGE" --out "$TEMP_DIR/icon_256x256@2x.png"
sips -z 512 512 "$INPUT_IMAGE" --out "$TEMP_DIR/icon_512x512.png"
sips -z 1024 1024 "$INPUT_IMAGE" --out "$TEMP_DIR/icon_512x512@2x.png"

# Copy to icon set
cp "$TEMP_DIR/icon_16x16.png" "$ICONSET_DIR/icon_16x16.png"
cp "$TEMP_DIR/icon_16x16@2x.png" "$ICONSET_DIR/icon_16x16@2x.png"
cp "$TEMP_DIR/icon_32x32.png" "$ICONSET_DIR/icon_32x32.png"
cp "$TEMP_DIR/icon_32x32@2x.png" "$ICONSET_DIR/icon_32x32@2x.png"
cp "$TEMP_DIR/icon_128x128.png" "$ICONSET_DIR/icon_128x128.png"
cp "$TEMP_DIR/icon_128x128@2x.png" "$ICONSET_DIR/icon_128x128@2x.png"
cp "$TEMP_DIR/icon_256x256.png" "$ICONSET_DIR/icon_256x256.png"
cp "$TEMP_DIR/icon_256x256@2x.png" "$ICONSET_DIR/icon_256x256@2x.png"
cp "$TEMP_DIR/icon_512x512.png" "$ICONSET_DIR/icon_512x512.png"
cp "$TEMP_DIR/icon_512x512@2x.png" "$ICONSET_DIR/icon_512x512@2x.png"

# Clean up
rm -rf "$TEMP_DIR"

echo "App icons generated successfully!"
