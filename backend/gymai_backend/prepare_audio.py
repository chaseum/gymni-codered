"""Prepare the configured ElevenLabs voice before the laptop workout starts."""

import argparse
import sys

from .app import AUDIO_DIR, CUES, DYNAMIC_CUES
from .voice_prompts import COACH_PROMPTS
from .rep_coaching import POLICY, count_text


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--exercise", choices=sorted({code.split(".")[0] for code in CUES}), default="curl")
    parser.add_argument("--target-reps", type=int, default=8)
    args = parser.parse_args()
    if not DYNAMIC_CUES:
        print("Dynamic voice is disabled; using device speech.")
        return 0
    from backend.audio.dynamic_cue import CueRequest, cached_cue_id, cached_voice_id, save_spoken_cue, save_voice_clip

    try:
        for name, text in COACH_PROMPTS.items():
            save_voice_clip(text, AUDIO_DIR / "dynamic" / f"{cached_voice_id(text)}.mp3")
            print(f"Workout voice ready: {name}", flush=True)
        texts = {POLICY["pace_fast"], POLICY["pace_slow"]}
        texts.update(text for count in range(1, args.target_reps + 1) if (text := count_text(count, args.target_reps)))
        for text in sorted(texts):
            save_voice_clip(text, AUDIO_DIR / "dynamic" / f"{cached_voice_id(text)}.mp3")
        print("Pace and rep milestone voices ready (no Gemini requests).", flush=True)
        for code, text in CUES.items():
            if code.split(".")[0] != args.exercise:
                continue
            request = CueRequest(exercise=args.exercise, issue_code=code, evidence="approved action only",
                                 recommended_action=text, confidence=1, tracking_status="ready", coach_approved=True)
            save_spoken_cue(request, AUDIO_DIR / "dynamic" / f"{cached_cue_id(request)}.mp3")
            print(f"Correction voice ready: {code}", flush=True)
    except Exception as exc:
        # Provider exceptions can contain request details. Never print credentials.
        print(f"Voice preparation failed ({type(exc).__name__}); device speech remains available.", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
