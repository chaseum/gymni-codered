"""fitness-ml: live webcam / MP4 analysis, model download, count validation.

    fitness-ml download-model                       # pose_landmarker_lite.task -> ml/models/
    fitness-ml run --source live --exercise curl --observations demo/logs/live.jsonl
    fitness-ml run --source recorded --video clip.mp4 --exercise squat --post http://localhost:8000 --session demo
    fitness-ml validate --annotations demo/annotations.csv --out demo/validation.csv

Window keys: q quit · p pause/resume · r replay (recorded) or reset (live) · s switch live<->recorded (needs --video)
"""
import argparse
import json
import math
import os
import sys
import time
from pathlib import Path

from .analyzer import Analyzer
from .artifacts import Artifact
from .config import Config
from .pipeline import process
from .pose import VARIANTS, PoseEstimator, download_model, model_path
from .recognition import Recognizer
from .sources import open_source
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
    elif args.cmd == "sample":
        print(json.dumps(_sample(cfg).to_dict()))
    elif args.cmd == "validate":
        validate_clips(Path(args.annotations), Path(args.out), _pose_model(args.pose_model, cfg), cfg)
    else:
        return Runner(args, cfg).run()
    return 0


class Runner:
    def __init__(self, args, cfg: Config):
        self.args, self.cfg = args, cfg
        self.kind = args.source
        self.model = _pose_model(args.pose_model, cfg)
        recognizer = (Recognizer(Artifact(args.recognizer), cfg.recognition_window_ms, cfg.recognition_stride_ms,
                                 cfg.reject_below) if args.recognizer else None)
        self.analyzer = Analyzer(args.exercise, args.session, args.source, set_id=args.set_id, variation=args.variation,
                                 config=cfg, recognizer=recognizer,
                                 form_model=Artifact(args.form_model) if args.form_model else None)
        self.observations = JsonlWriter(args.observations) if args.observations else None
        self.debug_log = JsonlWriter(args.debug_log) if args.debug_log else None
        self.poster = BackendPoster(args.post, args.session, os.environ.get("GYMAI_TOKEN")) if args.post else None
        self.stats = ClipStats()
        self.window = not args.no_window
        self.frames_seen = 0

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
        from .debug import draw
        return draw(step.frame.image, step, fps, list(self.analyzer.exercise_cfg.required), paused)

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
        if self.observations:
            self.observations.write(obs.to_dict())
        if self.poster:
            self.poster.send(obs)
        if self.debug_log:
            self.debug_log.write(_json_safe({
                "observation_id": obs.observation_id, "t_ms": obs.source_timestamp_ms, "frame": step.frame.index,
                "tracking": obs.tracking_status, "phase": obs.phase, "side": step.result.side, "view": step.result.view,
                "local_reps": step.result.local_rep_count, "latency_ms": round(step.latency_ms, 1),
                "candidates": [vars(a) for a in step.result.candidates], "features": step.result.features}))
        if obs.completed_rep:
            print(f"rep {step.result.local_rep_count} ({obs.completed_rep.duration_ms} ms) "
                  f"checks: {[(a.code, a.status) for a in step.result.candidates]}")

    def _show(self, image, wait_ms: int = 1) -> int:
        import cv2
        cv2.imshow("Gym&AI vision (debug)", image)
        return cv2.waitKey(wait_ms) & 0xFF

    def _key_action(self, key: int) -> str | None:
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
    sub.add_parser("sample", help="print one contract-shaped observation (provenance=fixture)")

    run = sub.add_parser("run", help="analyze webcam or MP4")
    run.add_argument("--source", choices=["live", "recorded"], required=True)
    run.add_argument("--video", help="MP4 path (required for recorded; enables 's' source switch for live)")
    run.add_argument("--camera", type=int, default=Config().camera_index)
    run.add_argument("--exercise", choices=["curl", "squat", "deadlift"], required=True, help="planned exercise")
    run.add_argument("--variation", help="e.g. standing_dumbbell_alternating, bodyweight, goblet, conventional")
    run.add_argument("--session", default=Config().session_id)
    run.add_argument("--set-id")
    run.add_argument("--pose-model", default="lite", help="lite|full|heavy or a .task path")
    run.add_argument("--observations", help="append contract observations (JSONL)")
    run.add_argument("--debug-log", help="append per-frame features/checks (JSONL, not a contract)")
    run.add_argument("--post", nargs="?", const=Config().backend_url, help="POST observations to the backend")
    run.add_argument("--recognizer", help="trained recognition artifact directory")
    run.add_argument("--form-model", help="trained form artifact directory for --exercise")
    run.add_argument("--no-window", action="store_true")
    run.add_argument("--realtime", action="store_true", help="pace recorded video at its own speed")
    run.add_argument("--loop", action="store_true", help="replay recorded video when it ends")
    run.add_argument("--max-frames", type=int)
    run.add_argument("--summary-csv", help="append a validation row at exit")
    run.add_argument("--actual-reps", type=int, help="human-annotated count for --summary-csv")

    val = sub.add_parser("validate", help="run annotated clips and write the count-validation CSV")
    val.add_argument("--annotations", required=True, help="CSV: path,exercise,actual_reps[,variation,notes]")
    val.add_argument("--out", required=True)
    val.add_argument("--pose-model", default="lite")
    return ap


if __name__ == "__main__":
    sys.exit(main())
