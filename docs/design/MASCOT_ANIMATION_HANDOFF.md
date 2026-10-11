# Gym&AI mascot modeling and animation handoff

Prepared October 10, 2026. Source snapshot: `1761c48e51cf01968fee4a9b8f0f476fab45d210` from [gymni-codered](https://github.com/chaseum/gymni-codered).

## Start here

Open this entire extracted folder in your editor, read this document, then open `project/` in Codex. The included `project/AGENTS.md` points back to this guide, and `project/.agents/skills/` contains the coding skills used by this project.

**Only Pip currently has a Blender model. Atlas and Flex are selected concept designs awaiting modeling.** There are no Atlas/Flex `.blend` files hidden elsewhere in this package, and no finished Blender animation clips for any character. The first task is to animate Pip; the next tasks are to build Atlas and Flex from the selected references.

This ZIP contains the mascot assets, an iOS source snapshot, shared protocol references, and local skill snapshots. It is not a complete backend/ML repository or an installer. Clone the linked repository for work that needs the backend. No MCP server is bundled or configured automatically.

## What the app does

Gym&AI is an iPhone-first workout companion that helps people start a workout, follow a plan, receive verbal form coaching and encouragement, count reps, and take breaks. The intended onboarding gathers goals and matches a companion to the user. Goal-based mascot matching is a design direction; the current iOS app displays Pip across its existing screens.

The interface is intentionally simple: Today, a workout with Reps/Camera views, Rest, and Recap. Camera view is landscape with controls and metric overlays. A mascot should communicate readiness, attention, encouragement, and recovery without obstructing reps, camera footage, captions, or workout controls.

The current app has a clearly labeled simulated workout and a laptop-backend connection path. Phone-only form inference, live Watch heart-rate delivery, full onboarding, and the complete personalized planner are not implemented in this iOS slice. HealthKit currently requests heart-rate read permission. Native iPhone text-to-speech drives Pip's coaching state; the newer repository audio assets do not imply an ElevenLabs player is already wired into this app.

## Character direction

| Character | Goal | Selected appearance | Actual asset status |
|---|---|---|---|
| Atlas | Get stronger | Fuzzy charcoal character with a sweeping turquoise band; sturdy, friendly proportions | Concept references only; model and animation still to build |
| Flex | Build muscle | Sculptural open ribbon; charcoal exterior, turquoise interior, matte finish, short feet | Concept references only; model and animation still to build |
| Pip | Feel fitter | Rounded curved charcoal body, glossy smooth finish, short limbs, turquoise orbit ring | Editable Blender source, USDZ, studio HDR, transparent PNG, runtime motion |

The strongest selected trio reference is `project/docs/design/gym-ai-mascots-v5-glossy-pip.png`. It retains fuzzy Atlas and ribbon Flex while giving Pip its smooth, water-polished finish. The latest Pip mesh and `PipPreview` supersede the thinner Pip proportions in that board.

Brand accent: **#0097B2**, sRGB `(0, 151, 178)`. Convert the base color to linear when setting Blender shader values; do not sample a highlighted raster pixel as the material color. Pip's current body base is sRGB `(35, 39, 45)` with roughness `0.27`; its accent roughness is `0.22`. Lighting changes the rendered colors.

Earlier `gym-ai-mascots-v1` through `v4` boards and their prompts are included as design history. Do not switch back to the rock Atlas, animal variants, or an older Pip. The octopus is retired. Keep the working display name Gym&AI and make the companions original to this project.

## Package map

| Path | Purpose |
|---|---|
| `HANDOFF.md` | This document, including a ready-to-use Codex prompt |
| `MANIFEST.json` | File sizes and SHA-256 hashes for checking the extracted package |
| `MODEL_STATUS.json` | Explicit record of which characters have models |
| `project/docs/design/models/pip/pip.blend` | Current editable rounded Pip, preview camera, and studio lights |
| `project/scripts/build_pip.py` | Procedural reconstruction, USDZ export, HDR generation, PNG rendering |
| `project/ios/GymAndAI/Mascot/Resources/Pip.usdz` | Current mobile model, approximately 438 KiB |
| `project/ios/GymAndAI/Mascot/Resources/PipStudio.hdr` | Generated studio reflection map |
| `project/ios/GymAndAI/Assets.xcassets/PipPreview.imageset/pip-preview.png` | Transparent 768 × 768 fallback and visual reference |
| `project/docs/design/gym-ai-mascots-*` | All mascot concept boards, design notes, and generation/edit prompts |
| `project/docs/design/gym-ai-logo-reference.png` | Brand reference supplied by Bryan |
| `project/docs/design/native/pip-rounded-*` | Actual simulator captures of the latest Pip revision |
| `project/ios/` | Xcode project, SwiftUI views, RealityKit integration, local package, and tests |
| `project/contracts/` | Shared event protocol and examples for understanding workout triggers |
| `project/.agents/skills/` | Local snapshots of code-tips-skill and swiftui-pro |
| `setup/` | Skill provenance and optional MCP configuration example |

## Opening and rebuilding Pip

The existing source was created and opened with **Blender 5.2.1 LTS**. Use that version or a compatible newer Blender; opening with an older version has not been tested. Blender is the only requirement for editing the model. Its bundled Python runs the build script; system Python does not provide `bpy`.

Open `project/docs/design/models/pip/pip.blend` in Blender. The scene contains the character plus `PreviewCamera` and studio lights. The model is approximately 19,268 triangles by the build script's estimate. There is no skeleton, skin weighting, fluid simulation, or fur in Pip.

**Save an animation copy before editing**, for example `pip-animated.blend`. The following reconstruction command deletes the scene in its Blender process and overwrites the generated `pip.blend`, USDZ, HDR, and PNG. It does not preserve artist edits or animation added only to the saved scene:

```bash
cd project
blender --background --python scripts/build_pip.py
```

If `blender` is not on PATH, use your Blender executable's full path. On this development Mac it is `/Applications/Blender.app/Contents/MacOS/Blender`. Do not assume that path exists on another computer.

## Preserve Pip's hierarchy and coordinate system

```text
PipRoot
├── Body
│   ├── BodyMesh, LeftEye, RightEye, Smile
│   ├── LeftArm → LeftArmMesh
│   └── RightArm → RightArmMesh
├── LeftFoot → mesh and leg
├── RightFoot → mesh and leg
└── Orbit → OrbitMesh
```

The app looks up **Body, Orbit, and RightArm** by name. Renaming or merging them breaks current runtime animation. Keep limbs and the ring separate; keep the eyes and mouth attached to the body. Additive rotation of the arm must retain its existing raised resting angle.

Blender source uses Z-up. USD export converts the root to Y-up, but child animation transforms still use their Blender-local axes under that converted root. The app's added `PipMotionRoot` bobs along world Y; the ring rotates around local Z. Preserve parent transforms and check orientation in RealityKit after export. Do not apply transforms blindly across the hierarchy.

The current exporter selects only the character hierarchy, exports materials, converts orientation, and omits cameras/lights. Its USD options are recorded in `build_pip.py`. The USDZ is a portable app model, not a substitute for the editable Blender source.

## What already animates

These movements are authored in `project/ios/GymAndAI/Mascot/PipMotion.swift`, not Blender Actions:

| State | Current motion | Current trigger |
|---|---|---|
| Idle | Gentle vertical bob and slow ring turn | Today and ordinary coaching display |
| Coaching | Small body nod, right-arm gesture, quicker ring | While native coach speech is active |
| Celebrate | Short bounce and arm lift; settles after 1.6 seconds | Tap Pip on Today, or completed-workout recap |
| Rest | Lower posture, slower bob, slower ring | Paused workout |

Speech activity comes from `CoachAudioPlayer.isSpeaking`, selected in `WorkoutFlowView`. Mute, cancellation, replacement cues, and backgrounding must stop the speaking animation. Reduce Motion uses a still neutral pose. Hidden or backgrounded views dismantle their RealityKit scene. Failed model loading displays the PNG.

## Animation work to do next

First polish Pip's idle motion and greeting. Add occasional blinks, a gentle breathing motion, and a friendly wave. Then refine coaching, celebration, and rest, including smooth transitions between poses. Greeting and blinking are **proposals**, not existing features. Avoid precise lip sync for this first pass.

Suggested authoring targets at 30 fps:

| Clip | Suggested duration | Intent |
|---|---|---|
| Idle | 3-second loop | Quiet, relaxed breathing and subtle sway |
| Greeting | 1.5 seconds, once | Look attentive and wave |
| Coaching | 2-second loop | Restrained nod/gesture while speaking |
| Celebrate | 1.6 seconds, once | Small bounce, both arms lift, energetic ring |
| Rest | 4-second loop | Slower breathing and relaxed posture |

Those durations are a starting brief, not the current runtime's exact periods. Keep loops seamless, ease transitions, preserve the face, and allow vertical/head/arm clearance in the app's small mascot viewport. Check the full ring rotation so it never masks the eyes or smile.

For the first app integration, keep the existing object-based runtime motion and use Blender animation as an editable timing/pose reference. Exporting Blender object keyframes does **not** establish that usable clips appear in RealityKit. If choosing baked animation, make a small export/playback test first and inspect `availableAnimations`. If bending, squash/stretch, or full character posing needs a rig, add a documented armature and validate its animation export before replacing the runtime driver. Do not run baked clips and the current transform driver on the same parts simultaneously.

Atlas needs a new model with a readable furry silhouette and mobile-friendly surface detail. Flex needs a new thick ribbon mesh with a visible turquoise inner surface and a deformation strategy for bending. Keep their selected character identities rather than treating Pip as a generic mesh to rename. The unseen sides must be designed; the references are single images, not complete turnarounds.

## Tools, skills, and MCP setup

Required for modeling: Blender and the reference assets. For iPhone integration: a Mac, Xcode compatible with this project, SwiftUI, and RealityKit. The tested toolchain is **Xcode 26.4**, with the existing **iOS 17** deployment target. Preserve that target and availability guards; do not raise it merely because a skill mentions newer systems. No Meshy/Tripo account or paid image-to-3D service is needed.

The ZIP includes local copies of **code-tips-skill** for clean code and **swiftui-pro** for SwiftUI work, with their references. Open `project/` as the Codex working folder to use the project-local skills. Codex supports repository `.agents/skills` and user `~/.agents/skills` locations. [Official skill documentation](https://learn.chatgpt.com/docs/build-skills).

To install the latest upstream SwiftUI skill globally instead of using the bundled snapshot:

```bash
npx skills add https://github.com/twostraws/swiftui-agent-skill --skill swiftui-pro --agent codex --global --yes
```

Sources: [code-tips-skill](https://github.com/chaseum/code-tips-skill), [SwiftUI Pro](https://github.com/twostraws/SwiftUI-Agent-Skill). See `setup/SKILL_SOURCES.md` for provenance and license information. Skills provide instructions; they do not install Blender or control its UI.

**Blender MCP is optional**, useful when Codex should inspect and operate a running Blender session. This project has used Blender Python directly; MCP has not been installed or tested here. The current community project's name/package is `mcp-for-blender`. [Maintainer setup instructions](https://github.com/ahujasid/mcp-for-blender).

With `uv` and the Codex CLI installed:

```bash
uvx mcp-for-blender install-addon
codex mcp add blender -- uvx mcp-for-blender
codex mcp list
```

Enable **Interface: MCP for Blender** in Blender Preferences → Add-ons, open Blender, and check its MCP panel/server. Restart Codex after configuration. If the GUI cannot find `uvx`, use its absolute executable path. The included `setup/blender-mcp.example.toml` is an example to merge into your own configuration, not a replacement for it. Keep the connection local and run one client/server connection at a time. [Official Codex MCP configuration](https://learn.chatgpt.com/docs/extend/mcp?surface=cli).

## App integration and validation

Open `project/ios/GymAndAI.xcodeproj`, choose scheme `GymAndAI`, and run on an available iPhone simulator. Select your own signing team for a physical device. The local `GymAndAIKit` package is included; backend access is unnecessary for the labeled demo.

Relevant files: `PipAssetLibrary.swift` loads/clones resources; `PipSceneController.swift` configures camera, lights, and updates; `PipRealityView.swift` is the iOS 17 non-AR bridge; `PipView.swift` handles fallback, accessibility, and visibility. Do not create an AR camera session for mascots.

Check idle, speech, mute/cancel, pause/rest, recap, tap celebration, navigation, background/foreground, and Reduce Motion. Inspect both the 160 × 140 point hero view and the 64 × 60 point coach thumbnail. Check face visibility, ring intersections, silhouette from several angles, shader appearance, frame clipping, and workout control access. Stop rendering offscreen. Measure performance on an actual iPhone before calling it production-ready.

The latest rounded Pip build passed six simulator UI tests on iPhone 17 Pro / iOS 26.4. Ten package tests passed during the prior integration. No physical-iPhone mascot validation has been completed. Read `project/docs/design/swiftui-first-slice-validation.md` for the recorded checks.

## What to send back

For each finished character, return the editable `.blend` with named objects/rig and Actions, exported `.usdz`, any textures needed by the export, a transparent PNG, a short motion preview, and a Markdown change note listing clip names, timing, loop behavior, hierarchy changes, materials, polygon count, and export settings. Pack external dependencies into the Blender source or include them in the delivery.

Do not replace production resources until playback and appearance are verified. For Pip, preserve the original and return `pip-animated.blend` initially. For new characters, use `atlas.blend` / `Atlas.usdz` and `flex.blend` / `Flex.usdz`, with documented root/node names. Work on a separate branch if using the full Git repository. The asset handoff does not authorize unrelated backend changes or publication.

## Paste this into your friend's Codex

> Read HANDOFF.md from the extracted Gym&AI mascot package and the project/AGENTS.md instructions. Use the bundled code-tips-skill when generating code and swiftui-pro when changing SwiftUI. Inspect the current rounded Pip Blender source and the selected glossy V5 trio reference. Start by saving a separate pip-animated.blend and polishing Pip's idle breathing, blinks, and greeting wave, followed by coaching, celebration, and rest. Preserve the existing named parts, #0097B2 accent, iOS 17 target, Reduce Motion, speech stop behavior, and offscreen teardown. Current app animation is procedural RealityKit; do not assume Blender clips will export/play correctly without a proof test. Atlas and Flex have references but no meshes yet: build fuzzy Atlas and ribbon Flex afterward. Use Blender Python or the optional local Blender MCP. Return editable source, mobile USDZ, dependencies, transparent preview, motion preview, and a Markdown integration note. Inspect the result in Blender and the native app and report any checks that cannot be run.
