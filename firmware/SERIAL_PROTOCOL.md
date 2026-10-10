# Pico ⇄ laptop serial protocol (v1)

USB CDC serial (the Pico's native USB), 115200 baud nominal (ignored by CDC). UTF-8, **one JSON object per line**, `\n` terminated, max 256 bytes per line. Either side ignores lines that fail to parse and fields it doesn't know.

## Pico → laptop

```json
{"event":"hello","fw":"0.1"}
{"event":"button_pressed","button":"a"}
```

- `hello` on boot/reconnect so the bridge can push current state immediately.
- `button_pressed` once per debounced press (debounce on the Pico, ~30 ms; tune on the real button). No long-press semantics yet.
- The bridge maps a press to a backend command: `active` → `pause`, `paused` → `resume`, `ready` → nothing (start comes from the phone so exercise/target are known). Each press gets a fresh `command_id` (`origin: "pico"`).

## Laptop → Pico

```json
{"state":"active","exercise":"curl","reps":3}
```

Sent on every `session.state`, `exercise.changed`, `rep.completed` event and after `hello`. `reps` is the **backend-committed** count; the Pico only displays it and never counts. `exercise` may be `null`.

## Reconnect

The bridge reopens the port every 2 s when it disappears and re-sends the latest state on `hello`. Unplugging the Pico must not affect the session.

Schemas: `contracts/gymai.schema.json` `$defs/pico_in`, `$defs/pico_out`.
