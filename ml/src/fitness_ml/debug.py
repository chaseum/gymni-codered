"""Debug overlay for the laptop window. Not part of the event transport."""
import cv2
import numpy as np

from .config import RepConfig
from .pipeline import Step
from .pose import CONNECTIONS

GREEN, AMBER, RED, WHITE, GREY = (80, 200, 120), (0, 190, 255), (60, 60, 230), (240, 240, 240), (120, 120, 120)
STATUS_COLOR = {"ready": GREEN, "low_visibility": AMBER, "unassessable": AMBER, "lost": RED}
STATUS_HINT = {"ready": "tracking", "low_visibility": "arm hidden - turn toward camera / sleeves up",
               "unassessable": "joint out of frame - step back", "lost": "no person - step into frame"}
FONT = cv2.FONT_HERSHEY_SIMPLEX


def draw(image: np.ndarray, step: Step, fps: float, rep: RepConfig, last_event: str | None, paused: bool) -> np.ndarray:
    out = image.copy()
    h, w = out.shape[:2]
    obs = step.result.observation
    if step.pose is not None:
        _skeleton(out, step.pose)

    _text(out, str(step.result.local_rep_count), (w - 40 - 60 * len(str(step.result.local_rep_count)), 110), 3.5, WHITE, 8)
    _text(out, "reps", (w - 110, 140), 0.8, WHITE, 2)
    _text(out, f"{obs.exercise.upper()}  {obs.source.upper()}", (16, 36), 0.9, WHITE, 2)
    _text(out, STATUS_HINT[obs.tracking_status], (16, 70), 0.8, STATUS_COLOR[obs.tracking_status], 2)
    _text(out, f"phase: {obs.phase}", (16, 102), 0.7, WHITE, 2)
    _angle_bar(out, step.result.signal_deg, rep, (16, h - 90, min(w - 32, 520)))
    if last_event:
        _text(out, last_event, (16, h - 24), 0.7, GREEN if last_event.startswith("rep counted") else AMBER, 2)
    _text(out, f"{fps:.0f} fps  {step.latency_ms:.0f} ms  view {step.result.view}  arm {step.result.side}", (16, 132), 0.55, GREY, 1)
    if paused:
        _text(out, "PAUSED  (p to resume)", (w // 2 - 170, h // 2), 1.2, AMBER, 3)
    return out


def _angle_bar(image, angle: float | None, rep: RepConfig, box) -> None:
    """Horizontal gauge from the start threshold to the turn threshold (with 20° margin each side)."""
    x, y, width = box
    lo, hi = sorted((rep.start_deg, rep.turn_deg))
    lo, hi = lo - 20, hi + 20

    def px(deg):
        return int(x + (deg - lo) / (hi - lo) * width)

    cv2.rectangle(image, (x, y), (x + width, y + 18), GREY, 1)
    for deg, label in ((rep.start_deg, "start"), (rep.turn_deg, "turn")):
        cv2.line(image, (px(deg), y - 6), (px(deg), y + 24), WHITE, 2)
        _text(image, f"{label} {deg:.0f}", (px(deg) - 30, y - 10), 0.5, WHITE, 1)
    if angle is not None:
        cv2.rectangle(image, (x, y + 2), (px(float(np.clip(angle, lo, hi))), y + 16), GREEN, -1)
        _text(image, f"{rep.signal} {angle:.0f}", (x + width + 10, y + 16), 0.6, WHITE, 2)


def _skeleton(image, pose):
    h, w = image.shape[:2]
    pts = [(int(x * w), int(y * h)) for x, y in pose.image[:, :2]]
    visible = pose.image[:, 3] >= 0.4
    for a, b in CONNECTIONS:
        cv2.line(image, pts[a], pts[b], GREEN if visible[a] and visible[b] else AMBER, 2, cv2.LINE_AA)
    for i, p in enumerate(pts):
        cv2.circle(image, p, 3, WHITE if visible[i] else RED, -1, cv2.LINE_AA)


def _text(image, text, org, scale, color, thickness):
    cv2.putText(image, text, org, FONT, scale, (0, 0, 0), thickness + 3, cv2.LINE_AA)
    cv2.putText(image, text, org, FONT, scale, color, thickness, cv2.LINE_AA)
