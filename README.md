# HandyTab

A macOS menu bar app that opens a target URL from a webcam hand gesture or a custom trackpad tap.

## Quickstart

```bash
# Setup
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt

# Download MediaPipe model
mkdir -p models
curl -o models/gesture_recognizer.task https://storage.googleapis.com/mediapipe-tasks/gesture_recognizer/gesture_recognizer.task

# Run the Swift menu bar shell.
# This keeps MediaPipe in Python and uses raw multitouch frames for trackpad taps.
swift run
```

## Usage
1. Click the app icon in the menu bar and toggle **Camera Gesture** or **Trackpad Gesture**.
2. Wave your hand at the camera, or tap the trackpad with the configured finger count, to open the target tab.
3. Use **Trackpad Fingers** to cycle between 2-, 3-, 4-, and 5-finger tap triggers.
4. Use **Target** to change the destination URL (persisted to `~/.handytab_config.json`).

The Swift runner uses Apple's private `MultitouchSupport.framework`, so it is intended for local/personal use rather than App Store distribution.

## Legacy Python App

The original Python/Rumps app is still available:

```bash
python -m handytab
```

Its webcam gesture path works, but custom trackpad taps should use the Swift runner.

## Build

Build the Swift runner:

```bash
swift build
```

To build the macOS application bundle and the DMG installer, simply run:

```bash
make build
```

The resulting assets will be located in the `dist/` directory:
- `dist/HandyTab.app`: The macOS application bundle.
- `dist/HandyTab.dmg`: The disk image installer.
