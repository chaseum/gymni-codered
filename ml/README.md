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

Everything at once: the newest recognizer and form models from `ml/models/` load automatically, the recognizer picks the exercise, and each exercise keeps its own rep count:

```bash
.venv/bin/fitness-ml run --source live
```

- **Choosing the exercise:** keys `1`-`8` choose one (manual mode) and `a` returns to auto. Auto switches only *between sets*: the new exercise must be recognized at ≥70% for 2 s, with no rep counted in the last 5 s.
- **Panel:** big rep count, a per-rep verdict, and the form model's held-out test F1, with "UNRELIABLE" below 0.65.
- **Deadlift:** the first 3 reps are your baseline. A rep the no-baseline model rates ≥70% faulty is refused as baseline. After 2 refusals the screen warns that faults are judged relative to a baseline that may itself be faulty.
- **Rules only:** `--no-models` turns the models off.

Live curls with the debug window and an observation log:

```bash
.venv/bin/fitness-ml run --source live --exercise curl --observations demo/logs/live_curl.jsonl --debug-log demo/logs/live_curl.debug.jsonl
```

A recorded clip through the same pipeline, posting to the backend at the clip's own speed:

```bash
.venv/bin/fitness-ml run --source recorded --video demo/clips/squat_side_01.mp4 --exercise squat --variation bodyweight --post --session demo --realtime
```

The window shows:
- a big rep count
- tracking state in plain words ("arm hidden", "step back")
- the counting angle on a bar marked with the **start** and **turn** thresholds
- the last counter message, e.g. `not counted: came back before reaching 85° (got to 97°)`

The same messages print in the terminal with timestamps.

**Tuning loop.** Record once:

```bash
.venv/bin/fitness-ml run --source live --exercise curl --record demo/clips/me_curl.mp4
```

Then replay that exact session as often as you like with true timing (`me_curl.timestamps.csv` is read automatically), changing thresholds in `config.py` or `--min-visibility` between runs:

```bash
.venv/bin/fitness-ml run --source recorded --video demo/clips/me_curl.mp4 --exercise curl
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
| shoulder_press | elbow, 2D | ≤105° → ≥150° → ≤105° | trained good/bad model only | arms visible |
| triceps_extension | elbow, 3D | ≤90° → ≥145° → ≤90° | trained good/bad model only | arms visible |
| row | elbow, 3D | ≥145° → ≤100° → ≥145° | trained good/bad model only | arms visible |
| push_up | elbow, 2D | ≥150° → ≤105° → ≥150° | trained good/bad model only | side view |
| side_bend | trunk lean, 2D | ≤8° → ≥20° → ≤8° | trained good/bad model only | front view |

- A rep counts only after a full cycle, longer than `min_rep_ms`, with hysteresis on both thresholds.
- A tracking gap over 800 ms mid-rep voids that rep (and says so). A clip starting mid-rep waits for the start position.
- A frame counts when MediaPipe's visibility of the arm/leg joints is ≥ 0.4 (`--min-visibility`). If the tracked arm drops out, the other arm takes over at once.
- Reported but never flagged: curl upper-arm drift, trunk lean, rep duration.
- When a frame can't count, tracking says why: `lost` (no person), `unassessable` (joint off-frame and not visible) or `low_visibility` (occluded, e.g. a baggy jacket sleeve).
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
4. **Contract v2 needed for 5 new exercises.** `shoulder_press`, `triceps_extension`, `row`, `push_up` and `side_bend` are sent as `exercise: "other"` plus `exercise_detail: "<id>"`. The v1 schema allows unknown fields, so nothing breaks, but the backend can't commit their reps until the exercise enum (and the phone's `Exercise` enum) gains these ids.
5. **Exercise mismatch.** With a recognizer loaded, `exercise` is what the model saw (possibly `unknown`/`other`), and the backend then won't commit that rep. Without a recognizer it is the planned exercise with `exercise_confidence: null`.
