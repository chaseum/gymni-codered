# Gym&AI — core-screen design specification

Status: visual design reference, not a functional app. All metrics, tracking states, freshness labels, countdowns, and workout details in the board are illustrative prototype data.

## Deliverables

- [Three-screen board](gym-ai-core-screens-v1.png): 1536 × 1024 PNG, Today / Workout / Rest.
- [Exact generation prompt](gym-ai-core-screens-v1.prompt.txt): generated with the built-in image-generation tool, without reference images or post-generation image editing.

## Visual system

Apple Fitness-inspired dark surfaces and glanceable metrics, with an original cyan Octobuddy. Use restrained panels and one primary action per state. SF Pro/system typography and SF Symbols are the intended native implementation choices. The generated raster is a visual reference; the specifications below define implementation targets rather than measurements taken from its pixels.

| Token | Value | Use |
|---|---|---|
| Background | `#080A0C` | Main app canvas |
| Surface | `#1C1F23` | Workout recommendation and coaching panels |
| Primary text | `#F5F7F8` | Headings, metrics, controls |
| Secondary text | `#A5ABB3` | Supporting labels, metadata |
| Primary action | `#D7FC42` | Start / Pause / Resume; use dark text |
| Coach accent | `#8DE4EB` | Octobuddy, coach label, links |
| Heart icon | `#FF577D` | Heart-rate identifier, never a safety-zone indicator |

- Typography targets: 36–40 pt bold main headline; 96–112 pt bold rep count; 64–72 pt countdown; 17 pt body/buttons; 13–15 pt metadata. Use tabular numbers for changing metrics.
- Layout targets: 20–24 pt side padding, 16–24 pt between sections, 12 pt between related controls, approximately 20 pt panel corners. Keep native safe areas clear.
- Primary buttons: 56 pt minimum height, full available width. Secondary controls: 48 pt minimum height. Settings and other icon actions: at least 44 × 44 pt hit area.
- Octobuddy: same head, eyes, short tentacles, and cyan coloring throughout. Friendly on Today, focused and smaller beside the cue, relaxed/closed eyes during Rest.
- Motion for the later app: restrained state transitions; no constant bouncing. Respect Reduce Motion, Dynamic Type, and VoiceOver. Allow scrolling at larger text sizes rather than shrinking text or clipping controls.

## Screens and intended interactions

| Screen | Hierarchy and exact key copy | Intended action |
|---|---|---|
| Today | “Ready when you are.”; Octobuddy; “Let's make time for you.”; one “TODAY'S WORKOUT” panel with “Curl practice”, “20 min · Dumbbells”, “View plan” | Start workout opens positioning before the set. View plan opens plan detail/review. Settings opens device/preferences sheet. Today / Progress are the only tabs. |
| Active Workout | “Biceps curl”; “Set 1 of 3”; “Tracking ready”; dominant “6” / “of 10 reps”; one cue, “Keep your upper arm steady.”; “112 bpm” / “Updated 2s ago” | Pause requests the backend's paused/rest state. End workout requests session end. Transition reflects acknowledgement; UI does not independently count reps. Hide the main tab bar during a set. |
| Rest | “Take a breath.”; resting Octobuddy; “00:45” / “Rest remaining”; “Continue when ready.”; optional “Water if you need it.” | Resume workout explicitly requests resume; tracking reacquires before counting. More time extends the configured rest. End workout ends the session. Timer expiry displays “Continue when ready.” and never auto-resumes. |

The board's back chevrons indicate navigation, not an implicit session end: backing out of an active session must preserve its state. Raw pose data, connection diagnostics, and detailed history stay outside these primary layouts. The v2 interaction below updates the original camera-preview decision.

## v2 — Reps / Camera switch

- Active Workout has a persistent **Reps | Camera** segmented control below the exercise/set heading. Reps is selected when a new session starts.
- Reps shows the oversized completed/target counter. Camera shows the external webcam preview with a compact rep overlay; the same caption, heart-rate status, spoken coaching, Pause and End controls remain available below it.
- Switching views never starts, pauses, ends, resets, or increments the workout. The selection survives rest/resume within the same session.
- Prototype camera imagery is explicitly illustrative. The interactive mockup never accesses a camera. Native Demo mode likewise shows a labeled illustration, never fabricated live footage.
- Native Laptop mode accepts an optional MJPEG preview URL. Missing, failed, or stale feeds show an unavailable state while backend workout events continue. Frames older than three seconds are hidden. Recorded sessions remain labeled recorded.
- The backend currently has no video endpoint. Publishing a feed from the same frames used by the analyzer is the remaining integration task; opening the webcam a second time in another process is not the proposed design.
- Updated mockup screenshots: `gym-ai-reps-view-v2.png` and `gym-ai-camera-view-v2.png`. The original v1 board is retained as design history.

