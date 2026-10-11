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
    signal: str                         # "elbow" | "knee" | "hip" (per side) or a whole-body feature name
    start_phase: Literal["lowered", "raised"]
    start_deg: float
    turn_deg: float
    hysteresis_deg: float = 8.0
    min_rep_ms: float = 600.0
    max_rep_ms: float = 10_000.0
    max_gap_ms: float = 800.0           # tracking loss longer than this mid-rep voids that rep
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
    # Tuned on real front-facing sessions (demo/clips/me_curl.mp4 + a water-bottle session, 2026-10-10): the
    # estimated 3D elbow angle flattened every curl to ~85-90°, the 2D angle dipped cleanly to 5-25°. Counts on the
    # recording are identical for turn 75° and 85°; 85° also catches the 77-84° near-misses of light, quick
    # water-bottle curls, as does min_rep_ms 450 (400 ms started double-counting on the recording).
    "curl": ExerciseConfig(
        variation="standing_dumbbell",  # simultaneous, alternating and single-arm all work: one counter per arm
        basis="image_2d",
        rep=RepConfig("elbow", start_phase="lowered", start_deg=140, turn_deg=85, min_rep_ms=450),
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
    # The five below come from the Multi-View dataset. No form *rules* yet: their form signal is the trained
    # good/bad model. Counting thresholds are starting guesses; tune with `run --record` + replay.
    "shoulder_press": ExerciseConfig(
        variation="standing_dumbbell", basis="image_2d",
        rep=RepConfig("elbow", start_phase="lowered", start_deg=105, turn_deg=150),
        required=("shoulder", "elbow", "wrist"), thresholds={},
    ),
    "triceps_extension": ExerciseConfig(
        variation="overhead_dumbbell", basis="world_3d",
        rep=RepConfig("elbow", start_phase="lowered", start_deg=90, turn_deg=145),
        required=("shoulder", "elbow", "wrist"), thresholds={},
    ),
    "row": ExerciseConfig(
        variation="bent_over_dumbbell", basis="world_3d",
        rep=RepConfig("elbow", start_phase="lowered", start_deg=145, turn_deg=100),
        required=("shoulder", "elbow", "wrist"), thresholds={},
    ),
    "push_up": ExerciseConfig(
        variation="standard", basis="image_2d",  # side view
        rep=RepConfig("elbow", start_phase="raised", start_deg=150, turn_deg=105),
        required=("shoulder", "elbow", "wrist"), thresholds={},
    ),
    "side_bend": ExerciseConfig(
        variation="standing_dumbbell", basis="image_2d",  # front view: lean is measured in the image plane
        rep=RepConfig("trunk_lean_deg", start_phase="raised", start_deg=8, turn_deg=20, hysteresis_deg=3),
        required=("shoulder", "hip"), thresholds={},
    ),
}
CONTRACT_EXERCISES = ("curl", "squat", "deadlift")  # v1 contract ids; the rest travel as "other" + exercise_detail


@dataclass
class Config:
    backend_url: str = os.environ.get("GYMAI_BACKEND_URL", "http://localhost:8000")
    session_id: str = os.environ.get("GYMAI_SESSION_ID", "session-001")
    camera_index: int = int(os.environ.get("GYMAI_CAMERA", "0"))
    models_dir: Path = Path(os.environ.get("GYMAI_MODELS_DIR", REPO / "ml" / "models"))  # env: installed copies (Pi)
    min_visibility: float = 0.4         # MediaPipe per-joint visibility needed to count; jackets/dumbbells lower it
    side_switch_margin: float = 0.2     # visibility gain needed before the tracked side changes
    side_view_max_ratio: float = 0.30   # shoulder width / torso length below this = side view
    front_view_min_ratio: float = 0.55  # above this = front view; in between = diagonal
    recognition_window_ms: float = 2000
    recognition_stride_ms: float = 500
    reject_below: float = 0.6           # recognizer confidence under this -> "unknown"
    form_preroll_ms: float = 700        # form checks also see this much before the rep starts (setup posture)
    exercises: dict[str, ExerciseConfig] = field(default_factory=lambda: dict(EXERCISES))
