"""Typed mirror of the observation contract. The JSON schema in contracts/ is authoritative."""
from dataclasses import asdict, dataclass, field
from typing import Literal

Exercise = Literal["curl", "squat", "deadlift"]
Recognized = Literal["curl", "squat", "deadlift", "other", "unknown"]
Source = Literal["live", "recorded"]
Tracking = Literal["ready", "low_visibility", "lost", "unassessable"]
Phase = Literal["unknown", "lowered", "raising", "raised", "lowering"]
Provenance = Literal["reviewed_rules", "trained_model", "fixture"]


@dataclass
class CompletedRep:
    rep_index: int  # monotonic for the whole analyzer run; never reused, even across sets
    duration_ms: float | None = None


@dataclass
class Issue:
    code: str  # "<exercise>.<snake_case>", e.g. "curl.elbow_drift"
    evidence: dict[str, float | str | None] = field(default_factory=dict)


@dataclass
class Observation:
    observation_id: str
    session_id: str
    source: Source
    source_timestamp_ms: float  # capture/video time base, NOT epoch
    exercise: Recognized
    tracking_status: Tracking
    phase: Phase
    inference_provenance: Provenance
    completed_rep: CompletedRep | None = None  # set only on the frame a new cycle completes
    measurements: dict[str, float | None] = field(default_factory=dict)
    measurement_basis: Literal["image_2d", "world_3d"] = "image_2d"
    issues: list[Issue] = field(default_factory=list)
    exercise_confidence: float | None = None  # recognition confidence, NOT form-safety confidence
    set_id: str | None = None
    clip_id: str | None = None
    model_version: str | None = None
    exercise_detail: str | None = None  # specific id when `exercise` is "other" (contract v1 has 3 ids); ignored by v1 readers
    schema_version: int = 1

    @property
    def time_base(self) -> str:
        return "capture_monotonic" if self.source == "live" else "video_pts"

    def to_dict(self) -> dict:
        return {**asdict(self), "time_base": self.time_base}
