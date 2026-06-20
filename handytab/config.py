"""Configuration constants for HandyTab."""

import os
import sys

# --- Paths ---
# When bundled with py2app, resources are in the app bundle's Resources dir.
# When running from source, they're relative to the project root.
_BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

def _resource_path(relative_path: str) -> str:
    """Resolve path to a resource, works both in dev and bundled .app.

    In a py2app bundle, this file lives at:
        HandyTab.app/Contents/Resources/lib/python3.12/handytab/config.py
    And data_files (like models/) are placed at:
        HandyTab.app/Contents/Resources/models/
    So we walk up from __file__ looking for a Resources dir that contains
    our target file.
    """
    # PyInstaller fallback
    if hasattr(sys, '_MEIPASS'):
        return os.path.join(sys._MEIPASS, relative_path)

    # py2app: walk up from this file's directory looking for Resources/
    current = os.path.dirname(os.path.abspath(__file__))
    for _ in range(6):  # Walk up at most 6 levels
        candidate = os.path.join(current, relative_path)
        if os.path.exists(candidate):
            return candidate
        current = os.path.dirname(current)

    # Dev mode: relative to project root
    return os.path.join(_BASE_DIR, relative_path)



# --- Model ---
MODEL_PATH = _resource_path(os.path.join("models", "gesture_recognizer.task"))
ICON_PATH = _resource_path(os.path.join("assets", "icon.png"))

import json

from .target import Target

# --- Target Action ---
_CONFIG_FILE = os.path.expanduser("~/.handytab_config.json")

_DEFAULT_TARGET = Target(
    gesture="Open_Palm",
    url="https://hsichen.dev",
    browser=None,
)
_DEFAULT_CAMERA_TRIGGER_ENABLED = False
_DEFAULT_TRACKPAD_TRIGGER_ENABLED = True


def load_target() -> Target:
    """Load the active target from disk, falling back to defaults."""
    if os.path.exists(_CONFIG_FILE):
        try:
            with open(_CONFIG_FILE, "r") as f:
                data = json.load(f)
            return Target(
                gesture=data.get("gesture", _DEFAULT_TARGET.gesture),
                url=data.get("target_url", _DEFAULT_TARGET.url),
                browser=data.get("browser") or None,
            )
        except Exception:
            pass
    return Target(
        gesture=_DEFAULT_TARGET.gesture,
        url=_DEFAULT_TARGET.url,
        browser=_DEFAULT_TARGET.browser,
    )


def save_target(target: Target):
    """Persist the active target to disk."""
    data = {}
    if os.path.exists(_CONFIG_FILE):
        try:
            with open(_CONFIG_FILE, "r") as f:
                data = json.load(f)
        except Exception:
            pass
    data["gesture"] = target.gesture
    data["target_url"] = target.url
    data["browser"] = target.browser
    try:
        with open(_CONFIG_FILE, "w") as f:
            json.dump(data, f, indent=2)
    except Exception:
        pass


def _load_config_data() -> dict:
    if os.path.exists(_CONFIG_FILE):
        try:
            with open(_CONFIG_FILE, "r") as f:
                return json.load(f)
        except Exception:
            pass
    return {}


def _save_config_data(data: dict):
    try:
        with open(_CONFIG_FILE, "w") as f:
            json.dump(data, f, indent=2)
    except Exception:
        pass


def load_trigger_settings() -> tuple[bool, bool]:
    """Load whether camera and trackpad triggers are enabled."""
    data = _load_config_data()
    return (
        bool(data.get("camera_trigger_enabled", _DEFAULT_CAMERA_TRIGGER_ENABLED)),
        bool(data.get("trackpad_trigger_enabled", _DEFAULT_TRACKPAD_TRIGGER_ENABLED)),
    )


def save_trigger_settings(camera_enabled: bool, trackpad_enabled: bool):
    """Persist enabled trigger sources."""
    data = _load_config_data()
    data["camera_trigger_enabled"] = camera_enabled
    data["trackpad_trigger_enabled"] = trackpad_enabled
    _save_config_data(data)


# --- Detection Tuning ---
TRIGGER_CONFIDENCE_THRESHOLD = 0.45  # Confidence required for a positive window hit
RELEASE_CONFIDENCE_THRESHOLD = 0.25  # Lower threshold keeps the latch stable near the edge
CONFIDENCE_THRESHOLD = TRIGGER_CONFIDENCE_THRESHOLD  # Backward-compatible alias
COOLDOWN_SECONDS = 0.7        # Prevent instant open-close-open retriggers
GESTURE_WINDOW_FRAMES = 5     # Rolling frame window used for confirmation
GESTURE_REQUIRED_HITS = 3     # Trigger when this many window samples are positive
RELEASE_ABSENT_SECONDS = 0.35 # Gesture must be absent this long before rearming
FRAME_SKIP = 3                # Process 1-in-3 frames -> ~10 fps effective recognition
CAMERA_WIDTH = 320            # Half-res is sufficient for gesture recognition
CAMERA_HEIGHT = 240
CAMERA_INDEX = 0              # Default camera device index
MIN_HAND_BOX_RATIO = 0.16     # Reject tiny far-away hands and classifier noise
HAND_EDGE_MARGIN_RATIO = 0.03 # Reject hands clipped hard against the frame edge
MIN_OPEN_PALM_EXTENDED_FINGERS = 3
MIN_OPEN_PALM_SPREAD_RATIO = 0.45

# --- Gesture ---
# TARGET_GESTURE is now owned by Target (loaded via config.load_target()).

# --- Logging ---
LOG_DIR = os.path.expanduser("~/Library/Logs/HandyTab")
LOG_FILE = os.path.join(LOG_DIR, "handytab.log")
