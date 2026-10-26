"""Project-relative locations (everything is resolved from this file, so the repo can live anywhere)."""
from pathlib import Path
ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / 'assets'
BUILD = ROOT / 'build'          # intermediate files (ignored by git)
DIST = ROOT / 'dist'            # finished apps (ignored by git)
