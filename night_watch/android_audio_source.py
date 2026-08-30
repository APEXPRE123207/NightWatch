"""
Night Watch — Android Audio Source (Phase 5)

Uses pyjnius to call Android's native AudioRecord API for continuous
microphone capture that works reliably in a foreground service with the
screen off.

This module is only imported on Android.  On desktop, the
DesktopAudioSource from audio_source.py is used instead.
"""

import numpy as np
import queue
import threading


def _get_android_audio_classes():
    """Lazy-import pyjnius classes to avoid import errors on desktop."""
    from jnius import autoclass
    AudioRecord = autoclass("android.media.AudioRecord")
    AudioFormat = autoclass("android.media.AudioFormat")
    MediaRecorder = autoclass("android.media.MediaRecorder")
    return AudioRecord, AudioFormat, MediaRecorder


class AndroidAudioSource:
    """
    Audio capture backend using Android's AudioRecord via pyjnius.

    Runs a background thread that reads PCM data from the mic and
    queues it as float32 numpy arrays, matching the DesktopAudioSource
    interface exactly.

    Parameters
    ----------
    sample_rate : int
        Sampling rate in Hz (default 16000).
    chunk_size : int
        Number of samples per chunk (= HOP_SIZE, default 8000).
    """

    def __init__(self, sample_rate: int = 16000, chunk_size: int = 8000):
        self.sample_rate = sample_rate
        self.chunk_size = chunk_size
        self._queue: queue.Queue[np.ndarray] = queue.Queue()
        self._recorder = None
        self._thread = None
        self._running = False

    def start(self) -> None:
        AudioRecord, AudioFormat, MediaRecorder = _get_android_audio_classes()

        # Audio source: MIC
        audio_source = MediaRecorder.AudioSource.MIC

        # Channel config: MONO
        channel_config = AudioFormat.CHANNEL_IN_MONO

        # Encoding: 16-bit PCM
        encoding = AudioFormat.ENCODING_PCM_16BIT

        # Calculate minimum buffer size (Android requires this)
        min_buf = AudioRecord.getMinBufferSize(
            self.sample_rate, channel_config, encoding
        )
        # Use at least 2× the chunk size in bytes (16-bit = 2 bytes/sample)
        buf_size = max(min_buf, self.chunk_size * 2 * 2)

        self._recorder = AudioRecord(
            audio_source,
            self.sample_rate,
            channel_config,
            encoding,
            buf_size,
        )

        self._recorder.startRecording()
        self._running = True

        # Start reader thread
        self._thread = threading.Thread(target=self._read_loop, daemon=True)
        self._thread.start()

    def _read_loop(self) -> None:
        """Continuously read from AudioRecord and queue float32 chunks."""
        from jnius import autoclass
        # Read into a Java short array, then convert to numpy
        num_shorts = self.chunk_size
        while self._running:
            try:
                # Allocate a Java short array
                short_buf = [0] * num_shorts
                # Read exactly chunk_size shorts (blocking)
                samples_read = self._recorder.read(short_buf, 0, num_shorts)

                if samples_read > 0:
                    # Convert Java shorts to numpy float32 in [-1, 1]
                    arr = np.array(short_buf[:samples_read], dtype=np.float32)
                    arr /= 32768.0
                    self._queue.put(arr)
            except Exception as e:
                print(f"[AndroidAudioSource] read error: {e}")
                break

    def read_chunk(self, timeout: float = 5.0) -> np.ndarray:
        """Return the next chunk of audio samples (matches DesktopAudioSource API)."""
        return self._queue.get(timeout=timeout)

    def stop(self) -> None:
        self._running = False
        if self._recorder is not None:
            try:
                self._recorder.stop()
                self._recorder.release()
            except Exception:
                pass
            self._recorder = None
        if self._thread is not None:
            self._thread.join(timeout=2.0)
            self._thread = None

    def __enter__(self):
        self.start()
        return self

    def __exit__(self, *exc):
        self.stop()