## v3 — Full-screen landscape Camera

- Selecting Camera opens a horizontal, full-screen surface. The video background extends edge to edge; its original aspect ratio is preserved, with letterboxing when necessary to keep the body visible.
- Upper left: Apple Watch label, BPM when fresh, and sample age. Missing/stale Watch readings show **Unavailable** rather than retaining a misleading number. Demo mode does not invent Watch readings.
- Upper right: completed/target reps, with **Illustrative data** in Demo mode. Counts still come from the shared session.
- Bottom overlay: one coaching caption and **Reps**, mute/unmute, **Pause**, and **End** controls. Touch targets stay at least 44 points and readable content respects device safe areas.
- Reps returns to the portrait counter. Rest and recap use portrait; resuming retains the selected view. Rotation and view changes never restart analysis or alter rep state.
- Camera preview failure remains visible independently of tracking/rep events. An unavailable feed does not become false live video.
- Reference: `gym-ai-camera-landscape-v3.png`; native Simulator captures are in `native/`.

## v4 — Liquid Glass

- Use native SwiftUI Liquid Glass on iOS 26+ for the upper-left Watch tile, upper-right rep tile, and floating coaching caption. Use the regular variant to preserve text legibility over changing video.
- Use native `glassProminent` with lime tint for primary actions, including Start/Pause/Resume, and `glass` for secondary buttons. Mute/unmute has a circular glass surface.
- Each surface floats directly over the camera. Keep the coach caption separate from the button row, avoiding glass panels behind glass buttons. Group the camera surfaces in a `GlassEffectContainer`.
- Retain 44-point minimum touch targets, Dynamic Type, freshness states, and workout behavior. Reduce Transparency replaces translucent tiles with opaque surfaces and standard button styles. iOS 17–25 keeps material tiles and standard buttons.
- Browser mockup blur/highlights approximate the appearance; they do not run Apple's native rendering. Screenshot: `gym-ai-camera-liquid-glass-v4.png`.
- Implementation follows [Apple's custom Liquid Glass guidance](https://developer.apple.com/documentation/SwiftUI/Applying-Liquid-Glass-to-custom-views).

## State and accessibility notes

- Keep a single current coaching cue. Replace resolved/stale guidance instead of accumulating messages.
- Tracking loss replaces the ready label with a clear positioning message; unavailable observations must not leave a confident correction visible.
- Stale/missing heart rate shows “Heart rate unavailable” instead of keeping an old number presented as fresh. Status has a text label, not color alone.
- Never translate heart rate into a green/red medical-clearance state or a hydration diagnosis.
- Quiet-coach and water-reminder preferences live in settings. Spoken commands remain accessible through a discoverable microphone action in the later app.
- Retain “Prototype data” labels in fixture-driven previews. Show honest source/freshness status when real data is connected.

## Review completed

Inspected the generated board for legible/correct copy, control visibility, whitespace, screen alignment, coherent hierarchy, and mascot consistency. All three requested screens and controls are present; the board and each screen identify prototype data. No revision was needed.

The defined text/background token pairs exceed 4.5:1 contrast. This checks the specification colors, not every raster pixel or a running SwiftUI implementation. Dynamic Type, VoiceOver, and real touch-target behavior require verification when the app is built.

## Swift skill setup

Installed SwiftUI Pro v2.0.0 using the requested `npx skills add` command with `--agent codex --global --yes`. Canonical installation: `/Users/bryan/.agents/skills/swiftui-pro`; a link at `/Users/bryan/.codex/skills/swiftui-pro` exposes it through this Codex installation's skills directory. Verified `SKILL.md` and supporting resources are readable.

Use `swiftui-pro` and `code-tips-skill` together for subsequent Swift work, respecting the actual installed SDK/toolchain. This deliverable adds no Swift app, networking, Watch integration, or functional navigation.
