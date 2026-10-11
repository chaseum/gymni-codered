# Supported exercise catalog

The shared machine-readable catalog is [`../contracts/exercise_catalog.json`](../contracts/exercise_catalog.json). Treat its exercise IDs, model class labels, and variation IDs as the source of truth for planner and client integrations.

## What the recommendations mean

These presets are for healthy adults age 18 and older. They are starting points for the demo planner, not individualized medical advice or a complete training program. The current ACSM position stand is an overview of reviews of healthy adults. It emphasizes progressive resistance training, at least two sets per exercise as a reasonable baseline, 2-3 sets for strength, at least two weekly strength sessions, and roughly 10 weekly sets per muscle group as a hypertrophy target. It also reports that failure training, equipment choice, tempo, and periodization do not consistently change outcomes for the average healthy adult.

The user-selectable profiles are **Fitness**, **Muscle Growth**, and **Strength Building**. The catalog uses 8-12 repetitions for its Fitness and Muscle Growth defaults as a practical, familiar range, rather than claiming this range is uniquely optimal. Its Strength Building profile uses 6-8 repetitions as a practical planning range and marks load as user-confirmed. ACSM highlights loads around 80% of one-repetition maximum for strength, but Gym&AI does not test or infer one-repetition maximum and must not turn that research finding into an automatic load recommendation.

Rest values are adjustable defaults for session planning, not exercise-specific clinical rules. The ACSM evidence review did not establish one optimal interval for all trainees. The catalog gives more rest to compound and strength-focused sets, and users can extend it until they feel ready to repeat controlled repetitions. It targets roughly 2-3 repetitions in reserve as a practical effort cue; the evidence does not make this an exact or individually measured target.

The CDC recommends adults perform muscle-strengthening activity on at least two days each week, working all major muscle groups. This catalog is only the model-supported set of movements listed in the team brief. It does not contain a dedicated calf movement or a complete core program, so it must not be presented as a fully balanced weekly routine on its own.

## Catalog and model boundaries

- `recognition_class` is the classifier label. `variation_id` is the movement variation selected for a plan; the two deadlift variations share the `deadlift` recognition class.
- `rep_unit` clarifies whether the prescription is per side. Alternating curls and side bends use repetitions per side. The backend and UI should preserve that meaning when they display targets and counts.
- Camera guidance reflects the current analyzer requirements in `ml/README.md` and `ml/src/fitness_ml/config.py`; it does not certify movement safety.
- Romanian deadlift appears only under `recognition_rejection_examples`, mapped to `other`. It must not be planned as conventional or sumo deadlift.
- Loads are user-confirmed. Do not infer safe weight, medical readiness, injury risk, or form safety from video, heart rate, a rep count, or a trained classifier.
- Honor movement restrictions supplied by the user. Stop when pain or dizziness is reported and encourage appropriate assistance, consistent with the team brief.

## Evidence and exercise references

- [ACSM 2026 position stand (overview of 137 systematic reviews)](https://pmc.ncbi.nlm.nih.gov/articles/PMC12965823/)
- [ACSM 2026 key takeaways infographic](https://www.acsm.org/wp-content/uploads/2026/03/Resistance-Training-Position-Stand-infographic.pdf)
- [CDC adult physical activity recommendations](https://www.cdc.gov/physical-activity-basics/guidelines/adults.html)
- [ACE exercise library: overhead triceps extension](https://www.acefitness.org/resources/everyone/exercise-library/74/triceps-extension/)
- [ACE exercise library: bent-over row](https://www.acefitness.org/resources/everyone/exercise-library/12/bent-over-row/)
