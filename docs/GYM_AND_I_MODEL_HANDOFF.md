# Gym&I model handoff

This document is the intake and integration contract for the exercise-recognition and form-analysis models used by Gym&I. It is written for the person supplying model files and the person integrating them into `ml/`.

The wire contract is already frozen at v1. Do not change its schema, event names, or meaning to fit a model. The authoritative reference is [`contracts/protocol.md`](../contracts/protocol.md) and [`contracts/gymai.schema.json`](../contracts/gymai.schema.json).

## Current integration path

```text
camera or video frame
  → MediaPipe Pose Landmarker (33 landmarks)
  → normalized pose features and tracking/view checks
  → optional exercise recognizer
  → rep state machine and per-rep rule/model assessments
  → v1 Observation JSON
  → optional JSONL log and/or POST /api/sessions/{session_id}/observations
  → backend commits reps and selects approved coaching cues
```

The integration lives in `ml/src/fitness_ml/`. `PoseEstimator` supplies a `Pose` (or `None`) per frame; `Analyzer.analyze_frame(pose, timestamp_ms)` produces a `FrameResult` whose `observation` is the backend payload. `Recognizer` accepts the rolling normalized feature window and returns `(exercise_label, confidence)`. A form `Artifact` accepts a rep/window and returns one probability per metadata label. New model adapters should fit these interfaces or be wrapped behind them; the camera loop and wire protocol should not need model-specific branches.

## Model handoff package

For each artifact, provide the following alongside the weights. Mark unsupported items explicitly instead of guessing.

| Item | Required handoff |
|---|---|
| Purpose | Exercise recognition, rep counting, or form issue assessment; identify supported exercises and variations. |
| Files | Weight files, inference code or exact runtime/dependencies, and a checksum for each file. State CPU/GPU requirements and supported operating systems. |
| Input | Tensor/feature names and order, shape, data types, units, normalization, coordinate convention, frame rate/window length, and treatment of missing/low-confidence joints. Say whether the input is raw video, landmarks, or derived features. |
| Output | Exact labels and their order; whether values are logits, scores, or calibrated probabilities; threshold/rejection behavior; and what `unknown` or “no issue” means. |
| Training/evaluation | Dataset and label definitions, participant-level split method, held-out results, per-class confusion matrix/precision/recall/F1, and known failure cases. Include camera-view and visibility breakdowns when available. |
| Performance | Measured end-to-end inference latency and FPS on the intended demo laptop, plus memory use and warm-up cost. State the test machine and runtime. |
| Versioning | Stable model version, source revision, training/config version, and a short change log. |
| Limits | Views, equipment, exercise variants, clothing/occlusion, body types, and movements for which the model has not been evaluated. |

Do not include API keys, user credentials, or identifiable workout videos in the model package. Use consented, de-identified samples for any shared evaluation clips.

## Expected outputs by model role

### Exercise recognizer

- Produces a supported contract exercise (`curl`, `squat`, `deadlift`) or `other`/`unknown`.
- Confidence is the recognizer's exercise-classification confidence only. It is not a form-quality or safety score.
- Low-confidence or insufficiently tracked windows must reject to `unknown`; do not force a best label.
- The current v1 backend commits a rep only when the reported exercise matches the session's planned exercise. Other exercise IDs are not backend-countable in v1.
- The current analyzer consumes a recognizer via `Recognizer.update(timestamp_ms, features)`. Its artifact metadata must match the feature names in `ml/src/fitness_ml/features.py` and the model loader in `artifacts.py`.

### Rep counting

- The current rep counter is a reviewed signal/state-machine implementation in `reps.py`; a new model does not replace it unless the handoff explicitly includes a replacement plan and evidence.
- Emit `completed_rep` only once, on the frame completing a full cycle. `rep_index` must increase across analyzer resets, and a restarted analyzer must start above the backend's last committed index. The current time-derived startup index is a temporary workaround; a backend-issued start index would be more reliable. The backend is authoritative for the displayed count.
- Tracking loss, an incomplete cycle, a replay reset, or a pause must not produce a completed rep.
- Do not emit counts for an exercise the backend session did not plan.

### Form assessment

