# Raspberry Pi software assessment

Inspected on 2026-10-11 against the current workspace at commit `5ea401d`, including its uncommitted iPhone changes. This records the initial read-only assessment. The subsequent [standalone tripod implementation](../pi/README.md) installed current repo source and matching model weights, enabled the boot service, saved the iPhone hotspot connection, and replaced manual addressing with automatic discovery. Measurements below describe the earlier assessment runs, not accuracy validation of the new integration.

## Access and hardware

The Pi is `tamousta.local`, username `tamousta`. The working wired connection uses Mac Internet Sharing from Wi-Fi to **USB 10/100/1000 LAN**. Its observed DHCP address is `192.168.2.2`; the Mac's Ethernet bridge is `192.168.2.1`. Addresses can change after reconnecting.

```bash
ssh tamousta@192.168.2.2
```

Enter the Pi password interactively. Do not put it in scripts or documentation.

- Raspberry Pi 4 Model B Rev 1.5, 4 GB RAM, 64-bit Debian 13.
- Logitech Brio 101 USB webcam on `/dev/video0`.
- About 2.9 GB free on the root filesystem at inspection time.
- Wi-Fi was down. No inference process or Gym&I startup service was running when accessed.
- Mac Internet Sharing remains enabled for this connection.

## Installed software

| Pi directory | Purpose | Integration implications |
| --- | --- | --- |
| `/home/tamousta/gymai-curls-pi4` | Custom curl coach and a newer three-exercise local coach (`gym_pi.py`, launched by `start-gym.sh`) | Own counting, local display and optional speech; no observation POST or network preview interface. |
| `/home/tamousta/gymai-original-pi4` | Original `fitness-ml` wheel and nine trained artifacts, launched by `start-original.sh` | Already emits contract observations and supports `--post`; closest match to this repo. |

The original launcher's nine model weight files match this repo's ignored `gymai-models-20261011-011650/models` files by SHA-256. There is no new model format to integrate. The three-exercise coach uses the recognition, curl, squat and deadlift artifacts from that bundle.

Both installations use `/home/tamousta/gymai-curls-pi4/.venv-pi4`: Python 3.12.15, MediaPipe 0.10.18, OpenCV 4.11.0.86, NumPy 1.26.4 and PyTorch 2.14.1+cpu. Scikit-learn, joblib and zeroconf are absent.

The existing launchers deliberately preserve this older MediaPipe runtime. `launch_original.py` supplies compatibility aliases for the landmark names used by `fitness_ml.pose`, then loads the original wheel. Keep that adapter when using repo code with this environment. Do not install the repo's default dependency pins over this working environment without a separate compatibility check.

## Verification on the actual Pi

- `bash start-gym.sh --check`: pose and recognition/curl/squat/deadlift models loaded and inferred successfully; peak process RAM **398 MB**. First measured recognition inference was 425 ms; form inferences were 35–54 ms. These are initialization checks on synthetic inputs, not accuracy results.
- Custom coach, muted and headless, 80 live frames at its default 480×360 analysis size: reported 5.9 then 7.7 analyzed FPS. Camera capture negotiated 640×480. The 8 FPS setting is a cap, not a guaranteed rate.
- Original pipeline, 40 live frames: reported **6.8 FPS**, mean processing latency **110 ms**, p95 **127.8 ms**. All 40 observations passed the current `contracts/gymai.schema.json`; source timestamps increased monotonically.
- No completed reps were demonstrated. The original run had 18 lost, 17 unassessable and 5 ready frames; no human-annotated workout was performed. These checks establish loading, capture and payload compatibility, not recognition/form accuracy.
- Current Mac `swift test --filter Hub`: **7 tests passed**, including HTTP observation acceptance, deduplication, pause behavior, coaching and workout journaling. This was not a physical iPhone end-to-end test.

## Recommended integration

Use **Pi camera and inference → iPhone `HubServer` on port 8000 → `HubSession` commits reps and selects coaching**. Reuse the original model artifacts and working Pi runtime; bring in the current repo's ML runner and preview module with the existing MediaPipe compatibility adapter.

The older Pi runner differs in two material ways:

1. Even with `--exercise curl`, it loads recognition and can emit `unknown`/`other`. The audit produced 38 unknown and 2 other observations. The phone counts only its selected exercise. The current `ml/src/fitness_ml/__main__.py` fixes manual selection by avoiding recognition unless explicitly requested.
2. It lacks `--preview-port`; the current repo's runner and `preview.py` provide MJPEG preview. Configure the phone's Pi preview URL separately, e.g. `http://<reachable-pi-address>:8081`.

The current phone and ML transport use an explicit address, not automatic Bonjour discovery or exercise switching. Start a phone workout, use the address shown by the app as `--post http://<phone-address>:8000 --session phone`, and select the same exercise on the Pi. Repeat/change the Pi command when the exercise changes until remote selection is implemented.

For a physical-phone demo, put the Pi and iPhone on a network where they can reach each other, such as an appropriate private Wi-Fi network or hotspot. Mac Internet Sharing currently supplies a separate Ethernet subnet; discovery and phone-to-Pi preview access across it have not been verified.

Keep the custom coach as a standalone fallback. Its curl assessment has its own rep counter and its generic good/bad form scores do not map to specific issue codes. Reusing its displayed count or spoken text as phone events would need a deliberate adapter and additional validation. The original observation pipeline avoids that second integration.

Next implementation work: stage current ML code separately on the Pi, preserve the working runtime adapter, verify fixed manual exercise output and preview on the Pi, then test a known number of actual reps, pause/resume and exercise changes against a physical iPhone. Neither a service installer nor automatic startup is currently configured on this Pi.

## Existing standalone commands

Run these after logging into the Pi; they are the existing programs, not the completed phone integration.

```bash
cd ~/gymai-curls-pi4
bash start-gym.sh --exercise curl --no-window --mute
```

```bash
cd ~/gymai-original-pi4
bash start-original.sh run --source live --camera 0 --exercise curl --no-window
```

Ctrl+C stops either command. Prefer `start-gym.sh` for the current standalone coach; the older original command retains the recognition issue described above.
