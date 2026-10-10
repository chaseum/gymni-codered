"""The integration adapter: one pose per frame in, one contract Observation out.

    analyzer = Analyzer("curl", session_id="demo", source="live")
    result = analyzer.analyze_frame(pose, timestamp_ms)   # result.observation -> backend

It never decides what to say: it reports tracking, phase, one-time completed reps, measurements
and (reviewed or model-labelled) issue codes with evidence. Cue text and audio belong to the backend.
"""
import time
from collections import deque
from dataclasses import dataclass, field, replace

import numpy as np

from .artifacts import Artifact
from .config import Config
from .features import SIDES, frame_features, to_matrix, view_of
from .form import Assessment, review_rep
from .pose import Pose
from .recognition import Recognizer
from .reps import RepCounter
from .types import CompletedRep, Issue, Observation

FORM_MODEL_MIN_PROBABILITY = 0.7


@dataclass
class FrameResult:
    observation: Observation
    features: dict[str, float]
    side: str | None
    view: str
    local_rep_count: int  # debug display only; the backend's count is authoritative
    candidates: list[Assessment] = field(default_factory=list)  # every assessment of a just-finished rep


class Analyzer:
    def __init__(self, exercise: str, session_id: str, source: str = "live", *, clip_id: str | None = None,
                 set_id: str | None = None, variation: str | None = None, config: Config | None = None,
                 recognizer: Recognizer | None = None, form_model: Artifact | None = None,
                 rep_index_start: int | None = None):
        self.config = config or Config()
        self.exercise = exercise
        self.exercise_cfg = self.config.exercises[exercise]
        if variation:
            self.exercise_cfg = replace(self.exercise_cfg, variation=variation)
        self.session_id, self.set_id = session_id, set_id
        self.recognizer, self.form_model = recognizer, form_model
        self.source, self.clip_id = source, clip_id
        # rep_index must never repeat within a backend session, even if this process restarts.
        # ponytail: half-second wall-clock base; a new run starts above any index an earlier run could reach
        # (reps take >= min_rep_ms > 500 ms). Replace with an index handed out by the backend if that changes.
        self._rep_index = rep_index_start if rep_index_start is not None else int(time.time() * 2)
        self._run_id = f"ml{int(time.time() * 1000)}"
        self._seq = 0
        self.local_rep_count = 0
        alternating = exercise == "curl" and "alternating" in self.exercise_cfg.variation
        self._counters = {s: RepCounter(self.exercise_cfg.rep) for s in (SIDES if alternating else ("tracked",))}
        self._trace: deque[tuple[float, dict]] = deque()
        self._side: str | None = None

    def reset(self, source: str | None = None, clip_id: str | None = None) -> None:
        """Call on pause/resume, replay and source switch. Discards any half-finished rep; rep_index keeps rising."""
        for counter in self._counters.values():
            counter.reset()
        self._trace.clear()
        self._side = None
        if self.recognizer:
            self.recognizer.reset()
        if source:
            self.source, self.clip_id = source, clip_id

    def analyze_frame(self, pose: Pose | None, timestamp_ms: float) -> FrameResult:
        features = frame_features(pose)
        view = view_of(features, self.config.side_view_max_ratio, self.config.front_view_min_ratio)
        self._side = self._choose_side(pose)
        status = {s: self._tracking(pose, s) for s in SIDES}
        tracking = status[self._side] if self._side else "lost"
        self._remember(timestamp_ms, features)

        exercise, confidence = (self.recognizer.update(timestamp_ms, features) if self.recognizer
                                else (self.exercise, None))
        measurements = self._live_measurements(features)
        completed, issues, candidates = None, [], []
        for key, counter in self._counters.items():
            side = self._side if key == "tracked" else key
            ready = side is not None and status[side] == "ready"
            cycle = counter.update(features[self._signal_name(side)] if ready else None, timestamp_ms)
            if cycle and completed is None:
                completed, issues, candidates = self._complete_rep(cycle, side, view, measurements)

        phase = self._phase()
        obs = Observation(
            observation_id=f"{self._run_id}-{self._seq}", session_id=self.session_id, set_id=self.set_id,
            source=self.source, clip_id=self.clip_id, source_timestamp_ms=round(timestamp_ms, 1),
            exercise=exercise, exercise_confidence=confidence, tracking_status=tracking, phase=phase,
            completed_rep=completed, measurement_basis=self.exercise_cfg.basis, measurements=measurements,
            issues=issues, inference_provenance="trained_model" if self.recognizer or self.form_model else "reviewed_rules",
            model_version=self._model_versions())
        self._seq += 1
        return FrameResult(obs, features, self._side, view, self.local_rep_count, candidates)

    def _complete_rep(self, cycle, side: str, view: str, measurements: dict):
        """Assign the next rep_index, review the rep's frames, and keep only reviewed or model-labelled issues."""
        self._rep_index += 1
        self.local_rep_count += 1
        trace = [(t, f) for t, f in self._trace if cycle.start_ms <= t <= cycle.end_ms]
        review = review_rep(self.exercise, self.exercise_cfg, trace, side, view)
        measurements.update(review.measurements)
        issues = [Issue(a.code, {**a.evidence, "provenance": "reviewed_rules"}) for a in review.assessments
                  if a.status == "issue" and a.code in self.exercise_cfg.reviewed]
        if self.form_model:
            issues += self._form_model_issues(trace, measurements)
        return CompletedRep(self._rep_index, round(cycle.duration_ms)), issues, review.assessments

    # --- helpers --------------------------------------------------------------------------------
    def _required(self, side: str) -> list[str]:
        return [f"{side}_{j}" for j in self.exercise_cfg.required]

    def _visibility(self, pose: Pose, side: str) -> float:
        return min(pose.visibility(n) for n in self._required(side))

    def _tracking(self, pose: Pose | None, side: str) -> str:
        if pose is None:
            return "lost"
        if not all(pose.in_frame(n) for n in self._required(side)):
            return "unassessable"  # joint outside the frame: reframe the camera
        return "ready" if self._visibility(pose, side) >= self.config.min_visibility else "low_visibility"

    def _choose_side(self, pose: Pose | None) -> str | None:
        """Track the more visible side, switching only on a clear margin so the angle doesn't flicker."""
        if pose is None:
            return self._side
        vis = {s: self._visibility(pose, s) for s in SIDES}
        best = max(vis, key=vis.get)
        if self._side is None or vis[best] > vis[self._side] + self.config.side_switch_margin:
            return best
        return self._side

    def _signal_name(self, side: str) -> str:
        suffix = "_3d" if self.exercise_cfg.basis == "world_3d" else ""
        return f"{side}_{self.exercise_cfg.rep.signal}_angle{suffix}_deg"

    def _live_measurements(self, features: dict) -> dict[str, float | None]:
        if not self._side:
            return {}
        suffix = "_3d" if self.exercise_cfg.basis == "world_3d" else ""
        names = {f"{a}_angle_deg": f"{self._side}_{a}_angle{suffix}_deg" for a in ("elbow", "knee", "hip")}
        names |= {"upper_arm_drift_deg": f"{self._side}_upper_arm_drift_deg", "trunk_lean_deg": "trunk_lean_deg"}
        return {k: _rounded(features[v]) for k, v in names.items()}

    def _remember(self, t_ms: float, features: dict) -> None:
        self._trace.append((t_ms, features))
        horizon = t_ms - self.exercise_cfg.rep.max_rep_ms - 1000
        while self._trace[0][0] < horizon:
            self._trace.popleft()

    def _phase(self) -> str:
        phases = [c.phase for c in self._counters.values()]
        moving = [p for p in phases if p not in ("unknown", self.exercise_cfg.rep.start_phase)]
        return moving[0] if moving else phases[0]

    def _form_model_issues(self, trace, measurements) -> list[Issue]:
        """Binary good/bad becomes a measurement only. A specific issue needs a model trained on that labelled error."""
        if len(trace) < 4:
            return []
        proba = self.form_model.predict_proba(to_matrix([f for _, f in trace]), np.array([t for t, _ in trace]))
        labels = self.form_model.labels
        for label, p in zip(labels, proba):
            measurements[f"form_model_p_{label}"] = round(float(p), 3)
        if self.form_model.meta["task"] != "form_issue":
            return []
        best = int(np.argmax(proba))
        if labels[best] == "none" or proba[best] < FORM_MODEL_MIN_PROBABILITY:
            return []
        return [Issue(f"{self.exercise}.{labels[best]}", {"probability": round(float(proba[best]), 3),
                                                          "provenance": "trained_model",
                                                          "model_version": self.form_model.version})]

    def _model_versions(self) -> str | None:
        versions = [m.version for m in (self.recognizer and self.recognizer.artifact, self.form_model) if m]
        return "+".join(versions) or None


def _rounded(v: float) -> float | None:
    return None if v != v else round(v, 1)  # NaN -> None
