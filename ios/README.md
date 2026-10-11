# Gym&I iPhone app

Open **GymAndAI.xcodeproj** in Xcode, select the **GymAndAI** scheme, choose your iPhone, and run. The app targets iOS 17+ with Swift 6 and the installed Xcode 26.4 toolchain. Select your development team in Signing & Capabilities for a physical device. No provider keys or signing secrets belong in the iOS project.

## Onboarding

First launch opens personal measurements and eight training questions after the upward logo animation. The review matches Atlas to strength, Flex to muscle growth, and Pip to fitness; you can change the match before confirming. Answers stay on the iPhone, unfinished progress resumes, and Settings → Training profile lets you edit. See [onboarding behavior](../docs/ios/ONBOARDING.md).

## Main workout setup

The main app defaults to **Camera device** mode on both Simulator and iPhone. Old saved demo, phone-only, and laptop choices migrate to this mode on normal launch. Settings contains the Pi preview, hosted API URL, audio, companion, Health, and Watch controls. Product settings offer no demo/laptop mode selector.

See [Pi + iPhone + Vercel setup](../docs/PI_IPHONE_VERCEL.md) for deployment and camera commands:

1. Vercel deploys the root `main.py` FastAPI app with ElevenLabs, Gemini, and Backboard keys from `.env` in its environment.
2. In Settings → Hosted coach, enter the HTTPS deployment URL and check the connection.
3. Start a workout. The app displays this iPhone's Wi-Fi address while waiting for the Pi.
4. On the Pi, run `fitness-ml run --source live --exercise curl --post http://IPHONE_IP:8000 --session phone` with the trained model bundle installed. Use the exercise selected on iPhone.

The Pi and iPhone must share a network. Allow Local Network access and keep the app open. Backgrounding an active workout pauses it. Only ready, recognized, trusted observations commit reps. No timer simulates movement and no connection failure starts a demo.

## Voice and local storage

All production workout speech plays ElevenLabs MP3 clips from the stateless hosted gateway. Form codes, measured count milestones, and sustained pace changes choose approved short captions on iPhone. Workout coaching uses **zero Gemini tokens**. Gemini is available for conversation through the hosted API; a conversation/onboarding screen is separate work.

The phone caches clips under Application Support `GymAndAI/Voice` for reuse across launches. A configuration revision invalidates selection after a hosted voice/model change. Missing audio keeps captions visible and reports the problem; there is no native speech fallback. Slow count/correction responses are discarded after six seconds or when the relevant rep/set/issue/tracking changes. Mute, pause, end, and scene changes cancel pending playback.

Application Support `GymAndAI/Workouts/<UUID>.json` stores sets and committed reps, including target/actual counts, active time excluding pauses, measured rep durations, source timestamps, model evidence and measurements, and selected captions. Writes are serialized, atomic, and flushed on workout end. The voice endpoint receives only approved cue codes and count/target numbers, never camera frames or workout journals.

## Workout UI

Today, exercise selection, Settings, last-session Progress, explicit pause/rest/resume, and recap remain available. Reps and Camera views share the same local workout state. The optional Pi MJPEG preview only displays video; it does not count reps or run inference. Missing/stale preview is shown as unavailable, while observations can continue independently. Landscape Camera view returns to portrait for Reps, rest, and recap.

Dynamic Type, scrolling layouts, accessible control labels, and 44-point touch targets remain supported. Settings → Companion selects Pip, Atlas, or Flex; companion selection does not change measured counting policy.

## Apple Health and Watch

Settings → Apple Health requests permission to read heart rate using HealthKit. A completed permission request does not establish that read access was granted. The iPhone and Watch targets retain their HealthKit entitlements. Install the companion on the paired Watch and enable **Use Watch heart rate**. Missing, stale, invalid, or unrelated samples show unavailable; no synthetic BPM is produced.

Live Activity updates and Watch synchronization remain attached to workout state. Neither the Pi nor Vercel owns the phone's rest timer or local workout lifecycle.

## Music during coaching

MP3 playback temporarily ducks other audio and releases the audio session on completion/cancellation. Physical-device verification is needed for music/AirPods routing: play music, start a Pi workout, hear a measured cue, then mute/pause/end and confirm audio stops and the music returns. Simulator checks do not establish physical audio routing.

## Verification

```sh
swift test --package-path ios/GymAndAIKit
.venv/bin/python -m pytest backend/tests
.venv/bin/python contracts/validate.py
```

`MainHubTests` exercises the actual main-app defaults, absence of a demo picker, zero reps without observations, measured count/form captions, ElevenLabs playback state, pause/end, and large-text settings. Run the hosted app locally on port 18081 with `.env` configured to enable that integration check:

```sh
.venv/bin/uvicorn main:app --host 127.0.0.1 --port 18081
xcodebuild -project ios/GymAndAI.xcodeproj -scheme GymAndAI \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.4' \
  -only-testing:GymAndAIUITests/MainHubTests test
```

Fixture observations are labeled `fixture`; tests do not measure real Pi camera/model accuracy. The iPhone camera positioning mode remains available to UI tests (`--gymni-ui-testing`); `--gymni-hub` starts a live camera-device session. Demo and laptop-backend modes have been removed. Local HTTP hosted URLs are limited to localhost/127.0.0.1. Normal app operation requires no laptop Python backend.
