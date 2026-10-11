"""fitness-ml: live webcam / MP4 analysis, model download, count validation.

    fitness-ml download-model                       # pose_landmarker_lite.task -> ml/models/
    fitness-ml run --source live                    # all trained models from ml/models, exercise auto-detected
    fitness-ml run --source live --exercise curl    # start counting curls (keys 1-8 / a still work)
    fitness-ml run --source recorded --video clip.mp4 --exercise squat --post http://localhost:8000 --session demo
    fitness-ml validate --annotations demo/annotations.csv --out demo/validation.csv

Window keys: 1-8 pick exercise · a auto (recognizer) · p pause/resume · r replay (recorded) or reset (live)
             s switch live<->recorded (needs --video) · q quit
"""
import argparse
import json
import math
import os
import sys
import time
from pathlib import Path

from .analyzer import Analyzer
from .artifacts import Artifact, discover
from .config import EXERCISES, Config
from .live import ExerciseSelector, rep_verdict
from .pipeline import process
from .pose import VARIANTS, PoseEstimator, download_model, model_path
from .recognition import Recognizer
from .sources import CameraLost, list_cameras, open_source
from .transport import BackendPoster, JsonlWriter
from .types import CompletedRep, Observation
from .validate import ClipStats, append_rows, validate_clips


def main() -> int:
    args = _parser().parse_args()
    cfg = Config()
    if args.cmd == "download-model":
        print(download_model(cfg.models_dir, args.variant))
    elif args.cmd == "config":
        print(json.dumps(cfg, default=lambda o: getattr(o, "__dict__", str(o)), indent=2))
    elif args.cmd == "cameras":
        cameras = list_cameras()
        for index, description in cameras:
            print(f"--camera {index}: {description}")
        if not cameras:
            print("no camera delivered a frame (macOS: allow Camera access for your terminal app)")
    elif args.cmd == "sample":
        print(json.dumps(_sample(cfg).to_dict()))
    elif args.cmd == "validate":
        validate_clips(Path(args.annotations), Path(args.out), _pose_model(args.pose_model, cfg), cfg)
    else:
        if args.min_visibility is not None:
            cfg.min_visibility = args.min_visibility
        return Runner(args, cfg).run()
    return 0


