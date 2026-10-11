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
BACKEND_URL="http://127.0.0.1:8000"
BUNDLE_ID="com.gymandai.hackathon"
DERIVED_DATA="$REPO_ROOT/ios/DerivedData"
LOG_DIR="$REPO_ROOT/demo/logs"
SESSION_ID="sim-$(date +%s)-$$"

if [[ ! -x "$PYTHON" ]]; then
  echo "Create .venv with Python 3.11 or 3.12 and install backend + ML: .venv/bin/pip install -e 'backend[dynamic-cues]' -e 'ml[gru]'" >&2
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
BACKEND_LOG="$LOG_DIR/$SESSION_ID-backend.log"
MODEL_LOG="$LOG_DIR/$SESSION_ID-model.log"
BACKEND_PID=""
MODEL_PID=""
TAIL_PID=""

cleanup() {
  [[ -n "$TAIL_PID" ]] && kill "$TAIL_PID" 2>/dev/null || true
  [[ -n "$MODEL_PID" ]] && kill "$MODEL_PID" 2>/dev/null || true
  [[ -n "$BACKEND_PID" ]] && kill "$BACKEND_PID" 2>/dev/null || true
  [[ -n "$BACKEND_PID" ]] && wait "$BACKEND_PID" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

# Keep this loopback-only Simulator demo unauthenticated; no token is passed to iOS.
export GYMAI_TOKEN=""
export GYMAI_DYNAMIC_CUES="1"
"$PYTHON" -m gymai_backend.prepare_audio --exercise "$EXERCISE" || \
  echo "Continuing with device speech fallback for unavailable voice clips."
"$PYTHON" -m uvicorn gymai_backend.app:app --app-dir "$REPO_ROOT/backend" --host 0.0.0.0 --port 8000 --timeout-graceful-shutdown 2 >"$BACKEND_LOG" 2>&1 &
BACKEND_PID=$!

ready=0
for _ in $(seq 1 40); do
  if ! kill -0 "$BACKEND_PID" 2>/dev/null; then
    echo "Backend exited during startup. See $BACKEND_LOG" >&2
    exit 1
  fi
  if curl --silent --fail "$BACKEND_URL/health" >/dev/null; then
    ready=1
    break
  fi
  sleep 0.5
done
if [[ "$ready" != 1 ]]; then
  echo "Backend did not become ready. See $BACKEND_LOG" >&2
  exit 1
fi

GYMAI_SESSION_ID="$SESSION_ID" GYMAI_BACKEND_URL="$BACKEND_URL" "$PYTHON" - <<'PY'
import os
import httpx

response = httpx.post(
    f"{os.environ['GYMAI_BACKEND_URL']}/api/sessions",
    json={"session_id": os.environ["GYMAI_SESSION_ID"]},
    timeout=5,
)
response.raise_for_status()
PY

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
xcrun simctl install "$SIMULATOR_ID" "$APP_PATH"
xcrun simctl terminate "$SIMULATOR_ID" "$BUNDLE_ID" >/dev/null 2>&1 || true
xcrun simctl launch "$SIMULATOR_ID" "$BUNDLE_ID" \
  --gymni-laptop --backend-url "$BACKEND_URL" --session-id "$SESSION_ID" --exercise "$EXERCISE"

echo "Simulator workout started. Live backend and model logs: $LOG_DIR"
GYMAI_SESSION_ID="$SESSION_ID" "$PYTHON" - <<'PY'
import os
from gymai_backend.workout_history import history_path
print(f"Workout JSON: {history_path(os.environ['GYMAI_SESSION_ID'])}")
PY
echo "Close the model camera window with q to stop the workout and laptop backend."
"$PYTHON" -m fitness_ml run \
  --source live \
  --exercise "$EXERCISE" \
  --session "$SESSION_ID" \
  --post "$BACKEND_URL" >"$MODEL_LOG" 2>&1 &
MODEL_PID=$!
tail -f "$MODEL_LOG" &
TAIL_PID=$!
wait "$MODEL_PID"
MODEL_PID=""
