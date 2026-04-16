"""Trackpad gesture listener helpers for macOS."""

from Cocoa import NSEvent
from PyObjCTools import AppHelper


class ThreeFingerTapListener:
    def __init__(self, callback):
        self.callback = callback
        self._monitor = None
        self._install_listener()

    def _install_listener(self):
        # AppKit event monitors must be installed on the main run loop.
        AppHelper.callAfter(self._install_monitor)

    def _install_monitor(self):
        if self._monitor is not None:
            return
        self._monitor = NSEvent.addGlobalMonitorForEventsMatchingMask_handler_(
            NSEvent.NSGesture, self._handle_event
        )

    def _handle_event(self, event):
        gesture_recognizer = getattr(event, "gestureRecognizer", lambda: None)()
        if gesture_recognizer is None:
            return
        if event.type() == NSEvent.NSGesture and gesture_recognizer.numberOfTouches() == 3:
            self.callback()
