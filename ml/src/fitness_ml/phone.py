"""Discover the phone on its hotspot; keep HTTP and reconnection off the camera thread."""
import json
import queue
import subprocess
import threading
import time
import urllib.error
import urllib.parse
import urllib.request

SERVICE = "_gymni._tcp.local."


def hotspot_gateway() -> str | None:
    try:
        routes = json.loads(subprocess.check_output(
            ["ip", "-j", "route", "show", "default", "dev", "wlan0"], timeout=2))
        return next((route["gateway"] for route in routes if "gateway" in route), None)
    except (OSError, subprocess.SubprocessError, ValueError):
        return None


def configuration_key(config: dict) -> tuple:
    return tuple(config.get(key) for key in ("workout_id", "session_id", "set_id", "exercise", "state", "revision"))


class PhoneLink:
    def __init__(self):
        from zeroconf import IPVersion, ServiceBrowser, Zeroconf
        self._stop = threading.Event()
        self._config = None
        self._confirmed_at = 0.0
        self._queue = queue.Queue(32)
        self._addresses = {}
        self._lock = threading.Lock()
        self._url = None
        self._delivered = False
        self._zeroconf = Zeroconf(ip_version=IPVersion.V4Only)
        self._browser = ServiceBrowser(self._zeroconf, SERVICE, self)
        self._thread = threading.Thread(target=self._run, daemon=True)
        self._thread.start()

    @property
    def configuration(self) -> dict | None:
        # Fail closed during a lost link; discard partial reps before reconnection.
        return self._config if time.monotonic() - self._confirmed_at < 2.5 else None

    def add_service(self, zeroconf, service_type, name):
        info = zeroconf.get_service_info(service_type, name, timeout=1000)
        if info:
            with self._lock:
                self._addresses[name] = [f"http://{address}:{info.port}" for address in info.parsed_addresses()]

    def update_service(self, zeroconf, service_type, name):
        self.add_service(zeroconf, service_type, name)

    def remove_service(self, zeroconf, service_type, name):
        with self._lock:
            self._addresses.pop(name, None)

    def send(self, observation, expected_key):
        config = self.configuration
        if not config or config["state"] != "active" or configuration_key(config) != expected_key:
            return
        try:
            self._queue.put_nowait((configuration_key(config), observation.to_dict()))
        except queue.Full:
            # Never hold the camera loop for a disconnected phone.
            pass

    def close(self):
        self._stop.set()
        self._thread.join(3)
        self._browser.cancel()
        self._zeroconf.close()

    def _candidates(self):
        with self._lock:
            addresses = [address for values in self._addresses.values() for address in values]
        gateway = hotspot_gateway()
        if gateway:
            addresses.append(f"http://{gateway}:8000")
        return list(dict.fromkeys(([f"http://{gateway}:8000"] if gateway else [])
                                  + ([self._url] if self._url else []) + addresses))

    def _refresh(self):
        for url in self._candidates():
            try:
                config = self._request(url + "/api/camera/configuration")
                if (config.get("service") != "gymni-phone" or config.get("schema_version") != 1
                        or config.get("exercise") not in ("curl", "squat", "deadlift")
                        or config.get("state") not in ("ready", "active", "paused", "complete")
                        or type(config.get("revision")) is not int
                        or not all(isinstance(config.get(key), str) and config[key]
                                   for key in ("workout_id", "session_id", "set_id"))):
                    continue
                if self._url != url:
                    print("Phone connected; workout controls follow Gym&I.", flush=True)
                self._url, self._config = url, config
                self._confirmed_at = time.monotonic()
                return
            except (OSError, ValueError, urllib.error.URLError):
                continue
        self._config = None
        self._url = None

    def _run(self):
        next_refresh = 0.0
        while not self._stop.is_set():
            if time.monotonic() >= next_refresh:
                self._refresh()
                next_refresh = time.monotonic() + 1
            try:
                key, record = self._queue.get(timeout=0.1)
            except queue.Empty:
                continue
            config = self.configuration
            if not config or key != configuration_key(config) or config["state"] != "active":
                continue
            url = (self._url + "/api/sessions/" + urllib.parse.quote(config["session_id"], safe="")
                   + "/observations?workout_id=" + urllib.parse.quote(config["workout_id"], safe="")
                   + "&revision=" + str(config["revision"]))
            try:
                ack = self._request(url, record)
                if ack.get("accepted") and not self._delivered:
                    print("Live camera/model observations are reaching the phone.", flush=True)
                    self._delivered = True
            except (OSError, ValueError, urllib.error.URLError):
                # Retry a completed rep only while the same control lease remains valid.
                if record.get("completed_rep") and self.configuration:
                    try:
                        self._queue.put_nowait((key, record))
                    except queue.Full:
                        pass
                next_refresh = 0

    @staticmethod
    def _request(url, record=None):
        data = json.dumps(record).encode() if record is not None else None
        request = urllib.request.Request(url, data, {"Content-Type": "application/json", "X-Gymni-Camera": "tripod"})
        with urllib.request.urlopen(request, timeout=1) as response:
            return json.load(response)
