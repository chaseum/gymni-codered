# Claude Code Prompt 02 — Pose Estimation, Rep Counting, ML Training, Vultr Readiness

You are Chase's ML engineer for **Gym&AI**. Use the existing `ml/` package and `contracts/` schemas. Read `docs/GYM_AND_AI_TEAM_BRIEF_REVISED.md` when present. **Do not modify Bryan's iOS app, Tyler's backend, or Taher's firmware.** Inspect code/status first; make a small implementation plan and build real runnable code, not pseudocode.

## Goal

Implement a complete camera/video -> MediaPipe -> normalized pose features -> exercise classification -> repetitions -> exercise-specific form assessment -> typed observation pipeline, with reproducible training locally or on a Vultr GPU. The required supported exercises are **standing dumbbell curl**, **squat (variation explicitly recorded)** and **conventional deadlift**. Webcam curls are the live demonstration; all three must analyze recorded footage as well. Pushups are optional; bench press is excluded.

## Phase A — Functional live pose system FIRST

1. Use the **current** MediaPipe Tasks Pose Landmarker (`mp.tasks.vision.PoseLandmarker`), not removed legacy APIs; OpenCV for webcam and MP4/video input. Installable Python package with pinned compatible versions (choose after verifying platform).
2. Download official `pose_landmarker_lite.task`, verify path/file; support optional Full model if available. Support CPU inference without cloud/GPU.
3. Start in synchronous `VIDEO` mode for both frame sources. Convert BGR->RGB; supply strictly increasing per-source **frame timestamps**. For recorded videos, use video presentation timestamps where valid and document fallback; for live use monotonic frame timestamps. Implement `LIVE_STREAM` async only if measured latency requires it.
4. Draw debug skeleton with MediaPipe landmark connections, live FPS/latency, required-joint visibility, and meaningful tracking-not-ready status. Preserve landmark `x/y/z`, confidence/visibility/presence when available; handle occlusion.
5. Export JSONL debug observations matching `contracts/` with source + session/set IDs. Keep camera/landmarker lifecycle safe on stop, pause, replay, and source switching.
6. Compute angle and motion features: 2D/estimated-world coordinates, body-centered normalized distances, hip/knee/elbow angles, velocities, range and rep timing. Avoid fake 'spinal curvature' from 33 coarse landmarks. Test features on known synthetic configurations and real clips.

**Stop gate A:** a local webcam shows skeleton and live elbow angle; a video file reuses same pipeline and outputs correct time-ordered observations.

## Phase B — Three actual exercise analyzers

1. A shared rep state machine framework with per-exercise configurations: initial phase, landmark requirements, minimum valid cycle, entry/exit hysteresis, elapsed-time minimum, confidence gating, and reset semantics.
2. `curl`: bottom -> ascending -> top -> descending -> bottom; elbow flexion and upper-arm drift are observations, not universal fault labels.
3. `squat`: standing -> descent -> bottom -> ascent -> standing; document bodyweight versus loaded variation; validate view before depth claims.
4. `deadlift`: bottom/setup -> lift -> lockout -> lower -> bottom; use side view; do not claim bar path, bracing, spinal safety or precise loading without proper evidence.
5. Use one `completed_rep` event emitted only when an eligible cycle finishes; no frame-by-frame increment. Support pause/resume, loss of required landmarks, low confidence, clipped reps, source switch/replay, and different filming angles.
6. First correction criterion for each exercise must be measurable and _reviewed_ on example clips (e.g. intended tempo vs observed tempo) with an issue code, evidence and resolution condition. If a criterion isn't supported by camera view, report `unassessable` instead of inventing a correction.
7. Produce a small validation CSV: exercise, variation, source, actual annotated reps, predicted reps, false counts, lost frames, observed issues, latency/FPS.

**Stop gate B:** live curl counting with real person and playback of recorded curl/squat/deadlift have actual counts and identifiable tracking failures.

## Phase C — Actual supervised ML (separate from heuristics)

