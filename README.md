# HandyTab

A macOS menu bar app that opens a target URL from a 3-finger trackpad tap. It also includes an optional Hand Wave Webcam mode for fun.

## Quickstart

```bash
# Setup
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt

# Download MediaPipe model
curl -o gesture_recognizer.task https://storage.googleapis.com/mediapipe-tasks/gesture_recognizer/gesture_recognizer.task

# Run the Swift menu bar app.
# Trackpad taps are handled in Swift; MediaPipe stays in Python for the webcam extra.
swift run
```

## Usage
1. Run `swift run`.
2. Tap the trackpad with 3 fingers to open the target URL in your system default browser.
3. Use **Open** in the menu to change the destination URL, persisted to `~/.handytab_config.json`.
4. Toggle **Hand Wave Webcam** only if you want the optional camera gesture mode.
5. Toggle **Open at Login** to start HandyTab when you sign in.

The Swift runner uses Apple's private `MultitouchSupport.framework`, so it is intended for local/personal use rather than App Store distribution.

## Build

Build the Swift app:

```bash
make build
```

Build a DMG:

```bash
./scripts/dmg.sh
```

The DMG script builds a signed `HandyTab.app`, stages it with an Applications shortcut, and bundles the MediaPipe model plus `venv` site-packages when available.
