from types import SimpleNamespace

import pytest

from backend.audio import dynamic_cue as voice


def request(**overrides):
    return voice.CueRequest(**{
        "exercise": "curl", "issue_code": "curl.elbow_drift", "evidence": "approved action only",
        "recommended_action": "Keep your elbows pinned to your sides.", "confidence": 1,
        "tracking_status": "ready", "coach_approved": True, **overrides,
    })


def test_complete_gemini_json_is_voiced_with_configured_provider(monkeypatch):
    monkeypatch.setenv("GEMINI_API_KEY", "test-gemini-key")
    monkeypatch.setenv("GEMINI_MODEL_ID", "configured-gemini-model")
    monkeypatch.setenv("ELEVENLABS_API_KEY", "test-eleven-key")
    monkeypatch.setenv("ELEVENLABS_VOICE_ID", "configured-voice")
    monkeypatch.setenv("ELEVENLABS_MODEL_ID", "configured-voice-model")
    spoken = "Keep your elbows pinned close to your sides."
    calls = []

    def generate(**kwargs):
        assert kwargs["model"] == "configured-gemini-model"
        assert kwargs["config"].max_output_tokens >= 128  # 24 truncated real structured responses
        assert "approved action only" not in kwargs["contents"]
        return SimpleNamespace(text='{"spoken_text": "' + spoken + '"}')

    def convert(**kwargs):
        calls.append(kwargs)
        return iter([b"ID3", b"audio"])

    monkeypatch.setattr(voice.genai, "Client", lambda **kw: SimpleNamespace(models=SimpleNamespace(generate_content=generate)))
    monkeypatch.setattr(voice, "ElevenLabs", lambda **kw: SimpleNamespace(text_to_speech=SimpleNamespace(convert=convert)))
    text, audio = voice.generate_spoken_cue(request())
    assert (text, audio) == (spoken, b"ID3audio")
    assert calls == [{"text": spoken, "voice_id": "configured-voice", "model_id": "configured-voice-model", "output_format": "mp3_44100_128"}]


@pytest.mark.parametrize("overrides", [{"tracking_status": "lost"}, {"confidence": 0.7}, {"coach_approved": False}])
def test_untrusted_observations_never_request_voice(overrides, monkeypatch, tmp_path):
    def unexpected(*args, **kwargs):
        pytest.fail("Untrusted observation reached a provider")

    monkeypatch.setattr(voice.genai, "Client", unexpected)
    monkeypatch.setattr(voice, "ElevenLabs", unexpected)
    with pytest.raises(ValueError):
        voice.save_spoken_cue(request(**overrides), tmp_path / "cue.mp3")


def test_cached_voice_changes_with_voice_or_model(monkeypatch, tmp_path):
    calls = []
    monkeypatch.setattr(voice, "generate_voice_audio", lambda text: calls.append(text) or b"ID3audio")
    text = "Paused. Take the time you need."
    first_id = voice.cached_voice_id(text)
    output = tmp_path / f"{first_id}.mp3"
    assert voice.save_voice_clip(text, output) == text
    assert voice.save_voice_clip(text, output) == text
    assert calls == [text]
    monkeypatch.setenv("ELEVENLABS_VOICE_ID", "different-voice")
    assert voice.cached_voice_id(text) != first_id
    next_id = voice.cached_voice_id(text)
    monkeypatch.setenv("ELEVENLABS_MODEL_ID", "different-model")
    assert voice.cached_voice_id(text) != next_id


def test_default_form_correction_uses_no_gemini_and_reuses_voice(monkeypatch, tmp_path):
    monkeypatch.delenv("GYMAI_REPHRASE_CUES", raising=False)
    monkeypatch.setattr(voice.genai, "Client", lambda **kw: pytest.fail("Default correction must not use Gemini"))
    calls = []
    monkeypatch.setattr(voice, "generate_voice_audio", lambda text: calls.append(text) or b"ID3test")
    cue = request()
    output = tmp_path / f"{voice.cached_cue_id(cue)}.mp3"
    assert voice.save_spoken_cue(cue, output) == cue.recommended_action
    assert voice.save_spoken_cue(cue, output) == cue.recommended_action
    assert calls == [cue.recommended_action]
