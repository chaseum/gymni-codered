"""Vercel function: voice an approved Gym&I phrase with ElevenLabs.

GET /api/voice?id=<phrase id>  ->  audio/mpeg

Only the phrases below can be voiced, so the public URL can't spend ElevenLabs credits on arbitrary text.
Clips are cached on Vercel's CDN for a year; every deployment clears that cache, so a new voice or model
(set in the project's environment variables) takes effect on the next deploy.
"""
import json
import os
import urllib.request
from http.server import BaseHTTPRequestHandler
from urllib.parse import parse_qs, urlparse

PHRASES = {
    # Coach prompts (backend/gymai_backend/voice_prompts.py, CoachVoiceCue on iOS).
    "paused": "Paused. Take the time you need.",
    "ended": "Workout ended. Here is your recap.",
    "begin": "Let’s begin. I’ll count your reps.",
    "positioning": "Step into view so I can follow your movement.",
    "waiting": "Waiting for camera tracking.",
    "tracking_ready": "Tracking ready. I’m following your reps.",
    "tracking_lost": "Tracking interrupted. Adjust your position.",
    # iPhone-only prompts.
    "camera_ready": "Camera ready. Begin when you’re ready.",
    "position_phone": "Position your phone so you can see your movement.",
    "form_improved": "That is steadier now. Nice work.",
    # Approved form corrections, keyed by issue code (backend CUES, HubSession.cues on iOS).
    "curl.elbow_drift": "Keep your elbows pinned to your sides.",
    "curl.partial_range": "Let the weight come all the way down.",
    "squat.shallow_depth": "Sit a little deeper if it feels comfortable.",
    "deadlift.hips_rise_early": "Push the floor away; let your hips and chest rise together.",
    "shoulder_press.incomplete_lockout": "Press all the way up until your arms are straight overhead.",
    "triceps_extension.incomplete_extension": "Straighten your arms fully at the top of each rep.",
    "row.short_pull": "Pull your elbow further back, toward your hip.",
    "push_up.shallow_depth": "Lower your chest a little closer to the floor.",
    "push_up.hips_sagging": "Squeeze your glutes and keep your hips in line with your shoulders.",
    "push_up.hips_piked": "Lower your hips so your body forms a straight line.",
    "side_bend.partial_range": "Bend a little further to the side, keeping your hips still.",
}
CACHE_FOREVER = "public, max-age=86400, s-maxage=31536000, immutable"


def synthesize(text: str) -> bytes:
    """ElevenLabs text-to-speech over plain HTTPS (no SDK, so the function needs no dependencies)."""
    request = urllib.request.Request(
        f"https://api.elevenlabs.io/v1/text-to-speech/{os.environ['ELEVENLABS_VOICE_ID']}?output_format=mp3_44100_128",
        data=json.dumps({"text": text, "model_id": os.environ.get("ELEVENLABS_MODEL_ID", "eleven_v4")}).encode(),
        headers={"xi-api-key": os.environ["ELEVENLABS_API_KEY"], "Content-Type": "application/json",
                 "Accept": "audio/mpeg"},
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=20) as response:
        audio = response.read()
    if not audio:
        raise RuntimeError("ElevenLabs returned no audio")
    return audio


class handler(BaseHTTPRequestHandler):
    def do_GET(self):
        phrase_id = parse_qs(urlparse(self.path).query).get("id", [""])[0]
        text = PHRASES.get(phrase_id)
        if text is None:
            return self._send(404, b'{"error":"unknown phrase"}', "application/json", "no-store")
        try:
            audio = synthesize(text)
        except (KeyError, OSError, RuntimeError) as error:  # missing setting, network, or ElevenLabs error
            print(f"voice {phrase_id} failed: {type(error).__name__}: {error}")
            return self._send(502, b'{"error":"voice unavailable"}', "application/json", "no-store")
        self._send(200, audio, "audio/mpeg", CACHE_FOREVER)

    def _send(self, status: int, body: bytes, content_type: str, cache: str):
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", cache)
        self.end_headers()
        self.wfile.write(body)
