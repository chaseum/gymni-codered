"""GRU inputs for one window, shared by training and live inference so the two cannot drift apart.

values (steps, F): frame features on an even time grid. seen (steps, F): 1 where the nearest real frame actually
had that feature (joint tracked), 0 where it was interpolated. Inputs = normalised values, optionally followed by
the `seen` mask and the step-to-step change ("velocity"). Works on one window (steps, F) or a batch (N, steps, F).
"""
import numpy as np

from .features import FEATURE_NAMES, resample

F = len(FEATURE_NAMES)
_INDEX = {name: i for i, name in enumerate(FEATURE_NAMES)}


def resample_seen(matrix: np.ndarray, timestamps_ms: np.ndarray, steps: int) -> tuple[np.ndarray, np.ndarray]:
    values = resample(matrix, timestamps_ms, steps)
    grid = np.linspace(timestamps_ms[0], timestamps_ms[-1], steps)
    nearest = np.abs(timestamps_ms[None, :] - grid[:, None]).argmin(1)
    return values, (~np.isnan(matrix[nearest])).astype(np.float32)


def gru_inputs(values: np.ndarray, seen: np.ndarray, mean: np.ndarray, std: np.ndarray,
               mask: bool, velocity: bool) -> np.ndarray:
    x = (values - mean) / std
    if mask:
        x = np.where(seen > 0, x, 0.0)  # with the mask channel, an unseen joint is "0 + not seen", not a guess
    parts = [x]
    if mask:
        parts.append(seen)
    if velocity:
        parts.append(np.diff(x, axis=-2, prepend=x[..., :1, :]))
    return np.concatenate(parts, axis=-1).astype(np.float32)


def input_size(mask: bool, velocity: bool) -> int:
    return F * (1 + mask + velocity)


# --- training-time augmentation (never used at inference) -------------------------------------------------------
ROTATE_DEG, JOINT_DROPOUT, NOISE_STD = 10.0, 0.1, 0.02
MIRROR = np.array([_INDEX[n.replace("left_", "\0").replace("right_", "left_").replace("\0", "right_")]
                   for n in FEATURE_NAMES])
FLIP_X = np.array([n.endswith("_x") for n in FEATURE_NAMES])
COORD_PAIRS = np.array([(_INDEX[n], _INDEX[n[:-2] + "_y"]) for n in FEATURE_NAMES if n.endswith("_x")])
LIMB_WORDS = {"arm": ("elbow", "wrist", "upper_arm", "arm_vis"), "leg": ("knee", "ankle", "leg_vis")}
LIMB_GROUPS = [np.array([i for i, n in enumerate(FEATURE_NAMES) if n.startswith(f"{side}_") and
                         any(w in n for w in words)]) for side in ("left", "right") for words in LIMB_WORDS.values()]


def augment(values: np.ndarray, seen: np.ndarray, mean: np.ndarray, std: np.ndarray,
            rng: np.random.Generator) -> tuple[np.ndarray, np.ndarray]:
    """Batch (N, steps, F) -> a randomly varied copy: mirrored left/right (half the time), rotated up to
    ±ROTATE_DEG in the image plane (phone tilt), one limb hidden with p=JOINT_DROPOUT (occlusion), small noise.
    ponytail: rotation moves the body-centred joint positions only; trunk lean/heights are left as is (<=10° error)."""
    v, s = values.copy(), seen.copy()
    flip = rng.random(len(v)) < 0.5
    v[flip], s[flip] = v[flip][..., MIRROR], s[flip][..., MIRROR]
    v[np.ix_(flip, np.arange(v.shape[1]), np.flatnonzero(FLIP_X))] *= -1

    theta = np.radians(rng.uniform(-ROTATE_DEG, ROTATE_DEG, len(v)))[:, None, None]
    x, y = v[..., COORD_PAIRS[:, 0]], v[..., COORD_PAIRS[:, 1]]
    v[..., COORD_PAIRS[:, 0]] = x * np.cos(theta) - y * np.sin(theta)
    v[..., COORD_PAIRS[:, 1]] = x * np.sin(theta) + y * np.cos(theta)

    for group in LIMB_GROUPS:
        hidden = rng.random(len(v)) < JOINT_DROPOUT
        s[np.ix_(hidden, np.arange(s.shape[1]), group)] = 0.0
        v[np.ix_(hidden, np.arange(v.shape[1]), group)] = mean[group]  # normalises to 0 without the mask too

    v += rng.normal(0.0, NOISE_STD, v.shape) * std
    return v, s
