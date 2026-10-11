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

Participant-disjoint split, 70/15/15 by **people** (Multi-View's 26 people → 18 train / 4 val / 4 test):

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

How it works:
- **Features:** setup and lockout angles, ranges, and the knee/hip/back curves resampled to 10 points (`artifacts.keypose_curve`).
- **Calibration:** each rep is judged relative to the lifter's first 3 clean reps. Between-lifter differences in absolute angles are larger than the differences between classes.
- **Threshold:** the fault threshold is chosen by leave-one-subject-out CV on the 5 training lifters, with a false-correction budget of 10% (`--max-false-correction`). The 2 test lifters are scored once.

Result on 2026-10-10:

| Metric | Untuned (whole-rep averages) | Tuned |
|---|---|---|
| macro-F1 | 0.76 | 0.75 |
| Correct reps wrongly flagged | 60% | 14% |
| Rounded back caught | 19/20 | 19/20 |
| Knees past toes caught | 20/20 | 10/20 |

All 10 missed knees-past-toes reps are lifter S07, whose correct setup is already deep-kneed. Live, the analyzer prints `form calibration 1/3 - keep these reps clean` for the first 3 deadlifts and judges nothing until then.

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

## All-GRU: sweep on a GPU machine (recognizer + 8 form models)

```bash
fitness-train sweep --task all --device cuda
```

Default grid: window 2 s / 3 s × hidden 64 / 128 × 1 / 2 layers, with dropout 0.2, learning rate 1e-3 and batch 128. That's 8 configurations per task, ranked on **validation** macro-F1. Change it with comma lists, e.g. `--hidden 64,128,256 --lr 0.001,0.0003`.

For each task, the sweep:
- keeps the winner in `ml/models/` (the live app loads it), and moves the others to `archive/sweeps/<task>-<time>/` with a `leaderboard.csv`;
- fits a **temperature** on validation, so confidence numbers mean something;
- for the recognizer, sets the "unknown" threshold from validation.

The test split is never used. Afterwards, run `fitness-train evaluate --artifact <winner>` once per winner, then `fitness-train export`.

Estimated time, `--task all` with the default grid: ~45–60 min on an RTX 3070, a few hours on an M1. The data comes from `gymai-training-data-*.zip`; unzip it inside `ml/`.

## Exporting models for another machine (e.g. a teammate's Raspberry Pi 4/5)

```bash
.venv/bin/fitness-train export
```

This writes `ml/models/exports/gymai-models-<time>.zip` with:
- the models `fitness-ml run` would load here, plus the pose model
- this exact `fitness_ml` code as a wheel
- `requirements.txt` with exact version pins
- a README with install steps and `MANIFEST.json` with SHA-256 hashes

Re-run it after every retrain. Needs a 64-bit OS: a Raspberry Pi Pico can't run it.

## Adding the Kaggle gym-video set (deadlift videos + a real "other" class)

[Workout/Exercises Video](https://www.kaggle.com/datasets/hasyimabdillah/workoutfitness-video) (Hasyim Abdillah, CC BY-NC-SA 4.0: non-commercial, credit the author) has 652 videos in 22 folders, including 32 `deadlift` videos. Download needs your Kaggle login: either the Download button, or the Kaggle CLI with your own API token. Unzip it to `ml/data/raw/kaggle_workout/`.

```bash
.venv/bin/fitness-train ingest kaggle_workout --root ml/data/raw/kaggle_workout --out ml/data/manifest_kaggle.csv
```

```bash
.venv/bin/fitness-train merge ml/data/manifest_multiview.csv ml/data/manifest_kaggle.csv --out ml/data/manifest.csv
```

Then run `extract`, `split`, and `train --task recognition`. How its folders are used:
- Deadlift, squat, push-up, curl (barbell and hammer), shoulder press and T-bar row map to our ids.
- Romanian deadlift and the other 14 exercises become `other`, which gives the recognizer real examples of movement it should reject.
- No person IDs are published, so this dataset's split is per video. Its test scores are optimistic.

## Adding weggry deadlift videos (550 side-view single reps with fault labels)

From [weggry/deadlift-classifier](https://github.com/weggry/deadlift-classifier), the dataset of [Automated Deadlift Techniques Assessment and Classification Using Deep Learning](https://doi.org/10.3390/ai6070148) (MDPI *AI*, 2025). **No licence is published:** use it only for this non-commercial project, credit the paper, and never commit or redistribute the videos (they sit in git-ignored `ml/data/raw/weggry_deadlift/`). The 550 originals were downloaded on 2026-10-10 and checked against GitHub's blob hashes; the 550 mirrored copies were not downloaded.

```bash
.venv/bin/fitness-train ingest weggry_deadlift --root ml/data/raw/weggry_deadlift --out ml/data/manifest_weggry.csv
```

How it maps:
- Conventional and sumo → `deadlift`.
- Romanian → `other`, because it starts standing.
- Faults → `issue_label`: `none` / `hips_rise_early` / `back_overextension` / `rounded_back`.

There are no person IDs, so the split is per video. If most clips show the same lifter, the scores are optimistic.

## Adding your own clips (e.g. deadlift, which no public dataset here has on video)

```bash
.venv/bin/fitness-ml run --source live --exercise deadlift --record demo/clips/deadlift_chase_side_01.mp4
```

```bash
.venv/bin/fitness-train add-clip demo/clips/deadlift_chase_side_*.mp4 --exercise deadlift --participant chase --view side --variation backpack
```

Then rebuild the manifest and retrain. Only new clips are extracted, and the Multi-View split is unchanged:

```bash
.venv/bin/fitness-train ingest multiview --root ml/data/raw/multiview --out ml/data/manifest_multiview.csv
```

```bash
.venv/bin/fitness-train merge ml/data/manifest_multiview.csv ml/data/manifest_own.csv --out ml/data/manifest.csv
```

```bash
.venv/bin/fitness-train extract && .venv/bin/fitness-train split && .venv/bin/fitness-train train --task recognition --model rf
```

Things to know:
- **Record the other exercises too.** If deadlift is the only exercise filmed in your room, the recognizer learns "your room" instead of "deadlift". A couple of short clips of each exercise you demo fixes that, and also helps with the webcam-vs-gym-phone gap.
- **Use several angles and people.** For deadlift, record side-on plus one diagonal. With your clips from a single person, that person always lands in training, so `evaluate` can't measure deadlift recognition. Record 3+ people (teammates) to get an honest test number.
