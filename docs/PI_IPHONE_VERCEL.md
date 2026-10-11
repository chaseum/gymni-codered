# Main app: Pi camera, iPhone workout, hosted coach

The Pi runs `fitness-ml` with the trained model. It sends observations directly to the iPhone over the same Wi-Fi network. The iPhone commits trusted reps, selects coaching, manages rest and the Watch, and saves workout JSON. Vercel supplies ElevenLabs audio, Gemini chat, and Backboard memory. A laptop backend is not part of the workout path.

## Vercel deployment

Import this repository into Vercel with the **repository root** as the project root. The root `main.py` exports the stateless FastAPI application. `requirements.txt` installs only API dependencies. `.vercelignore` excludes the iOS app, ML runtime/models, media, local keys, and private state. Do not use `gymai_backend.app:app` as the cloud entry point: that legacy app owns in-memory laptop sessions.

Add these values from your local ignored `.env` to the Vercel project's environment settings, then deploy:

- `ELEVENLABS_API_KEY`, `ELEVENLABS_VOICE_ID`, `ELEVENLABS_MODEL_ID`
- `GEMINI_API_KEY`, `GEMINI_MODEL_ID`, `BACKBOARD_API_KEY`
- `GYMAI_TOKEN` if you use an app access token

Provider keys remain on Vercel. Do not put them in Swift, the Pi command, or an app configuration file. The hosted workout voice route always uses approved text and zero Gemini tokens; `GYMAI_REPHRASE_CUES` does not enable rephrasing on this route.

The app is preset to `https://gymni-coach.vercel.app` (`WorkoutSession.hostedAPI`); nothing is entered on the phone. At launch it checks `GET /api/coach/configuration` and downloads the workout clips from `POST /api/coach/voice`, saving them on the iPhone. `vercel.json` pins the FastAPI preset so the root `main.py` is built. A simulator build can point elsewhere with `--hosted-api-url`.

## Pi camera

The tripod joins the paired iPhone's saved Personal Hotspot and launches the repository's camera/model runtime at boot. Enable the hotspot, power the Pi, open Gym&I, and tap **Start workout**. No address or website entry is required. Allow Local Network access on iPhone. See [tripod installation and connection behavior](../pi/README.md).

For a development camera with the compatible ML package and the `pi` extra installed:

```sh
fitness-ml run --source live --discover-phone --no-window --preview-port 8081
```

The phone supplies the exercise, session, set, and pause/resume controls. Bonjour and a DHCP gateway fallback reconnect automatically. Preview uses the camera connection's peer address. The active workout shows the live Pi camera; tap the picture or Live camera to expand it. The preview retries a dropped stream automatically and hides frames older than three seconds. Keep Gym&I open while working out: iOS background suspension still applies. A missing preview does not produce simulated footage or stop measured counting.

The app never auto-generates reps, switches to a demo on failure, or replaces ElevenLabs with the system voice. If voice is unavailable, it shows the problem and retains captions. Saved ElevenLabs clips can play offline after the first download. Changing the hosted voice/model invalidates clip selection when the app checks configuration. The app warms a bounded collection of prompts/cues in the background; an uncached slow cue is discarded if it is no longer relevant.

Tracking captions settle after two continuous seconds of readiness or three seconds of missing/uncertain tracking. Tracking announcements are spaced at least twelve seconds apart, wait for other audio to finish, and only announce a recovery if the preceding loss was spoken. An initial missing view uses positioning guidance, not an interruption announcement. Raw tracking still validates reps immediately; these presentation delays never permit an untrusted rep to count.

## Phone storage and coaching

Application Support contains `GymAndAI/Workouts/<workout UUID>.json`: sets with expected/actual reps, start/end timestamps, active duration excluding pauses, accumulated measured rep duration, and one rep object containing the source timestamp/time base, duration, model issues/evidence, measurements, baseline, and selected caption. Writes are atomic and serialized off the UI thread. Ending a workout waits for the pending history write. No workout events, frames, or per-rep history are uploaded to the hosted voice endpoint.

Completed journals go to the separate `POST /api/workouts/summary` route. It rejects incomplete/untrusted records and returns a deterministic measured summary. A matching `<workout UUID>.summary.json` marks successful processing; failures retain the journal for retry on reconnection/app launch. History and summaries stay on iPhone. This endpoint does not store cloud workout history or process video.

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

The iPhone Simulator build passed with Xcode 26.4, including Watch and Live Activity. 29 Swift tests, 26 backend/script tests, and seven contract fixture validations passed. Main-flow UI integration passed with a local instance of the hosted API and real cached ElevenLabs MP3 clips: zero reps without observations, measured count/form captions, actual clip playback, pause/end, and persisted five-rep fixture JSON. Largest accessibility text settings were also checked. These earlier checks used fixtures. The tripod integration additionally passed 55 ML tests, 26 backend tests, and 37 Swift tests. A signed physical-iPhone build and installation succeeded. The physical Pi joined the iPhone hotspot, received workout controls, and started repository-model inference. Its boot service and automatic hotspot profile are enabled. The hosted summary route was built, smoke-tested, and promoted to the preset production domain. The local camera stream delivered 13 JPEG frames in a three-second check, and completed zero-rep phone journals received hosted summaries. A real exercise trial remains required to assess form/count accuracy.
