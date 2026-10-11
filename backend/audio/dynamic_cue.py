"""Turn approved form observations into short Gemini-written ElevenLabs cues."""

import os
from pathlib import Path
from typing import Literal

from dotenv import load_dotenv
from elevenlabs.client import ElevenLabs
from google import genai
from google.genai import types
from pydantic import BaseModel, Field


ROOT = Path(__file__).resolve().parents[2]
load_dotenv(ROOT / ".env")


class CueRequest(BaseModel):
    """A form observation already approved by the deterministic coaching policy."""

    exercise: Literal["curl", "squat", "deadlift", "shoulder_press", "triceps_extension", "row", "push_up", "side_bend"]
    issue_code: str = Field(min_length=1, max_length=80)
    evidence: str = Field(min_length=1, max_length=300)
    recommended_action: str = Field(min_length=1, max_length=200)
    confidence: float = Field(ge=0.0, le=1.0)
    tracking_status: Literal["ready", "positioning", "lost"]
    coach_approved: bool


class SpokenCue(BaseModel):
    """Constrained natural-language version of the approved action."""

    spoken_text: str = Field(min_length=1, max_length=140)


def _required_setting(name: str) -> str:
    value = os.getenv(name)
    if not value:
        raise RuntimeError(f"Set {name} in the project-root .env file.")
    return value


def _check_request(request: CueRequest) -> None:
    if not request.coach_approved:
        raise ValueError("The coaching policy has not approved a spoken cue.")
    if request.tracking_status != "ready":
        raise ValueError("Dynamic coaching is only allowed while tracking is ready.")
    if request.confidence < 0.8:
        raise ValueError("Tracking confidence is too low for a spoken correction.")


def generate_spoken_cue(request: CueRequest) -> tuple[str, bytes]:
    """Generate a short cue and return its text plus MP3 bytes.

    Call this only after the shared coaching policy selects a supported correction.
    """
    _check_request(request)

    gemini = genai.Client(
        api_key=_required_setting("GEMINI_API_KEY"),
        http_options=types.HttpOptions(timeout=30_000),
    )
    gemini_model = os.getenv("GEMINI_MODEL_ID", "gemini-3.5-flash-lite")
    prompt = f"""
Rewrite the approved coaching action as one brief spoken cue for a supportive
workout coach. Use 6 to 14 words. Keep it specific, respectful, and easy to
understand while moving. Do not add advice, diagnoses, praise, claims, or facts
that are not in the approved action. Evidence is context only; do not infer any
other form issue. Return only the requested structured output.

Exercise: {request.exercise}
Issue code: {request.issue_code}
Observed evidence: {request.evidence}
Approved action (the only instruction you may express): {request.recommended_action}
""".strip()

    print("Requesting cue text from Gemini...", flush=True)
    response = gemini.models.generate_content(
        model=gemini_model,
        contents=prompt,
        config=types.GenerateContentConfig(
            response_mime_type="application/json",
            response_schema=SpokenCue,
            max_output_tokens=80,
        ),
    )
    if not response.text:
        raise RuntimeError("Gemini returned an empty response.")
    cue = SpokenCue.model_validate_json(response.text).spoken_text.strip()
    if not 1 <= len(cue.split()) <= 18:
        raise ValueError("Gemini returned a cue outside the allowed length.")

    print("Gemini returned a cue. Requesting audio from ElevenLabs...", flush=True)
    elevenlabs = ElevenLabs(api_key=_required_setting("ELEVENLABS_API_KEY"))
    audio_chunks = elevenlabs.text_to_speech.convert(
        text=cue,
        voice_id=_required_setting("ELEVENLABS_VOICE_ID"),
        model_id=os.getenv("ELEVENLABS_MODEL_ID", "eleven_v4"),
        output_format="mp3_44100_128",
    )
    audio = b"".join(chunk for chunk in audio_chunks if chunk)
    if not audio:
        raise RuntimeError("ElevenLabs returned an empty audio response.")
    print("ElevenLabs returned the audio.", flush=True)
    return cue, audio


def save_spoken_cue(request: CueRequest, output_path: Path) -> str:
    """Generate the cue, save its MP3, and return the spoken text."""
    spoken_text, audio = generate_spoken_cue(request)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_bytes(audio)
    return spoken_text
