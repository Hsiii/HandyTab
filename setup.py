"""py2app setup for bundling HandyTab as a native macOS .app."""

from setuptools import setup

APP = ["run_handytab.py"]
DATA_FILES = [
    ("models", ["models/gesture_recognizer.task"]),
    ("assets", ["assets/icon.png"]),
]
OPTIONS = {
    "argv_emulation": False,
    "iconfile": "assets/AppIcon.icns",
    "plist": {
        "LSUIElement": True,  # No Dock icon — menu bar only
        "NSCameraUsageDescription": (
            "HandyTab needs camera access to detect hand gestures "
            "and open your browser when you wave Hi."
        ),
        "CFBundleName": "HandyTab",
        "CFBundleDisplayName": "HandyTab",
        "CFBundleIdentifier": "dev.hsichen.handytab",
        "CFBundleVersion": "1.0.0",
        "CFBundleShortVersionString": "1.0.0",
    },
    "packages": ["handytab", "mediapipe", "cv2", "rumps", "numpy"],
}

setup(
    name="HandyTab",
    app=APP,
    data_files=DATA_FILES,
    options={"py2app": OPTIONS},
    setup_requires=["py2app"],
)
