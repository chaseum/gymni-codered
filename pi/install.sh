#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
runtime_python=${1:?Usage: pi/install.sh /absolute/path/to/verified/python3.12}
"$runtime_python" -c 'import sys, mediapipe; assert sys.version_info[:2] == (3,12) and mediapipe.__version__ == "0.10.18"'
wheel_options=()
if [[ -n ${2:-} ]]; then wheel_options=(--no-index --find-links "$2"); fi
"$runtime_python" -m pip install --disable-pip-version-check --no-cache-dir --target "$root/pi/vendor" "${wheel_options[@]}" 'zeroconf>=0.132,<1'
cat > "$root/pi/gymni-tripod.service" <<EOF
[Unit]
Description=Gym&I tripod camera and repository form model
After=NetworkManager.service

[Service]
User=$(id -un)
WorkingDirectory=$root
ExecStart=$runtime_python $root/pi/start.py
Restart=always
RestartSec=5
KillSignal=SIGINT
TimeoutStopSec=10
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=multi-user.target
EOF
sudo install -m 644 "$root/pi/gymni-tripod.service" /etc/systemd/system/gymni-tripod.service
sudo systemctl daemon-reload
sudo systemctl enable --now gymni-tripod.service
