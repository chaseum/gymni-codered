"""Laptop window for testing: skeleton, rep count per exercise, per-rep form verdict. Not the event transport."""
from dataclasses import dataclass, field

import cv2
import numpy as np

from .config import RepConfig
from .pipeline import Step
from .pose import CONNECTIONS

GREEN, AMBER, RED, WHITE, GREY = (80, 200, 120), (0, 190, 255), (70, 70, 235), (240, 240, 240), (150, 150, 150)
PANEL = (12, 12, 12)  # near-black so the text outline is invisible on the panel
STATUS_COLOR = {"ready": GREEN, "low_visibility": AMBER, "unassessable": AMBER, "lost": RED}
STATUS_HINT = {"ready": "tracking", "low_visibility": "arm/leg hidden - turn toward camera",
               "unassessable": "joint out of frame - step back", "lost": "no person - step into frame"}
VERDICT_COLOR = {"good": GREEN, "bad": RED, "neutral": WHITE, "pending": AMBER}
FONT = cv2.FONT_HERSHEY_SIMPLEX
PANEL_W = 330
VIEW_H = 720  # camera frame is scaled to this height so the layout reads the same at any resolution


@dataclass
class Hud:
    exercise: str
    exercises: list[str]
    counts: dict[str, int]
    rep: RepConfig
    auto: bool
    sees: tuple[str, float | None] | None = None       # recognizer's current guess
    last_event: str | None = None
    verdict: tuple[str, str] | None = None             # (text, good|bad|neutral|pending) for the last rep
    verdict_detail: list[str] = field(default_factory=list)
    model_note: str | None = None                      # "form model: test F1 0.56 - unreliable"
    warning: str | None = None
    paused: bool = False


