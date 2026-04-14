"""HandyTab — macOS menu bar app entry point for py2app bundling.

This file uses absolute imports so it works as a py2app entry script.
"""

import sys
import os

# Ensure the parent directory is on sys.path so 'handytab' package is importable
# This is needed when py2app runs this file as the main script
_this_dir = os.path.dirname(os.path.abspath(__file__))
_parent_dir = os.path.dirname(_this_dir)
if _parent_dir not in sys.path:
    sys.path.insert(0, _parent_dir)

from handytab.app import main

if __name__ == "__main__":
    main()
