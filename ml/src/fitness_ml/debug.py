"""Debug overlay for the laptop window. Not part of the event transport."""
import cv2
import numpy as np

from .pipeline import Step
from .pose import CONNECTIONS

GREEN, AMBER, RED, WHITE = (80, 200, 120), (0, 190, 255), (60, 60, 230), (240, 240, 240)
STATUS_COLOR = {"ready": GREEN, "low_visibility": AMBER, "unassessable": AMBER, "lost": RED}
STATUS_HINT = {"low_visibility": "joints hidden - turn or step back", "unassessable": "joints out of frame - reframe",
               "lost": "no person detected"}


def draw(image: np.ndarray, step: Step, fps: float, required: list[str], paused: bool) -> np.ndarray:
    out = image.copy()
    obs = step.result.observation
    if step.pose is not None:
        _skeleton(out, step.pose)
    lines = [
        (f"{obs.source.upper()}  {obs.exercise}  reps(local) {step.result.local_rep_count}  phase {obs.phase}", WHITE),
        (f"tracking: {obs.tracking_status}  {STATUS_HINT.get(obs.tracking_status, '')}", STATUS_COLOR[obs.tracking_status]),
        (f"elbow {_fmt(obs.measurements.get('elbow_angle_deg'))}  knee {_fmt(obs.measurements.get('knee_angle_deg'))}"
         f"  hip {_fmt(obs.measurements.get('hip_angle_deg'))}  ({obs.measurement_basis})", WHITE),
        (f"view {step.result.view}  side {step.result.side}  {fps:.1f} fps  {step.latency_ms:.0f} ms/frame", WHITE),
    ]
    if step.pose is not None and step.result.side:
        vis = "  ".join(f"{j.split('_', 1)[1]} {step.pose.visibility(j):.2f}"
                        for j in (f"{step.result.side}_{r}" for r in required))
        lines.append((f"visibility: {vis}", WHITE))
    for a in step.result.candidates:
        lines.append((f"rep check {a.code}: {a.status} {a.evidence}", AMBER if a.status == "issue" else WHITE))
    if paused:
        lines.append(("PAUSED (p to resume)", AMBER))
    for i, (text, color) in enumerate(lines):
        y = 28 + 26 * i
        cv2.putText(out, text, (12, y), cv2.FONT_HERSHEY_SIMPLEX, 0.6, (0, 0, 0), 4, cv2.LINE_AA)
        cv2.putText(out, text, (12, y), cv2.FONT_HERSHEY_SIMPLEX, 0.6, color, 1, cv2.LINE_AA)
    return out


def _skeleton(image, pose):
    h, w = image.shape[:2]
    pts = [(int(x * w), int(y * h)) for x, y in pose.image[:, :2]]
    visible = pose.image[:, 3] >= 0.5
    for a, b in CONNECTIONS:
        cv2.line(image, pts[a], pts[b], GREEN if visible[a] and visible[b] else AMBER, 2, cv2.LINE_AA)
    for i, p in enumerate(pts):
        cv2.circle(image, p, 3, WHITE if visible[i] else RED, -1, cv2.LINE_AA)


def _fmt(v):
    return "--" if v is None else f"{v:.0f}"
