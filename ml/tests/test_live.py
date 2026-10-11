from fitness_ml.analyzer import Analyzer, FrameResult
from fitness_ml.live import OVERRIDE_HOLD_MS, SWITCH_HOLD_MS, ExerciseSelector, rep_verdict
from fitness_ml.types import CompletedRep, Issue, Observation


class FakeRecognizer:
    def __init__(self):
        self.label, self.confidence = "curl", 0.9

    def update(self, t, features):
        return self.label, self.confidence

    def reset(self):
        pass


def selector():
    analyzer = Analyzer("curl", "s", "live", recognizer=FakeRecognizer())
    return analyzer, ExerciseSelector(analyzer, {}, auto=True)


def feed(sel, label, conf, start, end, step=100, rep_at=()):
    sel.analyzer.recognizer.label, sel.analyzer.recognizer.confidence = label, conf
    return [e for t in range(start, end, step) if (e := sel.on_frame(t, t in rep_at))]


def test_short_blip_does_not_switch():
    analyzer, sel = selector()
    assert feed(sel, "push_up", 0.9, 0, SWITCH_HOLD_MS - 200) == []
    assert analyzer.exercise == "curl"


def test_steady_confident_recognition_between_sets_switches():
    analyzer, sel = selector()
    events = feed(sel, "squat", 0.9, 0, SWITCH_HOLD_MS + 500)
    assert analyzer.exercise == "squat" and events and events[0].startswith("now counting: squat")


def test_no_switch_mid_set_or_at_low_confidence():
    analyzer, sel = selector()
    assert feed(sel, "squat", 0.9, 0, OVERRIDE_HOLD_MS - 500, rep_at={0, 2000}) == []  # reps still coming
    assert feed(sel, "row", 0.6, 10_000, 15_000) == []                           # never confident enough
    assert analyzer.exercise == "curl"


def test_manual_choice_keeps_counts_per_exercise():
    analyzer, sel = selector()
    analyzer.rep_counts["curl"] = 4
    sel.choose("squat")
    sel.choose("curl")
    assert analyzer.rep_counts == {"curl": 4, "squat": 0} and analyzer.local_rep_count == 4


def obs(**kw):
    base = dict(observation_id="o", session_id="s", source="live", source_timestamp_ms=0, exercise="curl",
                tracking_status="ready", phase="lowered", inference_provenance="trained_model",
                completed_rep=CompletedRep(1, 1500))
    return Observation(**{**base, **kw})


def test_verdict_wording():
    bad = FrameResult(obs(measurements={"form_model_p_bad": 0.72}), {}, "left", "front", 3)
    good = FrameResult(obs(measurements={"form_model_p_bad": 0.2}), {}, "left", "front", 4)
    fault = FrameResult(obs(issues=[Issue("deadlift.rounded_back", {"probability": 0.81})]), {}, "left", "side", 5)
    calib = FrameResult(obs(), {}, "left", "side", 1, events=["form calibration 1/3 - keep these reps clean"])
    assert rep_verdict(bad, None)[0] == ("rep 3: form looks BAD (72%)", "bad")
    assert rep_verdict(good, None)[0] == ("rep 4: form looks good (bad 20%)", "good")
    assert rep_verdict(fault, None)[0] == ("rep 5: rounded back 81%", "bad")
    assert rep_verdict(calib, None)[0] == ("rep 1: calibration 1/3 - keep these reps clean", "pending")


def test_switches_even_while_the_old_counter_keeps_misreading_the_new_exercise():
    """Live bug: curls -> push-ups. The curl counter kept 'counting curls' from push-up elbow bends, so the
    'no rep in the last 5 s' guard never cleared and the UI stayed on curl. Reps counted after the recognizer
    started saying push-up belong to push-ups."""
    analyzer, sel = selector()
    analyzer.rep_counts["curl"] = 10
    reps = set(range(0, 8000, 1500))  # the curl counter keeps firing every 1.5 s
    events = []
    for t in range(0, 8000, 100):
        if t in reps:
            analyzer.rep_counts[analyzer.exercise] += 1
        events += feed(sel, "push_up", 0.95, t, t + 1, rep_at=reps)
    assert analyzer.exercise == "push_up"
    assert events and "moved" in events[0]
    assert analyzer.rep_counts["curl"] == 10 and analyzer.rep_counts["push_up"] >= 2
