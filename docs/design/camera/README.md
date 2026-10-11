# Full-screen workout camera

The active Camera display rotates to landscape. Reps, pause/rest, and recap restore portrait. Both displays share one session: switching only changes `WorkoutDisplay` and never restarts tracking or rep counting.

- Upper left: Apple Watch reading and sample age, or explicit Unavailable. Only live `apple_watch` readings within ten seconds are current.
- Upper right: exercise, completed/target reps, and Simulated/Recorded/Laptop source. iPhone camera sessions show an unmeasured state.
- Lower center: current tracking status and one coach cue. Phone camera errors use their real status text.
- Lower left: Reps, mute/unmute, and phone camera flip when applicable.
- Lower right: teal Pause and separate End.

Video preserves its aspect ratio. External MJPEG preview now fits rather than crops; the phone preview uses aspect-fit capture framing. A missing or stale preview has an explicit unavailable state while backend events can continue.

Panels and controls are opaque slate from `GymTheme`. Accessibility text sizes use concise metric labels and scrollable details above persistent controls. Controls adapt to two rows when necessary. No label is shrunk to force a fit, and all controls remain at least 44 points.

The complete current design and verification record is in [SwiftUI product redesign](../swiftui-product-redesign.md). The iOS 17 deployment target is unchanged. Historical captures in this directory show earlier iterations; new captures are under `../native/redesign/`.
