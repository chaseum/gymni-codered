"""Choose an available iPhone, preferring the device already in use."""

import json
import re
import sys


def select_device(devices: dict, requested: str = "") -> dict | None:
    candidates = []
    for runtime, group in devices.items():
        if ".iOS-" not in runtime:
            continue
        version = tuple(int(n) for n in re.findall(r"\d+", runtime))
        for device in group:
            matches = requested in (device["name"], device["udid"]) if requested else device["name"].startswith("iPhone")
            if device["isAvailable"] and matches:
                candidates.append((device["state"] == "Booted", device.get("lastBootedAt", ""), version, device))
    if not candidates:
        return None
    return max(candidates, key=lambda candidate: candidate[:3])[3]


if __name__ == "__main__":
    device = select_device(json.load(sys.stdin)["devices"], sys.argv[1] if len(sys.argv) > 1 else "")
    if device:
        print(f"{device['udid']}\t{device['name']}")