def draw(image: np.ndarray, step: Step, fps: float, hud: Hud) -> np.ndarray:
    """Camera view on the left, a fixed-width panel on the right, so text never covers the person."""
    if image.shape[0] != VIEW_H:
        image = cv2.resize(image, (round(image.shape[1] * VIEW_H / image.shape[0]), VIEW_H))
    h, w = image.shape[:2]
    out = np.full((h, w + PANEL_W, 3), PANEL, np.uint8)
    out[:, :w] = image
    if step.pose is not None:
        _skeleton(out[:, :w], step.pose)
    obs = step.result.observation
    x0 = w + 16

    _text(out, hud.exercise.replace("_", " ").upper(), (x0, 40), 0.85, WHITE, 2)
    mode = "AUTO (recognizer)" if hud.auto else "MANUAL (keys 1-8)"
    _text(out, mode, (x0, 64), 0.5, GREY, 1)
    if hud.sees:
        label, conf = hud.sees
        _text(out, f"sees: {label.replace('_', ' ')}" + (f" {conf:.0%}" if conf is not None else ""), (x0, 86), 0.5, GREY, 1)
    count = str(hud.counts.get(hud.exercise, 0))
    _text(out, count, (x0, 190), 3.6, WHITE, 8)
    _text(out, "reps", (x0 + 8 + 62 * len(count), 190), 0.8, GREY, 2)

    y = 230
    if hud.verdict:
        text, kind = hud.verdict
        y = _wrap(out, text, (x0, y), 0.7, VERDICT_COLOR[kind], PANEL_W - 24, thickness=2, line_px=28) + 4
    for line in hud.verdict_detail[:3]:
        y = _wrap(out, line, (x0, y), 0.45, WHITE, PANEL_W - 24)
    if hud.model_note:
        y = _wrap(out, hud.model_note, (x0, y), 0.45, GREY, PANEL_W - 24)
    if hud.warning:
        _wrap(out, hud.warning, (x0, y + 6), 0.45, AMBER, PANEL_W - 24)

    y = h - 30 - 24 * len(hud.exercises)
    _text(out, "exercise", (x0, y - 8), 0.45, GREY, 1)
    _text(out, "reps", (x0 + 200, y - 8), 0.45, GREY, 1)
    for i, ex in enumerate(hud.exercises, 1):
        color, weight = (WHITE, 2) if ex == hud.exercise else (GREY, 1)
        _text(out, f"{i} {ex.replace('_', ' ')}", (x0, y + 22 * i), 0.5, color, weight)
        _text(out, str(hud.counts.get(ex, 0)), (x0 + 200, y + 22 * i), 0.5, color, weight)
    _text(out, "a auto  p pause  r reset  q quit", (x0, h - 8), 0.42, GREY, 1)

    _text(out, STATUS_HINT[obs.tracking_status], (16, 34), 0.8, STATUS_COLOR[obs.tracking_status], 2)
    _text(out, f"{obs.source.upper()}  {fps:.0f} fps  view {step.result.view}  phase {obs.phase}", (16, 60), 0.5, WHITE, 1)
    _angle_bar(out, step.result.signal_deg, hud.rep, (16, h - 70, min(w - 140, 460)))
    if hud.last_event:
        _text(out, hud.last_event, (16, h - 20), 0.6, GREEN if hud.last_event.startswith("rep counted") else AMBER, 2)
    if hud.paused:
        _text(out, "PAUSED  (p to resume)", (w // 2 - 170, h // 2), 1.2, AMBER, 3)
    return out


def _angle_bar(image, angle: float | None, rep: RepConfig, box) -> None:
    """Gauge across the start and turn thresholds (with margin), so you can see if a rep reaches both."""
    x, y, width = box
    lo, hi = sorted((rep.start_deg, rep.turn_deg))
    margin = max(10.0, (hi - lo) * 0.4)
    lo, hi = lo - margin, hi + margin

    def px(deg):
        return int(x + (deg - lo) / (hi - lo) * width)

    cv2.rectangle(image, (x, y), (x + width, y + 18), GREY, 1)
    for deg, label in ((rep.start_deg, "start"), (rep.turn_deg, "turn")):
        cv2.line(image, (px(deg), y - 6), (px(deg), y + 24), WHITE, 2)
        _text(image, f"{label} {deg:.0f}", (px(deg) - 30, y - 10), 0.5, WHITE, 1)
    if angle is not None:
        cv2.rectangle(image, (x, y + 2), (px(float(np.clip(angle, lo, hi))), y + 16), GREEN, -1)
        name = rep.signal.replace("_deg", "").replace("_", " ")
        _text(image, f"{name} {angle:.0f}", (x + width + 10, y + 16), 0.6, WHITE, 2)


def _skeleton(image, pose):
    h, w = image.shape[:2]
    pts = [(int(x * w), int(y * h)) for x, y in pose.image[:, :2]]
    visible = pose.image[:, 3] >= 0.4
    for a, b in CONNECTIONS:
        cv2.line(image, pts[a], pts[b], GREEN if visible[a] and visible[b] else AMBER, 2, cv2.LINE_AA)
    for i, p in enumerate(pts):
        cv2.circle(image, p, 3, WHITE if visible[i] else RED, -1, cv2.LINE_AA)


def _wrap(image, text, org, scale, color, width_px, thickness=1, line_px=20) -> int:
    """Word-wrapped text; returns the y just below the last line."""
    x, y = org
    line = ""
    for word in text.split():
        trial = f"{line} {word}".strip()
        if cv2.getTextSize(trial, FONT, scale, thickness)[0][0] > width_px and line:
            _text(image, line, (x, y), scale, color, thickness)
            y, line = y + line_px, word
        else:
            line = trial
    if line:
        _text(image, line, (x, y), scale, color, thickness)
    return y + line_px


def _text(image, text, org, scale, color, thickness):
    cv2.putText(image, text, org, FONT, scale, (0, 0, 0), thickness + 3, cv2.LINE_AA)
    cv2.putText(image, text, org, FONT, scale, color, thickness, cv2.LINE_AA)
