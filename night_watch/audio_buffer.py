"""
Night Watch — Circular Audio Buffer (Section 3.6)

Keeps the last N seconds of raw audio in a fixed-size ring buffer.
When an event triggers, the pre-buffer is grabbed so the beginning
of the sound isn't cut off.
"""

import numpy as np


class CircularAudioBuffer:
    """
    Fixed-capacity ring buffer for raw float32 audio samples.

    Parameters
    ----------
    capacity : int
        Maximum number of samples to keep (e.g. 5 s × 16 000 = 80 000).
    """

    def __init__(self, capacity: int):
        self._buf = np.zeros(capacity, dtype=np.float32)
        self._capacity = capacity
        self._write_pos = 0
        self._total_written = 0

    @property
    def is_full(self) -> bool:
        return self._total_written >= self._capacity

    def write(self, chunk: np.ndarray) -> None:
        """Append a chunk of samples into the ring buffer."""
        n = len(chunk)
        if n >= self._capacity:
            # Chunk is bigger than the whole buffer — just keep the tail
            self._buf[:] = chunk[-self._capacity:]
            self._write_pos = 0
            self._total_written = self._capacity
            return

        end = self._write_pos + n
        if end <= self._capacity:
            self._buf[self._write_pos:end] = chunk
        else:
            # Wrap around
            first = self._capacity - self._write_pos
            self._buf[self._write_pos:] = chunk[:first]
            self._buf[:n - first] = chunk[first:]

        self._write_pos = end % self._capacity
        self._total_written += n

    def read_all(self) -> np.ndarray:
        """
        Return all buffered samples in chronological order.
        If the buffer hasn't filled yet, returns only the written portion.
        """
        if self._total_written < self._capacity:
            return self._buf[:self._write_pos].copy()

        # Buffer has wrapped — read from write_pos to end, then start to write_pos
        return np.concatenate([
            self._buf[self._write_pos:],
            self._buf[:self._write_pos],
        ])

    def clear(self) -> None:
        self._buf[:] = 0
        self._write_pos = 0
        self._total_written = 0
