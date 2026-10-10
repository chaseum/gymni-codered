"""Tunables. Every threshold here is an UNCALIBRATED starting guess; tune on real clips and record the values used."""
import os
from dataclasses import dataclass, field


@dataclass
class RepThresholds:
    angle: str          # which measurement drives the cycle
    lowered_deg: float  # enter "lowered" when angle crosses this
    raised_deg: float   # enter "raised" when angle crosses this
    hysteresis_deg: float = 8.0
    min_rep_ms: float = 600.0


@dataclass
class Config:
    backend_url: str = os.environ.get("GYMAI_BACKEND_URL", "http://localhost:8000")
    session_id: str = os.environ.get("GYMAI_SESSION_ID", "session-001")
    camera_index: int = int(os.environ.get("GYMAI_CAMERA", "0"))
    min_landmark_visibility: float = 0.5
    pose_model_path: str = "ml/models/pose_landmarker_full.task"  # downloaded, not committed
    reps: dict[str, RepThresholds] = field(default_factory=lambda: {
        "curl": RepThresholds("elbow_angle_deg", lowered_deg=150, raised_deg=60),
        "squat": RepThresholds("knee_angle_deg", lowered_deg=100, raised_deg=160),
        "deadlift": RepThresholds("hip_angle_deg", lowered_deg=110, raised_deg=165),
    })
