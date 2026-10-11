import importlib.util
import threading
import urllib.error
import urllib.request
from http.server import HTTPServer
from pathlib import Path

import pytest

spec = importlib.util.spec_from_file_location("voice", Path(__file__).parents[1] / "api" / "voice.py")
voice = importlib.util.module_from_spec(spec)
spec.loader.exec_module(voice)


@pytest.fixture
def server(monkeypatch):
    spoken = []

    def fake_synthesize(text):
        if text == voice.PHRASES["ended"]:
            raise OSError("ElevenLabs down")
        spoken.append(text)
        return b"ID3fake-mp3"

    monkeypatch.setattr(voice, "synthesize", fake_synthesize)
    httpd = HTTPServer(("127.0.0.1", 0), voice.handler)
    threading.Thread(target=httpd.serve_forever, daemon=True).start()
    yield f"http://127.0.0.1:{httpd.server_port}/api/voice", spoken
    httpd.shutdown()


def test_approved_phrase_is_voiced_and_cached_on_the_cdn(server):
    url, spoken = server
    with urllib.request.urlopen(f"{url}?id=curl.partial_range") as response:
        assert response.headers["Content-Type"] == "audio/mpeg"
        assert "s-maxage=31536000" in response.headers["Cache-Control"]
        assert response.read() == b"ID3fake-mp3"
    assert spoken == ["Let the weight come all the way down."]


@pytest.mark.parametrize("query, status", [("id=say-anything", 404), ("", 404), ("id=ended", 502)])
def test_unknown_phrases_and_failures_are_never_cached(server, query, status):
    url, spoken = server
    with pytest.raises(urllib.error.HTTPError) as error:
        urllib.request.urlopen(f"{url}?{query}")
    assert error.value.code == status
    assert error.value.headers["Cache-Control"] == "no-store"
    assert spoken == []
