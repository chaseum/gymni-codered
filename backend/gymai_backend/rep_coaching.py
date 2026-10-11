"""Choose factual, short cues from committed reps without a language model."""

import json
from pathlib import Path
from statistics import median

POLICY = json.loads((Path(__file__).resolve().parents[2] / "contracts/coaching_policy.json").read_text())


def count_text(count: int, target: int | None) -> str | None:
    # Exact milestones only: never announce a target that was not counted.
    if target and count == target:
        key = "count_target"
    elif target and target >= 4 and count == target - 2:
        key = "count_near_target"
    elif target and target >= 4 and target % 2 == 0 and count == target // 2:
        key = "count_halfway"
    elif count == 1:
        key = "count_first"
    elif not target and count % 5 == 0:
        key = "count_open"
    else:
        return None
    return POLICY[key].format(count=count)


class RepCoach:
    def __init__(self):
        self.last_cue_ms = None
        self.reset_timing()

    def reset_timing(self):
        """A pause, lost view, or changed input breaks the timing baseline."""
        self.opening = []
        self.baseline_ms = None
        self.direction, self.streak = None, 0
        self.stream = None
        self.last_timestamp_ms = None

    def select(self, obs: dict, count: int, target: int | None, has_issues: bool, clock_ms: float):
        stream = (obs["source"], obs.get("clip_id"), obs["time_base"])
        stamp = obs["source_timestamp_ms"]
        if stream != self.stream or (self.last_timestamp_ms is not None and stamp <= self.last_timestamp_ms):
            self.reset_timing()
        self.stream, self.last_timestamp_ms = stream, stamp
        duration = obs["completed_rep"].get("duration_ms")
        direction = None
        if has_issues or duration is None or duration <= 0:
            self.direction, self.streak = None, 0
        elif self.baseline_ms is None:
            self.opening.append(duration)
            if len(self.opening) == POLICY["baseline_reps"]:
                self.baseline_ms = median(self.opening)
        else:
            ratio = duration / self.baseline_ms
            direction = "fast" if ratio < POLICY["fast_ratio"] else "slow" if ratio > POLICY["slow_ratio"] else None
            self.streak = self.streak + 1 if direction and direction == self.direction else int(direction is not None)
            self.direction = direction

        # Corrections take priority. No cue claims that unreported form is necessarily good.
        if has_issues:
            return None
        if self.last_cue_ms is not None and clock_ms - self.last_cue_ms < POLICY["cue_cooldown_ms"]:
            return None
        if direction and self.streak >= POLICY["consecutive_pace_reps"]:
            cue = {"kind": f"pace_{direction}", "text": POLICY[f"pace_{direction}"]}
            self.streak = 0
        else:
            text = count_text(count, target)
            if not text:
                return None
            cue = {"kind": "count", "text": text}
        self.last_cue_ms = clock_ms
        return cue
