"""Live testing helpers: which exercise is counted, and what to say about each rep's form."""
from pathlib import Path

from .analyzer import Analyzer, FrameResult
from .artifacts import Artifact, test_score
from .config import EXERCISES

RELIABLE_F1 = 0.65      # below this held-out macro-F1, a form model's verdict is labelled unreliable
SWITCH_HOLD_MS = 2000   # new exercise must be recognized continuously this long...
SWITCH_MIN_CONF = 0.7   # ...at at least this confidence...
SET_QUIET_MS = 5000     # ...and no rep counted this recently (changing exercise means a pause between sets),
OVERRIDE_HOLD_MS = 4000 # ...unless it has been recognized this long: then the old counter is misreading the new move


class ExerciseSelector:
    """Recognizer-driven (auto) or key-driven (manual).

    Auto switches between sets (new exercise held confidently for SWITCH_HOLD_MS, no rep for SET_QUIET_MS), or
    after OVERRIDE_HOLD_MS of steady recognition even if reps keep coming: going curls -> push-ups, the curl counter
    kept "counting curls" from push-up elbow bends, so the quiet-gap rule alone never fired. Reps counted after the
    recognizer started saying the new exercise are moved to it. (Short blips, like an 81% "push up" mid-curl-set
    seen on a real session, still can't switch.)"""

    def __init__(self, analyzer: Analyzer, form_dirs: dict[str, Path], auto: bool):
        self.analyzer, self.form_dirs = analyzer, form_dirs
        self.auto = auto and analyzer.recognizer is not None
        self.scores = {ex: test_score(d) for ex, d in form_dirs.items()}
        self._models: dict[str, Artifact] = {}
        self._candidate: str | None = None
        self._since_ms = 0.0
        self._last_rep_ms = -1e12
        self._rep_times: list[float] = []  # reps counted for the current exercise (to move on a late switch)

    def choose(self, exercise: str) -> str:
        self.analyzer.set_exercise(exercise, self._form_model(exercise))
        self._rep_times = []
        return f"now counting: {exercise.replace('_', ' ')}"

    def on_frame(self, t_ms: float, rep_completed: bool) -> str | None:
        if rep_completed:
            self._last_rep_ms = t_ms
            self._rep_times.append(t_ms)
        recognizer = self.analyzer.recognizer
        if not self.auto or recognizer is None:
            return None
        label, confident = recognizer.label, (recognizer.confidence or 0) >= SWITCH_MIN_CONF
        if label != self._candidate or not confident:
            self._candidate, self._since_ms = (label if confident else None), t_ms
            return None
        if label not in EXERCISES or label == self.analyzer.exercise:
            return None
        held_ms = t_ms - self._since_ms
        between_sets = t_ms - self._last_rep_ms >= SET_QUIET_MS and self.analyzer.idle
        if (held_ms >= SWITCH_HOLD_MS and between_sets) or held_ms >= OVERRIDE_HOLD_MS:
            return self._switch(label, recognizer.confidence)
        return None

    def _switch(self, new: str, confidence: float) -> str:
        old = self.analyzer.exercise
        misread = sum(1 for t in self._rep_times if t >= self._since_ms)
        message = self.choose(new) + f" (recognized {confidence:.0%})"
        if misread:
            self.analyzer.rep_counts[old] -= misread
            self.analyzer.rep_counts[new] += misread
            message += f"; moved {misread} rep{'s' * (misread > 1)} from {old.replace('_', ' ')}"
        return message

    def model_note(self, exercise: str) -> str | None:
        if exercise not in self.form_dirs:
            return "no form model for this exercise"
        score = self.scores.get(exercise)
        if score is None:
            return "form model not evaluated yet"
        relative = " - relative to your baseline" if self._form_model(exercise).calibration_reps else ""
        return f"form model test F1 {score:.2f}" + (" - UNRELIABLE" if score < RELIABLE_F1 else "") + relative

    def _form_model(self, exercise: str) -> Artifact | None:
        if exercise not in self.form_dirs:
            return None
        if exercise not in self._models:
            self._models[exercise] = Artifact(self.form_dirs[exercise])
        return self._models[exercise]


def rep_verdict(result: FrameResult, form_model: Artifact | None) -> tuple[tuple[str, str], list[str]]:
    """((headline, good|bad|neutral|pending), detail lines) for the rep that just completed."""
    obs = result.observation
    rep = f"rep {result.local_rep_count}"
    details = [f"{a.code.split('.', 1)[1].replace('_', ' ')}: {a.status}" + _evidence(a.evidence) for a in result.candidates]
    if obs.completed_rep and obs.completed_rep.duration_ms:
        details.append(f"duration {obs.completed_rep.duration_ms / 1000:.1f} s")
    for event in result.events:
        if event.startswith("baseline rep refused"):
            return (f"{rep}: baseline refused", "bad"), [event.split(": ", 1)[1]] + details
        if event.startswith("form calibration"):
            return (f"{rep}: {event.replace('form ', '')}", "pending"), details
    if obs.issues:
        worst = obs.issues[0]
        p = worst.evidence.get("probability")
        name = worst.code.split(".", 1)[1].replace("_", " ")
        return (f"{rep}: {name}" + (f" {p:.0%}" if isinstance(p, float) else ""), "bad"), details
    p_bad = obs.measurements.get("form_model_p_bad")
    if p_bad is not None:
        return ((f"{rep}: form looks BAD ({p_bad:.0%})", "bad") if p_bad >= 0.5
                else (f"{rep}: form looks good (bad {p_bad:.0%})", "good")), details
    if form_model is not None and form_model.meta.get("task") == "form_issue":
        return (f"{rep}: no fault detected", "good"), details
    return (f"{rep}: counted (no form model)", "neutral"), details


def _evidence(evidence: dict) -> str:
    numbers = [f"{k.replace('_deg', '').replace('_', ' ')} {v:.0f}" for k, v in evidence.items()
               if isinstance(v, float) and k.startswith(("min_", "max_"))]
    return f" ({', '.join(numbers)})" if numbers else ""
