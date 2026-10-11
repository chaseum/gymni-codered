"""Generate the approved Gym&I coaching cues into assets/audio."""

import os
from pathlib import Path

from dotenv import load_dotenv
from elevenlabs.client import ElevenLabs


ROOT = Path(__file__).resolve().parent
load_dotenv(ROOT / ".env")

API_KEY = os.getenv("ELEVENLABS_API_KEY")
VOICE_ID = os.getenv("ELEVENLABS_VOICE_ID")
MODEL_ID = os.getenv("ELEVENLABS_MODEL_ID", "eleven_flash_v2_5")

CUES = {
    "session_start": "Let's begin. Get into position when you're ready.",
    "curl_lower_slow": "Control the lowering phase. Take your time on the way down.",
    "curl_improved": "That was more controlled. Nice work.",
    "encouragement": "You're moving steadily. Keep it up.",
    "effort_check_in": "How is this feeling? You can take a break.",
    "pause_acknowledged": "Paused. Take the time you need.",
    "resume_ready": "Ready when you are. I'll wait until your position is clear.",
    "water_break": "This is a good moment for a water break if you need one.",
}


def main() -> None:
    if not API_KEY:
        raise SystemExit("Set ELEVENLABS_API_KEY in the project-root .env file.")
    if not VOICE_ID:
        raise SystemExit("Set ELEVENLABS_VOICE_ID in the project-root .env file.")

    client = ElevenLabs(api_key=API_KEY)
    output_dir = ROOT / "assets" / "audio"
    output_dir.mkdir(parents=True, exist_ok=True)

    for cue_id, text in CUES.items():
        audio = client.text_to_speech.convert(
            text=text,
            voice_id=VOICE_ID,
            model_id=MODEL_ID,
            output_format="mp3_44100_128",
        )
        output_path = output_dir / f"{cue_id}.mp3"
        with output_path.open("wb") as output_file:
            for chunk in audio:
                if chunk:
                    output_file.write(chunk)
        print(f"Saved {output_path.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
