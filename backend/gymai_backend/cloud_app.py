"""Stateless Vercel API. The iPhone owns workouts; the Pi owns capture and ML."""
import asyncio
import hashlib
import hmac
import os
from collections import defaultdict
from pathlib import Path
from typing import Literal

from fastapi import Depends, FastAPI, HTTPException, Request
from fastapi.responses import Response
from pydantic import BaseModel, ConfigDict, Field

from backend.audio.dynamic_cue import cached_voice_id, save_voice_clip
from .backboard_memory import (create_profile_assistant, add_profile_memory,
                               list_profile_memories, delete_profile_memory)
from .coaching_catalog import CUES
from .gemini import send_coach_message
from .rep_coaching import POLICY, count_text
from .voice_prompts import COACH_PROMPTS

app = FastAPI(title="Gym&I hosted coach")
AUDIO_DIR = Path(os.getenv("GYMAI_CLOUD_AUDIO_DIR", "/tmp/gymai/audio"))
VOICE_LOCKS = defaultdict(asyncio.Lock)


def auth(request: Request):
    token = os.getenv("GYMAI_TOKEN")
    if token and not hmac.compare_digest(request.headers.get("Authorization", ""), f"Bearer {token}"):
        raise HTTPException(401, "Access denied.")


class VoiceRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    kind: Literal["prompt", "form", "count", "pace_fast", "pace_slow"]
    code: str | None = Field(default=None, max_length=80)
    rep_count: int | None = Field(default=None, ge=1, le=1000)
    target_reps: int | None = Field(default=None, ge=1, le=1000)

    def approved_text(self) -> str:
        if self.kind == "prompt":
            text = COACH_PROMPTS.get(self.code)
        elif self.kind == "form":
            text = CUES.get(self.code)
        elif self.kind == "count":
            text = count_text(self.rep_count, self.target_reps) if self.rep_count else None
        else:
            text = POLICY[self.kind]
        if not text:
            raise HTTPException(422, "No approved cue for this request.")
        return text


@app.get("/health")
async def health():
    return {"status": "ok", "workout_owner": "iphone", "capture_owner": "pi"}


@app.get("/api/coach/configuration", dependencies=[Depends(auth)])
async def configuration():
    # Fingerprint invalidates the phone's clip cache when voice/model/catalog changes.
    fingerprint = hashlib.sha256((cached_voice_id("configuration") + str(POLICY) + str(CUES) + str(COACH_PROMPTS)).encode()).hexdigest()[:24]
    return {"voice_provider": "elevenlabs", "voice_revision": fingerprint,
            "voice_available": bool(os.getenv("ELEVENLABS_API_KEY") and os.getenv("ELEVENLABS_VOICE_ID")),
            "workout_llm_tokens": 0}


@app.post("/api/coach/voice", dependencies=[Depends(auth)])
async def voice(body: VoiceRequest):
    text = body.approved_text()
    if not os.getenv("ELEVENLABS_API_KEY") or not os.getenv("ELEVENLABS_VOICE_ID"):
        raise HTTPException(503, "ElevenLabs is not configured on the hosted API.")
    cache_id = cached_voice_id(text)
    path = AUDIO_DIR / f"{cache_id}.mp3"
    try:
        async with VOICE_LOCKS[cache_id]:
            await asyncio.to_thread(save_voice_clip, text, path)
            audio = await asyncio.to_thread(path.read_bytes)
    except Exception as exc:
        raise HTTPException(502, "ElevenLabs audio is temporarily unavailable.") from exc
    return Response(audio, media_type="audio/mpeg", headers={"X-Voice-Provider": "elevenlabs", "Cache-Control": "private, max-age=86400"})


class ChatTurn(BaseModel):
    role: Literal["user", "model"]
    text: str = Field(min_length=1, max_length=4000)


class CoachMessage(BaseModel):
    message: str = Field(min_length=1, max_length=4000)
    history: list[ChatTurn] = Field(default_factory=list, max_length=20)
    assistant_id: str | None = Field(default=None, max_length=100)


@app.post("/api/coach/messages", dependencies=[Depends(auth)])
async def message(body: CoachMessage):
    try:
        # Each turn carries its phone-owned history; no in-memory server conversation.
        return await send_coach_message(body.message, history=[{"role": turn.role, "parts": [{"text": turn.text}]} for turn in body.history], assistant_id=body.assistant_id)
    except Exception as exc:
        raise HTTPException(502, "The conversational coach is temporarily unavailable.") from exc


@app.post("/api/coach/profiles", dependencies=[Depends(auth)])
async def profile():
    try:
        return {"assistant_id": await create_profile_assistant()}
    except Exception as exc:
        raise HTTPException(502, "Profile memory is temporarily unavailable.") from exc


class Memory(BaseModel):
    content: str = Field(min_length=1, max_length=2000)


@app.post("/api/coach/profiles/{assistant_id}/memories", dependencies=[Depends(auth)])
async def save_memory(assistant_id: str, body: Memory):
    try:
        return {"memory_id": await add_profile_memory("", body.content, assistant_id=assistant_id)}
    except Exception as exc:
        raise HTTPException(502, "Could not save profile memory.") from exc


@app.get("/api/coach/profiles/{assistant_id}/memories", dependencies=[Depends(auth)])
async def memories(assistant_id: str):
    try:
        return {"memories": await list_profile_memories("", assistant_id=assistant_id)}
    except Exception as exc:
        raise HTTPException(502, "Could not load profile memory.") from exc


@app.delete("/api/coach/profiles/{assistant_id}/memories/{memory_id}", dependencies=[Depends(auth)])
async def remove_memory(assistant_id: str, memory_id: str):
    try:
        await delete_profile_memory("", memory_id, assistant_id=assistant_id)
        return {"deleted": True}
    except Exception as exc:
        raise HTTPException(502, "Could not remove profile memory.") from exc
