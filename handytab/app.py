"""HandyTab — macOS menu bar app for gesture-driven browser launching.

Sits in the menu bar, detects gestures via the webcam, and opens the
configured target URL in the configured browser.
"""

import atexit
import logging
import os
import subprocess
import sys
import time

from Cocoa import NSEvent
import rumps
from PyObjCTools import AppHelper

from . import config
from .gesture_detector import GestureDetector


def _setup_logging():
    """Configure logging to file and console."""
    os.makedirs(config.LOG_DIR, exist_ok=True)

    root_logger = logging.getLogger()
    root_logger.setLevel(logging.DEBUG)

    # File handler — detailed
    fh = logging.FileHandler(config.LOG_FILE, encoding="utf-8")
    fh.setLevel(logging.INFO)
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
    LOGIN_ITEM_NAME = "HandyTab"

    def __init__(self):
        super().__init__(
            name="HandyTab",
            title=self.APP_TITLE,
            icon=config.ICON_PATH,
            template=True,
            quit_button=None,  # We'll add a custom quit button
        )

        # --- State ---
        self._last_open_time = 0.0
        self._last_close_time = 0.0
        self._last_status_title = self.APP_TITLE
        self._gesture, self._url, self._browser = config.load_target()
        self.camera_trigger_enabled, self.trackpad_trigger_enabled = (
            config.load_trigger_settings()
        )
        self.detector = GestureDetector(
            target_gesture=self._gesture,
            on_gesture=self._on_gesture_detected,
            on_observation=self._on_gesture_observed,
            on_error=self._on_error,
        )

        self._three_finger_monitor = None

        # --- Menu ---
        self.camera_trigger_item = rumps.MenuItem("", callback=self._toggle_camera_trigger)
        self.trackpad_trigger_item = rumps.MenuItem("", callback=self._toggle_trackpad_trigger)
        self.edit_url_item = rumps.MenuItem(
            f"Target: {self._url}", callback=self._edit_target_url
        )
        self.edit_browser_item = rumps.MenuItem(
            f"Browser: {self._browser_label}", callback=self._edit_browser
        )
        self.start_at_login_item = rumps.MenuItem("", callback=self._toggle_start_at_login)

        self.menu = [
            self.camera_trigger_item,
            self.trackpad_trigger_item,
            None,
            self.edit_url_item,
            self.edit_browser_item,
            self.start_at_login_item,
            None,
            rumps.MenuItem("Quit HandyTab", callback=self._quit),
        ]

        # Register cleanup on exit
        atexit.register(self._cleanup)

        logger.info(
            "HandyTab app initialized (gesture: %s → %s, browser: %s, camera: %s, trackpad: %s)",
            self._gesture,
            self._url,
            self._browser_label,
            self.camera_trigger_enabled,
            self.trackpad_trigger_enabled,
        )
        self._refresh_trigger_menu_titles()
        self._refresh_start_at_login_title()
        if self.trackpad_trigger_enabled:
            AppHelper.callAfter(self._install_three_finger_monitor)
        if self.camera_trigger_enabled:
            self._start_detection()

    def _install_three_finger_monitor(self):
        if self._three_finger_monitor is not None:
            return
        try:
            self._three_finger_monitor = NSEvent.addGlobalMonitorForEventsMatchingMask_handler_(
                NSEvent.NSGesture,
                self._handle_trackpad_event,
            )
            logger.info("Three-finger tap listener initialized.")
        except Exception as e:
            logger.warning("Three-finger tap listener could not be initialized: %s", e)

    def _remove_three_finger_monitor(self):
        if self._three_finger_monitor is None:
            return
        try:
            NSEvent.removeMonitor_(self._three_finger_monitor)
            logger.info("Three-finger tap listener removed.")
        except Exception as e:
            logger.warning("Three-finger tap listener could not be removed: %s", e)
        finally:
            self._three_finger_monitor = None

    def _handle_trackpad_event(self, event):
        gesture_recognizer = getattr(event, "gestureRecognizer", lambda: None)()
        if gesture_recognizer is None:
            return
        if event.type() == NSEvent.NSGesture and gesture_recognizer.numberOfTouches() == 3:
            self._on_three_finger_tap()

    def _on_three_finger_tap(self):
        logger.info("Three-finger tap detected (trackpad)")
        self._handle_trigger("trackpad", "Three_Finger_Tap")

    @property
    def _browser_label(self) -> str:
        return self._browser or "System Default"

    def _toggle_camera_trigger(self, sender):
        """Enable or disable camera gesture detection."""
        self.camera_trigger_enabled = not self.camera_trigger_enabled
        if self.camera_trigger_enabled:
            self._start_detection()
        else:
            self._stop_detection()
        self._save_trigger_settings()
        self._refresh_trigger_menu_titles()

    def _toggle_trackpad_trigger(self, sender):
        """Enable or disable the trackpad trigger."""
        self.trackpad_trigger_enabled = not self.trackpad_trigger_enabled
        if self.trackpad_trigger_enabled:
            self._install_three_finger_monitor()
        else:
            self._remove_three_finger_monitor()
        self._save_trigger_settings()
        self._refresh_trigger_menu_titles()

    def _save_trigger_settings(self):
        config.save_trigger_settings(
            camera_enabled=self.camera_trigger_enabled,
            trackpad_enabled=self.trackpad_trigger_enabled,
        )

    def _refresh_trigger_menu_titles(self):
        self.camera_trigger_item.title = (
            "Camera Gesture: On" if self.camera_trigger_enabled else "Camera Gesture: Off"
        )
        self.trackpad_trigger_item.title = (
            "Trackpad Tap: On" if self.trackpad_trigger_enabled else "Trackpad Tap: Off"
        )

    def _edit_target_url(self, sender):
        """Prompt the user to change the target URL."""
        # Use callAfter to ensure we're on the main thread and the menu has closed
        AppHelper.callAfter(self._do_edit_target_url)

    def _do_edit_target_url(self):
        try:
            logger.info("Opening Edit Target URL window")
            window = rumps.Window(
                message="Enter the target URL to open when the gesture is detected:",
                title="Edit Target URL",
                default_text=self._url,
                cancel=True,
                dimensions=(320, 24)
            )
            response = window.run()
            if response.clicked:
                new_url = response.text.strip()
                if new_url:
                    try:
                        new_url = config.normalize_target_url(new_url)
                    except ValueError as exc:
                        rumps.notification(
                            title="HandyTab",
                            subtitle="Invalid target URL",
                            message=str(exc),
                        )
                        return
                    self._url = new_url
                    config.save_target(self._gesture, self._url, self._browser)
                    self.edit_url_item.title = f"Target: {new_url}"
                    logger.info("Target URL updated to: %s", new_url)
        except Exception as e:
            logger.error("Failed to show Target URL window: %s", e)

    def _edit_browser(self, sender):
        """Prompt the user to change the target browser."""
        AppHelper.callAfter(self._do_edit_browser)

    def _do_edit_browser(self):
        try:
            logger.info("Opening Set Browser window")
            window = rumps.Window(
                message=(
                    "Enter the macOS application name of your preferred browser (e.g., 'Safari', 'Arc', 'Firefox').\n\n"
                    "Leave empty or type 'Default' to use your system's default browser."
                ),
                title="Set Browser",
                default_text=self._browser or "Default",
                cancel=True,
                dimensions=(320, 24)
            )
            response = window.run()
            if response.clicked:
                val = response.text.strip()
                if not val or val.lower() == "default":
                    self._browser = None
                    config.save_target(self._gesture, self._url, self._browser)
                    self.edit_browser_item.title = f"Browser: {self._browser_label}"
                    logger.info("Browser preference reset to system default")
                else:
                    self._browser = val
                    config.save_target(self._gesture, self._url, self._browser)
                    self.edit_browser_item.title = f"Browser: {self._browser_label}"
                    logger.info("Browser updated to: %s", val)
        except Exception as e:
            logger.error("Failed to show Set Browser window: %s", e)

    def _toggle_start_at_login(self, sender):
        """Enable or disable launching the bundled app at login."""
        app_path = self._app_bundle_path()
        if app_path is None:
            rumps.notification(
                title="HandyTab",
                subtitle="Start at Login unavailable",
                message="Build and run HandyTab.app to manage this setting.",
            )
            return

        try:
            if self._login_item_enabled():
                self._remove_login_item()
            else:
                self._add_login_item(app_path)
        except Exception as exc:
            logger.error("Failed to update login item: %s", exc)
            rumps.notification(
                title="HandyTab",
                subtitle="Could not update Start at Login",
                message=str(exc),
            )
        finally:
            self._refresh_start_at_login_title()

    def _refresh_start_at_login_title(self):
        if self._app_bundle_path() is None:
            self.start_at_login_item.title = "Start at Login: Unavailable"
            return
        self.start_at_login_item.title = (
            "Start at Login: On" if self._login_item_enabled() else "Start at Login: Off"
        )

    def _app_bundle_path(self) -> str | None:
        try:
            from Foundation import NSBundle

            bundle_path = NSBundle.mainBundle().bundlePath()
            if bundle_path and bundle_path.endswith(".app"):
                return bundle_path
        except Exception:
            pass

        for path in (sys.argv[0], __file__):
            current = os.path.abspath(path)
            while current and current != os.path.dirname(current):
                if current.endswith(".app"):
                    return current
                current = os.path.dirname(current)
        return None

    def _login_item_enabled(self) -> bool:
        script = (
            f'tell application "System Events" to exists login item "{self.LOGIN_ITEM_NAME}"'
        )
        result = self._run_osascript(script, check=False)
        return result.stdout.strip().lower() == "true"

    def _add_login_item(self, app_path: str):
        escaped_path = app_path.replace("\\", "\\\\").replace('"', '\\"')
        script = (
            'tell application "System Events" to make login item at end with properties '
            f'{{path:"{escaped_path}", hidden:false}}'
        )
        self._run_osascript(script)

    def _remove_login_item(self):
        script = f'tell application "System Events" to delete login item "{self.LOGIN_ITEM_NAME}"'
        self._run_osascript(script)

    def _run_osascript(self, script: str, check: bool = True) -> subprocess.CompletedProcess:
        return subprocess.run(
            ["osascript", "-e", script],
            check=check,
            capture_output=True,
            text=True,
            timeout=3.0,
        )

    def _start_detection(self):
        """Start the gesture detector."""
        self._set_status_title("Watching 0%")
        self.detector.start()
        logger.info("Detection started by user")

    def _stop_detection(self):
        """Stop the gesture detector."""
        self._set_status_title(self.APP_TITLE)
        self.detector.stop()
        logger.info("Detection paused by user")

    def _on_gesture_observed(self, gesture_name: str, confidence: float):
        AppHelper.callAfter(
            self._set_status_title,
            self._format_gesture_status(gesture_name, confidence),
        )

    def _on_gesture_detected(self, gesture_name: str, confidence: float):
        """Callback when the target gesture is confirmed."""
        logger.info("Gesture callback: %s (%.2f)", gesture_name, confidence)
        self._handle_trigger("camera", gesture_name)

    def _format_gesture_status(self, gesture_name: str, confidence: float) -> str:
        label = gesture_name.replace("_", " ")
        return f"{label} {confidence:.0%}"

    def _set_status_title(self, title: str | None):
        if title == self._last_status_title:
            return
        self.title = title
        self._last_status_title = title

    def _handle_trigger(self, source: str, name: str):
        """Route any enabled input trigger to the configured target action."""
        if source == "camera" and not self.camera_trigger_enabled:
            return
        if source == "trackpad" and not self.trackpad_trigger_enabled:
            return
        logger.info("Trigger received from %s: %s", source, name)
        if name == "Thumb_Down":
            AppHelper.callAfter(self._close_current_tab)
        else:
            AppHelper.callAfter(self._open_target_url)

    def _on_error(self, error_msg: str):
        """Handle errors from the detector."""
        logger.error("Detector error: %s", error_msg)
        
        def update_ui():
            self.camera_trigger_enabled = False
            self._save_trigger_settings()
            self._refresh_trigger_menu_titles()
            self._set_status_title(self.APP_TITLE)

            rumps.notification(
                title="HandyTab Error",
                subtitle="Detection stopped",
                message=error_msg,
            )

        AppHelper.callAfter(update_ui)

    def _open_target_url(self) -> bool:
        """Open the configured target URL, respecting the cooldown."""
        if (time.time() - self._last_open_time) < config.COOLDOWN_SECONDS:
            return False

        url = self._url
        browser = self._browser

        try:
            cmd = ["open", "-a", browser, url] if browser else ["open", url]
            proc = subprocess.Popen(
                cmd,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.PIPE,
                text=True,
            )
            _, stderr = proc.communicate(timeout=1.0)
            if proc.returncode != 0:
                logger.error(
                    "macOS 'open' command failed with code %d: %s",
                    proc.returncode,
                    stderr.strip(),
                )
                return False

            logger.info("Opened %s (Browser: %s)", url, browser or "System Default")
            self._last_open_time = time.time()
            return True
        except subprocess.TimeoutExpired:
            logger.info("Opened %s (Browser: %s) [Async]", url, browser or "System Default")
            self._last_open_time = time.time()
            return True
        except FileNotFoundError:
            logger.error("'open' command not found — are you on macOS?")
            return False
        except Exception as exc:
            logger.error("Failed to open URL: %s", exc)
            return False

    def _close_current_tab(self) -> bool:
        """Close the active browser tab using the browser's AppleScript API."""
        if (time.time() - self._last_close_time) < config.COOLDOWN_SECONDS:
            return False

        browser = self._browser or self._frontmost_app_name()
        script = self._browser_close_tab_script(browser)
        if script is None:
            logger.error("No stable tab-close AppleScript support for: %s", browser or "Unknown")
            return False

        try:
            self._run_osascript(script)
            self._last_close_time = time.time()
            logger.info("Closed current tab (Browser: %s)", browser)
            return True
        except Exception as exc:
            logger.error("Failed to close current tab: %s", exc)
            return False

    def _frontmost_app_name(self) -> str | None:
        script = (
            'tell application "System Events" to get name of first application process '
            "whose frontmost is true"
        )
        result = self._run_osascript(script, check=False)
        return result.stdout.strip() or None

    def _browser_close_tab_script(self, browser: str | None) -> str | None:
        if not browser:
            return None

        escaped_browser = browser.replace("\\", "\\\\").replace('"', '\\"')
        browser_key = browser.casefold()

        if browser_key == "safari":
            return (
                f'tell application "{escaped_browser}"\n'
                "if exists front window then close current tab of front window\n"
                "end tell"
            )

        chromium_browsers = {
            "arc",
            "brave browser",
            "chromium",
            "dia",
            "google chrome",
            "microsoft edge",
            "opera",
            "vivaldi",
        }
        if browser_key in chromium_browsers:
            return (
                f'tell application "{escaped_browser}"\n'
                "if exists front window then close active tab of front window\n"
                "end tell"
            )

        return None

    def _quit(self, sender):
        """Clean up and quit."""
        self._cleanup()
        rumps.quit_application()

    def _cleanup(self):
        """Release resources."""
        self._remove_three_finger_monitor()
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
    gesture, url, _browser = config.load_target()
    logger.info("Target: %s → %s", gesture, url)
    logger.info("=" * 50)

    app = HandyTabApp()
    app.run()


if __name__ == "__main__":
    main()
