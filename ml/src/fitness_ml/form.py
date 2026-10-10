"""Per-rep form criteria. Each is one measurable rule with an issue code, evidence and a resolution:
the issue resolves when a later *assessed* rep passes the same rule.

Status "unassessable" means the camera view or tracking cannot support the rule; nothing is inferred.
Measurements that are not faults (curl upper-arm drift, trunk lean) are reported, never flagged.
"""
from dataclasses import dataclass, field

import numpy as np

from .config import ExerciseConfig


@dataclass
class Assessment:
    code: str
    status: str  # "ok" | "issue" | "unassessable"
    evidence: dict[str, float | str | None] = field(default_factory=dict)


@dataclass
class RepReview:
    assessments: list[Assessment]
    measurements: dict[str, float | None]


def review_rep(exercise: str, cfg: ExerciseConfig, trace: list[tuple[float, dict]], side: str, view: str) -> RepReview:
    return REVIEWERS[exercise](cfg, trace, side, view)


def _series(trace, name):
    return np.array([f[name] for _, f in trace], dtype=float)


def _nan_extreme(values: np.ndarray, fn) -> float | None:
    values = values[~np.isnan(values)]
    return round(float(fn(values)), 1) if values.size else None


def _curl(cfg, trace, side, view):
    suffix = "_3d" if cfg.basis == "world_3d" else ""
    min_elbow = _nan_extreme(_series(trace, f"{side}_elbow_angle{suffix}_deg"), np.min)
    drift = _nan_extreme(_series(trace, f"{side}_upper_arm_drift_deg"), np.max)
    limit = cfg.thresholds["full_flexion_max_deg"]
    if min_elbow is None:
        a = Assessment("curl.partial_range", "unassessable", {"reason": "elbow_not_tracked"})
    else:
        a = Assessment("curl.partial_range", "issue" if min_elbow > limit else "ok",
                       {"min_elbow_angle_deg": min_elbow, "threshold_deg": limit, "basis": cfg.basis})
    return RepReview([a], {"rep_min_elbow_angle_deg": min_elbow, "rep_max_upper_arm_drift_deg": drift})


def _squat(cfg, trace, side, view):
    min_knee = _nan_extreme(_series(trace, f"{side}_knee_angle_deg"), np.min)
    lean = _nan_extreme(_series(trace, "trunk_lean_deg"), np.max)
    limit = cfg.thresholds["depth_knee_max_deg"]
    if view != "side":  # 2D knee angle from the front is foreshortened: no depth claim
        a = Assessment("squat.shallow_depth", "unassessable", {"reason": "needs_side_view", "view": view})
    elif min_knee is None:
        a = Assessment("squat.shallow_depth", "unassessable", {"reason": "knee_not_tracked"})
    else:
        a = Assessment("squat.shallow_depth", "issue" if min_knee > limit else "ok",
                       {"min_knee_angle_deg": min_knee, "threshold_deg": limit, "variation": cfg.variation})
    return RepReview([a], {"rep_min_knee_angle_deg": min_knee, "rep_max_trunk_lean_deg": lean})


def _deadlift(cfg, trace, side, view):
    """Hips rising early: over the first part of the lift (bottom -> lockout), hip height increases
    much more than shoulder height, i.e. the torso tips forward instead of rising with the hips."""
    hip_angle = _series(trace, f"{side}_hip_angle_deg")
    lockout = _nan_extreme(hip_angle, np.max)
    code = "deadlift.hips_rise_early"
    if view != "side":
        return RepReview([Assessment(code, "unassessable", {"reason": "needs_side_view", "view": view})],
                         {"rep_max_hip_angle_deg": lockout})
    t = np.array([ts for ts, _ in trace])
    hips, shoulders = _series(trace, "hip_height"), _series(trace, "shoulder_height")
    ok = ~(np.isnan(hips) | np.isnan(shoulders) | np.isnan(hip_angle))
    if ok.sum() < 4:
        return RepReview([Assessment(code, "unassessable", {"reason": "hip_or_shoulder_not_tracked"})],
                         {"rep_max_hip_angle_deg": lockout})
    t, hips, shoulders, hip_angle = t[ok], hips[ok], shoulders[ok], hip_angle[ok]
    lockout_t = t[int(np.argmax(hip_angle))]
    early = t <= t[0] + cfg.thresholds["early_window_frac"] * (lockout_t - t[0])
    hip_rise = float(hips[early][-1] - hips[0])
    shoulder_rise = float(shoulders[early][-1] - shoulders[0])
    ratio = round(hip_rise / max(shoulder_rise, 1e-3), 2)
    is_issue = hip_rise >= cfg.thresholds["min_hip_rise"] and ratio >= cfg.thresholds["hip_shoulder_rise_ratio"]
    a = Assessment(code, "issue" if is_issue else "ok",
                   {"hip_rise_torso": round(hip_rise, 3), "shoulder_rise_torso": round(shoulder_rise, 3),
                    "rise_ratio": ratio, "threshold_ratio": cfg.thresholds["hip_shoulder_rise_ratio"]})
    return RepReview([a], {"rep_max_hip_angle_deg": lockout, "rep_hip_shoulder_rise_ratio": ratio})


REVIEWERS = {"curl": _curl, "squat": _squat, "deadlift": _deadlift}
