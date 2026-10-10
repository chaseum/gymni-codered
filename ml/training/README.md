# Offline training (Chase)

Nothing here runs during the live demo; the laptop loads exported artifacts from `ml/models/`.

- `ml/data/` — downloaded datasets (MyDeadlift, Multi-View Fitness). **Git-ignored.** Record license + source URL per dataset in this README before use.
- `ml/models/` — exported artifacts and the MediaPipe `pose_landmarker_*.task` file. **Git-ignored.**
- Keep subject / video / camera view / variation metadata before windowing; splits are **participant-disjoint**.
- Baseline first (Random Forest / k-NN on temporal features), optional GRU/CNN on Vultr GPU with the **same** splits. Destroy GPU instances after pulling artifacts.
- Report only measured numbers: per-clip rep count error, confusion matrix, macro-F1 with class support, false-cue rate, FPS/latency on the demo laptop. Record model, dataset and feature versions; set `model_version` + `inference_provenance: "trained_model"` on observations that use it.

No trained model exists yet.
