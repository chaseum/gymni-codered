# Main app: Pi camera, iPhone workout, hosted coach

The Pi runs `fitness-ml` with the trained model. It sends observations directly to the iPhone over the same Wi-Fi network. The iPhone commits trusted reps, selects coaching, manages rest and the Watch, and saves workout JSON. Vercel supplies ElevenLabs audio, Gemini chat, and Backboard memory. A laptop backend is not part of the workout path.

## Vercel deployment

Import this repository into Vercel with the **repository root** as the project root. The root `main.py` exports the stateless FastAPI application. `requirements.txt` installs only API dependencies. `.vercelignore` excludes the iOS app, ML runtime/models, media, local keys, and private state. Do not use `gymai_backend.app:app` as the cloud entry point: that legacy app owns in-memory laptop sessions.

Add these values from your local ignored `.env` to the Vercel project's environment settings, then deploy:

- `ELEVENLABS_API_KEY`, `ELEVENLABS_VOICE_ID`, `ELEVENLABS_MODEL_ID`
- `GEMINI_API_KEY`, `GEMINI_MODEL_ID`, `BACKBOARD_API_KEY`
- `GYMAI_TOKEN` if you use an app access token

Provider keys remain on Vercel. Do not put them in Swift, the Pi command, or an app configuration file. The hosted workout voice route always uses approved text and zero Gemini tokens; `GYMAI_REPHRASE_CUES` does not enable rephrasing on this route.

In the iPhone app, open **Settings → Hosted coach**, enter the HTTPS deployment URL, and tap **Check voice connection**. If configured, enter the app access token too (this field is memory-only). The endpoint must expose `GET /api/coach/configuration` and `POST /api/coach/voice`; an older laptop session API alone is insufficient.

## Pi camera

Install the model bundle into the Pi's ignored `ml/models/` directory and install the ML package with the appropriate Pi camera dependencies. Open GymAndAI in Xcode and run it on your iPhone. Tap **Start workout**. The screen shows the iPhone address while waiting for tracking. On the Pi, run:

```sh
fitness-ml run --source live --exercise curl --post http://IPHONE_WIFI_IP:8000 --session phone
```

Use the exercise selected in the app. The model's session ID must be `phone`; a set ID is optional. Keep the app open and the Pi/iPhone on the same Wi-Fi network; allow Local Network access on iPhone. A Pi preview URL is optional and separate from observations. A missing preview does not produce simulated footage or stop counting measured reps.

The app never auto-generates reps, switches to a demo on failure, or replaces ElevenLabs with the system voice. If voice is unavailable, it shows the problem and retains captions. Saved ElevenLabs clips can play offline after the first download. Changing the hosted voice/model invalidates clip selection when the app checks configuration. The app warms a bounded collection of prompts/cues in the background; an uncached slow cue is discarded if it is no longer relevant.

## Phone storage and coaching

Application Support contains `GymAndAI/Workouts/<workout UUID>.json`: sets with expected/actual reps, start/end timestamps, active duration excluding pauses, accumulated measured rep duration, and one rep object containing the source timestamp/time base, duration, model issues/evidence, measurements, baseline, and selected caption. Writes are atomic and serialized off the UI thread. Ending a workout waits for the pending history write. No workout events, frames, or per-rep history are uploaded to the hosted voice endpoint.

`contracts/coaching_policy.json` defines the count milestones, three-rep median baseline, fast/slow ratios, consecutive-rep threshold, and six-second cooldown. The Swift package includes the same JSON; a parity test guards against drift. Pace comparisons are relative to clean opening reps, reset after pauses/lost tracking/source changes, and require measured durations and camera timestamps. Form cues are approved model issue codes with probability ≥0.8 when supplied. Only one correction is selected at a time, with spaced reminders; raw unsupported/uncertain issues suppress motivational cues.

The hosted Gemini route accepts `message`, a phone-owned `history` list of `{role, text}`, and optional `assistant_id`. The Backboard profile creation route returns `assistant_id`; callers save that ID on the phone and pass it to memory endpoints. Vercel does not need a persistent SQLite profile mapping or an in-memory conversation. These APIs are ready for app conversation/onboarding integration; this change does not add a new chat screen.

## Development verification

```sh
.venv/bin/uvicorn main:app --host 127.0.0.1 --port 18081
swift test --package-path ios/GymAndAIKit
.venv/bin/python -m pytest backend/tests
```

An explicit Simulator launch can use `--gymni-hub --hosted-api-url http://127.0.0.1:18081 --exercise curl`. Local HTTP is allowed only for localhost test endpoints; the main app requires HTTPS for the hosted coach. Fixture observations used by automated tests are labeled `fixture` and are not evidence of Pi camera/model performance.

## Verified locally

The iPhone Simulator build passed with Xcode 26.4, including Watch and Live Activity. 29 Swift tests, 26 backend/script tests, and seven contract fixture validations passed. Main-flow UI integration passed with a local instance of the hosted API and real cached ElevenLabs MP3 clips: zero reps without observations, measured count/form captions, actual clip playback, pause/end, and persisted five-rep fixture JSON. Largest accessibility text settings were also checked. These are local checks; a Vercel deployment URL has not yet been supplied or verified, and the Pi itself was not part of the fixture test.
