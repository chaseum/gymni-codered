# Home v2 — design and brand reference

## Design read

Native SwiftUI Home for a user who wants to start a workout quickly, and for hackathon judges trying the demo. Mode: **Operate / redesign preserving the brand and product contracts**. The main task is selecting/reviewing the next exercise, then starting. Apple Fitness-inspired structure, gray ground, slate content, teal primary action, and the real 3D Pip establish the visual language.

- Visual variance **4/10**: the exercise and mascot share one dominant panel; navigation stays familiar.
- Motion **2/10**: preserve Pip's existing idle/celebration behavior and native control feedback; no new entrance choreography.
- Density **4/10**: one exercise, two useful details, one source/setup row, and one primary action.
- Asset dependence **7/10**: actual logo and 3D Pip remain the recognizable brand assets.
- Brand fidelity **9/10**: official colors, display name, mascot, tabs, and workflow are preserved.

The first version gave the greeting the largest visual weight. V2 gives that weight to the selected exercise and keeps encouragement short. The primary start control remains pinned above the tabs. Nothing claims that personalized plans, voice commands, or the exercise analysis model are complete.

## Assets and tokens

| Asset | Repository path |
| --- | --- |
| Official logo | `ios/GymAndAI/Assets.xcassets/GymAILogo.imageset/logo.png` |
| Pip model | `ios/GymAndAI/Mascot/Resources/Pip.usdz` |
| Studio lighting | `ios/GymAndAI/Mascot/Resources/PipStudio.hdr` |
| Pip fallback | `ios/GymAndAI/Assets.xcassets/PipPreview.imageset` |
| Existing visual baseline | `docs/design/home/home-slate-v1.png` |
| Implemented v2 preview | `docs/design/home/home-v2.png` |
| Largest text size preview | `docs/design/home/home-v2-large-text.png` |

Colors come from `GymTheme`: background `#283239`, panels `#1B272D`, main text `#F2F6F5`, secondary text `#B8C5CB`, action `#0097B2`, accent text `#6ECADB`, and text on the action `#0E1418`. The logo keeps its supplied white backing.

Typography is the native system family with rounded bold large titles, semantic headline/detail styles, and Dynamic Type. The base page padding is 24 points; related groups use 6–12 points, panel sections use 20 points, and distinct page sections use 28 points. Panel radius remains 24 points. One border establishes the panel's depth; no decorative glow or nested card system.

Liquid Glass is reserved for native navigation and the primary button on iOS 26. Content panels are opaque for legibility. Older iOS versions and Reduce Transparency use the existing button fallbacks. The iOS 17 deployment target stays unchanged.

## Preserved interactions and states

- **View plan** opens the existing plan/exercise picker.
- **Workout setup** and the toolbar gear open the existing Settings sheet.
- **Start workout** invokes the existing session start, shows **Starting…**, and disables repeat taps while starting.
- Pip retains its celebration button identifier, spoken label/value, Reduce Motion behavior, static fallback, and offscreen rendering lifecycle.
- Today / Progress, workout navigation, camera/Watch permission behavior, and app errors retain their existing contracts.
- Large accessibility text uses stacked panel contents; the page scrolls while Start workout remains reachable.

## Applied skills

Impeccable informed hierarchy, material restraint, truthful states, and a bounded inspection pass. UI/UX Designer ([Madina Gbotoe](https://madinagbotoe.com/)) informed touch targets, progressive disclosure, and the reachability of the primary action. Web Design Engineer informed asset fidelity, the design read, and protection of existing navigation/data contracts; its web patterns were adapted to native SwiftUI. SwiftUI Pro and Code Tips informed small view components and accessible, maintained native APIs.

## Verification

Simulator build passed on iPhone 17 Pro / iOS 26.4. Five existing mascot/phone-mode tests passed in the first run. The two workout journey tests passed in the final run after correcting the setup row's position relative to the pinned Start control. The journey now asserts the setup row ends above Start, opens both plan and settings, starts a workout, and completes the camera/pause/recap flow. Largest accessibility text keeps Start reachable and uses vertical, scrollable content.

Standard and largest-text Home captures were inspected together, then confirmed after the layout correction. All seven selected test cases passed across these runs. The screenshots are actual app captures with illustrative Demo data. No physical camera or Watch readings are shown.
