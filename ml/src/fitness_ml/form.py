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
    return REVIEWERS.get(exercise, _no_rules)(cfg, trace, side, view)


def _no_rules(cfg, trace, side, view):
    """Exercises without a reviewed rule: report the counting signal's range only."""
    name = f"{side}_{cfg.rep.signal}_angle{'_3d' if cfg.basis == 'world_3d' else ''}_deg" if cfg.rep.signal in ("elbow", "knee", "hip") else cfg.rep.signal
    values = _series(trace, name)
    return RepReview([], {"rep_min_signal_deg": _nan_extreme(values, np.min), "rep_max_signal_deg": _nan_extreme(values, np.max)})


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


def _check(code: str, value, is_issue: bool, evidence: dict) -> Assessment:
    if value is None:
        return Assessment(code, "unassessable", {"reason": "joint_not_tracked"})
    return Assessment(code, "issue" if is_issue else "ok", evidence)


def _range_rule(code: str, feature: str, extreme: str, limit_key: str, name: str, views: tuple = ()):
    """Range-of-motion rule: the rep's min (or max) of `feature` must pass a limit stricter than the rep counter's
    turn threshold. "min": flag when the smallest value stays above the limit; "max": when the largest stays below.
    `feature` may use {side} and {d} ("_3d" when the exercise counts on estimated 3D angles). `views`: the camera
    views where the measurement means something (empty = any)."""
    fn = np.min if extreme == "min" else np.max

    def review(cfg, trace, side, view):
        value = _nan_extreme(_series(trace, feature.format(side=side, d="_3d" if cfg.basis == "world_3d" else "")), fn)
        limit = cfg.thresholds[limit_key]
        if views and view not in views:
            a = Assessment(code, "unassessable", {"reason": f"needs_{'_or_'.join(views)}_view", "view": view})
        else:
            bad = value is not None and (value > limit if extreme == "min" else value < limit)
            a = _check(code, value, bad, {name: value, "threshold": limit, "basis": cfg.basis, "view": view})
        return [a], {f"rep_{name}": value}
    return review


def _push_up(cfg, trace, side, view):
    """Depth (min elbow angle) and body line: the hip's distance from the shoulder-ankle line, in torso lengths,
    median over the rep (+ = hips sag below the line, - = hips piked above it). Body line needs a side view."""
    assessments, measurements = _range_rule("push_up.shallow_depth", "{side}_elbow_angle{d}_deg", "min",
                                            "depth_elbow_max_deg", "min_elbow_angle_deg", ("side",))(cfg, trace, side, view)
    s = np.array([[f[f"{side}_{j}_{c}"] for j in ("shoulder", "hip", "ankle") for c in "xy"] for _, f in trace])
    sx, sy, hx, hy, ax, ay = s.T
    with np.errstate(all="ignore"):
        dev = hy - (sy + (hx - sx) * (ay - sy) / (ax - sx))  # image y points down: + = hip below the line
    dev = dev[np.isfinite(dev) & (np.abs(ax - sx) > 0.5)]  # shoulder-ankle must be roughly horizontal (plank)
    line = round(float(np.median(dev)), 3) if dev.size and view == "side" else None
    sag, pike = cfg.thresholds["hip_sag_max"], cfg.thresholds["hip_pike_max"]
    ev = {"hip_offset_torso": line, "sag_threshold": sag, "pike_threshold": -pike, "view": view}
    reason = {"reason": "needs_side_view_in_plank", "view": view}
    for code, bad in (("push_up.hips_sagging", line is not None and line > sag),
                      ("push_up.hips_piked", line is not None and line < -pike)):
        assessments.append(_check(code, line, bad, ev) if line is not None else Assessment(code, "unassessable", reason))
    return RepReview(assessments, {**measurements, "rep_hip_offset_torso": line})


def _rules(*reviews):
    """Combine range rules into one reviewer."""
    def review(cfg, trace, side, view):
        assessments, measurements = [], {}
        for r in reviews:
            a, m = r(cfg, trace, side, view)
            assessments += a
            measurements |= m
        return RepReview(assessments, measurements)
    return review


REVIEWERS = {
    "curl": _curl, "squat": _squat, "deadlift": _deadlift, "push_up": _push_up,
    "shoulder_press": _rules(_range_rule("shoulder_press.incomplete_lockout", "{side}_elbow_angle{d}_deg", "max",
                                         "lockout_elbow_min_deg", "max_elbow_angle_deg")),
    "triceps_extension": _rules(_range_rule("triceps_extension.incomplete_extension", "{side}_elbow_angle{d}_deg",
                                            "max", "extension_elbow_min_deg", "max_elbow_angle_deg")),
    "row": _rules(_range_rule("row.short_pull", "{side}_elbow_angle{d}_deg", "min", "pull_elbow_max_deg", "min_elbow_angle_deg")),
    "side_bend": _rules(_range_rule("side_bend.partial_range", "trunk_lean_deg", "max", "lean_min_deg", "max_trunk_lean_deg",
                                    ("front", "diagonal"))),
}
