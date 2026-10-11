from scripts.select_simulator import select_device


def device(udid, state="Shutdown", name="iPhone 17 Pro"):
    return {"udid": udid, "name": name, "isAvailable": True, "state": state}


def test_duplicate_names_prefer_the_booted_device():
    devices = {"com.apple.CoreSimulator.SimRuntime.iOS-26-4": [device("new")],
               "com.apple.CoreSimulator.SimRuntime.iOS-26-2": [device("visible", "Booted")]}
    assert select_device(devices, "iPhone 17 Pro")["udid"] == "visible"


def test_cold_start_chooses_latest_runtime_and_exact_udid_is_supported():
    devices = {"com.apple.CoreSimulator.SimRuntime.iOS-18-4": [device("older")],
               "com.apple.CoreSimulator.SimRuntime.iOS-26-4": [device("newer")]}
    assert select_device(devices)["udid"] == "newer"
    assert select_device(devices, "older")["udid"] == "older"
    assert select_device(devices, "missing") is None
