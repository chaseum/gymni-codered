import asyncio
import json
from pathlib import Path

from fastapi.testclient import TestClient
from backend.gymai_backend import cloud_app as cloud
from backend.gymai_backend import gemini


ROOT = Path(__file__).resolve().parents[2]


def test_shared_policy_and_form_catalog_match_phone():
    phone = ROOT / 'ios/GymAndAIKit/Sources/GymAndAIKit'
    assert json.loads((phone / 'Resources/coaching_policy.json').read_text()) == cloud.POLICY
    source = (phone / 'HubSession.swift').read_text()
    for code, text in cloud.CUES.items():
        assert f'"{code}": "{text}"' in source


def test_voice_whitelist_cache_and_no_workout_authority(monkeypatch, tmp_path):
    monkeypatch.delenv('GYMAI_TOKEN', raising=False)
    monkeypatch.setenv('ELEVENLABS_API_KEY', 'test-key')
    monkeypatch.setenv('ELEVENLABS_VOICE_ID', 'test-voice')
    monkeypatch.setattr(cloud, 'AUDIO_DIR', tmp_path)
    calls = []
    def save(text, path):
        if not path.exists():
            calls.append(text)
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b'test-mp3')
        return text
    monkeypatch.setattr(cloud, 'save_voice_clip', save)
    client = TestClient(cloud.app)
    config = client.get('/api/coach/configuration').json()
    assert config['voice_provider'] == 'elevenlabs' and config['voice_available']
    assert config['workout_llm_tokens'] == 0
    body = {'kind': 'count', 'rep_count': 4, 'target_reps': 8}
    for _ in range(2):
        response = client.post('/api/coach/voice', json=body)
        assert response.status_code == 200
        assert response.headers['x-voice-provider'] == 'elevenlabs'
        assert response.content == b'test-mp3'
    assert calls == ['4 reps. Halfway there.']
    assert client.post('/api/coach/voice', json={**body, 'text': 'arbitrary advice'}).status_code == 422
    assert client.post('/api/coach/voice', json={'kind': 'count', 'rep_count': 3, 'target_reps': 8}).status_code == 422
    assert client.post('/api/coach/voice', json={'kind': 'form', 'code': 'curl.unknown'}).status_code == 422
    assert client.post('/api/sessions', json={'session_id': 'phone'}).status_code == 404


def test_cloud_auth_configuration_and_failure_do_not_leak_provider_keys(monkeypatch):
    monkeypatch.setenv('GYMAI_TOKEN', 'app-access')
    monkeypatch.delenv('ELEVENLABS_API_KEY', raising=False)
    client = TestClient(cloud.app)
    assert client.get('/api/coach/configuration').status_code == 401
    headers = {'Authorization': 'Bearer app-access'}
    response = client.get('/api/coach/configuration', headers=headers)
    assert not response.json()['voice_available']
    assert 'app-access' not in response.text
    assert client.post('/api/coach/voice', headers=headers, json={'kind': 'prompt', 'code': 'begin'}).status_code == 503


def test_configuration_revision_changes_with_voice_and_model(monkeypatch):
    monkeypatch.delenv('GYMAI_TOKEN', raising=False)
    client = TestClient(cloud.app)
    before = client.get('/api/coach/configuration').json()['voice_revision']
    monkeypatch.setenv('ELEVENLABS_MODEL_ID', 'changed-model')
    after = client.get('/api/coach/configuration').json()['voice_revision']
    assert before != after


def test_chat_carries_client_history_and_direct_backboard_id(monkeypatch):
    monkeypatch.delenv('GYMAI_TOKEN', raising=False)
    seen = []
    async def send(message, **kwargs):
        seen.append((message, kwargs))
        return {'reply': 'What equipment do you have?'}
    monkeypatch.setattr(cloud, 'send_coach_message', send)
    result = TestClient(cloud.app).post('/api/coach/messages', json={
        'message': 'Three days a week', 'assistant_id': 'phone-saved-assistant',
        'history': [{'role': 'user', 'text': 'I want to gain strength'}]
    })
    assert result.status_code == 200
    assert seen == [('Three days a week', {'history': [{'role': 'user', 'parts': [{'text': 'I want to gain strength'}]}], 'assistant_id': 'phone-saved-assistant'})]


def test_stateless_gemini_does_not_store_server_conversation(monkeypatch):
    monkeypatch.setenv('GEMINI_API_KEY', 'test-key')
    posted = []
    class Client:
        def __init__(self, **kwargs): pass
        async def __aenter__(self): return self
        async def __aexit__(self, *args): pass
        async def post(self, *args, **kwargs):
            posted.append(kwargs['json'])
            class Result:
                def raise_for_status(self): pass
                def json(self): return {'candidates': [{'content': {'parts': [{'text': 'Okay'}]}}]}
            return Result()
    monkeypatch.setattr(gemini.httpx, 'AsyncClient', Client)
    before = dict(gemini.CONVERSATIONS)
    result = asyncio.run(gemini.send_coach_message('Hello', history=[]))
    assert result['reply'] == 'Okay'
    assert gemini.CONVERSATIONS == before
    assert posted[0]['contents'] == [{'role': 'user', 'parts': [{'text': 'Hello'}]}]
