"""Per-frame pose features and the window aggregation shared by training and live inference.

2D angles use pixel coordinates (x*width, y*height) so they are not skewed by the frame aspect ratio.
"_3d" angles use MediaPipe's *estimated* world landmarks. Neither is a clinical measurement, and
33 coarse landmarks cannot measure spinal curvature, so no spine feature exists.
"""
import math
import warnings

import numpy as np

from .pose import INDEX, Pose

SIDES = ("left", "right")
ANGLES = {"elbow": ("shoulder", "elbow", "wrist"), "knee": ("hip", "knee", "ankle"), "hip": ("shoulder", "hip", "knee")}
COORD_JOINTS = ("shoulder", "elbow", "wrist", "hip", "knee", "ankle")

FEATURE_NAMES = [
    *(f"{s}_{a}_angle{d}_deg" for s in SIDES for a in ANGLES for d in ("", "_3d")),
    *(f"{s}_upper_arm_drift_deg" for s in SIDES),
    "trunk_lean_deg", "shoulder_width_ratio", "hip_height", "shoulder_height",
    *(f"{s}_{j}_{axis}" for s in SIDES for j in COORD_JOINTS for axis in "xy"),
    *(f"{s}_{limb}_vis" for s in SIDES for limb in ("arm", "leg")),
]
AGG_STATS = ("mean", "std", "min", "max", "range", "speed")
AGG_NAMES = [f"{n}:{s}" for s in AGG_STATS for n in FEATURE_NAMES]


def angle(a: np.ndarray, b: np.ndarray, c: np.ndarray) -> float:
    """Angle at b in degrees between rays b->a and b->c."""
    return vector_angle(a - b, c - b)


def vector_angle(u: np.ndarray, v: np.ndarray) -> float:
    nu, nv = np.linalg.norm(u), np.linalg.norm(v)
    if nu < 1e-9 or nv < 1e-9:
        return math.nan
    return math.degrees(math.acos(float(np.clip(np.dot(u, v) / (nu * nv), -1.0, 1.0))))


def frame_features(pose: Pose | None) -> dict[str, float]:
    if pose is None:
        return dict.fromkeys(FEATURE_NAMES, math.nan)
    px = pose.image[:, :2] * (pose.width, pose.height)
    world = pose.world

    def p(side, joint):
        return px[INDEX[f"{side}_{joint}"]]

    def vis(side, joints):
        return float(np.nanmean([pose.visibility(f"{side}_{j}") for j in joints]))

    f: dict[str, float] = {}
    for s in SIDES:
        for name, (a, b, c) in ANGLES.items():
            ia, ib, ic = (INDEX[f"{s}_{j}"] for j in (a, b, c))
            f[f"{s}_{name}_angle_deg"] = angle(px[ia], px[ib], px[ic])
            f[f"{s}_{name}_angle_3d_deg"] = angle(world[ia], world[ib], world[ic]) if world is not None else math.nan
    for s in SIDES:
        f[f"{s}_upper_arm_drift_deg"] = vector_angle(p(s, "elbow") - p(s, "shoulder"), p(s, "hip") - p(s, "shoulder"))

    shoulder_mid = (p("left", "shoulder") + p("right", "shoulder")) / 2
    hip_mid = (p("left", "hip") + p("right", "hip")) / 2
    torso = float(np.linalg.norm(shoulder_mid - hip_mid))
    ok = torso > 1e-6
    f["trunk_lean_deg"] = vector_angle(shoulder_mid - hip_mid, np.array([0.0, -1.0]))  # 0 = upright (image y points down)
    f["shoulder_width_ratio"] = float(np.linalg.norm(p("left", "shoulder") - p("right", "shoulder"))) / torso if ok else math.nan
    f["hip_height"] = -hip_mid[1] / torso if ok else math.nan
    f["shoulder_height"] = -shoulder_mid[1] / torso if ok else math.nan
    for s in SIDES:
        for j in COORD_JOINTS:
            x, y = (p(s, j) - hip_mid) / torso if ok else (math.nan, math.nan)
            f[f"{s}_{j}_x"], f[f"{s}_{j}_y"] = float(x), float(y)
    for s in SIDES:
        f[f"{s}_arm_vis"] = vis(s, ANGLES["elbow"])
        f[f"{s}_leg_vis"] = vis(s, ANGLES["knee"])
    return f


def view_of(features: dict[str, float], side_max: float, front_min: float) -> str:
    r = features["shoulder_width_ratio"]
    if math.isnan(r):
        return "unknown"
    return "side" if r < side_max else "front" if r > front_min else "diagonal"


def to_matrix(frames: list[dict[str, float]]) -> np.ndarray:
    return np.array([[fr[n] for n in FEATURE_NAMES] for fr in frames], dtype=float).reshape(len(frames), len(FEATURE_NAMES))


def aggregate(matrix: np.ndarray, timestamps_ms: np.ndarray) -> np.ndarray:
    """(T, F) frame features -> one fixed-length vector (AGG_NAMES). NaN where a feature never tracked."""
    with np.errstate(all="ignore"), warnings.catch_warnings():
        warnings.simplefilter("ignore", RuntimeWarning)  # all-NaN column = joint never tracked; stays NaN
        mean, std = np.nanmean(matrix, 0), np.nanstd(matrix, 0)
        lo, hi = np.nanmin(matrix, 0), np.nanmax(matrix, 0)
        dt = np.diff(timestamps_ms)[:, None] / 1000.0
        speed = np.nanmean(np.abs(np.diff(matrix, axis=0)) / dt, 0) if len(matrix) > 1 else np.full(matrix.shape[1], np.nan)
    return np.concatenate([mean, std, lo, hi, hi - lo, speed])


def resample(matrix: np.ndarray, timestamps_ms: np.ndarray, steps: int) -> np.ndarray:
    """(T, F) -> (steps, F) on an even time grid, interpolating over untracked frames (0 if never tracked)."""
    grid = np.linspace(timestamps_ms[0], timestamps_ms[-1], steps)
    out = np.zeros((steps, matrix.shape[1]))
    for j in range(matrix.shape[1]):
        ok = ~np.isnan(matrix[:, j])
        if ok.any():
            out[:, j] = np.interp(grid, timestamps_ms[ok], matrix[ok, j])
    return out

