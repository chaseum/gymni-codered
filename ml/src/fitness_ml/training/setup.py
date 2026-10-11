"""`fitness-train setup`: everything training needs on a fresh machine, in one re-runnable command.

Downloads (each verified against the hash its host publishes; finished steps are skipped on re-run):
  - Multi-View Fitness "Dataset Exercise Quality-wise.zip" (3.1 GB, CC BY 4.0, Mendeley) -> unzipped, zip deleted
  - MyDeadlift Extracted_keypoints.csv (1.4 MB, CC BY 4.0, Mendeley)
  - weggry/deadlift-classifier original videos (550 files, ~76 MB, GitHub; NO licence: non-commercial project
    use only, credited, never redistributed; mirrored "_flipped" copies are skipped)
  - MediaPipe pose_landmarker_lite.task
then builds the manifest, extracts landmarks on all cores, and makes the 70/15/15 person-wise split (seed 13).
"""
import hashlib
import json
import os
import shutil
import urllib.parse
import urllib.request
import zipfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from ..config import Config
from ..pose import download_model, model_path
from .dataset import make_split
from .extract import extract
from .manifest import multiview, read, summary, weggry_deadlift, write

HEADERS = {"User-Agent": "Mozilla/5.0 (gymai-setup)"}  # Mendeley rejects Python's default user agent
MENDELEY = "https://data.mendeley.com/public-api/datasets/{id}/files?folder_id=root&version={version}"
WEGGRY_TREE = "https://api.github.com/repos/weggry/deadlift-classifier/git/trees/HEAD?recursive=1"
WEGGRY_RAW = "https://raw.githubusercontent.com/weggry/deadlift-classifier/HEAD/"


def setup(data: Path, workers: int) -> None:
    raw = data / "raw"
    models_dir = Config().models_dir
    if not model_path(models_dir, "lite").exists():
        print("pose model:", download_model(models_dir, "lite"))
    _multiview(raw / "multiview")
    _mendeley_file("w5prmmxyt9", 1, "Extracted_keypoints.csv", raw / "mydeadlift")
    _weggry(raw / "weggry_deadlift" / "Raw MP4 Videos")

    rows = multiview(raw / "multiview")[0] + weggry_deadlift(raw / "weggry_deadlift")[0]
    manifest = data / "manifest.csv"
    write(manifest, rows)
    print(summary(rows))
    extract(read(manifest), data / "cache", model_path(models_dir, "lite"), workers=workers)
    split = make_split(read(manifest), manifest, seed=13, test_frac=0.15, val_frac=0.15)
    (data / "splits.json").write_text(json.dumps(split, indent=2))
    print("split (people/videos):", {k: len(split[k]) for k in ("train", "val", "test")}, "-> ready to train")


def _multiview(dest: Path) -> None:
    if dest.exists() and sum(1 for _ in dest.rglob("*.mp4")) >= 1000:
        print("multiview: already present")
        return
    archive = _mendeley_file("kgbb3yn47p", 3, "Dataset Exercise Quality-wise.zip", dest)
    print("multiview: unzipping...")
    with zipfile.ZipFile(archive) as zf:
        zf.extractall(dest)
    archive.unlink()


def _mendeley_file(dataset_id: str, version: int, name: str, dest: Path) -> Path:
    listing = json.loads(_get(MENDELEY.format(id=dataset_id, version=version)))
    entry = next(f for f in listing if f["filename"] == name)
    target = dest / name
    expected = entry["content_details"]["sha256_hash"]
    if target.exists() and _sha256(target) == expected:
        print(f"{name}: already present")
        return target
    dest.mkdir(parents=True, exist_ok=True)
    print(f"{name}: downloading {entry['size'] / 1e6:.0f} MB...")
    _download(entry["content_details"]["download_url"], target)
    if _sha256(target) != expected:
        target.unlink()
        raise RuntimeError(f"{name}: SHA-256 mismatch, download deleted; re-run setup")
    return target


def _weggry(dest: Path) -> None:
    tree = json.loads(_get(WEGGRY_TREE))["tree"]
    files = [(f["path"], f["sha"]) for f in tree if f["path"].startswith("Raw MP4 Videos/") and f["type"] == "blob"
             and "_flipped" not in f["path"]]
    dest.mkdir(parents=True, exist_ok=True)

    def fetch(item):
        path, sha = item
        target = dest / Path(path).name
        if not (target.exists() and _git_blob_sha(target) == sha):
            _download(WEGGRY_RAW + urllib.parse.quote(path), target)
            if _git_blob_sha(target) != sha:
                target.unlink()
                raise RuntimeError(f"{target.name}: hash mismatch, deleted; re-run setup")

    with ThreadPoolExecutor(8) as pool:
        list(pool.map(fetch, files))
    print(f"weggry: {len(files)} videos verified (no licence: project use only, do not redistribute)")


def _get(url: str) -> bytes:
    with urllib.request.urlopen(urllib.request.Request(url, headers=HEADERS), timeout=60) as response:
        return response.read()


def _download(url: str, target: Path) -> None:
    part = target.with_suffix(target.suffix + ".part")
    with urllib.request.urlopen(urllib.request.Request(url, headers=HEADERS), timeout=120) as response, \
            open(part, "wb") as out:
        shutil.copyfileobj(response, out, 1 << 20)
    os.replace(part, target)


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _git_blob_sha(path: Path) -> str:
    data = path.read_bytes()
    return hashlib.sha1(b"blob %d\0" % len(data) + data).hexdigest()
