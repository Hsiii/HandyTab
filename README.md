<div align="center">
  <img src="assets/icon.png" alt="HandyTab icon" width="120" />

<h1>HandyTab</h1>

Open your target URL with a 3-finger trackpad tap.

Optional webcam hand wave included, mostly for fun.
</div>

## Why HandyTab

- **Trackpad first:** one 3-finger tap opens your chosen page.
- **Menu bar only:** no Dock icon, no window to manage.
- **Local by design:** target URL and toggles stay on your Mac.

## Install

Build the DMG and drag HandyTab into Applications:

```bash
make dmg
open dist/HandyTab.dmg
```

The trackpad shortcut works from the Swift app. The optional webcam mode also needs the MediaPipe model and Python packages from the setup below.

## Development

```bash
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
curl -o gesture_recognizer.task https://storage.googleapis.com/mediapipe-tasks/gesture_recognizer/gesture_recognizer.task

make run
```

Useful commands:

```bash
make build
make dmg
make clean
```

## Notes

HandyTab uses Apple's private `MultitouchSupport.framework`, so it is meant for personal/local use rather than App Store distribution.
