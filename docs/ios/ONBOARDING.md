# Gym&I onboarding

The first launch moves the existing logo upward and opens the profile questionnaire. Reduce Motion opens the content directly. Completed or deferred onboarding goes to Today on later launches. Settings → Training profile reopens the flow.

## Flow

1. Optional weight, height, and sex. Metric and imperial inputs convert to kilograms and centimeters for storage; no values are prefilled. These measurements do not determine the training focus.
2. Eight questions: goal, training experience, daily activity, gym visits per week, time per session, main equipment, preferred training style, and motivation. Each answer requires an explicit Continue. Back preserves answers.
3. Match and review: Strength → Atlas; muscle growth → Flex; general fitness → Pip. The user can choose another focus or edit answers before confirming.
4. Confirmation saves the profile and selects the corresponding existing companion for the app. Today shows the saved training focus.

The stated goal has six points, training preference three, and motivation two. An explicit goal always wins. “Help me choose” delegates to preference and motivation. Routine answers are retained as context, without claiming that activity level, sex, or body size diagnoses a suitable training goal. The matching rule is deterministic and uses no provider tokens.

## Storage and boundaries

`OnboardingStore` saves a versioned draft and confirmed profile as JSON in the phone's UserDefaults. The draft includes progress, answers, optional measurements and units; it resumes after app termination. Confirmation stores normalized measurements, all answers, selected focus, and completion date. Set up later retains the draft without inventing a completed profile or mascot match. Canceling an edit leaves the confirmed profile intact.

No questionnaire data is sent to the Pi, Gemini, ElevenLabs, or Backboard. No permissions are requested during this flow. The profile does not generate a multi-day workout or alter the current rep-counting/voice contract; the app still runs the existing selected single set. A personalized workout planner can consume the stored routine in subsequent work.

## Checks

Swift tests cover all mascot mappings, explicit-goal precedence, undecided matching, measurement conversion, optional/invalid values, draft recovery, completion persistence, focus overrides, editing and deferral. UI tests cover the native intro/questionnaire, resume, real mascot match, confirmation, relaunch, editing, and largest Dynamic Type layouts.

Existing workout UI tests bypass first-run onboarding in DEBUG. Dedicated onboarding tests use their own preferences suite and `--gymni-onboarding-testing`; normal app launches show onboarding whenever no profile or deferral exists.

Verified on iPhone 17 Pro / iOS 26.4: 33 Swift tests and both onboarding UI tests passed. The app build includes the existing Watch and Live Activity targets. Actual Simulator captures: [measurements](../design/native/onboarding/measurements.png), [Atlas match](../design/native/onboarding/atlas-match.png), and [largest text goal](../design/native/onboarding/large-text-goal.png).