- The existing form-model adapter receives per-rep normalized pose features and returns probabilities in the exact `metadata.json` label order. For a `form_issue` artifact, labels must map to issue suffixes supported by the v1 schema and approved by the backend cue table.
- A binary `good`/`bad` output is not a specific issue code. Do not convert a generic bad score into a named fault.
- A candidate issue is not sent to the backend until its code and measurable criterion are reviewed and enabled in the exercise configuration. Evidence should contain the measured values or model probability and per-issue provenance.
- If view, visibility, or feature coverage is inadequate, abstain from assessment. Missing evidence must not be represented as a clean rep.
- Do not describe any confidence, score, cue, or rep result as a safety certification or medical judgment.

## Observation mapping

For every frame sent to the backend, emit the v1 fields described by the schema:

- `schema_version: 1`, unique `observation_id`, matching `session_id`, and `source` (`live` or `recorded`).
- `time_base` is `capture_monotonic` for live capture and `video_pts` for recorded clips. `source_timestamp_ms` is relative to that source clock, never Unix epoch time; it starts over for a new clip/source.
- `exercise`, nullable `exercise_confidence`, `tracking_status`, and `phase` reflect the model/pipeline's actual state. Use `unknown`, `lost`, `low_visibility`, or `unassessable` when appropriate.
- `completed_rep` is null on ordinary frames and present only on the one completion frame. Its `rep_index` is positive and increasing; restart above the backend's last committed index. The backend deduplicates `observation_id` and ignores stale rep indices. `set_id` is informational; the backend owns set IDs.
- `measurement_basis` accurately identifies image 2D vs estimated world 3D values. `measurements` use numeric values or null when unavailable.
- `issues` contain only approved `<exercise>.<snake_case>` codes with relevant evidence. Never use an issue label that the receiving backend does not recognize.
- `inference_provenance` is `reviewed_rules`, `trained_model`, or `fixture`. Use `trained_model` only for real model inference, include `model_version`, and never label fixtures as real inference.

See [`contracts/protocol.md`](../contracts/protocol.md) for event semantics, deduplication, and backend acceptance rules. The Python `Observation` in `ml/src/fitness_ml/types.py` is a convenience mirror, not a separate source of truth.

## Integration and acceptance checklist

Before enabling an artifact in a demo build:

- [ ] Confirm its task, supported labels, variation, input specification, output semantics, version, and limitations with the model owner.
- [ ] Check the artifact loads on CPU in the existing ML runtime and has matching feature metadata. If it requires a new runtime, package it behind a small adapter and record pinned dependencies.
- [ ] Verify recognition rejects unsupported/uncertain movement and form assessment abstains on inadequate tracking or view.
- [ ] Evaluate with held-out participants or clips that were not used to train/tune thresholds. Report per-class errors, including missed faults and false cues.
- [ ] Run annotated clips through the same `fitness-ml` path used for the demo and review rep counts, issue evidence, tracking status, latency, and dropped posts.
- [ ] Confirm only approved v1 issue codes reach the backend and the backend remains the only rep-count authority.
- [ ] Record the artifact version and evaluation result in the model metadata/README. Keep the prior artifact available for rollback.

Thresholds and minimum acceptable quality are **not set by this document**. The model owner and Gym&I team must agree on them using the actual held-out results and demo hardware before activating the model. The repository's current uncalibrated rules and thresholds are starting points, not evidence of model accuracy.

## Decisions to resolve when model files arrive

- Which delivered artifact replaces or supplements pose estimation, exercise recognition, form assessment, or none of these?
- Are its labels compatible with the three v1 analyzable exercise IDs? If not, keep unsupported labels as `other`/`unknown` until the shared protocol, backend, and iOS owners approve a coordinated version change.
- Which form issue labels have a measurable definition and backend cue? Review each against examples before enabling it.
- Does it need a camera view, variation, calibration sequence, or device capability that the current analyzer does not provide?
- Who owns artifact updates and the rollback decision during the hackathon demo?

## Current code references

- Pipeline: [`ml/src/fitness_ml/pipeline.py`](../ml/src/fitness_ml/pipeline.py)
- Pose adapter: [`ml/src/fitness_ml/pose.py`](../ml/src/fitness_ml/pose.py)
- Analyzer and observation mapping: [`ml/src/fitness_ml/analyzer.py`](../ml/src/fitness_ml/analyzer.py)
- Artifact loading and inference: [`ml/src/fitness_ml/artifacts.py`](../ml/src/fitness_ml/artifacts.py)
- Feature schema: [`ml/src/fitness_ml/features.py`](../ml/src/fitness_ml/features.py)
- Wire protocol: [`contracts/protocol.md`](../contracts/protocol.md)
