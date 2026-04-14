"""A single gesture → action mapping."""

from dataclasses import dataclass
from typing import Optional


@dataclass
class Target:
    """Bundles the gesture trigger, destination URL, and preferred browser."""

    gesture: str           # MediaPipe category name, e.g. "Open_Palm"
    url: str               # URL to open on trigger
    browser: Optional[str] = None  # macOS app name, or None for system default

    @property
    def browser_label(self) -> str:
        """Human-readable browser label for display in the menu."""
        return self.browser or "System Default"
