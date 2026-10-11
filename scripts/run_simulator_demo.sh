#!/usr/bin/env bash
set -Eeuo pipefail

EXERCISE="${1:-curl}"
SIMULATOR_NAME="${2:-}"
case "$EXERCISE" in
  curl|squat|deadlift) ;;
  *) echo "Exercise must be curl, squat, or deadlift." >&2; exit 2 ;;
esac

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"
PYTHON="$REPO_ROOT/.venv/bin/python"
HUB_URL="http://127.0.0.1:8000"  # the Simulator app itself listens here (Pi / laptop camera mode)
DERIVED_DATA="$REPO_ROOT/ios/DerivedData"
LOG_DIR="$REPO_ROOT/demo/logs"

if [[ ! -x "$PYTHON" ]]; then
  echo "Create .venv with Python 3.11 or 3.12 and install the ML runtime: .venv/bin/pip install -e 'ml[gru]'" >&2
  exit 1
fi
if [[ ! -f "$REPO_ROOT/ml/models/pose_landmarker_lite.task" ]] || \
   ! compgen -G "$REPO_ROOT/ml/models/recognition-*/metadata.json" >/dev/null; then
  echo "Copy the ignored model bundle into ml/models/ on this Mac, including pose_landmarker_lite.task and a recognition-* artifact." >&2
  exit 1
fi
if ! compgen -G "$REPO_ROOT/ml/models/form*-$EXERCISE-*/metadata.json" >/dev/null; then
  echo "No local form model for $EXERCISE was found under ml/models/. Copy the matching form artifact or choose an exercise with a delivered model." >&2
  exit 1
fi
if ! command -v xcodebuild >/dev/null || ! command -v xcrun >/dev/null; then
  echo "Xcode command-line tools are required. Run this script on the Mac that has Xcode installed." >&2
  exit 1
fi

"$PYTHON" - <<'PY'
import socket
with socket.socket() as connection:
    connection.settimeout(1)
    if connection.connect_ex(("127.0.0.1", 8000)) == 0:
        raise SystemExit("Port 8000 is already in use. Stop the previous demo with q or Ctrl+C, then run this script again.")
PY

mkdir -p "$LOG_DIR"
MODEL_LOG="$LOG_DIR/sim-$(date +%s)-model.log"
MODEL_PID=""
TAIL_PID=""

cleanup() {
  [[ -n "$TAIL_PID" ]] && kill "$TAIL_PID" 2>/dev/null || true
  [[ -n "$MODEL_PID" ]] && kill "$MODEL_PID" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

if lsof -nP -iTCP:8000 -sTCP:LISTEN >/dev/null 2>&1; then
  echo "Port 8000 is in use (an old backend?). The Simulator app needs it; stop that process first." >&2
  exit 1
fi

SIMULATOR_INFO="$(xcrun simctl list devices available -j | "$PYTHON" scripts/select_simulator.py "$SIMULATOR_NAME")"
IFS=$'\t' read -r SIMULATOR_ID SIMULATOR_NAME <<< "$SIMULATOR_INFO"
if [[ -z "$SIMULATOR_ID" ]]; then
  echo "No matching iPhone Simulator was found${SIMULATOR_NAME:+ for '$SIMULATOR_NAME'}. Available devices:" >&2
  xcrun simctl list devices available >&2
  exit 1
fi
echo "Using $SIMULATOR_NAME ($SIMULATOR_ID)."

xcrun simctl boot "$SIMULATOR_ID" 2>/dev/null || true
xcrun simctl bootstatus "$SIMULATOR_ID" -b
open -a Simulator --args -CurrentDeviceUDID "$SIMULATOR_ID"
xcodebuild \
  -project "$REPO_ROOT/ios/GymAndAI.xcodeproj" \
  -scheme GymAndAI \
  -destination "platform=iOS Simulator,id=$SIMULATOR_ID" \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO build

APP_PATH="$DERIVED_DATA/Build/Products/Debug-iphonesimulator/GymAndAI.app"
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_PATH/Info.plist")"
xcrun simctl install "$SIMULATOR_ID" "$APP_PATH"
xcrun simctl terminate "$SIMULATOR_ID" "$BUNDLE_ID" >/dev/null 2>&1 || true
xcrun simctl launch "$SIMULATOR_ID" "$BUNDLE_ID" --gymni-hub --exercise "$EXERCISE"

for _ in $(seq 1 40); do
  curl --silent --fail "$HUB_URL/health" >/dev/null && break
  sleep 0.5
done
curl --silent --fail "$HUB_URL/health" >/dev/null || { echo "The Simulator app is not listening on $HUB_URL." >&2; exit 1; }

echo "Simulator workout started; the iPhone app counts reps. Model log: $MODEL_LOG"
echo "Close the model camera window with q to stop."
"$PYTHON" -m fitness_ml run \
  --source live \
  --exercise "$EXERCISE" \
  --session phone \
  --post "$HUB_URL" >"$MODEL_LOG" 2>&1 &
MODEL_PID=$!
tail -f "$MODEL_LOG" &
TAIL_PID=$!
wait "$MODEL_PID"
MODEL_PID=""
