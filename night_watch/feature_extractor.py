"""
Night Watch — Feature Extraction (Section 3.2 of the spec)

Extracts four acoustic features per frame using only numpy:
  1. RMS energy          — overall loudness
  2. Spectral centroid   — frequency "center of mass"
  3. Spectral flux       — L2 distance between consecutive normalised spectra
                           (the single most important feature)
  4. Zero-crossing rate  — tonal-vs-noisy/percussive indicator
"""

import numpy as np


class FeatureExtractor:
    """Stateful extractor that tracks the previous spectrum for flux."""

    def __init__(self, sample_rate: int):
        self.sample_rate = sample_rate
        self._prev_norm_spectrum: np.ndarray | None = None

    def reset(self) -> None:
        """Clear state (e.g. between sessions)."""
        self._prev_norm_spectrum = None

    # ── Public API ──────────────────────────────────────────────────────────

    def extract(self, frame: np.ndarray) -> dict:
        """
        Extract all features from a single audio frame.

        Parameters
        ----------
        frame : np.ndarray, shape (frame_size,), dtype float32
            One analysis frame of mono audio samples.

        Returns
        -------
        dict with keys: rms, spectral_centroid, spectral_flux, zcr
        """
        # Magnitude spectrum (real FFT)
        spectrum = np.abs(np.fft.rfft(frame))
        freqs = np.fft.rfftfreq(len(frame), d=1.0 / self.sample_rate)

        rms = self._rms(frame)
        centroid = self._spectral_centroid(spectrum, freqs)
        flux = self._spectral_flux(spectrum)
        zcr = self._zcr(frame)

        return {
            "rms": float(rms),
            "spectral_centroid": float(centroid),
            "spectral_flux": float(flux),
            "zcr": float(zcr),
        }

    # ── Individual feature methods ──────────────────────────────────────────

    @staticmethod
    def _rms(frame: np.ndarray) -> float:
        """Root mean square energy of the frame."""
        return float(np.sqrt(np.mean(frame ** 2)))

    @staticmethod
    def _spectral_centroid(spectrum: np.ndarray, freqs: np.ndarray) -> float:
        """
        Weighted mean of frequencies, weighted by magnitude.
        Returns 0 if the spectrum is silent.
        """
        total = np.sum(spectrum)
        if total < 1e-10:
            return 0.0
        return float(np.sum(freqs * spectrum) / total)

    def _spectral_flux(self, spectrum: np.ndarray) -> float:
        """
        L2 distance between this frame's normalised magnitude spectrum and
        the previous frame's.  A droning fan has near-zero flux; speech,
        movement, and impacts spike it.
        """
        norm = np.linalg.norm(spectrum)
        if norm < 1e-10:
            norm_spectrum = np.zeros_like(spectrum)
        else:
            norm_spectrum = spectrum / norm

        if self._prev_norm_spectrum is not None:
            flux = float(np.linalg.norm(norm_spectrum - self._prev_norm_spectrum))
        else:
            flux = 0.0

        self._prev_norm_spectrum = norm_spectrum.copy()
        return flux

    @staticmethod
    def _zcr(frame: np.ndarray) -> float:
        """
        Zero-crossing rate: fraction of consecutive sample pairs that cross
        zero.  Useful for distinguishing tonal hums from noisier/percussive
        sounds.
        """
        signs = np.sign(frame)
        # Count sign changes, normalise to [0, 1]
        crossings = np.sum(np.abs(np.diff(signs)) > 0)
        return float(crossings / max(len(frame) - 1, 1))
