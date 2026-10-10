# Firmware (Taher)

Raspberry Pi Pico / RP2040: Grove button + Grove display first; accelerometer / ultrasonic only after the main demo works. The Pico is a control/display accessory — it never runs vision or counts reps.

**Before writing drivers:** identify the exact board (Pico vs Pico W vs Grove Shield), display model (e.g. 16x2 LCD vs OLED, I²C address), button pin, and sensor part numbers; write them here. No drivers are committed yet because none of that is verified.

Protocol: [`SERIAL_PROTOCOL.md`](SERIAL_PROTOCOL.md).

Still unassigned: the laptop-side **serial bridge** (reads Pico lines → `POST /api/sessions/{id}/commands`; subscribes to `/ws/workout` → writes state lines). It is ~50 lines of Python with `pyserial` + `websockets`; Taher and Tyler decide who owns it.

Suggested layout once the hardware is confirmed: `firmware/main.py` (MicroPython) or `firmware/src/` (C SDK), plus a pin map table in this README.
