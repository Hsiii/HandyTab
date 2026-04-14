"""HandyTab — macOS menu bar app for gesture-driven browser launching.

Sits in the menu bar, detects the "Hi" (Open Palm) gesture via the webcam,
and opens https://hsichen.dev in Chrome.
"""

import atexit
import logging
import os
import sys

import rumps
from PyObjCTools import AppHelper

from . import config
from .actions import ActionDispatcher
from .gesture_detector import GestureDetector


def _setup_logging():
    """Configure logging to file and console."""
    os.makedirs(config.LOG_DIR, exist_ok=True)

    root_logger = logging.getLogger()
    root_logger.setLevel(logging.DEBUG)

    # File handler — detailed
    fh = logging.FileHandler(config.LOG_FILE, encoding="utf-8")
    fh.setLevel(logging.DEBUG)
    fh.setFormatter(
        logging.Formatter("%(asctime)s [%(levelname)s] %(name)s: %(message)s")
    )
    root_logger.addHandler(fh)

    # Console handler — info only
    ch = logging.StreamHandler(sys.stderr)
    ch.setLevel(logging.INFO)
    ch.setFormatter(logging.Formatter("[%(levelname)s] %(message)s"))
    root_logger.addHandler(ch)


logger = logging.getLogger(__name__)


class HandyTabApp(rumps.App):
    """Menu bar application for HandyTab."""

    APP_TITLE = None
    OPEN_PALM_LABEL = "Open Palm"
    CLOSED_FIST_LABEL = "Closed Fist"
    NO_HAND_LABEL = "No Hand"

    def __init__(self):
        super().__init__(
            name="HandyTab",
            title=self.APP_TITLE,
            icon=config.ICON_PATH,
            template=True,
            quit_button=None,  # We'll add a custom quit button
        )

        # --- State ---
        self.detecting = False
        self.dispatcher = ActionDispatcher(cooldown_seconds=config.COOLDOWN_SECONDS)
        self.detector = GestureDetector(
            on_gesture=self._on_gesture_detected,
            on_status_change=self._on_status_change,
            on_error=self._on_error,
            on_frame_result=self._on_frame_result,
        )

        self.toggle_button = rumps.MenuItem("Start Detection", callback=self._toggle_detection)
        self.edit_url_item = rumps.MenuItem("Edit Target URL...", callback=self._edit_target_url)
        
        current_browser = config.get_browser()
        browser_label = f"Browser: {current_browser}" if current_browser else "Browser: System Default"
        self.edit_browser_item = rumps.MenuItem(browser_label, callback=self._edit_browser)

        self.menu = [
            self.toggle_button,
            None,  # Separator
            self.edit_url_item,
            self.edit_browser_item,
            None,  # Separator
            rumps.MenuItem("Quit HandyTab", callback=self._quit),
        ]

        # Register cleanup on exit
        atexit.register(self._cleanup)

        current_browser = config.get_browser() or "System Default"
        logger.info(
            "HandyTab app initialized (target: %s, browser: %s)",
            config.get_target_url(),
            current_browser,
        )

    def _toggle_detection(self, sender):
        """Start or stop gesture detection."""
        if self.detecting:
            self._stop_detection()
        else:
            self._start_detection()

    def _edit_target_url(self, sender):
        """Prompt the user to change the target URL."""
        current_url = config.get_target_url()
        window = rumps.Window(
            message="Enter the target URL to open when the gesture is detected:",
            title="Edit Target URL",
            default_text=current_url,
            cancel=True,
            icon=config.ICON_PATH,
            dimensions=(320, 24)
        )
        response = window.run()
        if response.clicked:
            new_url = response.text.strip()
            if new_url:
                config.set_target_url(new_url)
                logger.info("Target URL updated to: %s", new_url)

    def _edit_browser(self, sender):
        """Prompt the user to change the target browser."""
        current_browser = config.get_browser() or "Default"
        window = rumps.Window(
            message=(
                "Enter the macOS application name of your preferred browser (e.g., 'Safari', 'Arc', 'Firefox').\n\n"
                "Leave empty or type 'Default' to use your system's default browser."
            ),
            title="Set Browser",
            default_text=current_browser,
            cancel=True,
            icon=config.ICON_PATH,
            dimensions=(320, 24)
        )
        response = window.run()
        if response.clicked:
            val = response.text.strip()
            if not val or val.lower() == "default":
                config.set_browser(None)
                self.edit_browser_item.title = "Browser: System Default"
                logger.info("Browser preference reset to system default")
            else:
                config.set_browser(val)
                self.edit_browser_item.title = f"Browser: {val}"
                logger.info("Browser updated to: %s", val)

    def _start_detection(self):
        """Start the gesture detector."""
        if not os.path.exists(config.MODEL_PATH):
            rumps.alert(
                title="Model Not Found",
                message=(
                    f"Cannot find the gesture model at:\n{config.MODEL_PATH}\n\n"
                    "Please run the download script first."
                ),
            )
            return

        self.detecting = True
        self.toggle_button.title = "Pause Detection"
        self.title = self.APP_TITLE
        self.detector.start()
        logger.info("Detection started by user")

    def _stop_detection(self):
        """Stop the gesture detector."""
        self.detecting = False
        self.toggle_button.title = "Start Detection"
        self.title = self.APP_TITLE
        self.detector.stop()
        logger.info("Detection paused by user")

    def _on_gesture_detected(self, gesture_name: str, confidence: float):
        """Callback when the target gesture is confirmed."""
        logger.info("Gesture callback: %s (%.2f)", gesture_name, confidence)

        self.dispatcher.open_url(config.get_target_url(), config.get_browser())

    def _on_frame_result(self, gesture_name, confidence: float, streak: int):
        """Called every processed frame."""
        pass

    def _on_status_change(self, status: str):
        """Update the status display in the menu."""
        pass

    def _on_error(self, error_msg: str):
        """Handle errors from the detector."""
        logger.error("Detector error: %s", error_msg)
        
        def update_ui():
            self.detecting = False
            self.toggle_button.title = "Start Detection"
            self.title = self.APP_TITLE

            rumps.notification(
                title="HandyTab Error",
                subtitle="Detection stopped",
                message=error_msg,
            )

        self._dispatch_ui(update_ui)

    def _dispatch_ui(self, callback):
        """Schedule AppKit work onto the main run loop."""
        AppHelper.callAfter(callback)

    def _quit(self, sender):
        """Clean up and quit."""
        self._cleanup()
        rumps.quit_application()

    def _cleanup(self):
        """Release resources."""
        if self.detector.is_running:
            self.detector.stop()
        logger.info("HandyTab shutting down")

def main():
    """Entry point."""
    _setup_logging()
    logger.info("=" * 50)
    logger.info("HandyTab v1.0.0 starting")
    logger.info("Python %s", sys.version)
    logger.info("Model: %s", config.MODEL_PATH)
    logger.info("Target: %s → %s", config.TARGET_GESTURE, config.get_target_url())
    logger.info("=" * 50)

    app = HandyTabApp()
    app.run()


if __name__ == "__main__":
    main()
