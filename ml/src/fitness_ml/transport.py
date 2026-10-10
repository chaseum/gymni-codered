"""Where observations go: a JSONL file and/or the backend. Debug logs are written separately (see __main__)."""
import json
import queue
import threading
import urllib.error
import urllib.request

from .types import Observation

QUEUE_LIMIT = 256
REP_RETRIES = 3


class JsonlWriter:
    def __init__(self, path):
        self._file = open(path, "a", encoding="utf-8")

    def write(self, record: dict) -> None:
        self._file.write(json.dumps(record, separators=(",", ":")) + "\n")
        self._file.flush()

    def close(self) -> None:
        self._file.close()


class BackendPoster:
    """POSTs observations from a background thread so HTTP never stalls the camera loop.
    Plain frames are dropped when the queue is full; frames carrying a completed rep wait and are
    retried with the same observation_id (the backend dedupes)."""

    def __init__(self, base_url: str, session_id: str, token: str | None = None):
        self._url = f"{base_url.rstrip('/')}/api/sessions/{session_id}/observations"
        self._headers = {"Content-Type": "application/json", **({"Authorization": f"Bearer {token}"} if token else {})}
        self._queue: queue.Queue = queue.Queue(QUEUE_LIMIT)
        self.dropped = 0
        self.last_error: str | None = None
        self._thread = threading.Thread(target=self._run, daemon=True)
        self._thread.start()

    def send(self, obs: Observation) -> None:
        try:
            self._queue.put(obs.to_dict(), block=obs.completed_rep is not None, timeout=2)
        except queue.Full:
            self.dropped += 1

    def close(self, timeout: float = 3.0) -> None:
        self._queue.put(None)
        self._thread.join(timeout)

    def _run(self) -> None:
        while (record := self._queue.get()) is not None:
            attempts = REP_RETRIES if record["completed_rep"] else 1
            for _ in range(attempts):
                if self._post(record):
                    break

    def _post(self, record: dict) -> bool:
        request = urllib.request.Request(self._url, json.dumps(record).encode(), self._headers, method="POST")
        try:
            with urllib.request.urlopen(request, timeout=2) as response:
                return response.status == 200
        except (urllib.error.URLError, TimeoutError) as e:
            self.last_error = str(e)
            return False
