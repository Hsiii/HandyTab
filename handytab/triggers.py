"""Shared trigger events and gesture state handling."""

import time
from collections import deque
from typing import Deque


class GestureTriggerStateMachine:
    """Converts noisy per-frame recognition into one deliberate trigger."""

    def __init__(
        self,
        *,
        required_hits: int,
        window_size: int,
        release_absent_seconds: float,
        cooldown_seconds: float,
    ):
        self.required_hits = required_hits
        self.window_size = window_size
        self.release_absent_seconds = release_absent_seconds
        self.cooldown_seconds = cooldown_seconds
        self.phase = "idle"
        self._samples: Deque[bool] = deque(maxlen=window_size)
        self._absent_since: float | None = None
        self._cooldown_until = 0.0

    def reset(self):
        self.phase = "idle"
        self._samples.clear()
        self._absent_since = None
        self._cooldown_until = 0.0

    def observe(self, candidate: bool, trigger_ready: bool, now: float | None = None) -> bool:
        """Return True exactly once when the gesture is confirmed."""
        now = time.monotonic() if now is None else now

        if candidate:
            self._absent_since = None
        elif self._absent_since is None:
            self._absent_since = now

        if self.phase == "cooldown":
            if now < self._cooldown_until:
                return False
            self.phase = "idle"
            self._samples.clear()

        if self.phase == "triggered":
            if (
                self._absent_since is not None
                and now - self._absent_since >= self.release_absent_seconds
            ):
                self.phase = "cooldown"
                self._cooldown_until = now + self.cooldown_seconds
                self._samples.clear()
            return False

        self._samples.append(trigger_ready)
        hits = sum(self._samples)

        if hits > 0:
            self.phase = "candidate"
        else:
            self.phase = "idle"

        if len(self._samples) >= self.required_hits and hits >= self.required_hits:
            self.phase = "triggered"
            self._samples.clear()
            return True

        return False
