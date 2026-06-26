#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build"
APPLE_BUILD_DIR="$BUILD_DIR/apple"
DIST_DIR="$BUILD_DIR/dist"
STAGING_DIR="$BUILD_DIR/dmg"
TRACKED_DIST_DIR="$ROOT_DIR/dist"
APP_NAME="HandyTab"
APP_BUNDLE_PATH="$APPLE_BUILD_DIR/${APP_NAME}.app"
EXECUTABLE_PATH="$APP_BUNDLE_PATH/Contents/MacOS/${APP_NAME}"
RESOURCES_DIR="$APP_BUNDLE_PATH/Contents/Resources"
CODE_SIGN_IDENTITY="${HANDYTAB_CODE_SIGN_IDENTITY:-${CODE_SIGN_IDENTITY:--}}"

VERSION=""
VOLUME_NAME=""
SKIP_STYLE=0
INCLUDE_PYTHON_PACKAGES=1

usage() {
    cat <<'EOF'
Usage: scripts/dmg.sh [--version <version>] [--volume-name <name>] [--skip-style] [--skip-python-packages]

Options:
  --version <version>      Include the version in the DMG filename and app Info.plist.
  --volume-name <name>     Volume name shown when the DMG is mounted.
  --skip-style             Skip Finder window styling.
  --skip-python-packages   Do not copy ./venv site-packages into the app bundle.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)
            VERSION="${2:-}"
            shift 2
            ;;
        --volume-name)
            VOLUME_NAME="${2:-}"
            shift 2
            ;;
        --skip-style)
            SKIP_STYLE=1
            shift
            ;;
        --skip-python-packages|--skip-venv)
            INCLUDE_PYTHON_PACKAGES=0
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            echo "Unknown argument: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

require_command() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "error: $1 is required to build the DMG" >&2
        exit 1
    fi
}

require_file() {
    if [[ ! -e "$1" ]]; then
        echo "error: missing required file: $1" >&2
        exit 1
    fi
}

require_command hdiutil
require_command swift
require_command codesign
if [[ "$SKIP_STYLE" -eq 0 ]]; then
    require_command osascript
fi

require_file "$ROOT_DIR/assets/AppIcon.icns"
require_file "$ROOT_DIR/assets/icon.png"
require_file "$ROOT_DIR/gesture_recognizer.task"
require_file "$ROOT_DIR/handytab"

PYTHON_SITE_PACKAGES=""
if [[ -d "$ROOT_DIR/venv/lib" ]]; then
    PYTHON_SITE_PACKAGES="$(find "$ROOT_DIR/venv/lib" -path "*/site-packages" -type d -print -quit 2>/dev/null || true)"
fi

if [[ "$INCLUDE_PYTHON_PACKAGES" -eq 1 && -z "$PYTHON_SITE_PACKAGES" ]]; then
    echo "warning: ./venv site-packages not found; packaged Hand Wave Webcam mode may not work" >&2
    INCLUDE_PYTHON_PACKAGES=0
fi

APP_VERSION="${VERSION:-0.0.0}"
dmg_name="$APP_NAME"
if [[ -n "$VERSION" ]]; then
    dmg_name="${dmg_name}-${VERSION}"
fi
if [[ -z "$VOLUME_NAME" ]]; then
    VOLUME_NAME="$dmg_name"
fi

swift build -c release --package-path "$ROOT_DIR" >/dev/null
SWIFT_BIN_DIR="$(swift build -c release --package-path "$ROOT_DIR" --show-bin-path)"
SWIFT_BINARY="$SWIFT_BIN_DIR/$APP_NAME"
require_file "$SWIFT_BINARY"

rm -rf "$APP_BUNDLE_PATH"
mkdir -p "$APP_BUNDLE_PATH/Contents/MacOS" "$RESOURCES_DIR" "$TRACKED_DIST_DIR" "$DIST_DIR"

cp "$SWIFT_BINARY" "$EXECUTABLE_PATH"
chmod +x "$EXECUTABLE_PATH"
strip -S "$EXECUTABLE_PATH" >/dev/null 2>&1 || true

cp "$ROOT_DIR/assets/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
cp "$ROOT_DIR/assets/icon.png" "$RESOURCES_DIR/icon.png"
cp -R "$ROOT_DIR/assets" "$RESOURCES_DIR/assets"
cp "$ROOT_DIR/gesture_recognizer.task" "$RESOURCES_DIR/gesture_recognizer.task"
cp -R "$ROOT_DIR/handytab" "$RESOURCES_DIR/handytab"
find "$RESOURCES_DIR/handytab" -name "__pycache__" -type d -prune -exec rm -rf {} +
find "$RESOURCES_DIR/handytab" -name "*.pyc" -type f -delete

