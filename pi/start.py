"""Run this checkout's fitness_ml on the Pi's verified Python/MediaPipe runtime."""
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path[:0] = [str(ROOT / "ml/src"), str(ROOT / "pi/vendor")]
os.environ.setdefault("GYMAI_MODELS_DIR", str(ROOT / "ml/models"))
os.environ.setdefault("OMP_NUM_THREADS", "2")
os.environ.setdefault("OPENBLAS_NUM_THREADS", "1")

import mediapipe as mp
import torch

if sys.version_info[:2] != (3, 12) or mp.__version__ != "0.10.18":
    raise SystemExit("Pi 4 requires the verified Python 3.12 / MediaPipe 0.10.18 runtime.")
torch.set_num_threads(2)
torch.set_num_interop_threads(1)

from fitness_ml.__main__ import main

if len(sys.argv) == 1:
    sys.argv.extend(["run", "--source", "live", "--exercise", "curl", "--discover-phone", "--no-window",
                     "--preview-port", "8081", "--capture-width", "640", "--capture-height", "480",
                     "--analysis-width", "480", "--max-fps", "8"])
sys.exit(main())