class Runner:
    def __init__(self, args, cfg: Config):
        self.args, self.cfg = args, cfg
        self.kind = args.source
        self.model = _pose_model(args.pose_model, cfg)
        found_recognizer, form_dirs = (None, {}) if args.no_models else discover(cfg.models_dir)
        recognizer_dir = args.recognizer or found_recognizer
        if args.form_model:
            form_dirs[args.exercise] = Path(args.form_model)
        recognizer = None
        if recognizer_dir:
            artifact = Artifact(recognizer_dir)  # a threshold calibrated on validation beats the generic default
            recognizer = Recognizer(artifact, artifact.meta.get("window_ms", cfg.recognition_window_ms),
                                    cfg.recognition_stride_ms, artifact.meta.get("reject_below", cfg.reject_below))
        auto = args.exercise == "auto"
        if auto and recognizer is None:
            raise SystemExit("--exercise auto needs a trained recognizer in ml/models (or pass --exercise curl etc.)")
        first = "curl" if auto else args.exercise
        self.analyzer = Analyzer(first, args.session, args.source, set_id=args.set_id, variation=args.variation,
                                 config=cfg, recognizer=recognizer)
        self.selector = ExerciseSelector(self.analyzer, form_dirs, auto)
        self.selector.choose(first)
        self.verdict, self.verdict_detail = None, []
        print(f"recognizer: {recognizer_dir.name if recognizer_dir else 'none'}; form models: "
              f"{', '.join(sorted(form_dirs)) or 'none'}; mode: {'auto' if auto else 'manual'}")
        self.observations = JsonlWriter(args.observations) if args.observations else None
        self.debug_log = JsonlWriter(args.debug_log) if args.debug_log else None
        self.poster = BackendPoster(args.post, args.session, os.environ.get("GYMAI_TOKEN")) if args.post else None
        self.stats = ClipStats()
        self.window = not args.no_window
        self.frames_seen = 0
        self.last_event: str | None = None
        self.recorder = Recorder(args.record) if args.record else None

    def run(self) -> int:
        try:
            while True:
                source = open_source(self.kind, self.args.video, self.args.camera)
                self.analyzer.reset(source=source.source, clip_id=source.clip_id)
                action = self._play(source)
                if action == "quit" or (action == "ended" and not self.args.loop):
                    break
                if action == "switch":
                    self.kind = "recorded" if self.kind == "live" else "live"
        except KeyboardInterrupt:
            pass
        except CameraLost as e:
            print(f"\nSTOPPED: {e}", file=sys.stderr)
            return 1
        finally:
            self._close()
        return 0

    def _play(self, source) -> str:
        """One pass over one source with its own landmarker (VIDEO-mode timestamps restart per source)."""
        fps, last = 0.0, time.perf_counter()
        wall_start = time.perf_counter()
        with PoseEstimator(self.model) as estimator:
            for frame in source.frames():
                if self.args.max_frames and self.frames_seen >= self.args.max_frames:
                    return "quit"
                step = process(frame, estimator, self.analyzer)
                switched = self.selector.on_frame(frame.timestamp_ms, step.result.observation.completed_rep is not None)
                if switched:
                    self._event(switched, frame.timestamp_ms)
                self.frames_seen += 1
                now = time.perf_counter()
                instant = 1 / max(now - last, 1e-6)
                fps, last = (0.9 * fps + 0.1 * instant) if fps else instant, now
                self._emit(step)
                if self.args.realtime and source.source == "recorded":
                    time.sleep(max(0.0, frame.timestamp_ms / 1000 - (now - wall_start)))
                if self.window:
                    action = self._key_action(self._show(self._overlay(step, fps, paused=False)))
                    if action == "pause":
                        action = self._wait_while_paused(step, fps)
                    if action:
                        return action
        return "ended"

    def _overlay(self, step, fps: float, paused: bool):
        from .debug import Hud, draw
        a = self.analyzer
        rec = a.recognizer
        warning = ("Baseline may include faults: deadlift faults are judged relative to it. Press r and redo "
                   "3 clean reps." if a.baseline_rejections.get(a.exercise, 0) >= 2 else None)
        hud = Hud(exercise=a.exercise, exercises=list(EXERCISES), counts=a.rep_counts, rep=a.exercise_cfg.rep,
                  auto=self.selector.auto, sees=(rec.label, rec.confidence) if rec else None,
                  last_event=self.last_event, verdict=self.verdict, verdict_detail=self.verdict_detail,
                  model_note=self.selector.model_note(a.exercise), warning=warning, paused=paused)
        return draw(step.frame.image, step, fps, hud)

    def _wait_while_paused(self, step, fps: float) -> str | None:
        """Freeze on the current frame. Resuming discards any half-done rep so it can't complete after the pause."""
        while True:
            key = self._show(self._overlay(step, fps, paused=True), wait_ms=50)
            if key == ord("p"):
                self.analyzer.reset()
                return None
            action = self._key_action(key)
            if action not in (None, "pause"):
                return action

    def _emit(self, step) -> None:
        obs = step.result.observation
        self.stats.add(step)
        if self.recorder and step.result.observation.source == "live":
            self.recorder.write(step.frame)
        for event in step.result.events:
            self._event(event, obs.source_timestamp_ms)
        if obs.completed_rep or any(e.startswith(("form calibration", "baseline rep refused")) for e in step.result.events):
            self.verdict, self.verdict_detail = rep_verdict(step.result, self.analyzer.form_model)
        if self.observations:
            self.observations.write(obs.to_dict())
        if self.poster:
            self.poster.send(obs)
        if self.debug_log:
            self.debug_log.write(_json_safe({
                "observation_id": obs.observation_id, "t_ms": obs.source_timestamp_ms, "frame": step.frame.index,
                "tracking": obs.tracking_status, "phase": obs.phase, "side": step.result.side, "view": step.result.view,
                "local_reps": step.result.local_rep_count, "latency_ms": round(step.latency_ms, 1),
                "signal_deg": step.result.signal_deg, "events": step.result.events,
                "candidates": [vars(a) for a in step.result.candidates], "features": step.result.features}))
        if obs.completed_rep:
            print(f"          {self.analyzer.exercise} {self.verdict[0]}"
                  + "".join(f" | {d}" for d in self.verdict_detail))

    def _event(self, text: str, t_ms: float) -> None:
        self.last_event = text
        print(f"[{t_ms / 1000:7.1f}s] {text}")

    def _show(self, image, wait_ms: int = 1) -> int:
        import cv2
        cv2.imshow("Gym&AI vision (debug)", image)
        return cv2.waitKey(wait_ms) & 0xFF

    def _key_action(self, key: int) -> str | None:
        exercises = list(EXERCISES)
        if ord("1") <= key < ord("1") + len(exercises):
            self.selector.auto = False
            self.last_event = self.selector.choose(exercises[key - ord("1")])
            self.verdict, self.verdict_detail = None, []
        if key == ord("a") and self.analyzer.recognizer:
            self.selector.auto = True
            self.last_event = "auto: following the recognizer"
        if key == ord("q"):
            return "quit"
        if key == ord("p"):
            return "pause"
        if key == ord("r"):
            if self.kind == "recorded":
                return "replay"
            self.analyzer.reset()
        if key == ord("s") and self.args.video:
            return "switch"
        return None

    def _close(self) -> None:
        if self.recorder:
            print(f"recorded {self.recorder.close()} (replay: --source recorded --video {self.args.record})")
        for out in (self.observations, self.debug_log):
            if out:
                out.close()
        if self.poster:
            self.poster.close()
            if self.poster.dropped or self.poster.last_error:
                print(f"backend: dropped {self.poster.dropped} frames, last error: {self.poster.last_error}", file=sys.stderr)
        if self.window:
            import cv2
            cv2.destroyAllWindows()
        row = self.stats.row(self.args.video or f"camera{self.args.camera}", self.args.exercise,
                             self.analyzer.exercise_cfg.variation, self.kind, self.args.actual_reps)
        print(json.dumps(row))
        if self.args.summary_csv:
            append_rows(Path(self.args.summary_csv), [row])


