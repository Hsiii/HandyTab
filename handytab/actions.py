"""Action dispatcher — executes system actions when gestures are detected."""

import logging
import subprocess
import time

logger = logging.getLogger(__name__)


class ActionDispatcher:
    """Handles triggering actions with a cooldown to prevent rapid-fire."""

    def __init__(self, cooldown_seconds: float = 5.0):
        self.cooldown_seconds = cooldown_seconds
        self._last_trigger_time: float = 0.0

    @property
    def is_on_cooldown(self) -> bool:
        return (time.time() - self._last_trigger_time) < self.cooldown_seconds

    @property
    def cooldown_remaining(self) -> float:
        remaining = self.cooldown_seconds - (time.time() - self._last_trigger_time)
        return max(0.0, remaining)

    def open_url(self, url: str, browser: str) -> bool:
        """Open a URL in the specified browser.

        Returns True if the action was triggered, False if on cooldown.
        """
        if self.is_on_cooldown:
            logger.debug(
                "Action suppressed — cooldown active (%.1fs remaining)",
                self.cooldown_remaining,
            )
            return False

        try:
            subprocess.Popen(["open", "-a", browser, url])
            self._last_trigger_time = time.time()
            logger.info("Opened %s in %s", url, browser)
            return True
        except FileNotFoundError:
            logger.error("'open' command not found — are you on macOS?")
            return False
        except Exception as e:
            logger.error("Failed to open URL: %s", e)
            return False

    def reset_cooldown(self):
        """Reset the cooldown timer."""
        self._last_trigger_time = 0.0
