"""Configuration constants for HandyTab's MediaPipe worker."""

import os
import sys

# --- Paths ---
_BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def _resource_path(relative_path: str) -> str:
    """Resolve a worker resource from Swift's project-root cwd or package root."""
    if hasattr(sys, "_MEIPASS"):
        return os.path.join(sys._MEIPASS, relative_path)

    for root in (os.getcwd(), _BASE_DIR):
        candidate = os.path.join(root, relative_path)
        if os.path.exists(candidate):
            return candidate

    return os.path.join(_BASE_DIR, relative_path)


# --- Model ---
MODEL_PATH = _resource_path("gesture_recognizer.task")
DEFAULT_TARGET_GESTURE = "Open_Palm"


# --- Detection Tuning ---
TRIGGER_CONFIDENCE_THRESHOLD = 0.45  # Confidence required for a positive window hit
RELEASE_CONFIDENCE_THRESHOLD = 0.25  # Lower threshold keeps the latch stable near the edge
COOLDOWN_SECONDS = 0.7        # Prevent instant open-close-open retriggers
GESTURE_WINDOW_FRAMES = 4     # Rolling frame window used for confirmation
GESTURE_REQUIRED_HITS = 2     # Trigger when this many window samples are positive
RELEASE_ABSENT_SECONDS = 0.35 # Gesture must be absent this long before rearming
FRAME_SKIP = 3                # Process 1-in-3 frames -> ~10 fps effective recognition
CAMERA_WIDTH = 320            # Half-res is sufficient for gesture recognition
CAMERA_HEIGHT = 240
CAMERA_INDEX = 0              # Default camera device index
MIN_HAND_BOX_RATIO = 0.16     # Reject tiny far-away hands and classifier noise
HAND_EDGE_MARGIN_RATIO = 0.03 # Reject hands clipped hard against the frame edge
MIN_OPEN_PALM_EXTENDED_FINGERS = 3
MIN_OPEN_PALM_SPREAD_RATIO = 0.45

# --- Logging ---
LOG_DIR = os.path.expanduser("~/Library/Logs/HandyTab")
LOG_FILE = os.path.join(LOG_DIR, "handytab.log")
