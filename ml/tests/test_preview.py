import socket
import urllib.request

import numpy as np

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
            chunk = response.read(200)
        assert b"--frame" in chunk and b"\xff\xd8" in chunk  # boundary + JPEG start, what the phone scans for
    finally:
        server.close()
