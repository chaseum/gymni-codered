# Approved cue audio

One file per cue: `<cue_id>.m4a` where `cue_id` is the `feedback.issued.cue_id` from the backend (currently equal to the issue code, e.g. `curl.elbow_drift.m4a`). Non-correction cues use plain names (`rest_started.m4a`, `set_complete.m4a`).

- Text for each cue lives in `backend/gymai_backend/app.py` (`CUES`); audio must say exactly that text.
- Generated ahead of time with ElevenLabs; the API key lives in your shell env / `.env`, **never** in git. Commit only cues whose voice/licence terms allow it.
- Keep each cue < 3 s. The iPhone bundles a copy; the laptop speaker is the fallback.
