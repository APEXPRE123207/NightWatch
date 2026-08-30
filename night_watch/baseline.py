"""
Night Watch — Rolling Baseline (Section 3.3)

Maintains a fixed-window rolling mean and standard deviation for each
acoustic feature, computed ONLY from frames classified as "normal."
Anomalous frames are never fed into the baseline so they don't corrupt it.

The baseline needs a short warm-up period (MIN_FRAMES) before it can
produce meaningful z-scores.
"""

from collections import deque

import numpy as np


# Minimum number of frames before the baseline is considered "ready."
# ~10 seconds at 0.5 s hop = 20 frames.
MIN_FRAMES = 20


class RollingBaseline:
    """
    Fixed-window rolling statistics for a set of named features.

    Parameters
    ----------
    max_frames : int
        Maximum number of "normal" frames to keep (≈ 60 s / hop = 120).
    feature_names : list[str]
        The feature keys to track (e.g. ["rms", "spectral_flux", ...]).
    """

    def __init__(self, max_frames: int, feature_names: list[str],
                 min_stds: dict[str, float] | None = None):
        self.max_frames = max_frames
        self.feature_names = feature_names
        self._min_stds = min_stds or {}
        self._buffers: dict[str, deque] = {
            name: deque(maxlen=max_frames) for name in feature_names
        }

    # ── Public API ──────────────────────────────────────────────────────────

    @property
    def is_ready(self) -> bool:
        """True once enough frames have been collected for stable stats."""
        return len(self._buffers[self.feature_names[0]]) >= MIN_FRAMES

    @property
    def frame_count(self) -> int:
        return len(self._buffers[self.feature_names[0]])

    def update(self, features: dict[str, float]) -> None:
        """
        Add a **normal** frame's features to the baseline.
        Do NOT call this for anomalous frames.
        """
        for name in self.feature_names:
            self._buffers[name].append(features[name])

    def mean(self, name: str) -> float:
        buf = self._buffers[name]
        if len(buf) == 0:
            return 0.0
        return float(np.mean(buf))

    def std(self, name: str) -> float:
        buf = self._buffers[name]
        floor = self._min_stds.get(name, 1e-10)
        if len(buf) < 2:
            return max(1.0, floor)
        return float(max(np.std(buf), floor))

    def z_score(self, name: str, value: float) -> float:
        """Z-score of a single feature value against the current baseline."""
        return (value - self.mean(name)) / self.std(name)

    def z_scores(self, features: dict[str, float]) -> dict[str, float]:
        """Z-scores for all tracked features."""
        return {name: self.z_score(name, features[name]) for name in self.feature_names}

    def reset(self) -> None:
        for buf in self._buffers.values():
            buf.clear()