Inspect original dataset structure, licensing, label definitions and subject IDs **before coding mapping**:

- MyDeadlift: https://data.mendeley.com/datasets/w5prmmxyt9/1
- Multi-View Fitness: https://data.mendeley.com/datasets/kgbb3yn47p/3

Build CLI for ingest -> landmark cache -> temporal feature extraction -> split -> baseline training -> evaluation. Input data paths are configurable; do NOT invent video files/labels or use fake training results. Store per-source dataset/video/participant/camera/exercise/variation/label metadata. Split by participant **before** forming windows so adjacent frames/reps/subjects never leak. Train and report:

- **Exercise recognition** on short pose-feature sequences: `curl`, `squat`, `deadlift`, `other`; unknown/reject prediction if unsupported or insufficient evidence; do not coerce all movement into 3 labels. Plan selection may bias expected exercise but cannot substitute for observation.
- **Form quality** separately per exercise where labels exist. Binary good/bad is **not** a diagnosis or specific fault classification. Specific issue predictions require matching labeled error types or reviewed measurements. Distinguish `model_prediction`, `reviewed_rule`, and `unknown` provenance.
- Baseline: scikit-learn Random Forest or k-NN on aggregated temporal features, with saved feature schema/normalization/label mapping. Report per-class support, macro-F1, confusion matrices, generalization across held-out people and camera views. Evaluate rejection thresholds and false-positive corrections.
- Optional comparator: small PyTorch 1D CNN or GRU consuming pose-feature windows, train CPU or CUDA with `--device auto|cpu|cuda`, reproducible seed, early stopping, checkpoint export and loadable CPU inference. Compare on **identical** held-out split; ship whichever demonstrates stronger valid results, not whichever sounds more sophisticated.

Add `ml/training/` tools for extraction, training and evaluation, CLI help and an examples README; no secret credentials or huge datasets in Git. Keep the training dependency group optional so CPU inference doesn't require a full CUDA environment.

## Phase D — Vultr training portability

Create `docs/VULTR_TRAINING.md` documenting, but **do not autonomously rent** any server:

- Claim/verify MLH sponsor credits, eligible hardware, quota, GPU price and remaining credit; list current pricing as unverified until checked by operator.
- Ubuntu Cloud GPU with access to SSH; `nvidia-smi` driver check; install matching PyTorch CUDA wheel using official PyTorch selector.
- Transfer **cached landmarks/features** rather than raw personal workout videos when adequate; limit data retention and inspect dataset redistribution rights.
- Run exact same training CLI in CPU/GPU modes and compare results; model artifact includes `model_version`, training config, subject-split IDs, feature schema and code revision.
- Download checkpoints + metrics to the repo's ignored local models directory; validate local CPU load/inference from the laptop; destroy idle instance so spend stops.
- Keep Vultr out of real-time inference architecture. ML demo should run with Wi-Fi/cloud off.

## Phase E — Integration and test cases

Expose a stable `analyze_frame(...)` or equivalent adapter that converts captured video into **ML observation** contracts only. Do not send cue text directly to ElevenLabs or audio; send issue codes/evidence to Tyler. Test source changes, odd frame rates, occlusion, live rep crossing an angle threshold repeatedly, incomplete/partial rep, and unknown exercise. Keep debug output separate from structured event transport.

Deliver: working command(s) to run webcam and MP4, annotatable logs, real baseline training/eval scripts, model metadata, Vultr runbook, and a factual concise report of what was implemented/tested. Preserve `ml/` integration schemas and do not manufacture ML accuracy or safety claims.

**Execution:** Inspect existing repo -> implement Phase A and smoke-test -> Phase B and count clips -> Phase C dataset processing/baseline -> Phase D portability -> Phase E end-to-end. Stop and report blockers accurately if sample data/hardware/cloud access is unavailable; don't claim incomplete steps are done.

defer training/testing for the user to do manually. do not train the model in your output.
