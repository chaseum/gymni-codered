# Approved cue audio

One file per approved issue cue: `<cue_id>.mp3` where `cue_id` is the `feedback.issued.cue_id` from the backend. Fixed cues use the issue code, e.g. `curl.elbow_drift.mp3`. Dynamic corrections use `dynamic/<configuration_hash>.mp3` and a matching `.txt` file. Fixed workout prompts use `dynamic/voice-<configuration_hash>.mp3` and are fetched through `/api/coach/audio/<prompt_name>`.

- Approved corrections live in `backend/gymai_backend/app.py` (`CUES`). They are voiced verbatim by default (zero Gemini tokens). Optional `GYMAI_REPHRASE_CUES=1` caches one Gemini rewrite per approved action/configuration. Fixed workout prompts live in `backend/gymai_backend/voice_prompts.py`.
- Measured rep counts and relative pace cues use `contracts/coaching_policy.json`. The `coach.cue` event carries the caption; `/api/sessions/{id}/coaching/{cue_id}/audio` voices only server-selected, still-current cues. These clips use the same text/voice/model cache, without Gemini.
- Run `python -m pip install -e 'backend[audio]'`, then `python generate_audio.py` from the repository root to create the fixed spoken cues with ElevenLabs. The project-root `.env` supplies the key, voice ID, and model ID; credentials are never stored in this directory.
- Keep each cue brief. The laptop serves locally generated MP3 files to the iPhone; if a file is missing or unavailable, the iPhone uses native speech for the approved text.
- Prepare dynamic audio with `.venv/bin/python -m gymai_backend.prepare_audio --exercise curl`. The simulator script does this automatically. The cache includes the selected model and voice and is excluded from Git.
- Commit audio only when the selected voice and plan license the generated files for redistribution.
