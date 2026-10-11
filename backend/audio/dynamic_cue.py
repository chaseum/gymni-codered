"""Turn approved form observations into short Gemini-written ElevenLabs cues."""

import hashlib
import json
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


def cached_cue_id(request: CueRequest) -> str:
    """Reuse one generated clip per approved action and provider configuration."""
    identity = {
        "issue_code": request.issue_code,
        "recommended_action": request.recommended_action,
        "gemini_model": os.getenv("GEMINI_MODEL_ID", "gemini-3.5-flash-lite"),
        "elevenlabs_model": os.getenv("ELEVENLABS_MODEL_ID", "eleven_v4"),
        "voice_id": os.getenv("ELEVENLABS_VOICE_ID", ""),
    }
    encoded = json.dumps(identity, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()[:24]


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
    prompt = (
        "Rewrite the approved correction as a natural spoken cue in 6 to 10 words. "
        "Keep its meaning. Add no advice, praise, diagnosis, or new claim. "
        f"Approved correction: {request.recommended_action}"
    )

    print("Requesting cue text from Gemini...", flush=True)
    response = gemini.models.generate_content(
        model=gemini_model,
        contents=prompt,
        config=types.GenerateContentConfig(
            response_mime_type="application/json",
            response_schema=SpokenCue,
            max_output_tokens=24,
        ),
    )
    if not response.text:
        raise RuntimeError("Gemini returned an empty response.")
    cue = SpokenCue.model_validate_json(response.text).spoken_text.strip()
    if not 1 <= len(cue.split()) <= 12:
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
    text_path = output_path.with_suffix(".txt")
    if output_path.is_file() and output_path.stat().st_size and text_path.is_file():
        cached_text = text_path.read_text(encoding="utf-8").strip()
        if cached_text:
            return cached_text

    spoken_text, audio = generate_spoken_cue(request)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    temporary_audio = output_path.with_suffix(".mp3.tmp")
    temporary_text = text_path.with_suffix(".txt.tmp")
    temporary_audio.write_bytes(audio)
    temporary_text.write_text(spoken_text, encoding="utf-8")
    temporary_audio.replace(output_path)
    temporary_text.replace(text_path)
    return spoken_text
