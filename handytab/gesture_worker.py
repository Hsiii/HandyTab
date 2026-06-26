"""JSON-line worker for camera gesture detection.

This keeps MediaPipe in Python while another process owns the menu bar UI.
Stdout is reserved for machine-readable events; logs go to stderr.
"""

import argparse
import json
import logging
import signal
import sys
import threading
import time

from . import config
from .gesture_detector import GestureDetector


logger = logging.getLogger(__name__)


def _emit(event: dict):
    print(json.dumps(event, separators=(",", ":")), flush=True)


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Run HandyTab camera gestures as a JSON worker.")
    parser.add_argument(
        "--target-gesture",
        default=None,
        help="MediaPipe gesture name to trigger on. Defaults to Open_Palm.",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    args = _build_parser().parse_args(argv)
    logging.basicConfig(
        level=logging.INFO,
        stream=sys.stderr,
        format="[%(levelname)s] %(name)s: %(message)s",
    )

    target_gesture = args.target_gesture or config.DEFAULT_TARGET_GESTURE
    stopped = threading.Event()

    def stop(_signum=None, _frame=None):
        stopped.set()

    signal.signal(signal.SIGINT, stop)
    signal.signal(signal.SIGTERM, stop)

    detector = GestureDetector(
        target_gesture=target_gesture,
        on_gesture=lambda name, confidence: _emit(
            {"type": "trigger", "gesture": name, "confidence": confidence}
        ),
        on_observation=lambda name, confidence: _emit(
            {"type": "observation", "gesture": name, "confidence": confidence}
        ),
        on_error=lambda message: (_emit({"type": "error", "message": message}), stopped.set()),
    )

    logger.info("Starting gesture worker for target gesture: %s", target_gesture)
    _emit({"type": "ready", "target_gesture": target_gesture})
    detector.start()

    try:
        while not stopped.is_set():
            time.sleep(0.1)
    finally:
        detector.stop()
        logger.info("Gesture worker stopped")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
