# Gym&AI onboarding — visual concept v1

Status: visual mockup only. No SwiftUI onboarding, persistence, or planner integration is implemented by this deliverable. Example selections and plan details are illustrative.

## Direction

Four question panels followed by a review panel. Calm, friendly Octobuddy; existing Gym&AI dark/lime/cyan palette; system typography; opaque choice surfaces. One primary action per panel. Subtle glass treatment on controls, not stacked over choice surfaces.

## Panels

| Panel | Question | Choices / example selection |
|---|---|---|
| Goal | What would you like to work toward? | Get stronger; Build muscle; **Build a routine**; General fitness. Single choice. |
| Experience | How familiar are you with strength training? | **Just starting**; Getting back into it; Training regularly. Single choice. |
| Schedule | What fits your week? | 2 / **3** / 4 days per week; 15 / **30** / 45 minutes per workout. Two single-choice groups. |
| Equipment | What can you work out with? | Bodyweight; **Dumbbells**; Barbell and plates. Multiple choice. |
| Preview | Your starting plan | Review goal, experience, schedule, session length, equipment. Edit answers / Use this plan. |

Bodyweight means workouts that require no equipment and may be selected alongside equipment. This concept includes the proposed general-fitness and barbell choices; a later planner must only offer exercises it can actually support.

## Intended interactions

- Back preserves answers. Continue advances explicitly; selecting a choice never navigates automatically.
- Step 1–4 progress counts question panels only. The preview has no misleading fifth-step label.
- Skip for now leads to Today with an explicit unpersonalized starter experience; unanswered fields remain unknown rather than silently inventing user answers.
- If a schedule is incomplete, keep the missing choice visible for review; a proposed default must be labeled as suggested, not user-selected.
- Edit answers returns to the relevant panel with prior selections preserved. Use this plan confirms the reviewed profile and plan once planning is connected. Current raster preview does not generate or prescribe a real workout.
- Do not place Pi pairing or Health/microphone permissions in these question panels. Device setup follows separately and does not block viewing the plan.
- Coaching personality is deferred to an optional preference or later concept, keeping this first flow short.

## Native implementation targets

- Colors: background #080A0C; surface #1C1F23; text #F5F7F8; secondary #A5ABB3; lime #D7FC42; cyan #8DE4EB.
- SF Pro/system type with Dynamic Type, 32–36 pt question headings and 17 pt choice/button text at the default size. Allow vertical scrolling at large sizes; never shrink labels to fit.
- 24 pt side padding; 12–16 pt related-item gaps; 56 pt primary controls; all hit targets at least 44 pt. Controls respect safe areas.
- Selection includes a check/radio/checkbox indication and VoiceOver selected state, not just a lime border. Single-select and multi-select groups have different semantics.
- Same cyan round-headed Octobuddy throughout. Respect Reduce Motion and Reduce Transparency.

## Artifacts

- `gym-ai-onboarding-v1.png`: visual board, generated using the built-in image-generation tool.
- `gym-ai-onboarding-v1.prompt.txt`: exact generation prompt.
- `gym-ai-onboarding-v1.edit-prompt.txt`: exact targeted revision prompt, correcting the schedule step number and making equipment selection indicators square checkboxes.
- User-visible typography, geometry, and behavior in the PNG are conceptual. Native accessibility and functional navigation must be tested when implemented.

## Visual review

Inspected the complete board for copy, progress labels, visible actions, consistent mascot appearance, spacing, and agreement between selected answers and the plan preview. The final revision shows steps 1–4 correctly and distinguishes multi-select equipment checkboxes from goal/experience single-select choices. All five panels and prototype labels are present. The native schedule selectors must additionally expose their selected state to VoiceOver; the raster is not an accessibility test.
