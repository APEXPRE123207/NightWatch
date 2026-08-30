"""
Night Watch — Anomaly Detector (Sections 3.3–3.5)

Combines the FeatureExtractor output with the RollingBaseline to produce
a single anomaly score per frame.  The score is a weighted sum of per-
feature z-scores (absolute values), with spectral flux weighted 2× as
the primary discriminator.

The detector also computes ``spectral_centroid_delta`` (frame-to-frame
change in centroid) because the spec formula uses z(centroid_delta),
not z(centroid) directly.
"""

from night_watch.baseline import RollingBaseline
from night_watch.config import (
    ANOMALY_THRESHOLD,
    BASELINE_MAX_FRAMES,
    MIN_STD_RMS,
    MIN_STD_SPECTRAL_FLUX,
    MIN_STD_CENTROID_DELTA,
    MIN_STD_ZCR,
    W_RMS,
    W_SPECTRAL_FLUX,
    W_SPECTRAL_CENTROID,
    W_ZCR,
)


# Features tracked by the baseline
BASELINE_FEATURES = ["rms", "spectral_flux", "centroid_delta", "zcr"]


class AnomalyDetector:
    """
    Stateful anomaly detector.

    Call ``process(features)`` once per frame.  Returns an
    ``AnomalyResult`` with the score, per-feature z-scores, and a
    boolean ``is_anomaly`` flag.
    """

    def __init__(self):
        min_stds = {
            "rms": MIN_STD_RMS,
            "spectral_flux": MIN_STD_SPECTRAL_FLUX,
            "centroid_delta": MIN_STD_CENTROID_DELTA,
            "zcr": MIN_STD_ZCR,
        }
        self.baseline = RollingBaseline(BASELINE_MAX_FRAMES, BASELINE_FEATURES, min_stds)
        self._prev_centroid: float | None = None
        self._weights = {
            "rms": W_RMS,
            "spectral_flux": W_SPECTRAL_FLUX,
            "centroid_delta": W_SPECTRAL_CENTROID,
            "zcr": W_ZCR,
        }

    def reset(self) -> None:
        self.baseline.reset()
        self._prev_centroid = None

    def process(self, features: dict) -> "AnomalyResult":
        """
        Evaluate one frame's features against the rolling baseline.

        Parameters
        ----------
        features : dict
            Output of ``FeatureExtractor.extract()`` — must contain keys
            ``rms``, ``spectral_flux``, ``spectral_centroid``, ``zcr``.

        Returns
        -------
        AnomalyResult
        """
        # Compute centroid delta (abs change from previous frame)
        centroid = features["spectral_centroid"]
        if self._prev_centroid is not None:
            centroid_delta = abs(centroid - self._prev_centroid)
        else:
            centroid_delta = 0.0
        self._prev_centroid = centroid

        # Build the feature dict the baseline tracks
        baseline_feats = {
            "rms": features["rms"],
            "spectral_flux": features["spectral_flux"],
            "centroid_delta": centroid_delta,
            "zcr": features["zcr"],
        }

        # During warm-up, everything is "normal" — just feed the baseline
        if not self.baseline.is_ready:
            self.baseline.update(baseline_feats)
            return AnomalyResult(
                score=0.0,
                z_scores={name: 0.0 for name in BASELINE_FEATURES},
                is_anomaly=False,
                warming_up=True,
                baseline_frames=self.baseline.frame_count,
            )

        # Compute z-scores and weighted anomaly score.
        # Use max(0, z) — only UPWARD deviations are anomalous.
        # A frame that is quieter / more stable than baseline is not an anomaly.
        z = self.baseline.z_scores(baseline_feats)
        score = sum(
            self._weights[name] * max(0.0, z[name]) for name in BASELINE_FEATURES
        )

        is_anomaly = score > ANOMALY_THRESHOLD

        # Only update the baseline with normal frames
        if not is_anomaly:
            self.baseline.update(baseline_feats)

        return AnomalyResult(
            score=score,
            z_scores=z,
            is_anomaly=is_anomaly,
            warming_up=False,
            baseline_frames=self.baseline.frame_count,
        )


class AnomalyResult:
    """Container for one frame's detection result."""

    __slots__ = ("score", "z_scores", "is_anomaly", "warming_up", "baseline_frames")

    def __init__(
        self,
        score: float,
        z_scores: dict[str, float],
        is_anomaly: bool,
        warming_up: bool,
        baseline_frames: int,
    ):
        self.score = score
        self.z_scores = z_scores
        self.is_anomaly = is_anomaly
        self.warming_up = warming_up
        self.baseline_frames = baseline_frames
