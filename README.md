# HandyTab ✋

A macOS menu bar app that detects hand gestures via webcam to open a target URL in Chrome when you wave **Hi** 👋.

## Quickstart

```bash
# Setup
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt

# Download MediaPipe model
mkdir -p models
curl -o models/gesture_recognizer.task https://storage.googleapis.com/mediapipe-tasks/gesture_recognizer/gesture_recognizer.task

# Run
python run_handytab.py
```

## Usage
1. Click the ✋ icon in the menu bar and select **Start Detection**.
2. Wave your hand (**Open Palm**) at the camera to trigger the browser action.
3. Use **Edit Target...** to change the destination URL (persisted to `~/.handytab_config.json`).

## Build

To build the macOS application bundle and the DMG installer, simply run:

```bash
make build
```

The resulting assets will be located in the `dist/` directory:
- `dist/HandyTab.app`: The macOS application bundle.
- `dist/HandyTab.dmg`: The disk image installer.

