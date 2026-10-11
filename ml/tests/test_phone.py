import json
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from types import SimpleNamespace

from fitness_ml.phone import PhoneLink, configuration_key, hotspot_gateway


def test_discovery_mode_waits_for_phone_exercise_without_requiring_auto_recognizer(monkeypatch):
    from fitness_ml.__main__ import Runner, _parser
    from fitness_ml.config import Config
    monkeypatch.setattr("fitness_ml.phone.PhoneLink", lambda: SimpleNamespace(close=lambda: None))
    args = _parser().parse_args(["run", "--source", "live", "--discover-phone", "--no-models", "--no-window"])
    runner = Runner(args, Config())
    try:
        assert runner.analyzer.exercise == "curl"
        assert runner.analyzer.recognizer is None
        assert not runner.selector.auto
    finally:
        runner._close()


def test_hotspot_gateway_comes_from_wifi_route_not_a_fixed_ip(monkeypatch):
    seen = []
    def routes(command, **kwargs):
        seen.append(command)
        return b'[{"gateway":"172.20.10.1"}]'
    monkeypatch.setattr("fitness_ml.phone.subprocess.check_output", routes)
    assert hotspot_gateway() == "172.20.10.1"
    assert seen[0][-1] == "wlan0"


def test_discovered_phone_receives_reps_and_pause_discards_old_controls(monkeypatch):
    config = {"service": "gymni-phone", "schema_version": 1, "session_id": "phone", "workout_id": "w1",
              "exercise": "curl", "set_id": "set-001", "state": "active", "revision": 1}
    received = []
    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            self.send_response(200); self.end_headers()
            self.wfile.write(json.dumps(config).encode())
        def do_POST(self):
            received.append((self.path, json.loads(self.rfile.read(int(self.headers['Content-Length'])))))
            self.send_response(200); self.end_headers(); self.wfile.write(b'{"accepted":true}')
        def log_message(self, *args): pass
    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    class Zeroconf:
        def __init__(self, **kwargs): pass
        def get_service_info(self, *args, **kwargs):
            return SimpleNamespace(port=server.server_port, parsed_addresses=lambda: ["127.0.0.1"])
        def close(self): pass
    class Browser:
        def __init__(self, zeroconf, service, listener): listener.add_service(zeroconf, service, "Gym&I")
        def cancel(self): pass
    monkeypatch.setitem(__import__('sys').modules, "zeroconf", SimpleNamespace(
        Zeroconf=Zeroconf, ServiceBrowser=Browser, IPVersion=SimpleNamespace(V4Only=4)))
    monkeypatch.setattr("fitness_ml.phone.hotspot_gateway", lambda: None)
    link = PhoneLink()
    def wait_for(condition):
        deadline = time.monotonic() + 4
        while not condition() and time.monotonic() < deadline: time.sleep(0.01)
        assert condition()
    try:
        wait_for(lambda: link.configuration is not None)
        old_key = configuration_key(link.configuration)
        obs = SimpleNamespace(to_dict=lambda: {"completed_rep": {"rep_index": 1}})
        link.send(obs, old_key)
        wait_for(lambda: len(received) == 1)
        assert "workout_id=w1&revision=1" in received[0][0]
        config.update(state="paused", revision=2)
        wait_for(lambda: link.configuration["state"] == "paused")
        link.send(obs, old_key)
        assert link._queue.empty()
        config.update(state="active", revision=3)
        wait_for(lambda: link.configuration["revision"] == 3)
        link.send(obs, old_key)
        assert link._queue.empty()
        link.send(obs, configuration_key(link.configuration))
        wait_for(lambda: len(received) == 2)
        link._confirmed_at = time.monotonic() - 3
        assert link.configuration is None
    finally:
        link.close(); server.shutdown(); server.server_close()


def test_non_gymni_gateway_is_rejected():
    link = PhoneLink.__new__(PhoneLink)
    link._config = {"state": "active"}
    link._url = "http://wrong-service"
    link._candidates = lambda: ["http://wrong-service"]
    link._request = lambda url: {"schema_version": 1, "state": "active"}
    link._refresh()
    assert link._config is None and link._url is None
