# Gym&I companion animations

Six reusable animations for each of Atlas, Flex and Pip: **18 clips total**. Original artist files are preserved. These follow the selected V5 models and the app's hands-free fitness coaching flow.

| Clip | Duration | Playback | Reuse |
|---|---:|---|---|
| `idle` | 2.4 s | Loop | Float, Today, waiting, listening, active workout |
| `encouraging` | 2 s | Once | Coaching and gentle guidance |
| `celebration` | 2.4 s | Once | Verified set/workout completion and achievements |
| `rest` | 3 s | Loop | Sleep, recovery and paused sessions |
| `happy` | 2 s | Once | Positive acknowledgement and improved form |
| `sad` | 2.4 s | Once | Empathy for user-reported disappointment |

All clips use 30 fps skeletal samples in GLB and USDZ. Idle/rest have matching loop endpoints. One-shot gestures ease into and out of their neutral pose. Rest keeps closed eyes and a quiet breathing pose; use a transition when entering it. Happy/sad also deform the mouth corners. Review GIFs repeat every clip for inspection; production must respect the loop flags.

Atlas is the fuzzy strength coach: restrained hover and deliberate gestures. Flex is an elastic matte ribbon focused on building muscle: counterbends and curled-hand gestures. Pip is the glossy fluid fitness companion: buoyant motion and gentle orbit wobble. Sad is an empathetic reaction, never a punishment for form or performance. Companions do not count reps or determine health status.

## iOS package

Bundle only the four files in `ios-package/`: three USDZs and `CompanionClips.json`, **4,271,121 bytes combined (4.27 MB)**. Geometry is stored once per companion. Animation uses joint transforms, with no mesh caches, simulations, videos or texture dependencies.

| Companion | Triangles | Joints | USDZ |
|---|---:|---:|---:|
| Atlas | 38,656 | 12 | 2.54 MB |
| Flex | 15,358 | 16 | 1.14 MB |
| Pip | 16,116 | 12 | 0.59 MB |

Each character folder also contains an editable `.blend`, a GLB with six named animations, a USDZ with one shared skeletal timeline, and a manifest. Atlas's reduced carpet strands approximate its detailed original fuzz. Atlas has four materials; Flex/Pip have three each. Sources, skeleton samples, PNGs and GIFs are authoring/review artifacts and must stay outside the app bundle.

Open `review/index.html` to compare all six animations side by side.

Celebration confetti and rest's floating Z letters are shared SwiftUI overlays in `ios/GymAndAI/Mascot/CompanionEffectsView.swift`, connected to the existing `PipView`. One Canvas draws 18 confetti pieces for a 2.4-second burst, or three Z glyphs on a three-second rest loop. Its animation schedule requests at most 30 updates per second. The burst's schedule pauses after completion; the parent removes effects offscreen/inactive or under Reduce Motion. There are no added textures, dependencies or USDZ bytes. Reuse the same overlay for Atlas/Flex when their baked models are integrated. Review GIFs simulate the overlay for all three models; they are not app resources.

## RealityKit handoff

The iOS app now bundles the three USDZs and clip metadata. Settings > Companion selects Pip, Atlas or Flex. `MascotState` maps idle, coaching, celebrate and rest to the first four clips; happy/sad are also available to callers. Sad is only for an appropriate user-reported emotional context. Other contexts reuse these six clips. The Windows bundle check passed; native playback still needs Mac/iPhone validation.

`PipMotion` now replaces the procedural driver with trimmed skeletal clips. Cached async loading, selected-companion fallback, offscreen cancellation and Reduce Motion are retained. Essential workout status remains in text/audio. The controller fits each companion's bounds into the existing studio framing.

Find the entity owning the imported take by inspecting `availableAnimations` on the root and descendants. Play the animation on that entity. Cache the loaded model and generated resources. `trim_start` and `trim_end` in `CompanionClips.json` are seconds relative to the take's start. All three idle clips span 0–2.4 seconds.

Apple's [AnimationView](https://developer.apple.com/documentation/realitykit/animationview) trims a source [animation definition](https://developer.apple.com/documentation/realitykit/animationresource/definition):

```swift
guard let take = animatedEntity.availableAnimations.first else {
    throw CocoaError(.fileReadCorruptFile)
}
let view = AnimationView(
    source: take.definition, name: "idle",
    trimStart: 0, trimEnd: 2.4
)
let idle = try AnimationResource.generate(with: view)
let playback = animatedEntity.playAnimation(
    idle.repeat(), transitionDuration: 0.15
)
// Stop on disappearance or when Reduce Motion is enabled.
playback.stop()
```

Decode the other trim times and loop flags from the JSON. Repeat only idle/rest. After a one-shot, transition back to the current idle/rest state. For Reduce Motion, show a neutral non-playing model.

## Verification and rebuild

`validation.json` verifies all 18 GLB animations move, their timing and finite transforms, matching endpoints, USD skeleton bindings/weights, full 30 Hz joint samples, color shader connections, material counts, absence of animated mesh caches, and the combined size budget. `usd-roundtrip-validation.json` records reimport of the actual exported USDZ skeletons and motion in Blender. Preview renders use the animated Blender sources.

Run `scripts/animate_companions.py` through Blender MCP's `execute_blender_code` using `runpy.run_path` and call `main()`. Then run `scripts/sample_companion_skeletons.py` through MCP. With the isolated tooling Python containing `usd-core`, run `scripts/finalize_companion_usdz.py`, `scripts/validate_companion_exports.py`, and `scripts/package_companion_ios.py` in order. Run `scripts/preview_companions.py` through MCP, then `scripts/package_companion_previews.py` with Pillow to refresh the review.

Local Blender Lab MCP 1.0.3 is installed from Downloads and enabled as `bl_ext.user_default.mcp`; its Python server is in `C:\Users\panda\.codex\mcp-servers\blender`, registered in Codex as `mcp_servers.blender`. A dedicated background Blender bridge uses `127.0.0.1:9876`; the artist's UI session is untouched. Start a bridge in a later session with:

```powershell
& 'C:\Program Files\Blender Foundation\Blender 5.2\blender.exe' --background --online-mode --command blender_mcp --host 127.0.0.1 --port 9876
```

RealityKit take offsets, transitions, Reduce Motion, small-screen materials and frame time/thermal behavior alongside the camera stream still require an iPhone test. Blender export and reimport checks do not prove native playback or device performance.
