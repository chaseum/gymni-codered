# Gym&AI Home redesign — v2

The native SwiftUI Home screen uses a lighter slate-grey backdrop, the official logo, and teal actions. It keeps the existing Today / Progress navigation, plan picker, settings, and workout flow.

## Palette

| Role | Colour |
| --- | --- |
| Main background | `#283239` |
| Official blue charcoal / text on teal buttons | `#0E1418` |
| Official deep slate cards | `#1B272D` |
| Official soft white text | `#F2F6F5` |
| Official teal primary action / selection | `#0097B2` |
| Lighter teal for readable small labels | `#6ECADB` |
| Secondary text | `#B8C5CB` |

The main background is a flat slate grey derived from the supplied palette. The requested lighter grey takes priority over using near-black `#0E1418` as the entire background. The brighter teal text tint supports small labels; charcoal text on the official teal action has a 5.36:1 contrast ratio.

## Composition

- Original logo in the navigation bar, with its supplied white background preserved. Settings remains a separate action.
- Today and the local date provide orientation without invented user details or activity statistics.
- The selected exercise leads the screen. Its larger rounded title sits beside the existing animated 3D Pip inside one slate workout panel. Tapping Pip keeps its short celebration.
- Equipment and the set target occupy distinct columns. No fabricated duration, streak, or personalized prescription. Demo targets explicitly say **8 demo reps**; phone targets say **Manual set**.
- View plan remains a full-width, clearly labeled action within the workout panel.
- The smaller greeting follows the workout: **Ready when you are.** and the existing encouragement.
- Start workout stays above the tab bar while the content scrolls. Its loading state disables repeated starts.
- A compact explanation identifies the camera source. The entire row now opens **Workout setup**, giving quick access to camera, audio, and Watch settings. Phone mode explicitly states that rep and form analysis are pending. Demo mode is labeled illustrative.

## Typography and accessibility

Use native Dynamic Type: large title for Today and the exercise, title 3 for the greeting, headline for actions and detail values, and subheadline for supporting text. No new font dependency. Accessibility text sizes switch the exercise/Pip and equipment rows into vertical layouts; content scrolls while the start action remains available.

Controls have a minimum 44-point hit area. Pip retains its VoiceOver label, reduced-motion pose, static fallback, and offscreen rendering behavior. Native Liquid Glass buttons remain available on iOS 26, with existing older-OS and Reduce Transparency fallbacks. The iOS 17 deployment target is unchanged.

## Scope

This update changes the Home composition and adds a shortcut to the existing Settings sheet. Shared colors, primary navigation, camera capture, Watch connectivity, audio behavior, and model integration retain their existing behavior.

`home-slate-v1.png` and `home-large-text.png` document the earlier design. New captures and asset details are listed in [brand-spec.md](brand-spec.md).

## Previous validation

- Simulator build passed with the existing iOS 17 target.
- Seven existing UI tests passed: four mascot checks, two workout journeys (including accessibility text sizes), and the iPhone camera-mode flow.
- Standard and largest accessibility-text Home captures were inspected. The start control stays visible; longer content scrolls.
- The bundled logo's SHA-256 matches the supplied file exactly.

These checks validate layout and existing app interactions in Simulator, not the pending physical Watch installation issue or trained model behavior.

## V2 validation

The v2 build and seven selected UI test cases passed across the initial and final runs. The first inspection identified a setup row below the visible scroll area; the final composition makes Pip more compact and positions setup before the greeting. A navigation check confirms setup sits above Start and opens Settings. Standard and largest accessibility-text captures were confirmed after this correction; see [brand-spec.md](brand-spec.md) for current previews and details.