if [[ "$INCLUDE_PYTHON_PACKAGES" -eq 1 ]]; then
    ditto "$PYTHON_SITE_PACKAGES" "$RESOURCES_DIR/python"
    find "$RESOURCES_DIR/python" -name "__pycache__" -type d -prune -exec rm -rf {} +
    find "$RESOURCES_DIR/python" -name "*.pyc" -type f -delete
fi

cat > "$APP_BUNDLE_PATH/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>dev.hsichen.handytab</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$APP_VERSION</string>
    <key>CFBundleVersion</key>
    <string>$APP_VERSION</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSCameraUsageDescription</key>
    <string>HandyTab needs camera access only when Hand Wave Webcam is enabled.</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

if [[ "$CODE_SIGN_IDENTITY" == "-" ]]; then
    codesign --force --deep --sign "$CODE_SIGN_IDENTITY" "$APP_BUNDLE_PATH" >/dev/null
else
    codesign --force --deep --options runtime --timestamp --sign "$CODE_SIGN_IDENTITY" "$APP_BUNDLE_PATH" >/dev/null
fi

rm -rf "$TRACKED_DIST_DIR/${APP_NAME}.app"
cp -R "$APP_BUNDLE_PATH" "$TRACKED_DIST_DIR/${APP_NAME}.app"

rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
cp -R "$APP_BUNDLE_PATH" "$STAGING_DIR/${APP_NAME}.app"
ln -s /Applications "$STAGING_DIR/Applications"

dmg_path="$DIST_DIR/${dmg_name}.dmg"
tracked_dmg_path="$TRACKED_DIST_DIR/${APP_NAME}.dmg"
temp_dmg_path="$BUILD_DIR/${dmg_name}-temp.dmg"
attach_plist_path="$BUILD_DIR/${dmg_name}-attach.plist"

rm -f "$dmg_path" "$tracked_dmg_path" "$temp_dmg_path" "$attach_plist_path"

if [[ "$SKIP_STYLE" -eq 1 ]]; then
    hdiutil create \
        -volname "$VOLUME_NAME" \
        -srcfolder "$STAGING_DIR" \
        -fs HFS+ \
        -format UDZO \
        -imagekey zlib-level=9 \
        "$dmg_path" >/dev/null
else
    hdiutil create \
        -volname "$VOLUME_NAME" \
        -srcfolder "$STAGING_DIR" \
        -fs HFS+ \
        -format UDRW \
        "$temp_dmg_path" >/dev/null

    hdiutil attach \
        "$temp_dmg_path" \
        -readwrite \
        -noverify \
        -noautoopen \
        -plist > "$attach_plist_path"

    MOUNT_DIR="$(sed -n '/<key>mount-point<\/key>/{n;s/.*<string>\(.*\)<\/string>.*/\1/p;q;}' "$attach_plist_path")"
    if [[ -z "$MOUNT_DIR" ]]; then
        echo "error: unable to determine mounted DMG path" >&2
        exit 1
    fi

    MOUNT_NAME="$(basename "$MOUNT_DIR")"
    touch "$MOUNT_DIR/.DS_Store"

    cleanup_mount() {
        if [[ -d "$MOUNT_DIR" ]]; then
            hdiutil detach "$MOUNT_DIR" -quiet >/dev/null 2>&1 || hdiutil detach "$MOUNT_DIR" -force -quiet >/dev/null 2>&1 || true
        fi
    }
    trap cleanup_mount EXIT

    sleep 1
    osascript <<EOF
tell application "Finder"
    tell disk "${MOUNT_NAME}"
        open
        delay 1
        set containerWindow to container window
        set current view of containerWindow to icon view
        set toolbar visible of containerWindow to false
        set statusbar visible of containerWindow to false
        set pathbar visible of containerWindow to false
        set bounds of containerWindow to {120, 120, 700, 500}

        set viewOptions to the icon view options of containerWindow
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 128
        set text size of viewOptions to 14
        set background color of viewOptions to {59000, 60200, 62000}

        set position of item "${APP_NAME}.app" to {150, 150}
        set position of item "Applications" to {410, 150}
        update without registering applications
        delay 2

        close
        open
        update without registering applications
        delay 2
        close
    end tell
end tell
EOF

    sleep 2
    sync
    hdiutil detach "$MOUNT_DIR" -quiet >/dev/null || hdiutil detach "$MOUNT_DIR" -force -quiet >/dev/null
    trap - EXIT

    hdiutil convert "$temp_dmg_path" \
        -format UDZO \
        -imagekey zlib-level=9 \
        -o "$dmg_path" >/dev/null
fi

rm -f "$temp_dmg_path" "$attach_plist_path"
cp -R "$dmg_path" "$tracked_dmg_path"

printf '%s\n' "$tracked_dmg_path"
