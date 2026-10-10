"""Hysteresis rep state machine shared by all exercises; RepConfig makes it curl, squat or deadlift.

waiting --signal in start region--> start --leaves by > hysteresis--> away --reaches turn--> turn
turn --backs off by > hysteresis--> back --reaches start--> start  (emits one Cycle)
away --returns to start without reaching turn--> start  (partial rep: nothing emitted)

"depth" = degrees travelled from the start threshold toward the turn threshold, so one code path
serves angles that shrink (curl, squat) and angles that grow (deadlift hip).
"""
import math
from dataclasses import dataclass

from .config import RepConfig

OPPOSITE = {"lowered": "raised", "raised": "lowered"}
MOVING = {("lowered", "away"): "raising", ("lowered", "back"): "lowering",
          ("raised", "away"): "lowering", ("raised", "back"): "raising"}


@dataclass(frozen=True)
class Cycle:
    start_ms: float
    end_ms: float
    extreme_deg: float  # smoothed signal at the deepest point of the rep

    @property
    def duration_ms(self) -> float:
        return self.end_ms - self.start_ms


class RepCounter:
    def __init__(self, cfg: RepConfig):
        self.cfg = cfg
        self._toward_smaller = cfg.turn_deg < cfg.start_deg
        self._span = abs(cfg.start_deg - cfg.turn_deg)
        self.reset()

    def reset(self) -> None:
        """Forget any rep in progress (pause, source switch, replay). Wait for the start position again."""
        self.state = "waiting"
        self._smoothed: float | None = None
        self._last_seen_ms: float | None = None
        self._left_start_ms = 0.0
        self._deepest = 0.0

    @property
    def phase(self) -> str:
        if self.state == "waiting":
            return "unknown"
        if self.state == "start":
            return self.cfg.start_phase
        if self.state == "turn":
            return OPPOSITE[self.cfg.start_phase]
        return MOVING[(self.cfg.start_phase, self.state)]

    def update(self, value: float | None, t_ms: float) -> Cycle | None:
        """Feed one frame (value None/NaN = joints not trackable). Returns a Cycle only on the completing frame."""
        if value is None or math.isnan(value):
            self._on_missing(t_ms)
            return None
        self._last_seen_ms = t_ms
        a = self.cfg.smoothing
        self._smoothed = value if self._smoothed is None else a * value + (1 - a) * self._smoothed
        depth = self._depth(self._smoothed)
        return self._step(depth, t_ms)

    def _step(self, depth: float, t_ms: float) -> Cycle | None:
        cfg = self.cfg
        if self.state == "waiting":
            if depth <= 0:
                self.state = "start"
            return None
        if self.state == "start":
            if depth > cfg.hysteresis_deg:
                self.state, self._left_start_ms, self._deepest = "away", t_ms, depth
            return None

        self._deepest = max(self._deepest, depth)
        if t_ms - self._left_start_ms > cfg.max_rep_ms:
            self.state = "waiting"
        elif self.state == "away":
            if depth >= self._span:
                self.state = "turn"
            elif depth <= 0:
                self.state = "start"
        elif self.state == "turn":
            if depth < self._span - cfg.hysteresis_deg:
                self.state = "back"
        elif self.state == "back":
            if depth >= self._span:
                self.state = "turn"
            elif depth <= 0:
                self.state = "start"
                cycle = Cycle(self._left_start_ms, t_ms, self._signal_at(self._deepest))
                if cycle.duration_ms >= cfg.min_rep_ms:
                    return cycle
        return None

    def _on_missing(self, t_ms: float) -> None:
        mid_rep = self.state in ("away", "turn", "back")
        if mid_rep and self._last_seen_ms is not None and t_ms - self._last_seen_ms > self.cfg.max_gap_ms:
            self.reset()

    def _depth(self, signal: float) -> float:
        d = self.cfg.start_deg - signal
        return d if self._toward_smaller else -d

    def _signal_at(self, depth: float) -> float:
        return self.cfg.start_deg - depth if self._toward_smaller else self.cfg.start_deg + depth
