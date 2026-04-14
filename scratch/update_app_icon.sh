#!/bin/bash
# Script to convert assets/icon.png into assets/AppIcon.icns

PNG="assets/icon.png"
ICONSET="assets/AppIcon.iconset"

mkdir -p "$ICONSET"

# Resize to standard macOS icon sizes
sips -z 16 16     "$PNG" --out "$ICONSET/icon_16x16.png"
sips -z 32 32     "$PNG" --out "$ICONSET/icon_16x16@2x.png"
sips -z 32 32     "$PNG" --out "$ICONSET/icon_32x32.png"
sips -z 64 64     "$PNG" --out "$ICONSET/icon_32x32@2x.png"
sips -z 128 128   "$PNG" --out "$ICONSET/icon_128x128.png"
sips -z 256 256   "$PNG" --out "$ICONSET/icon_128x128@2x.png"
sips -z 256 256   "$PNG" --out "$ICONSET/icon_256x256.png"
sips -z 512 512   "$PNG" --out "$ICONSET/icon_256x256@2x.png"
sips -z 512 512   "$PNG" --out "$ICONSET/icon_512x512.png"
sips -z 1024 1024 "$PNG" --out "$ICONSET/icon_512x512@2x.png"

# Convert iconset to icns
iconutil -c icns "$ICONSET" -o assets/AppIcon.icns

# Clean up
rm -rf "$ICONSET"

echo "Regenerated assets/AppIcon.icns from assets/icon.png"
