"""Backboard memory operations used alongside Gemini replies."""

import asyncio
import hashlib
import os
import sqlite3
from collections import defaultdict
from pathlib import Path
from urllib.parse import quote

import httpx
from dotenv import load_dotenv


ROOT = Path(__file__).resolve().parents[2]
load_dotenv(ROOT / ".env")

BASE_URL = "https://app.backboard.io/api"
ASSISTANT_PROMPT = """Gym&I fitness profile memory store. Keep only durable, user-provided
fitness goals, schedule, equipment, and exercise preferences. Do not infer or
store diagnoses, injuries, or other sensitive health information."""
FACT_EXTRACTION_PROMPT = """Extract only explicitly stated, durable fitness goals,
training schedule, available equipment, and exercise preferences. Do not infer
medical diagnoses, injuries, body composition, or sensitive traits."""
MEMORY_UPDATE_PROMPT = """Only update or remove a saved fact when the user explicitly
corrects it. Prefer the user's latest explicit statement when facts conflict."""
PROFILE_LOCKS: defaultdict[str, asyncio.Lock] = defaultdict(asyncio.Lock)


def _api_key() -> str:
    key = os.getenv("BACKBOARD_API_KEY")
    if not key:
        raise RuntimeError("Backboard memory is not configured; set BACKBOARD_API_KEY in the project-root .env.")
    return key


def _database_path() -> Path:
    configured = os.getenv("GYMAI_PROFILE_DB_PATH")
    return Path(configured).expanduser() if configured else Path.home() / ".gymai" / "profile_assistants.sqlite3"


def _profile_key(profile_id: str) -> str:
    return hashlib.sha256(profile_id.strip().encode("utf-8")).hexdigest()


def _lookup_assistant(profile_key: str) -> str | None:
    path = _database_path()
    path.parent.mkdir(parents=True, exist_ok=True)
    with sqlite3.connect(path) as database:
        database.execute(
            "CREATE TABLE IF NOT EXISTS profile_assistants "
            "(profile_key TEXT PRIMARY KEY, assistant_id TEXT NOT NULL)"
        )
        row = database.execute(
            "SELECT assistant_id FROM profile_assistants WHERE profile_key = ?",
            (profile_key,),
        ).fetchone()
    return row[0] if row else None


def _save_assistant(profile_key: str, assistant_id: str) -> None:
    with sqlite3.connect(_database_path()) as database:
        database.execute(
            "INSERT OR REPLACE INTO profile_assistants (profile_key, assistant_id) VALUES (?, ?)",
            (profile_key, assistant_id),
        )


async def get_profile_assistant(profile_id: str) -> str:
    """Return this profile's Backboard assistant, creating it once if needed."""
    _api_key()
    profile_key = _profile_key(profile_id)
    async with PROFILE_LOCKS[profile_key]:
        existing = _lookup_assistant(profile_key)
        if existing:
            return existing

        assistant_id = await create_profile_assistant()
        _save_assistant(profile_key, assistant_id)
        return assistant_id


async def create_profile_assistant() -> str:
    """Cloud callers keep the returned ID on the phone; no server database needed."""
    api_key = _api_key()
    async with httpx.AsyncClient(timeout=30.0) as client:
        response = await client.post(
            f"{BASE_URL}/assistants",
            headers={"X-API-Key": api_key},
            json={
                "name": "Gym&I Profile Memory",
                "system_prompt": ASSISTANT_PROMPT,
                "tok_k": 5,
                "custom_fact_extraction_prompt": FACT_EXTRACTION_PROMPT,
                "custom_update_memory_prompt": MEMORY_UPDATE_PROMPT,
            },
        )
        response.raise_for_status()
        assistant_id = response.json().get("assistant_id")

    if not isinstance(assistant_id, str) or not assistant_id:
        raise ValueError("Backboard did not return an assistant_id.")
    return assistant_id


async def search_profile_memories(profile_id: str, query: str, limit: int = 5, *, assistant_id: str | None = None) -> list[str]:
    assistant_id = assistant_id or await get_profile_assistant(profile_id)
    async with httpx.AsyncClient(timeout=20.0) as client:
        response = await client.post(
            f"{BASE_URL}/assistants/{quote(assistant_id, safe='')}/memories/search",
            headers={"X-API-Key": _api_key()},
            json={"query": query, "limit": limit},
        )
        response.raise_for_status()
        items = response.json().get("memories", [])
    return [item["content"] for item in items if isinstance(item.get("content"), str)]


async def add_profile_memory(profile_id: str, content: str, *, assistant_id: str | None = None) -> str | None:
    assistant_id = assistant_id or await get_profile_assistant(profile_id)
    async with httpx.AsyncClient(timeout=20.0) as client:
        response = await client.post(
            f"{BASE_URL}/assistants/{quote(assistant_id, safe='')}/memories",
            headers={"X-API-Key": _api_key(), "Content-Type": "application/json"},
            json={"content": content, "metadata": {"source": "Gym&I", "user_confirmed": True}},
        )
        response.raise_for_status()
        result = response.json()
    return result.get("memory_id") or result.get("id")


async def list_profile_memories(profile_id: str, *, assistant_id: str | None = None) -> list[dict]:
    assistant_id = assistant_id or await get_profile_assistant(profile_id)
    async with httpx.AsyncClient(timeout=20.0) as client:
        response = await client.get(
            f"{BASE_URL}/assistants/{quote(assistant_id, safe='')}/memories",
            headers={"X-API-Key": _api_key()},
            params={"page": 1, "page_size": 100},
        )
        response.raise_for_status()
        result = response.json()
    return result.get("memories", [])


async def delete_profile_memory(profile_id: str, memory_id: str, *, assistant_id: str | None = None) -> None:
    assistant_id = assistant_id or await get_profile_assistant(profile_id)
    async with httpx.AsyncClient(timeout=20.0) as client:
        response = await client.delete(
            f"{BASE_URL}/assistants/{quote(assistant_id, safe='')}/memories/{quote(memory_id, safe='')}",
            headers={"X-API-Key": _api_key()},
        )
        response.raise_for_status()
