# fitness_ml (Chase)

Webcam/MP4 → MediaPipe Tasks Pose Landmarker (VIDEO mode, CPU) → per-frame features → rep state machine → per-rep form checks → `contracts/` observations.

```bash
.venv/bin/pip install -e 'ml[train,dev]'
```

```bash
.venv/bin/fitness-ml download-model
```

`--variant full` or `--variant heavy` gives the larger models. Install exactly one OpenCV: MediaPipe pulls `opencv-contrib-python`, so don't also install `opencv-python` (both write the same `cv2` folder; uninstalling one breaks the other).

## Run

Live curls with the debug window and an observation log:

```bash
.venv/bin/fitness-ml run --source live --exercise curl --observations demo/logs/live_curl.jsonl --debug-log demo/logs/live_curl.debug.jsonl
```

A recorded clip through the same pipeline, posting to the backend at the clip's own speed:

```bash
.venv/bin/fitness-ml run --source recorded --video demo/clips/squat_side_01.mp4 --exercise squat --variation bodyweight --post --session demo --realtime
```

Keys: `q` quit, `p` pause/resume (a half-done rep is discarded on resume), `r` replay the clip / reset live, `s` switch between live and `--video`. Each source run gets a fresh landmarker, because VIDEO mode needs strictly increasing timestamps. `rep_index` keeps rising across all of these.

macOS asks for Camera permission for your terminal the first time.

- `--observations`: contract JSONL, the same records `--post` sends.
- `--debug-log`: per-frame features, view, side and rep checks. **Not a contract**; never feed it to the backend.

## How it decides

| Exercise | Counting signal (config.py) | Cycle | First criterion (issue code) | Needs |
|---|---|---|---|---|
| curl | elbow angle, estimated 3D (webcam faces you) | lowered ≥145° → raised ≤85° → lowered | `curl.partial_range`: rep's smallest elbow angle > 60° | elbow visible |
| squat | knee angle, 2D | standing ≥160° → bottom ≤120° → standing | `squat.shallow_depth`: smallest knee angle > 95° | **side view**, else `unassessable` |
| deadlift | hip angle, 2D | setup ≤120° → lockout ≥160° → setup | `deadlift.hips_rise_early`: in the first 30% of the lift, hips rise ≥2× shoulders | **side view**, else `unassessable` |

- A rep counts only after a full cycle, longer than `min_rep_ms`, with hysteresis on both thresholds.
- A tracking gap over 400 ms mid-rep voids that rep. A clip starting mid-rep waits for the start position.
- Reported but never flagged: curl upper-arm drift, trunk lean, rep duration.
- Tracking is `lost` (no person), `unassessable` (required joint outside the frame) or `low_visibility` (occluded).
- All thresholds are **uncalibrated starting guesses**.

**Review gate:** a criterion's issue reaches the backend only after its code is added to `reviewed` for that exercise in `config.py`. Until then it is a debug "candidate" only. To review: record demonstration clips of correct and faulty reps, run them with `--debug-log`, check each rep's printed `checks:` line against what a person sees, tune the threshold, then add the code to `reviewed`.

## Validate counts

Write `demo/annotations.csv` (paths relative to it), using [`demo/annotations.example.csv`](../demo/annotations.example.csv) as the template. Then:

```bash
.venv/bin/fitness-ml validate --annotations demo/annotations.csv --out demo/validation.csv
```

Each row has actual vs predicted reps, over/missed counts, lost / low-visibility / out-of-frame frames, candidate issues, unassessable checks, FPS and mean/p95 latency. For a live session, append a row at exit:

```bash
.venv/bin/fitness-ml run --source live --exercise curl --summary-csv demo/validation.csv --actual-reps 10
```

## Tests

```bash
.venv/bin/python -m pytest ml -q
```

Synthetic poses only, covering:
- exact angles in non-square frames
- jitter at the thresholds, partial reps, too-fast reps
- frame rates of 12/24/29.97/59.94 fps
- short vs long tracking gaps, a clip starting mid-rep
- source switch and reset, occlusion, front-view squat (depth unassessable)
- an unsure recognizer → `unknown`
- contract validity of every emitted observation
- manifest parsing and split leakage

No real video is tested here; real clips go through `validate`.

## Integration notes for Tyler (backend not modified)

1. **"Improved" after an unassessable rep.** The backend marks an issue improved when a completed rep doesn't carry it. A rep that was *unassessable* (wrong view, joint lost) also doesn't carry it, so it would count as a false "improved". Suggested fix: only resolve on reps that carry a measurement for that criterion (e.g. `rep_min_knee_angle_deg` is not null), or have ML send an explicit per-criterion status.
2. **`rep_index` across ML restarts.** The backend commits only `rep_index > max seen`. The analyzer starts its index at `int(time.time() * 2)`, so a restarted process still counts. A backend-issued start index would be cleaner.
3. **Provenance names.** The contract enum is `reviewed_rules | trained_model | fixture`. The prompt's `model_prediction` maps to `trained_model`, and per-issue `evidence.provenance` says which rule or model produced each issue. No contract change was made.
4. **Exercise mismatch.** With a recognizer loaded, `exercise` is what the model saw (possibly `unknown`/`other`), and the backend then won't commit that rep. Without a recognizer it is the planned exercise with `exercise_confidence: null`.
