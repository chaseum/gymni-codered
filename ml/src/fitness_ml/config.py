"""Tunables. Every threshold is an UNCALIBRATED starting guess: tune on real clips, record what you used.

A form criterion only reaches the backend once its issue code is listed in `reviewed` for that
exercise, i.e. after a human checked it against demonstration clips. Until then it is a debug candidate.
"""
import os
from dataclasses import dataclass, field
from pathlib import Path
from typing import Literal

Basis = Literal["image_2d", "world_3d"]
REPO = Path(__file__).resolve().parents[3]


@dataclass(frozen=True)
class RepConfig:
    """One rep = leave `start_deg`, pass `turn_deg`, come back to `start_deg`."""
    signal: str                         # joint angle driving the cycle: "elbow", "knee" or "hip"
    start_phase: Literal["lowered", "raised"]
    start_deg: float
    turn_deg: float
    hysteresis_deg: float = 8.0
    min_rep_ms: float = 600.0
    max_rep_ms: float = 10_000.0
    max_gap_ms: float = 400.0           # tracking loss longer than this mid-rep voids that rep
    smoothing: float = 0.5              # EMA weight of the newest sample (1.0 = no smoothing)


@dataclass(frozen=True)
class ExerciseConfig:
    variation: str
    basis: Basis                        # coordinates used for the counting angle
    rep: RepConfig
    required: tuple[str, ...]           # landmark names per side, without "left_"/"right_"
    thresholds: dict[str, float]
    reviewed: frozenset[str] = frozenset()


EXERCISES: dict[str, ExerciseConfig] = {
    # Webcam faces the user, so the 2D elbow angle is foreshortened; the estimated 3D angle is steadier.
    "curl": ExerciseConfig(
        variation="standing_dumbbell_simultaneous",  # or "standing_dumbbell_alternating": one counter per arm
        basis="world_3d",
        rep=RepConfig("elbow", start_phase="lowered", start_deg=145, turn_deg=85),
        required=("shoulder", "elbow", "wrist"),
        thresholds={"full_flexion_max_deg": 60},
    ),
    # Side view required for depth. Variation must be stated: bodyweight vs goblet/barbell change depth norms.
    "squat": ExerciseConfig(
        variation="bodyweight",
        basis="image_2d",
        rep=RepConfig("knee", start_phase="raised", start_deg=160, turn_deg=120, min_rep_ms=800),
        required=("hip", "knee", "ankle"),
        thresholds={"depth_knee_max_deg": 95},
    ),
    # Side view. Landmarks cannot show bar path, bracing or spinal flexion; none of those are claimed.
    "deadlift": ExerciseConfig(
        variation="conventional",
        basis="image_2d",
        rep=RepConfig("hip", start_phase="lowered", start_deg=120, turn_deg=160, min_rep_ms=800),
        required=("shoulder", "hip", "knee"),
        thresholds={"early_window_frac": 0.3, "hip_shoulder_rise_ratio": 2.0, "min_hip_rise": 0.05},
    ),
}


@dataclass
class Config:
    backend_url: str = os.environ.get("GYMAI_BACKEND_URL", "http://localhost:8000")
    session_id: str = os.environ.get("GYMAI_SESSION_ID", "session-001")
    camera_index: int = int(os.environ.get("GYMAI_CAMERA", "0"))
    models_dir: Path = REPO / "ml" / "models"
    min_visibility: float = 0.5
    side_switch_margin: float = 0.2     # visibility gain needed before the tracked side changes
    side_view_max_ratio: float = 0.30   # shoulder width / torso length below this = side view
    front_view_min_ratio: float = 0.55  # above this = front view; in between = diagonal
    recognition_window_ms: float = 2000
    recognition_stride_ms: float = 500
    reject_below: float = 0.6           # recognizer confidence under this -> "unknown"
    exercises: dict[str, ExerciseConfig] = field(default_factory=lambda: dict(EXERCISES))
