"""MJPEG feed of the annotated camera frames, so the phone can show what the laptop camera sees."""
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import cv2

PREVIEW_WIDTH = 640  # phone-sized; keeps each JPEG small over Wi-Fi


class PreviewServer:
    """Serves the newest frame at any path as multipart/x-mixed-replace. Slow clients skip frames, never queue them."""

    def __init__(self, port: int, host: str = "0.0.0.0"):
        self._jpeg: bytes | None = None
        self._changed = threading.Condition()
        self._httpd = ThreadingHTTPServer((host, port), self._handler())
        self._httpd.daemon_threads = True
        threading.Thread(target=self._httpd.serve_forever, daemon=True).start()

    def publish(self, bgr) -> None:
        # ponytail: encodes every frame even with no viewer; skip when nobody is connected if CPU gets tight (Pi).
        height, width = bgr.shape[:2]
        if width > PREVIEW_WIDTH:
            bgr = cv2.resize(bgr, (PREVIEW_WIDTH, round(height * PREVIEW_WIDTH / width)))
        ok, buffer = cv2.imencode(".jpg", bgr, [cv2.IMWRITE_JPEG_QUALITY, 70])
        if ok:
            with self._changed:
                self._jpeg = buffer.tobytes()
                self._changed.notify_all()

    def next_frame(self, previous: bytes | None) -> bytes | None:
        """The next frame after `previous`; after 5 s without one, the current frame again (keeps the link alive)."""
        with self._changed:
            self._changed.wait_for(lambda: self._jpeg is not None and self._jpeg is not previous, timeout=5)
            return self._jpeg

    def close(self) -> None:
        self._httpd.shutdown()
        self._httpd.server_close()

    def _handler(self):
        server = self

        class Handler(BaseHTTPRequestHandler):
            def do_GET(self):
                self.send_response(200)
                self.send_header("Content-Type", "multipart/x-mixed-replace; boundary=frame")
                self.send_header("Cache-Control", "no-store")
                self.end_headers()
                jpeg = None
                try:
                    while True:
                        jpeg = server.next_frame(jpeg)
                        if jpeg is None:
                            continue
                        self.wfile.write(b"--frame\r\nContent-Type: image/jpeg\r\nContent-Length: %d\r\n\r\n" % len(jpeg))
                        self.wfile.write(jpeg + b"\r\n")
                except (BrokenPipeError, ConnectionResetError):
                    pass  # phone left the camera view

            def log_message(self, *args):
                pass

        return Handler
