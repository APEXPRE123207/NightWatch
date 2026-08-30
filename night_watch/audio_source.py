"""
Night Watch — Audio Source Abstraction

Provides a swappable interface for audio capture:
  - DesktopAudioSource  (sounddevice)  — Phase 1-4, desktop testing
  - AndroidAudioSource  (pyjnius)      — Phase 5+, on-device

The main loop calls start(), read_chunk() in a loop, then stop().
read_chunk() blocks until one hop's worth of samples is available.
"""

import queue
import numpy as np


class AudioSource:
    """Abstract base class for audio capture backends."""

    def start(self) -> None:
        raise NotImplementedError

    def read_chunk(self, timeout: float = 5.0) -> np.ndarray:
        """
        Return the next chunk of audio samples.

        Returns
        -------
        np.ndarray, shape (chunk_size,), dtype float32
            One hop's worth of mono audio.
        """
        raise NotImplementedError

    def stop(self) -> None:
        raise NotImplementedError

    def __enter__(self):
        self.start()
        return self

    def __exit__(self, *exc):
        self.stop()


class DesktopAudioSource(AudioSource):
    """
    Desktop audio capture using the ``sounddevice`` library.

    Each call to read_chunk() returns exactly ``chunk_size`` samples
    (= one hop, typically 0.5 s at 16 kHz = 8 000 samples).
    """

    def __init__(self, sample_rate: int = 16000, chunk_size: int = 8000):
        self.sample_rate = sample_rate
        self.chunk_size = chunk_size
        self._queue: queue.Queue[np.ndarray] = queue.Queue()
        self._stream = None

    # ── sounddevice callback (runs on a separate thread) ────────────────────

    def _callback(self, indata, frames, time_info, status):
        if status:
            print(f"[AudioSource] {status}")
        # indata is (frames, channels); take channel 0 and copy
        self._queue.put(indata[:, 0].copy())

    # ── Lifecycle ───────────────────────────────────────────────────────────

    def start(self) -> None:
        import sounddevice as sd

        self._stream = sd.InputStream(
            samplerate=self.sample_rate,
            channels=1,
            blocksize=self.chunk_size,
            dtype="float32",
            callback=self._callback,
        )
        self._stream.start()

    def read_chunk(self, timeout: float = 5.0) -> np.ndarray:
        return self._queue.get(timeout=timeout)

    def stop(self) -> None:
        if self._stream is not None:
            self._stream.stop()
            self._stream.close()
            self._stream = None
