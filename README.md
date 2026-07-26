<div align="center">
  <img src="assets/icon.png" alt="HandyTab icon" width="120" />

<h1>HandyTab</h1>

Open your most-used tab instantly with webcam hand wave or a quick 3-finger trackpad tap.

</div>

## Install

Install with Homebrew:

```bash
brew install --cask Hsiii/tap/handytab
```

Or build the DMG and drag HandyTab into Applications:

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

## Release packaging

Generate a versioned app archive and Homebrew cask:

```bash
make brew ARGS="--version 0.1.0"
```

Release builds use `--notarize` and require a Developer ID Application signing
identity plus Apple notarization credentials. The GitHub workflow reads the same
certificate and notarization secrets used by Comux.

To copy the generated cask into the adjacent shared tap checkout:

```bash
make tap ARGS="--version 0.1.0"
```
