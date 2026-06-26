<div align="center">
  <img src="assets/icon.png" alt="HandyTab icon" width="120" />

<h1>HandyTab</h1>

Open your most-used tab instantly with webcam hand wave or a quick 3-finger trackpad tap.

</div>

## Install

Build the DMG and drag HandyTab into Applications:

```bash
make dmg
open dist/HandyTab.dmg
```

## Quick Start (Dev)

```bash
pip install -r requirements.txt
curl -o gesture_recognizer.task https://storage.googleapis.com/mediapipe-tasks/gesture_recognizer/gesture_recognizer.task

make run # run swift
make dmg # build dmg
```
