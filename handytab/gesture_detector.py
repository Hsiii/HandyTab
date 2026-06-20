"""Gesture detection engine — camera capture + MediaPipe recognition in a background thread."""

import logging
import os
import threading
import time
from typing import Callable, Optional

from . import config
from .triggers import GestureTriggerStateMachine

logger = logging.getLogger(__name__)


class GestureDetector:
    """Runs gesture detection on a background thread.

    Calls `on_gesture(name, confidence)` whenever a gesture is confirmed.
    """

    def __init__(
        self,
        target_gesture: str,
        on_gesture: Callable[[str, float], None],
        on_observation: Optional[Callable[[str, float], None]] = None,
        on_error: Optional[Callable[[str], None]] = None,
    ):
        """Args:
            target_gesture:  MediaPipe category name to watch for, e.g. "Open_Palm".
            on_gesture:      Called when target gesture is confirmed.
            on_observation:  Called with the latest observed gesture each processed frame.
            on_error:        Called on fatal errors.
        """
        self.target_gesture = target_gesture
        self.on_gesture = on_gesture
        self.on_observation = on_observation or (lambda _name, _confidence: None)
        self.on_error = on_error or (lambda e: None)

        self._stop_event = threading.Event()
        self._thread: Optional[threading.Thread] = None
        self._state = GestureTriggerStateMachine(
            required_hits=config.GESTURE_REQUIRED_HITS,
            window_size=config.GESTURE_WINDOW_FRAMES,
            release_absent_seconds=config.RELEASE_ABSENT_SECONDS,
            cooldown_seconds=config.COOLDOWN_SECONDS,
        )
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
        self._state.reset()
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
        self._state.reset()
        logger.info("Gesture detector stopped")

    def _run(self):
        """Main detection loop — runs on the background thread."""
        cap = None
        recognizer = None

        try:
            if not os.path.exists(config.MODEL_PATH):
                error_msg = (
                    f"Cannot find the gesture model at:\n{config.MODEL_PATH}\n\n"
                    "Please run the download script first."
                )
                logger.error(error_msg)
                self.on_error(error_msg)
                return

            recognizer = self._create_recognizer()

            cap = self._cv2.VideoCapture(config.CAMERA_INDEX)
            if not cap.isOpened():
                error_msg = (
                    f"Cannot open camera (index {config.CAMERA_INDEX}). "
                    "Check System Settings > Privacy > Camera."
                )
                logger.error(error_msg)
                self.on_error(error_msg)
                return

            cap.set(self._cv2.CAP_PROP_FRAME_WIDTH, config.CAMERA_WIDTH)
            cap.set(self._cv2.CAP_PROP_FRAME_HEIGHT, config.CAMERA_HEIGHT)

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

        candidate = False
        trigger_ready = False
        gesture_name = "No_Hand"
        confidence = 0.0

        if result.gestures and len(result.gestures) > 0:
            top_gesture = result.gestures[0][0]
            gesture_name = top_gesture.category_name
            confidence = top_gesture.score
        else:
            logger.debug("Frame %d (ts=%dms): no gesture", frame_count, timestamp_ms)

        self.on_observation(gesture_name, confidence)

        if gesture_name != "No_Hand":
            quality_ok = self._hand_quality_ok(result, gesture_name)

            logger.debug("Frame %d (ts=%dms): %s (%.2f)",
                         frame_count, timestamp_ms, gesture_name, confidence)

            candidate = (
                gesture_name in {self.target_gesture, "Thumb_Down"}
                and confidence >= config.RELEASE_CONFIDENCE_THRESHOLD
                and quality_ok
            )
            trigger_ready = candidate and confidence >= config.TRIGGER_CONFIDENCE_THRESHOLD

        if self._state.observe(candidate=candidate, trigger_ready=trigger_ready):
            logger.info(
                "Gesture confirmed: %s (confidence=%.2f, window=%d/%d)",
                gesture_name,
                confidence,
                config.GESTURE_REQUIRED_HITS,
                config.GESTURE_WINDOW_FRAMES,
            )
            self.on_gesture(gesture_name, confidence)

    def _hand_quality_ok(self, result, gesture_name: str) -> bool:
        """Reject low-quality hand poses before they can trigger actions."""
        hand_landmarks = getattr(result, "hand_landmarks", None)
        if not hand_landmarks:
            return False

        landmarks = hand_landmarks[0]
        xs = [landmark.x for landmark in landmarks]
        ys = [landmark.y for landmark in landmarks]
        min_x, max_x = min(xs), max(xs)
        min_y, max_y = min(ys), max(ys)
        width = max_x - min_x
        height = max_y - min_y
        hand_size = max(width, height)

        if hand_size < config.MIN_HAND_BOX_RATIO:
            logger.debug("Rejecting gesture: hand too small (%.2f)", hand_size)
            return False

        margin = config.HAND_EDGE_MARGIN_RATIO
        if min_x < margin or max_x > 1.0 - margin or min_y < margin or max_y > 1.0 - margin:
            logger.debug("Rejecting gesture: hand too close to frame edge")
            return False

        if gesture_name != "Open_Palm":
            return True

        finger_pairs = ((8, 6), (12, 10), (16, 14), (20, 18))
        extended_fingers = sum(1 for tip, pip in finger_pairs if landmarks[tip].y < landmarks[pip].y)
        if extended_fingers < config.MIN_OPEN_PALM_EXTENDED_FINGERS:
            logger.debug("Rejecting open palm: only %d extended fingers", extended_fingers)
            return False

        finger_spread = abs(landmarks[8].x - landmarks[20].x)
        if width > 0 and finger_spread / width < config.MIN_OPEN_PALM_SPREAD_RATIO:
            logger.debug("Rejecting open palm: insufficient finger spread")
            return False

        return True
