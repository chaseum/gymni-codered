import socket
import urllib.request

import numpy as np
import cv2
import pytest
from contextlib import nullcontext
from types import SimpleNamespace

from fitness_ml.preview import PreviewServer


def test_preview_streams_published_frames_as_mjpeg():
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        port = s.getsockname()[1]
    server = PreviewServer(port, host="127.0.0.1")
    try:
        server.publish(np.zeros((720, 1280, 3), np.uint8))
        with urllib.request.urlopen(f"http://127.0.0.1:{port}/", timeout=5) as response:
            assert response.headers["Content-Type"].startswith("multipart/x-mixed-replace")
            assert response.readline() == b"--frame\r\n"
            headers = {}
            while (line := response.readline()) != b"\r\n":
                key, value = line.decode().split(":", 1)
                headers[key] = value.strip()
            jpeg = response.read(int(headers["Content-Length"]))
        image = cv2.imdecode(np.frombuffer(jpeg, dtype=np.uint8), cv2.IMREAD_COLOR)
        assert image.shape == (720, 1280, 3)
    finally:
        server.close()


@pytest.mark.parametrize("active", [True, False])
def test_preview_keeps_capture_detail_while_inference_uses_small_frames(monkeypatch, active):
    from fitness_ml import __main__ as cli
    from fitness_ml.config import Config
    from fitness_ml.sources import Frame

    analyzed, published = [], []
    def detect(image, timestamp):
        analyzed.append(image.shape)
        return None
    monkeypatch.setattr(cli, "_pose_model", lambda *args: None)
    monkeypatch.setattr(cli, "PoseEstimator", lambda _: nullcontext(SimpleNamespace(detect=detect)))
    args = cli._parser().parse_args(["run", "--source", "live", "--exercise", "curl", "--no-models",
                                    "--no-window", "--analysis-width", "480"])
    runner = cli.Runner(args, Config())
    runner.preview = SimpleNamespace(publish=lambda image: published.append(image.shape), close=lambda: None)
    runner.phone = SimpleNamespace(configuration={"session_id": "phone", "workout_id": "w1", "exercise": "curl",
                                                  "set_id": "s1", "state": "active" if active else "paused", "revision": 1},
                                   send=lambda *args: None, close=lambda: None)
    source = SimpleNamespace(source="live", frames=lambda: iter([Frame(np.zeros((720, 1280, 3), np.uint8), 0, 0)]))
    try:
        assert runner._play(source) == "ended"
        assert published == [(720, 1280, 3)]
        assert analyzed == ([(270, 480, 3)] if active else [])
    finally:
        runner._close()
