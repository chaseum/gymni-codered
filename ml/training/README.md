# Offline training (Chase)

Code: `ml/src/fitness_ml/training/` (CLI `fitness-train`). The laptop demo loads exported artifacts from `ml/models/`; nothing here runs live.

**What gets trained (and what doesn't):** pose detection is MediaPipe's pretrained Pose Landmarker; we don't retrain it. We train on top of its landmarks:
1. **Exercise recognition** — which of the 8 exercises is happening, or `unknown`.
2. **Form models** — good/bad per exercise (Multi-View labels) and deadlift fault type (MyDeadlift labels).

**Status: datasets downloaded and parsed; nothing trained yet.** Report only numbers from `metrics_*.json`.

## Data (already in place, git-ignored)

| Path | Source (CC BY 4.0) | Contents |
|---|---|---|
| `ml/data/raw/multiview/` | [Multi-View Fitness v3](https://data.mendeley.com/datasets/kgbb3yn47p/3) | 1042 videos, 26 people, 7 exercises × good/bad × front/side/diagonal |
| `ml/data/raw/mydeadlift/Extracted_keypoints.csv` | [MyDeadlift v1](https://data.mendeley.com/datasets/w5prmmxyt9/1) | **No videos published.** 191 single-rep clips as per-frame knee/hip/back angles; labels correct / rounded back / knees past toes; its own split: S04, S07 test |
| `ml/data/manifest.csv` | built by `ingest` | one row per video |

Exercise ids: `curl` (alternating in this dataset), `squat` (bodyweight), `side_bend`, `row`, `push_up`, `shoulder_press`, `triceps_extension`, plus `deadlift` (angles only, and from your own clips).

## Run it (in order)

```bash
.venv/bin/pip install -e 'ml[train]'
```

Build the manifest. It's already built, but re-running it is harmless:

```bash
.venv/bin/fitness-train ingest multiview --root ml/data/raw/multiview --out ml/data/manifest.csv
```

Pose extraction, once per video, is the slow step (~1042 videos). Try 5 first:

```bash
.venv/bin/fitness-train extract --limit 5
```

```bash
.venv/bin/fitness-train extract
```

`--every 2` halves the time by keeping every 2nd frame.

Participant-disjoint split (26 people → about 17 train / 4 val / 5 test):

```bash
.venv/bin/fitness-train split
```

Exercise recognition:

```bash
.venv/bin/fitness-train train --task recognition --model rf
```

The same again, with push-ups held out, measures whether the model says "unknown" for movement it never saw:

```bash
.venv/bin/fitness-train train --task recognition --model rf --exclude-labels push_up
```

Good/bad form, one model per exercise (repeat for each id above except deadlift):

```bash
.venv/bin/fitness-train train --task form_binary --exercise curl --model rf
```

Deadlift fault type, from the angle CSV. This trains and tests on the dataset's own split in one step:

```bash
.venv/bin/fitness-train deadlift-angles
```

Evaluate each video-based model on its held-out people:

```bash
.venv/bin/fitness-train evaluate --artifact ml/models/<model_version>
```

`metrics_test.json` holds:
- per-class F1 and support, macro-F1 and the confusion matrix
- F1 per camera view and per-video vote
- the rejection sweep: coverage, accuracy, and how often an unseen exercise was accepted
- for form models, the false-correction rate (good reps flagged as bad)

Pick `Config.reject_below` from the sweep.

Optional GRU comparator on the identical split: `pip install -e 'ml[train,gru]'`, then `--model gru --device auto`. For a cloud GPU see `docs/VULTR_TRAINING.md`.

## Use the models live

```bash
.venv/bin/fitness-ml run --source live --exercise curl --recognizer ml/models/<recognition_version> --form-model ml/models/<form_binary-curl-...>
```

```bash
.venv/bin/fitness-ml run --source recorded --video deadlift.mp4 --exercise deadlift --form-model ml/models/<form_issue-deadlift-angles-...>
```

- A good/bad model shows up as `form_model_p_bad` in the observation's measurements and as a printed line per rep. It never becomes a spoken correction.
- The deadlift angle model emits issue codes `deadlift.rounded_back` / `deadlift.knees_past_toes` (provenance `trained_model`). The backend only voices codes Tyler adds to its cue table.

## Known limits (say these with any result)

- **No deadlift video anywhere.** The recognizer can't learn deadlift until you record your own clips. Add them with `fitness-train ingest csv --root my_clips.csv --out ml/data/manifest_own.csv` and merge.
- **Deadlift angle model domain shift.** It was trained on the dataset's MediaPipe angles from an iPhone side view at 2.5 m, and live input comes from our 2D side-view angles. Validate on your own side-view deadlifts.
- **Webcam ≠ gym phone video.** Multi-View is phone footage in a gym, and the live input is a laptop webcam at home. Expect lower accuracy live than in `metrics_test.json`, and record a few of your own clips per exercise to check.
- **"Bad form" is the dataset annotators' whole-video judgement**, not a specific fault and not a safety assessment.
