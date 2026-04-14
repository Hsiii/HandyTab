"""Gesture detection engine — camera capture + MediaPipe recognition in a background thread."""

import logging
import threading
import time
from typing import Callable, Optional

from . import config

logger = logging.getLogger(__name__)


class GestureDetector:
    """Runs gesture detection on a background thread.

    Calls `on_gesture(gesture_name, confidence)` whenever the target gesture
    is detected for `consecutive_frames` frames in a row.
    """

    def __init__(
        self,
        target_gesture: str,
        on_gesture: Callable[[str, float], None],
        on_status_change: Optional[Callable[[str], None]] = None,
        on_error: Optional[Callable[[str], None]] = None,
        on_frame_result: Optional[Callable[[Optional[str], float, int], None]] = None,
    ):
        """Args:
            target_gesture:  MediaPipe category name to watch for, e.g. "Open_Palm".
            on_gesture:      Called when target gesture is confirmed (name, confidence).
            on_status_change: Called when detector lifecycle status changes.
            on_error:        Called on fatal errors.
            on_frame_result: Called every processed frame with
                             (gesture_name_or_None, confidence, consecutive_count).
                             Use this for live UI feedback.
        """
        self.target_gesture = target_gesture
        self.on_gesture = on_gesture
        self.on_status_change = on_status_change or (lambda s: None)
        self.on_error = on_error or (lambda e: None)
        self.on_frame_result = on_frame_result or (lambda g, c, s: None)

        self._stop_event = threading.Event()
        self._thread: Optional[threading.Thread] = None
        self._consecutive_count = 0
        self._target_gesture_latched = False
        self._cv2 = None
        self._mp = None

    @property
    def is_running(self) -> bool:
        return self._thread is not None and self._thread.is_alive()

    def start(self):
        """Start detection in a background thread."""
        if self.is_running:
            logger.warning("Detector is already running")
            return

        self._stop_event.clear()
        self._consecutive_count = 0
        self._target_gesture_latched = False
        self._thread = threading.Thread(target=self._run, daemon=True, name="GestureDetector")
        self._thread.start()
        logger.info("Gesture detector started")

    def stop(self):
        """Signal the detector thread to stop and wait for it."""
        if not self.is_running:
            return

        logger.info("Stopping gesture detector...")
        self._stop_event.set()
        self._thread.join(timeout=5.0)
        if self._thread.is_alive():
            logger.warning("Detector thread did not stop cleanly")
        self._thread = None
        self._consecutive_count = 0
        self._target_gesture_latched = False
        logger.info("Gesture detector stopped")

    def _run(self):
        """Main detection loop — runs on the background thread."""
        cap = None
        recognizer = None

        try:
            # Initialize the gesture recognizer
            self.on_status_change("Initializing...")
            recognizer = self._create_recognizer()

            # Open camera
            self.on_status_change("Opening camera...")
            cap = cv2.VideoCapture(config.CAMERA_INDEX)
            if not cap.isOpened():
                error_msg = (
                    f"Cannot open camera (index {config.CAMERA_INDEX}). "
                    "Check System Settings > Privacy > Camera."
                )
                logger.error(error_msg)
                self.on_error(error_msg)
                self.on_status_change("Camera error")
                return

            cap.set(cv2.CAP_PROP_FRAME_WIDTH, config.CAMERA_WIDTH)
            cap.set(cv2.CAP_PROP_FRAME_HEIGHT, config.CAMERA_HEIGHT)

            self.on_status_change("Detecting...")
            logger.info(
                "Camera opened (%.0fx%.0f). Detection loop starting.",
                cap.get(self._cv2.CAP_PROP_FRAME_WIDTH),
                cap.get(self._cv2.CAP_PROP_FRAME_HEIGHT),
            )

            frame_count = 0
            _start_time = time.monotonic()  # Reference time for real timestamps

            while not self._stop_event.is_set():
                ret, frame = cap.read()
                if not ret:
                    logger.warning("Failed to read frame from camera")
                    time.sleep(0.1)
                    continue

                frame_count += 1

                # Skip frames to reduce CPU usage.
                if frame_count % config.FRAME_SKIP != 0:
                    continue

                # Use real wall-clock timestamp — MediaPipe VIDEO mode requires
                # timestamps that match actual elapsed time, not frame counts.
                timestamp_ms = int((time.monotonic() - _start_time) * 1000)
                self._process_frame(recognizer, frame, frame_count, timestamp_ms)

                # Throttle: cap detection rate to avoid hammering the recognizer.
                # With FRAME_SKIP=3 and ~30 fps camera this fires ~10 times/sec;
                # the sleep ensures we never exceed that even on fast cameras.
                time.sleep(0.033)

        except Exception as e:
            error_msg = f"Detection error: {e}"
            logger.exception(error_msg)
            self.on_error(error_msg)
            self.on_status_change("Error")
        finally:
            if cap is not None and cap.isOpened():
                cap.release()
                logger.info("Camera released")
            if recognizer is not None:
                recognizer.close()
                logger.info("Recognizer closed")

    def _create_recognizer(self):
        """Create and return a MediaPipe GestureRecognizer."""
        import cv2
        import mediapipe as mp
        from mediapipe.tasks.python import BaseOptions
        from mediapipe.tasks.python.vision import (
            GestureRecognizer,
            GestureRecognizerOptions,
            RunningMode,
        )

        self._cv2 = cv2
        self._mp = mp

        logger.info("Loading model from: %s", config.MODEL_PATH)
        base_options = BaseOptions(model_asset_path=config.MODEL_PATH)
        options = GestureRecognizerOptions(
            base_options=base_options,
            running_mode=RunningMode.VIDEO,
            num_hands=1,
            min_hand_detection_confidence=0.5,
            min_hand_presence_confidence=0.5,
            min_tracking_confidence=0.5,
        )
        return GestureRecognizer.create_from_options(options)

    def _process_frame(self, recognizer, frame, frame_count: int, timestamp_ms: int):
        """Process a single frame for gesture recognition."""
        # Convert BGR (OpenCV) to RGB (MediaPipe)
        rgb_frame = self._cv2.cvtColor(frame, self._cv2.COLOR_BGR2RGB)
        mp_image = self._mp.Image(
            image_format=self._mp.ImageFormat.SRGB,
            data=rgb_frame,
        )

        try:
            result = recognizer.recognize_for_video(mp_image, timestamp_ms)
        except Exception as e:
            logger.debug("Recognition error on frame %d (ts=%dms): %s", frame_count, timestamp_ms, e)
            return

        if result.gestures and len(result.gestures) > 0:
            top_gesture = result.gestures[0][0]
            gesture_name = top_gesture.category_name
            confidence = top_gesture.score

            logger.debug("Frame %d (ts=%dms): %s (%.2f)",
                         frame_count, timestamp_ms, gesture_name, confidence)

            if (
                gesture_name == self.target_gesture
                and confidence >= config.CONFIDENCE_THRESHOLD
            ):
                if self._target_gesture_latched:
                    self.on_frame_result(
                        gesture_name,
                        confidence,
                        config.CONSECUTIVE_FRAMES,
                    )
                    return

                self._consecutive_count += 1
                logger.debug(
                    "Open_Palm detected (%.2f) — streak %d/%d",
                    confidence,
                    self._consecutive_count,
                    config.CONSECUTIVE_FRAMES,
                )
                self.on_frame_result(
                    gesture_name,
                    confidence,
                    self._consecutive_count,
                )

                if self._consecutive_count >= config.CONSECUTIVE_FRAMES:
                    logger.info(
                        "🖐 Hi gesture confirmed! (confidence=%.2f, streak=%d)",
                        confidence,
                        self._consecutive_count,
                    )
                    self._target_gesture_latched = True
                    self.on_gesture(gesture_name, confidence)
                    self._consecutive_count = 0
                return

            # Hand detected but not the target gesture / below threshold
            self.on_frame_result(gesture_name, confidence, 0)
        else:
            logger.debug("Frame %d (ts=%dms): no gesture", frame_count, timestamp_ms)
            self.on_frame_result(None, 0.0, 0)

        # Reset streak and release the trigger latch once the palm is gone or changed.
        if self._consecutive_count > 0:
            logger.debug("Streak broken — resetting")
        self._consecutive_count = 0
        if self._target_gesture_latched:
            logger.debug("Target gesture released — ready for the next trigger")
        self._target_gesture_latched = False