class Recorder:
    """Saves live frames plus their true capture times (<name>.timestamps.csv), so a webcam session can be
    replayed through `--source recorded` with identical timing to tune thresholds offline."""

    def __init__(self, path: str):
        self.path = Path(path)
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self._writer = None
        self._times = open(self.path.with_suffix(".timestamps.csv"), "w")
        self._times.write("frame,timestamp_ms\n")

    def write(self, frame) -> None:
        import cv2
        if self._writer is None:
            h, w = frame.image.shape[:2]
            self._writer = cv2.VideoWriter(str(self.path), cv2.VideoWriter_fourcc(*"mp4v"), 30, (w, h))
        self._writer.write(frame.image)
        self._times.write(f"{frame.index},{frame.timestamp_ms:.1f}\n")

    def close(self) -> Path:
        if self._writer:
            self._writer.release()
        self._times.close()
        return self.path


def _pose_model(value: str, cfg: Config) -> Path:
    return model_path(cfg.models_dir, value) if value in VARIANTS else Path(value)


def _json_safe(value):
    if isinstance(value, float):
        return None if math.isnan(value) or math.isinf(value) else value
    if isinstance(value, dict):
        return {k: _json_safe(v) for k, v in value.items()}
    if isinstance(value, list):
        return [_json_safe(v) for v in value]
    return value


def _sample(cfg: Config) -> Observation:
    return Observation(observation_id="ml-sample-1", session_id=cfg.session_id, source="live",
                       source_timestamp_ms=2850, exercise="curl", tracking_status="ready", phase="lowered",
                       inference_provenance="fixture", completed_rep=CompletedRep(1, 1850),
                       measurements={"elbow_angle_deg": 158.0})


def _parser() -> argparse.ArgumentParser:
    ap = argparse.ArgumentParser(prog="fitness-ml", description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    dl = sub.add_parser("download-model", help="fetch the official MediaPipe pose model")
    dl.add_argument("--variant", choices=VARIANTS, default="lite")
    sub.add_parser("config", help="print effective configuration")
    sub.add_parser("cameras", help="list cameras with index and resolution (pick one with run --camera N)")
    sub.add_parser("sample", help="print one contract-shaped observation (provenance=fixture)")

    run = sub.add_parser("run", help="analyze webcam or MP4")
    run.add_argument("--source", choices=["live", "recorded"], required=True)
    run.add_argument("--video", help="MP4 path (required for recorded; enables 's' source switch for live)")
    run.add_argument("--camera", type=int, default=Config().camera_index)
    run.add_argument("--exercise", choices=[*EXERCISES, "auto"], default="auto",
                     help="exercise to count; auto = follow the trained recognizer (default)")
    run.add_argument("--variation", help="e.g. standing_dumbbell_alternating, bodyweight, goblet, conventional")
    run.add_argument("--session", default=Config().session_id)
    run.add_argument("--set-id")
    run.add_argument("--pose-model", default="lite", help="lite|full|heavy or a .task path")
    run.add_argument("--observations", help="append contract observations (JSONL)")
    run.add_argument("--debug-log", help="append per-frame features/checks (JSONL, not a contract)")
    run.add_argument("--post", nargs="?", const=Config().backend_url, help="POST observations to the backend")
    run.add_argument("--recognizer", help="recognition artifact dir (default: newest in ml/models)")
    run.add_argument("--form-model", help="form artifact dir for --exercise (default: newest per exercise in ml/models)")
    run.add_argument("--no-models", action="store_true", help="rules only: no recognizer, no form models")
    run.add_argument("--no-window", action="store_true")
    run.add_argument("--realtime", action="store_true", help="pace recorded video at its own speed")
    run.add_argument("--loop", action="store_true", help="replay recorded video when it ends")
    run.add_argument("--max-frames", type=int)
    run.add_argument("--record", help="save the live camera to this .mp4 (+ .timestamps.csv) for offline replay")
    run.add_argument("--min-visibility", type=float, help=f"joint visibility needed to count (default {Config().min_visibility})")
    run.add_argument("--summary-csv", help="append a validation row at exit")
    run.add_argument("--actual-reps", type=int, help="human-annotated count for --summary-csv")

    val = sub.add_parser("validate", help="run annotated clips and write the count-validation CSV")
    val.add_argument("--annotations", required=True, help="CSV: path,exercise,actual_reps[,variation,notes]")
    val.add_argument("--out", required=True)
    val.add_argument("--pose-model", default="lite")
    return ap


if __name__ == "__main__":
    sys.exit(main())
