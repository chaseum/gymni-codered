# Gym&I cloud (Vercel)

`api/voice.py` voices approved coach phrases with ElevenLabs: `GET /api/voice?id=<phrase id>` returns an MP3.
Only ids in its `PHRASES` table work, so the public URL can't spend credits on arbitrary text, and Vercel's CDN
caches each clip until the next deploy. The iPhone app (`CoachVoice.swift`) falls back to the iPhone voice
if a clip is slow or unavailable.

Deploy from this folder (project `gymni-coach`):

```bash
npx vercel login
npx vercel link --yes --project gymni-coach
npx vercel env add ELEVENLABS_API_KEY production
npx vercel env add ELEVENLABS_VOICE_ID production
npx vercel env add ELEVENLABS_MODEL_ID production
npx vercel deploy --prod
```

Changing the voice or model: update the variable and redeploy (a deploy also clears the cached clips).
Tests: `.venv/bin/python -m pytest cloud/tests`.
