"""Synthetic poses: a person facing the camera whose right/left elbow (and optionally knee) are set to
exact angles, so the expected features are known without any video."""
import math

import numpy as np
import pytest

from fitness_ml.pose import INDEX, Pose


def make_pose(elbow_deg: float = 170, knee_deg: float = 175, visibility: float = 0.95,
              width: int = 640, height: int = 480) -> Pose:
    """Pixel-space skeleton converted to normalized coords; world = same geometry in metres (z = 0)."""
    px = np.zeros((33, 2))
    for side, dx in (("left", 60), ("right", -60)):
        shoulder, hip = np.array([320 + dx, 140.0]), np.array([320 + dx * 0.6, 280.0])
        elbow = shoulder + [0, 70]                                         # upper arm straight down
        theta = math.radians(180 - elbow_deg)                              # forearm folds forward/up
        wrist = elbow + 60 * np.array([math.sin(theta) * np.sign(dx), math.cos(theta)])
        knee = hip + [0, 90]
        phi = math.radians(180 - knee_deg)
        ankle = knee + 90 * np.array([math.sin(phi) * np.sign(dx), math.cos(phi)])
        for name, p in (("shoulder", shoulder), ("elbow", elbow), ("wrist", wrist), ("hip", hip), ("knee", knee), ("ankle", ankle)):
            px[INDEX[f"{side}_{name}"]] = p
    image = np.zeros((33, 5))
    image[:, 0], image[:, 1] = px[:, 0] / width, px[:, 1] / height
    image[:, 3] = image[:, 4] = visibility
    world = np.c_[px / 400.0, np.zeros(33)]
    return Pose(image, world, width, height)


def curl_frames(reps: int, fps: float = 30, rep_s: float = 2.0, low: float = 165, high: float = 45, start_s: float = 0.5):
    """(t_ms, elbow_deg) for `reps` smooth curls, with still time before and after."""
    out, t, dt = [], 0.0, 1000 / fps
    while t < start_s * 1000:
        out.append((t, low)); t += dt
    for _ in range(reps):
        t0 = t
        while t - t0 < rep_s * 1000:
            u = (t - t0) / (rep_s * 1000)
            out.append((t, low - (low - high) * math.sin(math.pi * u))); t += dt
    for _ in range(int(fps / 2)):
        out.append((t, low)); t += dt
    return out


@pytest.fixture
def pose_factory():
    return make_pose
