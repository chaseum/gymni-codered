"""One zip with everything `fitness-ml run` needs on another machine: the models it would load here (newest
recognizer + form model per exercise), the pose model, this exact fitness_ml code as a wheel, and pinned
requirements. Trained models are scikit-learn pickles: they only load with the same scikit-learn version."""
import hashlib
import json
import subprocess
import sys
import tempfile
import time
import zipfile
from pathlib import Path

from ..artifacts import discover, test_score
from ..config import REPO
from ..pose import model_path
from .train import git, package_version

PINNED = ("mediapipe", "opencv-contrib-python", "numpy", "scikit-learn", "joblib")
README = """# Gym&I vision models: {stamp}

Code revision {revision}{dirty}. Built on Python {python}.

Needs a Raspberry Pi 4/5 (or any machine) with a **64-bit** OS and Python 3.11+. A Raspberry Pi Pico
(microcontroller) cannot run this. Install everything into a fresh venv:

    python3 -m venv ~/gymai && . ~/gymai/bin/activate
    pip install -r requirements.txt
    pip install --no-deps wheels/*.whl
    export GYMAI_MODELS_DIR=$PWD/models
    fitness-ml cameras
    fitness-ml run --source live --camera 0

`requirements.txt` pins exact versions, and they matter: `model.joblib` files are scikit-learn pickles that only load
with the same scikit-learn. Expect fewer frames per second than a laptop (MediaPipe runs on the Pi's CPU).
Headless (no display): add `--no-window --post http://<backend-host>:8000 --session <id>`.

## Models (held-out macro-F1 from `fitness-train evaluate`; "n/a" = not evaluated yet)

{models}

## Data credits
Multi-View Fitness (CC BY 4.0), MyDeadlift (CC BY 4.0), weggry/deadlift-classifier (doi:10.3390/ai6070148,
no licence published: non-commercial project use, credited, not redistributed). Videos are NOT in this zip.
"""


def export(models_dir: Path, out_dir: Path) -> Path:
    recognizer, forms = discover(models_dir)
    chosen = {"recognition": recognizer, **{f"form:{ex}": d for ex, d in sorted(forms.items())}}
    chosen = {k: d for k, d in chosen.items() if d}
    pose = model_path(models_dir, "lite")
    if not pose.exists():
        raise FileNotFoundError(f"{pose} missing: run `fitness-ml download-model`")

    stamp = time.strftime("%Y%m%d-%H%M%S")
    out_dir.mkdir(parents=True, exist_ok=True)
    out = out_dir / f"gymai-models-{stamp}.zip"
    with tempfile.TemporaryDirectory() as tmp, zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as zf:
        hashes = {}

        def add(name: str, data: bytes):  # hash what we write: reading entries back fails on Windows paths
            zf.writestr(name, data)
            hashes[name] = hashlib.sha256(data).hexdigest()

        wheel = _build_wheel(Path(tmp))
        add(f"wheels/{wheel.name}", wheel.read_bytes())
        add(f"models/{pose.name}", pose.read_bytes())
        for directory in chosen.values():
            for f in sorted(directory.iterdir()):
                add(f"models/{directory.name}/{f.name}", f.read_bytes())
        needs_torch = any(json.loads((d / "metadata.json").read_text())["model"] == "gru" for d in chosen.values())
        pins = PINNED + (("torch",) if needs_torch else ())
        # "+cu130"-style local builds exist only on the training box; the target installs its own build of that version
        add("requirements.txt", "".join(f"{p}=={package_version(p).split('+')[0]}\n" for p in pins).encode())
        manifest = {"exported_at": stamp, "code_revision": git("rev-parse", "HEAD"),
                    "code_dirty": bool(git("status", "--porcelain", "--", "ml/src")),
                    "python": sys.version.split()[0], "packages": {p: package_version(p) for p in pins},
                    "models": {k: {"dir": d.name, "test_macro_f1": test_score(d)} for k, d in chosen.items()},
                    "sha256": hashes}
        zf.writestr("MANIFEST.json", json.dumps(manifest, indent=2))
        zf.writestr("README.md", README.format(
            stamp=stamp, revision=(manifest["code_revision"] or "unknown")[:7],
            dirty=" (with uncommitted changes)" if manifest["code_dirty"] else "", python=manifest["python"],
            models="\n".join(f"- `{k}`: {d.name} (test F1 {test_score(d) if test_score(d) is not None else 'n/a'})"
                             for k, d in chosen.items())))
    return out


def _build_wheel(tmp: Path) -> Path:
    subprocess.run([sys.executable, "-m", "pip", "wheel", "--no-deps", "-q", "-w", str(tmp), str(REPO / "ml")],
                   check=True)
    return next(tmp.glob("fitness_ml-*.whl"))
